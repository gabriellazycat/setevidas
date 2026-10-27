class_name ShadowPeek
extends Node3D
## What shows of the Shadow in a hiding place: its head and two long-fingered hands
## (shadow_peek.glb, tools/blender/build_shadow_forms.py), each placed on its own by points, with no
## rig. heat turns the flesh ember red, the eyes swell and burn and a red light falls on whatever is
## around: the warning before it charges.

const SPECTRAL := preload("res://shaders/spectral.gdshader")
const MODEL := "res://assets/models/people/shadow_peek.glb"

var head: Node3D
var hands: Array[Node3D] = []      # [hand_l, hand_r]
var mat: ShaderMaterial
var eye_mat: StandardMaterial3D
var eyes: Array[MeshInstance3D] = []
var glow: OmniLight3D
var size := 1.12
var alpha := 0.0:
	set(v):
		alpha = v
		mat.set_shader_parameter("alpha", v)
		eye_mat.albedo_color.a = clampf(v * 1.2, 0, 1)
		visible = v > 0.01
var heat := 0.0
var _t := 0.0


func _init() -> void:
	mat = ShaderMaterial.new()
	mat.shader = SPECTRAL
	mat.set_shader_parameter("body_color", Color(0.002, 0.002, 0.003))
	mat.set_shader_parameter("rim_color", Color(0.07, 0.08, 0.11))
	mat.set_shader_parameter("noise_tex", load("res://assets/textures/gen/noise.png"))
	mat.set_shader_parameter("wobble", 0.006)
	mat.set_shader_parameter("dissolve", 0.1)
	# the cut ends (neck, wrist) point down their -Y: they trail off into smoke
	mat.set_shader_parameter("fade_y0", -0.09)
	mat.set_shader_parameter("foot_fade", 0.07)
	mat.set_shader_parameter("fade_noise", 0.25)
	eye_mat = StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	eye_mat.emission_enabled = true
	eye_mat.albedo_color = Color(0.85, 0.92, 1.0)
	# drawn after the see-through flesh, or the head covers them
	eye_mat.render_priority = 2


func _ready() -> void:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	head = model.find_child("head", true, false)
	hands = [model.find_child("hand_l", true, false), model.find_child("hand_r", true, false)]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n in ["eye_l", "eye_r"]:
		var at := model.find_child(n, true, false) as Node3D
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.009
		sm.height = 0.012
		sm.radial_segments = 8
		sm.rings = 4
		e.mesh = sm
		e.material_override = eye_mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(at if at else head).add_child(e)
		# the eye points sit up in the forehead, inside the skull: down and out to the sockets
		e.position = Vector3(0, -0.029, 0.03)
		eyes.append(e)
	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.1, 0.04)
	glow.omni_range = 2.2
	glow.omni_attenuation = 1.4
	glow.shadow_enabled = false
	glow.light_energy = 0.0
	add_child(glow)
	alpha = 0.0


## places the pieces (world transforms of their frames: head at the top of the neck, face +Z;
## hands at the wrist, fingers +Y, back +Z)
func place(head_xf: Transform3D, hand_xf: Array) -> void:
	var s := Basis.from_scale(Vector3.ONE * size)
	head.global_transform = Transform3D(head_xf.basis * s, head_xf.origin)
	for i in 2:
		hands[i].global_transform = Transform3D((hand_xf[i] as Transform3D).basis * s, (hand_xf[i] as Transform3D).origin)
	glow.global_position = head_xf.origin + head_xf.basis.z * 0.35 + head_xf.basis.y * 0.1


func tick(dt: float) -> void:
	_t += dt
	var h := clampf(heat, 0.0, 1.0)
	mat.set_shader_parameter("heat", h)
	# the eyes go red within the first third, then swell; near the end they flicker fast
	var e := smoothstep(0.0, 0.33, h)
	var c := Color(0.85, 0.92, 1.0).lerp(Color(1.0, 0.05, 0.02), e)
	# on the ember-red flesh red eyes vanish: past the middle they burn white-hot
	c = c.lerp(Color(1.0, 0.88, 0.55), smoothstep(0.4, 0.8, h))
	var flick := 1.0 if h < 0.75 else 0.7 + 0.3 * signf(sin(_t * 28.0))
	eye_mat.albedo_color = Color(c.r, c.g, c.b, eye_mat.albedo_color.a)
	eye_mat.emission = c
	eye_mat.emission_energy_multiplier = (6.0 + 22.0 * h) * flick
	for ey in eyes:
		ey.scale = Vector3.ONE * (1.0 + 1.4 * smoothstep(0.2, 1.0, h))
	glow.light_energy = 1.6 * h * h * (0.85 + 0.15 * sin(_t * lerpf(5.0, 15.0, h))) * clampf(alpha, 0, 1)
	glow.visible = glow.light_energy > 0.01
