extends Node3D
## Look-development harness: builds the house with night lighting and saves screenshots from preset
## cameras. Run: godot --path godot res://scenes/lookdev.tscn -- --shots=sala,hall --out=C:/tmp

const SHOTS := {
	"sala": [Vector3(4.6, 1.5, 0.4), Vector3(1.0, 1.0, 4.5)],
	"sala2": [Vector3(0.6, 1.2, 4.9), Vector3(3.5, 0.8, 1.0)],
	"hall": [Vector3(6.3, 1.5, 0.5), Vector3(6.3, 1.4, 9.0)],
	"quarto": [Vector3(4.5, 4.5, 4.8), Vector3(0.8, 3.6, 1.5)],
	"hospedes": [Vector3(4.5, 4.4, 6.0), Vector3(1.0, 3.5, 9.0)],
	"cozinha": [Vector3(7.9, 1.6, 4.0), Vector3(10.5, 0.8, 9.5)],
	"escritorio": [Vector3(4.5, 1.6, 6.0), Vector3(1.5, 0.7, 9.5)],
	"porao": [Vector3(7.4, -1.6, 9.4), Vector3(2.0, -2.6, 2.0)],
	"lavanderia": [Vector3(11.5, -1.6, 9.0), Vector3(9.0, -2.4, 0.5)],
	"banheiro": [Vector3(8.0, 4.6, 6.4), Vector3(11.0, 3.4, 9.6)],
	"sotao": [Vector3(6.8, 7.4, 1.0), Vector3(2.5, 6.4, 8.5)],
	"corredor": [Vector3(6.6, 4.6, 9.6), Vector3(6.4, 3.6, 1.0)],
	"exterior": [Vector3(4.0, 3.0, -15.0), Vector3(6.5, 3.0, 4.0)],
	"catview": [Vector3(3.2, 3.45, 4.6), Vector3(2.0, 3.25, 2.6)],
}

var shots: Array = []
var out_dir := "user://shots"
var frame := 0
var cam: Camera3D
var lit_all := true
var cat: CatRig
var cat_variant := CatRig.GAME   # --catvariant=ID (style studies: mingau, mingau_a/b/c, mingau_creme...)
var cat_pose := {}
var cat_shots := false
var tunes := {}
var people_shots := false
var ghost_id := ""
var ghost_pose := ""
var ghost_heat := 0.0     # --ghostheat=0..1: the Shadow's red warning on the ghost
var ghost: GhostBody
var people_clip := ""     # --clip=name: the rig plays this clip state (or one-shot with --clip=!name)
var people_walk := 0.0    # walking speed for the people shots (--speed=)
var people_talk := ""     # --talk="text": the mouth says it
var people_mood := ""     # --mood=joy|surprised|sorrow|eye_joy
var people_hand := false  # --hand: right hand reaches a point in front (IK check)
var clara: HumanRig
var davi: HumanRig
const PEOPLE := {
	"clara_stand": ["clara", "day", "stand", Vector3(6.5, 0, 2.2), PI, Vector3(6.3, 1.45, 0.6), Vector3(6.5, 1.1, 2.2), 0.0],
	"clara_walk": ["clara", "day", "stand", Vector3(6.5, 0, 2.2), PI, Vector3(5.6, 1.2, 1.0), Vector3(6.5, 0.9, 2.2), 1.2],
	"clara_bed": ["clara", "night", "lie", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(2.9, 4.4, 3.9), Vector3(1.1, 3.6, 2.7), 0.0],
	"clara_hug": ["clara", "night", "hug", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(3.0, 4.2, 3.4), Vector3(1.1, 3.6, 2.7), 0.0],
	"clara_face": ["clara", "day", "stand", Vector3(6.5, 0, 2.2), PI, Vector3(6.45, 1.55, 1.55), Vector3(6.5, 1.52, 2.2), 0.0],
	"davi_sit": ["davi", "night", "read", Vector3(2.45, 0, 8.85), 0.0, Vector3(3.6, 1.5, 7.6), Vector3(2.45, 0.9, 8.9), 0.0],
	"davi_stand": ["davi", "day", "stand", Vector3(6.5, 0, 6.0), PI, Vector3(6.2, 1.6, 3.6), Vector3(6.5, 1.0, 6.0), 0.0],
	"davi_face": ["davi", "day", "stand", Vector3(6.5, 0, 6.0), PI, Vector3(6.45, 1.62, 5.3), Vector3(6.5, 1.6, 6.0), 0.0],
	"clara_bedside": ["clara", "night", "lie", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(1.4, 4.1, 5.0), Vector3(1.3, 3.5, 2.7), 0.0],
	"clara_bath": ["clara", "bath", "bath", Vector3(10.75, 3.12, 9.57), -PI / 2, Vector3(9.3, 4.3, 8.6), Vector3(10.75, 3.5, 9.57), 0.0],
	"clara_kneel": ["clara", "day", "kneel", Vector3(6.5, 0, 2.2), PI, Vector3(5.4, 1.1, 1.0), Vector3(6.5, 0.5, 2.2), 0.0],
	"davi_bedside": ["davi", "night", "lie", Vector3(1.0, 2.93, 8.3), PI / 2, Vector3(1.2, 3.8, 9.85), Vector3(0.7, 3.6, 8.3), 0.0],
	"davi_lie": ["davi", "night", "lie", Vector3(1.0, 2.93, 8.3), PI / 2, Vector3(2.9, 4.5, 9.3), Vector3(1.1, 3.6, 8.3), 0.0],
	"clara_bedarm": ["clara", "night", "lie", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(0.8, 3.7, 3.65), Vector3(0.7, 3.35, 2.8), 0.0],
	"clara_bedtop": ["clara", "night", "lie", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(1.05, 4.4, 3.1), Vector3(0.7, 3.3, 2.8), 0.0],
	"clara_bedface": ["clara", "night", "lie", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(2.9, 4.4, 3.9), Vector3(1.1, 3.6, 2.7), 0.0],
	"davi_bedface": ["davi", "night", "lie", Vector3(1.0, 2.93, 8.3), PI / 2, Vector3(2.9, 4.5, 9.3), Vector3(1.1, 3.6, 8.3), 0.0],
	"clara_lieside": ["clara", "night", "lieSide", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(1.3, 4.3, 4.6), Vector3(1.1, 3.5, 2.7), 0.0],
	"clara_lieside2": ["clara", "night", "lieSide", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(3.2, 3.8, 2.8), Vector3(1.1, 3.5, 2.8), 0.0],
	"clara_kneelface": ["clara", "day", "kneel", Vector3(6.5, 0, 2.2), PI, Vector3(6.0, 1.0, 1.0), Vector3(6.5, 0.7, 2.0), 0.0],
	"davi_kneel": ["davi", "day", "kneel", Vector3(6.5, 0, 2.2), PI, Vector3(5.4, 1.1, 1.0), Vector3(6.5, 0.5, 2.2), 0.0],
	"clara_cry": ["clara", "night", "cry", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(3.0, 4.2, 3.4), Vector3(1.1, 3.6, 2.7), 0.0],
	"clara_reach": ["clara", "day", "stand", Vector3(6.5, 0, 2.2), PI, Vector3(5.4, 1.4, 1.2), Vector3(6.5, 1.0, 2.2), 0.0],
	"clara_reachp": ["clara", "day", "reach", Vector3(6.5, 0, 2.2), PI, Vector3(5.2, 1.3, 2.0), Vector3(6.5, 1.0, 2.2), 0.0],
	"clara_carryp": ["clara", "day", "carry", Vector3(6.5, 0, 2.2), PI, Vector3(5.2, 1.3, 2.0), Vector3(6.5, 1.0, 2.2), 0.0],
	"clara_hugside": ["clara", "night", "hug", Vector3(0.89, 3.05, 2.8), PI / 2, Vector3(1.0, 3.9, 4.3), Vector3(1.1, 3.5, 2.7), 0.0],
	"clara_readp": ["clara", "day", "read", Vector3(2.45, 0, 8.85), 0.0, Vector3(2.45, 1.3, 10.4), Vector3(2.45, 0.9, 8.9), 0.0],
	"clara_standread": ["clara", "day", "read", Vector3(6.5, 0, 2.2), PI, Vector3(6.5, 1.3, 0.8), Vector3(6.5, 1.0, 2.2), 0.0],
	"clara_turban": ["clara", "night", "stand", Vector3(6.5, 0, 2.2), PI, Vector3(6.2, 1.62, 1.45), Vector3(6.5, 1.5, 2.2), 0.0],
	# the ghost of --ghost from its side and from the front (Clara out of the way)
	"ghost_side": ["clara", "day", "stand", Vector3(9.5, 0, 8.0), PI, Vector3(7.3, 1.0, 1.7), Vector3(5.7, 0.7, 2.6), 0.0],
	"ghost_front": ["clara", "day", "stand", Vector3(9.5, 0, 8.0), PI, Vector3(5.7, 1.3, 0.4), Vector3(5.7, 0.8, 2.6), 0.0],
	"ghost_face": ["clara", "day", "stand", Vector3(9.5, 0, 8.0), PI, Vector3(5.7, 1.62, 1.6), Vector3(5.7, 1.58, 2.6), 0.0],
	"ghost_face_hi": ["clara", "day", "stand", Vector3(9.5, 0, 8.0), PI, Vector3(5.7, 2.1, 1.3), Vector3(5.7, 2.05, 2.6), 0.0],
	"clara_bathclose": ["clara", "bath", "bath", Vector3(10.75, 3.12, 9.57), -PI / 2, Vector3(9.9, 4.1, 9.3), Vector3(10.75, 3.6, 9.57), 0.0],
	"clara_towel": ["clara", "bath", "stand", Vector3(6.5, 0, 2.2), PI, Vector3(6.1, 1.3, 0.4), Vector3(6.5, 1.0, 2.2), 0.0],
	"clara_towelback": ["clara", "bath", "stand", Vector3(6.5, 0, 2.2), PI, Vector3(7.2, 1.5, 3.9), Vector3(6.5, 1.1, 2.2), 0.0],
	"clara_sit": ["clara", "day", "sit", Vector3(2.45, 0, 8.85), 0.0, Vector3(3.6, 1.5, 7.6), Vector3(2.45, 0.9, 8.9), 0.0],
}
const CAT_POSES := {
	"stand": {},
	"walk": {"speed": 1.6},
	"run": {"speed": 4.2, "run": true},
	"sit": {"sit": 1.0},
	"lie": {"lie": 1.0, "purr": 1.0},
	"hiss": {"hiss": 1.0, "bristle": 1.0, "tail_up": 1.0},
	"crouch": {"crouch": 1.0, "speed": 0.6},
	"meow": {"meow": 1.0, "tail_up": 1.0},
	"face": {"sit": 1.0},
	"faceclose": {"sit": 1.0},
	"face34": {},
	"back": {"sit": 1.0},
}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8).split(",")
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--dark":
			lit_all = false
		elif a.begins_with("--tune="):
			for kv in a.substr(7).split(","):
				var pr := kv.split(":")
				tunes[pr[0]] = float(pr[1])
		elif a == "--cat":
			cat_shots = true
		elif a.begins_with("--catvariant="):
			cat_variant = a.substr(13)
		elif a == "--people":
			people_shots = true
		elif a.begins_with("--clip="):
			people_clip = a.substr(7)
		elif a.begins_with("--talk="):
			people_talk = a.substr(7)
		elif a.begins_with("--mood="):
			people_mood = a.substr(7)
		elif a == "--hand":
			people_hand = true
		elif a.begins_with("--speed="):
			people_walk = float(a.substr(8))
		elif a.begins_with("--ghostpose="):
			ghost_pose = a.substr(12)
		elif a.begins_with("--ghost="):
			ghost_id = a.substr(8)
		elif a.begins_with("--ghostheat="):
			ghost_heat = float(a.substr(12))
	if shots.is_empty():
		shots = ["sala"]
	HouseBuilder.build(self)
	# the bed blankets are gone from the game (hide the ones still baked in the house model); the
	# guest bed as Davi finds it, without the dust sheet
	for pat in ["BLANKET*", "GUEST_DUST*"]:
		for n in find_children(pat, "Node3D", true, false):
			(n as Node3D).visible = false
	_env()
	_lights()
	cam = Camera3D.new()
	cam.fov = 68
	cam.near = 0.03
	add_child(cam)
	cam.current = true
	if cat_shots:
		cat = CatRig.new(cat_variant)
		add_child(cat)
		for k in tunes:
			cat.tune[k] = tunes[k]
		cat.position = Vector3(2.2, 0.0, 3.6)
		cat.rotation.y = 0.9
		if shots.is_empty() or not CAT_POSES.has(str(shots[0]).trim_prefix("side_")):
			shots = CAT_POSES.keys()
	if people_shots:
		clara = HumanRig.new("clara")
		add_child(clara)
		davi = HumanRig.new("davi")
		add_child(davi)
		if ghost_id != "":
			# a ghost next to Clara's stand shot: the ghosts keep the MPFB models and spectral shaders
			var gb := GhostBody.new(ghost_id)
			add_child(gb)
			gb.position = Vector3(5.7, 0, 2.6)
			gb.rotation.y = PI
			gb.alpha = 1.0
			ghost = gb
		if shots.is_empty() or not PEOPLE.has(shots[0]):
			shots = PEOPLE.keys()
	_set_shot(shots[0])


func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = load("res://assets/sky/night.hdr")
	mat.energy_multiplier = 0.35
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.85, 0.87, 0.9)
	env.volumetric_fog_ambient_inject = 0.05
	env.volumetric_fog_anisotropy = 0.5
	env.sdfgi_enabled = false
	we.environment = env
	add_child(we)
	# same house outline as the game (GameEnv), so character shots show how the two outlines meet
	var edge := ShaderMaterial.new()
	edge.shader = GameEnv.EDGE
	edge.render_priority = -100
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var eq := MeshInstance3D.new()
	eq.mesh = q
	eq.material_override = edge
	eq.extra_cull_margin = 16384.0
	eq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(eq)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-148), 0)
	moon.light_volumetric_fog_energy = 2.0
	add_child(moon)
	var vgi := VoxelGI.new()
	vgi.size = Vector3(14, 13, 12)
	vgi.position = Vector3(6, 2.4, 5)
	vgi.subdiv = VoxelGI.SUBDIV_128
	add_child(vgi)
	vgi.bake()


func _lights() -> void:
	for d in Layout.data()["LIGHTS"]:
		if d["room"] == "dynamic":
			continue
		var l := OmniLight3D.new()
		l.position = Layout.v3(d["pos"])
		l.light_color = Color(d["color"])
		l.omni_range = float(d["distance"])
		l.light_energy = float(d["intensity"]) / 16.0 if lit_all or d["room"] == "exterior" else 0.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = true
		l.light_size = 0.04
		l.light_volumetric_fog_energy = 0.6
		add_child(l)


func _set_shot(name: String) -> void:
	if people_shots:
		var d: Array = PEOPLE[name]
		var r: HumanRig = clara if d[0] == "clara" else davi
		var other: HumanRig = davi if r == clara else clara
		other.visible = false
		r.visible = true
		r.set_outfit(d[1])
		r.snap_pose(d[2])
		r.pose = d[2]
		r.position = d[3]
		r.rotation.y = d[4]
		r.speed = d[7]
		r.asleep = d[2] == "lie" and not name.ends_with("_awake")
		cam.fov = 50
		cam.position = d[5]
		cam.look_at(d[6])
		if people_walk > 0.0:
			r.speed = people_walk
		r.set_turban(name.begins_with("clara_bath") or name.begins_with("clara_towel") or name == "clara_turban")
		r.hide_skirt(d[2] == "bath")
		if people_talk != "":
			r.talk(people_talk, 8.0)
		if people_mood != "":
			r.set_mood(people_mood, 1.0, 20.0)
		if people_hand:
			r.hand_target = r.global_position + r.global_transform.basis.z * 0.45 + Vector3(0, 0.25, 0) + r.global_transform.basis.x * -0.1
		if people_clip.begins_with("!"):
			r.play_once(people_clip.substr(1))
		elif people_clip.begins_with("~"):
			r.gesture(people_clip.substr(1))
		elif people_clip != "":
			r._set_state(people_clip)
		return
	if cat_shots:
		var side_view := name.begins_with("side_")
		if side_view:
			name = name.substr(5)
		cat_pose = CAT_POSES.get(name, {})
		var fwd := Vector3(sin(cat.rotation.y), 0, cos(cat.rotation.y))
		var right := Vector3(fwd.z, 0, -fwd.x)
		if name == "face" or name == "face34" or name == "faceclose":
			var head := cat.position + Vector3(0, 0.32 if name == "face" else 0.29, 0) + fwd * (0.22 if name == "face" else 0.28)
			cam.fov = 30
			cam.position = head + fwd * 0.5 + right * (0.0 if name == "face" else 0.32) + Vector3(0, 0.04, 0)
			cam.look_at(head)
			return
		if side_view:
			cam.fov = 34
			cam.position = cat.position - right * 0.95 + Vector3(0, 0.2, 0)
			cam.look_at(cat.position + Vector3(0, 0.16, 0))
			return
		if name == "back":
			cam.fov = 38
			cam.position = cat.position - fwd * 0.8 - right * 0.35 + Vector3(0, 0.6, 0)
			cam.look_at(cat.position + Vector3(0, 0.18, 0))
			return
		var side := 1.0 if name != "lie" else -1.0
		cam.fov = 40
		cam.position = cat.position + Vector3(0.75 * side, 0.42, 0.2)
		cam.look_at(cat.position + Vector3(0, 0.18, 0.05))
		return
	var s: Array = SHOTS.get(name, SHOTS["sala"])
	cam.position = s[0]
	cam.look_at(s[1])


func _process(dt: float) -> void:
	if cat:
		cat.update_pose(dt, cat_pose)
		var nm: String = shots[0] if shots.size() > 0 else ""
		if nm == "face" or nm == "face34" or nm == "faceclose":
			var fwd := Vector3(sin(cat.rotation.y), 0, cos(cat.rotation.y))
			var right := Vector3(fwd.z, 0, -fwd.x)
			var head := cat.head_world() + fwd * 0.03
			var dist := 0.32 if nm == "faceclose" else 0.55
			cam.fov = 30
			cam.position = head + fwd * dist + right * (0.0 if nm != "face34" else 0.3) + Vector3(0, 0.03, 0)
			cam.look_at(head)
	if people_shots and str(shots[0]).ends_with("_bedface"):
		# close on the face from above and a little to the side (eyes closed? mouth?)
		var hr: HumanRig = clara if str(shots[0]).begins_with("clara") else davi
		var hw := hr.head_world()
		cam.fov = 35
		cam.position = hw + Vector3(0.45, 0.5, 0.15)
		cam.look_at(hw)
	if ghost:
		if ghost_pose != "":
			var gp := ghost_pose.split("@")
			ghost.rig.pose = gp[0]
			ghost.rig.speed = float(gp[1]) if gp.size() > 1 else 0.0
			ghost.rig.jerky = 10.0 if gp[0] == "spider" else 0.0
		if ghost_id == "shadow_run":
			ghost.flesh({"dissolve": 0.12, "foot_fade": 0.06})
		ghost.heat = ghost_heat
		ghost.glare = ghost_heat
		ghost.tick(dt)
	if clara and clara.visible:
		clara.update(dt)
	if davi and davi.visible:
		davi.update(dt)
	frame += 1
	if frame % 45 == 0:
		var name: String = shots[0]
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(out_dir)
		img.save_png(out_dir.path_join("godot_%s.png" % name))
		print("SHOT ", name)
		if people_shots:
			var rr: HumanRig = clara if clara.visible else davi
			print("HEAD %s %s  root %s" % [name, rr.head_world().snappedf(0.01), rr.global_position.snappedf(0.01)])
			if OS.get_cmdline_user_args().has("--bones"):
				for b in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "thigh_l", "foot_l"]:
					print("  BONE %s %s" % [b, rr.bone_world(b).origin.snappedf(0.01)])
		shots.remove_at(0)
		if shots.is_empty():
			get_tree().quit()
			return
		_set_shot(shots[0])
