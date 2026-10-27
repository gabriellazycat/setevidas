class_name HoundBody
extends Node3D
## The spectral hound's body: the Blender-built rigged dog in ghost flesh, ember eyes, wisps of
## black smoke shed while it moves, driven procedurally (prowl, gallop, crouched tell, lunge,
## sniffing, snarl).

const SPECTRAL := preload("res://shaders/spectral.gdshader")

var skel: Skeleton3D
var flesh: ShaderMaterial
var eye_mat: StandardMaterial3D
var teeth_mat: StandardMaterial3D
var smoke: GPUParticles3D
var eye_light: OmniLight3D
var _b := {}
var _rest_rot := {}
var _rest_pos := {}
var _gbasis := {}
var _pgbasis := {}
var alpha := 0.0
var t := 0.0
var gait := 0.0
var st_speed := 0.0
var st_crouch := 0.0
var st_sniff := 0.0
var st_snarl := 0.0
var st_lunge := 0.0


func _ready() -> void:
	var inst: Node3D = (load("res://assets/models/ghosts/hound.glb") as PackedScene).instantiate()
	add_child(inst)
	skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		_b[n] = i
		_rest_rot[i] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_rest_pos[i] = skel.get_bone_rest(i).origin
		_gbasis[i] = skel.get_bone_global_rest(i).basis.orthonormalized()
		var p := skel.get_bone_parent(i)
		_pgbasis[i] = skel.get_bone_global_rest(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	flesh = ShaderMaterial.new()
	flesh.shader = SPECTRAL
	flesh.set_shader_parameter("body_color", Color(0.012, 0.007, 0.008))
	# an ember rim: in a dark hall the black dog has to read as a shape, not just two eyes
	flesh.set_shader_parameter("rim_color", Color(0.6, 0.16, 0.07))
	flesh.set_shader_parameter("wobble", 0.012)
	flesh.set_shader_parameter("dissolve", 0.18)
	flesh.set_shader_parameter("foot_fade", 0.18)
	flesh.set_shader_parameter("noise_tex", load("res://assets/textures/gen/noise.png"))
	eye_mat = StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.25, 0.08)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.22, 0.06)
	eye_mat.emission_energy_multiplier = 8.0
	eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	teeth_mat = StandardMaterial3D.new()
	teeth_mat.albedo_color = Color(0.62, 0.6, 0.52)
	teeth_mat.roughness = 0.35
	teeth_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := m.name.to_lower()
		if "eye" in n:
			m.material_override = eye_mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif "teeth" in n:
			m.material_override = teeth_mat
		else:
			m.material_override = flesh
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	smoke = FX.wisps(Color(0.02, 0.005, 0.005, 0.5), 0.9, 0.35, 40, false, 0.45)
	smoke.position = Vector3(0, 0.55, 0)
	add_child(smoke)
	eye_light = OmniLight3D.new()
	eye_light.light_color = Color(1.0, 0.25, 0.1)
	eye_light.omni_range = 1.6
	eye_light.light_energy = 0.0
	eye_light.shadow_enabled = false
	add_child(eye_light)
	scale = Vector3.ONE * 0.5


func _rot(n: String, e: Vector3) -> void:
	var i: int = _b.get(n, -1)
	if i < 0:
		return
	var g: Basis = _gbasis[i]
	var local := Quaternion(g.inverse() * Basis(Quaternion.from_euler(e)) * g)
	skel.set_bone_pose_rotation(i, (_rest_rot[i] as Quaternion) * local)


func _move(n: String, off: Vector3) -> void:
	var i: int = _b.get(n, -1)
	if i < 0:
		return
	skel.set_bone_pose_position(i, (_rest_pos[i] as Vector3) + (_pgbasis[i] as Basis).inverse() * off)


func head_world() -> Vector3:
	var i: int = _b.get("head", -1)
	if i < 0:
		return global_position + Vector3.UP * 0.9
	return skel.global_transform * (skel.get_bone_global_pose(i) * Vector3(0, 0.12, 0))


static func _damp(a: float, b: float, l: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-l * dt))


## speed: m/s along the ground; crouch: the tell; sniff: nose to the floor; snarl: jaw; lunge: leap
func update_pose(dt: float, speed: float, crouch: float, sniff: float, snarl: float, lunge: float, chasing: bool) -> void:
	if skel == null:
		return
	t += dt
	st_speed = _damp(st_speed, speed, 10, dt)
	st_crouch = _damp(st_crouch, crouch, 8, dt)
	st_sniff = _damp(st_sniff, sniff, 4, dt)
	st_snarl = _damp(st_snarl, snarl, 10, dt)
	st_lunge = _damp(st_lunge, lunge, 14, dt)
	flesh.set_shader_parameter("alpha", alpha)
	eye_mat.albedo_color.a = clampf(alpha * 1.4, 0, 1)
	teeth_mat.albedo_color.a = clampf(alpha * 1.1, 0, 1) * (0.4 + st_snarl * 0.6)
	eye_light.light_energy = alpha * (0.6 + (0.8 if chasing else 0.0))
	eye_light.global_position = head_world() + global_basis.z * 0.12
	smoke.emitting = alpha > 0.15
	smoke.amount_ratio = clampf(0.3 + st_speed * 0.15, 0, 1)
	visible = alpha > 0.01
	if not visible:
		return
	# a walk (lateral sequence) blending into a rotary gallop
	var moving := clampf(st_speed / 0.3, 0, 1)
	var gal := clampf((st_speed - 2.2) / 1.6, 0, 1)
	var stride := lerpf(0.9, 2.1, gal)
	gait += st_speed / stride * TAU * dt
	var g := gait
	var bob := -absf(sin(g)) * 0.025 * moving * (1.0 - gal) + sin(g) * 0.05 * gal
	var breathe := sin(t * (5.5 if st_snarl > 0.3 else 2.2)) * 0.006
	_move("hips", Vector3(0, bob + breathe - st_crouch * 0.14 - st_sniff * 0.03, 0))
	_rot("hips", Vector3(sin(g) * 0.1 * gal + st_crouch * 0.12, 0, sin(g * 0.5) * 0.04 * moving))
	var flex := sin(g) * 0.18 * gal
	_rot("spine", Vector3(flex + st_crouch * 0.1, 0, 0))
	_rot("chest", Vector3(-flex * 0.7 - st_crouch * 0.25 + st_lunge * 0.2, 0, 0))
	# head low and forward when stalking, nose to the floor when sniffing
	var sway := sin(t * 1.1) * 0.08 * (1.0 - moving)
	var neck_x := 0.35 * st_crouch + 0.75 * st_sniff + 0.2 * moving + sin(g * 2.0) * 0.05 * moving
	_rot("neck", Vector3(neck_x, sway + sin(t * 9.0) * 0.06 * st_sniff, 0))
	_rot("head", Vector3(-0.25 * st_crouch + 0.2 * st_sniff - 0.1 * moving + sin(t * 14.0) * 0.04 * st_sniff, sway * 0.6, 0))
	_rot("jaw", Vector3(st_snarl * 0.35 + st_lunge * 0.5 + sin(t * 23.0) * 0.03 * st_snarl, 0, 0))
	for side: int in [1, -1]:
		var sd := "L" if side > 0 else "R"
		_rot("ear." + sd, Vector3(-0.7 * maxf(st_crouch, st_snarl) + 0.15 * st_sniff, 0, side * 0.35 * st_crouch))
	# tail low, stiff when it hunts
	var tail_sw := sin(t * 3.0 + g * 0.5) * (0.25 - st_crouch * 0.18)
	for i in 4:
		_rot("tail%d" % i, Vector3((0.25 if i == 0 else 0.08) - st_crouch * 0.2 + gal * (0.3 if i == 0 else 0.0), tail_sw * (0.4 + i * 0.25), 0))
	var amp := lerpf(0.5, 0.95, gal) * moving
	# [side, front, walk phase, gallop phase]
	var legs := [["L", true, 0.0, 0.0], ["R", true, 0.5, 0.12], ["L", false, 0.75, 0.55], ["R", false, 0.25, 0.65]]
	for L in legs:
		var sd: String = L[0]
		var front: bool = L[1]
		var ph: float = lerpf(L[2], L[3], gal) * TAU
		var sw := sin(g + ph)
		var lift := maxf(0.0, cos(g + ph))
		var hip_a := sw * amp
		var knee_a := lift * (1.0 if front else 1.2) * moving
		if front:
			hip_a += 0.35 * st_crouch - 0.8 * st_lunge
			knee_a += -0.5 * st_crouch
			_rot("upperarm." + sd, Vector3(hip_a, 0, 0))
			_rot("forearm." + sd, Vector3(-knee_a * 0.7, 0, 0))
			_rot("fpaw." + sd, Vector3(-hip_a * 0.35 + knee_a * 0.4, 0, 0))
		else:
			hip_a += -0.45 * st_crouch + 0.7 * st_lunge
			knee_a += 0.9 * st_crouch
			_rot("thigh." + sd, Vector3(hip_a, 0, 0))
			_rot("shin." + sd, Vector3(-knee_a * 0.6, 0, 0))
			_rot("hock." + sd, Vector3(knee_a * 0.55 - hip_a * 0.3, 0, 0))
			_rot("hpaw." + sd, Vector3(-knee_a * 0.2 + hip_a * 0.2, 0, 0))
