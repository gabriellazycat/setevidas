extends Node3D
## Sweeps a person-sized capsule (radius 0.22) along every edge of the navigation graph against the
## solid world (walls, furniture, beds, closed parts) and lists the edges that hit something.
## Doors are opened first (a walker passes through them open), the attic ladder ramp is ignored.
##   godot --headless --path godot res://scenes/navcheck.tscn [-- --navlift=0.25 --navtop=1.5]
## Prints "NAVCHECK CLEAN" or one "NAVHIT" line per blocked edge, then "NAVCHECK DONE <hits>".
## With -- --cattest it instead drives the cat through a few collision cases (doors, window, stairs,
## railing, gate, under a table, jumps, turning against a wall) and prints CATTEST lines.

const R := 0.22

var house: House


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var lift := float(args.get("navlift", "0.25"))
	var top := float(args.get("navtop", "1.5"))
	house = House.new()
	house.name = "House"
	add_child(house)
	house.build()
	await house.measure_beds()
	for d: Door in house.doors.values():
		d.locked = false
		d.set_state("open", true)
	house.set_hatch(true, true)
	for i in 3:
		await get_tree().physics_frame
	if OS.get_cmdline_user_args().has("--atticcheck"):
		attic_check()
		get_tree().quit()
		return
	if args.has("cattest") or OS.get_cmdline_user_args().has("--cattest"):
		await cat_test()
		get_tree().quit()
		return
	var exclude: Array[RID] = []
	for lc in house._ladder_cols:
		exclude.append((lc.get_parent() as CollisionObject3D).get_rid())
	var hits := 0
	var L := Layout.data()
	for e in L["NAV_EDGES"]:
		var a: Vector3 = house.nav.nodes[e[0]].p
		var b: Vector3 = house.nav.nodes[e[1]].p
		var ghost: bool = e.size() > 2 and e[2] == true
		var h := top
		var r := R
		if ghost:
			# ghost-only edges climb the ladder into the attic, low under the roof (0.3 m over the hatch):
			# checked crawling, small
			h = minf(top, 0.45)
			r = 0.15
		var hit := sweep(a, b, lift, h, exclude, r)
		if not hit.is_empty():
			hits += 1
			print("NAVHIT %s -> %s%s at %s: %s" % [e[0], e[1], " (ghost)" if ghost else "", hit["at"], hit["what"]])
	if hits == 0:
		print("NAVCHECK CLEAN %d edges" % L["NAV_EDGES"].size())
	print("NAVCHECK DONE %d" % hits)
	get_tree().quit()


## Attic furniture: one box per item (all its meshes), listing the pairs that overlap or sit closer than
## GAP, the items that reach the sloped roof, and the ones that sit on the walking line to the chest.
##   godot --headless --path godot res://scenes/navcheck.tscn -- --atticcheck [--atticgap=0.12]
func attic_check() -> void:
	var L := Layout.data()
	var gap := 0.12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--atticgap="):
			gap = float(a.substr(11))
	var kne := float((L.get("ATTIC", {}) as Dictionary).get("knee", 0.0))
	var items := {}   # name -> AABB
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var bb := m.global_transform * m.get_aabb()
		if bb.position.y < 5.95 or bb.position.y > 9.5 or bb.end.x < 0 or bb.position.x > 7.5 or bb.position.z > 10 or bb.end.z < 0:
			continue
		# the item is the first ancestor below the Furniture / Shell / house glb root
		var n: Node = m
		while n.get_parent() != null and n.get_parent() != house and n.get_parent().name not in ["Furniture", "Shell", "Props", "Kit"] and not str(n.get_parent().name).begins_with("house"):
			n = n.get_parent()
		var nm := str(n.name)
		if nm.begins_with("rafter") or nm.begins_with("collar") or nm.begins_with("ridge") or nm.begins_with("house_") or nm.begins_with("Shell") or nm.begins_with("L12") or nm.begins_with("SW12") or nm.begins_with("HATCH") or nm == "LADDER" or nm.begins_with("_"):
			continue
		items[nm] = bb if not items.has(nm) else (items[nm] as AABB).merge(bb)
	var names := items.keys()
	names.sort()
	var bad := 0
	for nm in names:
		var bb: AABB = items[nm]
		print("ATTICITEM %-28s x %.2f..%.2f  z %.2f..%.2f  h %.2f" % [nm, bb.position.x, bb.end.x, bb.position.z, bb.end.z, bb.end.y - 6.0])
		# roof underside above the footprint's nearest wall edge (rafters hang 0.14 under the slope)
		for x in [bb.position.x, bb.end.x]:
			var under := kne + 0.64 * minf(x, 7.5 - x) - 0.14
			if bb.end.y - 6.0 > under - 0.02:
				bad += 1
				print("ATTICHIT %s reaches the roof at x=%.2f (item %.2f m, roof %.2f m)" % [nm, x, bb.end.y - 6.0, under])
				break
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: AABB = items[names[i]]
			var b: AABB = items[names[j]]
			if a.grow(gap * 0.5).intersects(b.grow(gap * 0.5)):
				var dy := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
				if dy > 0.02:
					bad += 1
					print("ATTICHIT %s and %s overlap or touch (gap < %.2f)" % [names[i], names[j], gap])
	print("ATTICCHECK DONE %d" % bad)


## first thing a capsule from a to b (bottom lifted, total height h) runs into, or {}
func sweep(a: Vector3, b: Vector3, lift: float, h: float, exclude: Array[RID], r := R) -> Dictionary:
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = maxf(h - lift, r * 2.0 + 0.01)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = HouseBuilder.LAYER_WORLD
	q.exclude = exclude
	var up := Vector3(0, lift + cap.height / 2.0, 0)
	q.transform = Transform3D(Basis.IDENTITY, a + up)
	q.motion = b - a
	var space := house.space
	var frac := space.cast_motion(q)
	if frac.size() == 2 and frac[0] >= 1.0:
		return {}
	var t: float = frac[1] if frac.size() == 2 else 0.0
	q.motion = Vector3.ZERO
	q.transform = Transform3D(Basis.IDENTITY, a.lerp(b, t) + up)
	var res := space.intersect_shape(q, 4)
	var what := []
	for hit in res:
		what.append(describe(hit["collider"], int(hit["shape"])))
	return {"at": a.lerp(b, t), "what": ", ".join(what) if not what.is_empty() else "?"}


static func describe(col: Object, shape_idx: int) -> String:
	if not (col is CollisionObject3D):
		return str(col)
	var co := col as CollisionObject3D
	var owner_id := co.shape_find_owner(shape_idx)
	var cs := co.shape_owner_get_owner(owner_id) as CollisionShape3D
	var name := str(co.name)
	if cs:
		var tag := str(cs.get_meta("tag", ""))
		var box := cs.shape as BoxShape3D
		var c := (co.global_transform * cs.transform).origin
		name += "[%s %s%s]" % [tag, c, (" size " + str(box.size)) if box else ""]
	return name


# ---------------------------------------------------------------------- cat test

var cat: Cat


func cat_test() -> void:
	cat = Cat.new()
	cat.house = house
	add_child(cat)
	await get_tree().physics_frame
	var cases := [
		# name, start, facing yaw, move dir (yaw, or null), seconds, jump at (s, or -1), check
		["door_sala", Vector3(3.6, 0, 2.2), PI / 2, PI / 2, 2.0, -1.0, func(p: Vector3): return p.x > 5.4],
		["kitchen_table", Vector3(8.1, 0, 6.7), PI / 2, PI / 2, 1.0, -1.0, func(p: Vector3): return p.x > 9.0],
		["stairs_up", Vector3(5.55, 0, 3.5), 0.0, 0.0, 4.5, -1.0, func(p: Vector3): return p.y > 2.9],
		["stairs_down", Vector3(5.55, 3, 8.9), PI, PI, 4.5, -1.0, func(p: Vector3): return p.y < 0.2],
		["base_stairs_down", Vector3(11.5, 0, 9.5), PI, PI, 4.5, -1.0, func(p: Vector3): return p.y < -2.8],
		["sill_sala_w", Vector3(0.75, 0, 2.75), -PI / 2, null, 1.5, 0.0, func(p: Vector3): return p.y > 0.8],
		["window_sala_w", Vector3(0.75, 0, 2.75), -PI / 2, -PI / 2, 2.5, 0.0, func(p: Vector3): return p.x > 0.05],
		["window_quarto_f", Vector3(2.5, 3, 0.8), PI, PI, 2.5, 0.0, func(p: Vector3): return p.z > 0.05],
		["attic_up", Vector3(6.97, 3, 4.3), PI, PI, 5.0, -1.0, func(p: Vector3): return p.y > 5.9 and p.z < 0.8],
		["attic_down", Vector3(6.97, 6.0, 0.6), 0.0, 0.0, 5.0, -1.0, func(p: Vector3): return p.y < 3.1 and p.z > 4.0],
		["attic_exit", Vector3(6.97, 6.0, 0.6), -PI / 2, -PI / 2, 1.5, -1.0, func(p: Vector3): return p.x < 6.4 and p.y > 5.9],
		["attic_hole_west", Vector3(5.8, 6, 2.0), PI / 2, PI / 2, 2.5, -1.0, func(p: Vector3): return p.y > 5.9 and p.x < 6.55],
		["attic_hole_south", Vector3(6.97, 6, 3.6), PI, PI, 2.5, -1.0, func(p: Vector3): return p.y > 5.9 and p.z > 2.9],
		["attic_under", Vector3(6.0, 3, 2.5), PI / 2, PI / 2, 2.0, -1.0, func(p: Vector3): return p.x > 6.9 and p.y < 3.1],
		["attic_off_side", Vector3(7.025, 4.7, 2.0), -PI / 2, -PI / 2, 2.0, 0.3, func(p: Vector3): return p.x > 6.55 and p.y > 4.3],
		["porao_window", Vector3(2.5, -3, 5.6), -PI / 2, -PI / 2, 2.0, -1.0, func(p: Vector3): return p.x < 0.9],
		["rail_corredor", Vector3(6.75, 3, 6.0), -PI / 2, -PI / 2, 2.5, 0.0, func(p: Vector3): return p.y > 2.9 and p.x > 6.1],
		["rail_front", Vector3(5.6, 3, 3.3), 0.0, 0.0, 2.5, 0.0, func(p: Vector3): return p.y > 2.9 and p.z < 3.97],
		["gate", Vector3(6.45, -0.9, -4.8), PI, PI, 2.5, -1.0, func(p: Vector3): return p.z > -5.6],
		["jump_bed", Vector3(2.75, 3, 2.8), -PI / 2, null, 1.5, 0.2, func(p: Vector3): return p.y > 3.3],
		["jump_sofa", Vector3(2.5, 0, 2.3), PI, null, 1.5, 0.2, func(p: Vector3): return p.y > 0.3],
		["jump_counter", Vector3(8.8, 0, 8.85), 0.0, null, 1.5, 0.2, func(p: Vector3): return p.y > 0.8],
		["turn_at_wall", Vector3(0.35, 0, 3.0), -PI / 2, 0.0, 2.0, -1.0, func(p: Vector3): return p.z > 3.6],
		["corner_turn", Vector3(11.75, 3, 1.0), PI / 2, PI, 2.0, -1.0, func(p: Vector3): return p.z < 0.6],
		["doghouse_roof", Vector3(9.0, -0.9, 15.6), 0.0, null, 1.5, 0.2, func(p: Vector3): return p.y > -0.3],
	]
	for c in cases:
		var res: Array = await drive(c[1], c[2], c[3], c[4], c[5])
		var ok: bool = (c[6] as Callable).call(res[0])
		print("CATTEST %s %s jumped=%s end=%s col_yaw_err=%.2f stuck_frames=%d" % [c[0], "OK" if ok else "FAIL", res[3], res[0], res[1], res[2]])
	# safety net: from a known good spot, push the cat out past the fence
	await drive(Vector3(6.45, -0.9, -4.0), PI, null, 0.6, -1.0)
	cat.global_position = Vector3(6.45, -0.9, -7.5)
	for i in 3:
		await get_tree().physics_frame
		cat.tick(1.0 / 60.0, 0.0, false)
	print("CATTEST safety_net %s at %s" % ["OK" if cat.global_position.z > -5.6 else "FAIL", cat.global_position])
	print("CATTEST DONE")


## [final position, |yaw - col_yaw| at the end, frames the cat wanted to move but did not]
func drive(start: Vector3, yaw: float, move_yaw, secs: float, jump_at: float) -> Array:
	cat.teleport(start + Vector3(0, 0.05, 0), yaw)
	for i in 20:
		await get_tree().physics_frame
		cat.tick(1.0 / 60.0, yaw, true)
	if move_yaw != null:
		Input.action_press("move_forward")
	var t := 0.0
	var stuck := 0
	var jumped := false
	var flew := false
	while t < secs:
		await get_tree().physics_frame
		var before := cat.global_position
		if jump_at >= 0.0 and t >= jump_at and not jumped:
			Input.action_press("jump")
			jumped = true
		elif jumped:
			Input.action_release("jump")
		cat.tick(1.0 / 60.0, float(move_yaw) if move_yaw != null else yaw, true)
		flew = flew or cat.arc != null
		if OS.get_cmdline_user_args().has("--catlog") and int(t * 60) % 6 == 0:
			var cols := []
			for k in cat.get_slide_collision_count():
				var sc := cat.get_slide_collision(k)
				cols.append("%s n=%s" % [describe(sc.get_collider(), sc.get_collider_shape_index()), sc.get_normal()])
			print("  t=%.2f p=%s floor=%s vy=%.2f %s" % [t, cat.global_position, cat.is_on_floor(), cat.vy, cols])
		if move_yaw != null and cat.global_position.distance_to(before) < 0.0005:
			stuck += 1
		t += 1.0 / 60.0
	Input.action_release("move_forward")
	Input.action_release("jump")
	return [cat.global_position, absf(wrapf(cat.yaw - cat.col_yaw, -PI, PI)), stuck, flew]
