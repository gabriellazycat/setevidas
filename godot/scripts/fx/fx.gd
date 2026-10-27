class_name FX
extends RefCounted
## Particle effect factory: dust motes, splashes, drips, smoke and wisps around ghosts, sparks
## from dying bulbs, breath, rain... All GPU particles, lit by the scene so they glow in light shafts.

static var _tex := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/textures/gen/%s.png" % name)
	return _tex[name]


static func _billboard_mat(texture: Texture2D, color: Color, additive := false, unshaded := false, soft := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.proximity_fade_enabled = soft
	m.proximity_fade_distance = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = false
	return m


static func dust_motes(box: Vector3, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = clampi(amount, 20, 2000)
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.randomness = 1.0
	p.visibility_aabb = AABB(-box / 2 - Vector3.ONE, box + Vector3.ONE * 2)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box / 2 - Vector3(0.2, 0.2, 0.2)
	pm.gravity = Vector3(0, -0.004, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.03
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(0.15, 1))
	c.add_point(Vector2(0.85, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.alpha_curve = curve
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.008, 0.008)
	q.material = _billboard_mat(tex("dot"), Color(1.0, 0.95, 0.85, 0.55), false, false, false)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.45
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.008, 0.008)
	q.material = _billboard_mat(tex("dot"), Color(0.8, 0.9, 1.0, 0.8), false, false, false)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	return p


static func drip() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 0.9
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.1
	pm.gravity = Vector3(0, -9.8, 0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.01, 0.016)
	q.material = _billboard_mat(tex("dot"), Color(0.8, 0.9, 1.0, 0.9), false, false, false)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-1, -4, -1), Vector3(2, 5, 2))
	return p


## dark smoke / wisps clinging to a ghost (attach as a child of the ghost root)
static func wisps(color: Color, height := 1.8, spread := 0.3, amount := 48, additive := false, size := 0.35) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.4
	p.preprocess = 2.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(spread, height / 2, spread)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, 0.06, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.angle_min = -180
	pm.angle_max = 180
	pm.angular_velocity_min = -20
	pm.angular_velocity_max = 20
	var sc := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.2))
	sc.curve = c
	pm.scale_curve = sc
	var ac := CurveTexture.new()
	var c2 := Curve.new()
	c2.add_point(Vector2(0, 0))
	c2.add_point(Vector2(0.25, 1))
	c2.add_point(Vector2(1, 0))
	ac.curve = c2
	pm.alpha_curve = ac
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := _billboard_mat(tex("smoke"), color, additive, additive, true)
	m.billboard_keep_scale = true
	q.material = m
	p.draw_pass_1 = q
	p.position = Vector3(0, height / 2, 0)
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.3
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var m := _billboard_mat(tex("spark"), Color(1.0, 0.75, 0.4, 1.0), true, true, false)
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-3, -4, -3), Vector3(6, 6, 6))
	return p


static func embers(radius := 1.2, color := Color(1.0, 0.3, 0.15)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 3.0
	p.preprocess = 3.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.3
	pm.emission_ring_height = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0, 0.05, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	var ac := CurveTexture.new()
	var c2 := Curve.new()
	c2.add_point(Vector2(0, 0))
	c2.add_point(Vector2(0.2, 1))
	c2.add_point(Vector2(1, 0))
	ac.curve = c2
	pm.alpha_curve = ac
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	q.material = _billboard_mat(tex("spark"), color, true, true, false)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	return p


static func breath_puff() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.6
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.2, 1)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, 0.05, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var ac := CurveTexture.new()
	var c2 := Curve.new()
	c2.add_point(Vector2(0, 0))
	c2.add_point(Vector2(0.2, 0.7))
	c2.add_point(Vector2(1, 0))
	ac.curve = c2
	pm.alpha_curve = ac
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	q.material = _billboard_mat(tex("smoke"), Color(0.85, 0.9, 1.0, 0.25), false, false, true)
	p.draw_pass_1 = q
	return p


static var _beam_mat: ShaderMaterial


## the shared material of the dust in the sun / moon beams (Env sets its `gain` per phase)
static func beam_dust_mat() -> ShaderMaterial:
	if _beam_mat == null:
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = load("res://shaders/beam_dust.gdshader")
	return _beam_mat


static var _haze_mat: ShaderMaterial


## the fine dust of every room: the beam dust shader, weaker in the sun / moon, lit by the lamps
## and with a faint glow of its own (Env sets `gain` and `amb` per phase)
static func haze_mat() -> ShaderMaterial:
	if _haze_mat == null:
		_haze_mat = ShaderMaterial.new()
		_haze_mat.shader = load("res://shaders/beam_dust.gdshader")
		_haze_mat.set_shader_parameter("fwd", 3.0)
		_haze_mat.set_shader_parameter("lamp_gain", 0.4)
		# translucent, misty grains that fade out before they get big in front of the camera
		_haze_mat.set_shader_parameter("core", 0.0)
		_haze_mat.set_shader_parameter("opacity", 0.6)
		_haze_mat.set_shader_parameter("near_fade", 1.5)
	return _haze_mat


static var _shaft_mat: ShaderMaterial


## the shared material of the drawn light shafts (Env sets its `gain` per phase)
static func shaft_mat() -> ShaderMaterial:
	if _shaft_mat == null:
		_shaft_mat = ShaderMaterial.new()
		_shaft_mat.shader = load("res://shaders/light_shaft.gdshader")
	return _shaft_mat


## dust drifting in the light that comes through one window: invisible in the shade (the shader
## only takes the sun / moon through its shadow), so the grains show inside the beam alone
static func beam_dust(amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = clampi(amount * 4, 96, 880)
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.randomness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3.ONE
	pm.gravity = Vector3(0, -0.003, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.025
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.015
	pm.turbulence_influence_max = 0.05
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(1.0, 0.97, 0.9, 1.0)
	pm.alpha_curve = _fade_curve(0.15, 0.85)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.016, 0.016)
	q.material = beam_dust_mat()
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## a soft puff of dust where the cat lands (one node, restarted; Env scales it per landing)
static func dust_puff() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 0.16
	pm.emission_ring_inner_radius = 0.05
	pm.emission_ring_height = 0.02
	pm.direction = Vector3(0, 0.25, 0)
	pm.spread = 180.0
	pm.flatness = 0.85
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.02, 0)
	pm.damping_min = 1.2
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.angle_min = -180
	pm.angle_max = 180
	var sc := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, 1.6))
	sc.curve = c
	pm.scale_curve = sc
	pm.alpha_curve = _fade_curve(0.1, 0.3)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.26, 0.26)
	var m := _billboard_mat(tex("smoke"), Color(1.0, 0.94, 0.84, 0.35), false, false, true)
	m.billboard_keep_scale = true
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 1.5, 2))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## dry leaves drifting down over the yard; Env pushes them with the wind
static func leaves(box: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 11.0
	p.preprocess = 11.0
	p.randomness = 0.6
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box / 2
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, -0.55, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 1.5
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.3
	pm.angle_min = -180
	pm.angle_max = 180
	pm.angular_velocity_min = -160
	pm.angular_velocity_max = 160
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color("#8a5a2b"))
	g.set_color(1, Color("#c08a3e"))
	g.add_point(0.5, Color("#6e4a2a"))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	pm.alpha_curve = _fade_curve(0.05, 0.85)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.06)
	var m := _billboard_mat(tex("dot"), Color(1, 1, 1, 1), false, false, false)
	m.alpha_scissor_threshold = 0.4
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(-box / 2 - Vector3(4, 8, 4), box + Vector3(8, 10, 8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## fireflies over the yard at dusk: slow drifting points that blink on and off
static func fireflies(box: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 110
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.randomness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box / 2
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	# two slow blinks per life
	var ac := CurveTexture.new()
	var c := Curve.new()
	for pt in [Vector2(0, 0), Vector2(0.15, 1), Vector2(0.3, 0), Vector2(0.55, 0), Vector2(0.7, 1), Vector2(0.85, 0), Vector2(1, 0)]:
		c.add_point(pt)
	ac.curve = c
	pm.alpha_curve = ac
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	q.material = _billboard_mat(tex("dot"), Color(0.85, 1.0, 0.45, 1.0), true, true, false)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(-box / 2 - Vector3.ONE * 2, box + Vector3.ONE * 4)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


## fine night drizzle (sereno) falling through the cone of a lamp; only the lit part reads
static func mist(radius: float, height: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = height / 0.35
	p.preprocess = p.lifetime
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.alpha_curve = _fade_curve(0.1, 0.7)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.006)
	q.material = _billboard_mat(tex("dot"), Color(1.0, 0.92, 0.75, 0.55), true, true, false)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-radius - 1, -height - 1, -radius - 1), Vector3(radius * 2 + 2, height + 2, radius * 2 + 2))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


## alpha 0 → 1 at `a`, 1 → 0 after `b` (fractions of the particle's life)
static func _fade_curve(a: float, b: float) -> CurveTexture:
	var ct := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(a, 1))
	c.add_point(Vector2(b, 1))
	c.add_point(Vector2(1, 0))
	ct.curve = c
	return ct
