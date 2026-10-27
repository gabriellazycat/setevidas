class_name HouseBuilder
extends RefCounted
## Instances the Blender-built house, swaps in the real surface materials, places the Poly Haven
## furniture and builds the static colliders described in house_data.json.

const LAYER_WORLD := 1      # everything solid for the cat / props
const LAYER_CAMERA := 2     # what the camera collides with
const LAYER_SURFACE := 4    # tops the cat may jump onto (raycast for jump targets)
## invisible walls only for the cat (window openings, above the stair railing): the camera, floor and
## jump raycasts, people and ghosts all ignore them
const LAYER_CAT_BLOCK := 32

static var model_cache: Dictionary = {}


static func load_data() -> Dictionary:
	var f := FileAccess.open("res://assets/models/house/house_data.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


static func build(parent: Node3D) -> Dictionary:
	var data := load_data()
	var shell: Node3D = load("res://assets/models/house/house.glb").instantiate()
	shell.name = "Shell"
	parent.add_child(shell)
	# the Blender export also carries untextured copies of every Poly Haven piece: they would
	# z-fight with the textured instances placed below, so drop them
	var placed := {}
	for p in data["placements"]:
		placed[str(p["name"]).validate_node_name()] = true
	for n in shell.find_children("*", "Node3D", true, false):
		if placed.has(str(n.name)) and is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	Surfaces.apply_to(shell)
	_shadow_setup(shell)
	# the old tree by the balcony pokes its branches through the east wall of the ground floor
	var tree := shell.find_child("tree_balcony", true, false) as MeshInstance3D
	if tree:
		_cut_triangles(tree, AABB(Vector3(-2.0, -3.0, -0.4), Vector3(14.45, 6.35, 10.8)))
	var furn := Node3D.new()
	furn.name = "Furniture"
	parent.add_child(furn)
	for p in data["placements"]:
		var inst := instance_model(p["model"])
		if inst == null:
			continue
		if p.has("parts"):
			# the Blender build only kept some named parts of this model (a single wine bottle, one shrub...):
			# the rest would hang in the air next to it
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var keep := false
				for pr in p["parts"]:
					if str(mi.name).begins_with(pr):
						keep = true
				if not keep:
					mi.get_parent().remove_child(mi)
					mi.queue_free()
		inst.name = str(p["name"]).validate_node_name()
		inst.transform = xform(p["xform"])
		furn.add_child(inst)
	var cols := StaticBody3D.new()
	cols.name = "Colliders"
	cols.collision_layer = LAYER_WORLD
	cols.collision_mask = 0
	parent.add_child(cols)
	var cam := StaticBody3D.new()
	cam.name = "CameraColliders"
	cam.collision_layer = LAYER_CAMERA
	cam.collision_mask = 0
	parent.add_child(cam)
	var catb := StaticBody3D.new()
	catb.name = "CatBlockers"
	catb.collision_layer = LAYER_CAT_BLOCK
	catb.collision_mask = 0
	parent.add_child(catb)
	for c in data["colliders"]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var t := Transform3D.IDENTITY
		if c.has("obb"):
			box.size = Layout.v3(c["size"])
			var b: Array = c["basis"]
			t.basis = Basis(Vector3(b[0][0], b[1][0], b[2][0]), Vector3(b[0][1], b[1][1], b[2][1]), Vector3(b[0][2], b[1][2], b[2][2]))
			t.origin = Layout.v3(c["center"])
		else:
			var mn := Layout.v3(c["min"])
			var mx := Layout.v3(c["max"])
			box.size = (mx - mn).max(Vector3(0.01, 0.01, 0.01))
			t.origin = (mn + mx) * 0.5
		shape.shape = box
		shape.transform = t
		shape.set_meta("tag", c.get("tag", ""))
		if c.get("cat_only", false):
			catb.add_child(shape)
			continue
		cols.add_child(shape)
		if c.get("cam", false):
			var s2 := shape.duplicate()
			cam.add_child(s2)
	return data


## a furniture model: our procedural kit piece (tools/blender/build_kit.py, materials named by
## materials.json key) when there is one, else the old Poly Haven glTF
static func instance_model(id: String) -> Node3D:
	if not model_cache.has(id):
		var path := "res://assets/models/kit/%s.glb" % id
		if not ResourceLoader.exists(path):
			path = "res://assets/models/ph/%s/%s.gltf" % [id, id]
		if not ResourceLoader.exists(path):
			push_warning("missing model " + id)
			model_cache[id] = null
		else:
			model_cache[id] = load(path)
	var ps: PackedScene = model_cache[id]
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	if ps.resource_path.begins_with("res://assets/models/kit/"):
		Surfaces.apply_to(n)
	_shadow_setup(n)
	return n


## a Poly Haven model (optionally only some named parts), re-centred so its origin is the
## bottom-centre and uniformly scaled to `height`. lay = turn it on its side (books).
static func instance_parts(id: String, parts: Array, height: float, lay := false) -> Node3D:
	var inst := instance_model(id)
	var holder := Node3D.new()
	if inst == null:
		return holder
	if not parts.is_empty():
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var keep := false
			for pr in parts:
				if str(mi.name).begins_with(pr):
					keep = true
			if not keep:
				mi.queue_free()
				mi.get_parent().remove_child(mi)
	var aabb := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := _rel_xform(m, inst)
		var b := t * m.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	var size := aabb.size
	var sc := height / maxf(0.001, size.y) if not lay else height / maxf(0.001, size.y)
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child(inst)
	inst.position = -Vector3(aabb.position.x + size.x / 2, aabb.position.y, aabb.position.z + size.z / 2)
	if lay:
		pivot.rotation = Vector3(0, 0, PI / 2)
		pivot.position = Vector3(size.y * sc / 2.0, size.x * sc / 2.0, 0)
	pivot.scale = Vector3.ONE * sc
	return holder


## drop every triangle of a mesh that touches `region` (world space)
static func _cut_triangles(mi: MeshInstance3D, region: AABB) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var xf := mi.global_transform
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null:
			idx = PackedInt32Array(range(verts.size()))
		var kept := PackedInt32Array()
		for i in range(0, idx.size() - 2, 3):
			if region.has_point(xf * verts[idx[i]]) or region.has_point(xf * verts[idx[i + 1]]) or region.has_point(xf * verts[idx[i + 2]]):
				continue
			kept.append(idx[i])
			kept.append(idx[i + 1])
			kept.append(idx[i + 2])
		if kept.is_empty():
			continue
		arr[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	mi.mesh = out


static func _rel_xform(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p and p != root:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


static func xform(rows: Array) -> Transform3D:
	var b := Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]), Vector3(rows[0][2], rows[1][2], rows[2][2]))
	return Transform3D(b, Vector3(rows[0][3], rows[1][3], rows[2][3]))


static func _shadow_setup(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		m.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		# Poly Haven "_rough" maps are greyscale: once VRAM-compressed only the red channel holds
		# the value, but glTF reads roughness from green (which then reads as 0: a mirror)
		if m.mesh:
			for si in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(si) as BaseMaterial3D
				if mat and mat.roughness_texture and "_rough" in mat.roughness_texture.resource_path:
					mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
				if mat and m.get_surface_override_material(si) == null:
					var st := Surfaces.stylize_standard(mat)
					if st != mat:
						m.set_surface_override_material(si, st)
