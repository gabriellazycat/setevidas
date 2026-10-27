extends "res://scripts/dev/lookdev.gd"
## Films Mingau's procedural animation frame by frame (fixed 30 fps steps) for review:
## godot --path godot res://scenes/cat_anim.tscn -- --cat --shots=stand --clip=walk|run|sit|eat|stand --view=side|34|front|face|close|wide --out=DIR
## walk/run: the cat crosses the room at the gait speed; sit: stand, sit down, hold, stand up;
## eat: stand, head down to a bowl on the floor and chew, then look up again.
## Acting prototypes (variations to pick from before refining):
##   swat_a short sharp paw, swat_b slow reach and push looking at you, swat_c two quick taps;
##   cup_a pushes the cup off the table staring at you, cup_b without looking, cup_c tests it first;
##   startle_a jumps up arched, startle_b freezes then arches, startle_c recoils backwards;
##   pounce_a long wiggle and leap, pounce_b short wiggle, pounce_c wiggle, creep, wiggle, leap;
##   tilt_a slow head tilt, tilt_b one side then the other; blink_a slow blink, blink_b with a head dip.

const FPS := 30.0
const CLIPS := {"walk": 1.2, "run": 0.8, "sit": 5.0, "look": 1.0, "eat": 5.0, "curl": 4.0, "stand": 0.5,
	"swat_a": 2.0, "swat_b": 3.4, "swat_c": 2.4,
	"cup_a": 4.6, "cup_b": 3.6, "cup_c": 5.2,
	"startle_a": 2.6, "startle_b": 3.2, "startle_c": 2.6,
	"pounce_a": 4.2, "pounce_b": 3.0, "pounce_c": 4.8,
	"tilt_a": 3.2, "tilt_b": 3.4, "blink_a": 2.8, "blink_b": 3.2, "aim": 4.4}
## aim: the game's aimed swat (Cat.swat_at timing) at four targets in turn, one second each, rig space:
## low ahead-left, on the right, ahead on the floor near the chest, up on a ledge (rears up)
const AIM := [Vector3(0.1, 0.03, 0.34), Vector3(-0.14, 0.03, 0.3), Vector3(0.03, 0.03, 0.26), Vector3(0.04, 0.4, 0.33)]
var aim_box: MeshInstance3D
var ledge: MeshInstance3D
const TABLE_H := 0.45          # the coffee table the cup clips stand on
const CUP_R := 0.038

var clip := "walk"
var view := "side"
var n := 0
var start := Vector3(2.4, 0.0, 1.6)
var _z := 0.0                  # distance walked (speed integrated)
var cup: Node3D
var cup_v := Vector3.ZERO
var cup_falling := false
var cup_spin := Vector3.ZERO
var table_edge := 0.0
var shards: Array = []         # [node, velocity]
var ball: MeshInstance3D
var ball_v := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--curlin="):
			set_meta("curlin", float(a.substr(9)))
		elif a.begins_with("--curlhind="):
			var hv := a.substr(11).split(",")
			set_meta("curlhind", [float(hv[0]), float(hv[1])])
	if clip.begins_with("cup_"):
		start.y = TABLE_H
	super._ready()
	if has_meta("curlin"):
		cat.CURL_IN = get_meta("curlin")
	if has_meta("curlhind"):
		cat.CURL_HIND = get_meta("curlhind")
	cat.rotation.y = 0.0   # facing +Z
	cat.position = start
	_stage()


static func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## hides the house and lights a plain floor so the silhouette and the paw contacts read clearly
func _stage() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		if not cat.is_ancestor_of(mi) and not (mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == GameEnv.EDGE):
			(mi as MeshInstance3D).visible = false
	for l in find_children("*", "OmniLight3D", true, false):
		(l as OmniLight3D).visible = false
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor.mesh = pm
	floor.material_override = _mat(Color(0.78, 0.7, 0.62), 0.9)
	floor.position = Vector3(start.x, 0, start.z + 2)
	add_child(floor)
	if clip == "eat":
		# a food bowl on the floor right under the muzzle
		var bowl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.065
		cm.bottom_radius = 0.05
		cm.height = 0.035
		bowl.mesh = cm
		bowl.material_override = _mat(Color(0.55, 0.25, 0.22))
		bowl.position = start + Vector3(0, 0.0175, 0.22)
		add_child(bowl)
	if clip.begins_with("cup_"):
		_stage_cup()
	if clip == "aim":
		aim_box = MeshInstance3D.new()
		var ab := BoxMesh.new()
		ab.size = Vector3(0.05, 0.06, 0.05)
		aim_box.mesh = ab
		aim_box.material_override = _mat(Color(0.3, 0.55, 0.85), 0.4)
		add_child(aim_box)
		ledge = MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.5, 0.37, 0.25)
		ledge.mesh = lb
		ledge.material_override = _mat(Color(0.79, 0.56, 0.33), 0.6)
		ledge.position = start + Vector3(0, 0.185, AIM[3].z + 0.1)
		ledge.visible = false
		add_child(ledge)
	if clip.begins_with("pounce_"):
		# the yarn ball the cat leaps on
		ball = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		ball.mesh = sm
		ball.material_override = _mat(Color(0.8, 0.2, 0.22))
		ball.position = start + Vector3(0, 0.05, 0.98)
		add_child(ball)
	for i in 2:
		var sun := DirectionalLight3D.new()
		sun.light_color = Color(1.0, 0.95, 0.88)
		sun.light_energy = 1.6 if i == 0 else 0.5
		sun.shadow_enabled = i == 0
		sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(70 if i == 0 else -120), 0)
		add_child(sun)


## a wooden coffee table under the cat, with a tea cup near its front edge, in reach of the left paw
func _stage_cup() -> void:
	var tb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# the cup sits just ahead of the standing left fore paw, the edge right past it
	table_edge = start.z + cat._mpos("fpaw.L").z + 0.025 + CUP_R + 0.05 + 0.045
	bm.size = Vector3(0.9, TABLE_H, 0.9)
	tb.mesh = bm
	tb.material_override = _mat(Color(0.79, 0.56, 0.33), 0.6)
	tb.position = Vector3(start.x, TABLE_H * 0.5, table_edge - 0.45)
	add_child(tb)
	cup = Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = CUP_R
	cm.bottom_radius = CUP_R * 0.75
	cm.height = 0.07
	body.mesh = cm
	body.material_override = _mat(Color(0.97, 0.93, 0.86), 0.35)
	body.position.y = 0.035
	cup.add_child(body)
	var band := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = CUP_R + 0.002
	bc.bottom_radius = CUP_R + 0.001
	bc.height = 0.012
	band.mesh = bc
	band.material_override = _mat(Color(0.86, 0.5, 0.55), 0.4)
	band.position.y = 0.055
	cup.add_child(band)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.012
	tm.outer_radius = 0.02
	handle.mesh = tm
	handle.material_override = body.material_override
	handle.rotation = Vector3(0, 0, PI * 0.5)
	handle.position = Vector3(CUP_R + 0.008, 0.04, 0)
	cup.add_child(handle)
	add_child(cup)
	cup.position = Vector3(start.x + _paw_x(), TABLE_H, table_edge - 0.05)


## the left fore paw's sideways offset from the body centre (rig space)
func _paw_x() -> float:
	return cat._mpos("fpaw.L").x if cat.skel != null else 0.045


## 0 before a, eases up to 1 at b, holds, eases back to 0 between c and d
static func _ramp(x: float, a: float, b: float, c := INF, d := INF) -> float:
	if c == INF:
		return smoothstep(a, b, x)
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))


## alert stance (ears up, pupils a bit open) under the clip's own keys
static func _a(d: Dictionary) -> Dictionary:
	return {"ear_alert": 1.0, "pupil": 0.55}.merged(d, true)


## a ballistic hop of height h between t0 and t1 along dz: [offset, vertical speed, airborne]
static func _hop(tm: float, t0: float, t1: float, h: float, dz := 0.0) -> Array:
	if tm < t0:
		return [Vector3.ZERO, 0.0, false]
	if tm > t1:
		return [Vector3(0, 0, dz), 0.0, false]
	var s := (tm - t0) / (t1 - t0)
	return [Vector3(0, 4.0 * h * s * (1.0 - s), dz * s), 4.0 * h * (1.0 - 2.0 * s) / (t1 - t0), true]


func _pose(tm: float) -> Dictionary:
	match clip:
		"walk":
			return {"speed": 2.1}
		"run":
			return {"speed": 4.4, "run": true}
		"look":
			return {"head_yaw": -0.7, "ear_alert": 1.0, "ear_yaw": 0.8, "meow": 0.0}
		"sit":
			if tm < 0.6 or tm > 3.2:
				return {}
			return {"sit": 1.0}
		"eat":
			if tm < 0.6 or tm > 3.6:
				return {}
			return {"eat": 1.0}
		"curl":
			if tm < 0.3:
				return {}
			return {"lie": 1.0, "purr": 1.0, "curl": 1.0}
		# ---- swat
		"swat_a":
			# short and sharp: up fast, a hair of hold, back
			return _a({"head_pitch": 0.25, "swat": _ramp(tm, 0.6, 0.67, 0.72, 0.92), "swat_hip": -1.3, "swat_knee": -0.5, "swat_paw": 0.2})
		"swat_b":
			# slow reach, then the paw presses forward and down while the cat looks at you
			var reach := _ramp(tm, 0.5, 1.3, 2.6, 3.1)
			var press := smoothstep(1.4, 2.3, tm)
			return _a({"head_pitch": 0.25 * (1.0 - _ramp(tm, 1.2, 1.6, 2.4, 2.8)), "head_yaw": 0.9 * _ramp(tm, 1.2, 1.6, 2.4, 2.8),
				"swat": reach, "swat_hip": lerpf(-1.05, -0.75, press), "swat_knee": lerpf(-0.6, 0.0, press), "swat_paw": -0.4})
		"swat_c":
			# two quick taps, then a curious tilt
			var tap := maxf(_ramp(tm, 0.5, 0.57, 0.6, 0.75), _ramp(tm, 0.95, 1.02, 1.05, 1.2))
			return _a({"head_pitch": 0.3, "swat": tap, "swat_hip": -0.85, "swat_knee": -0.05, "swat_paw": -0.25,
				"tilt": 0.35 * _ramp(tm, 1.4, 1.8)})
		# ---- the cup (the paw pushes it; _cup() moves it)
		"cup_a":
			# stares at you the whole time, the paw pushes slowly, the cup goes
			var reach := smoothstep(1.0, 2.6, tm) * (1.0 - smoothstep(3.6, 4.1, tm))
			return _a({"head_yaw": 0.95 * _ramp(tm, 0.3, 0.9, 3.3, 3.8), "head_pitch": 0.3 * _ramp(tm, 3.3, 3.8),
				"swat": reach, "swat_hip": -0.85, "swat_knee": -0.05, "swat_paw": -0.35, "tail_up": 0.9})
		"cup_b":
			# eyes on the cup, a single deliberate swipe, watches it fall
			return _a({"head_pitch": lerpf(0.3, 0.55, smoothstep(1.4, 2.0, tm)), "pupil": 0.7,
				"swat": _ramp(tm, 0.8, 1.15, 1.35, 1.7), "swat_hip": -0.95, "swat_knee": 0.0, "swat_paw": -0.3})
		"cup_c":
			# two little test taps (the cup wobbles), a look at you, then the push
			var taps := maxf(_ramp(tm, 0.6, 0.72, 0.76, 0.95), _ramp(tm, 1.3, 1.42, 1.46, 1.65))
			var push := smoothstep(3.0, 3.7, tm) * (1.0 - smoothstep(4.3, 4.7, tm))
			return _a({"head_pitch": 0.3 * (1.0 - _ramp(tm, 1.9, 2.3, 2.7, 3.0)), "head_yaw": 0.95 * _ramp(tm, 1.9, 2.3, 2.7, 3.0),
				"tilt": 0.3 * _ramp(tm, 2.0, 2.4, 2.7, 3.0),
				"swat": maxf(taps * 0.55, push), "swat_hip": -0.98, "swat_knee": 0.0, "swat_paw": -0.35})
		# ---- startle
		"startle_a":
			# looking away, then the jump straight up, arched and puffed, turned side-on
			var hop := _hop(tm, 0.7, 1.12, 0.17)
			var scared := smoothstep(0.66, 0.74, tm)
			return {"head_yaw": lerpf(-0.4, 0.5, scared), "ear_alert": 1.0 - scared, "hiss": scared * (1.0 - smoothstep(2.0, 2.4, tm)), "arch": scared * (1.0 - smoothstep(2.0, 2.4, tm)),
				"bristle": scared, "pupil": lerpf(0.4, 1.0, scared), "tail_up": lerpf(0.6, 1.0, scared),
				"_off": hop[0], "_yaw": -0.75 * smoothstep(0.7, 1.0, tm), "grounded": true, "land": _ramp(tm, 1.12, 1.16, 1.22, 1.4)}
		"startle_b":
			# freezes on a sound, stares, then arches and hisses with a small hop
			var freeze := smoothstep(0.5, 0.58, tm)
			var arch := smoothstep(1.7, 1.8, tm) * (1.0 - smoothstep(2.7, 3.1, tm))
			var hop := _hop(tm, 1.7, 1.95, 0.05)
			return {"head_yaw": -0.6 * freeze, "head_pitch": -0.1 * freeze, "ear_alert": freeze * (1.0 - arch), "ear_yaw": -0.6,
				"pupil": lerpf(0.35, 1.0, freeze), "crouch": 0.4 * freeze * (1.0 - arch), "hiss": arch, "arch": arch, "bristle": arch,
				"tail_up": lerpf(0.6, 1.0, arch), "_off": hop[0]}
		"startle_c":
			# flinches down and scoots backwards, ears back, then hisses
			var back := smoothstep(0.55, 0.95, tm)
			var flinch := smoothstep(0.5, 0.58, tm)
			return {"crouch": flinch * (1.0 - smoothstep(1.3, 1.6, tm)), "pupil": lerpf(0.35, 1.0, flinch),
				"hiss": smoothstep(1.3, 1.45, tm) * (1.0 - smoothstep(2.2, 2.5, tm)), "arch": smoothstep(1.3, 1.45, tm) * (1.0 - smoothstep(2.2, 2.5, tm)), "bristle": flinch,
				"head_pitch": -0.15 * flinch, "speed": -0.9 * _ramp(tm, 0.55, 0.62, 0.85, 0.95), "tail_up": 0.2}
		# ---- pounce on the yarn
		"pounce_a":
			return _pounce(tm, 0.8, 2.6, 2.7)
		"pounce_b":
			return _pounce(tm, 0.6, 1.3, 1.4)
		"pounce_c":
			# wiggle, creep closer, wiggle again, leap
			var p := _pounce(tm, 0.6, 3.3, 3.4, 0.5)
			var creep := _ramp(tm, 1.5, 1.6, 2.2, 2.3)
			p["wiggle"] = p["wiggle"] * (1.0 - _ramp(tm, 1.4, 1.5, 2.3, 2.5))
			p["speed"] = 0.45 * creep
			return p
		"aim":
			# Cat.swat_at's timeline (SWAT_HIT 0.46, SWAT_FREE 0.62, SWAT_SECS 0.95) once per target
			var i := mini(int(tm / 1.1), AIM.size() - 1)
			var at := tm - i * 1.1
			var obj: Vector3 = AIM[i]
			aim_box.position = start + obj
			ledge.visible = i == 3
			var lift := _ramp(at, 0.1, 0.36)
			var push := _ramp(at, 0.36, 0.49)
			var dir := Vector3(obj.x, 0, obj.z).normalized()
			var hover := obj - dir * 0.07 + Vector3.UP * 0.07
			var through := obj + dir * 0.035 + Vector3.UP * 0.025
			var h := cat.to_local(cat.head_world())
			var flat := Vector2(obj.x - h.x, obj.z - h.z).length()
			var look_w := _ramp(at, 0.0, 0.12, 0.75, 1.05)
			return {"ear_alert": 1.0, "pupil": lerpf(0.5, 0.85, _ramp(at, 0.0, 0.2)), "crouch": 0.3 * _ramp(at, 0.0, 0.15, 0.5, 0.8),
				"swat": lift * (1.0 - _ramp(at, 0.62, 0.95)), "swat_side": "L" if obj.x >= 0.0 else "R",
				"swat_target": hover.lerp(through, push),
				"head_yaw": atan2(obj.x - h.x, obj.z - h.z) * look_w, "head_pitch": clampf(atan2(h.y - obj.y, maxf(flat, 0.05)), -0.55, 0.95) * look_w}
		# ---- head tilt and slow blink (sitting, facing the camera)
		"tilt_a":
			return {"sit": 1.0, "ear_alert": 1.0, "head_yaw": 0.25, "pupil": 0.6, "tilt": 0.5 * _ramp(tm, 0.6, 1.5, 2.5, 3.1),
				"head_pitch": -0.08 * _ramp(tm, 0.6, 1.5, 2.5, 3.1)}
		"tilt_b":
			var t1 := _ramp(tm, 0.5, 0.85, 1.4, 1.65)
			var t2 := _ramp(tm, 1.65, 2.0, 2.7, 3.1)
			return {"sit": 1.0, "ear_alert": 1.0, "ear_yaw": 0.4 * t1 - 0.4 * t2, "head_yaw": 0.25, "pupil": 0.65,
				"tilt": 0.45 * t1 - 0.45 * t2}
		"blink_a":
			return {"sit": 1.0, "head_yaw": 0.25, "pupil": 0.35, "slowblink": _ramp(tm, 0.7, 1.3, 1.7, 2.3)}
		"blink_b":
			var b := _ramp(tm, 0.7, 1.4, 1.9, 2.6)
			return {"sit": 1.0, "head_yaw": 0.25, "pupil": 0.35, "slowblink": b, "head_pitch": 0.25 * b, "tilt": 0.12 * b,
				"ear_alert": 0.0}
	return {}


## crouch, wiggle from w0 to w1, leap at j0 (0.45 s, 0.75 m forward), land pinning the ball
func _pounce(tm: float, w0: float, w1: float, j0: float, creep := 0.0) -> Dictionary:
	var hop := _hop(tm, j0, j0 + 0.45, 0.16, 0.75 - creep)
	var crouch := smoothstep(0.2, 0.5, tm)
	return {"crouch": crouch if not hop[2] else 0.0, "wiggle": _ramp(tm, w0, w0 + 0.5, w1 - 0.1, w1 + 0.05),
		"wiggle_rate": 10.0, "pupil": lerpf(0.4, 1.0, crouch), "ear_alert": 1.0, "head_pitch": 0.15 * crouch,
		"tail_up": 0.3, "_off": hop[0], "grounded": not hop[2], "vy": hop[1], "land": _ramp(tm, j0 + 0.45, j0 + 0.5, j0 + 0.6, j0 + 0.8)}


## the cup: pushed along by the left fore paw, over the edge it falls, tumbles and breaks
func _cup(dt: float) -> void:
	if cup == null or not cup.visible:
		_shards(dt)
		return
	if not cup_falling:
		var paw: Vector3 = cat.to_global(cat._mpos("fpaw.L"))
		var front := paw.z + 0.025 + CUP_R
		if absf(paw.x - cup.position.x) < CUP_R + 0.03 and paw.y < TABLE_H + 0.09 and front > cup.position.z:
			cup_v.z = maxf(cup_v.z, (front - cup.position.z) / dt * 0.5)
			cup.position.z = front
			# a tap makes it wobble
			cup.rotation.x = -0.15
		cup.rotation.x = lerpf(cup.rotation.x, 0.0, 1.0 - exp(-10.0 * dt))
		cup_v.z = maxf(0.0, cup_v.z - 2.0 * dt)
		cup.position.z += cup_v.z * dt
		if cup.position.z > table_edge + CUP_R * 0.3:
			cup_falling = true
			cup_v = Vector3(0, 0, maxf(cup_v.z, 0.35))
			cup_spin = Vector3(5.0, 0, 1.5)
	else:
		cup_v.y -= 9.8 * dt
		cup.position += cup_v * dt
		cup.rotation += cup_spin * dt
		if cup.position.y <= 0.0:
			cup.visible = false
			for i in 9:
				var s := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3.ONE * randf_range(0.012, 0.028)
				s.mesh = bm
				s.material_override = _mat(Color(0.97, 0.93, 0.86) if i % 3 else Color(0.86, 0.5, 0.55), 0.35)
				s.position = cup.position + Vector3(0, 0.01, 0)
				add_child(s)
				var a := randf() * TAU
				shards.append([s, Vector3(cos(a) * randf_range(0.4, 1.2), randf_range(0.6, 1.4), sin(a) * randf_range(0.4, 1.2) + 0.4)])
	_shards(dt)


func _shards(dt: float) -> void:
	for sh in shards:
		var s: MeshInstance3D = sh[0]
		var v: Vector3 = sh[1]
		if s.position.y <= 0.006 and v.y <= 0:
			continue
		v.y -= 9.8 * dt
		s.position += v * dt
		s.rotation += Vector3(7, 4, 2) * dt
		if s.position.y < 0.006:
			s.position.y = 0.006
			v = Vector3.ZERO
		sh[1] = v


## the yarn: knocked forward when the cat lands on it, then rolls to a stop
func _ball(dt: float) -> void:
	if ball == null:
		return
	if ball_v == 0.0 and cat.position.z > ball.position.z - 0.3 and cat.position.y < 0.02 and cat.position.z > start.z + 0.3:
		ball_v = 0.9
	ball_v = maxf(0.0, ball_v - 1.2 * dt) if ball_v > 0.0 else 0.0
	ball.position.z += ball_v * dt
	ball.rotation.x += ball_v / 0.05 * dt


func _process(_dt: float) -> void:
	var dt := 1.0 / FPS
	var tm := maxf(0.0, (n - 20) * dt)
	var p := _pose(tm)
	_z += p.get("speed", 0.0) * dt
	cat.position = start + Vector3(0, 0, _z) + p.get("_off", Vector3.ZERO)
	cat.rotation.y = p.get("_yaw", 0.0)
	cat.update_pose(dt, p)
	_cup(dt)
	_ball(dt)
	var c := Vector3(start.x, start.y, cat.position.z) + Vector3(0, 0.17, 0)
	cam.fov = 34
	if view == "side":
		cam.position = c + Vector3(1.05, 0.03, 0)
	elif view == "top":
		cam.position = c + Vector3(0.05, 1.1, 0.25)
	elif view == "front":
		cam.position = c + Vector3(0.3, 0.2, 0.9)
	elif view == "face":
		cam.position = c + Vector3(0.18, 0.12, 0.75)
	elif view == "close":
		cam.position = c + Vector3(0.12, 0.13, 0.5)
	elif view == "wide":
		# the cup clips: the cat on the table and the floor the cup lands on
		if clip.begins_with("cup_"):
			c = start + Vector3(0, 0.1, 0.28)
			cam.position = c + Vector3(0.95, 0.12, 0.85)
		else:
			c = start + Vector3(0, 0.08, 0.5)
			cam.position = c + Vector3(0.9, 0.16, 0.35)
		cam.fov = 40
	elif view == "34w":
		# wider 3/4 that follows the cat up (startle jumps)
		c.y += (cat.position.y - start.y) * 0.5
		cam.position = c + Vector3(1.1, 0.3, 0.9)
	elif view == "back":
		cam.position = c + Vector3(0.35, 0.25, -0.85)
	else:
		cam.position = c + Vector3(0.75, 0.25, 0.6)
	var aim := c + (Vector3(0, 0.08, 0.12) if view == "face" or view == "close" else Vector3.ZERO)
	if view == "wide":
		aim = c + Vector3(0, -0.12, 0.15)
	cam.look_at(aim)
	n += 1
	# warm-up frames let the damped pose settle before filming
	var f := n - 20
	if f >= 0 and f < int(CLIPS[clip] * FPS):
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(out_dir)
		img.save_png(out_dir.path_join("f_%03d.png" % f))
	if clip == "eat" and f == 75:
		print("MOUTH (rig space) ", cat.to_local(cat.mouth_world()))
	if f >= int(CLIPS[clip] * FPS):
		print("CLIP DONE ", clip)
		get_tree().quit()
