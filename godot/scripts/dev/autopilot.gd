extends Node
## Development harness driven by command-line user args (after "--"):
##   --phase=menu|night|morning|afternoon  --day=N   start straight into a phase
##   --shots=DIR --every=SEC --count=N            save screenshots periodically, then quit
##   --shotfrom=SEC                                start the screenshots at that game time
##   --cam=x,y,z,tx,ty,tz                          fixed camera (overrides the rig)
##   --catcam=ANGLE[,dist,h]                       camera around the cat's head (0 = in front of its nose)
##   --catpos=x,y,z  --yaw=Y                        place the cat
##   --carry[=ID]                                  the cat holds toy|chave|foto|coleira|doll|relic:KIND
##   --threat=id --stage=S                          force a threat into a stage
##   --hour=H                                      jump the night clock
##   --lights                                      turn every room light on
##   --hatch                                       open the attic hatch
##   --fear=F                                      set Clara's fear
##   --bedpose=P[@sec],...                         hold a pose in bed (switching at those seconds)
##   --meet=id                                     at t=2 put the cat one nav hop from that ghost
##   --huntlog                                     print stages, sight, hunts and lives twice a second
##   --claraat=x,y,z,yaw --clarato=node,...       walk Clara along nav nodes (wait2, gest:x, clip:x, spot:x, kneel)
##   --follow=side|34|front|back[,dist]            camera follows Clara
##   --devctl[=PORT]                               live controller on 127.0.0.1:PORT (7777): see devctl.gd,
##                                                 client tools/dev/devctl.py
##   --clarahold=book|book_open                    Ivone's diary in Clara's hands (closed / open)
##   --holdtune=FILE.json [--views=front,34,side]  one run, many tries: FILE is a list of {kind: {joint:
##                                                 [x,y,z]}} (arms over HumanRig.HOLD_ARMS; "_grip": {name: n}
##                                                 for HumanRig.grip_tune); each is shot from
##                                                 every view (--tunedir=DIR: DIR/tN_view.png, --dist=M;
##                                                 --tunefocus: views front,reader,side,under,pages,eyes around the held thing)
##   --carrytune=all|ID,... --tunedir=DIR          the cat holds each carryable in turn, shot close around its
##                                                 head (--carryfile=FILE.json grips over Carry.GRIPS)
##   --seatlog                                  once a second: Clara's / Davi's pelvis height and place
##   --hiplog                                      every frame: Clara's hip / head height, speed, yaw
##   --runaway                                     the cat runs straight away from the nearest hunter
##   --catgo=YAW                                   the cat walks that way (0 = +z) until the flag is dropped (devctl unarg)
##   --steplog                                     print Clara's / Davi's steps; in the afternoon the cat also
##                                                 plays it (eats, brings the key, lies down with Clara)
##   --e2e=1                                       end to end: the afternoon of day 1 (eat, key, lie down), then
##                                                 night 1 (Ivone's things to the circle) until dawn; logs each
##                                                 stage, "E2E FAIL ..." and exit code 1 on a stall
##   --lang=en|pt_BR                               play in that language (dev only, not saved)
##   --timescale=K                                 run the game K times faster (e2e defaults to 2)
##   --nohud                                       trailer capture: no HUD, prompts or interact outlines##   --campath=FILE.json [--camfrom=SEC]           trailer camera move from game time SEC (default 0):
##                                                 {"rel": "cat|clara|davi|", "keys": [{t, pos, look, fov,
##                                                 roll (deg), hand (handheld 0..1), ease: inout|linear|in|out}]}
##                                                 pos/look are world points, or offsets from "rel" (per key too)
##   --camsecs=S                                   quit S seconds into the camera move (tools/dev/capture.py)
##   --scene=NAME                                  a staged trailer moment (trailer.gd: lap, bowl, bed, sofa)

var _catgo := false   # --catgo pressed move_forward
var g: Game
var args := {}
var t := 0.0
var shot_t := 0.0
var shots := 0
var started := false
var _met := false
var _log_t := 0.0
var _e2e_stage := ""
var _e2e_t := 0.0          # seconds in the current stage
var _aft_seen := {}        # afternoon autoplay: when each condition was first seen (acts a moment later)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if args.has("lang"):
		TranslationServer.set_locale(str(args["lang"]))

func _process(dt: float) -> void:
	if g == null or g.mode == "boot":
		return
	if not started:
		started = true
		_start()
		if args.has("devctl"):
			var dc: Node = load("res://scripts/dev/devctl.gd").new()
			dc.name = "DevCtl"
			dc.ap = self
			dc.g = g
			add_child(dc)
			dc.start(int(args["devctl"]) if str(args["devctl"]).is_valid_int() and args["devctl"] != "1" else 7777)
		if args.has("scene"):
			var tr: Node = load("res://scripts/dev/trailer.gd").new()
			tr.name = "Trailer"
			tr.ap = self
			tr.g = g
			tr.scene = str(args["scene"])
			add_child(tr)
	t += dt
	_apply_overrides()
	if args.has("e2e"):
		_e2e(dt)
	elif args.has("steplog") and g.phase == "afternoon":
		_aft_play()
	if args.has("shots") and t >= float(args.get("shotfrom", "0")):
		shot_t += dt
		var every := float(args.get("every", "2"))
		if shot_t >= every:
			shot_t = 0.0
			var img := get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(args["shots"])
			var nm: String = args.get("name", "shot")
			img.save_png(str(args["shots"]).path_join("%s_%02d.png" % [nm, shots]))
			print("FPS %d SHOT %d t=%.1f mode=%s phase=%s hour=%.2f fear=%.0f cam=%s dist=%.2f cat=%s yaw=%.2f" % [Engine.get_frames_per_second(), shots, t, g.mode, g.phase, g.hour, g.clara.fear, g.cam.global_position, g.rig.cur_dist, g.cat.global_position, g.rig.yaw])
			if g.phase == "night":
				print("  NIGHT decay=%d pressure=%.2f sleep=%.0f focus=%.0f hound=%s speed=%.2f" % [g.director.decay.items.size(), g.director.decay.pressure(), g.cat.sleep, g.cat.focus, Hound.S.keys()[g.director.hound.state], g.threat_speed])
			shots += 1
			if shots >= int(args.get("count", "3")):
				get_tree().quit()


## --shadowtest=1|2|3: 1 look at it -> it flees to a nook; 2 stare at the nook -> peek, red, charge, a
## life; 3 look, light the room it comes out in, look away -> it comes out after 5 s and is banished.
## --shadowblock: the cat stands between it and its nearest nook (it must go around or retreat);
## min_cat in the log is the closest it ever ran to the cat
## --peekat=NOOK [--peekshots=DIR] [--peekheat=0..1] [--peekcam=x,y,z]: holds the Shadow peeking from that nook and shoots it from the
## places the cat would look from: around the line to the nook's exit, low (cat) and high (camera)
func _peek_test() -> void:
	var sh: ShadowThreat = g.director.get_threat("shadow")
	if t < 1.5:
		return
	if sh.nook.is_empty() or sh.nook["id"] != str(args["peekat"]):
		for nk in Layout.data().get("SHADOW_NOOKS", []):
			if nk["id"] == str(args["peekat"]):
				sh.nook = nk
	if sh.nook.is_empty():
		return
	sh.mode = "peek"
	sh.dev_no_look = args.get("peeklook", "1") == "0"
	sh.sight = float(args.get("peekheat", "0.3"))
	sh.vis = 1.0
	var head := sh._peek_head()
	var exit_p: Vector3 = g.house.nav.get_node(sh.nook["exit"]).p
	var base := Vector2(exit_p.x - head.x, exit_p.z - head.z).angle()
	var views := []
	for da in [-0.7, -0.35, 0.0, 0.35, 0.7]:
		for hh in [0.35, 1.3]:
			views.append([base + da, hh])
	var k := int((t - 7.0) / 0.8)
	if k < 0:
		k = 0
	if k >= views.size():
		if not has_meta("pk_done"):
			set_meta("pk_done", true)
			get_tree().quit()
		return
	if not has_meta("pk_logged") and t > 6.5:
		set_meta("pk_logged", true)
		var pv := sh.peek
		print("PEEKPOS %s head=%s hand_l=%s hand_r=%s" % [sh.nook["id"], pv.head.global_position, pv.hands[0].global_position, pv.hands[1].global_position])
		if args.get("peekfurn", "") == "near":
			var np := Layout.v3(sh.nook["p"])
			for mi in g.house.find_children("*", "MeshInstance3D", true, false):
				var mm := mi as MeshInstance3D
				if mm.mesh == null or not mm.is_visible_in_tree():
					continue
				var gab: AABB = mm.global_transform * mm.mesh.get_aabb()
				var c := gab.get_center()
				if absf(gab.position.y - np.y) < 0.6 and Vector2(c.x - np.x, c.z - np.z).length() < 1.6 and gab.size.x < 3.0 and gab.size.z < 3.0:
					print("NEAR %s %s..%s" % [mm.get_parent().name + "/" + mm.name, gab.position, gab.end])
		for fn in str(args.get("peekfurn", "")).split(","):
			var fnode := g.house.find_child(fn, true, false) as Node3D if fn != "" else null
			if fnode:
				var ab: AABB = g._node_aabb(fnode)
				print("FURN %s aabb=%s..%s" % [fn, ab.position, ab.end])
		if not args.has("peekshots"):
			get_tree().quit()
	var v: Array = views[k]
	var floor_y := Layout.v3(sh.nook["p"]).y
	var cp := Vector3(head.x + cos(v[0]) * 2.4, floor_y + float(v[1]), head.z + sin(v[0]) * 2.4)
	if args.has("peekcam"):
		var pc := str(args["peekcam"]).split(",")
		cp = Vector3(float(pc[0]), float(pc[1]), float(pc[2])) + Vector3(0, float(v[1]) - 0.35, 0) * 0.5
	g.rig.override_pose = {"pos": cp, "look": head + Vector3(0, -0.35, 0), "blend": 1.0}
	g.cat.teleport(Vector3(cp.x, floor_y, cp.z) - (Vector3(head.x, floor_y, head.z) - Vector3(cp.x, floor_y, cp.z)).normalized() * 0.6, 0.0)
	if args.has("peekshots") and int((t - 7.0) / 0.8 - 0.6) == k and not has_meta("pk_%d" % k):
		set_meta("pk_%d" % k, true)
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(args["peekshots"])
		img.save_png(str(args["peekshots"]).path_join("%s_%02d.png" % [str(args["peekat"]), k]))
		var vp := get_viewport().get_visible_rect().size
		var hs := get_viewport().get_camera_3d().unproject_position(sh.peek.head.global_position)
		var hz: Vector3 = sh.peek.head.global_basis.z.normalized()
		var tocat := (g.cat.global_position + Vector3(0, 0.25, 0) - sh.peek.head.global_position).normalized()
		print("  cat=%s cam=%s face_to_cam=%.0fdeg" % [g.cat.global_position, g.cam.global_position, rad_to_deg(hz.angle_to((g.cam.global_position - sh.peek.head.global_position).normalized()))])
		print("PEEKSHOT %d %s cam=%s scr=%.3f,%.3f blocked=%s look=%.2f face_to_cat=%.0fdeg stares=%s" % [k, args["peekat"], cp, hs.x / vp.x, hs.y / vp.y, g.house.blocked(cp, head, HouseBuilder.LAYER_WORLD | HouseBuilder.LAYER_CAMERA), sh._look_k, rad_to_deg(hz.angle_to(tocat)), sh._player_stares(head)])


## --shadowtest=5: three sightings in a row (look, it flees and hides, look away until it comes out,
## look again); after the third the bold Shadow should back off in view, stare, heat up and charge, or
## follow the cat faster and faster (--walkaway: the cat walks off at 1 m/s). Logs boldness and speed.
func _shadow_test() -> void:
	var sh: ShadowThreat = g.director.get_threat("shadow")
	var test := str(args["shadowtest"])
	sh.dev_nook = str(args.get("shadownook", ""))
	sh.dev_log = true
	var dt := get_process_delta_time()
	_log_t -= dt
	var last_p: Vector3 = get_meta("sh_last_p", sh.pos)
	var sh_speed := Vector2(sh.pos.x - last_p.x, sh.pos.z - last_p.z).length() / maxf(dt, 1e-4)
	set_meta("sh_last_p", sh.pos)
	if _log_t <= 0:
		_log_t = 0.5
		print("SHADOW t=%.1f stage=%d mode=%s nook=%s sight=%.2f pos=%s lives=%d cam=%s cat_d=%.2f min_cat=%.2f bold=%s speed=%.2f hidden=%s" % [t, sh.stage, sh.mode, sh.nook.get("id", "-"), sh.sight, sh.pos, g.lives, g.cam.global_position, sh._cat_dist(), sh.dev_min_cat, sh.get("boldness"), sh_speed, sh.hidden_room() if sh.has_method("hidden_room") else "?"])
	if t < 2.0 or sh.stage < 2:
		if test == "5" and get_meta("sh_phase", "") == "stalk" and sh.stage == 0 and not has_meta("sh_done"):
			set_meta("sh_done", true)
			print("SHADOWTEST5 end: gone (lives=%d bold=%s)" % [g.lives, sh.get("boldness")])
		return
	var phase_k: String = get_meta("sh_phase", "look")
	if test == "5" and phase_k == "stalk":
		# after the third sighting: keep looking at it from where the cat is
		var e5 := sh.pos + Vector3(0, 1.0, 0)
		var cp := g.cat.global_position + Vector3(0, 0.9, 0)
		var back := (cp - e5)
		back.y = 0
		back = back.normalized() if back.length() > 0.01 else Vector3(1, 0, 0)
		g.rig.override_pose = {"pos": cp + back * 0.6 + Vector3(0, 0.3, 0), "look": e5, "blend": 1.0}
		if args.has("walkaway") and t - float(get_meta("sh_stalk_t", t)) > 1.5:
			var away := g.cat.global_position - sh.pos
			away.y = 0
			if away.length() > 0.01:
				var np := g.cat.global_position + away.normalized() * 1.0 * dt
				if g.house.nav.nearest(np).p.distance_to(np) < 2.5:
					g.cat.teleport(np, atan2(away.x, away.z))
		if g.lives < int(get_meta("sh_lives", g.lives)) and not has_meta("sh_done"):
			set_meta("sh_done", true)
			print("SHADOWTEST5 end: it took a life after %.1f s of stalking (bold=%s)" % [t - float(get_meta("sh_stalk_t", t)), sh.get("boldness")])
		return
	if test == "5" and (phase_k == "fled" or phase_k == "hidden") and sh.mode == "walk":
		# it came out again: the next sighting
		set_meta("sh_phase", "look")
		phase_k = "look"
		print("SHADOWTEST5 out again mode=%s bold=%s" % [sh.mode, sh.get("boldness")])
	if phase_k == "look":
		# a clear view of it from a couple of metres away
		var e := sh.pos
		var best := Vector3.ZERO
		# --shadowblock: stand between it and the nook it would have picked (the nearest one)
		var a0 := 0.0
		if args.has("shadowblock"):
			var bd := INF
			for nk in Layout.data().get("SHADOW_NOOKS", []):
				var np := Layout.v3(nk["p"])
				if absf(np.y - e.y) < 1.5 and np.distance_to(e) < bd:
					bd = np.distance_to(e)
					a0 = atan2(np.z - e.z, np.x - e.x)
		for k in 16:
			var a := a0 + (ceili(k / 2.0) * (1 if k % 2 == 0 else -1)) / 16.0 * TAU
			for dd in [2.6, 2.0, 1.5]:
				var c := e + Vector3(cos(a) * dd, 1.3, sin(a) * dd)
				if not g.house.blocked(e + Vector3(0, 1.3, 0), c, HouseBuilder.LAYER_WORLD | HouseBuilder.LAYER_CAMERA):
					best = c
					break
			if best != Vector3.ZERO:
				break
		g.rig.override_pose = {"pos": best, "look": e + Vector3(0, 1.3, 0), "blend": 1.0}
		g.cat.teleport(Vector3(best.x, e.y, best.z), 0.0)
		if sh.mode == "flee" or sh.mode == "retreat" or sh.mode == "stalk":
			set_meta("sh_phase", "fled")
			print("SHADOWTEST fled to %s (cat at %.2f m)" % [sh.nook.get("id", "retreat"), sh._cat_dist()])
			if test == "5":
				var seen := int(get_meta("sh_seen", 0)) + 1
				set_meta("sh_seen", seen)
				print("SHADOWTEST5 sighting %d mode=%s bold=%s" % [seen, sh.mode, sh.get("boldness")])
				if seen >= 3:
					set_meta("sh_phase", "stalk")
					set_meta("sh_stalk_t", t)
					set_meta("sh_lives", g.lives)
					return
	elif phase_k == "fled":
		# test 3: the room of the nook it runs to is lit (it may first back off with no nook in reach)
		if test == "3" and not sh.nook.is_empty() and not has_meta("sh_lit3"):
			set_meta("sh_lit3", true)
			var rl = g.house.lights.by_room.get(sh.nook["room"])
			if rl:
				rl.set_on(true)
				rl.life = 999.0
				print("SHADOWTEST lit %s" % sh.nook["room"])
		if sh.mode == "hidden" or sh.mode == "peek":
			set_meta("sh_phase", "hidden")
			print("SHADOWTEST hidden in %s min_cat=%.2f" % [sh.nook.get("id", "-"), sh.dev_min_cat])
		if test == "1" or test == "3" or test == "4" or test == "5" or test == "6":
			g.rig.override_pose = {"pos": g.cam.global_position, "look": g.cam.global_position + Vector3(0, -2.0, 0.1), "blend": 1.0}
	elif phase_k == "hidden":
		if sh.nook.is_empty():
			if sh.stage == 0 and not has_meta("sh_done"):
				set_meta("sh_done", true)
				print("SHADOWTEST end: gone (lives=%d)" % g.lives)
			return
		var exit_p: Vector3 = g.house.nav.get_node(sh.nook["exit"]).p
		var head := sh._peek_head()
		if test == "2":
			var cpos := exit_p + Vector3(0, 1.2, 0) + (exit_p - head).normalized() * float(args.get("camback", "0.6"))
			cpos.y = exit_p.y + 1.2
			g.rig.override_pose = {"pos": cpos, "look": head, "blend": 1.0}
			if g.cat.global_position.distance_to(exit_p) > 1.0 and sh.mode != "charge":
				g.cat.teleport(exit_p, 0.0)
		elif test == "6":
			# staring at the nook from its exit, then the light of its room comes on (a normal bulb):
			# it must crawl out and be banished
			g.rig.override_pose = {"pos": exit_p + Vector3(0, 1.2, 0) + (exit_p - head).normalized() * 0.6, "look": head, "blend": 1.0}
			if not has_meta("sh_lit6"):
				set_meta("sh_lit6", t)
			elif t - float(get_meta("sh_lit6")) > 1.0 and not has_meta("sh_lit6b"):
				set_meta("sh_lit6b", true)
				var rl6 = g.house.lights.by_room.get(sh.nook["room"])
				if rl6:
					rl6.set_on(true)
					print("SHADOWTEST6 lit %s while %s" % [sh.nook["room"], sh.mode])
		elif test == "4":
			# in the room but not staring: the nook sits near the edge of the frame
			var away := (head - exit_p).normalized().rotated(Vector3.UP, float(args.get("awayang", "0.6")))
			var cpos := exit_p + Vector3(0, 1.3, 0) + (exit_p - head).normalized() * 1.2
			g.rig.override_pose = {"pos": cpos, "look": cpos + away * 3.0 + Vector3(0, -0.4, 0), "blend": 1.0}
			if _log_t == 0.5:
				var vp := get_viewport().get_visible_rect().size
				var hs := g.cam.unproject_position(head)
				print("SHADOWTEST4 head scr=%.2f,%.2f in_frustum=%s sees=%s stares=%s" % [hs.x / vp.x, hs.y / vp.y, g.cam.is_position_in_frustum(head), sh._player_sees([head]), sh._player_stares(head)])
		elif test == "5":
			# away from the nook and not looking at it: it has to come out by itself
			var aw := (exit_p - head).normalized()
			var cpos5 := exit_p + aw * 3.0
			g.cat.teleport(g.house.nav.nearest(cpos5).p, 0.0)
			g.rig.override_pose = {"pos": g.cat.global_position + Vector3(0, 1.2, 0), "look": g.cat.global_position + aw * 3.0 + Vector3(0, 0.8, 0), "blend": 1.0}
		else:
			g.rig.override_pose = {"pos": exit_p + Vector3(0, 1.2, 0), "look": exit_p + Vector3(0.1, -1.0, 0.1) + (exit_p - head).normalized() * 2.0, "blend": 1.0}
		if sh.stage == 0 and not has_meta("sh_done"):
			set_meta("sh_done", true)
			print("SHADOWTEST end: gone (lives=%d)" % g.lives)


## --selftest: lives bookkeeping, save migration and the loops of the house, then quit
func _selftest() -> void:
	var fails := 0
	var sv := SaveGame.new_save()
	fails += _expect("fresh lives", SaveGame.lives_at(sv, 5), 7)
	SaveGame.record_night(sv, 1, 2)
	SaveGame.record_night(sv, 2, 1)
	fails += _expect("after two nights", SaveGame.lives_at(sv, 3), 4)
	SaveGame.record_night(sv, 1, 0)
	fails += _expect("replay better", SaveGame.lives_at(sv, 3), 6)
	SaveGame.record_night(sv, 2, 3)
	fails += _expect("replay worse keeps best", SaveGame.lives_at(sv, 3), 6)
	var old := {"version": 2, "unlocked_night": 4, "current": {}, "night": {}}
	var mig = SaveGame.migrate(old)
	fails += _expect("migrated version", int(mig["version"]), 3)
	fails += _expect("migrated lives", SaveGame.lives_at(mig, 4), 7)
	fails += _expect("migrated tips", SaveGame.tips_of(mig).has("howto"), true)
	var v3 := {"version": 3, "unlocked_night": 2, "nights": {}}
	fails += _expect("v3 without tips loads", SaveGame.tips_of(SaveGame.migrate(v3))["introduced"].size(), 0)
	# the outside doors bring the cat back in; the afternoon ends lying down with Clara
	for did in ["d_front", "d_back"]:
		fails += _expect("scratch-in interaction %s" % did, g.inter.find("scratch_in_" + did) != null, true)
	fails += _expect("key carryable", g.house.carryables.has(Game.PORAO_KEY), true)
	fails += _expect("afternoon tasks for every day", Story.AFTERNOON_TASKS.size(), Config.LAST_NIGHT)
	for id in Story.THREAT_INFO:
		fails += _expect("how to beat %s" % id, Story.THREAT_INFO[id].has("howto"), true)
	var nav := g.house.nav
	for pair in [["g_sala_tv", "g_esc_mid"], ["g_esc_mid", "g_jan_mid"], ["g_jan_mid", "g_hall_back"], ["g_jan_e", "g_desp_mid"], ["f_quarto_bed", "f_hosp_mid"]]:
		var r := nav.route(nav.get_node(pair[0]), nav.get_node(pair[1]))
		fails += _expect("route %s -> %s" % pair, r.size() > 0 and r.size() <= 6, true)
	# a loop: from the hall to the dining room both through the study and straight through the back door
	var via_esc := nav.route(nav.get_node("g_d_esc_h"), nav.get_node("g_jan_w"))
	fails += _expect("hall->study->dining is short", via_esc.size() <= 6, true)
	for spot in Layout.data()["HIDE_SPOTS"]:
		fails += _expect("hide spot %s has an exit" % spot["id"], spot.has("exit"), true)
	for nk in Layout.data().get("SHADOW_NOOKS", []):
		fails += _expect("shadow nook %s exit node" % nk["id"], nav.nodes.has(nk["exit"]), true)
		fails += _expect("shadow nook %s room" % nk["id"], Layout.room_at(Layout.v3(nk["p"])) != "", true)
	# one line at a time: a line that comes while she talks waits for its turn
	var cl: Owner = g.clara
	cl._says.clear()
	cl._say_left = 0.0
	cl.say("primeira", 1.0)
	cl.say("segunda", 1.0)
	fails += _expect("second line waits its turn", cl._says.size(), 1)
	cl._tick_says(1.0 + cl.SAY_GAP + 0.1)
	fails += _expect("still waiting while the first talks", cl._says.size(), 1)
	cl._tick_says(0.0)
	fails += _expect("second line starts after the first", cl._says.size() == 0 and cl._say_left > 0.5, true)
	cl._say_left = 0.0
	print("SELFTEST %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit()


func _expect(what: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got %s, want %s" % [what, got, want])
	return 1


func _start() -> void:
	if args.has("selftest"):
		_selftest()
		return
	if args.has("armtest"):
		# model-space directions of Clara's left upper arm / forearm in the procedural poses
		var r: HumanRig = g.clara.model
		for p in str(args["armtest"]).split(","):
			r.snap_pose(p)
			r.update(0.016)
			r._modify(r.cur_outfit, 0.016)
			var sk: Skeleton3D = r.outfits[r.cur_outfit]["skel"]
			var a := sk.get_bone_global_pose(sk.find_bone("upperarm_l")).origin
			var b := sk.get_bone_global_pose(sk.find_bone("lowerarm_l")).origin
			var c := sk.get_bone_global_pose(sk.find_bone("hand_l")).origin
			print("ARM %s upper %s fore %s" % [p, (b - a).normalized(), (c - b).normalized()])
		get_tree().quit()
		return
	if args.has("e2e") or args.has("timescale"):
		Engine.time_scale = float(args.get("timescale", "2"))
	var ph: String = args.get("phase", "afternoon" if args.has("e2e") else "menu")
	var d := int(args.get("day", "1"))
	if args.has("e2e"):
		_e2e_go("afternoon")
	if ph == "night":
		g.start_at_night(d)
	elif ph == "morning":
		g.flags = SaveGame.fresh_flags()
		g.start_morning(d)
	elif ph == "afternoon":
		g.day = d
		g.start_afternoon()
	if args.has("threat"):
		var th := g.director.get_threat(args["threat"])
		g.director.summons_on = false   # a driven test: the Director calls nobody else
		if th:
			th.enable(0.0)
			for st in range(1, int(args.get("stage", "1")) + 1):
				th.set_stage(st)
	if args.has("hound"):
		g.director.hound.cooldown = 0.0
	if args.has("hour"):
		g.phase_t = float(args["hour"]) / 6.0 * g.night_len
	if args.has("lights"):
		g.house.lights.set_all(true)
	if args.has("hatch"):
		g.house.set_hatch(true, true)
	if args.has("nonormal") or args.has("noroughtex"):
		for mi in g.house.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(si) as BaseMaterial3D
				if mat:
					if args.has("nonormal"):
						mat.normal_enabled = false
					if args.has("noroughtex"):
						mat.roughness_texture = null
	if args.has("matdump"):
		var n := g.house.find(str(args["matdump"]))
		if n:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				for si in m.mesh.get_surface_count():
					var mat = m.get_active_material(si)
					if mat is BaseMaterial3D:
						print("MAT %s/%d alb=%s nrm=%s r=%.2f rt=%s ch=%d detail=%s tri=%s transp=%d ov=%s" % [m.name, si, mat.albedo_texture.resource_path if mat.albedo_texture else "-", mat.normal_enabled, mat.roughness, mat.roughness_texture.resource_path if mat.roughness_texture else "-", mat.roughness_texture_channel, mat.detail_enabled, mat.uv1_triplanar, mat.transparency, m.material_override != null])
					else:
						print("MAT %s/%d %s" % [m.name, si, mat])
	if args.has("noshadow"):
		for l in g.find_children("*", "Light3D", true, false):
			(l as Light3D).shadow_enabled = false
	if args.has("nolfog"):
		for l in g.find_children("*", "Light3D", true, false):
			(l as Light3D).light_volumetric_fog_energy = 0.0
	if args.has("nodirsh"):
		for l in g.find_children("*", "DirectionalLight3D", true, false):
			(l as Light3D).shadow_enabled = false
	if args.has("noomsh"):
		for l in g.find_children("*", "OmniLight3D", true, false):
			(l as Light3D).shadow_enabled = false
	if args.has("nospsh"):
		for l in g.find_children("*", "SpotLight3D", true, false):
			(l as Light3D).shadow_enabled = false
	if args.has("sun0"):
		g.env.sun.visible = false
	if args.has("hidel"):
		var ls := g.find_children("*", "Light3D", true, false)
		var ids := str(args["hidel"]).split(",")
		print("LIGHTS ", ls.size())
		for i in ls.size():
			if str(i) in ids:
				(ls[i] as Light3D).visible = false
				print("HID ", i, " ", ls[i].name, " ", ls[i].get_class())
	if args.has("sunv"):
		var sn: DirectionalLight3D = g.env.sun
		match str(args["sunv"]):
			"ortho": sn.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			"blur0": sn.shadow_blur = 0.0
			"md10": sn.directional_shadow_max_distance = 10.0
			"nonb": sn.shadow_normal_bias = 0.0
			"bias0": sn.shadow_bias = 0.0
		print("SUN ", sn.rotation_degrees, " ", sn.light_color, " ", sn.light_energy, " ", sn.visible)
	if args.has("nolod"):
		get_viewport().mesh_lod_threshold = 0.0
	for k in ["ssil", "ssao", "gi", "glow", "fog", "ssr"]:
		if args.has("no" + k):
			match k:
				"ssil": g.env.env.ssil_enabled = false
				"ssao": g.env.env.ssao_enabled = false
				"gi": g.env.vgi.visible = false
				"glow": g.env.env.glow_enabled = false
				"fog": g.env.env.volumetric_fog_enabled = false


func _apply_overrides() -> void:
	if args.has("meet") and t > 2.0 and not _met:
		var th := g.director.get_threat(args["meet"])
		var e = th.entity() if th else null
		if e != null:
			_met = true
			var nav := g.house.nav
			var n := nav.nearest(e)
			var far = n
			for l in n.links:
				var o = l["to"]
				if o and o.p.distance_to(e) > far.p.distance_to(e) and absf(o.p.y - e.y) < 1.0:
					far = o
			g.cat.teleport(far.p, atan2(e.x - far.p.x, e.z - far.p.z))
			print("MEET %s at %s cat=%s" % [args["meet"], e, far.p])
			if args.has("camghost"):
				var back: Vector3 = (far.p - e)
				back.y = 0
				back = back.normalized()
				g.rig.override_pose = {"pos": far.p + back * 0.3 + Vector3(0, 0.55, 0), "look": e + Vector3(0, 1.3, 0), "blend": 1.0}
	if args.has("catgo"):
		g.cat.yaw = float(args["catgo"])
		Input.action_press("move_forward")
		_catgo = true
	elif _catgo:
		Input.action_release("move_forward")
		_catgo = false
	if args.has("runaway") and _met:
		var hunter = null
		for th2: Threat in g.director.all:
			if th2.hunting_cat and th2.entity() != null:
				hunter = th2.entity()
		if hunter != null:
			var away: Vector3 = g.cat.global_position - hunter
			g.cat.yaw = atan2(away.x, away.z)
			Input.action_press("move_forward")
			Input.action_press("run")
		else:
			Input.action_release("move_forward")
			Input.action_release("run")
	if args.has("pressbtn") and t > 1.0 and not _met:
		for b in g.ui.find_children("*", "Button", true, false):
			if (b as Button).text == str(args["pressbtn"]):
				_met = true
				(b as Button).pressed.emit()
				print("PRESSED ", b.text)
	if args.has("fakesave") and t < 0.1 and not has_meta("faked"):
		set_meta("faked", true)
		var sv := SaveGame.new_save()
		sv["unlocked_night"] = 4
		sv["nights"] = {"1": {"lost": 0, "done": true}, "2": {"lost": 2, "done": true}, "3": {"lost": 1, "done": true}}
		SaveGame.write_save(sv)
		g.to_menu()
	if args.has("relictest") and t > 2.0:
		var k := int((t - 2.0) / 1.5)
		if k < g.relics.size() and not has_meta("r%d" % k):
			set_meta("r%d" % k, true)
			var c: PropSystem.Carryable = g.relics[k]["c"]
			var nav := g.house.nav
			var path := nav.route(nav.nearest(g.cat.global_position), nav.nearest(c.pos))
			print("RELIC %d %s at %s room=%s path=%d" % [k, c.name, c.pos, Layout.room_at(c.pos), path.size()])
			g.cat.carrying = c
			c.carried = true
			g.cat.teleport(g.house.ritual_center + Vector3(0.8, 0, 0), 0.0)
			g.deliver_relic()
			print("  delivered %d/%d" % [g.relics_done, g.relics.size()])
		if t > 2.0 + g.relics.size() * 1.5 + 8.0 and not has_meta("rdone"):
			set_meta("rdone", true)
			print("RELIC END mode=%s phase=%s winning=%s" % [g.mode, g.phase, g._winning])
			get_tree().quit()
	if args.has("boxtest") and not has_meta("boxed") and g.director.cat_hunters(null) > 0:
		set_meta("boxed", true)
		var bp: Vector3 = g.house.boxes[0]["pos"]
		g.cat.teleport(bp + Vector3(0, 0, 0.6), PI)
		g.enter_box(0)
		print("BOX entered at %s box=%s" % [bp, g.flags["boxes"][0]])
	if args.has("boxtest") and has_meta("boxed") and not has_meta("boxlog") and t > 0 and g.cat.mode == "hidden" and g.flags["boxes"][0]["used"]:
		set_meta("boxlog", true)
		print("BOX used=%s hunters=%d" % [g.flags["boxes"][0]["used"], g.director.cat_hunters(null)])
	if args.has("visitortest"):
		var vt: VisitorThreat = g.director.visitor
		if t > 2.0 and not has_meta("vt1") and vt.stage >= 2 and vt.cur != null:
			set_meta("vt1", true)
			var k: Vector3 = vt.cur["figure"]
			var out := Vector3(k.x, -0.9, k.z) + (Vector3(6.45, -0.9, 5.0) - Vector3(k.x, -0.9, k.z)).normalized() * -1.2
			g.cat.teleport(out, 0.0)
			g.cat.focus = 100.0
			var ok := g.director.hiss(g.cat.global_position, true)
			print("VISITOR hiss outside ok=%s hunting=%s at=%s cat=%s" % [ok, vt.hunting_cat, k, g.cat.global_position])
	# --visitorat=front|sala|coz: that entrance; --visitorhiss=SEC: hiss at it from inside then
	if args.has("visitorat"):
		var va: VisitorThreat = g.director.visitor
		if va.cur != null and va.cur["id"] != str(args["visitorat"]) and va.stage <= 2 and not has_meta("va_hissed"):
			for e in va.entrances:
				if e["id"] == str(args["visitorat"]):
					va.cur = e
					va.fig_pos = e["figure"]
	if args.has("visitorhiss") and t > float(args["visitorhiss"]) and not has_meta("va_hissed"):
		var vh: VisitorThreat = g.director.visitor
		if vh.cur != null and vh.stage >= 2:
			set_meta("va_hissed", true)
			var sp := Layout.spot_pos(vh.cur["spot"])
			g.cat.teleport(sp, 0.0)
			g.cat.focus = 100.0
			var ok := g.director.hiss(g.cat.global_position, true)
			print("VISITOR hiss inside at %s ok=%s at %s hunting=%s" % [sp, ok, vh.cur["id"] if vh.cur else "-", vh.hunting_cat])
	if args.has("vislog"):
		var vl: VisitorThreat = g.director.visitor
		_log_t -= get_process_delta_time()
		if _log_t <= 0:
			_log_t = 0.5
			print("VIS t=%.1f stage=%d cur=%s fig=%s pose=%s style=%s hunt=%s leave=%.1f" % [t, vl.stage, vl.cur["id"] if vl.cur else "-", vl.fig_pos, vl.fig.rig.pose, vl.fig.rig.style, vl.hunting_cat, vl._leave_t])
	if args.has("whisperlog"):
		var wl: WhispererThreat = g.director.whisperer
		if get_meta("wl_light", -1) != wl.light or get_meta("wl_stage", -1) != wl.stage:
			set_meta("wl_light", wl.light)
			set_meta("wl_stage", wl.stage)
			print("WHISPER t=%.2f stage=%d light=%s dev=%s harsh=%.2f" % [t, wl.stage, ["verde", "amarelo", "vermelho"][wl.light], wl.dev.id if wl.dev else "-", wl.harsh])
	# --orbtest: the Whisperer takes a device, the cat stands 2.5 m in front of it and the ball comes
	# out; the camera watches from behind the cat; logs the ball's speed
	if args.has("orbtest"):
		var wo2: WhispererThreat = g.director.whisperer
		if t > 1.5 and not has_meta("orb0"):
			set_meta("orb0", true)
			wo2.enable(0.0)
			wo2.set_stage(1)
			wo2.set_stage(2)
			var dv0: House.Device = wo2.dev
			var nrm: Vector3 = dv0.normal if dv0.normal.length() > 0.1 else Vector3(0, 0, 1)
			nrm.y = 0
			var cpos: Vector3 = g.house.nav.nearest(dv0.pos + nrm.normalized() * 2.5).p
			g.cat.teleport(cpos, atan2(dv0.pos.x - cpos.x, dv0.pos.z - cpos.z))
			set_meta("orb_cam", cpos + (dv0.pos - cpos).normalized() * 0.25 + Vector3(0, 0.8, 0))
			set_meta("orb_dev", dv0.pos)
			print("ORBTEST dev=%s at %s cat=%s" % [dv0.id, dv0.pos, cpos])
		if has_meta("orb0") and t > 2.5 and not has_meta("orb1"):
			set_meta("orb1", true)
			print("ORBTEST released=%s" % wo2._release_orb())
		if has_meta("orb_cam"):
			g.rig.override_pose = {"pos": get_meta("orb_cam"), "look": (get_meta("orb_dev") as Vector3) + Vector3(0, 0.3, 0), "blend": 1.0}
			g.cat.teleport(g.cat.global_position, g.cat.yaw)
		if has_meta("orb1") and wo2.hunting_cat:
			var lp: Vector3 = get_meta("orb_lp", wo2.orb_pos)
			var dtt := get_process_delta_time()
			set_meta("orb_lp", wo2.orb_pos)
			if int(t * 2) != int((t - dtt) * 2):
				print("ORB t=%.1f age=%.1f speed=%.2f pos=%s" % [t, wo2.ORB_LIFE - wo2.orb_life, lp.distance_to(wo2.orb_pos) / maxf(dtt, 1e-4), wo2.orb_pos])
	# --whisperodds: ~50 forced pulls per colour, how many balls come out
	if args.has("whisperodds") and t > 1.0 and not has_meta("wodds"):
		set_meta("wodds", true)
		var wo: WhispererThreat = g.director.whisperer
		for c in 3:
			wo.light = c
			var balls := 0
			for k in 50:
				if randf() < wo._orb_chance():
					balls += 1
			print("WHISPER odds %s: %d/50 balls (%.0f%%)" % [["verde", "amarelo", "vermelho"][c], balls, balls * 2.0])
	if args.has("nltest"):
		var wh2: WhispererThreat = g.director.whisperer
		var nld: House.Device = g._nightlight_device()
		if t > 1.0 and not has_meta("nl1"):
			set_meta("nl1", true)
			for dv in g.house.devices:
				if dv.id != "nightlight":
					g.house.set_plugged(dv, false)
			wh2.enable(0.0)
			wh2.set_stage(1)
			wh2.set_stage(2)
			print("NL dev=%s room=%s lit=%s hidden=%s" % [wh2.dev.id if wh2.dev else "-", nld.room, g.house.lights.is_room_lit(nld.room), nld.hidden])
		if t > 4.0 and not has_meta("nl2"):
			set_meta("nl2", true)
			wh2.harsh = 0.0
			g.house.set_plugged(nld, false)
		if t > 4.5 and not has_meta("nl3"):
			set_meta("nl3", true)
			print("NL after unplug: lit=%s stage=%d plugged=%s glow_on=%s" % [g.house.lights.is_room_lit(nld.room), wh2.stage, nld.plugged, g.house.nightlight_glow.light_energy > 0.01])
			get_tree().quit()
	if args.has("unplug") and t > 3.0 and t < 3.05:
		var wh: WhispererThreat = g.director.whisperer
		if wh.dev:
			wh.harsh = float(args["unplug"])
			g.cat.teleport(g.house.nav.nearest(wh.dev.outlet).p, 0.0)
			g.house.set_plugged(wh.dev, false)
			print("UNPLUG %s harsh=%.2f" % [wh.dev.name, wh.harsh])
	if args.has("splash") and t > 3.0 and not _met:
		_met = true
		var dr: DrownerThreat = g.director.drowner
		dr.source.puddle = 1.0
		var pc: Vector3 = dr.source.puddle_center
		g.cat.teleport(Vector3(pc.x, dr.source.floor_y, pc.z), 0.0)
		print("SPLASH at %s her=%s" % [pc, dr.pos])
	if args.has("huntlog"):
		_log_t -= get_process_delta_time()
		if _log_t <= 0:
			_log_t = 0.5
			var parts := []
			for th3: Threat in g.director.all:
				if th3.enabled and th3.stage > 0:
					parts.append("%s:s%d sight=%.2f hunt=%s at=%s" % [th3.threat_id, th3.stage, th3.sight, th3.hunting_cat, th3.entity()])
			print("HUNT t=%.1f lives=%d lost=%d cat=%s mode=%s hound=%s | %s" % [t, g.lives, g.lost_tonight, g.cat.global_position, g.mode, Hound.S.keys()[g.director.hound.state], ", ".join(parts)])
	if args.has("lamp"):
		for rl in g.house.lights.lights:
			if rl.def["room"] == "exterior":
				match str(args["lamp"]):
					"spot": rl.light.light_color = Color.BLACK
					"omni": rl.glow_light.light_energy = 0.0; rl.glow_light.visible = false
					"all": rl.base_energy = 0.0
	if args.has("nogi"):
		g.env.vgi.visible = false
		g.env.vgi.queue_free() if args.has("killgi") else null
	if args.has("noglow"):
		g.env.env.glow_enabled = false
	if args.has("noedge"):
		g.env.edge_quad.visible = false
	if args.has("nopost"):
		for n in g.find_children("*", "CanvasLayer", true, false):
			n.visible = false
	if args.has("purr") and t > 1.5 and t < 1.53 and g.cat.mode != "purr":
		g.toggle_purr(g.clara)
	if args.has("carry") and t > 1.0 and t < 1.03 and g.cat.carrying == null:
		# --carry=ID: a carryable of the house (toy, chave, foto, coleira, doll) or relic:KIND
		var cid := str(args["carry"])
		var c: PropSystem.Carryable
		if cid.begins_with("relic:"):
			c = PropSystem.Carryable.new()
			c.id = "relic_dev"
			c.node = Node3D.new()
			g.house.add_child(c.node)
			c.node.add_child(Carry.make_relic(cid.substr(6)))
			c.node.set_meta("grip", cid.substr(6))
		else:
			c = g.house.carryables.get(cid if cid != "1" else "toy")
			if cid == "doll":
				c.node.visible = true
		g.cat.carrying = c
		c.carried = true
	if args.has("walk"):
		if t > 1.0 and t < 3.0:
			Input.action_press("move_forward")
			Input.action_press("run")
		elif t >= 3.0 and t < 3.1:
			Input.action_release("move_forward")
			Input.action_release("run")
			print("WALKED cat=%s" % g.cat.global_position)
		if t > 3.5 and t < 3.6:
			Input.action_press("meow")
		elif t >= 3.6 and t < 3.7:
			Input.action_release("meow")
		if t > 4.0 and t < 4.1:
			Input.action_press("jump")
		elif t >= 4.1 and t < 4.2:
			Input.action_release("jump")
			print("JUMP grounded=%s arc=%s" % [g.cat.grounded, g.cat.arc != null])
	# --relics: where tonight's things of Ivone lie
	if args.has("relics") and t > 1.0 and not has_meta("relics_logged"):
		set_meta("relics_logged", true)
		for r in g.relics:
			print("RELIC %s %s" % [(r["c"] as PropSystem.Carryable).id, (r["c"] as PropSystem.Carryable).pos])
	# --atrelic=I: the cat 1.6 m from tonight's I-th thing of Ivone, the camera behind it looking at it
	if args.has("atrelic") and t > 0.6 and g.relics.size() > int(args["atrelic"]):
		var rp: Vector3 = (g.relics[int(args["atrelic"])]["c"] as PropSystem.Carryable).pos
		if not has_meta("atrelic_done"):
			set_meta("atrelic_done", true)
			var nn := g.house.nav.nearest(rp)
			var away := Vector3(nn.p.x - rp.x, 0, nn.p.z - rp.z)
			away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
			set_meta("atrelic_dir", away)
			g.cat.teleport(rp + away * 1.6, atan2(-away.x, -away.z))
			print("ATRELIC %s cat=%s" % [rp, rp + away * 1.6])
		var ad: Vector3 = get_meta("atrelic_dir")
		g.rig.override_pose = {"pos": rp + ad * 2.6 + Vector3(0, 1.3, 0), "look": rp, "blend": 1.0}
	if args.has("catpos") and t < 0.5:
		var p := str(args["catpos"]).split(",")
		g.cat.teleport(Vector3(float(p[0]), float(p[1]), float(p[2])), float(args.get("yaw", "0")))
		g.rig.snap(g.cat.global_position + Vector3(0, 0.32, 0), float(args.get("yaw", "0")) + PI)
	# --catcam=ANGLE[,dist,h]: camera around the cat's head (ANGLE in degrees from its nose, 90 = its left)
	if args.has("catcam"):
		var cc := str(args["catcam"]).split(",")
		var hd: Vector3 = g.cat.rig.head_world()
		var a := g.cat.yaw + deg_to_rad(float(cc[0]))
		var dd := float(cc[1]) if cc.size() > 1 else 0.7
		var hh := float(cc[2]) if cc.size() > 2 else 0.05
		g.rig.override_pose = {"pos": hd + Vector3(sin(a) * dd, hh, cos(a) * dd), "look": hd + Vector3(0, -0.06, 0), "blend": 1.0}
	if args.has("cam"):
		var c := str(args["cam"]).split(",")
		var pos := Vector3(float(c[0]), float(c[1]), float(c[2]))
		g.rig.override_pose = {"pos": pos, "look": Vector3(float(c[3]), float(c[4]), float(c[5])), "blend": 1.0}
	if args.has("campath"):
		var ct := t - float(args.get("camfrom", "0"))
		var cpose = campath_pose(str(args["campath"]), ct)
		if cpose != null:
			g.rig.override_pose = cpose
		# tools/dev/capture.py cuts the movie from this frame and stops it after --camsecs
		if ct >= 0.0 and not has_meta("cam_start"):
			set_meta("cam_start", true)
			print("CAMSTART frame=%d" % Engine.get_frames_drawn())
		if args.has("camsecs") and ct >= float(args["camsecs"]) and not has_meta("cam_end"):
			set_meta("cam_end", true)
			print("CAMEND frame=%d" % Engine.get_frames_drawn())
			get_tree().quit()
	if args.has("nohud"):
		g.ui.visible = false
		g.marks.hidden = true
		g.cat.hide_marker = true
	if args.has("watch"):
		var e = null
		if args["watch"] == "hound":
			e = g.director.hound.pos if g.director.hound.active else null
		else:
			var th := g.director.get_threat(args["watch"])
			if th:
				e = th.entity()
				if e == null:
					e = th.focus()
		if e != null:
			var ev: Vector3 = e
			var off := Vector3(2.2, 1.4, 1.6)
			var bestd := -1.0
			for k in 12:
				var a := k / 12.0 * TAU
				for dist in [2.4, 1.7, 1.2]:
					var o2 := Vector3(cos(a) * dist, 0.9, sin(a) * dist)
					if not g.house.blocked(ev + Vector3(0, 0.7, 0), ev + o2, HouseBuilder.LAYER_WORLD | HouseBuilder.LAYER_CAMERA):
						if dist > bestd:
							bestd = dist
							off = o2
						break
			if args.has("off"):
				var o := str(args["off"]).split(",")
				off = Vector3(float(o[0]), float(o[1]), float(o[2]))
			g.rig.override_pose = {"pos": ev + off, "look": ev + Vector3(0, 0.7, 0), "blend": 1.0}
	if args.has("houndhunt") and g.director.hound.state == Hound.S.TRACKING:
		g.director.hound._awareness = 2.0   # the hound decays it before checking; clamp keeps it at 1
	if args.has("fear"):
		g.clara.fear = float(args["fear"])
	if args.has("bedpose"):
		# --bedpose=sitUp or --bedpose=lie@3,hug@6 (switch at those seconds)
		var bp := str(args["bedpose"])
		var cur_bp := ""
		for part in bp.split(","):
			var pr := part.split("@")
			if pr.size() == 1 or t >= float(pr[1]):
				cur_bp = pr[0]
		g.clara.force_pose = cur_bp
		g.davi.force_pose = cur_bp
	# --bones[=SEC]: print the bone positions once, at SEC seconds (default 1)
	var bones_t := float(args["bones"]) if args.has("bones") and str(args["bones"]).is_valid_float() else 1.0
	if args.has("bones") and t > bones_t and t < bones_t + 0.05:
		for b in ["head", "neck_01", "spine_03", "spine_02", "pelvis", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r", "upperarm_l", "hand_l", "hand_r"]:
			print("BONE %s %s" % [b, g.clara.model.bone_world(b).origin])
	if args.has("hide"):
		for nm in str(args["hide"]).split(","):
			var n := g.house.find(nm)
			if n:
				n.visible = false
	if args.has("probe") and t > 1.0 and t < 1.03:
		for z in [2.2, 2.8, 3.4]:
			var line := ""
			for x in [0.2, 0.5, 0.8, 1.1, 1.4, 1.7, 2.0, 2.2, 2.4]:
				line += "%.2f " % g.house.ground_height(x, z, 5.5)
			print("PROBE z=%.1f: %s" % [z, line])
	# --claraat=x,y,z,yaw  --clarato=node,node,...  --follow=side|34|front[,dist]: walking checks
	if args.has("claraat") and not has_meta("cat_at"):
		set_meta("cat_at", true)
		var ca := str(args["claraat"]).split(",")
		g.clara.abort()
		g.clara.in_bed = false
		g.clara.asleep = false
		g.clara.show_model()
		g.clara.global_position = Vector3(float(ca[0]), float(ca[1]), float(ca[2]))
		g.clara.yaw = float(ca[3]) if ca.size() > 3 else 0.0
		g.clara.model.snap_pose("stand")
	# --clarahold=book|book_open: Ivone's diary in Clara's hands
	if args.has("clarahold") and t > 0.5 and not has_meta("clarahold"):
		set_meta("clarahold", true)
		g._book_open(g.clara, args["clarahold"] == "book_open")
	if args.has("clarato") and t > 1.0 and not has_meta("walked"):
		set_meta("walked", true)
		var steps := []
		for nid in str(args["clarato"]).split(","):
			if nid.begins_with("wait"):
				steps.append({"t": "wait", "dur": float(nid.substr(4))})
			elif nid.begins_with("gest:"):
				steps.append({"t": "anim", "gesture": nid.substr(5)})
			elif nid.begins_with("clip:"):
				steps.append({"t": "anim", "clip": nid.substr(5)})
			elif nid.begins_with("pose:"):
				steps.append({"t": "pose", "pose": nid.substr(5), "dur": 0.1})
			elif nid.begins_with("spot:"):
				steps.append({"t": "spot", "spot": Layout.spot(nid.substr(5))})
			elif nid.begins_with("say:"):
				steps.append({"t": "say", "text": nid.substr(4), "dur": 3.0})
			elif nid == "kneel":
				steps.append({"t": "kneel_talk", "text": "Oi, {cat}! Tudo bem?", "dur": 2.5})
			else:
				steps.append({"t": "walk", "node": nid, "style": str(args.get("style", "normal"))})
		g.clara.scripted = true
		g.clara.run("devwalk", steps, 5)
		print("WALK %s" % [steps.size()])
	if args.has("holdtune"):
		_hold_tune()
	if args.has("carrytune"):
		_carry_tune()
	if args.has("follow"):
		var fo := str(args["follow"]).split(",")
		var dist := float(fo[1]) if fo.size() > 1 else 2.6
		var fw: Owner = g.davi if str(args.get("followwho", "clara")) == "davi" else g.clara
		var cy := fw.yaw
		var fwd := Vector3(sin(cy), 0, cos(cy))
		var right := Vector3(fwd.z, 0, -fwd.x)
		var dirs := {"side": right, "34": (right + fwd).normalized(), "front": fwd, "back": -fwd}
		var c0 := fw.global_position + Vector3(0, 0.9, 0)
		# the asked angle if the view is clear, else the first clear one (other side, 3/4, back...)
		var order := [dirs.get(fo[0], right), -right, (right + fwd).normalized(), (-right + fwd).normalized(), (right - fwd).normalized(), (-right - fwd).normalized(), -fwd, fwd]
		var pick: Vector3 = c0 + order[0] * dist
		var found := false
		for dd in [dist, dist * 0.7, dist * 0.5]:
			for dv in order:
				var cp: Vector3 = c0 + (dv as Vector3) * dd + Vector3(0, 0.25, 0)
				if not g.house.blocked(c0, cp, HouseBuilder.LAYER_WORLD | HouseBuilder.LAYER_CAMERA):
					pick = cp
					found = true
					break
			if found:
				break
		if not has_meta("fcam"):
			set_meta("fcam", pick)
		var fc: Vector3 = get_meta("fcam")
		fc = fc.lerp(pick, 0.08) if fc.distance_to(pick) < 1.5 else pick
		set_meta("fcam", fc)
		g.rig.override_pose = {"pos": fc, "look": c0, "blend": 1.0}
	# every frame: Clara's pelvis / head heights over her feet, speed, yaw and stance blend (bobs, jitter)
	# --seatlog: once a second, both people's pelvis height over their feet and over the floor, and where it is
	if args.has("seatlog") and not has_meta("seatprobe"):
		set_meta("seatprobe", true)
		print("SEATPROBE desk chair top=%.3f sofa=%.3f sofaR=%.3f" % [g.house.ground_height(2.45, 8.73, 1.2), g.house.ground_height(2.5, 1.6, 1.2), g.house.ground_height(3.08, 1.6, 1.2)])
	if args.has("seatlog") and int(t) != int(t - get_process_delta_time()):
		for o: Owner in [g.clara, g.davi]:
			if o.visible:
				var pw := o.model.bone_world("pelvis").origin
				print("SEAT t=%.0f %s pose=%s state=%s pel_y=%.3f over_feet=%.3f pel=%s pos=%s lift=%.2f deep=%.2f sit_pel=%s pd=%.3f hips_y=%.3f" % [t, o.display_name, o.model.pose, o.model._state, pw.y, pw.y - o.global_position.y, pw, o.global_position, o.model.seat_lift, o.model.seat_deep, o.model.outfits[o.model.cur_outfit].get("sit_pel"), o.model.pelvis_d, o.model.hips_y])
	if args.has("hiplog") and t > 1.0:
		var m: HumanRig = g.clara.model
		print("HIP t=%.3f pel=%.4f head=%.4f spd=%.2f yaw=%.3f stance=%.2f feet=%.2f" % [t, m.bone_world("pelvis").origin.y - g.clara.global_position.y, m.head_world().y - g.clara.global_position.y, m.speed, g.clara.yaw, m._stance_w, m._feet_w])
	if args.has("walklog") and g.clara.task != null:
		_log_t -= get_process_delta_time()
		if _log_t <= 0:
			_log_t = 0.25
			print("WALKLOG t=%.2f pos=%s yaw=%.2f speed=%.2f v=%.2f step=%s pose=%s" % [t, g.clara.global_position, g.clara.yaw, g.clara.model.speed, g.clara._v, g.clara.task["steps"][g.clara.task["idx"]]["t"], g.clara.model.pose])
	if args.has("lap") and g.phase == "afternoon" and g.aft.get("lap_open", false) and not g.aft.get("lap", false) and not has_meta("lapped"):
		var lp = g.lap_point()
		if lp != null:
			set_meta("lapped", true)
			g.cat.teleport(lp, 0.0)
			print("LAP at %s" % lp)
	if args.has("riglog"):
		_log_t -= get_process_delta_time()
		if _log_t <= 0:
			_log_t = 0.5
			var m: HumanRig = g.davi.model if args["riglog"] == "davi" else g.clara.model
			print("RIG t=%.1f pose=%s state=%s shot=%s/%s gest=%s spd=%.2f wsp=%.2f look=%s mood=%s" % [t, m.pose, m._state, m._shot, m.shot_playing(), m._gest, m.speed, m.wj["spine"], m.look_target, m._mood])
	if args.has("tubcheck") and int(t * 2) != int((t - get_process_delta_time()) * 2):
		for f: House.Faucet in g.house.faucets:
			if f.id == "tub":
				print("TUB t=%.1f level=%.2f vis=%s foam=%s pos=%s" % [t, f.level, f.water.visible, (f.water.material_override as ShaderMaterial).get_shader_parameter("foam"), f.water.global_position])
	# --bathtest: day 3, Clara straight into the tub and the door opened (films the hands rising)
	if args.has("bathtest") and t > 1.5 and not has_meta("bathtest"):
		set_meta("bathtest", true)
		var o: Owner = g.clara
		o.abort()
		o.scripted = true
		o.set_outfit_k("bath")
		o.model.set_turban(true)
		o.model.hide_skirt(true)
		o.place(Layout.spot("bathTubIn"))
		o.model.snap_pose("bath")
		g.aft["scene"] = "bath"
		g.aft["bath_wait"] = true
		g.open_bath_door(true)
		print("BATHTEST in the tub")
	# --ending=good|secret|bad|lives: plays that ending (the good ones open with the memory montage)
	if args.has("ending") and t > 2.0 and not has_meta("ending_done"):
		set_meta("ending_done", true)
		g._ending(str(args["ending"]))
	# --esctest: ESC opens the pause, ESC again closes it (real key events through the input pipeline)
	if args.has("esctest"):
		for k in [[2.0, "esc1"], [3.0, "esc2"]]:
			if t > k[0] and not has_meta(k[1]):
				set_meta(k[1], true)
				for pressed in [true, false]:
					var ev := InputEventKey.new()
					ev.keycode = KEY_ESCAPE
					ev.physical_keycode = KEY_ESCAPE
					ev.pressed = pressed
					Input.parse_input_event(ev)
		if t > 2.5 and not has_meta("esc_l1"):
			set_meta("esc_l1", true)
			print("ESCTEST after 1st ESC mode=%s overlay=%s" % [g.mode, g.ui.overlay_open])
		if t > 3.5 and not has_meta("esc_l2"):
			set_meta("esc_l2", true)
			print("ESCTEST after 2nd ESC mode=%s overlay=%s" % [g.mode, g.ui.overlay_open])
			get_tree().quit()
	# --ruletest: every rule of tonight's things of Ivone, done by hand: fished out of the drain / the
	# mailbox, the room's light put out (dark), washed (wash), one wrong order first on night 6; logs
	# each step and RELICTEST PASS when the night is won
	if args.has("ruletest") and g.phase == "night" and t > 3.0:
		_relic_test()
	if args.has("ruletest") and has_meta("rt_started") and (g._winning or g.phase != "night") and not has_meta("rt_done"):
		set_meta("rt_done", true)
		print("RELICTEST PASS night %d (phase=%s)" % [g.day, g.phase])
		get_tree().quit()
	# --dolltarget=davi|clara: the Doll goes after that person; logs where it is and their fear
	if args.has("dolltarget"):
		var dl: DollThreat = g.director.doll
		if t > 1.0 and not has_meta("dt0"):
			set_meta("dt0", true)
			dl.target = g.davi if args["dolltarget"] == "davi" else g.clara
			dl._goal_id = ""
		_log_t -= get_process_delta_time()
		if _log_t <= 0.0 and has_meta("dt0"):
			_log_t = 2.0
			print("DOLL t=%.0f stage=%d at=%s (%s) target=%s in %s bed=%s fear=%.0f near=%s" % [t, dl.stage, dl.item.pos, Layout.room_at(dl.item.pos), dl.target.display_name, Layout.room_at(dl.target.global_position), dl.target.in_bed, dl.target.fear, dl._near_target()])
	if args.has("dirlog"):
		g.director.dev_log = true
	if args.has("shadowtest"):
		_shadow_test()
	if args.has("peekat"):
		_peek_test()
	# --playbot: a careful player who never defends: item i is taken at 15+PACE*i s and delivered 20 s
	# later (teleports); logs the Director every 10 s. --pace=SEC (default 40). For pacing, not for skill.
	if args.has("playbot") and g.phase == "night" and g.mode == "play":
		var pace := float(args.get("pace", "40"))
		var items: Array = g._mission
		var bs: Dictionary = get_meta("bot", {"taken": {}, "done": {}, "log": 0.0, "t0": t, "ritual": false})
		set_meta("bot", bs)
		var bt: float = t - float(bs["t0"])
		for i in items.size():
			var m: Dictionary = items[i]
			var c: PropSystem.Carryable = m["c"]
			if not bs["taken"].has(i) and bt > 15.0 + pace * i and g.cat.carrying == null:
				bs["taken"][i] = bt
				g.cat.teleport(c.pos + Vector3(0.3, 0, 0), 0.0)
				g.cat.carrying = c
				c.carried = true
				print("BOT t=%.0f takes item %d/%d (%s)" % [bt, i + 1, items.size(), c.name])
			elif bs["taken"].has(i) and not bs["done"].has(i) and bt > float(bs["taken"][i]) + 20.0 and g.cat.carrying == c:
				bs["done"][i] = bt
				g.cat.teleport(g.house.ritual_center + Vector3(0.8, 0, 0), 0.0)
				if m["r"] != null:
					g.deliver_relic()
				else:
					g.cat.carrying = null
					c.carried = false
					g.flags["clues"][m["id"]] = {"x": 0.0, "y": 0.0, "z": 0.0, "on_circle": true}
					g.on_ritual_item()
				print("BOT t=%.0f delivers item %d/%d" % [bt, i + 1, items.size()])
		if g.day == Config.LAST_NIGHT and not bs["ritual"] and bs["done"].size() == items.size():
			bs["ritual"] = true
			g.complete_ritual()
			print("BOT t=%.0f ritual complete" % bt)
		if bt - float(bs["log"]) >= 10.0:
			bs["log"] = bt
			var dr: Director = g.director
			var ids := []
			for th: Threat in dr.all:
				if th.enabled and th.stage > 0:
					ids.append("%s:%d%s" % [th.threat_id, th.stage, "*" if th.hunting_cat else ""])
			if dr.hound.active:
				ids.append("hound:%s" % ("hunt" if dr.hound.hunting else "walk"))
			print("BOT t=%.0f %s I=%.2f/%.2f P=%.2f cyc=%d lives=%d fear=%.0f/%.0f out=%s" % [bt, dr.phase(), dr.intensity, dr.ceiling(), dr.progress, dr.cycle, g.lives, g.clara.fear, g.davi.fear, ids])
	# --ritualtest: night 7, the five things get to the circle one by one (as the game would see it)
	if args.has("ritualtest") and t > 1.0 + 0.5 * int(get_meta("rt_n", 0)) and int(get_meta("rt_n", 0)) < 7:
		var rn: int = get_meta("rt_n", 0)
		set_meta("rt_n", rn + 1)
		if rn < 2:
			var rr: Dictionary = g.relics[rn]
			rr["done"] = true
			g.relics_done += 1
			(rr["c"] as PropSystem.Carryable).place(g.house.ritual_center + Vector3(1.25, 0.005, rn))
		elif rn < 5:
			var cid: String = Game.CLUES[rn - 2]
			g.flags["clues"][cid] = {"x": 0.0, "y": 0.0, "z": 0.0, "on_circle": true}
			g.on_ritual_item()
		print("RITUAL step %d: taken=%d P=%.2f ready=%s thing=%d" % [rn, g.mission_taken(), g.mission_progress(), g.ritual_ready(), g.director.thing.stage])
		if rn == 5:
			g.complete_ritual()
			print("RITUAL complete: winning=%s" % g._winning)
	if args.has("killthing") and t > float(args["killthing"]) and not has_meta("thing_killed"):
		set_meta("thing_killed", true)
		var th_k: ThingThreat = g.director.get_threat("thing")
		th_k.kill()
		print("THING killed at t=%.1f" % t)
	if args.has("steplog"):
		for o: Owner in [g.clara, g.davi]:
			var key := "-"
			if o.task != null and o.task["idx"] < o.task["steps"].size():
				var st: Dictionary = o.task["steps"][o.task["idx"]]
				key = "%s#%d %s %s" % [o.task["name"], o.task["idx"], st["t"], str(st.get("text", st.get("pose", st.get("node", st.get("gesture", st.get("clip", ""))))))]
			if get_meta("step_" + o.display_name, "") != key:
				set_meta("step_" + o.display_name, key)
				print("STEP t=%.1f %s %s phase=%s pos=%s" % [t, o.display_name, key, g.phase, o.global_position])
	if args.has("nofade"):
		g.fx["fade"] = 0.0
		g.fx["fade_target"] = 0.0


const CARRY_ITEMS := ["toy", "chave", "porao_key", "foto", "coleira", "yarn", "nightlight", "doll", "relic:page", "relic:tape", "relic:ring", "relic:pin", "relic:clothes", "relic:letter"]


## --carrytune=all|ID,... [--carryfile=FILE.json] --tunedir=DIR [--views=side,34,front,back] [--dist=M]:
## the cat holds each thing in turn (1 s to settle), shot close around its head from every view
## (DIR/ID_view.png); FILE is {grip kind: [[x,y,z], [rx,ry,rz]]} over Carry.GRIPS. Quits after the last
func _carry_tune() -> void:
	if not has_meta("ct"):
		var items: Array = CARRY_ITEMS if str(args["carrytune"]) in ["1", "all"] else Array(str(args["carrytune"]).split(","))
		set_meta("ct", items)
		set_meta("ct_i", -1)
		set_meta("ct_t", 0.0)
		if args.has("carryfile"):
			var f := FileAccess.open(str(args["carryfile"]), FileAccess.READ)
			var d: Dictionary = JSON.parse_string(f.get_as_text())
			for k in d:
				var v: Array = d[k]
				Carry.tune[k] = [Vector3(v[0][0], v[0][1], v[0][2]), Vector3(v[1][0], v[1][1], v[1][2])]
				if v.size() > 2:
					Carry.tune[k].append(Vector3(v[2][0], v[2][1], v[2][2]))
	var items: Array = get_meta("ct")
	var views := str(args.get("views", "side,34,front,back")).split(",")
	if t < float(args.get("shotfrom", "2")):
		return
	var tt: float = get_meta("ct_t") + get_process_delta_time()
	set_meta("ct_t", tt)
	var step := 1.0 + 0.3 * views.size()
	var i: int = get_meta("ct_i")
	var want := int(tt / step)
	if want != i:
		var prev: PropSystem.Carryable = g.cat.carrying
		if prev:
			prev.carried = false
			g.cat.carrying = null
			prev.node.global_position = Vector3(0, -50, 0)
		if want >= items.size():
			get_tree().quit()
			return
		i = want
		set_meta("ct_i", i)
		var cid: String = items[i]
		var c: PropSystem.Carryable
		if cid.begins_with("relic:"):
			c = PropSystem.Carryable.new()
			c.id = "relic_dev"
			c.node = Node3D.new()
			g.house.add_child(c.node)
			c.node.add_child(Carry.make_relic(cid.substr(6)))
			c.node.set_meta("grip", cid.substr(6))
		else:
			c = g.house.carryables.get(cid)
		c.node.visible = true
		g.cat.carrying = c
		c.carried = true
		var gk := str(c.node.get_meta("grip", c.id))
		print("CARRYTUNE %d %s grip=%s" % [i, cid, Carry.tune.get(gk, Carry.GRIPS.get(gk, "-"))])
	var k := clampi(int((tt - i * step - 1.0) / 0.3), 0, views.size() - 1)
	# angles from the snout (the head's real facing), 90 = the cat's left; a long lens, close on the mouth
	var ang := {"side": 90.0, "34": 40.0, "front": 0.0, "back": 145.0, "rside": -90.0}
	var mo: Vector3 = g.cat.rig.mouth_world()
	var fw: Vector3 = mo - g.cat.rig.head_world()
	var a := atan2(fw.x, fw.z) + deg_to_rad(float(ang.get(views[k], 90.0)))
	var dd := float(args.get("dist", "1.1"))
	g.rig.override_pose = {"pos": mo + Vector3(sin(a) * dd, 0.12, cos(a) * dd), "look": mo + Vector3(0, -0.07, 0), "blend": 1.0, "fov": 26.0}
	var ks := int((tt - i * step - 1.0) / 0.3 - 0.5)
	if ks >= 0 and ks < views.size() and ks == k and not has_meta("ct_%d_%d" % [i, ks]):
		set_meta("ct_%d_%d" % [i, ks], true)
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(args["tunedir"])
		img.save_png(str(args["tunedir"]).path_join("%s_%s.png" % [str(items[i]).replace(":", "_"), views[ks]]))


## --holdtune: each try in the file gets 1.2 s to settle, then a shot from every view (the follow camera
## jumps there); quits after the last
func _hold_tune() -> void:
	if not has_meta("ht"):
		var f := FileAccess.open(str(args["holdtune"]), FileAccess.READ)
		set_meta("ht", JSON.parse_string(f.get_as_text()))
		set_meta("ht_i", -1)
		set_meta("ht_t", 0.0)
	var tries: Array = get_meta("ht")
	var views := str(args.get("views", "front,34,side")).split(",")
	var i: int = get_meta("ht_i")
	if t < float(args.get("shotfrom", "3")):
		return
	var tt: float = get_meta("ht_t") + get_process_delta_time()
	set_meta("ht_t", tt)
	var step := 1.2 + 0.4 * views.size()
	var want := int(tt / step)
	if want != i:
		if want >= tries.size():
			get_tree().quit()
			return
		i = want
		set_meta("ht_i", i)
		var tune := {}
		g.clara.model.grip_tune = {}
		for kind in tries[i]:
			if kind == "_grip":
				g.clara.model.grip_tune = tries[i][kind]
				continue
			var arms := {}
			for j in tries[i][kind]:
				var v: Array = tries[i][kind][j]
				arms[j] = Vector3(v[0], v[1], v[2])
			tune[kind] = arms
		g.clara.model.hold_tune = tune
		print("HOLDTUNE %d %s" % [i, JSON.stringify(tries[i])])
	var k := int((tt - i * step - 1.2) / 0.4)
	if k >= 0 and k < views.size() and not has_meta("ht_%d_%d" % [i, k]):
		set_meta("ht_%d_%d" % [i, k], true)
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(args["tunedir"])
		img.save_png(str(args["tunedir"]).path_join("t%d_%s.png" % [i, views[k]]))
	var kv := clampi(int((tt - i * step - 1.0) / 0.4), 0, views.size() - 1)
	var m: HumanRig = g.clara.model
	if args.has("tunefocus") and m.held.has("hand") and is_instance_valid(m.held["hand"][0]):
		# close on what she holds: front (facing her), reader (over her shoulder), side, under
		var c: Vector3 = (m.held["hand"][0] as Node3D).global_position
		var fw := Vector3(sin(g.clara.yaw), 0, cos(g.clara.yaw))
		var rt := Vector3(fw.z, 0, -fw.x)
		var dirs := {"front": fw + Vector3(0, 0.35, 0), "reader": -fw * 0.15 + Vector3(0, 1.0, 0) + rt * 0.55, "side": rt + Vector3(0, 0.2, 0), "under": fw * 0.8 + Vector3(0, -0.45, 0) - rt * 0.3}
		# pages: straight onto the open pages (from between the book and her face)
		dirs["pages"] = (m.held["hand"][0] as Node3D).global_transform.basis.y
		var dv: Vector3 = dirs.get(views[kv], fw)
		# the pages view starts inside her sweater: clip it away with the near plane
		g.cam.near = float(args.get("dist", "0.6")) - 0.1 if views[kv] == "pages" else 0.05
		var cp: Vector3 = c + dv.normalized() * float(args.get("dist", "0.6"))
		if views[kv] == "eyes":
			# what she sees: from just in front of her face (the head clipped by the near plane)
			cp = m.head_world() + Vector3(0, 0.12, 0) - fw * 0.02
			g.cam.near = 0.3
		g.rig.override_pose = {"pos": cp, "look": c, "blend": 1.0}
	else:
		args["follow"] = "%s,%s" % [views[kv], args.get("dist", "1.4")]
		remove_meta("fcam")


# ---------------------------------------------------------------------- afternoon autoplay and e2e


## the cat plays the afternoon (with --steplog or --e2e): eats when Clara waits by the bowl, brings the
## padlock key down to her, lies down with her once she is in bed. Each action waits a moment after its
## condition shows up, so the steps read in order in the log.
func _aft_play() -> void:
	var a := g.aft
	if a.is_empty() or a.get("ending", false) or not g.controls:
		return
	var c := g.cat
	var o := g.clara
	if a.get("wait_eat", false) and not a["fed"] and not g.is_eating() and _aft_ready("eat", 2.0):
		c.teleport(Game.BOWL_POS + Vector3(0.0, 0, 0.45), PI)
		g.eat()
		print("AFT t=%.1f ate (fed=%s)" % [t, a["fed"]])
	var key: PropSystem.Carryable = g.house.carryables.get(Game.PORAO_KEY)
	if key and a.get("key_asked", false) and not a.get("key_given", false) and not a.get("key_missed", false):
		if c.carrying != key and key.enabled and key.node.visible and _aft_ready("key_pick", 2.0):
			c.teleport(key.pos + Vector3(0.35, -key.pos.y, 0.0), -PI / 2)
			c.carrying = key
			key.carried = true
			print("AFT t=%.1f picked up the key at %s" % [t, key.pos])
		elif c.carrying == key and a.get("wait_key", false) and o.task != null and _aft_ready("key_give", 1.5):
			var fwd := Vector3(sin(o.yaw), 0, cos(o.yaw))
			c.teleport(o.global_position + fwd * 0.7, o.yaw + PI)
			g.give_key()
			print("AFT t=%.1f gave the key to Clara at %s (given=%s)" % [t, o.global_position, a["key_given"]])
	# the private rooms: --intrude walks the cat in once (it must be put out); the bath door is
	# scratched, Clara is taken out of the tub once the hands are up
	if a.get("private", "") != "" and args.has("intrude") and not has_meta("intruded_" + str(a["private"])):
		set_meta("intruded_" + str(a["private"]), true)
		var rc := {"banheiro_cima": Vector3(9.5, 3, 7.9), "quarto": Vector3(2.9, 3, 4.35)}
		c.teleport(rc.get(a["private"], c.global_position), 0.0)
		print("AFT t=%.1f cat walked into the private %s" % [t, a["private"]])
	if a.get("private", "") != "" and has_meta("intruded_" + str(a["private"])) and not has_meta("intrude_log_" + str(a["private"])) and Layout.room_at(c.global_position) != a["private"]:
		set_meta("intrude_log_" + str(a["private"]), true)
		print("AFT t=%.1f cat put out of %s, now in %s at %s" % [t, a["private"], Layout.room_at(c.global_position), c.global_position])
	if a.get("bath_wait", false) and _aft_ready("bath_door", 3.0):
		c.teleport(Vector3(7.1, 3, 9.1), PI / 2)
		g.open_bath_door(true)
		print("AFT t=%.1f scratched the bathroom door (bathing=%s)" % [t, a["bathing"]])
	if a.get("bathing", false) and float(a.get("bath_t", 0.0)) > 8.0 and _aft_ready("bath_out", 0.5):
		c.teleport(Vector3(10.2, 3, 8.6), PI / 2)
		print("AFT t=%.1f hands alpha=%.2f at %s; getting Clara out" % [t, g.director.drowner.hands.alpha, g.director.drowner.hands.global_position])
		g.end_bath(true)
	if o.in_bed and a.get("can_skip", false) and c.mode != "purr" and _aft_ready("bed", 2.0):
		c.teleport(Layout.spot_pos(o.cfg["bedside_spot"]), PI / 2)
		g.toggle_purr(o)
		print("AFT t=%.1f lay down with Clara (mode=%s)" % [t, c.mode])


func _aft_ready(k: String, delay: float) -> bool:
	if not _aft_seen.has(k):
		_aft_seen[k] = t
	if t - float(_aft_seen[k]) < delay:
		return false
	_aft_seen.erase(k)
	return true


const E2E_LIMIT := {"afternoon": 30.0, "eat": 200.0, "key": 360.0, "bed": 420.0, "night": 60.0, "relics": 120.0, "dawn": 30.0}


func _e2e_go(stage: String) -> void:
	_e2e_stage = stage
	_e2e_t = 0.0
	print("E2E t=%.1f stage %s (phase=%s mode=%s)" % [t, stage, g.phase, g.mode])


func _e2e_fail(why: String) -> void:
	var st := "-"
	if g.clara.task != null and g.clara.task["idx"] < g.clara.task["steps"].size():
		var s: Dictionary = g.clara.task["steps"][g.clara.task["idx"]]
		st = "%s#%d %s" % [g.clara.task["name"], g.clara.task["idx"], s["t"]]
	print("E2E FAIL at stage %s after %.0f s: %s | phase=%s mode=%s clara=%s step=%s in_bed=%s cat=%s mode=%s lives=%d" % [_e2e_stage, _e2e_t, why, g.phase, g.mode, g.clara.global_position, st, g.clara.in_bed, g.cat.global_position, g.cat.mode, g.lives])
	set_meta("e2e_over", true)
	get_tree().quit(1)


## --e2e=1: day 1 afternoon (eat, key, lie down) then night 1 (Ivone's things to the circle) to dawn
func _e2e(dt: float) -> void:
	if has_meta("e2e_over"):
		return
	_e2e_t += dt
	if _e2e_t > float(E2E_LIMIT.get(_e2e_stage, 120.0)):
		_e2e_fail("timed out")
		return
	if g.phase == "afternoon":
		_aft_play()
	match _e2e_stage:
		"afternoon":
			if g.phase == "afternoon" and g.clara.task != null:
				_e2e_go("eat")
		"eat":
			if g.aft.get("fed", false):
				_e2e_go("key")
			elif g.aft.get("key_asked", false):
				_e2e_fail("Clara moved on to the key without the cat eating")
		"key":
			if g.aft.get("key_given", false):
				_e2e_go("bed")
			elif g.aft.get("key_missed", false):
				_e2e_fail("Clara gave up waiting for the key")
		"bed":
			if g.phase == "night":
				_e2e_go("night")
			elif g.aft.get("ending", false) and _e2e_t > 380.0:
				_e2e_fail("the afternoon ended but the night did not start")
		"night":
			if g.phase == "night" and g.mode == "play" and g.relics.size() > 0:
				print("E2E night %d: %d things of Ivone, lives=%d" % [g.night, g.relics.size(), g.lives])
				_e2e_go("relics")
		"relics":
			if g.phase != "night":
				_e2e_fail("left the night before dawn")
				return
			if g._winning:
				_e2e_go("dawn")
				return
			if _e2e_t > 2.0 and g.cat.mode == "free" and g.controls and int(_e2e_t / 1.5) != int((_e2e_t - dt) / 1.5):
				for r in g.relics:
					if r["done"]:
						continue
					var c: PropSystem.Carryable = r["c"]
					g.cat.teleport(c.pos + Vector3(0.3, 0, 0), 0.0)
					g.cat.carrying = c
					c.carried = true
					g.cat.teleport(g.house.ritual_center + Vector3(0.8, 0, 0), 0.0)
					g.deliver_relic()
					print("E2E t=%.1f delivered %s (%d/%d)" % [t, c.name, g.relics_done, g.relics.size()])
					break
		"dawn":
			if g.mode == "over":
				print("E2E PASS: afternoon 1 (eat, key, bed) and night 1 to dawn, lives=%d lost=%d, t=%.1f" % [g.lives, g.lost_tonight, t])
				set_meta("e2e_over", true)
				get_tree().quit(0)


func _relic_test() -> void:
	set_meta("rt_started", true)
	_log_t -= get_process_delta_time()
	if _log_t > 0.0:
		return
	_log_t = 0.6
	if g.cat.carrying == null:
		if g.day == Story.RELIC_ORDER_NIGHT and not has_meta("rt_wrong"):
			# the last one first: the circle must refuse it
			set_meta("rt_wrong", true)
			var rl: Dictionary = g.relics[g.relics.size() - 1]
			var cw: PropSystem.Carryable = rl["c"]
			g.cat.carrying = cw
			cw.carried = true
			var before := g.relics_done
			g.deliver_relic()
			print("RT wrong order: refused=%s" % (g.cat.carrying == cw and g.relics_done == before))
			g.drop_carried()
			return
		for r in g.relics:
			if r["done"]:
				continue
			var c: PropSystem.Carryable = r["c"]
			if not r["found"]:
				g.take_hidden_relic(r)
				print("RT took the hidden one (%s) carrying=%s" % [r["rule"], g.cat.carrying == c])
				return
			if r["rule"] == "dark" and not c.enabled:
				var l = g.house.lights.by_room.get(str(r["room"]))
				print("RT dark: %s lit=%s enabled=%s" % [r["room"], g.house.lights.is_room_lit(str(r["room"])), c.enabled])
				if l:
					l.set_on(false)
				return
			g.cat.carrying = c
			c.carried = true
			print("RT picked %s rule=%s dirty=%s" % [c.name, r["rule"], r.get("dirty", false)])
			return
	else:
		var rr: Dictionary = g.relic_of(g.cat.carrying)
		if rr.get("dirty", false):
			var before_done := g.relics_done
			g.deliver_relic()
			print("RT dirty refused=%s" % (g.relics_done == before_done))
			for f: House.Faucet in g.house.faucets:
				if f.id == "coz":
					g.wash_carried(f)
			print("RT washed dirty=%s" % rr.get("dirty", false))
			return
		g.deliver_relic()
		print("RT delivered %d/%d" % [g.relics_done, g.relics.size()])


## --campath: the camera pose at time tt along FILE's keys (null before loading / with no keys). Each
## segment eases by the key it ends on; "rel" anchors pos/look to an actor so the move follows it.
var _campaths := {}
func campath_pose(file: String, tt: float):
	if not _campaths.has(file):
		var txt := FileAccess.get_file_as_string(file)
		var d = JSON.parse_string(txt)
		if d == null:
			push_error("campath: cannot read " + file)
			_campaths[file] = {}
		else:
			_campaths[file] = d if d is Dictionary else {"keys": d}
	var cp: Dictionary = _campaths[file]
	var keys: Array = cp.get("keys", [])
	if keys.is_empty():
		return null
	var i := 0
	while i < keys.size() - 1 and tt > float(keys[i + 1].get("t", 0.0)):
		i += 1
	var a: Dictionary = keys[i]
	var b: Dictionary = keys[mini(i + 1, keys.size() - 1)]
	var ta := float(a.get("t", 0.0))
	var tb := float(b.get("t", 0.0))
	var k := 0.0 if tb <= ta else clampf((tt - ta) / (tb - ta), 0.0, 1.0)
	if tt < ta:
		k = 0.0
	match str(b.get("ease", "inout")):
		"linear":
			pass
		"in":
			k = k * k
		"out":
			k = 1.0 - (1.0 - k) * (1.0 - k)
		_:
			k = k * k * (3.0 - 2.0 * k)
	var pa := _cam_point(a, "pos", cp)
	var pb := _cam_point(b, "pos", cp)
	var la := _cam_point(a, "look", cp)
	var lb := _cam_point(b, "look", cp)
	var fa := float(a.get("fov", Settings.g("fov")))
	var fb := float(b.get("fov", fa))
	return {"pos": pa.lerp(pb, k), "look": la.lerp(lb, k), "blend": 1.0,
		"fov": lerpf(fa, fb, k),
		"roll": deg_to_rad(lerpf(float(a.get("roll", 0.0)), float(b.get("roll", a.get("roll", 0.0))), k)),
		"hand": lerpf(float(a.get("hand", 0.0)), float(b.get("hand", a.get("hand", 0.0))), k)}


func _cam_point(key: Dictionary, field: String, cp: Dictionary) -> Vector3:
	var v: Array = key.get(field, [0, 0, 0])
	var p := Vector3(float(v[0]), float(v[1]), float(v[2]))
	var rel := str(key.get("rel", cp.get("rel", "")))
	match rel:
		"cat":
			p += g.cat.global_position
		"clara":
			p += g.clara.global_position
		"davi":
			p += g.davi.global_position
	return p
