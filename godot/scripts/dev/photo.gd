extends Node3D
## Renders the old photograph the cat finds in the basement: Dona Ivone sitting with Breu, the
## black cat, on her lap; then ages the picture (sepia, fading, foxing spots, scratches, a white
## deckled border) and saves it to assets/textures/gen/old_photo.png.

var cam: Camera3D
var ivone: HumanRig
var cat: CatRig
var frame := 0


func _ready() -> void:
	get_window().size = Vector2i(900, 680)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.38, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.58, 0.55)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	we.environment = env
	add_child(we)
	# a studio backdrop and the chair
	var wall := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(6, 4)
	wall.mesh = q
	wall.material_override = Surfaces.get_material("wallpaper_damask") if Surfaces.has("wallpaper_damask") else StandardMaterial3D.new()
	wall.position = Vector3(0, 1.5, -0.7)
	add_child(wall)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	floor.material_override = Surfaces.get_material("floor_wood") if Surfaces.has("floor_wood") else StandardMaterial3D.new()
	add_child(floor)
	var chair := HouseBuilder.instance_parts("GreenChair_01", [], 0.95)
	chair.rotation.y = 0.0
	chair.position = Vector3(0, 0, -0.08)
	add_child(chair)
	ivone = HumanRig.new("ivone", {"day": "ivone"})
	add_child(ivone)
	ivone.position = Vector3(0, 0.05, 0.12)
	cat = CatRig.new("breu")
	add_child(cat)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(30), 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.4, 1.6, 1.6)
	fill.light_energy = 0.6
	fill.omni_range = 5
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 24
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0.12, 1.0, 2.2)
	cam.look_at(Vector3(0.02, 0.9, 0.1))


func _process(dt: float) -> void:
	frame += 1
	ivone.pose = "sit"
	if frame < 3:
		ivone.snap_pose("sit")
	ivone.update(dt)
	# Breu curled on her lap: on top of the thighs
	var th := ivone.bone_world("thigh_l").origin.lerp(ivone.bone_world("thigh_r").origin, 0.5)
	var kn := ivone.bone_world("calf_l").origin.lerp(ivone.bone_world("calf_r").origin, 0.5)
	cat.global_position = th.lerp(kn, 0.3) + Vector3(0.03, 0.06, -0.02)
	cat.rotation.y = 0.15
	cat.update_pose(dt, {"sit": 1.0, "pupil": 0.35, "tail_up": 0.3, "ear_alert": 0.3})
	if frame == 90:
		var img := get_viewport().get_texture().get_image()
		_age(img)
		img.save_png("res://assets/textures/gen/old_photo.png")
		print("PHOTO saved")
		get_tree().quit()


func _age(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := FastNoiseLite.new()
	noise.frequency = 0.004
	var fine := FastNoiseLite.new()
	fine.frequency = 0.08
	var spots := []
	for i in 40:
		spots.append([Vector2(rng.randf() * w, rng.randf() * h), rng.randf_range(2, 9), rng.randf_range(0.2, 0.6)])
	var scratches := []
	for i in 7:
		var x0 := rng.randf() * w
		scratches.append([x0, rng.randf_range(-0.3, 0.3), rng.randf_range(0.3, 1.0)])
	var border := 26
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			l = pow(clampf(l, 0, 1), 0.85)
			# contrast down, lifted blacks: a faded print
			l = 0.12 + l * 0.78
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var g := fine.get_noise_2d(x, y) * 0.06
			l *= 0.88 + 0.16 * n
			l += g
			var sep := Color(l * 1.07, l * 0.92, l * 0.72)
			# vignette
			var d := Vector2((x - w / 2.0) / w, (y - h / 2.0) / h).length()
			sep = sep.darkened(clampf((d - 0.32) * 1.3, 0, 0.45))
			for s in spots:
				var dd: float = (Vector2(x, y) - s[0]).length()
				if dd < s[1]:
					sep = sep.lerp(Color(0.55, 0.42, 0.28), s[2] * (1.0 - dd / s[1]))
			for sc in scratches:
				var sx: float = sc[0] + (y - h / 2.0) * sc[1]
				if absf(x - sx) < 0.8 and fine.get_noise_2d(x * 3.0, y * 0.2) > 0.1:
					sep = sep.lerp(Color(0.92, 0.88, 0.8), sc[2] * 0.6)
			# deckled white border
			var edge := mini(mini(x, w - 1 - x), mini(y, h - 1 - y))
			var deckle := border + int(fine.get_noise_2d(x * 2.0, y * 2.0) * 4.0)
			if edge < deckle:
				var paper := Color(0.86, 0.82, 0.72).darkened(0.08 * n)
				sep = paper
				if edge < 3:
					sep = paper.darkened(0.2)
			img.set_pixel(x, y, Color(sep.r, sep.g, sep.b, 1.0))
