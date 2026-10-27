class_name DollThreat
extends Threat
## A Boneca: climbs out of the attic chest and creeps toward the bedroom, but only moves while
## nobody is watching. Stare at it (Cat Vision or a lit room) to freeze it; carry it back to the
## chest. Carrying it drains Focus and the cat cannot hiss. Port of Doll.ts.
## It walks (a small waddle under the skirt) instead of jumping from spot to spot; only the last
## step, onto the bed, is a jump.

var item: PropSystem.Carryable
var route: Array = []
var ri := 0
var hop_t := 0.0
var carried := false
var in_chest := true
var giggle_t := 3.0
var _gait := 0.0
var _step_side := 0
var _was_obs := false
var _eye_mats: Array[StandardMaterial3D] = []

const WALK_SPEED := 0.45


func _init() -> void:
	threat_id = "doll"
	display_name = "A Boneca"


func setup(world: Game) -> void:
	super.setup(world)
	var node: Node3D
	if ResourceLoader.exists("res://assets/models/ghosts/doll.glb"):
		node = (load("res://assets/models/ghosts/doll.glb") as PackedScene).instantiate()
	else:
		node = _placeholder()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_glass_eyes(mi as MeshInstance3D)
	w.house.add_child(node)
	item = PropSystem.Carryable.new()
	item.id = "doll"
	item.name = "a boneca"
	item.node = node
	w.house.carryables["doll"] = item
	var nav := w.house.nav
	route = nav.route(nav.get_node("a_chest"), nav.get_node("f_quarto_bed"), true)
	_hide_in_chest()


## the glass eyes catch what little light there is: a cold glint in the dark, so from across a dark
## room the first thing the cat sees is two small eyes already on it
func _glass_eyes(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
		if m == null or not (m.resource_name.contains("iris") or m.resource_name.contains("eyewhite")):
			continue
		var g := m.duplicate() as StandardMaterial3D
		g.emission_enabled = true
		g.emission = Color(0.62, 0.78, 1.0) if m.resource_name.contains("iris") else Color(0.85, 0.85, 0.9)
		g.emission_energy_multiplier = 0.0
		mi.set_surface_override_material(i, g)
		_eye_mats.append(g)


func _process(dt: float) -> void:
	# only at night, and brighter the darker the room is (a lit room shows the plain doll)
	var want := 0.0
	if w and w.phase == "night" and item and item.node.visible:
		want = 0.25 if w.house.lights.is_room_lit(Layout.room_at(item.pos)) else 1.6
	for g: StandardMaterial3D in _eye_mats:
		var k := want * (1.0 if g.resource_name.contains("iris") else 0.18)
		g.emission_energy_multiplier = move_toward(g.emission_energy_multiplier, k, dt * 2.0)


static func _placeholder() -> Node3D:
	var n := Node3D.new()
	var porcelain := StandardMaterial3D.new()
	porcelain.albedo_color = Color(0.94, 0.9, 0.86)
	porcelain.roughness = 0.2
	var dress := StandardMaterial3D.new()
	dress.albedo_color = Color(0.55, 0.32, 0.36)
	dress.roughness = 0.9
	var skirt := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.11
	cm.height = 0.2
	skirt.mesh = cm
	skirt.material_override = dress
	skirt.position.y = 0.1
	n.add_child(skirt)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	head.mesh = sm
	head.material_override = porcelain
	head.position.y = 0.3
	n.add_child(head)
	return n


func _hide_in_chest() -> void:
	in_chest = true
	item.enabled = false
	item.node.visible = false
	item.place(Vector3(w.house.chest_pos.x, 6.1, w.house.chest_pos.z))


func reset() -> void:
	stage = 0
	t = 0.0
	ri = 0
	carried = false
	if w:
		if w.cat.carrying == item:
			w.cat.carrying = null
		_hide_in_chest()
		w.house.set_chest(false)


func on_stage(s: int, _prev: int) -> void:
	var cp := w.house.chest_pos
	if s == 1:
		w.house.set_chest(true)
		Sfx.creak(cp + Vector3(0, 0.4, 0), 0.45, 1.6, 1.3)
		get_tree().create_timer(1.2).timeout.connect(func(): Sfx.giggle(cp + Vector3(0, 0.5, 0)))
	if s == 2:
		if w.house.hatch_target < 0.5:
			w.house.set_hatch(true)
			Sfx.creak(Vector3(6.85, 5.6, 1.6), 0.55, 1.8, 0.9)
			get_tree().create_timer(1.5).timeout.connect(func(): Sfx.thud(Vector3(6.85, 3.3, 2.2), 0.6, 60))
		in_chest = false
		item.enabled = true
		item.node.visible = true
		ri = 0
		var nav := w.house.nav
		route = nav.route(nav.get_node("a_chest"), _goal_node(), true)
		_goal_id = _goal_node().id
		item.place(route[0].p + Vector3(0.3, 0, -0.2), randf_range(-3, 3))
		Sfx.porcelain(item.pos)
	if s == 5:
		w.sting(0.5)
		Sfx.giggle(item.pos + Vector3(0, 0.4, 0))


## where the person it is after is now: in bed, or wherever they are in the house (Davi reads in
## the study until late; the doll goes there, not to his empty bed)
var _goal_id := ""
var _repath_t := 0.0


func _goal_node() -> NavGraph.NavNode:
	var nav := w.house.nav
	if target.in_bed:
		return nav.get_node(target.cfg["bed_node"])
	return nav.nearest(target.global_position)


func _goal_room() -> String:
	return target.cfg["bed_room"] if target.in_bed else Layout.room_at(target.global_position)


## close to the person, in the same room: only then does it frighten them
func _near_target() -> bool:
	var tp: Vector3 = target.cfg["bed_top"] if target.in_bed else target.global_position
	return item.pos.distance_to(tp) < 2.6 and Layout.room_at(item.pos) == _goal_room()


## the person moved (got up, went to bed, changed rooms): a new way to them from where it stands
func _follow_target(dt: float) -> void:
	_repath_t -= dt
	if _repath_t > 0.0:
		return
	_repath_t = 1.5
	var g := _goal_node()
	if g.id == _goal_id:
		return
	_goal_id = g.id
	var nav := w.house.nav
	route = nav.route(nav.nearest(item.pos), g, true)
	ri = 0
	if stage >= 4 and not _near_target():
		set_stage(3)


func _observed() -> bool:
	return w.is_observed(item.pos + Vector3(0, 0.25, 0), true)


func tick(dt: float) -> void:
	if carried:
		giggle_t -= dt
		if giggle_t <= 0:
			giggle_t = 3.2
			Sfx.giggle(w.cat.head())
			w.shake(0.12)
		w.cat.focus = maxf(0.0, w.cat.focus - 4.0 * dt)
		return
	var obs := _observed()
	# the moment you look away, sometimes, a little laugh
	if stage >= 3 and _was_obs and not obs and randf() < 0.3:
		get_tree().create_timer(randf_range(0.4, 0.9)).timeout.connect(func():
			Sfx.giggle(item.pos + Vector3(0, 0.4, 0)))
	_was_obs = obs
	if stage == 1 and t > d(9):
		set_stage(2)
	elif stage == 2 and t > d(5):
		set_stage(3)
	elif stage >= 3:
		_follow_target(dt)
		if stage == 3:
			if not obs:
				_walk(dt)
		else:
			if not obs:
				hop_t += dt
			else:
				hop_t = maxf(0.0, hop_t - dt * 0.5)
			if hop_t > d(8):
				hop_t = 0.0
				_hop()
		if stage >= 4 and not _near_target():
			# they got away from it: back to walking after them
			set_stage(3)
		elif stage == 4:
			target.add_fear(4.5 * dt)
		elif stage == 5:
			target.add_fear(8.5 * dt)
		if stage == 3:
			target.add_fear(0.2 * dt)


## anywhere in the frame or just past its edge (seen or not: in the dark it is not "seen" from afar)
func _on_screen() -> bool:
	var cam := w.cam
	var p := item.pos + Vector3(0, 0.25, 0)
	if cam.is_position_behind(p):
		return false
	var vs := w.get_viewport().get_visible_rect().size
	var s := (cam.unproject_position(p) - vs * 0.5) / (vs * 0.5)
	return absf(s.x) < 1.3 and absf(s.y) < 1.3


## a few centimetres at a time toward the bedroom, only while nobody looks
func _walk(dt: float) -> void:
	if ri + 1 >= route.size():
		set_stage(4)
		return
	var nxt = route[ri + 1]
	if nxt.room == _goal_room() and not may_attack:
		return
	var p := item.pos
	var dir: Vector3 = nxt.p - p
	var dist := dir.length()
	if dist < 0.05:
		ri += 1
		if nxt.room == _goal_room() and _near_target():
			set_stage(4)
		return
	# off screen it hurries, and turns to face the cat: whenever you look back, it is looking at you
	var off := not _on_screen()
	var sp := WALK_SPEED * clampf(w.threat_speed, 0.8, 1.2) * (1.7 if off else 1.0)
	p += dir / dist * minf(dist, sp * dt)
	_gait += dt * (9.5 if off else 7.5)
	var cp := w.cat.global_position
	var face := atan2(cp.x - p.x, cp.z - p.z) if off and p.distance_to(cp) < 9.0 else atan2(dir.x, dir.z)
	var y := face if off else lerp_angle(item.yaw, face, 1.0 - exp(-2.0 * dt))
	item.place(p, y)
	# waddle: sway side to side and a tiny bob, the skirt hides the legs
	item.node.rotation.z = sin(_gait) * 0.105
	item.node.global_position.y = p.y + absf(sin(_gait)) * 0.018
	var side := 1 if sin(_gait) > 0 else -1
	if side != _step_side:
		_step_side = side
		Sfx.porcelain(p)
		if randf() < 0.05:
			Sfx.giggle(p + Vector3(0, 0.4, 0))


func _hop() -> void:
	if stage == 5:
		return
	if stage == 4:
		if not may_attack:
			return
		# onto the bed with them, or right at their feet if they are up
		if target.in_bed:
			item.place(target.cfg["bed_top"], PI)
		else:
			var tp := target.global_position
			var to := (item.pos - tp)
			to.y = 0
			to = to.normalized() if to.length() > 0.05 else Vector3(0, 0, 1)
			item.place(tp + to * 0.45, atan2(-to.x, -to.z))
		Sfx.porcelain(item.pos)
		set_stage(5)
		return
	var next_i := mini(ri + 1, route.size() - 1)
	var nxt = route[next_i]
	if nxt.room == _goal_room() and not may_attack:
		return
	ri = next_i
	var p: Vector3 = nxt.p + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25))
	var ahead: Vector3 = route[mini(ri + 1, route.size() - 1)].p
	item.place(p, atan2(ahead.x - p.x, ahead.z - p.z))
	Sfx.porcelain(p)
	if randf() < 0.35:
		get_tree().create_timer(0.3).timeout.connect(func(): Sfx.giggle(p + Vector3(0, 0.4, 0)))
	if nxt.room == _goal_room() and _near_target():
		set_stage(4)


func picked_up() -> void:
	carried = true


func dropped(p: Vector3) -> void:
	carried = false
	if stage < 3:
		return
	# it walks now: a fresh route from where it was dropped (the first leg stays in this room)
	var nav := w.house.nav
	route = nav.route_from(p, _goal_node(), true)
	_goal_id = _goal_node().id
	# dropped mid-staircase it already stands on the first leg
	if route.size() < 2 or not NavGraph.on_first_leg(p, route[0].p, route[1].p):
		route.push_front(route[0])
	ri = 0
	stage = 4 if route[0].room == _goal_room() and _near_target() else 3
	hop_t = 0.0


func returned() -> void:
	var cp := w.house.chest_pos
	Sfx.thud(cp + Vector3(0, 0.4, 0), 0.5, 80)
	Sfx.giggle(cp + Vector3(0, 0.4, 0))
	if stage >= 4:
		target.say(pick(["Ufa... que pesadelo.", "Hm? Tinha alguma coisa na cama...?"]), 2.6, "whisper")
	repel()


func can_hiss(p: Vector3) -> bool:
	return stage >= 3 and not carried and p.distance_to(item.pos) < 2.2


func on_hiss(p: Vector3, strong: bool) -> bool:
	if stage < 3 or not strong or carried:
		return false
	if p.distance_to(item.pos) > 2.2:
		return false
	ri = maxi(0, ri - 1)
	if stage >= 4:
		stage = 3
	item.place(route[ri].p, item.yaw)
	Sfx.porcelain(item.pos)
	stall = d(4)
	return true


func focus():
	if stage == 0:
		return null
	return w.house.chest_pos if stage < 2 else item.pos


func entity():
	return item.pos if stage >= 2 and not carried else null


func describe_death() -> Dictionary:
	return {
		"title": tr("%s foi levado(a) pela Boneca") % target.display_name,
		"why": "A Boneca andou pela casa sempre que ninguém olhava e apareceu na cama da pessoa.",
		"tip": "Encare-a (de perto ou num cômodo aceso) para congelá-la, pegue-a na boca e leve de volta ao baú do sótão. Carregá-la drena o Foco e você não pode bufar.",
	}
