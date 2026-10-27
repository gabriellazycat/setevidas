class_name GhostBody
extends Node3D
## A humanoid ghost: an MPFB body (the Shadow's emaciated frame, Dona Ivone, the hat man) dressed in
## spectral flesh, clinging smoke and two pin-prick eyes.

const SPECTRAL := preload("res://shaders/spectral.gdshader")

var rig: HumanRig
var mats: Array = []
var smoke: GPUParticles3D
var eyes: Array = []
var eye_mat: StandardMaterial3D
var alpha := 0.0:
	set(v):
		alpha = v
		_apply_alpha()
var limb_stretch := 1.0
## 0..1: how hard it is staring at the cat. Eyes and hands heat up to red (the warning before a hunt).
var glare := 0.0
## 0..1: the flesh itself turns ember red (spectral.gdshader heat)
var heat := 0.0:
	set(v):
		heat = v
		if toon:
			_apply_toon()
		for m in mats:
			(m as ShaderMaterial).set_shader_parameter("heat", v)
var _eye_base := Color.WHITE
var _hands: Array = []
var _hand_mat: StandardMaterial3D
var height_scale := 1.0
## the eye glow from the top of the neck, body axes (side, up, forward): the height of the MPFB eye
## sockets, measured on shadow_peek (the old 0.075 / 0.085 sat inside the forehead); the depth is
## taken from each face (_eye_offsets), this one only if the mesh gives none
const EYE := Vector3(0.032, 0.046, 0.128)
var _eye_local: Array = []
## true: the body is Clara's own anime model (toon, outline) instead of spectral flesh, a stranger
## that looks like her; pale skin, a cold cast, and the glare reddens it
var toon := false
var _toon_mats: Array = []     # [ShaderMaterial, base tint] of every toon surface


func _init(model_id: String, body_color := Color(0.004, 0.004, 0.006), rim := Color(0.1, 0.12, 0.16), wet := 0.0, smoke_col := Color(0.01, 0.01, 0.015, 0.55), height := 1.8, eye_col := Color(0.85, 0.92, 1.0), as_toon := false) -> void:
	toon = as_toon
	rig = HumanRig.new("clara", {"night": model_id}) if toon else HumanRig.new("ghost", {"day": model_id})
	add_child(rig)
	var m := ShaderMaterial.new()
	m.shader = SPECTRAL
	m.set_shader_parameter("body_color", body_color)
	m.set_shader_parameter("rim_color", rim)
	m.set_shader_parameter("wet", wet)
	m.set_shader_parameter("noise_tex", load("res://assets/textures/gen/noise.png"))
	mats.append(m)
	smoke = FX.wisps(smoke_col, height, 0.28, 56)
	add_child(smoke)
	eye_mat = StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = eye_col
	eye_mat.emission_enabled = true
	eye_mat.emission = eye_col
	eye_mat.emission_energy_multiplier = 6.0
	_eye_base = eye_col
	eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	eye_mat.no_depth_test = false
	eye_mat.render_priority = 2   # after the see-through flesh, which would cover them


## spectral.gdshader settings for this ghost (dissolve, foot_fade...)
func flesh(params: Dictionary) -> void:
	for m in mats:
		for k in params:
			(m as ShaderMaterial).set_shader_parameter(k, params[k])


## toon body: it fades through darkness (the toon shader cuts alpha, it cannot blend), reddens with heat
func _apply_toon() -> void:
	var k := clampf(alpha, 0.0, 1.0)
	for e in _toon_mats:
		var base: Color = e[1]
		var warm := Color(1.0, 0.42, 0.36)
		var c := base.lerp(warm, clampf(heat, 0.0, 1.0) * 0.7) * lerpf(0.03, 1.0, k * k)
		(e[0] as ShaderMaterial).set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	if eye_mat:
		eye_mat.albedo_color.a = clampf(alpha * 1.2, 0, 1)
	if smoke:
		smoke.emitting = alpha > 0.05
	visible = alpha > 0.01


func _ready() -> void:
	if toon:
		_ready_toon()
		return
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		var n := mm.name.to_lower()
		if n.ends_with("_eyes"):
			mm.visible = false
		elif n.ends_with("_teeth") or n.ends_with("_tongue") or n.ends_with("_eyelashes") or n.ends_with("_eyebrows"):
			mm.visible = false
		else:
			mm.material_override = mats[0]
			mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	scale = Vector3.ONE * height_scale
	# two pin-prick eyes that glow in the dark
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.009
		sm.height = 0.012
		sm.radial_segments = 8
		sm.rings = 4
		e.mesh = sm
		e.material_override = eye_mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.set_meta("side", sx)
		add_child(e)
		eyes.append(e)
	# red glow in the palms, only visible while it glares
	_hand_mat = StandardMaterial3D.new()
	_hand_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hand_mat.albedo_color = Color(1.0, 0.08, 0.04, 0.0)
	_hand_mat.emission_enabled = true
	_hand_mat.emission = Color(1.0, 0.08, 0.04)
	_hand_mat.emission_energy_multiplier = 0.0
	for b in ["hand_l", "hand_r"]:
		var h := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.05
		hm.height = 0.1
		hm.radial_segments = 10
		hm.rings = 5
		h.mesh = hm
		h.material_override = _hand_mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.set_meta("bone", b)
		h.visible = false
		add_child(h)
		_hands.append(h)
	_apply_alpha()


func _apply_alpha() -> void:
	if toon:
		_apply_toon()
		return
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("alpha", alpha)
	if eye_mat:
		eye_mat.albedo_color.a = clampf(alpha * 1.2, 0, 1)
	if smoke:
		smoke.emitting = alpha > 0.05
	visible = alpha > 0.01


func _ready_toon() -> void:
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		var part := mm.name.to_lower().get_slice("_", mm.name.to_lower().get_slice_count("_") - 1)
		# skin a shade too pale and cold, the clothes only a little
		var base := Color(0.8, 0.84, 0.92) if part == "body" else Color(0.9, 0.92, 0.96)
		for si in mm.mesh.get_surface_count():
			var sm := mm.get_surface_override_material(si) as ShaderMaterial
			if sm:
				_toon_mats.append([sm, base])
	scale = Vector3.ONE * height_scale
	# the pin-prick eyes only show once it glares (bigger than the ghosts', over the anime eyes)
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.014
		sm.height = 0.02
		sm.radial_segments = 8
		sm.rings = 4
		e.mesh = sm
		e.material_override = eye_mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.set_meta("side", sx)
		e.visible = false
		add_child(e)
		eyes.append(e)
	_apply_alpha()


## the eyes in the head bone's frame (from the rest pose, body facing +Z), so they turn and tilt with
## the head: on the face itself, just out of the skin in front of each socket (each MPFB head has
## its own shape, measured on the mesh in its bind pose)
func _eye_offsets() -> Array:
	var skel: Skeleton3D = rig.outfits[rig.cur_outfit]["skel"]
	var rest := skel.get_bone_global_rest(skel.find_bone("head"))
	var rest_inv := Transform3D(rest.basis.orthonormalized(), rest.origin).affine_inverse()
	var to_skel := (global_transform.affine_inverse() * skel.global_transform).basis.orthonormalized().inverse()
	# the skin in front of each eye, in the head's rest frame
	var front := [-INF, -INF]
	for mi in skel.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		if not mm.visible or mm.mesh == null:
			continue
		var to_head := rest_inv * (skel.global_transform.affine_inverse() * mm.global_transform)
		for s in mm.mesh.get_surface_count():
			for v: Vector3 in mm.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var hv := to_head * v
				if absf(hv.y - EYE.y) < 0.012 and hv.z > 0.05 and hv.z < 0.2:
					for k in 2:
						if absf(hv.x - EYE.x * (1.0 if k == 0 else -1.0)) < 0.01:
							front[k] = maxf(front[k], hv.z)
	var out := []
	for e: MeshInstance3D in eyes:
		var side := float(e.get_meta("side"))
		var z: float = front[0 if side > 0 else 1]
		var off := Vector3(EYE.x * side, EYE.y, z + 0.004 if z > 0.0 else EYE.z)
		out.append(rest.basis.orthonormalized().inverse() * (to_skel * off))
	return out


## the hand's world position: the IK target when it holds one (bone_world is the pose before the IK)
func _hand_at(bone: String) -> Vector3:
	var tgt = rig.hand_target_l if bone == "hand_l" else rig.hand_target
	if tgt != null:
		return tgt
	return rig.bone_world(bone).origin


func tick(dt: float) -> void:
	rig.update(dt)
	if eyes.size() > 0 and visible:
		var hb := rig.bone_world("head")
		if _eye_local.is_empty():
			_eye_local = _eye_offsets()
		for i in eyes.size():
			(eyes[i] as MeshInstance3D).global_position = hb.origin + hb.basis * (_eye_local[i] as Vector3)
		var g := clampf(glare, 0.0, 1.0)
		var ec := _eye_base.lerp(Color(1.0, 0.06, 0.02), g)
		ec.a = eye_mat.albedo_color.a
		eye_mat.albedo_color = ec
		eye_mat.emission = Color(ec.r, ec.g, ec.b)
		eye_mat.emission_energy_multiplier = 6.0 + 10.0 * g
		for e: MeshInstance3D in eyes:
			e.scale = Vector3.ONE * (1.0 + 0.8 * g)
		for h: MeshInstance3D in _hands:
			h.visible = g > 0.02
			if h.visible:
				h.global_position = _hand_at(h.get_meta("bone"))
		if _hand_mat:
			_hand_mat.albedo_color.a = 0.55 * g * clampf(alpha, 0, 1)
			_hand_mat.emission_energy_multiplier = 5.0 * g
	if limb_stretch != 1.0:
		var o: Dictionary = rig.outfits[rig.cur_outfit]
		var skel: Skeleton3D = o["skel"]
		for b in ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]:
			var i := skel.find_bone(b)
			if i >= 0:
				skel.set_bone_pose_scale(i, Vector3(1.0, limb_stretch, 1.0))
