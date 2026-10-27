class_name Ambient
extends Node3D
## Rare, capped environmental scares. Each vanishes when looked at or when its room is lit: a pair
## of eyes glowing in a dark corner, a figure standing outside the living-room window (nights 3+),
## a door drifting open somewhere near but out of view. Port of Ambient.ts.

const EYE_SPOTS := [
	Vector3(0.4, 0.35, 8.8), Vector3(4.7, 0.5, 0.5), Vector3(0.5, -2.6, 0.6), Vector3(7.5, -2.5, 9.4), Vector3(11.3, -2.4, 0.7),
	Vector3(0.5, 3.4, 9.3), Vector3(4.6, 3.4, 0.5), Vector3(0.6, 6.5, 0.8), Vector3(7.0, 6.4, 9.2),
]

var eyes: Node3D
var eye_mat: StandardMaterial3D
var eye_until := 0.0
var eye_seen := 0.0
var eye_spot := Vector3.ZERO
var figure: GhostBody
var figure_t := 0.0
var figure_seen := 0.0
var cd := {"eyes": 40.0, "figure": 80.0, "door": 60.0}
var clock := 0.0


func _ready() -> void:
	eyes = Node3D.new()
	eye_mat = StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.3, 0.16)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.29, 0.16)
	eye_mat.emission_energy_multiplier = 5.0
	eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for s in [-1, 1]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.012
		sm.height = 0.016
		e.mesh = sm
		e.material_override = eye_mat
		e.position = Vector3(s * 0.045, 0, 0)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eyes.add_child(e)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.3, 0.15)
	glow.omni_range = 0.6
	glow.light_energy = 0.25
	eyes.add_child(glow)
	eyes.visible = false
	add_child(eyes)
	figure = GhostBody.new("visitor", Color(0.004, 0.004, 0.006), Color(0.05, 0.06, 0.08), 0.0, Color(0, 0, 0, 0.3), 1.9)
	add_child(figure)
	figure.alpha = 0.0
	figure.position = Vector3(-1.1, -0.9, 2.7)   # outside the sala window
	figure.rotation.y = PI / 2


func reset() -> void:
	eyes.visible = false
	figure.alpha = 0.0
	cd = {"eyes": randf_range(30, 60), "figure": randf_range(60, 120), "door": randf_range(40, 90)}


## observed: Callable(Vector3) -> bool; angle_to: Callable(Vector3) -> degrees; allowed: the Director
## says the house is calm (new scares wait, their timers paused; the ones already out still run out)
func tick(dt: float, house: House, cat_pos: Vector3, night: int, observed: Callable, angle_to: Callable, allowed := true) -> void:
	clock += dt
	if night < 1:
		return
	var calm: bool = not Settings.g("reduce_flashes")
	# glowing eyes in a dark corner
	if eyes.visible:
		var room := Layout.room_at(eye_spot)
		var lit := house.lights.is_room_lit(room) if room != "" else false
		var watched: bool = observed.call(eye_spot) and float(angle_to.call(eye_spot)) < 14.0
		eye_seen = eye_seen + dt if watched else 0.0
		eye_mat.albedo_color.a = 0.0 if sin(clock * 2.3) > 0.96 else 1.0
		if lit or eye_seen > 0.7 or clock > eye_until:
			eyes.visible = false
			cd["eyes"] = randf_range(45, 90)
	elif allowed:
		cd["eyes"] -= dt
		if cd["eyes"] <= 0:
			var spots := []
			for p: Vector3 in EYE_SPOTS:
				var d := p.distance_to(cat_pos)
				var room := Layout.room_at(p)
				if d > 3.5 and d < 9 and room != "" and not house.lights.is_room_lit(room) and not observed.call(p):
					spots.append(p)
			if spots.size() > 0:
				eye_spot = spots[randi() % spots.size()]
				eyes.global_position = eye_spot
				eyes.look_at(Vector3(cat_pos.x, eye_spot.y, cat_pos.z), Vector3.UP, true)
				eyes.visible = true
				eye_seen = 0.0
				eye_until = clock + randf_range(10, 18)
			else:
				cd["eyes"] = 8.0
	# a figure standing outside the window (nights 3+), gone the moment it is looked at
	if figure.alpha > 0.01:
		figure_t -= dt
		var p := figure.global_position + Vector3(0, 2.3, 0)
		var watched2: bool = observed.call(p) and float(angle_to.call(p)) < 16.0
		figure_seen = figure_seen + dt if watched2 else 0.0
		figure.rig.pose = "stare"
		figure.tick(dt)
		if figure_seen > 0.9 or figure_t <= 0:
			figure.alpha = 0.0
			cd["figure"] = randf_range(90, 160)
	elif night >= 3 and calm and allowed:
		cd["figure"] -= dt
		if cd["figure"] <= 0:
			if Layout.room_at(cat_pos) == "sala" and not house.lights.is_room_lit("sala"):
				figure.alpha = 0.9
				figure_t = randf_range(8, 14)
				figure_seen = 0.0
			else:
				cd["figure"] = 10.0
	# a door that drifts open on its own, somewhere near but not in view
	if allowed:
		cd["door"] -= dt
	if allowed and cd["door"] <= 0:
		cd["door"] = randf_range(70, 140)
		var cands := []
		for d: Door in house.doors.values():
			var st: String = d.def.get("style", "")
			if d.locked or d.state != "closed" or st == "front" or st == "basement":
				continue
			var ctr := d.center()
			var dist := ctr.distance_to(cat_pos)
			if dist > 3 and dist < 10 and not observed.call(ctr):
				cands.append(d)
		if cands.size() > 0:
			var dd: Door = cands[randi() % cands.size()]
			dd.set_state("ajar")
			Sfx.creak(dd.center() + Vector3(0, 1, 0), 0.3, 1.2)
