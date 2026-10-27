class_name CatRig
extends Node3D
## Mingau's model: loads the Blender-built rigged cat, dresses it (anime toon + outline and painted
## anime eyes for Mingau, like Clara and Davi; shell fur for the old v1 cats) and
## drives every bone procedurally from a pose description (walk/run gait, sit, lie, crouch, jump,
## meow, hiss, scratch, purr, ears tracking danger, tail mood). Port of the web CatModel.

const FUR_SHADER := preload("res://shaders/fur.gdshader")
const EYE_SHADER := preload("res://shaders/cat_eye.gdshader")
const EYE_ANIME := preload("res://shaders/cat_eye_anime.gdshader")
const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
const SHELLS := 18
## the game's cat: the generated body with the white-and-orange coat and flat slit eyes
const GAME := "mingau_bolinha"
const V2 := ["mingau", "mingau_a", "mingau_b", "mingau_c", "mingau_a1", "mingau_a2", "mingau_a3", "mingau_creme", "mingau_bolinha"]   # variants built by build_cat2.py (generated base mesh, toon coat)
## style studies (build_cat2.py --look a|b|c): toon ramp and eye shader overrides per variant;
## a1-a3 share the look-a model ("model") with a coat painted by body position (gen_cat_coat.py)
## and pick which painted mouth lines show ("mouth": cat_mouthline_<id>)
## the game body with the from-scratch studies' coats and their flat slit eyes (model mingau_d:
## build_cat2.py --face decal; coats gen_cat_coat.py creme|bolinha --model cat_mingau_d)
const SLIT_EYE := {"decal": true, "iris_top": Color(0.4, 0.55, 0.08), "iris_bottom": Color(0.85, 0.9, 0.3),
	"rim_col": Color(0.12, 0.07, 0.06), "pupil_round": 0.0, "pupil_min": 0.12, "pupil_max": 0.4, "pupil_h": 0.78,
	"rim": 0.08, "hl": 0.26, "hl2": 0.1}
const LOOK := {
	"mingau_creme": {"model": "mingau_d", "toon": {"shade_soft": 0.12, "shade_amount": 0.7, "shade_color": Color(0.9, 0.74, 0.68)},
		"eye": SLIT_EYE, "lid": Color(0.99, 0.9, 0.78)},
	"mingau_bolinha": {"model": "mingau_d", "toon": {"shade_soft": 0.12, "shade_amount": 0.7, "shade_color": Color(0.9, 0.74, 0.68)},
		"eye": SLIT_EYE, "lid": Color(0.95, 0.56, 0.22)},
	"mingau_a1": {"model": "mingau_a", "mouth": ["ws"],
		"toon": {"shade_soft": 0.2, "shade_amount": 0.72, "shade_color": Color(0.9, 0.72, 0.66), "rim_strength": 0.3},
		"eye": {"iris_top": Color(0.62, 0.5, 0.12), "iris_bottom": Color(0.99, 0.86, 0.36), "rim_col": Color(0.16, 0.09, 0.05),
			"pupil_round": 1.0, "pupil_min": 0.3, "pupil_max": 0.72, "rim": 0.1, "hl": 0.3, "hl2": 0.09, "lid_color": Color(0.87, 0.53, 0.26)}},
	"mingau_a2": {"model": "mingau_a", "mouth": ["w", "ph"],
		"toon": {"shade_soft": 0.06, "shade_amount": 0.66, "shade_color": Color(0.88, 0.68, 0.66)},
		"eye": {"iris_top": Color(0.16, 0.36, 0.12), "iris_bottom": Color(0.72, 0.9, 0.38), "rim_col": Color(0.1, 0.06, 0.05),
			"pupil_round": 0.55, "pupil_min": 0.16, "pupil_max": 0.62, "pupil_h": 0.8, "rim": 0.11, "hl": 0.27, "hl2": 0.12,
			"lid_rest": 0.08, "lash": 0.1, "lid_tilt": 0.06, "lid_color": Color(0.86, 0.49, 0.22)}},
	"mingau_a3": {"model": "mingau_a", "mouth": ["w"],
		"toon": {"shade_soft": 0.1, "shade_amount": 0.66, "shade_color": Color(0.88, 0.7, 0.66)},
		"eye": {"iris_top": Color(0.3, 0.5, 0.14), "iris_bottom": Color(0.8, 0.88, 0.34), "pupil_round": 0.2,
			"pupil_min": 0.1, "pupil_max": 0.5, "rim": 0.09, "hl": 0.22, "hl2": 0.08, "lid_color": Color(0.82, 0.47, 0.21)}},
	"mingau_a": {"toon": {"shade_soft": 0.14, "shade_amount": 0.66}, "eye": {"pupil_round": 0.6, "pupil_max": 0.62, "rim": 0.09, "hl": 0.28}},
	"mingau_b": {"toon": {"shade_soft": 0.22, "shade_amount": 0.7, "rim_strength": 0.45}, "eye": {"pupil_round": 0.85, "pupil_max": 0.7, "rim": 0.08, "hl": 0.3}},
	"mingau_c": {"toon": {"shade_soft": 0.32, "shade_amount": 0.72, "shade_shift": -0.2, "rim_strength": 0.5}, "eye": {"pupil_round": 1.0, "pupil_max": 0.78, "rim": 0.07, "hl": 0.32, "hl2": 0.13}},
}

var skel: Skeleton3D
var body_mesh: MeshInstance3D
var fur_mats: Array[ShaderMaterial] = []
var eye_mats: Array[ShaderMaterial] = []
var _b := {}            # bone name -> index
var _rest_rot := {}     # index -> Quaternion (local rest)
var _rest_pos := {}     # index -> Vector3 (local rest)
var _gbasis := {}       # index -> Basis (global rest rotation, model space)
var _pgbasis := {}      # index -> Basis (parent global rest rotation)

# smoothed pose state
var st_speed := 0.0
var st_crouch := 0.0
var st_sit := 0.0
var st_lie := 0.0
var st_meow := 0.0
var st_hiss := 0.0
var st_bristle := 0.0
var st_tail_up := 0.6
var st_ear_yaw := 0.0
var st_ear_alert := 0.0
var st_head_yaw := 0.0
var st_head_pitch := 0.0
var st_pupil := 0.5
var st_scratch := 0.0
var st_jump := 0.0
var st_land := 0.0
var st_purr := 0.0
var st_wet := 0.0
var st_carry := 0.0
var st_eat := 0.0
## acting (prototypes for the trailer, see cat_anim.gd swat_*/cup_*/pounce_*/tilt_*/blink_*):
## swat is a raw 0..1 reach of one front paw (the caller shapes the timing), wiggle the butt
## wiggle before a pounce, tilt a head roll, slowblink a raw 0..1 lid
var st_swat := 0.0
var swat_side := "L"
var swat_hip := -1.1
var swat_knee := -0.15
var swat_paw := 0.0
var st_wiggle := 0.0
var wiggle_rate := 9.0
var st_tilt := 0.0
var st_slowblink := 0.0
var st_arch := 0.0      # Halloween-cat hump: back high in the middle, stiff legs (startle)
## aimed swat: the paw goes to swat_tgt (rig space) by IK, the shoulder swinging out toward it; a target
## above the reach of a standing cat makes it rear up on the hind legs
var swat_tgt = null
var st_rear := 0.0
var _shoulder_rest := Vector3.ZERO
var _fore_reach := 0.2
var t := 0.0
var gait := 0.0
var blink := 0.0
var blink_t := 2.0
var flick := 0.0
var flick_t := 3.0
var variant := GAME
var foot_fix := 0.0     # keeps the lowest paw on the ground whatever the pose
## per-model pose calibration (the v2 skeleton rests differently from v1)
var tune := {"tail_base": 0.0, "crouch_hind": -0.5, "crouch_hind_knee": 0.9}
## sitting: hips pitch and drop solved once from the skeleton (_solve_sit) so the rump rests on the
## floor and the shoulders sit right above straight front legs; the paws are placed by IK
const SIT_SPINE := 0.3       # the back rounds over the rump (takes most of the head levelling)
const SIT_CHEST := 0.2
const SIT_HIP_H := 0.07      # hip joint height when sitting (rump fur on the floor)
var sit_pitch := -0.6
var sit_drop := -0.1
## sitting, most of the head levelling is taken by the rounded back (SIT_SPINE/SIT_CHEST above); what is
## left spreads over the two neck bones and the head, so no single joint folds the throat
const SIT_NECK := [0.34, 0.33, 0.33]   # neck, neck1, head
## eating: the back and shoulders drop, the elbows bend so the paws stay put, the neck reaches down to
## the bowl on the floor and the jaw chews in short bursts
const EAT_SPINE := 0.24
const EAT_CHEST := 0.52
const EAT_NECK := [0.4, 0.06, -0.16]    # neck, neck1, head (radians, nose down)
var _rest_wrist := {}   # side -> fore paw wrist (fpaw head) in the rig's space, standing rest
var _rest_paw_ang := -0.6


func _init(v := GAME) -> void:
	variant = v
	if V2.has(v):
		tune = {"tail_base": 0.0, "crouch_hind": 0.2, "crouch_hind_knee": 0.5}


func _ready() -> void:
	var scene: PackedScene = load("res://assets/models/cat/cat_%s.glb" % LOOK.get(variant, {}).get("model", variant))
	var inst := scene.instantiate()
	add_child(inst)
	skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		_b[n] = i
		_b[n.replace(".", "_")] = i
		var rest := skel.get_bone_rest(i)
		_rest_rot[i] = rest.basis.get_rotation_quaternion()
		_rest_pos[i] = rest.origin
		_gbasis[i] = skel.get_bone_global_rest(i).basis.orthonormalized()
		var p := skel.get_bone_parent(i)
		_pgbasis[i] = skel.get_bone_global_rest(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	_dress(inst)
	_solve_sit()
	for sd in ["L", "R"]:
		_rest_wrist[sd] = _mpos("fpaw." + sd)
	_shoulder_rest = _mpos("upperarm.L")
	_fore_reach = _shoulder_rest.distance_to(_mpos("forearm.L")) + _mpos("forearm.L").distance_to(_mpos("fpaw.L"))
	_rest_paw_ang = _side_angle("fpaw.L")


func _dress(root: Node) -> void:
	var albedo: Texture2D = null if V2.has(variant) else load("res://assets/models/cat/cat_%s_albedo.png" % variant)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var n := m.name.to_lower()
		if n.begins_with("cat_body"):
			body_mesh = m
			if V2.has(variant):
				# v2: flat toon coat (tools/textures/gen_cat_toon.py), same ramp and outline as the humans
				m.material_override = _toon(load("res://assets/models/cat/cat_%s_toon.png" % variant))
			else:
				m.material_override = _fur_chain(albedo, SHELLS, 0.011, 260.0, load("res://assets/models/cat/cat_%s_furmask.png" % variant))
		elif n.begins_with("cat_decal_"):
			# painted nose / mouth decals: their own texture, cut by its alpha
			var dm := StandardMaterial3D.new()
			var src := m.mesh.surface_get_material(0) as BaseMaterial3D
			if src:
				dm.albedo_texture = src.albedo_texture
			dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			dm.roughness = 1.0
			dm.metallic_specular = 0.0
			m.material_override = dm
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("cat_ear"):
			var ginger := _solid(Color(0.8, 0.46, 0.19) if variant == "mingau" else Color(0.03, 0.026, 0.024))
			m.set_surface_override_material(0, _fur_chain(ginger, 6, 0.004, 320.0))
			if m.mesh.get_surface_count() > 1:
				var inner := StandardMaterial3D.new()
				inner.albedo_color = Color(0.86, 0.6, 0.58)
				inner.roughness = 0.6
				inner.subsurf_scatter_enabled = true
				inner.subsurf_scatter_strength = 0.4
				m.set_surface_override_material(1, inner)
		elif n.begins_with("cat_eye"):
			var em := ShaderMaterial.new()
			em.shader = EYE_ANIME if V2.has(variant) else EYE_SHADER
			if V2.has(variant):
				em.set_shader_parameter("side", 1.0 if n.contains("eye_l") else -1.0)
			if variant == "breu":
				em.set_shader_parameter("iris_inner", Color(0.85, 0.75, 0.25))
				em.set_shader_parameter("lid_color", Color(0.03, 0.03, 0.03))
			for k in LOOK.get(variant, {}).get("eye", {}):
				em.set_shader_parameter(k, LOOK[variant]["eye"][k])
			if LOOK.get(variant, {}).has("lid"):
				em.set_shader_parameter("lid_color", LOOK[variant]["lid"])
			if LOOK.get(variant, {}).get("eye", {}).get("decal", false):
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			eye_mats.append(em)
			m.material_override = em
		elif n.begins_with("cat_nose"):
			var nm := StandardMaterial3D.new()
			nm.albedo_color = Color(0.88, 0.56, 0.58) if variant == "mingau" else Color(0.06, 0.05, 0.05)
			nm.roughness = 0.35
			m.material_override = nm
		elif n.begins_with("cat_whisker"):
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.96, 0.95, 0.9)
			wm.roughness = 0.4
			m.material_override = wm
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("cat_mouthline_"):
			# painted-look mouth strokes (build_cat2.py mouth_lines): only the variant's own show
			var id := n.trim_prefix("cat_mouthline_").get_slice(".", 0)
			m.visible = (LOOK.get(variant, {}).get("mouth", []) as Array).has(id)
			var ml := StandardMaterial3D.new()
			ml.albedo_color = Color(0.3, 0.13, 0.1)
			ml.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ml.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.material_override = ml
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("cat_mouthline"):
			var ml := StandardMaterial3D.new()
			ml.albedo_color = Color(0.22, 0.1, 0.09) if variant == "mingau" else Color(0.01, 0.01, 0.01)
			ml.roughness = 0.6
			m.material_override = ml
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.begins_with("cat_mouth"):
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(0.3, 0.06, 0.08)
			mm.roughness = 0.3
			m.material_override = mm


func _solid(c: Color) -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _toon(albedo: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("shade_color", Color(0.86, 0.66, 0.66))
	m.set_shader_parameter("shade_amount", 0.6)
	m.set_shader_parameter("shade_shift", -0.1)
	m.set_shader_parameter("shade_soft", 0.05)
	m.set_shader_parameter("rim_strength", 0.35)
	for k in LOOK.get(variant, {}).get("toon", {}):
		m.set_shader_parameter(k, LOOK[variant]["toon"][k])
	var ol := ShaderMaterial.new()
	ol.shader = OUTLINE
	ol.set_shader_parameter("albedo_tex", albedo)
	ol.set_shader_parameter("width", 0.0012)
	m.next_pass = ol
	return m


func _fur_chain(albedo: Texture2D, shells: int, length: float, density: float, mask: Texture2D = null, normal: Texture2D = null) -> ShaderMaterial:
	var strands: Texture2D = load("res://assets/textures/gen/fur_strands.png")
	var first: ShaderMaterial = null
	var prev: ShaderMaterial = null
	for i in shells + 1:
		var m := ShaderMaterial.new()
		m.shader = FUR_SHADER
		m.set_shader_parameter("albedo_tex", albedo)
		m.set_shader_parameter("strands", strands)
		m.set_shader_parameter("shell", float(i) / float(shells))
		m.set_shader_parameter("fur_length", length)
		m.set_shader_parameter("density", density)
		if mask:
			m.set_shader_parameter("fur_mask", mask)
		elif V2.has(variant):
			m.set_shader_parameter("use_vertex_mask", true)
		if normal:
			m.set_shader_parameter("normal_tex", normal)
			m.set_shader_parameter("use_normal", true)
		if prev:
			prev.next_pass = m
		else:
			first = m
		prev = m
		fur_mats.append(m)
	return first


# ---------------------------------------------------------------------- bones


func _bone(n: String) -> int:
	return _b.get(n, -1)


## rotate a bone by an Euler (model-space axes, radians) relative to its rest pose
func _rot(n: String, e: Vector3) -> void:
	var i := _bone(n)
	if i < 0:
		return
	var q := Quaternion.from_euler(e)
	var g: Basis = _gbasis[i]
	var local := Quaternion(g.inverse() * Basis(q) * g)
	skel.set_bone_pose_rotation(i, (_rest_rot[i] as Quaternion) * local)


## translate a bone by a model-space offset relative to its rest position
func _move(n: String, off: Vector3) -> void:
	var i := _bone(n)
	if i < 0:
		return
	var pb: Basis = _pgbasis[i]
	skel.set_bone_pose_position(i, (_rest_pos[i] as Vector3) + pb.inverse() * off)


## bone head in the rig's own space (+Z forward, Y up, floor at 0)
func _mpos(n: String) -> Vector3:
	var to_rig := global_transform.affine_inverse() * skel.global_transform
	return to_rig * skel.get_bone_global_pose(_bone(n)).origin


## side-view angle (forward, up) of a bone: toward its child's head, or along its own axis for a leaf
func _side_angle(n: String, child := "") -> float:
	var d: Vector3
	if child != "":
		d = _mpos(child) - _mpos(n)
	else:
		var to_rig := global_transform.affine_inverse() * skel.global_transform
		d = to_rig.basis * skel.get_bone_global_pose(_bone(n)).basis.y
	return atan2(d.y, d.z)


## turns a leg bone (X rotation value v) until its side-view angle is ang; returns the new value
func _aim(n: String, child: String, v: float, ang: float) -> float:
	_rot(n, Vector3(v, 0, 0))
	var a0 := _side_angle(n, child)
	_rot(n, Vector3(v + 0.05, 0, 0))
	var k := wrapf(_side_angle(n, child) - a0, -PI, PI) / 0.05
	if absf(k) < 0.2:
		_rot(n, Vector3(v, 0, 0))
		return v
	var nv := v + wrapf(ang - a0, -PI, PI) / k
	_rot(n, Vector3(nv, 0, 0))
	return nv


## two-bone IK in the side view: puts the head of `end` on target; bend -1 = joint toward the back
func _ik2(upper: String, lower: String, end: String, target: Vector3, bend: float, vu: float, vl: float) -> Array:
	var sp := _mpos(upper)
	var a := sp.distance_to(_mpos(lower))
	var b := _mpos(lower).distance_to(_mpos(end))
	var d2 := Vector2(target.z - sp.z, target.y - sp.y)
	var d := clampf(d2.length(), absf(a - b) + 0.001, a + b - 0.001)
	var alpha := acos(clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0))
	vu = _aim(upper, lower, vu, d2.angle() + bend * alpha)
	var ep := _mpos(lower)
	vl = _aim(lower, end, vl, Vector2(target.z - ep.z, target.y - ep.y).angle())
	return [vu, vl]


## finds the hips pitch and drop of the sitting pose for this skeleton (rest legs, rounded back)
func _solve_sit() -> void:
	var reach := _mpos("upperarm.L").distance_to(_mpos("forearm.L")) + _mpos("forearm.L").distance_to(_mpos("fpaw.L"))
	var shoulder_h := _mpos("fpaw.L").y + reach * 0.96
	_rot("spine", Vector3(SIT_SPINE, 0, 0))
	_rot("chest", Vector3(SIT_CHEST, 0, 0))
	for it in 30:
		_move("hips", Vector3(0, sit_drop, 0))
		_rot("hips", Vector3(sit_pitch, 0, 0))
		var hy := _mpos("thigh.L").y
		var sy := _mpos("upperarm.L").y
		sit_drop += SIT_HIP_H - hy
		_rot("hips", Vector3(sit_pitch - 0.02, 0, 0))
		var ds := (_mpos("upperarm.L").y - _mpos("thigh.L").y) - (sy - hy)
		if absf(ds) > 1e-5:
			sit_pitch += clampf((shoulder_h - SIT_HIP_H - (sy - hy)) / ds * -0.02, -0.1, 0.1)
	skel.reset_bone_poses()


func mouth_world() -> Vector3:
	var i := _bone("jaw")
	if i < 0:
		return global_position + global_basis.z * 0.3 + Vector3.UP * 0.26
	var gp := skel.get_bone_global_pose(i)
	return skel.global_transform * (gp * Vector3(0, 0.03, 0.0))


## the mouth as a frame: x across the snout, y up from the head, z out of the snout; follows the
## head when it dips (eating, sniffing, lying down)
func mouth_frame() -> Transform3D:
	var m := mouth_world()
	var fwd := m - head_world()
	if fwd.length() < 1e-4:
		fwd = global_basis.z
	fwd = fwd.normalized()
	var side := Vector3.UP.cross(fwd)
	side = side.normalized() if side.length() > 1e-4 else global_basis.x
	return Transform3D(Basis(side, fwd.cross(side), fwd), m)


func head_world() -> Vector3:
	var i := _bone("head")
	if i < 0:
		return global_position + Vector3.UP * 0.3
	return skel.global_transform * skel.get_bone_global_pose(i).origin


# ---------------------------------------------------------------------- animation


## walking: the paw lands flat and hangs a little while it swings, whatever the leg angle
func _level_paw(n: String, v: float, lift: float, w: float) -> void:
	if w < 0.01:
		return
	var flat := _aim(n, "", v, lerpf(-0.45, -1.0, lift))
	_rot(n, Vector3(lerpf(v, flat, w), 0, 0))


static func _lerp_leg(a: Array, b: Array, w: float) -> Array:
	var out := []
	for i in a.size():
		out.append(lerpf(a[i], b[i], w))
	return out


## sitting front leg: straight under the shoulder, paw flat on the floor a little ahead
func _sit_front(sd: String, v: Array) -> Array:
	var sp := _mpos("upperarm." + sd)
	var r := _ik2("upperarm." + sd, "forearm." + sd, "fpaw." + sd, Vector3(sp.x, 0.03, sp.z + 0.012), -1.0, v[0], v[1])
	return [r[0], r[1], _aim("fpaw." + sd, "", v[2], -0.35)]


## sitting hind leg: heel flat on the floor under the hip, knee up beside the belly, paw forward
func _sit_hind(sd: String, v: Array) -> Array:
	var hp := _mpos("thigh." + sd)
	var r := _ik2("thigh." + sd, "shin." + sd, "hock." + sd, Vector3(hp.x, 0.022, hp.z + 0.02), 1.0, v[0], v[1])
	var hv := _aim("hock." + sd, "hpaw." + sd, v[2], -0.12)
	return [r[0], r[1], hv, _aim("hpaw." + sd, "", v[3], -0.3)]


## eating front leg: the shoulder has dropped, the elbow bends back so the paw stays where it stood
func _eat_front(sd: String, v: Array) -> Array:
	var w: Vector3 = _rest_wrist[sd]
	var r := _ik2("upperarm." + sd, "forearm." + sd, "fpaw." + sd, Vector3(w.x, w.y, w.z), -1.0, v[0], v[1])
	return [r[0], r[1], _aim("fpaw." + sd, "", v[2], _rest_paw_ang)]


## aimed fore leg: IK in the leg's own vertical plane (the horizontal distance to the target laid out
## ahead of the shoulder), then the shoulder yaws toward it; returns [upperarm, forearm, paw, yaw]
func _reach_front(sd: String, tgt: Vector3, v: Array) -> Array:
	var sp := _mpos("upperarm." + sd)
	var dx := tgt.x - sp.x
	var dz := tgt.z - sp.z
	var h := maxf(0.04, sqrt(dx * dx + dz * dz))
	var yw := clampf(atan2(dx, maxf(dz, 0.02)), -0.9, 0.9)
	var r := _ik2("upperarm." + sd, "forearm." + sd, "fpaw." + sd, Vector3(sp.x, tgt.y, sp.z + h), -1.0, v[0], v[1])
	# the paw points at what it touches, a little down, pads first
	var pw := _aim("fpaw." + sd, "", v[2], -0.75)
	return [r[0], r[1], pw, yw]


static func _damp(a: float, b: float, l: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-l * dt))


## curled up asleep (in bed with Clara): the loaf leaning a little onto one side, the spine bent
## sideways into a C so the head comes round to rest by the hind legs, chin down on the front paws,
## the tail wrapped round to the nose
var st_curl := 0.0
var CURL_HIND := [-0.6, 2.95]
var CURL_IN := -0.6   # hind hip / knee while curled (var: tuned with cat_anim --curlhind=)
const CURL := {"drop": 0.02, "roll": 0.08, "spine_y": 0.7, "chest_y": 0.65, "neck_y": 0.7, "head_y": 0.45,
	"neck_x": 0.55, "neck1_x": 0.25, "head_x": 0.05, "tail_y": -0.75}


func update_pose(dt: float, p: Dictionary) -> void:
	if skel == null:
		return
	t += dt
	var k := 10.0
	st_speed = _damp(st_speed, p.get("speed", 0.0), 12, dt)
	st_crouch = _damp(st_crouch, p.get("crouch", 0.0), k, dt)
	st_sit = _damp(st_sit, p.get("sit", 0.0), 4, dt)
	st_lie = _damp(st_lie, p.get("lie", 0.0), 3, dt)
	st_meow = _damp(st_meow, p.get("meow", 0.0), 14, dt)
	st_hiss = _damp(st_hiss, p.get("hiss", 0.0), 16, dt)
	st_bristle = _damp(st_bristle, maxf(p.get("bristle", 0.0), p.get("hiss", 0.0)), 8, dt)
	st_tail_up = _damp(st_tail_up, p.get("tail_up", 0.6), 3, dt)
	st_ear_yaw = lerp_angle(st_ear_yaw, p.get("ear_yaw", 0.0), 1.0 - exp(-6 * dt))
	st_ear_alert = _damp(st_ear_alert, p.get("ear_alert", 0.0), 5, dt)
	st_head_yaw = lerp_angle(st_head_yaw, p.get("head_yaw", 0.0), 1.0 - exp(-6 * dt))
	st_head_pitch = _damp(st_head_pitch, p.get("head_pitch", 0.0), 6, dt)
	st_pupil = _damp(st_pupil, p.get("pupil", 0.3), 5, dt)
	st_scratch = _damp(st_scratch, p.get("scratch", 0.0), 8, dt)
	st_jump = _damp(st_jump, 0.0 if p.get("grounded", true) else 1.0, 14, dt)
	st_land = _damp(st_land, p.get("land", 0.0), 18, dt)
	st_purr = _damp(st_purr, p.get("purr", 0.0), 3, dt)
	st_wet = _damp(st_wet, p.get("wet", 0.0), 2, dt)
	st_carry = _damp(st_carry, 1.0 if p.get("carry", false) else 0.0, 10, dt)
	st_eat = _damp(st_eat, p.get("eat", 0.0), 6, dt)
	st_curl = _damp(st_curl, p.get("curl", 0.0), 2.2, dt)
	st_swat = p.get("swat", 0.0)
	swat_side = p.get("swat_side", "L")
	swat_hip = p.get("swat_hip", -1.1)
	swat_knee = p.get("swat_knee", -0.15)
	swat_paw = p.get("swat_paw", 0.0)
	swat_tgt = p.get("swat_target", null)
	var rear_to := 0.0
	if swat_tgt != null:
		rear_to = clampf(((swat_tgt as Vector3).y - (_shoulder_rest.y + _fore_reach * 0.45)) / 0.22, 0.0, 1.0) * st_swat
	st_rear = _damp(st_rear, rear_to, 12, dt)
	st_wiggle = _damp(st_wiggle, p.get("wiggle", 0.0), 8, dt)
	wiggle_rate = p.get("wiggle_rate", 9.0)
	st_tilt = _damp(st_tilt, p.get("tilt", 0.0), 5, dt)
	st_slowblink = p.get("slowblink", 0.0)
	st_arch = _damp(st_arch, p.get("arch", 0.0), 14, dt)
	var vy: float = p.get("vy", 0.0)

	var moving := clampf(st_speed / 0.4, 0, 1)
	var run_k := clampf((st_speed - 2.4) / 1.6, 0, 1)
	var walking := moving * (1.0 - run_k) * (1.0 - st_jump) * (1.0 - st_sit) * (1.0 - st_lie) * (1.0 - st_scratch)
	# a longer, slower step as the walk speeds up (a cat walking fast doesn't scurry)
	var walk_k := clampf((st_speed - 0.6) / 1.5, 0, 1)
	var stride := lerpf(lerpf(0.36, 0.52, walk_k), 0.85, run_k)
	gait += (st_speed / stride) * TAU * dt
	var g := gait

	# ---- body (hips carry the whole spine)
	var breathe := sin(t * (3.2 if st_purr > 0.1 else 1.9)) * 0.003
	var bob := -absf(sin(g)) * 0.01 * moving * (1.0 - run_k) - absf(sin(g)) * 0.018 * run_k
	var body_y := bob + breathe - st_crouch * 0.05 - st_lie * 0.105 - st_curl * CURL["drop"] + st_sit * sit_drop + st_hiss * 0.03 - st_land * 0.035 + st_scratch * 0.1 + st_arch * 0.035 + st_rear * 0.07
	var pitch := sin(g) * 0.07 * run_k + st_sit * sit_pitch - st_scratch * 1.1 - st_rear * 0.85 + st_jump * clampf(-vy * 0.12, -0.5, 0.5) - st_arch * 0.5
	_move("hips", Vector3(0, body_y + foot_fix * (1.0 - st_sit), 0))
	# walking, the hips roll over whichever hind leg is carrying the weight
	# wiggle (before a pounce): the rump swings side to side and the spine undoes it so the head stays on target;
	# swat: the weight rolls onto the paw that stays down
	var wig := sin(t * wiggle_rate) * st_wiggle
	var swat_roll := st_swat * 0.07 * (1.0 if swat_side == "L" else -1.0)
	_rot("hips", Vector3(pitch, -st_curl * CURL["spine_y"] * 0.6 + wig * 0.2, sin(g + PI * 0.5) * 0.045 * moving * (1.0 - run_k) + st_curl * CURL["roll"] + wig * 0.08 + swat_roll))
	# hiss: the back arches; lie: the spine relaxes; run: flexing spine
	var flex := sin(g) * 0.12 * run_k
	# eating (standing still): the front of the body crouches toward the bowl
	var eat_k := st_eat * (1.0 - st_sit) * (1.0 - st_lie) * (1.0 - moving)
	_rot("spine", Vector3(-st_hiss * 0.35 * (1.0 - st_arch) + st_arch * 0.45 + flex - st_lie * 0.05 + st_sit * SIT_SPINE + eat_k * EAT_SPINE, st_head_yaw * 0.15 + st_curl * CURL["spine_y"] - wig * 0.14, -wig * 0.05))
	# the shoulders roll the other way over the front legs
	_rot("chest", Vector3(-st_hiss * 0.25 * (1.0 - st_arch) + st_arch * 0.5 - flex * 0.6 + st_crouch * 0.1 + st_sit * SIT_CHEST + eat_k * EAT_CHEST, st_head_yaw * 0.25 + st_curl * CURL["chest_y"] - wig * 0.08, sin(g - PI * 0.5) * 0.035 * moving * (1.0 - run_k) - swat_roll * 0.5))

	# ---- head
	# sitting, the neck undoes what is left of the body's tilt so the head stays level (eyes ahead,
	# chin a bit down), spread over neck, neck1 and head
	var sit_level := (-(sit_pitch + SIT_SPINE + SIT_CHEST) + 0.12) * st_sit
	var head_pitch := st_crouch * 0.25 - st_meow * 0.35 + st_hiss * 0.25 + st_scratch * 0.9 + st_lie * 0.15
	# chewing: short bursts of quick bites, the head bobbing a little with each one
	var chew_on := smoothstep(-0.2, 0.3, sin(t * 1.7) + 0.35 * sin(t * 4.1))
	var bite := pow(0.5 + 0.5 * sin(t * 15.0), 2.0) * chew_on * st_eat
	var eat_n: float = eat_k + st_eat * 0.25 * (1.0 - eat_k)   # sitting/lying it only bows the head
	var nk := -0.05 + 0.14 * walking + head_pitch * 0.4 + st_head_pitch * 0.35 - st_arch * 0.55
	_rot("neck", Vector3(nk + sit_level * SIT_NECK[0] + eat_n * EAT_NECK[0] + st_curl * CURL["neck_x"], st_head_yaw * 0.2 + st_curl * CURL["neck_y"], 0))
	_rot("neck1", Vector3(head_pitch * 0.3 + st_head_pitch * 0.3 + sit_level * SIT_NECK[1] + eat_n * EAT_NECK[1] + bite * 0.04 + st_curl * CURL["neck1_x"], st_head_yaw * 0.2, st_tilt * 0.35))
	_rot("head", Vector3(head_pitch * 0.3 + st_head_pitch * 0.35 - st_lie * 0.2 + sit_level * SIT_NECK[2] + eat_n * EAT_NECK[2] - bite * 0.05 + st_curl * CURL["head_x"], st_head_yaw * 0.2 + st_curl * CURL["head_y"], st_tilt * 0.65))
	_rot("jaw", Vector3(st_meow * 0.5 + st_hiss * 0.65 + st_carry * 0.22 + bite * 0.2, 0, 0))

	# ---- eyes
	blink_t -= dt
	if blink_t < 0:
		blink = 1.0
		blink_t = randf_range(2.0, 6.0)
	blink = maxf(0.0, blink - dt * 7.0)
	var lid := blink
	lid = maxf(lid, st_lie * (0.85 if st_purr > 0.5 else 0.35))
	lid = maxf(lid, st_slowblink)
	for em in eye_mats:
		em.set_shader_parameter("pupil", st_pupil)
		em.set_shader_parameter("blink", lid)
		em.set_shader_parameter("shine", 0.15 + st_pupil * 0.4)

	# ---- ears
	flick_t -= dt
	if flick_t < 0:
		flick = 1.0
		flick_t = randf_range(2.0, 7.0)
	flick = maxf(0.0, flick - dt * 6.0)
	for side: int in [1, -1]:
		var yaw := clampf(st_ear_yaw * st_ear_alert, -1.3, 1.3)
		var ex := -st_hiss * 0.45 + st_ear_alert * 0.15 - (flick * 0.4 if side > 0 else 0.0)
		var ey := yaw * 0.9 + (0.12 * side) * (1.0 - st_ear_alert)
		var ez := side * (st_hiss * 0.5 + st_lie * 0.15)
		_rot("ear.L" if side > 0 else "ear.R", Vector3(ex, ey, ez))

	# ---- tail
	var sway := sin(t * (1.2 + st_bristle * 3.0)) * (0.18 + moving * 0.1)
	# sitting or lying, the tail drops to the floor and curls around the paws
	var rest_k := clampf(st_sit + st_lie, 0, 1)
	var base := lerpf(-0.45, 0.85, st_tail_up) + st_hiss * 0.45 - st_crouch * 0.7 - st_lie * 0.55 - st_sit * 0.5
	for i in 5:
		var f := float(i) / 5.0
		var hook := (0.25 if f > 0.5 else 0.06) if st_tail_up > 0.5 else 0.1
		var tx := base + st_curl * 0.35 if i == 0 else lerpf(hook * (1.0 - st_hiss), 0.2, rest_k) - st_curl * 0.12
		var ty := sway * (0.3 + f) * 0.4 * (1.0 - rest_k * 0.7) + rest_k * 0.36 + st_curl * CURL["tail_y"] * (0.3 + f * 1.4)
		# wiggling, the tip twitches fast
		ty += sin(t * 11.0 - f * 4.0) * st_wiggle * 0.35 * f
		_rot("tail%d" % i, Vector3(tx, ty, 0))

	# ---- legs
	var amp := lerpf(lerpf(0.55, 0.72, walk_k), 0.9, run_k) * moving
	# walk: lateral sequence (each hind leg a quarter cycle ahead of the front leg on its side);
	# run: rotary gallop
	var legs := [["L", true, 0.0, 0.5], ["R", true, 0.5, 0.6], ["L", false, 0.75, 0.0], ["R", false, 0.25, 0.1]]
	var sit_ik := st_sit > 0.01
	for L in legs:
		var sd: String = L[0]
		var front: bool = L[1]
		var ph: float = lerpf(L[2], L[3], run_k) * TAU
		var sw := sin(g + ph)
		var lift := maxf(0.0, cos(g + ph))
		var hip_a := sw * amp
		# the hind paw skims the floor on its way forward instead of high-stepping
		var knee_a := lift * (0.9 if front else 0.7) * moving
		if front:
			hip_a += 0.3 * st_crouch
			knee_a += -0.6 * st_crouch
		else:
			hip_a += tune["crouch_hind"] * st_crouch
			knee_a += tune["crouch_hind_knee"] * st_crouch
		hip_a = lerpf(hip_a, 1.0 if front else -1.2, st_lie)
		knee_a = lerpf(knee_a, -2.0 if front else 2.3, st_lie)
		if not front:
			# curled up: the hind legs fold forward under the belly instead of the loaf's tuck
			hip_a = lerpf(hip_a, CURL_HIND[0], st_curl)
			knee_a = lerpf(knee_a, CURL_HIND[1], st_curl)
		hip_a = lerpf(hip_a, -0.75 if front else 0.8, st_jump * 0.8)
		knee_a = lerpf(knee_a, -0.15 if front else 0.25, st_jump * 0.8)
		if front and st_scratch > 0.01:
			hip_a = lerpf(hip_a, -1.4 + sin(t * 14 + (PI if sd == "R" else 0.0)) * 0.35, st_scratch)
			knee_a = lerpf(knee_a, -0.3, st_scratch)
		if not front:
			hip_a = lerpf(hip_a, 1.0, st_scratch)
			# reared up for a high target: the hind legs carry the body like when scratching
			hip_a = lerpf(hip_a, 0.8, st_rear)
		elif sd != swat_side:
			# the other fore paw comes off the floor and tucks in
			hip_a = lerpf(hip_a, -0.6, st_rear)
			knee_a = lerpf(knee_a, -1.2, st_rear)
		var swat_k := st_swat if front and sd == swat_side and swat_tgt == null else 0.0
		if swat_k > 0.001:
			hip_a = lerpf(hip_a, swat_hip, swat_k)
			knee_a = lerpf(knee_a, swat_knee, swat_k)
		hip_a *= 1.0 - st_hiss * 0.5
		# arched: stiff straight legs, undoing the hump's tilt so they stand plumb
		knee_a *= 1.0 - st_arch
		hip_a += st_arch * (-0.45 if front else 0.5)
		knee_a *= 1.0 - st_hiss * 0.8
		var v: Array
		if front:
			v = [hip_a, knee_a * -0.55, -hip_a * 0.4 + knee_a * 0.3 + lift * 0.3 * moving + swat_paw * swat_k]
			if sit_ik:
				v = _lerp_leg(v, _sit_front(sd, v), st_sit)
			elif eat_k > 0.01:
				v = _lerp_leg(v, _eat_front(sd, v), eat_k)
			var reach_yaw := 0.0
			if swat_tgt != null and sd == swat_side and st_swat > 0.001:
				_rot("upperarm." + sd, Vector3(v[0], 0, 0))
				var r := _reach_front(sd, swat_tgt, v)
				v = _lerp_leg(v, r, st_swat)
				reach_yaw = r[3] * st_swat
			_rot("upperarm." + sd, Vector3(v[0], reach_yaw, 0))
			_rot("forearm." + sd, Vector3(v[1], 0, 0))
			_rot("fpaw." + sd, Vector3(v[2], 0, 0))
			_level_paw("fpaw." + sd, v[2], lift, walking)
		else:
			v = [hip_a, -knee_a * 0.55, knee_a * 0.45 - hip_a * 0.3, -knee_a * 0.2 + hip_a * 0.2]
			if sit_ik:
				v = _lerp_leg(v, _sit_hind(sd, v), st_sit)
			# curled: the thighs swing in under the belly (the paws stay inside the curl)
			_rot("thigh." + sd, Vector3(v[0], 0, st_curl * CURL_IN * (1.0 if sd == "L" else -1.0)))
			_rot("shin." + sd, Vector3(v[1], 0, 0))
			_rot("hock." + sd, Vector3(v[2], 0, 0))
			_rot("hpaw." + sd, Vector3(v[3], 0, 0))
			_level_paw("hpaw." + sd, v[3], lift, walking)

	# ---- ground contact: measure the lowest paw and settle the body onto it
	# (sitting, the solved drop already rests the rump on the floor)
	if st_jump < 0.2:
		var lowest := INF
		for b in ["fpaw.L", "fpaw.R", "hpaw.L", "hpaw.R"]:
			var bi := _bone(b)
			if bi >= 0:
				lowest = minf(lowest, (skel.global_transform * skel.get_bone_global_pose(bi).origin).y)
		if lowest < INF:
			var off := lowest - global_position.y - 0.016
			foot_fix = clampf(foot_fix - off * (1.0 - exp(-12.0 * dt)), -0.09, 0.06)
	else:
		foot_fix = lerpf(foot_fix, 0.0, 1.0 - exp(-6.0 * dt))

	# ---- puffed up (startled, hunted): the toon coat has no fur to raise, so the tail thickens and the
	# body swells a little
	var puff := st_bristle
	for pb: Array in [["tail0", 0.55], ["spine", 0.05]]:
		var bi := _bone(pb[0])
		if bi >= 0:
			var sw: float = 1.0 + float(pb[1]) * puff
			skel.set_bone_pose_scale(bi, Vector3(sw, 1.0, sw))

	# ---- fur
	for fm in fur_mats:
		fm.set_shader_parameter("bristle", st_bristle)
		fm.set_shader_parameter("wet", st_wet)
