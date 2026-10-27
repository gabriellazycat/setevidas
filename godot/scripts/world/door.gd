class_name Door
extends RefCounted
## A hinged door leaf (built in Blender with its origin on the hinge). closed / ajar / open, can be
## locked (the cat gets shut in the bathroom). Blocks the cat and the camera only while closed.

signal moved(door, opening)

const ANGLES := {"closed": 0.0, "ajar": 0.55, "open": 1.62}
## Interior doors open all the way, leaf flat against the wall beside the doorway (out of the cat's path).
const FLAT_OPEN := 2.95
const WALL_OFFSET := 0.125   # hinge shift off the wall's centre line, so the open leaf lies against the wall face, not inside it

var def: Dictionary
var id: String
var leaf: Node3D
var yaw0 := 0.0
var angle := 0.0
var target := 0.0
var state := "closed"
var locked := false
var body: StaticBody3D
var shape: CollisionShape3D
var _dir_s := 1.0
var _flat := false
var _open_angle := FLAT_OPEN
var _pos0 := Vector3.ZERO
var _slide := Vector3.ZERO   # hinge shift along the wall (into the opening) for doors hinged right at a corner
var _n := Vector3.ZERO       # which way the leaf swings out of the wall plane
var _was_moving := false


func _init(d: Dictionary, leaf_node: Node3D, parent: Node3D) -> void:
	def = d
	id = d["id"]
	leaf = leaf_node
	if leaf:
		leaf = _hinge_pivot(leaf)
		yaw0 = leaf.rotation.y
		_pos0 = leaf.position
	_dir_s = 1.0 if int(d["hinge"]) == 0 else -1.0
	state = d["state"]
	_flat = d["style"] != "front"
	if _flat and leaf:
		_plan_open()
	body = StaticBody3D.new()
	body.collision_layer = HouseBuilder.LAYER_WORLD | HouseBuilder.LAYER_CAMERA
	body.collision_mask = 0
	shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	var y0 := float(d["y"])
	var h := float(d["h"])
	if d["axis"] == "z":
		box.size = Vector3(0.14, h, float(d["s1"]) - float(d["s0"]))
		shape.position = Vector3(float(d["fixed"]), y0 + h / 2, (float(d["s0"]) + float(d["s1"])) / 2)
	else:
		box.size = Vector3(float(d["s1"]) - float(d["s0"]), h, 0.14)
		shape.position = Vector3((float(d["s0"]) + float(d["s1"])) / 2, y0 + h / 2, float(d["fixed"]))
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	angle = _angle_for(state)
	target = angle
	_apply()


## The exported leaf mesh is centred on its node origin (hinge edge at -width/2, bottom at -height/2), so
## swinging the node swung the door about its middle and sank it into the floor. Wrap it in a pivot that sits
## on the hinge at floor level and shift the mesh so its hinge edge / bottom land on the pivot.
func _hinge_pivot(node: Node3D) -> Node3D:
	var mi := node as MeshInstance3D
	var par := node.get_parent()
	if mi == null or par == null:
		return node
	var bb := mi.get_aabb()
	var pv := Node3D.new()
	pv.name = node.name + "_hinge"
	pv.position = node.position
	pv.rotation = node.rotation
	par.add_child(pv)
	par.remove_child(node)
	pv.add_child(node)
	node.position = Vector3(-bb.position.x - 0.012, -bb.position.y, 0.0)
	node.rotation = Vector3.ZERO
	return pv


## How far this door can swing: flat against the wall when the wall beside the opening is long enough for the
## leaf, otherwise only as far as the corner allows (never through the perpendicular wall).
func _plan_open() -> void:
	var swing := float(def["swing"])
	var phi90 := swing * _dir_s * 1.62 if def["axis"] == "z" else -swing * _dir_s * 1.62
	var th := yaw0 + phi90
	var dir := Vector3(cos(th), 0.0, -sin(th))
	_n = Vector3(signf(dir.x), 0, 0) if def["axis"] == "z" else Vector3(0, 0, signf(dir.z))
	var s0 := float(def["s0"])
	var s1 := float(def["s1"])
	var width := s1 - s0 - 0.03
	var avail := 99.0
	for w in Layout.data()["WALLS"]:
		if w["axis"] == def["axis"] and absf(float(w["fixed"]) - float(def["fixed"])) < 0.01 and absf(float(w["y"]) - float(def["y"])) < 0.35 				and float(w["a"]) <= s0 + 0.01 and float(w["b"]) >= s1 - 0.01:
			avail = (s0 - float(w["a"])) if int(def["hinge"]) == 0 else (float(w["b"]) - s1)
			avail -= 0.1   # half the thickness of the wall at the corner
			break
	if avail < 0.1:
		var slide := clampf(0.1 - avail, 0.0, 0.12)
		var sdir := 1.0 if int(def["hinge"]) == 0 else -1.0
		_slide = (Vector3(0, 0, sdir) if def["axis"] == "z" else Vector3(sdir, 0, 0)) * slide
		avail += slide
	if avail >= width + 0.04:
		_open_angle = FLAT_OPEN
	else:
		_open_angle = clampf(acos(clampf(-avail / width, -1.0, 1.0)), 1.2, FLAT_OPEN)


## Every interior door that is not closed (ajar included) swings fully open; only the front door keeps its own angles.
func _angle_for(s: String) -> float:
	if _flat and s != "closed":
		return _open_angle
	return ANGLES[s]


func _apply() -> void:
	var swing := float(def["swing"])
	var phi := swing * _dir_s * angle if def["axis"] == "z" else -swing * _dir_s * angle
	if leaf:
		leaf.rotation.y = yaw0 + phi
		if _flat:
			var k := clampf(angle / 1.62, 0.0, 1.0)
			leaf.position = _pos0 + _n * WALL_OFFSET * k + _slide * k
	shape.disabled = angle >= 0.22


func set_state(s: String, instant := false) -> void:
	if locked and s != "closed":
		return
	state = s
	target = _angle_for(s)
	if instant:
		angle = target
		_apply()


var is_closed: bool:
	get:
		return angle < 0.22


func center() -> Vector3:
	var m := (float(def["s0"]) + float(def["s1"])) / 2
	if def["axis"] == "z":
		return Vector3(float(def["fixed"]), float(def["y"]), m)
	return Vector3(m, float(def["y"]), float(def["fixed"]))


func side_point(side: float, dist := 0.5) -> Vector3:
	var c := center()
	if def["axis"] == "z":
		c.x += side * dist
	else:
		c.z += side * dist
	return c


func update(dt: float) -> void:
	var prev := angle
	angle = lerpf(angle, target, 1.0 - exp(-5.0 * dt))
	var moving := absf(angle - prev) > 0.0015
	if moving and not _was_moving:
		moved.emit(self, target > prev)
	_was_moving = moving
	_apply()
