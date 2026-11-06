class_name CatSolids
extends RefCounted
## Extra colliders made from the visible meshes of the items listed in data/cat_solids.json: the
## Blender colliders are boxes (a seat, a table top) and the cat walked through what they leave out
## (sofa arms, table legs, the fruit bowl...). Found and checked with navcheck --catbump.
##   solid: one trimesh of the item on LAYER_WORLD
##   block: one convex hull around the item on LAYER_CAT_BLOCK (only the cat bumps into it)


## the item an exported mesh belongs to: the first node below Furniture / Shell / Props (as navcheck)
static func item_of(m: Node, house: Node) -> String:
	var n: Node = m
	while n.get_parent() != null and n.get_parent() != house and n.get_parent().name not in ["Furniture", "Shell", "Props", "Kit"] and not str(n.get_parent().name).begins_with("house"):
		n = n.get_parent()
	return str(n.name)


static func build(house: Node3D) -> void:
	var f := FileAccess.open("res://data/cat_solids.json", FileAccess.READ)
	if f == null:
		return
	var cfg: Dictionary = JSON.parse_string(f.get_as_text())
	var mode := {}
	var prefix := {}   # "log_1_*" -> every log of the woodpile
	for kind in ["solid", "block"]:
		for nm: String in cfg.get(kind, []):
			if nm.ends_with("*"):
				prefix[nm.trim_suffix("*")] = kind
			else:
				mode[nm] = kind
	var faces := {}    # item -> world-space triangles
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var nm := item_of(m, house)
		if not mode.has(nm):
			for p: String in prefix:
				if nm.begins_with(p):
					mode[nm] = prefix[p]
		if not mode.has(nm):
			continue
		var tri := m.mesh.get_faces()
		var xf := m.global_transform
		for i in tri.size():
			tri[i] = xf * tri[i]
		if not faces.has(nm):
			faces[nm] = PackedVector3Array()
		faces[nm].append_array(tri)
	var solid := StaticBody3D.new()
	solid.name = "CatSolids"
	solid.collision_layer = HouseBuilder.LAYER_WORLD
	solid.collision_mask = 0
	house.add_child(solid)
	var block := StaticBody3D.new()
	block.name = "CatBlocks"
	block.collision_layer = HouseBuilder.LAYER_CAT_BLOCK
	block.collision_mask = 0
	house.add_child(block)
	for nm in faces:
		var cs := CollisionShape3D.new()
		cs.name = str(nm).validate_node_name()
		cs.set_meta("tag", "cat_" + str(mode[nm]))
		if mode[nm] == "solid":
			var tm := ConcavePolygonShape3D.new()
			tm.backface_collision = true
			tm.set_faces(faces[nm])
			cs.shape = tm
			solid.add_child(cs)
		else:
			# the hull of a plant or a teapot from every vertex: snapped to a 1 cm grid first
			var seen := {}
			var pts := PackedVector3Array()
			for p: Vector3 in faces[nm]:
				var k := Vector3i(roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0))
				if not seen.has(k):
					seen[k] = true
					pts.append(p)
			var hull := ConvexPolygonShape3D.new()
			hull.points = pts
			cs.shape = hull
			block.add_child(cs)
