class_name House
extends Node3D
## The house at runtime: geometry + furniture from the Blender build, plus every living part of it
## (lights, doors, devices, faucets, props, clues, attic hatch, duct, basculante, chest,
## marks seen with Cat Vision, the chalk circle, dust in the air). Port of House.ts.

const STATIC_SHADER := preload("res://shaders/screen_static.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

var data: Dictionary
var nodes: Dictionary
var shell: Node3D
var lights: LightSystem
var nav: NavGraph
var doors: Dictionary = {}
var props: PropSystem
var devices: Array = []
var faucets: Array = []
var marks: Array = []
var carryables: Dictionary = {}

var chest_pos := Vector3(3.1, 6, 9.0)
var cat_bed := Vector3(4.25, 0, 4.6)
var clock_pos := Vector3(0.3, 1.75, 1.0)
var ritual_center := Vector3(3.6, -3, 4.4)
var ritual_glow := 0.0
const RITUAL_CHALK := 0.6  # opacity of the bare chalk, before any object glows in it
const RELIC_SLOTS := 6
## where the two cardboard boxes start (the second one only from day 6)
const BOX_HOMES := [Vector3(9.4, 0, 5.1), Vector3(6.3, 3, 8.6)]
const NIGHTLIGHT_HOME := Vector3(9.7, 0, 10.9)
var boxes: Array = []        # [{node, body, pos, yaw}]
var nightlight_glow: OmniLight3D

var hatch_target := 0.0
var hatch_open := 0.0
var duct_target := 0.0
var duct_open := 0.0
var basculante_target := 0.0
var basculante_open := 0.0
var chest_target := 0.0
var chest_open := 0.0

var _hatch_w: Node3D
var _hatch_e: Node3D
var _hatch_w_rest := Basis.IDENTITY
var _hatch_e_rest := Basis.IDENTITY
var _hatch_w_pos := Vector3.ZERO
var _hatch_e_pos := Vector3.ZERO
var _ladder: Node3D
var _cord: Node3D
var _ducts: Array = []
var _basculante: Node3D
var _bas_rest := Basis.IDENTITY
var _chest_lid: Node3D
var _chest_pivot: Node3D
var _clock_hands: Array = []
var _sheets: Array = []
var _rocking: Node3D
var _rock := 0.0
var _rock_v := 0.0
var bowl_food: Node3D
var guest_dust: Array = []
var guest_movein: Array = []
var ritual_decal: Decal
var _hatch_col: CollisionShape3D
var _ladder_cols: Array[CollisionShape3D] = []   # the attic stair ramp, its top and the cat-only guards
var _bas_col: CollisionShape3D
var _t := 0.0
var space: PhysicsDirectSpaceState3D
var bed_info := {}          # who -> {x0, x1, z0, z1, top} (mattress rectangle)


class Device:
	var id: String
	var name: String
	var room: String
	var pos: Vector3
	var outlet: Vector3
	var normal: Vector3
	var plugged := true
	var hidden := false   # the night light before morning 6, or while the cat carries it
	var glow := 0.0
	var screen: MeshInstance3D
	var screen_mat: ShaderMaterial
	var plug: MeshInstance3D
	var cord: MeshInstance3D
	var cord_from: Vector3
	var floor_y := 0.0
	var light_pos: Vector3


class Faucet:
	var id: String
	var name: String
	var room: String
	var spout: Vector3
	var handle: Vector3
	var running := 0.0
	var level := 0.0
	var puddle := 0.0
	var bottom_y := 0.0
	var top_y := 0.0
	var floor_y := 0.0
	var puddle_center: Vector3
	var basin_c: Vector3          # the middle of the basin (where things dropped down the drain wait)
	var water: MeshInstance3D
	var stream: MeshInstance3D
	var puddle_mesh: MeshInstance3D
	var splash: GPUParticles3D
	var drip_t := 0.0


class Mark:
	var id: String
	var day: int
	var pos: Vector3
	var decal: Decal
	var text: String
	var alpha := 0.0


func build() -> void:
	space = get_world_3d().direct_space_state
	data = HouseBuilder.build(self)
	nodes = data["nodes"]
	shell = get_node("Shell")
	nav = NavGraph.new()
	lights = LightSystem.new()
	lights.name = "Lights"
	add_child(lights)
	lights.build(self, nodes)
	if nodes.has("clock"):
		clock_pos = Layout.v3(nodes["clock"])
	_build_doors()
	props = PropSystem.new()
	props.name = "Props"
	add_child(props)
	props.build()
	_build_devices()
	_build_faucets()
	_build_dynamic()
	_build_carryables()
	_build_marks()
	_build_ritual()
	_build_dust()
	_build_window_glows()


## trimesh colliders for the beds (the cat can jump on them, nobody walks through them) and the
## mattress rectangles, measured by raycasts
func measure_beds() -> void:
	var furn := get_node("Furniture")
	var bodies := {}
	for pair in [["clara", "bed_clara", 2.8], ["davi", "bed_guest", 8.33]]:
		var node := furn.find_child(pair[1], true, false) as Node3D
		if node == null:
			continue
		var body := StaticBody3D.new()
		body.name = "BedCollider_" + pair[0]
		body.collision_layer = HouseBuilder.LAYER_WORLD | HouseBuilder.LAYER_CAMERA
		body.collision_mask = 0
		add_child(body)
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var faces := m.mesh.get_faces()
			var xf := m.global_transform
			for i in faces.size():
				faces[i] = xf * faces[i]
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
		bodies[pair[0]] = [body, pair[2]]
	await get_tree().physics_frame
	await get_tree().physics_frame
	for who in bodies:
		var zc: float = bodies[who][1]
		var hits := []
		for xi in 50:
			var x := 0.0 + xi * 0.05
			hits.append([x, _probe_y(x, zc)])
		var mids := []
		for h in hits:
			if h[1] > 3.25 and h[1] < 3.8:
				mids.append(h[1])
		if mids.is_empty():
			continue
		mids.sort()
		var top: float = mids[mids.size() / 2]
		var xs := []
		for h in hits:
			if absf(h[1] - top) < 0.05:
				xs.append(h[0])
		var x0: float = xs.min()
		var x1: float = xs.max()
		var xm := (x0 + x1) / 2.0
		var zs := []
		for zi in 60:
			var z := zc - 1.2 + zi * 0.04
			if absf(_probe_y(xm, z) - top) < 0.05:
				zs.append(z)
		bed_info[who] = {"x0": x0, "x1": x1, "z0": zs.min(), "z1": zs.max(), "top": top}
		print("BED %s %s" % [who, bed_info[who]])


func _probe_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 4.6, z), Vector3(x, 3.0, z), HouseBuilder.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit else -1.0


func find(name: String) -> Node3D:
	return find_child(name, true, false) as Node3D


# ---------------------------------------------------------------------- doors


func _build_doors() -> void:
	for d in Layout.data()["DOORS"]:
		var leaf := find("DOOR_" + str(d["id"]))
		var door := Door.new(d, leaf, self)
		doors[door.id] = door


# ---------------------------------------------------------------------- devices


func _build_devices() -> void:
	var tv := _add_device("tv", "a TV", "sala", Vector3(2.5, 0.83, 5.2), "outlet_tv", 0.0)
	var tvn := find("TV")
	if tvn:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.4, 0.3)
		q.mesh = qm
		tvn.add_child(q)
		q.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(2.55, 0.83, 4.952))
		tv.screen = q
	var radio := _add_device("radio", "o rádio", "cozinha", Vector3(10.66, 1.02, 6.4), "outlet_radio", 0.9)
	var dial := find("RADIO_DIAL")
	if dial:
		radio.screen = dial as MeshInstance3D
	var lap := _add_device("laptop", "o notebook", "escritorio", Vector3(2.4, 0.86, 9.6), "outlet_laptop", 0.0)
	var lapn := find("LAPTOP")
	if lapn:
		for mi in lapn.find_children("*", "MeshInstance3D", true, false):
			if str(mi.name).find("screen") >= 0:
				lap.screen = mi
	for dv: Device in devices:
		if dv.screen:
			var m := ShaderMaterial.new()
			m.shader = STATIC_SHADER
			m.set_shader_parameter("tint", Color(1.0, 0.68, 0.36) if dv.id == "radio" else Color(0.6, 0.78, 1.0))
			m.set_shader_parameter("dial", dv.id == "radio")
			if dv.id == "laptop":
				var src := dv.screen.mesh.surface_get_material(dv.screen.mesh.get_surface_count() - 1)
				dv.screen.set_surface_override_material(dv.screen.mesh.get_surface_count() - 1, m)
			else:
				dv.screen.material_override = m
			dv.screen_mat = m
		set_plugged(dv, true)


func _add_device(id: String, nm: String, room: String, pos: Vector3, outlet_key: String, floor_y: float) -> Device:
	var dv := Device.new()
	dv.id = id
	dv.name = nm
	dv.room = room
	dv.pos = pos
	var o: Dictionary = nodes.get(outlet_key, {"p": [pos.x, 0.3, pos.z], "n": [0, 0, -1]})
	dv.outlet = Layout.v3(o["p"])
	dv.normal = Layout.v3(o["n"])
	dv.floor_y = floor_y
	dv.cord_from = pos + Vector3(0, -0.2, 0) - dv.normal * 0.05
	dv.plug = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.045, 0.04)
	dv.plug.mesh = bm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.05, 0.05, 0.05)
	pm.roughness = 0.4
	dv.plug.material_override = pm
	add_child(dv.plug)
	dv.cord = MeshInstance3D.new()
	dv.cord.material_override = pm
	add_child(dv.cord)
	devices.append(dv)
	return dv


func set_plugged(d: Device, plugged: bool) -> void:
	d.plugged = plugged
	var n := d.normal
	var at := d.outlet + n * 0.025 if plugged else Vector3(d.outlet.x, d.floor_y + 0.02, d.outlet.z) + n * 0.35
	d.plug.global_position = at
	d.plug.look_at(at + n + Vector3(0.0001, 0, 0), Vector3.UP)
	var a := d.cord_from
	var mid := a.lerp(at, 0.5)
	mid.y = maxf(minf(a.y, at.y) - 0.15, d.floor_y + 0.01)
	var curve := Curve3D.new()
	curve.add_point(a)
	curve.add_point(mid, (a - at) * 0.25, (at - a) * 0.25)
	curve.add_point(at)
	d.cord.mesh = _tube(curve, 0.006)


static func _tube(curve: Curve3D, r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := curve.tessellate(4, 3)
	var seg := 6
	var rings: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.01:
			side = t.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(t).normalized()
		var ring := []
		for k in seg:
			var ang := TAU * k / seg
			ring.append([p + (side * cos(ang) + up * sin(ang)) * r, side * cos(ang) + up * sin(ang)])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in seg:
			var l := (k + 1) % seg
			for v in [rings[i][k], rings[i + 1][k], rings[i + 1][l], rings[i][k], rings[i + 1][l], rings[i][l]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	return st.commit()


# ---------------------------------------------------------------------- faucets


func _build_faucets() -> void:
	var c: Dictionary = nodes.get("faucet_coz", {})
	if c:
		var b: Array = c["basin"]
		_add_faucet("coz", "a pia da cozinha", "cozinha", Layout.v3(c["spout"]), Layout.v3(c["handle"]), b[1], 0.88, 0.0, Layout.v3(c["floor"]), Vector2(b[3] - 0.04, b[4] - 0.04), Vector3(b[0], b[1], b[2]))
	var bb: Dictionary = nodes.get("faucet_banb", {})
	if bb:
		var b2: Array = bb["basin"]
		_add_faucet("banb", "a pia do banheiro", "banheiro_baixo", Layout.v3(bb["spout"]), Layout.v3(bb["handle"]), b2[1], 0.86, 0.0, Layout.v3(bb["floor"]), Vector2(b2[3], b2[4]), Vector3(b2[0], b2[1], b2[2]))
	var tb: Dictionary = nodes.get("tub", {})
	if tb:
		var r: Array = tb["rect"]
		var sp := Layout.v3(tb["spout"])
		_add_faucet("tub", "a banheira", "banheiro_cima", sp, sp + Vector3(0.06, -0.12, 0), tb["bottom"], tb["top"], 3.0, Vector3(10.6, 3.0, 8.8), Vector2(r[2] - r[0], r[3] - r[1]), Vector3((r[0] + r[2]) / 2, tb["bottom"], (r[1] + r[3]) / 2))


func _water_mat(kind := "basin") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("kind", 0 if kind == "basin" else (1 if kind == "stream" else 2))
	return m


func _add_faucet(id: String, nm: String, room: String, spout: Vector3, handle: Vector3, bottom: float, top: float, floor_y: float, puddle_c: Vector3, basin: Vector2, basin_c: Vector3) -> void:
	var f := Faucet.new()
	f.id = id
	f.name = nm
	f.room = room
	f.spout = spout
	f.handle = handle
	f.bottom_y = bottom
	f.top_y = top
	f.floor_y = floor_y
	f.puddle_center = puddle_c
	f.basin_c = basin_c
	f.water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = basin
	f.water.mesh = pm
	f.water.material_override = _water_mat("basin")
	f.water.position = basin_c
	f.water.visible = false
	add_child(f.water)
	f.stream = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.007
	cm.bottom_radius = 0.011
	cm.height = 1.0
	cm.radial_segments = 8
	cm.cap_top = false
	cm.cap_bottom = false
	f.stream.mesh = cm
	f.stream.material_override = _water_mat("stream")
	f.stream.visible = false
	f.stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(f.stream)
	f.puddle_mesh = MeshInstance3D.new()
	var pd := PlaneMesh.new()
	pd.size = Vector2(2.0, 2.0)
	f.puddle_mesh.mesh = pd
	f.puddle_mesh.material_override = _water_mat("puddle")
	f.puddle_mesh.position = Vector3(puddle_c.x, floor_y + 0.006, puddle_c.z)
	f.puddle_mesh.scale = Vector3.ONE * 0.001
	f.puddle_mesh.visible = false
	f.puddle_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(f.puddle_mesh)
	f.splash = FX.splash()
	add_child(f.splash)
	faucets.append(f)


# ---------------------------------------------------------------------- dynamic pieces


func _static_box(center: Vector3, size: Vector3, rot := Basis.IDENTITY, layers := 3) -> CollisionShape3D:
	var b := StaticBody3D.new()
	b.collision_layer = layers
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.transform = Transform3D(rot, center)
	b.add_child(cs)
	add_child(b)
	return cs


func _build_dynamic() -> void:
	var H: Dictionary = Layout.data()["HATCH"]
	_hatch_w = find("HATCH_W")
	_hatch_e = find("HATCH_E")
	if _hatch_w:
		_hatch_w_rest = _hatch_w.transform.basis
		_hatch_w_pos = _hatch_w.position
	if _hatch_e:
		_hatch_e_rest = _hatch_e.transform.basis
		_hatch_e_pos = _hatch_e.position
	_ladder = find("LADDER")
	_cord = find("HATCH_CORD")
	_hatch_col = _static_box(Vector3((H["x0"] + H["x1"]) / 2, 5.9, (H["z0"] + H["z1"]) / 2), Vector3(H["x1"] - H["x0"], 0.2, H["z1"] - H["z0"]))
	# the attic stair works like the others: one straight flight and a plain ramp through the middle of the treads,
	# on the world layer (the cat's floor probes must see it, or it slides off as if perched on a ledge). It only
	# exists while the hatch is open. Cat-only walls along the open (west) side and around the hole in the attic.
	var A: Dictionary = Layout.data()["ATTIC"]
	var x0: float = A["x0"]
	var x1: float = A["x1"]
	var zf: float = A["z_foot"]
	var zt: float = A["z_top"]
	var run := (zf - zt) / float(A["steps"])
	var z_open := zt + 0.65
	_ladder_cols.append(_ramp_box((x0 + x1) / 2.0, x1 - x0, Vector3(0, 3.0, zf + run * 0.5), Vector3(0, 6.0, zt + run * 0.5), HouseBuilder.LAYER_WORLD))
	_ladder_cols.append(_static_box(Vector3((x0 + x1) / 2.0, 5.95, zt + run * 0.25), Vector3(x1 - x0, 0.1, run * 0.5 + 0.02), Basis.IDENTITY, HouseBuilder.LAYER_WORLD))
	for g in [
			[Vector3(x0 - 0.05, 3.0, H["z1"]), Vector3(x0 + 0.01, 5.8, zf)],        # open side, under the corridor ceiling
			[Vector3(x0 - 0.05, 3.0, z_open), Vector3(x0 + 0.01, 7.0, H["z1"])],    # open side through the hole + attic railing
			[Vector3(x0, 6.0, H["z1"] - 0.06), Vector3(x1, 7.0, H["z1"])]]:         # attic railing across the south end
		var mn: Vector3 = g[0]
		var mx: Vector3 = g[1]
		_ladder_cols.append(_static_box((mn + mx) * 0.5, mx - mn, Basis.IDENTITY, HouseBuilder.LAYER_CAT_BLOCK))
	for i in 2:
		var dn := find("DUCT_%d" % i)
		if dn:
			_ducts.append([dn, dn.transform.basis])
	_basculante = find("BASCULANTE")
	if _basculante:
		_bas_rest = _basculante.transform.basis
	_bas_col = _static_box(Vector3(10.4, 4.95, 6.0), Vector3(0.8, 0.7, 0.2))
	# chest lid: pivot on the back edge of the Poly Haven treasure chest
	var chest := find("CHEST")
	if chest:
		for mi in chest.find_children("*lid*", "MeshInstance3D", true, false):
			_chest_lid = mi
		if _chest_lid:
			var aabb := (_chest_lid as MeshInstance3D).get_aabb()
			var gt := _chest_lid.global_transform
			var back := gt * Vector3(aabb.position.x + aabb.size.x / 2, aabb.position.y, aabb.position.z)
			_chest_pivot = Node3D.new()
			add_child(_chest_pivot)
			_chest_pivot.global_position = back
			_chest_pivot.global_rotation = Vector3(0, chest.global_rotation.y, 0)
			_chest_lid.reparent(_chest_pivot, true)
	var clock := find("CLOCK")
	if clock:
		for mi in clock.find_children("*Hand*", "MeshInstance3D", true, false):
			_clock_hands.append([mi, mi.transform, str(mi.name).find("Hour") >= 0])
	for i in 3:
		var sh := find("SHEET_%d" % i)
		if sh:
			_sheets.append([sh, sh.transform])
	_rocking = find("ROCKING_CHAIR")
	bowl_food = find("BOWL_FOOD")
	if bowl_food:
		_build_kibble()
	for n in find_children("GUEST_DUST*", "", true, false):
		guest_dust.append(n)
	for n in find_children("GUEST_MOVEIN*", "", true, false):
		guest_movein.append(n)
	var furn := get_node("Furniture")
	for p in data["placements"]:
		if p.get("group", "") == "GUEST_MOVEIN":
			var n2 := furn.get_node_or_null(NodePath(str(p["name"]).validate_node_name()))
			if n2:
				guest_movein.append(n2)
	set_hatch(false, true)
	set_duct(false, true)
	set_basculante(false, true)
	set_guest_move_in(false)


## a ramp whose top surface runs from a to b (y, z at the lane centre x)
func _ramp_box(cx: float, width: float, a: Vector3, b: Vector3, layers: int) -> CollisionShape3D:
	var run := b.z - a.z
	var rise := b.y - a.y
	var length := sqrt(run * run + rise * rise)
	var up := Vector3(0, absf(run), -signf(run) * rise).normalized()   # the surface normal, pointing up
	var mid := Vector3(cx, (a.y + b.y) / 2.0, (a.z + b.z) / 2.0) - up * 0.05
	var ang := atan2(rise, -run) if run < 0.0 else atan2(-rise, run)
	return _static_box(mid, Vector3(width, 0.1, length), Basis(Vector3.RIGHT, ang), layers)


func set_hatch(open: bool, instant := false) -> void:
	hatch_target = 1.0 if open else 0.0
	if instant:
		hatch_open = hatch_target
	if _ladder and instant:
		_ladder.visible = open
	if _cord:
		_cord.visible = not open
	_hatch_col.disabled = open
	if instant:
		_set_ladder_cols(open)


## the cat's ramps and guards switch on with the stair, which appears once the hatch leaves are open
func _set_ladder_cols(on: bool) -> void:
	for c in _ladder_cols:
		c.disabled = not on


func set_duct(open: bool, instant := false) -> void:
	duct_target = 1.0 if open else 0.0
	if instant:
		duct_open = duct_target


func set_basculante(open: bool, instant := false) -> void:
	basculante_target = 1.0 if open else 0.0
	if instant:
		basculante_open = basculante_target


func set_chest(open: bool) -> void:
	chest_target = 1.0 if open else 0.0


func set_guest_move_in(on: bool) -> void:
	set_guest_parts(on, not on)


## Davi's things in the guest room and the dust sheet over its bed, separately (day 4: the sheet comes
## off when he pulls it, his things appear when he puts the suitcase down)
func set_guest_parts(items: bool, dust: bool) -> void:
	for n in guest_movein:
		(n as Node3D).visible = items
	for n in guest_dust:
		(n as Node3D).visible = dust


func rock_chair(strength := 1.0) -> void:
	_rock_v += 0.25 * strength


# ---------------------------------------------------------------------- carryables, marks, ritual


func _build_carryables() -> void:
	_add_carry("foto", "a foto antiga", Carry.make("foto"), Vector3(6.75, -3 + 0.01, 0.55))
	_add_carry("coleira", "a coleira antiga", Carry.make("coleira"), Vector3(8.5, -3, 0.16))
	_add_carry("chave", "a chave do baú", Carry.make("chave"), Vector3(2.0, 6.8, 2.2))
	_add_carry("toy", "o ratinho de brinquedo", Carry.make("toy"), Vector3(3.6, 0, 4.0))
	_add_carry("yarn", "o novelo de lã", Carry.make("yarn"), Vector3(1.6, 0.47, 1.6))
	# the night light (carried like any small thing) and the cardboard boxes
	var nl := _add_carry("nightlight", "a luz noturna", Carry.make_nightlight(), NIGHTLIGHT_HOME)
	nightlight_glow = OmniLight3D.new()
	nightlight_glow.light_color = Color(1.0, 0.76, 0.46)
	nightlight_glow.light_energy = 0.9
	nightlight_glow.omni_range = 3.8
	nightlight_glow.position = Vector3(0, 0.08, 0)
	nightlight_glow.shadow_enabled = false
	nl.node.add_child(nightlight_glow)
	var nld := _add_device("nightlight", "a luz noturna", "despensa", NIGHTLIGHT_HOME + Vector3(0, 0.06, 0), "", NIGHTLIGHT_HOME.y)
	nld.plug.visible = false
	nld.cord.visible = false
	nld.hidden = true
	for i in BOX_HOMES.size():
		var bn := Carry.make_box()
		add_child(bn)
		var body := StaticBody3D.new()
		body.collision_layer = HouseBuilder.LAYER_WORLD | HouseBuilder.LAYER_SURFACE
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.56, 0.36, 0.44)
		cs.shape = bs
		cs.position = Vector3(0, 0.18, 0)
		body.add_child(cs)
		bn.add_child(body)
		boxes.append({"node": bn, "body": body, "shape": cs, "pos": BOX_HOMES[i], "yaw": 0.0})
		set_box(i, BOX_HOMES[i], 0.0, false)
	# Ivone's things for the night mission: a fixed pool, dressed per night by the game
	for i in RELIC_SLOTS:
		var holder := Node3D.new()
		holder.name = "RELIC_%d" % i
		var rc := _add_carry("relic_%d" % i, "", holder, Vector3(0, -50, 0))
		rc.enabled = false
		holder.visible = false


## shows / moves / ruins a cardboard box; hidden while that morning has not unlocked it yet
func set_box(i: int, p: Vector3, yaw: float, shown: bool, used := false) -> void:
	var b: Dictionary = boxes[i]
	b["pos"] = p
	b["yaw"] = yaw
	var n: Node3D = b["node"]
	n.visible = shown
	n.global_position = p
	n.rotation = Vector3(0, yaw, 0.18 if used else 0.0)
	n.scale = Vector3(1.0, 0.55, 1.0) if used else Vector3.ONE
	(b["shape"] as CollisionShape3D).disabled = not shown


func _add_carry(id: String, nm: String, node: Node3D, at: Vector3) -> PropSystem.Carryable:
	var c := PropSystem.Carryable.new()
	c.id = id
	c.name = nm
	c.node = node
	add_child(node)
	c.place(at)
	carryables[id] = c
	return c


func _build_marks() -> void:
	var defs := [
		["m_tv", 2, "claw", Vector3(3.55, 0.45, 5.43), Vector3(0, 0, -1), "Arranhões perto da tomada da TV. Algo aqui gosta de eletricidade."],
		["m_radio", 2, "claw", Vector3(10.93, 1.3, 6.95), Vector3(-1, 0, 0), "Marcas ao redor da tomada do rádio. Um sussurro ficou preso nos fios."],
		["m_laptop", 2, "claw", Vector3(3.5, 0.45, 9.89), Vector3(0, 0, -1), "O notebook cheira a queimado. Tomadas são a porta de entrada dele."],
		["m_tub", 3, "hand", Vector3(10.6, 3.85, 9.89), Vector3(0, 0, -1), "Mãos molhadas na parede da banheira. Ela vem pela água."],
		["m_sink", 3, "hand", Vector3(8.8, 1.4, 9.89), Vector3(0, 0, -1), "A torneira da cozinha está gelada. Alguém a abre de dentro."],
		["m_chest", 4, "hand_small", Vector3(3.1, 6.3, 8.72), Vector3(0, 0, -1), "Mãozinhas pequenas no baú, por dentro. Ela só anda quando ninguém olha."],
		["m_door", 5, "hand", Vector3(6.45, 1.35, 0.03), Vector3(0, 0, 1), "Uma mão enorme do lado de dentro da porta da frente. Ele quer ser convidado."],
		["m_hound", 2, "claw", Vector3(6.3, 0.0, 2.4), Vector3(0, 1, 0), "Marcas fundas de garras no piso do hall. Algo grande rondou por aqui, e não foi atrás de Clara: foi atrás de você."],
		["m_porao", 2, "claw", Vector3(4.6, -3.0, 6.0), Vector3(0, 1, 0), "O chão do porão está riscado. A Sombra começa aqui, sempre."],
	]
	for d in defs:
		var mk := Mark.new()
		mk.id = d[0]
		mk.day = d[1]
		mk.pos = d[3]
		mk.text = d[5]
		var dec := Decal.new()
		var tex: Texture2D = load("res://assets/textures/gen/mark_%s.png" % d[2])
		dec.texture_albedo = tex
		dec.texture_emission = premul(tex)
		dec.emission_energy = 2.0
		dec.modulate = Color(0.45, 0.95, 1.0, 0.0)
		dec.albedo_mix = 0.6
		var sz := 0.38 if d[2] == "claw" else 0.3
		dec.size = Vector3(sz, 0.08, sz)
		var n: Vector3 = d[4]
		dec.position = mk.pos
		if absf(n.y) < 0.5:
			# decals project along their -Y: point it into the wall
			dec.basis = Basis.looking_at(-n, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)
		add_child(dec)
		dec.visible = false
		mk.decal = dec
		marks.append(mk)


## emission textures for decals must be premultiplied, or the transparent parts glow as a square
static func premul(tex: Texture2D, size := 512) -> Texture2D:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() > size:
		img.resize(size, size * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		data[i] = data[i] * a / 255
		data[i + 1] = data[i + 1] * a / 255
		data[i + 2] = data[i + 2] * a / 255
		data[i + 3] = 255
	var out := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


func _build_ritual() -> void:
	ritual_decal = Decal.new()
	var tex: Texture2D = load("res://assets/textures/gen/chalk_circle.png")
	ritual_decal.texture_albedo = tex
	ritual_decal.texture_emission = premul(tex)
	ritual_decal.size = Vector3(2.6, 0.3, 2.6)
	ritual_decal.position = ritual_center + Vector3(0, 0.05, 0)
	ritual_decal.modulate = Color(1, 1, 1, 0)
	ritual_decal.emission_energy = 0.0
	add_child(ritual_decal)


## from outside, lit rooms glow warm behind their windows (light scattering in the curtains)
var _glows: Array = []   # [MeshInstance3D, StandardMaterial3D, room]


func _build_window_glows() -> void:
	for w in Layout.data()["WINDOWS"]:
		if not w.get("exterior", false):
			continue
		var along_x: bool = w["axis"] == "x"
		var inside := float(w.get("inside", 1))
		var s0 := float(w["s0"])
		var s1 := float(w["s1"])
		var y0 := float(w["y0"])
		var y1 := float(w["y1"])
		var f := float(w["fixed"])
		var c := Vector3((s0 + s1) / 2.0, (y0 + y1) / 2.0, f + inside * 0.07) if along_x else Vector3(f + inside * 0.07, (y0 + y1) / 2.0, (s0 + s1) / 2.0)
		var room := Layout.room_at(c + (Vector3(0, 0, inside * 0.4) if along_x else Vector3(inside * 0.4, 0, 0)))
		if room == "":
			continue
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(s1 - s0, y1 - y0)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.62, 0.3, 0.0)
		m.albedo_texture = FX.tex("smoke")
		m.uv1_scale = Vector3(0.8, 0.8, 1)
		m.uv1_offset = Vector3(0.1, 0.1, 0)
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.disable_fog = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = c
		# the quad faces +Z by default: turn it to face outside
		var out := Vector3(0, 0, -inside) if along_x else Vector3(-inside, 0, 0)
		mi.basis = Basis.looking_at(-out, Vector3.UP)
		add_child(mi)
		_glows.append([mi, m, room])


func _update_window_glows() -> void:
	var lv := {}
	for l: LightSystem.RoomLight in lights.lights:
		var r := l.room()
		if r == "":
			continue
		lv[r] = maxf(lv.get(r, 0.0), l.level * l.scale * (0.6 if l.def["fixture"] == "lamp" else 1.0))
	for g in _glows:
		var k: float = lv.get(g[2], 0.0)
		(g[1] as StandardMaterial3D).albedo_color.a = minf(1.0, 1.1 * k)
		(g[0] as MeshInstance3D).visible = k > 0.01


func _build_dust() -> void:
	for r in Layout.rooms():
		if r["id"] == "varanda":
			continue
		var p := FX.dust_motes(Vector3(r["x1"] - r["x0"], r["h"], r["z1"] - r["z0"]), int((r["x1"] - r["x0"]) * (r["z1"] - r["z0"]) * 3))
		p.position = Vector3((r["x0"] + r["x1"]) / 2, r["y"] + r["h"] / 2, (r["z0"] + r["z1"]) / 2)
		add_child(p)


# ---------------------------------------------------------------------- physics queries


func ground_height(x: float, z: float, from_y: float, _r := 0.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 30.0, z), HouseBuilder.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit else -1000.0


func ceiling_height(x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y + 10.0, z), HouseBuilder.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit else 1000.0


func blocked(a: Vector3, b: Vector3, mask := HouseBuilder.LAYER_CAMERA) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	return not space.intersect_ray(q).is_empty()


var _clear_shape := SphereShape3D.new()
var _clear_q := PhysicsShapeQueryParameters3D.new()


## true when a sphere of radius r can travel straight from a to b without touching the solid world
## (walls, furniture, beds, closed doors: LAYER_WORLD, not the camera-only shapes). For anything
## that wants to go in a straight line (a charge, a thrown ball, a chase): if false, use the route.
## Pass points at the height of the body's centre (e.g. a floor point + Vector3.UP * 0.5).
func clear_path(a: Vector3, b: Vector3, r := 0.2, mask := HouseBuilder.LAYER_WORLD, exclude: Array[RID] = []) -> bool:
	_clear_shape.radius = r
	_clear_q.shape = _clear_shape
	_clear_q.transform = Transform3D(Basis.IDENTITY, a)
	_clear_q.motion = b - a
	_clear_q.collision_mask = mask
	_clear_q.exclude = exclude
	if not space.intersect_shape(_clear_q, 1).is_empty():
		# starting inside something (a doorway corner, a rug edge): it only counts if the way out is blocked too
		_clear_q.transform = Transform3D(Basis.IDENTITY, a + (b - a).normalized() * minf(r, a.distance_to(b)))
		_clear_q.motion = b - _clear_q.transform.origin
	var frac := space.cast_motion(_clear_q)
	return frac.size() == 2 and frac[0] >= 1.0


var _occ_shape := BoxShape3D.new()
var _occ_q := PhysicsShapeQueryParameters3D.new()


func occupied(x: float, z: float, y0: float, y1: float, r: float) -> bool:
	_occ_shape.size = Vector3(r * 2, maxf(0.01, y1 - y0), r * 2)
	_occ_q.shape = _occ_shape
	_occ_q.transform = Transform3D(Basis.IDENTITY, Vector3(x, (y0 + y1) / 2, z))
	_occ_q.collision_mask = HouseBuilder.LAYER_WORLD
	return not space.intersect_shape(_occ_q, 1).is_empty()


# ---------------------------------------------------------------------- update


func update(dt: float, day: int, phase: String) -> void:
	_t += dt
	for d: Door in doors.values():
		d.update(dt)
	lights.update(dt)
	_update_window_glows()
	props.update(dt)
	hatch_open = lerpf(hatch_open, hatch_target, 1.0 - exp(-4.0 * dt))
	# the leaf swings up and lies flat on the attic floor, the stair comes down when it is open
	if _hatch_w:
		_hatch_w.transform.basis = Basis(Vector3.BACK, hatch_open * PI) * _hatch_w_rest
		_hatch_w.position = _hatch_w_pos + Vector3(0, hatch_open * 0.2, 0)
	if _hatch_e:
		_hatch_e.transform.basis = Basis(Vector3.BACK, -hatch_open * 2.95) * _hatch_e_rest
		_hatch_e.position = _hatch_e_pos + Vector3(0, hatch_open * 0.23, 0)
	if _ladder and _ladder.visible != (hatch_open > 0.6):
		_ladder.visible = hatch_open > 0.6
		_set_ladder_cols(_ladder.visible)
	duct_open = lerpf(duct_open, duct_target, 1.0 - exp(-5.0 * dt))
	for dn in _ducts:
		(dn[0] as Node3D).transform.basis = Basis(Vector3.RIGHT, duct_open * 1.3) * (dn[1] as Basis)
	basculante_open = lerpf(basculante_open, basculante_target, 1.0 - exp(-4.0 * dt))
	if _basculante:
		_basculante.transform.basis = Basis(Vector3.RIGHT, -basculante_open * 0.9) * _bas_rest
	_bas_col.disabled = basculante_open >= 0.5
	chest_open = lerpf(chest_open, chest_target, 1.0 - exp(-3.0 * dt))
	if _chest_pivot:
		_chest_pivot.rotation.x = 0.0
		_chest_pivot.transform.basis = Basis(Vector3.UP, _chest_pivot.rotation.y) * Basis(Vector3.RIGHT, -chest_open * 1.15)
	# faucets
	for f: Faucet in faucets:
		f.stream.visible = f.running > 0.05
		var surf := f.bottom_y + (f.top_y - f.bottom_y) * f.level
		if f.stream.visible:
			var fall := maxf(0.02, f.spout.y - maxf(f.bottom_y, surf))
			f.stream.scale = Vector3(0.6 + f.running * 0.8, fall, 0.6 + f.running * 0.8)
			f.stream.global_position = f.spout - Vector3(0, fall / 2, 0)
			f.splash.global_position = Vector3(f.spout.x, maxf(f.bottom_y, surf) + 0.01, f.spout.z)
		f.splash.emitting = f.running > 0.2
		f.water.visible = f.level > 0.02
		f.water.position.y = surf
		var pr := f.puddle * 1.4
		f.puddle_mesh.scale = Vector3.ONE * maxf(0.001, pr / 2.0 * 2.0)
		f.puddle_mesh.visible = f.puddle > 0.01
	# devices: static on screens; the night light flickers when the Whisperer is in it, dark if unplugged
	for dv: Device in devices:
		if dv.screen_mat:
			dv.screen_mat.set_shader_parameter("glow", dv.glow)
		if dv.id == "nightlight" and nightlight_glow:
			nightlight_glow.light_energy = (0.0 if not dv.plugged else 0.9 * (1.0 - 0.7 * dv.glow * randf()) + dv.glow * 0.8)
	# marks: faint, in the morning of their day
	for mk: Mark in marks:
		var active := phase == "morning" and mk.day == day
		var target := 0.6 if active else 0.0
		mk.alpha = lerpf(mk.alpha, target * (0.8 + 0.2 * sin(_t * 3.0 + mk.pos.x)), 1.0 - exp(-8.0 * dt))
		mk.decal.visible = mk.alpha > 0.01
		mk.decal.modulate.a = mk.alpha
	# ritual circle: the chalk is always on the floor, the objects only make it glow
	var gl := clampf(ritual_glow, 0, 1)
	var hot := clampf(ritual_glow - 1.0, 0, 1)
	ritual_decal.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.42, 0.3), hot)
	ritual_decal.modulate.a = lerpf(RITUAL_CHALK, 1.0, gl)
	ritual_decal.emission_energy = gl * (0.4 + hot * 3.0)
	# sheets on the clothesline sway
	for i in _sheets.size():
		var sh: Array = _sheets[i]
		(sh[0] as Node3D).transform = (sh[1] as Transform3D) * Transform3D(Basis(Vector3.RIGHT, sin(_t * 0.8 + i) * 0.05), Vector3.ZERO)
	# rocking chair keeps rocking once pushed
	if _rocking:
		_rock_v += -_rock * 6.0 * dt - _rock_v * 0.6 * dt
		_rock += _rock_v * dt
		_rocking.rotation.z = 0.0
		_rocking.rotation.x = _rock * 0.18
	# grandfather clock hands follow the night's hour (set by the game) or the real time
	for h in _clock_hands:
		var mi: Node3D = h[0]
		var hour := clock_hour
		var a := -(hour / 12.0) * TAU if h[2] else -fmod(hour, 1.0) * TAU
		mi.transform = (h[1] as Transform3D) * Transform3D(Basis(Vector3.FORWARD, a), Vector3.ZERO)


var clock_hour := 0.0


# ---------------------------------------------------------------------- food in the bowl

const KIBBLE_N := 90
var _kibble: Array[MultiMeshInstance3D] = []


## the smooth food mound of the kit becomes a heap of kibble (round bits and little fish), lowest
## first, so showing fewer of them eats the heap from the top
func _build_kibble() -> void:
	for mi in bowl_food.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false
	if bowl_food is MeshInstance3D:
		(bowl_food as MeshInstance3D).mesh = null
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pts := []
	for i in KIBBLE_N:
		var r := 0.066 * sqrt(rng.randf())
		var a := rng.randf() * TAU
		# a low dome over the bottom of the bowl (bottom at 0.012, wall flares out above it)
		var top := 0.016 + 0.03 * (1.0 - pow(r / 0.07, 2.0))
		var y := 0.016 + rng.randf() * (top - 0.016)
		pts.append([y, Vector3(cos(a) * r, y, sin(a) * r)])
	pts.sort_custom(func(p, q): return p[0] < q[0])
	var round_m := SphereMesh.new()
	round_m.radius = 0.0075
	round_m.height = 0.009
	round_m.radial_segments = 8
	round_m.rings = 4
	var fish_m := PrismMesh.new()
	fish_m.size = Vector3(0.016, 0.011, 0.006)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	var cols := [Color("#8a4f26"), Color("#a5642f"), Color("#6e3a1c"), Color("#b97a3c")]
	for kind in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = round_m if kind == 0 else fish_m
		var mine := []
		for i in pts.size():
			if (i % 3 == 0) == (kind == 1):
				mine.append(pts[i][1])
		mm.instance_count = mine.size()
		for i in mine.size():
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			if kind == 0:
				b = b.scaled(Vector3(1.0, 0.75, 1.0))
			mm.set_instance_transform(i, Transform3D(b, mine[i]))
			mm.set_instance_color(i, cols[rng.randi() % cols.size()])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bowl_food.add_child(mmi)
		_kibble.append(mmi)
	set_food(0.0)


## how full the bowl is (0 empty, 1 full; a little left over shows crumbs)
func set_food(amount: float) -> void:
	if bowl_food == null:
		return
	bowl_food.visible = amount > 0.0
	for mmi in _kibble:
		var mm := mmi.multimesh
		mm.visible_instance_count = clampi(roundi(mm.instance_count * amount), 0, mm.instance_count)

