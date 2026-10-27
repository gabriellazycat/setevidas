class_name LightSystem
extends Node3D
## Every light of the house (fixed count and order, from LIGHTS in the layout): real shadowed omni
## lights, glowing fixtures and switches. Bulbs burn out on their own at night (10-20 s for ceiling
## lights, longer for lamps), the Shadow drains and kills them. Port of Lights.ts.

signal warned(light)
signal burned_out(light)

class RoomLight:
	var def: Dictionary
	var index: int
	var light: Light3D
	var glow_light: OmniLight3D   # street lamp: a soft omni next to the spot
	var on := false
	var level := 0.0
	var flicker := 0.0
	var dead := 0.0
	var scale := 1.0
	var life := 0.0
	var warn := 0.0
	var base_energy := 1.0
	var base_color := Color.WHITE
	var emissive: Array = []      # [material, max_energy]
	var lever: Node3D
	var lever_rest := Basis.IDENTITY
	var switch_pos = null         # Vector3 or null
	var switch_normal := Vector3.ZERO
	var _ft := 0.0
	var _seed := randf() * 100.0
	var noise := FastNoiseLite.new()
	var hush := 0.0              # 1 = street lamp muted (camera inside the house)
	var presence := 0.0          # a ghost close by makes the bulb stutter (set every frame by the game)
	var hush_to := 0.0

	func room() -> String:
		var r: String = def["room"]
		return "" if r == "exterior" or r == "dynamic" else r

	func ticks() -> bool:
		return def["room"] != "dynamic" and def["room"] != "exterior"

	func set_on(v: bool) -> bool:
		if v and dead > 0:
			return false
		if v and not on:
			life = randf_range(28, 45) if def["fixture"] == "lamp" else randf_range(10, 20)
		if not v:
			warn = 0.0
		on = v
		if lever:
			lever.transform.basis = lever_rest * Basis(Vector3.RIGHT, -0.45 if v else 0.45)
		return true

	func update(dt: float, ambient_flicker: float) -> void:
		if dead > 0:
			dead -= dt
		_ft += dt
		var target := 1.0 if on else 0.0
		var fl := maxf(maxf(flicker, presence), maxf(warn, ambient_flicker if on else 0.0))
		if on and fl > 0.001:
			var n := noise.get_noise_1d((_ft * (8.0 + fl * 22.0) + _seed) * 10.0) * 0.5 + 0.5
			var n2 := noise.get_noise_1d((_ft * 3.1 + _seed * 2.0) * 10.0) * 0.5 + 0.5
			if n < fl * 0.75:
				target = 0.04
			else:
				target = 1.0 - fl * 0.35 * n2
		var rate := 28.0 if target > level else 16.0
		level = lerpf(level, target, 1.0 - exp(-rate * dt))
		hush = lerpf(hush, hush_to, 1.0 - exp(-6.0 * dt))
		var e := base_energy * level * scale * (1.0 - hush)
		light.light_energy = e
		light.visible = e > 0.002
		if glow_light:
			glow_light.light_energy = e * 0.25
			glow_light.visible = light.visible
		for em in emissive:
			var m: BaseMaterial3D = em[0]
			m.emission_energy_multiplier = em[1] * (0.03 + level * 0.97)

var lights: Array = []
var by_room: Dictionary = {}
var ambient_flicker := 0.0
## the street lamp lights the yard only: from inside, its wide spot shows in the rooms as coarse tinted blocks
var indoors := false
var lifetimes := false


func build(house_root: Node, nodes: Dictionary) -> void:
	for d in Layout.data()["LIGHTS"]:
		var rl := RoomLight.new()
		rl.def = d
		rl.index = int(d["index"])
		rl.noise.frequency = 0.1
		rl.base_color = Color(d["color"])
		var room: String = d["room"]
		var pos := Layout.v3(d["pos"])
		if room == "exterior":
			var sp := SpotLight3D.new()
			var head: Array = nodes.get("street_lamp_head", [pos.x, pos.y, pos.z])
			sp.position = Vector3(head[0], head[1] - 0.15, head[2])
			sp.rotation = Vector3(-PI / 2, 0, 0)
			sp.spot_range = 16.0
			sp.spot_angle = 52.0
			sp.spot_attenuation = 0.8
			sp.shadow_enabled = true
			sp.light_volumetric_fog_energy = 3.0
			rl.light = sp
			rl.base_energy = 9.0
			var g := OmniLight3D.new()
			g.position = sp.position + Vector3(0, -0.2, 0)
			g.omni_range = 7.0
			g.light_color = rl.base_color
			g.shadow_enabled = false
			g.light_volumetric_fog_energy = 1.5
			add_child(g)
			rl.glow_light = g
		else:
			var om := OmniLight3D.new()
			om.position = pos
			om.omni_range = float(d["distance"]) * (0.75 if room == "dynamic" else 0.9)
			om.omni_attenuation = 1.1
			om.shadow_enabled = room != "dynamic"
			om.shadow_bias = 0.04
			om.shadow_normal_bias = 1.2
			om.light_size = 0.05 if d["fixture"] != "lamp" else 0.1
			om.light_volumetric_fog_energy = 0.0 if room == "dynamic" else (1.4 if d["fixture"] == "lamp" else 0.8)
			om.light_specular = 0.6
			rl.light = om
			rl.base_energy = float(d["intensity"]) / 16.0 * (2.0 if d["fixture"] == "lamp" else 1.0)
		rl.light.light_color = rl.base_color
		rl.light.light_energy = 0.0
		rl.light.visible = false
		rl.light.light_bake_mode = Light3D.BAKE_DYNAMIC
		add_child(rl.light)
		lights.append(rl)
		if room != "exterior" and room != "dynamic" and d["fixture"] != "lamp":
			by_room[room] = rl
		if d.has("sw"):
			rl.switch_pos = Layout.v3(d["sw"]["p"])
			rl.switch_normal = Layout.v3(d["sw"]["n"])
	_find_fixtures(house_root)


func _emissive_for(rl: RoomLight, mi: MeshInstance3D, max_energy: float, only := "") -> void:
	for i in mi.mesh.get_surface_count():
		var src: Material = mi.get_surface_override_material(i)
		if src == null:
			src = mi.mesh.surface_get_material(i)
		src = Surfaces.original_of(src) if src else src
		if only != "" and (src == null or src.resource_name.to_lower().find(only) < 0):
			continue
		var m: BaseMaterial3D
		if src is BaseMaterial3D:
			m = (src as BaseMaterial3D).duplicate()
		else:
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.95, 0.9, 0.8)
		m.emission_enabled = true
		m.emission = rl.base_color
		m.emission_energy_multiplier = 0.0
		mi.set_surface_override_material(i, m)
		rl.emissive.append([m, max_energy])


func _find_fixtures(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var n: String = mi.name
		var owner_name := ""
		var p: Node = mi
		while p and owner_name == "":
			if str(p.name).begins_with("L") and str(p.name).find("_") > 1 and str(p.name).substr(1, str(p.name).find("_") - 1).is_valid_int():
				owner_name = p.name
			p = p.get_parent()
		if owner_name == "":
			continue
		var idx := int(owner_name.substr(1, owner_name.find("_") - 1))
		if idx < 0 or idx >= lights.size():
			continue
		var rl: RoomLight = lights[idx]
		# a ceiling fixture would print the shadow of its own arms / shade over the whole ceiling
		if rl.def["fixture"] != "lamp" and rl.def["room"] != "exterior":
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var low := owner_name.to_lower()
		if low.find("chandelier") >= 0:
			_emissive_for(rl, mi, 5.0, "lamp")
		elif low.find("_bulb") >= 0:
			_emissive_for(rl, mi, 6.0)
		elif low.find("_shade") >= 0 or low.find("lampshade") >= 0:
			_emissive_for(rl, mi, 1.2)
	for mi in root.find_children("SW*_lever*", "MeshInstance3D", true, false):
		var nm: String = mi.name
		var idx := int(nm.substr(2, nm.find("_") - 2))
		if idx >= 0 and idx < lights.size():
			lights[idx].lever = mi
			lights[idx].lever_rest = (mi as Node3D).transform.basis


func get_light(i: int) -> RoomLight:
	return lights[i]


func update(dt: float) -> void:
	if lifetimes:
		for l: RoomLight in lights:
			if not l.ticks() or not l.on:
				continue
			l.life -= dt
			if l.life < 3.2 and l.life > 0:
				if l.warn == 0.0:
					warned.emit(l)
				l.warn = 0.55 + 0.4 * (1.0 - l.life / 3.2)
			if l.life <= 0:
				l.set_on(false)
				l.dead = 1.4
				l.warn = 0.0
				burned_out.emit(l)
	for l: RoomLight in lights:
		l.hush_to = 1.0 if indoors and l.def["room"] == "exterior" else 0.0
		l.update(dt, ambient_flicker)


func set_all(v: bool, except: Array = []) -> void:
	for l: RoomLight in lights:
		var r: String = l.def["room"]
		if r == "dynamic" or r == "exterior" or except.has(l.index):
			continue
		l.dead = 0.0
		l.set_on(v)


func toggle(l: RoomLight) -> bool:
	return l.set_on(not l.on)


## rooms kept lit by the cat's night light (never burns out)
var night_lit := {}


func is_room_lit(room: String) -> bool:
	if night_lit.get(room, false):
		return true
	var l: RoomLight = by_room.get(room)
	var lit := l != null and l.on and l.level > 0.5
	if room == "quarto":
		var lamp: RoomLight = lights[8]
		lit = lit or (lamp.on and lamp.level > 0.5)
	return lit
