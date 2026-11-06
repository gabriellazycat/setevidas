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
	if OS.get_cmdline_user_args().has("--doorcheck"):
		door_check()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--atticcheck"):
		attic_check()
		get_tree().quit()
		return
	if args.has("cattest") or OS.get_cmdline_user_args().has("--cattest"):
		await cat_test()
		get_tree().quit()
		return
	if args.has("catbump") or OS.get_cmdline_user_args().has("--catbump"):
		await cat_bump(str(args.get("catbump", "")), float(args.get("bumpdepth", "0.03")))
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


## Each door leaf, swung open, against every other mesh in the house (world boxes, leaf shrunk 2 cm).
##   godot --headless --path godot res://scenes/navcheck.tscn -- --doorcheck
## Prints "DOORHIT <door> <state> hits <node>" and "DOORCHECK DONE <hits>".
func door_check() -> void:
	var bad := 0
	for d: Door in house.doors.values():
		if d.leaf == null:
			continue
		var hits := _door_hits(d)
		if hits.is_empty():
			continue
		var best := -1.0
		var a := d.angle
		while a >= 1.0:
			d.angle = a
			d._apply()
			if _door_hits(d).is_empty():
				best = a
				break
			a -= 0.05
		d.angle = d.target
		d._apply()
		for k in hits:
			bad += 1
			print("DOORHIT %s open %.2f hits %s | clean angle %.2f" % [d.id, d.target, k, best])
	print("DOORCHECK DONE %d" % bad)


## names of everything (but the shell, terrain, wall-mounted switches and frames) the leaf's box overlaps
func _door_hits(d: Door) -> Dictionary:
	var lt := d.leaf.global_transform
	var lb := AABB()
	var first := true
	for m in d.leaf.find_children("*", "MeshInstance3D", true, false):
		var mm := m as MeshInstance3D
		var bb := (lt.affine_inverse() * mm.global_transform) * mm.get_aabb()
		lb = bb if first else lb.merge(bb)
		first = false
	var hits := {}
	if first:
		return hits
	var core := lb.grow(-0.02)
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or d.leaf.is_ancestor_of(m):
			continue
		var n: Node = m
		while n.get_parent() != null and n.get_parent() != house and n.get_parent().name not in ["Furniture", "Shell", "Props", "Kit"] and not str(n.get_parent().name).begins_with("house"):
			n = n.get_parent()
		var nm := str(n.name)
		if nm.begins_with("house_") or nm == "fence" or nm.begins_with("hill") or nm.begins_with("SW") or nm.begins_with("paint_"):
			continue
		var bb := (lt.affine_inverse() * m.global_transform) * m.get_aabb()
		if bb.intersects(core):
			hits[nm] = true
	return hits


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
		# under the round table, beside its pedestal (straight at the pedestal it stops)
		["kitchen_table", Vector3(8.1, 0, 6.25), PI / 2, PI / 2, 1.0, -1.0, func(p: Vector3): return p.x > 9.5 and p.y < 0.1],
		["kitchen_pedestal", Vector3(8.1, 0, 6.7), PI / 2, PI / 2, 1.0, -1.0, func(p: Vector3): return p.x < 9.0],
		["sofa_arm", Vector3(3.0, 0.46, 1.5), PI / 2, PI / 2, 1.0, -1.0, func(p: Vector3): return p.x < 3.5],
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


# ---------------------------------------------------------------------- cat bump

## The cat walks into every piece of furniture and object of the house from all sides (and, from the
## tops it can stand on, across them), at walking and running speed. Each item's own visible meshes
## are turned into a test-only trimesh (layer 128, nothing collides with it); every frame the cat's
## collision shapes, shrunk by --bumpdepth, are checked against it. Also checks the hide spots (the
## cat slides straight there) along the line from the exit to the spot.
##   godot --headless --fixed-fps 60 --path godot res://scenes/navcheck.tscn -- --catbump[=name,name] [--bumpdepth=0.03] [--bumpall]
## Prints "BUMPHIT <item> frames <n> drives <k>/<total> at <pos> dir <deg> [run]" per item crossed,
## "BUMPHIDE <spot> ..." per hide spot inside something and "CATBUMP DONE <hits> of <items>".
const BUMP_LAYER := 128
const BUMP_SKIP := ["house_", "fence", "hill", "SW", "paint_", "rafter", "collar", "ridge", "Shell", "HATCH", "LADDER", "_"]
## what the cat is meant to pass through: brush and the vegetable bed (one hide spot is inside a shrub),
## the duct it crawls along, its own bed and bowls, things it carries, the devices' cords on the floor; props it knocks over are skipped too
const BUMP_PASS := ["shrub_", "weed_", "veg_", "tree_", "DUCT_", "duct_sleeve", "CARRY_", "catbed_", "bowl_food", "bowl_water", "dog_bowl", "NIGHTLIGHT", "lamp_shade", "PLUG_", "CORD_"]
var _bump_bodies := {}      # item -> StaticBody3D (layer 128)
var _bump_aabb := {}        # item -> AABB
var _bump_shapes := []      # [shrunk shape, the cat's CollisionShape3D it stands for]


func cat_bump(only: String, depth: float) -> void:
	cat = Cat.new()
	cat.house = house
	add_child(cat)
	await get_tree().physics_frame
	_collect_items(only.split(",", false) if only != "" else PackedStringArray())
	for cs in cat.get_children():
		if not (cs is CollisionShape3D) or (cs as CollisionShape3D).disabled:
			continue
		var s := (cs as CollisionShape3D).shape
		var sh: Shape3D
		if s is SphereShape3D:
			sh = SphereShape3D.new()
			sh.radius = maxf(0.01, s.radius - depth)
		elif s is CapsuleShape3D:
			sh = CapsuleShape3D.new()
			sh.radius = maxf(0.01, s.radius - depth)
			sh.height = maxf(sh.radius * 2.0 + 0.01, s.height - depth * 2.0)
		else:
			continue
		_bump_shapes.append([sh, cs])
	for i in 2:
		await get_tree().physics_frame
	var names := _bump_bodies.keys()
	names.sort()
	print("CATBUMP %d items" % names.size())
	var bad := 0
	for nm in names:
		var r := await _bump_item(nm)
		if r["hits"] > 0:
			bad += 1
			print("BUMPHIT %s frames %d drives %d/%d at %s dir %d%s  aabb %s" % [nm, r["frames"], r["hits"], r["total"], r["at"], r["dir"], " run" if r["run"] else "", _bump_aabb[nm]])
		elif OS.get_cmdline_user_args().has("--bumpall"):
			print("BUMPOK %s drives %d" % [nm, r["total"]])
	bad += _bump_hide_spots()
	print("CATBUMP DONE %d of %d" % [bad, names.size()])


## items = the first node below Furniture / Shell / Props (as in the door check); each gets one
## trimesh of all its meshes on the test layer
func _collect_items(only: PackedStringArray) -> void:
	var faces := {}
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var n: Node = m
		while n.get_parent() != null and n.get_parent() != house and n.get_parent().name not in ["Furniture", "Shell", "Props", "Kit"] and not str(n.get_parent().name).begins_with("house"):
			n = n.get_parent()
		var nm := str(n.name)
		var skip := false
		for p in BUMP_SKIP:
			if nm.begins_with(p):
				skip = true
		for p in BUMP_PASS:
			if nm.begins_with(p):
				skip = true
		if n is RigidBody3D:
			skip = true
		if skip or (not only.is_empty() and nm not in only):
			continue
		var bb := m.global_transform * m.get_aabb()
		if bb.size.y < 0.015:
			continue    # rugs, flat decals: the cat walks on them
		var f := m.mesh.get_faces()
		if f.is_empty():
			continue
		var xf := m.global_transform
		for i in f.size():
			f[i] = xf * f[i]
		if not faces.has(nm):
			faces[nm] = PackedVector3Array()
			_bump_aabb[nm] = bb
		faces[nm].append_array(f)
		_bump_aabb[nm] = (_bump_aabb[nm] as AABB).merge(bb)
	for nm in faces:
		var b := StaticBody3D.new()
		b.name = "BUMP_" + nm
		b.collision_layer = BUMP_LAYER
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cps := ConcavePolygonShape3D.new()
		cps.backface_collision = true
		cps.set_faces(faces[nm])
		cs.shape = cps
		b.add_child(cs)
		add_child(b)
		_bump_bodies[nm] = b


## does the shrunk cat overlap this item's trimesh now
func _bump_overlap(item_rid: RID) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = BUMP_LAYER
	for e in _bump_shapes:
		q.shape = e[0]
		q.transform = cat.global_transform * (e[1] as CollisionShape3D).transform
		for h in house.space.intersect_shape(q, 8):
			if h["rid"] == item_rid:
				return true
	return false


## the cat's real shapes clear of the world at p (a fair place to start a drive)
func _cat_fits(p: Vector3, yaw: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = cat.collision_mask
	for cs in cat.get_children():
		if not (cs is CollisionShape3D) or (cs as CollisionShape3D).disabled:
			continue
		q.shape = (cs as CollisionShape3D).shape
		q.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.03, 0)) * (cs as CollisionShape3D).transform
		if not house.space.intersect_shape(q, 1).is_empty():
			return false
	return true


func _floor_below(p: Vector3, down: float) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(p, p - Vector3(0, down, 0), HouseBuilder.LAYER_WORLD)
	var h := house.space.intersect_ray(q)
	if h.is_empty() or (h["normal"] as Vector3).y < 0.7:
		return null
	return h["position"]


func _bump_item(nm: String) -> Dictionary:
	var bb: AABB = _bump_aabb[nm]
	var rid := (_bump_bodies[nm] as StaticBody3D).get_rid()
	var c := bb.get_center()
	var rad := maxf(bb.size.x, bb.size.z) * 0.5
	var starts := []   # [pos, move yaw]
	# around it, on whatever it stands on, walking in toward the centre
	for k in 12:
		var a := TAU * k / 12.0
		var d := Vector3(sin(a), 0, cos(a))
		for dist in [rad + 0.45, rad + 0.3]:
			var top: Vector3 = Vector3(c.x, bb.position.y + 0.45, c.z) + d * float(dist)
			var f = _floor_below(top, 0.9)
			if f == null or absf((f as Vector3).y - bb.position.y) > 0.5:
				continue
			var mv := atan2(-d.x, -d.z)
			if _cat_fits(f, mv):
				starts.append([f, mv])
				break
	# the tops the cat can stand on in and around it (seats, table tops, beds), walking across
	var g := 0.2
	var tops := []
	var x := bb.position.x - 0.3
	while x <= bb.end.x + 0.3:
		var z := bb.position.z - 0.3
		while z <= bb.end.z + 0.3:
			var f = _floor_below(Vector3(x, bb.end.y + 0.4, z), bb.size.y + 0.4)
			if f != null and (f as Vector3).y > bb.position.y + 0.12 and (f as Vector3).y < bb.end.y + 0.05:
				tops.append(f)
			z += g
		x += g
	# points of the 20 cm grid spread over the tops: the same drives every run
	var used := 0
	var step := maxi(1, tops.size() / 6)   # ~6 points spread over the whole top
	for ti in range(0, tops.size(), step):
		var f = tops[ti]
		if used >= 16:
			break
		for k in 4:
			var mv := TAU * k / 4.0
			if _cat_fits(f, mv):
				starts.append([f, mv])
				used += 1
	var res := {"hits": 0, "frames": 0, "total": 0, "at": Vector3.ZERO, "dir": 0, "run": false}
	for s in starts:
		for run in [false, true]:
			var fr: Array = await _bump_drive(s[0], s[1], run, rad * 2.0 + 0.9, rid)
			res["total"] += 1
			if fr[0] > 0:
				res["hits"] += 1
				if fr[0] > res["frames"]:
					res["frames"] = fr[0]
					res["at"] = fr[1]
					res["dir"] = int(rad_to_deg(s[1]))
					res["run"] = run
	# a couple of frames of grazing at the very edge are the shrink margin, not a pass-through
	if res["frames"] < 3:
		res["hits"] = 0
	return res


## [frames overlapping, first place it overlapped]
func _bump_drive(start: Vector3, yaw: float, run: bool, dist: float, rid: RID) -> Array:
	cat.teleport(start + Vector3(0, 0.03, 0), yaw)
	for i in 6:
		await get_tree().physics_frame
		cat.tick(1.0 / 60.0, yaw, true)
	Input.action_press("move_forward")
	if run:
		Input.action_press("run")
	var secs := dist / (4.4 if run else 2.1) + 0.5
	var t := 0.0
	var frames := 0
	var at := Vector3.ZERO
	while t < secs:
		await get_tree().physics_frame
		cat.tick(1.0 / 60.0, yaw, true)
		if _bump_overlap(rid):
			if frames == 0:
				at = cat.global_position
			frames += 1
		t += 1.0 / 60.0
	Input.action_release("move_forward")
	Input.action_release("run")
	return [frames, at]


## the cat slides straight to the hide spot (Cat mode "hidden"): its shrunk shapes at the spot and
## along the line from the spot's exit must be clear of every item and of the world
func _bump_hide_spots() -> int:
	var bad := 0
	var L := Layout.data()
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = BUMP_LAYER | HouseBuilder.LAYER_WORLD
	for sp in L.get("HIDE_SPOTS", []):
		var p := Layout.v3(sp["p"])
		var ex := Layout.v3(sp.get("exit", sp["p"]))
		var hit := {}
		for k in 11:
			var at := ex.lerp(p, k / 10.0)
			var xf := Transform3D(Basis(Vector3.UP, float(sp.get("yaw", 0.0))), at + Vector3(0, 0.03, 0))
			for e in _bump_shapes:
				q.shape = e[0]
				q.transform = xf * (e[1] as CollisionShape3D).transform
				for h in house.space.intersect_shape(q, 8):
					var co := h["collider"] as Node
					var nm := str(co.name).trim_prefix("BUMP_") if str(co.name).begins_with("BUMP_") else describe(h["collider"], int(h["shape"]))
					hit[nm] = "%.1f" % (k / 10.0)
		if not hit.is_empty():
			bad += 1
			print("BUMPHIDE %s %s: %s" % [sp["id"], p, hit])
	return bad
