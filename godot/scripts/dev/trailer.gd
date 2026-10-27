extends Node
## Staged scenes for the trailer (autopilot --scene=NAME, recorded with tools/dev/capture.py):
## people and the cat put straight into a moment and held there, so the camera move can be shot
## again and again the same way. The night ones mostly use the autopilot's own flags (--peekat,
## --visitorat, --shadowtest...); these are the moments the routine only reaches by playing.
##   lap      afternoon: Clara on the sofa, the cat purring in her lap, the TV on
##   bowl     afternoon: Clara kneeling by the bowl, the cat eating
##   bed      Clara lying down awake, the cat curled up purring at her side
##   sofa     Clara alone on the sofa (for the cat to walk into)
##   peek     night: the Shadow peeking from --nook=ID, heating from --heat0 to --heat1 (0..1) over
##            --heatsecs, the cat sitting where --catat=x,z says (it is what she stares at)
##   doll     night: the Doll standing still at --dollat=x,y,z, facing --dollface=x,z (the camera);
##            "doll" commands from devctl move it between takes (arg dollat=...)
##   hound    night: the Hound in full view from --houndat=x,y,z heading --houndyaw (degrees, 0 = +z) at
##            --houndspeed m/s, snarling by --houndsnarl (0..1); it ignores the cat

var ap: Node
var g: Game
var scene := ""
var _t := 0.0
var _set := false


func _ready() -> void:
	# after the Director and the threats: what a scene poses is what gets drawn
	process_priority = 1000


func _process(dt: float) -> void:
	if g == null or g.mode != "play":
		return
	_t += dt
	if _t < 1.0:
		return
	if not _set:
		_set = true
		_setup()
	_hold()


func _setup() -> void:
	var o: Owner = g.clara
	o.abort()
	o.scripted = true
	match scene:
		"lap", "sofa":
			o.place(Layout.spot("sofa"))
			o.model.snap_pose("sit")
			g._tv_show(true)
			g.aft["lap_open"] = true
		"bowl":
			o.place(Layout.spot("bowl"))
			o.model.snap_pose("kneel")
			g.cat.teleport(Game.BOWL_POS + Vector3(0.0, 0, 0.45), PI)
			g.cat.mode = "free"
			g.eat()
		"bed":
			o.put_in_bed(false)
			g.cat.teleport(Layout.spot_pos(o.cfg["bedside_spot"]), PI / 2)
			g.cat.mode = "free"
			g.toggle_purr(o)
	print("TRAILER scene %s set" % scene)


func _hold() -> void:
	var o: Owner = g.clara
	match scene:
		"lap":
			# the lap is measured on her thighs: only once the sitting pose has settled
			if g.cat.mode != "lap" and _t > 2.5:
				g.aft["lap"] = false
				g.aft["lap_open"] = true
				var lp = g.lap_point()
				if lp != null:
					g.cat.teleport(lp, o.yaw + PI / 2)
					g._enter_lap()
			o.model.set_mood("joy", 0.7, 1.0)
		"bowl":
			if not g.is_eating():
				g.eat()
		"bed":
			# the afternoon would turn into the night after a while of purring
			g.aft["purr_t"] = 0.0
		"doll":
			var dl: DollThreat = g.director.get_threat("doll")
			dl.enabled = false
			var dp := str(ap.args.get("dollat", "6.49,3.0,3.47")).split(",")
			var p := Vector3(float(dp[0]), float(dp[1]), float(dp[2]))
			var fp := str(ap.args.get("dollface", "6.49,5.0")).split(",")
			dl.in_chest = false
			dl.item.pos = p
			dl.item.node.visible = true
			dl.item.node.global_position = p
			dl.item.node.rotation = Vector3(0, atan2(float(fp[0]) - p.x, float(fp[1]) - p.z), 0)
		"hound":
			# runs after the Director (process_priority), so this pose is the one drawn
			var hd: Hound = g.director.hound
			var hp := str(ap.args.get("houndat", "6.5,0,8.5")).split(",")
			var yw := deg_to_rad(float(ap.args.get("houndyaw", "180")))
			var spd := float(ap.args.get("houndspeed", "0.8"))
			var p := Vector3(float(hp[0]), float(hp[1]), float(hp[2])) + Vector3(sin(yw), 0, cos(yw)) * spd * maxf(0.0, _t - 1.0)
			hd.body.visible = true
			hd.body.alpha = 0.96
			hd.body.global_position = p
			hd.body.rotation = Vector3(0, yw, 0)
			hd.body.update_pose(get_process_delta_time(), spd, 0.0, 0.0, float(ap.args.get("houndsnarl", "0.6")), 0.0, spd > 1.5)
		"peek":
			var sh: ShadowThreat = g.director.get_threat("shadow")
			if sh.nook.is_empty() or sh.nook["id"] != str(ap.args.get("nook", "quarto_cama")):
				for nk in Layout.data().get("SHADOW_NOOKS", []):
					if nk["id"] == str(ap.args.get("nook", "quarto_cama")):
						sh.nook = nk
			if sh.nook.is_empty():
				return
			sh.mode = "peek"
			var k := clampf((_t - 1.0) / maxf(0.01, float(ap.args.get("heatsecs", "5"))), 0.0, 1.0)
			sh.sight = lerpf(float(ap.args.get("heat0", "0")), float(ap.args.get("heat1", "1")), k)
			sh.vis = 1.0
			if ap.args.has("catat"):
				var c := str(ap.args["catat"]).split(",")
				var np := Layout.v3(sh.nook["p"])
				var cp := Vector3(float(c[0]), np.y, float(c[1]))
				g.cat.teleport(cp, atan2(np.x - cp.x, np.z - cp.z))
