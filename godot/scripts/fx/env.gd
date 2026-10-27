class_name GameEnv
extends Node3D
## The world around the house and its mood: sky panoramas per phase, moon / sun, ambient light,
## volumetric fog and drifting ground fog, rain streaks, wind, lightning, moths at the street lamp,
## steam over hot water, the cat's breath in the cold, VoxelGI bounce light, quality presets and
## the full-screen grade. Port of Sky.ts + Weather.ts + Atmosphere.ts + the renderer setup.

const POST := preload("res://shaders/post.gdshader")
const EDGE := preload("res://shaders/edge.gdshader")
const RAIN := preload("res://shaders/rain.gdshader")
const FOG := preload("res://shaders/ground_fog.gdshader")

## how each night feels outside
const WEATHER := {
	1: {"wind": 0.4, "rain": 0.0, "bolts": 0.0},
	2: {"wind": 0.5, "rain": 0.0, "bolts": 0.0},
	3: {"wind": 0.6, "rain": 0.4, "bolts": 70.0},
	4: {"wind": 0.7, "rain": 0.6, "bolts": 55.0},
	5: {"wind": 0.8, "rain": 0.75, "bolts": 45.0},
	6: {"wind": 1.0, "rain": 1.0, "bolts": 28.0},
	7: {"wind": 0.9, "rain": 0.85, "bolts": 22.0},
}
const CLEAR_DAY := {"wind": 0.18, "rain": 0.0, "bolts": 0.0}

const LOOKS := {
	"night": {"sky": "night", "sky_e": 0.22, "sun": Color("#9cb4ff"), "sun_e": 0.6, "sun_dir": Vector3(-0.42, 0.6, -0.68), "amb_e": 0.085,
		"fog": 0.02, "fog_alb": Color(0.62, 0.68, 0.8), "fog_emit": Color(0.002, 0.003, 0.006), "exposure": 1.3,
		"tint": Vector3(0.97, 0.99, 1.05), "lift": Vector3(0.006, 0.008, 0.016), "sat": 0.95, "ground_fog": 0.55, "adj_sat": 1.02, "adj_con": 1.04, "edge": 0.85},
	"menu": {"sky": "night_overcast", "sky_e": 0.16, "sun": Color("#9cb4ff"), "sun_e": 0.32, "sun_dir": Vector3(-0.42, 0.6, -0.68), "amb_e": 0.1,
		"fog": 0.018, "fog_alb": Color(0.62, 0.68, 0.8), "fog_emit": Color(0.002, 0.003, 0.006), "exposure": 1.25,
		"tint": Vector3(0.95, 0.98, 1.06), "lift": Vector3(0.005, 0.008, 0.017), "sat": 0.92, "ground_fog": 0.8, "adj_sat": 1.01, "adj_con": 1.03, "edge": 0.0},
	"morning": {"sky": "morning", "sky_e": 1.0, "sun": Color("#ffefd6"), "sun_e": 2.4, "sun_dir": Vector3(0.62, 0.6, -0.5), "amb_e": 0.9,
		"fog": 0.005, "fog_alb": Color(0.85, 0.88, 0.9), "fog_emit": Color(0, 0, 0), "exposure": 1.0,
		"tint": Vector3(1.05, 1.0, 0.93), "lift": Vector3(0.008, 0.006, 0.004), "sat": 1.04, "ground_fog": 0.08, "adj_sat": 1.12, "adj_con": 1.05,
		"amb_col": Color("#ffe6cc"), "amb_sky": 0.45},
	"afternoon": {"sky": "afternoon", "sky_e": 0.9, "sun": Color("#ffb070"), "sun_e": 2.0, "sun_dir": Vector3(-0.82, 0.3, -0.48), "amb_e": 0.72,
		"fog": 0.008, "fog_alb": Color(0.9, 0.78, 0.7), "fog_emit": Color(0.004, 0.002, 0.001), "exposure": 1.0,
		"tint": Vector3(1.09, 0.99, 0.89), "lift": Vector3(0.01, 0.005, 0.003), "sat": 1.05, "ground_fog": 0.12, "adj_sat": 1.12, "adj_con": 1.05,
		"amb_col": Color("#ffd9b8"), "amb_sky": 0.45},
	"dawn": {"sky": "dawn", "sky_e": 0.7, "sun": Color("#ffc0a0"), "sun_e": 1.1, "sun_dir": Vector3(0.7, 0.18, -0.6), "amb_e": 0.6,
		"fog": 0.012, "fog_alb": Color(0.8, 0.72, 0.75), "fog_emit": Color(0.003, 0.002, 0.003), "exposure": 1.05,
		"tint": Vector3(1.06, 0.98, 0.95), "lift": Vector3(0.008, 0.005, 0.005), "sat": 1.0, "ground_fog": 0.35, "adj_sat": 1.06, "adj_con": 1.04,
		"amb_col": Color("#f2d6c8"), "amb_sky": 0.6},
}

var we: WorldEnvironment
var env: Environment
var sky_mat: PanoramaSkyMaterial
var sun: DirectionalLight3D
var vgi: VoxelGI
var post: ColorRect
var post_mat: ShaderMaterial
var post_layer: CanvasLayer
var edge_mat: ShaderMaterial
var edge_quad: MeshInstance3D
var _edge_base := 1.0
var rain_p: GPUParticles3D
var rain_mat: ShaderMaterial
var rain_loop = null
var wind_level := 0.0
var rain := 0.0
var boost := 0.0
var cur := "night"
var look: Dictionary = LOOKS["night"]
var weather: Dictionary = CLEAR_DAY
var fog_vols: Array = []
var moths: GPUParticles3D
var steam: Array = []
var breath: GPUParticles3D
var _breath_t := 0.0
var _bolt_t := 999.0
var _pending: Array = []
var _clock := 0.0
var _skies := {}
var _sun_base := 0.4
var _sky_base := 0.3
signal flashed(power)


func build(house: House) -> void:
	for k in ["night", "night_overcast", "morning", "afternoon", "dawn"]:
		_skies[k] = load("res://assets/sky/%s.hdr" % k)
	we = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = PanoramaSkyMaterial.new()
	sky_mat.panorama = _skies["night"]
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# evaluated Filmic and ACES for the stylised pass: both blow out the warm interiors; AgX + adjustment wins
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	# soft corner shading only: the painted look has no AO blotches
	env.ssao_radius = 0.5
	env.ssao_intensity = 0.7
	env.ssao_power = 1.0
	env.ssao_detail = 0.4
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_strength = 0.95
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.7)
	env.set_glow_level(4, 0.4)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_ambient_inject = 0.05
	env.volumetric_fog_sky_affect = 0.15
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.adjustment_enabled = true
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 2.5
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	add_child(sun)
	vgi = VoxelGI.new()
	vgi.size = Vector3(15, 14, 13)
	vgi.position = Vector3(6, 2.4, 5)
	vgi.subdiv = VoxelGI.SUBDIV_128
	add_child(vgi)
	_build_rain()
	_build_fog()
	_build_moths(house)
	breath = FX.breath_puff()
	add_child(breath)
	# full-screen grade under the UI
	post_layer = CanvasLayer.new()
	post_layer.layer = 1
	add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST
	post.material = post_mat
	post_layer.add_child(post)
	# light screen-space outline of the house, drawn before the other transparents (ghosts, rain, hair)
	edge_mat = ShaderMaterial.new()
	edge_mat.shader = EDGE
	edge_mat.render_priority = -100
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	edge_quad = MeshInstance3D.new()
	edge_quad.mesh = q
	edge_quad.material_override = edge_mat
	edge_quad.extra_cull_margin = 16384.0
	edge_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edge_quad)
	Settings.changed.connect(apply_quality)
	apply_quality()


func bake_gi() -> void:
	if vgi and str(Settings.g("quality")) != "low":
		vgi.bake()


func apply_quality() -> void:
	var q := str(Settings.g("quality"))
	var low := q == "low"
	var ultra := q == "ultra"
	env.ssao_enabled = not low
	env.ssil_enabled = q == "high" or ultra
	env.ssr_enabled = ultra
	env.ssr_max_steps = 48
	env.volumetric_fog_enabled = not low
	env.glow_enabled = bool(Settings.g("bloom"))
	if vgi:
		vgi.visible = not low
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if low else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED if low else (Viewport.MSAA_4X if ultra else Viewport.MSAA_2X)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if low else Viewport.SCREEN_SPACE_AA_SMAA
	vp.use_taa = false
	vp.positional_shadow_atlas_size = 2048 if low else (4096 if q == "medium" else 8192)
	RenderingServer.directional_shadow_atlas_set_size(2048 if low else 4096, true)
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if q == "medium" else (128 if ultra else 96), 64 if q == "medium" else (128 if ultra else 96))
	for f in fog_vols:
		(f as FogVolume).visible = not low
	if rain_p:
		rain_p.amount_ratio = 0.5 if low else 1.0
	post_mat.set_shader_parameter("grain", 1.0 if Settings.g("grain") else 0.0)
	edge_mat.set_shader_parameter("use_normal", not low)


# ---------------------------------------------------------------------- pieces


func _build_rain() -> void:
	rain_p = GPUParticles3D.new()
	rain_p.amount = 3200
	rain_p.lifetime = 1.3
	rain_p.preprocess = 1.3
	rain_p.local_coords = false
	rain_p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.5, 13)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 17.0
	pm.gravity = Vector3(0, -4, 0)
	rain_p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.6)
	rain_mat = ShaderMaterial.new()
	rain_mat.shader = RAIN
	q.material = rain_mat
	rain_p.draw_pass_1 = q
	rain_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_p.emitting = false
	add_child(rain_p)


func _build_fog() -> void:
	var n := NoiseTexture3D.new()
	n.width = 64
	n.height = 32
	n.depth = 64
	n.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.05
	fn.fractal_octaves = 3
	n.noise = fn
	# yard fog (outside) and basement fog; the house interior is carved out with a negative volume
	for d in [[Vector3(5.5, -0.35, 2.0), Vector3(34, 1.8, 30), Color(0.55, 0.6, 0.72), 0.55, false],
			[Vector3(6, -2.75, 5), Vector3(11.6, 0.9, 9.6), Color(0.45, 0.47, 0.5), 0.35, true]]:
		var fv := FogVolume.new()
		fv.position = d[0]
		fv.size = d[1]
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		var m := ShaderMaterial.new()
		m.shader = FOG
		m.set_shader_parameter("noise3d", n)
		m.set_shader_parameter("albedo", d[2])
		m.set_shader_parameter("density", d[3])
		m.set_shader_parameter("height_falloff", 1.6 if not d[4] else 1.0)
		fv.material = m
		add_child(fv)
		fog_vols.append(fv)
	var carve := FogVolume.new()
	carve.position = Vector3(6, -0.2, 5)
	carve.size = Vector3(12.4, 2.0, 10.4)
	var cm := FogMaterial.new()
	cm.density = -2.0
	carve.material = cm
	add_child(carve)
	fog_vols.append(carve)


func _build_moths(house: House) -> void:
	var head := Vector3(-1.8, 4.2, -2.2)
	if house.nodes.has("street_lamp_head"):
		head = Layout.v3(house.nodes["street_lamp_head"]) + Vector3(0, -0.35, 0)
	moths = GPUParticles3D.new()
	moths.amount = 14
	moths.lifetime = 6.0
	moths.preprocess = 6.0
	moths.position = head
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.gravity = Vector3.ZERO
	pm.orbit_velocity_min = 0.25
	pm.orbit_velocity_max = 0.6
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 4.0
	pm.turbulence_noise_scale = 1.2
	pm.turbulence_influence_min = 0.3
	pm.turbulence_influence_max = 0.6
	pm.attractor_interaction_enabled = true
	moths.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.028, 0.028)
	q.material = FX._billboard_mat(FX.tex("dot"), Color(1.0, 0.95, 0.75, 0.9), true, true, false)
	moths.draw_pass_1 = q
	moths.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	add_child(moths)
	var at := GPUParticlesAttractorSphere3D.new()
	at.radius = 1.4
	at.strength = 1.5
	at.position = head
	add_child(at)


func steam_at(points: Array) -> void:
	while steam.size() < points.size():
		var s := FX.wisps(Color(0.85, 0.9, 0.95, 0.12), 0.5, 0.12, 16, false, 0.3)
		add_child(s)
		steam.append(s)
	for i in steam.size():
		var s: GPUParticles3D = steam[i]
		s.emitting = i < points.size()
		if i < points.size():
			s.global_position = (points[i] as Vector3) + Vector3(0, 0.1, 0)


# ---------------------------------------------------------------------- phases


func apply(kind: String, night := 1) -> void:
	cur = kind
	look = LOOKS[kind]
	sky_mat.panorama = _skies["night_overcast" if kind == "night" and night >= 3 else look["sky"]]
	_sky_base = look["sky_e"] * (0.75 if kind == "night" and night >= 3 else 1.0)
	sky_mat.energy_multiplier = _sky_base
	sun.light_color = look["sun"]
	_sun_base = look["sun_e"] * (0.6 if kind == "night" and night >= 3 else 1.0)
	sun.light_energy = _sun_base
	var d: Vector3 = (look["sun_dir"] as Vector3).normalized()
	sun.look_at_from_position(Vector3(6, 1, 5) + d * 40.0, Vector3(6, 1, 5), Vector3.UP)
	env.ambient_light_energy = look["amb_e"]
	# daytime interiors read warm (painted look): part of the blue sky ambient is swapped for a cream fill
	env.ambient_light_color = look.get("amb_col", Color(1, 1, 1))
	env.ambient_light_sky_contribution = look.get("amb_sky", 1.0)
	env.volumetric_fog_density = look["fog"] * (1.0 + (0.1 * night if kind == "night" else 0.0))
	env.volumetric_fog_albedo = look["fog_alb"]
	env.volumetric_fog_emission = look["fog_emit"]
	env.tonemap_exposure = look["exposure"]
	env.adjustment_saturation = look.get("adj_sat", 1.0)
	env.adjustment_contrast = look.get("adj_con", 1.0)
	for i in 2:
		var fv: FogVolume = fog_vols[i]
		var m := fv.material as ShaderMaterial
		var k: float = look["ground_fog"] * (1.0 + (night - 1) * 0.08 if kind == "night" else 1.0)
		m.set_shader_parameter("density", (0.6 if i == 0 else 0.35) * k)
	post_mat.set_shader_parameter("tint", look["tint"])
	post_mat.set_shader_parameter("lift", look["lift"])
	post_mat.set_shader_parameter("sat", look["sat"])
	_edge_base = look.get("edge", 1.0)
	set_edge(1.0)
	moths.emitting = kind == "night" or kind == "menu" or kind == "afternoon"
	if kind == "night":
		set_weather(WEATHER.get(night, WEATHER[1]))
	elif kind == "menu":
		set_weather(WEATHER[3])
	else:
		set_weather(CLEAR_DAY)


## the afternoon goes by: k 1 (Clara just got home) .. 0 (dusk, the lights on): the sun sinks,
## reddens and fades, the sky dims, so the warm afternoon slides into the cold night
func set_daylight(k: float) -> void:
	if cur != "afternoon":
		return
	k = clampf(k, 0.0, 1.0)
	sun.light_energy = _sun_base * lerpf(0.25, 1.0, k)
	sun.light_color = (look["sun"] as Color).lerp(Color("#ff7a52"), (1.0 - k) * 0.7)
	sky_mat.energy_multiplier = _sky_base * lerpf(0.45, 1.0, k)
	var d: Vector3 = (look["sun_dir"] as Vector3)
	d.y = lerpf(0.12, d.y, k)
	d = d.normalized()
	sun.look_at_from_position(Vector3(6, 1, 5) + d * 40.0, Vector3(6, 1, 5), Vector3.UP)
	env.ambient_light_energy = look["amb_e"] * lerpf(0.55, 1.0, k)


func set_weather(wt: Dictionary) -> void:
	weather = wt
	_bolt_t = randf_range(wt["bolts"] * 0.3, wt["bolts"]) if wt["bolts"] > 0 else 999.0
	if wt["rain"] > 0 and rain_loop == null:
		rain_loop = Sfx.loop("rain", null, 1.0, "Rain")


## an immediate storm bolt (scripted moments)
func bolt(power := 1.0) -> void:
	_pending.append({"at": 0.0, "power": power})
	Sfx.thunder(randf_range(0.5, 2.8), power)


func tick(dt: float, cam: Camera3D, indoors: bool, cat_pos: Vector3, hunted: float, night: bool) -> void:
	_clock += dt
	rain = lerpf(rain, weather["rain"], 1.0 - exp(-0.6 * dt))
	var gust := 0.6 + 0.4 * sin(_clock * 0.21) * sin(_clock * 0.07 + 1.3)
	wind_level = lerpf(wind_level, weather["wind"] * gust, 1.0 - exp(-1.2 * dt))
	rain_p.emitting = rain > 0.02
	rain_p.global_position = cam.global_position + Vector3(0, 9, 0)
	rain_mat.set_shader_parameter("amount", rain)
	rain_mat.set_shader_parameter("wind", wind_level)
	(rain_p.process_material as ParticleProcessMaterial).direction = Vector3(wind_level * 0.15, -1, 0).normalized()
	if rain_loop:
		rain_loop.set_level(rain * (0.3 if indoors else 0.75))
	Sfx.set_rain_indoor(1.0 if indoors else 0.0)
	# lightning
	if weather["bolts"] > 0:
		_bolt_t -= dt
		if _bolt_t <= 0:
			_bolt_t = randf_range(weather["bolts"] * 0.5, weather["bolts"] * 1.3)
			var power := randf_range(0.6, 1.0)
			_pending.append({"at": 0.0, "power": power})
			if randf() < 0.4:
				_pending.append({"at": 0.22, "power": power * 0.7})
			Sfx.thunder(randf_range(0.4, 3.2), power)
	boost = lerpf(boost, 0.0, 1.0 - exp(-14.0 * dt))
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i]["at"] -= dt
		if _pending[i]["at"] <= 0:
			var pw: float = _pending[i]["power"]
			_pending.remove_at(i)
			boost = maxf(boost, pw * (0.35 if Settings.g("reduce_flashes") else 1.0))
			flashed.emit(pw)
	sun.light_energy = _sun_base + boost * 6.0
	sky_mat.energy_multiplier = _sky_base + boost * 2.5
	# the cat's breath shows in the cold of the hunt and in the basement
	_breath_t -= dt
	var cold := night and (hunted > 0.3 or cat_pos.y < -1.0)
	if cold and _breath_t <= 0:
		_breath_t = randf_range(1.6, 2.4)
		breath.global_position = cat_pos + Vector3(0, 0.26, 0)
		breath.restart()


## scale the house outline on top of the phase's own strength (0 hides it)
func set_edge(k: float) -> void:
	var s := _edge_base * k
	edge_mat.set_shader_parameter("strength", s)
	edge_quad.visible = s > 0.001


func set_post(params: Dictionary) -> void:
	for k in params:
		post_mat.set_shader_parameter(k, params[k])
