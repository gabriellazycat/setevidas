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
	p.amount = clampi(amount, 20, 160)
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
