extends Node
## Clara clipping survey (autopilot --clarasurvey=OUTDIR): every situation she appears in, in every
## outfit, frozen at one instant (Engine.time_scale 0) and shot from several sides with the same
## cameras every run, so a fix can be shot again before / after.
##   --cases=a,b,...      only these cases (ids below; a trailing * matches a prefix: hold_*, g_*)
##   --outfits=day,night,bath
##   --views=front,34,side,back34   override every case's own views
##   --armfix=FILE.json   arm fixes to try, over HumanRig.ARM_FIX (key -> side -> arm/fore -> [out, fwd, up])
##   --bones=a,b          print those bones' world heights at the shot (SURVEY BONES lines)
##   --posefix=FILE.json  pose numbers to try, written into HumanRig.POSES (pose -> joint -> [x,y,z])
##   --who=davi           shoot Davi instead (shared code; needs --day=4 or later)
##   --layerback=M        Clara's trousers / skirt depth push (0 = off) to compare
##   --hidehair           diagnosis: the hair hidden in the shots (a face against the knees)
##   --hidebody           diagnosis: the body mesh hidden in the shots (what pokes through the clothes)
##   --close=BONE[,DIST]  close-up: the camera centred on that bone (spine_02 chest, pelvis hips,
##                        hand_r, calf_l...) at DIST m (0.75), fov 40
## Shots: OUTDIR/<outfit>/<case>_<view>.png; one "SURVEY <outfit> <case>" line per case, "SURVEY DONE".

var ap: Node
var g: Game
var out := ""
var queue: Array = []        # [outfit, case id]
var cur := {}
var outfit := ""
var stage := "next"          # next | settle | shots
var timer := 0.0
var views: Array = []
var view_i := 0
var frames := 0
var only_views: Array = []

const OPEN := Vector2(3.5, -3.2)        # front yard, open all round (x, z; the height is the ground's)
const OPEN_YAW := -PI / 2               # facing the low afternoon sun (lit from the front)
const GEST_ORDER := ["glasses", "hair", "yawn", "stretch", "hug_self", "look_back", "sneeze", "key_turn", "switch", "pat", "pull", "wave", "hat_tip", "cross_arms"]

# frame: [look-at height over her root, distance, fov]
const FRAMES := {"full": [0.85, 2.3, 50.0], "upper": [1.15, 1.55, 45.0], "seat": [0.75, 1.9, 50.0], "bed": [0.25, 1.9, 50.0], "bath": [0.2, 1.15, 55.0], "low": [0.45, 1.6, 50.0]}


func _cases() -> Dictionary:
	var c := {
		"stand": {"setup": _stand.bind("stand"), "settle": 2.0, "frame": "full", "views": ["front", "34", "side", "back34"]},
		"walk_a": {"setup": _walk, "settle": 1.7, "frame": "full", "views": ["front", "34", "side", "back34"]},
		"walk_b": {"setup": _walk, "settle": 2.05, "frame": "full", "views": ["front", "34", "side", "back34"]},
		"stairs_a": {"setup": _stairs, "settle": 2.4, "frame": "full", "views": ["front_hi", "34", "back", "back34"]},
		"stairs_b": {"setup": _stairs, "settle": 3.6, "frame": "full", "views": ["front_hi", "34", "back", "back34"]},
		"sofa": {"setup": _sofa, "settle": 7.0, "frame": "seat", "views": ["front", "34", "34l", "top"]},
		"sofa_lap": {"setup": _sofa.bind("lap"), "settle": 9.0, "frame": "seat", "views": ["front", "34", "34l", "top"]},
		"sofa_book_open": {"setup": _sofa.bind("book_open"), "settle": 8.0, "frame": "seat", "views": ["front", "34", "34l", "top"]},
		"bowl": {"setup": _bowl, "settle": 6.0, "frame": "low", "views": ["back", "back34", "back34l", "top"]},
		"bed_lie": {"setup": _bed.bind("lie"), "settle": 3.0, "frame": "bed", "views": ["top", "foot", "side", "34"]},
		"bed_lieSide": {"setup": _bed.bind("lieSide"), "settle": 3.0, "frame": "bed", "views": ["top", "foot", "side", "34"]},
		"bed_sitUp": {"setup": _bed.bind("sitUp"), "settle": 3.0, "frame": "bed", "views": ["top", "foot", "side", "34"]},
		"bed_hug": {"setup": _bed.bind("hug"), "settle": 3.0, "frame": "bed", "views": ["top", "foot", "side", "34"]},
		"bed_cry": {"setup": _bed.bind("cry"), "settle": 3.0, "frame": "bed", "views": ["top", "foot", "side", "34"]},
		"bath": {"setup": _bath, "settle": 3.0, "frame": "bath", "views": ["top", "hifoot", "hi34", "hi34l"]},
		"phone": {"setup": _stand.bind("phone"), "settle": 2.5, "frame": "upper", "views": ["front", "34", "side", "back34"]},
		"fold": {"setup": _stand.bind("fold"), "settle": 2.5, "frame": "upper", "views": ["front", "34", "side", "back34"]},
	}
	# the rest of what she does in the game (left out of the first survey)
	for k in ["talk", "reach", "drink", "carry", "pet"]:
		c[k] = {"setup": _stand.bind(k), "settle": 2.5, "frame": "full" if k == "pet" else "upper", "views": ["front", "34", "side", "back34"]}
	c["sofa_talk"] = {"setup": _sofa.bind("talk"), "settle": 7.0, "frame": "seat", "views": ["front", "34", "34l", "top"]}
	c["sofa_sitting"] = {"setup": _sofa, "settle": 3.6, "frame": "seat", "views": ["front", "34", "34l", "side"]}
	c["stairs_down_a"] = {"setup": _stairs_down, "settle": 2.2, "frame": "full", "views": ["front_hi", "34", "back", "back34"]}
	c["stairs_down_b"] = {"setup": _stairs_down, "settle": 3.3, "frame": "full", "views": ["front_hi", "34", "back", "back34"]}
	for k in ["box", "suitcase", "doll", "book", "book_open", "cushion", "backpack"]:
		c["hold_" + k] = {"setup": _hold.bind(k), "settle": 2.5, "frame": "upper", "views": ["front", "34", "side", "back34"]}
	for k in GEST_ORDER:
		var keys: Array = HumanRig.GESTURES[k]["keys"]
		# frozen at the gesture's held key (the last one, or the middle of a long one)
		var at: float = float(keys[keys.size() - 1][0]) if keys.size() <= 2 else float(keys[1][0])
		c["g_" + k] = {"setup": _gesture.bind(k), "settle": at + 0.12, "frame": "upper", "views": ["front", "34", "side", "back34"]}
	return c


func _ready() -> void:
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS


## the person shot: Clara, or Davi with --who=davi (from day 4, when he is in the house)
func _who() -> Owner:
	return g.davi if str(ap.args.get("who", "clara")) == "davi" and g.davi != null else g.clara


func start(dir: String) -> void:
	out = dir
	if ap.args.has("layerback"):
		# --layerback=M: the inner layer's depth push (HumanRig.LAYER_BACK) on Clara's trousers / skirt; 0 = off
		for k in _who().model.outfits:
			for mi in (_who().model.outfits[k]["root"] as Node).find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				for si in m.get_surface_override_material_count():
					var sm := m.get_surface_override_material(si) as ShaderMaterial
					if sm and float(sm.get_shader_parameter("layer_back") if sm.get_shader_parameter("layer_back") != null else 0.0) > 0.0:
						while sm:
							sm.set_shader_parameter("layer_back", float(ap.args["layerback"]))
							sm = sm.next_pass as ShaderMaterial
	if ap.args.has("posefix"):
		# --posefix=FILE.json: {pose: {joint: [x, y, z] | hips_y}} written into HumanRig.POSES
		var pj = JSON.parse_string(FileAccess.get_file_as_string(str(ap.args["posefix"])))
		if pj is Dictionary:
			for pn in pj:
				for jn in pj[pn]:
					var v = pj[pn][jn]
					HumanRig.POSES[pn][jn] = Vector3(v[0], v[1], v[2]) if v is Array else float(v)
		print("SURVEY posefix ", pj)
	if ap.args.has("armfix"):
		# --armfix=FILE.json: {key: {"l"/"r": {"arm"/"fore": [out, fwd, up]}}} over HumanRig.ARM_FIX
		var j = JSON.parse_string(FileAccess.get_file_as_string(str(ap.args["armfix"])))
		HumanRig.arm_fix_tune = j if j is Dictionary else {}
		print("SURVEY armfix ", HumanRig.arm_fix_tune)
	if ap.args.has("skinmask"):
		# --skinmask=0|1|2: the skin under the clothes drawn / cut (the game) / painted red
		HumanRig.skin_mask_mode = float(ap.args["skinmask"])
		for k in _who().model.outfits:
			var body: MeshInstance3D = _who().model.outfits[k].get("body")
			if body == null:
				continue
			for si in body.mesh.get_surface_count():
				var sm := body.get_surface_override_material(si) as ShaderMaterial
				while sm and body.mesh.surface_get_format(si) & Mesh.ARRAY_FORMAT_TEX_UV2:
					sm.set_shader_parameter("skin_mask", HumanRig.skin_mask_mode)
					sm = sm.next_pass as ShaderMaterial
	var outfits := str(ap.args.get("outfits", "day,night,bath")).split(",")
	var want := str(ap.args.get("cases", "")).split(",", false)
	if ap.args.has("views"):
		only_views = Array(str(ap.args["views"]).split(","))
	var all := _cases()
	for o in outfits:
		for id in all:
			if want.is_empty() or _wanted(id, want):
				queue.append([o, id])
	print("SURVEY %d shots-sets to %s" % [queue.size(), out])


func _wanted(id: String, want: PackedStringArray) -> bool:
	for w in want:
		if w == id or (w.ends_with("*") and id.begins_with(w.trim_suffix("*"))):
			return true
	return false


func _process(dt: float) -> void:
	if g == null or out == "" or g.mode != "play":
		return
	var o: Owner = _who()
	match stage:
		"next":
			Engine.time_scale = 1.0
			if queue.is_empty():
				print("SURVEY DONE")
				get_tree().quit()
				return
			var q: Array = queue.pop_front()
			outfit = q[0]
			cur = _cases()[q[1]]
			cur["id"] = q[1]
			_reset(o)
			(cur["setup"] as Callable).call()
			timer = 0.0
			stage = "settle"
		"settle":
			timer += dt
			if not str(cur["id"]).begins_with("g_"):
				o.model._idle_t = 0.0      # no random idle gesture in the middle of a shot
			if cur.has("hold_fn"):
				(cur["hold_fn"] as Callable).call()
			if timer >= float(cur["settle"]):
				Engine.time_scale = 0.0
				if ap.args.has("bones"):
					# --bones=a,b: their world heights at the shot (and the root's), to measure against furniture
					var hs := []
					for b in str(ap.args["bones"]).split(","):
						hs.append("%s %.3f" % [b, o.model.bone_world(b).origin.y])
					print("SURVEY BONES %s %s root %.3f %s" % [outfit, cur.get("id", ""), o.global_position.y, " ".join(hs)])
				if ap.args.has("hidehair"):
					for mi in (o.model.outfits[o.model.cur_outfit]["root"] as Node).find_children("*_hair", "MeshInstance3D", true, false):
						(mi as MeshInstance3D).visible = false
				if ap.args.has("hidebody"):
					# diagnosis: which part pokes through (the body hidden, the clothes left)
					for mi in (o.model.outfits[o.model.cur_outfit]["root"] as Node).find_children("*_body", "MeshInstance3D", true, false):
						(mi as MeshInstance3D).visible = false
				views = only_views if not only_views.is_empty() else cur["views"]
				view_i = 0
				frames = 0
				_cam(o, views[0])
				stage = "shots"
		"shots":
			frames += 1
			_cam(o, views[view_i])
			if frames >= 4:
				var p := out.path_join(outfit).path_join("%s_%s.png" % [cur["id"], views[view_i]])
				DirAccess.make_dir_recursive_absolute(p.get_base_dir())
				get_viewport().get_texture().get_image().save_png(p)
				frames = 0
				view_i += 1
				if view_i >= views.size():
					print("SURVEY %s %s pose=%s state=%s held=%s" % [outfit, cur["id"], o.model.pose, o.model._state, o.model.holding()])
					stage = "next"


func _reset(o: Owner) -> void:
	seed(hash(str(cur.get("id", "")) + outfit))   # the same random choices (sleep side...) every run
	o.abort()
	o.scripted = true
	o.force_pose = ""
	o.in_bed = false
	o.asleep = false
	o.purring = false
	o.show_model()
	for k in o.model.outfits:
		for mi in (o.model.outfits[k]["root"] as Node).find_children("*_hair", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = true
		for mi in (o.model.outfits[k]["root"] as Node).find_children("*_body", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = true
	for slot in ["hand", "back"]:
		var n := o.model.drop_held(slot)
		if n:
			n.queue_free()
	o.model.hand_target = null
	o.model.hand_target_l = null
	o.model.hide_skirt(false)
	o.model.hide_shoes(false)
	o.set_outfit_k(outfit)
	o.model.set_turban(outfit == "bath")
	g.aft["lap"] = false
	g.cat.mode = "free"
	g.cat.teleport(Vector3(10.4, 0.0, 7.6), 0.0)


func _put(o: Owner, p: Vector3, y: float, pose: String) -> void:
	o.global_position = p
	o.yaw = y
	o.rotation.y = y
	o.model.seat_back = false
	o.model.seat_lift = 0.0
	o.model.snap_pose(pose)
	o.model.pose = pose
	o.model.reset_springs()


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, g.house.ground_height(x, z, 6.0), z)


func _stand(pose: String) -> void:
	var o: Owner = _who()
	_put(o, _ground(OPEN.x, OPEN.y), OPEN_YAW, "stand")
	if pose != "stand":
		o.run("survey", [{"t": "pose", "pose": pose, "dur": 999.0}], 9)


func _walk() -> void:
	var o: Owner = _who()
	_put(o, _ground(OPEN.x + 2.2, OPEN.y), OPEN_YAW, "stand")
	o.run("survey", [{"t": "walk", "points": [_ground(OPEN.x - 4.0, OPEN.y)]}], 9)


func _stairs() -> void:
	var o: Owner = _who()
	_put(o, Vector3(5.55, 0, 3.8), 0.0, "stand")
	o.run("survey", [{"t": "walk", "node": "f_stairs_t"}], 9)


func _stairs_down() -> void:
	var o: Owner = _who()
	_put(o, Vector3(5.55, 3, 8.7), PI, "stand")
	o.run("survey", [{"t": "walk", "node": "g_stairs_b"}], 9)


func _sofa(extra := "") -> void:
	var o: Owner = _who()
	_put(o, Vector3(2.5, 0, 2.6), 0.0, "stand")
	o.run("survey", [{"t": "spot", "spot": Layout.spot("sofa")}, {"t": "pose", "pose": "read" if extra == "book_open" else ("sit_talk" if extra == "talk" else "sit"), "dur": 999.0}], 9)
	if extra == "book_open":
		g._book_open(o, true)
	elif extra == "lap":
		g.aft["lap_open"] = true
		cur["hold_fn"] = func():
			if g.cat.mode != "lap" and timer > 6.0:
				g.aft["lap"] = false
				g.aft["lap_open"] = true
				var lp = g.lap_point()
				if lp != null:
					g.cat.teleport(lp, o.yaw + PI / 2)
					g._enter_lap()


func _bowl() -> void:
	var o: Owner = _who()
	_put(o, Vector3(8.65, 0, 5.2), PI, "stand")
	o.run("survey", [{"t": "spot", "spot": Layout.spot("bowl")}, {"t": "pose", "pose": "kneel", "dur": 999.0}], 9)


func _bed(pose: String) -> void:
	var o: Owner = _who()
	o.put_in_bed(false)
	o.force_pose = pose
	o.model.snap_pose(pose)
	o.model.pose = pose


func _bath() -> void:
	var o: Owner = _who()
	o.model.set_turban(true)
	o.model.hide_skirt(true)
	o.place(Layout.spot("bathTubIn"))
	o.model.snap_pose("bath")
	o.model.pose = "bath"
	o.run("survey", [{"t": "pose", "pose": "bath", "dur": 999.0}], 9)
	# the tub as in the game's bath scene: water at 0.8 with foam
	for f: House.Faucet in g.house.faucets:
		if f.id == "tub":
			f.level = 0.8
			if f.water and f.water.material_override:
				(f.water.material_override as ShaderMaterial).set_shader_parameter("foam", 1.0)


func _hold(kind: String) -> void:
	var o: Owner = _who()
	_put(o, _ground(OPEN.x, OPEN.y), OPEN_YAW, "stand")
	if kind == "book" or kind == "book_open":
		g._book_open(o, kind == "book_open")
	else:
		o.model.hold(g._prop(kind), kind)


func _gesture(name: String) -> void:
	var o: Owner = _who()
	_put(o, _ground(OPEN.x, OPEN.y), OPEN_YAW, "stand")
	o.model.gesture(name)


## the camera around her: VIEW relative to the way she faces, framed by the case's frame
func _cam(o: Owner, view: String) -> void:
	var fr: Array = FRAMES[cur["frame"]]
	var yaw := o.yaw
	var fw := Vector3(sin(yaw), 0, cos(yaw))
	var rt := Vector3(fw.z, 0, -fw.x)
	var base := o.global_position
	if cur["frame"] == "bed" or cur["frame"] == "bath" or cur["frame"] == "seat":
		# centre on the pelvis (lying / sitting she is not over her root)
		base = o.model.bone_world("pelvis").origin
		base.y -= float(fr[0])
	var c := base + Vector3(0, float(fr[0]), 0)
	var dist := float(fr[1])
	var fov := float(fr[2])
	if ap.args.has("close"):
		var cl := str(ap.args["close"]).split(",")
		c = o.model.bone_world(cl[0]).origin
		dist = float(cl[1]) if cl.size() > 1 else 0.75
		fov = 40.0
	var dirs := {"front": fw, "back": -fw, "side": rt, "left": -rt, "34": (rt + fw).normalized(), "34l": (fw - rt).normalized(),
		"back34": (rt - fw).normalized(), "top": (fw * 0.35 + Vector3(0, 1, 0)).normalized(),
		# lying: her "front" is up; from the foot of the bed is along -fw of the body's up axis
		"foot": (Vector3(0, 0.45, 0) + rt * 0.0 - (o.model.bone_world("head").origin - o.model.bone_world("pelvis").origin).normalized()).normalized()}
	var up := Vector3(0, 1, 0)
	dirs["hi34"] = ((rt + fw).normalized() * 0.55 + up).normalized()
	dirs["back34l"] = (-rt - fw).normalized()
	dirs["hi34l"] = ((fw - rt).normalized() * 0.55 + up).normalized()
	dirs["hifoot"] = (dirs["foot"] * 0.55 + up).normalized()
	dirs["front_hi"] = (fw + up * 0.75).normalized()
	var d: Vector3 = dirs.get(view, fw)
	var lift := 0.15 if view != "top" and not ap.args.has("close") else 0.0
	g.rig.override_pose = {"pos": c + d * dist + Vector3(0, lift, 0), "look": c, "blend": 1.0, "fov": fov}
