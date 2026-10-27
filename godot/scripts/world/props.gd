class_name PropSystem
extends Node3D
## Knock-off-able things on tables and shelves (real rigid bodies): the cat bumps or swats them,
## they fall, fragile ones shatter into shards. Every impact is a noise the house (and the ghosts
## that hunt by ear) can hear. Also the carryables the cat picks up in its mouth (and the padlock key
## of the first afternoon, made here: see make_key).

signal noise(pos, loudness, kind)

const KINDS := {
	"cup": {"model": "tea_set_01", "parts": ["tea_set_01_cup_small_01"], "h": 0.08, "fragile": true, "r": 0.05},
	"glass": {"proc": "glass", "h": 0.11, "fragile": true, "r": 0.04},
	"vase": {"model": "ceramic_vase_02", "parts": [], "h": 0.26, "fragile": true, "r": 0.08},
	"bottle": {"model": "wine_bottles_01", "parts": ["wine_bottles_01_bordeaux"], "h": 0.24, "fragile": true, "r": 0.04},
	"book": {"model": "book_encyclopedia_set_01", "parts": ["book_encyclopedia_set_01_book01"], "h": 0.2, "fragile": false, "r": 0.09, "lay": true},
	"frame": {"model": "standing_picture_frame_01", "parts": [], "h": 0.2, "fragile": true, "r": 0.07},
	"pot": {"model": "potted_plant_02", "parts": [], "h": 0.28, "fragile": true, "r": 0.07},
}

# the web version's props.add(...) calls: kind, x, y, z, yaw
const PLACES := [
	["cup", 2.35, 0.43, 3.0, 0.0], ["book", 2.85, 0.43, 3.15, 0.4], ["vase", 3.05, 0.55, 5.2, 0.0], ["frame", 1.85, 0.55, 5.25, 0.0],
	["cup", 3.0, 0.71, 9.55, 0.0], ["book", 1.75, 0.71, 9.6, 0.2], ["pot", 0.32, 0.6, 7.75, 0.0],
	["vase", 7.2, 0.7, 3.15, 0.0],
	["glass", 10.5, 0.9, 5.6, 0.0], ["cup", 10.0, 0.9, 9.5, 0.0], ["bottle", 11.6, 0.9, 4.5, 0.0], ["pot", 7.9, 0.9, 9.6, 0.0],
	["bottle", 7.8, 0.9, 2.8, 0.0],
	["glass", 0.3, 3.62, 3.9, 0.0], ["bottle", 2.5, 4.0, 5.2, 0.0], ["bottle", 2.66, 4.0, 5.25, 0.0], ["frame", 3.15, 4.0, 5.25, 0.0],
	["pot", 2.6, 4.16, 6.2, 0.0],
	["vase", 7.25, 3.63, 7.2, 0.0], ["frame", 7.25, 3.63, 6.75, 0.0],
	["bottle", 10.2, 3.9, 6.3, 0.0], ["glass", 10.6, 3.9, 6.3, 0.0],
]

class Prop:
	var kind: String
	var body: RigidBody3D
	var home: Transform3D
	var fragile := true
	var broken := false
	var r := 0.05
	var cooldown := 0.0

var props: Array = []
var shards: GPUParticles3D
var _floor_col: GPUParticlesCollisionBox3D
var _visual_cache := {}
var last_broken := ""  # kind of the last prop that shattered (the "break" noise picks its sound by it)


func build() -> void:
	for p in PLACES:
		add_prop(p[0], Vector3(p[1], p[2], p[3]), p[4])
	shards = _make_shards()
	add_child(shards)


static func make_visual(kind: String) -> Node3D:
	var k: Dictionary = KINDS[kind]
	if k.has("proc"):
		return _proc_glass()
	return HouseBuilder.instance_parts(k["model"], k["parts"], k["h"], k.get("lay", false))


static func _proc_glass() -> Node3D:
	var n := Node3D.new()
	var g := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.034
	cm.bottom_radius = 0.029
	cm.height = 0.11
	cm.radial_segments = 20
	g.mesh = cm
	g.position.y = 0.055
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.85, 0.92, 0.95, 0.22)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.03
	gm.metallic_specular = 0.9
	g.material_override = gm
	n.add_child(g)
	var w := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.03
	wm.bottom_radius = 0.027
	wm.height = 0.06
	w.mesh = wm
	w.position.y = 0.033
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.6, 0.72, 0.78, 0.45)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.02
	w.material_override = wmat
	n.add_child(w)
	return n


func add_prop(kind: String, pos: Vector3, yaw := 0.0) -> Prop:
	var k: Dictionary = KINDS[kind]
	var p := Prop.new()
	p.kind = kind
	p.fragile = k["fragile"]
	p.r = k["r"]
	var b := RigidBody3D.new()
	b.collision_layer = 8  # props layer
	b.collision_mask = HouseBuilder.LAYER_WORLD | 8
	b.mass = 0.35 if kind != "book" else 0.6
	b.contact_monitor = true
	b.max_contacts_reported = 4
	b.continuous_cd = true
	b.can_sleep = true
	b.physics_material_override = PhysicsMaterial.new()
	b.physics_material_override.friction = 0.7
	b.physics_material_override.bounce = 0.15
	var vis := make_visual(kind)
	b.add_child(vis)
	var cs := CollisionShape3D.new()
	var h: float = k["h"]
	if k.get("lay", false):
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.16, 0.035, 0.22)
		cs.shape = bx
		cs.position.y = 0.0175
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = p.r * 0.75
		cyl.height = h
		cs.shape = cyl
		cs.position.y = h / 2
	b.add_child(cs)
	b.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.002, 0))
	p.home = b.transform
	p.body = b
	add_child(b)
	b.freeze = true  # asleep until the cat touches it (stable stacks on shelves)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.body_entered.connect(_on_hit.bind(p))
	props.append(p)
	return p


func reset_all() -> void:
	for p: Prop in props:
		p.broken = false
		p.body.visible = true
		p.body.freeze = true
		p.body.linear_velocity = Vector3.ZERO
		p.body.angular_velocity = Vector3.ZERO
		p.body.transform = p.home
		p.body.process_mode = Node.PROCESS_MODE_INHERIT
		p.cooldown = 0.0
	shards.restart()
	shards.emitting = false


func wake(p: Prop) -> void:
	if p.body.freeze:
		p.body.freeze = false
		p.body.sleeping = false


## the cat bumps into props while walking (called with its horizontal velocity)
func interact_cat(cat_pos: Vector3, cat_vel: Vector3, cat_r := 0.14) -> void:
	for p: Prop in props:
		if p.broken:
			continue
		var pp := p.body.global_position
		var dy := pp.y - cat_pos.y
		if dy < -0.12 or dy > 0.22:
			continue
		var d := Vector2(pp.x - cat_pos.x, pp.z - cat_pos.z)
		var dist := d.length()
		if dist < p.r + cat_r and dist > 1e-4:
			wake(p)
			var n := d / dist
			var sp := maxf(0.6, Vector2(cat_vel.x, cat_vel.z).length() * 0.9)
			p.body.apply_central_impulse(Vector3(n.x, 0.05, n.y) * sp * p.body.mass * 0.6)


func near_swattable(cat_pos: Vector3) -> Prop:
	for p: Prop in props:
		if p.broken:
			continue
		var pp := p.body.global_position
		var dy := pp.y - cat_pos.y
		if dy < -0.15 or dy > 0.55:
			continue
		if Vector2(pp.x - cat_pos.x, pp.z - cat_pos.z).length() < 0.55:
			return p
	return null


func swat(cat_pos: Vector3, forward: Vector3) -> Prop:
	var p := near_swattable(cat_pos)
	if p == null:
		return null
	knock(p, cat_pos, forward)
	return p


## knocks p off: pushed away from `from` (the cat or its paw), level and a bit up; forward adds the swing
func knock(p: Prop, from: Vector3, forward := Vector3.ZERO) -> void:
	if p == null or p.broken:
		return
	wake(p)
	var pp := p.body.global_position
	var d := Vector3(pp.x - from.x, 0, pp.z - from.z)
	var fw := Vector3(forward.x, 0, forward.z)
	d = d.normalized() if d.length() > 0.01 else fw.normalized()
	if fw.length() < 0.01:
		fw = d
	var imp := (d * 1.6 + fw.normalized() * 0.6 + Vector3.UP * 0.7) * p.body.mass
	p.body.apply_impulse(imp, Vector3(0, 0.05, 0))
	p.body.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.02)


func _on_hit(other: Node, p: Prop) -> void:
	if p.broken or p.cooldown > 0:
		return
	var v := p.body.linear_velocity.length()
	if v < 1.0:
		return
	p.cooldown = 0.25
	if p.fragile and v > 2.4:
		_break(p)
		noise.emit(p.body.global_position, 1.0, "break")
	else:
		noise.emit(p.body.global_position, minf(0.7, v / 5.0), "thud")


func _break(p: Prop) -> void:
	p.broken = true
	last_broken = p.kind
	p.body.visible = false
	p.body.freeze = true
	p.body.process_mode = Node.PROCESS_MODE_DISABLED
	var bp := p.body.global_position
	shards.global_position = bp + Vector3(0, 0.03, 0)
	var q := PhysicsRayQueryParameters3D.create(bp + Vector3(0, 0.1, 0), bp + Vector3(0, -6, 0), HouseBuilder.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var gy: float = hit["position"].y if hit else bp.y - 1.0
	_floor_col.global_position = Vector3(bp.x, gy - 0.5, bp.z)
	var col := Color(0.85, 0.85, 0.82)
	if p.kind == "glass" or p.kind == "bottle":
		col = Color(0.7, 0.85, 0.8)
	elif p.kind == "pot":
		col = Color(0.6, 0.3, 0.2)
	(shards.process_material as ParticleProcessMaterial).color = col
	shards.restart()
	shards.emitting = true


func _make_shards() -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = 26
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.lifetime = 40.0
	ps.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_friction = 0.8
	pm.collision_bounce = 0.15
	pm.angular_velocity_min = -400
	pm.angular_velocity_max = 400
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	ps.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.004, 0.018)
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	mm.roughness = 0.15
	mm.metallic_specular = 0.8
	mesh.material = mm
	ps.draw_pass_1 = mesh
	ps.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	_floor_col = GPUParticlesCollisionBox3D.new()
	_floor_col.size = Vector3(4, 1, 4)
	add_child(_floor_col)
	return ps


func update(dt: float) -> void:
	for p: Prop in props:
		p.cooldown = maxf(0.0, p.cooldown - dt)


class Carryable:
	var id: String
	var name: String
	var node: Node3D
	var pos := Vector3.ZERO
	var yaw := 0.0
	var carried := false
	var enabled := true

	func place(p: Vector3, y = null) -> void:
		pos = p
		if y != null:
			yaw = y
		node.global_position = p
		node.rotation = Vector3(0, yaw, 0)


## a loose carryable the game adds itself (the house builds the others): its node goes under parent
static func add_carryable(carry: Dictionary, parent: Node, id: String, nm: String, node: Node3D, at: Vector3) -> Carryable:
	var c := Carryable.new()
	c.id = id
	c.name = nm
	c.node = node
	parent.add_child(node)
	c.place(at)
	carry[id] = c
	return c


## day 1: the padlock key Clara left on the moving box. Steel, a ring and a red paper tag, so it reads
## on top of the cardboard
static func make_key() -> Node3D:
	var n := Node3D.new()
	n.name = "CARRY_porao_key"
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.7, 0.66)
	steel.metallic = 0.85
	steel.roughness = 0.35
	var tag_m := StandardMaterial3D.new()
	tag_m.albedo_color = Color(0.72, 0.16, 0.12)
	tag_m.roughness = 0.8
	var parts := []
	var ring := TorusMesh.new()
	ring.inner_radius = 0.011
	ring.outer_radius = 0.015
	ring.rings = 16
	ring.ring_segments = 6
	parts.append([ring, steel, Vector3(-0.05, 0.003, 0), Vector3.ZERO])
	var head := CylinderMesh.new()
	head.top_radius = 0.016
	head.bottom_radius = 0.016
	head.height = 0.005
	parts.append([head, steel, Vector3(-0.026, 0.003, 0), Vector3.ZERO])
	var blade := BoxMesh.new()
	blade.size = Vector3(0.045, 0.004, 0.008)
	parts.append([blade, steel, Vector3(0.008, 0.003, 0), Vector3.ZERO])
	for k in 3:
		var tooth := BoxMesh.new()
		tooth.size = Vector3(0.006, 0.004, 0.006)
		parts.append([tooth, steel, Vector3(0.012 + k * 0.009, 0.003, 0.006 + (k % 2) * 0.002), Vector3.ZERO])
	var tag := BoxMesh.new()
	tag.size = Vector3(0.04, 0.002, 0.026)
	# under the head and blade, peeking out at the side (not past the ring: the cat carries it by the ring)
	parts.append([tag, tag_m, Vector3(-0.012, 0.001, 0.007), Vector3(0, 0.25, 0)])
	for pr in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = pr[0]
		mi.material_override = pr[1]
		mi.position = pr[2]
		mi.rotation = pr[3]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		n.add_child(mi)
	return n
