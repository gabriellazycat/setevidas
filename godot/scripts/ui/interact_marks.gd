class_name InteractMarks
extends RefCounted
## With no Cat Vision, what the cat can use has to show by itself: everything usable close by (and
## in plain sight) gets a faint cream outline (interact_outline.gdshader), the one the button is for a
## stronger one, and the button sits on the screen over it (UI.prompt_at). Ivone's things show from
## further away, so they can be found in the dark.

const OUTLINE := preload("res://shaders/interact_outline.gdshader")
const NEAR := 2.6          # metres from the cat
const RELIC_NEAR := 6.0
const FAINT := 0.35
const STRONG := 0.85

var g: Game
var _meshes := {}         # Interactable -> Array[MeshInstance3D]
var _k := {}              # Interactable -> current strength
var _mats := {}           # Interactable -> ShaderMaterial
var _small: Array = []    # [center, MeshInstance3D] of the house's small meshes (switch plates, handles)
var hidden := false       # trailer capture (--nohud): no outlines, no button


func _init(game: Game) -> void:
	g = game
	for mi in g.house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var ab: AABB = m.global_transform * m.mesh.get_aabb()
		if ab.get_longest_axis_size() < 0.5:
			_small.append([ab.get_center(), m])


## the small house meshes around a point (a switch plate, a faucet handle)
func near_meshes(p: Vector3, r: float) -> Array:
	var out := []
	for e in _small:
		if (e[0] as Vector3).distance_to(p) < r:
			out.append(e[1])
	return out


func _meshes_of(it: Interactions.Interactable) -> Array:
	if _meshes.has(it):
		return _meshes[it]
	var out := []
	if it.outline.is_valid():
		for n in it.outline.call():
			if n is MeshInstance3D:
				out.append(n)
			if n is Node3D:
				for c in (n as Node3D).find_children("*", "MeshInstance3D", true, false):
					out.append(c)
	_meshes[it] = out
	return out


func tick(dt: float, best: Interactions.Interactable) -> void:
	var cam := g.cam
	var cp := g.cat.global_position
	var want := {}
	if cam and g.controls and g.mode == "play" and not hidden:
		for it: Interactions.Interactable in g.inter.list:
			if not it.outline.is_valid() or not it.enabled.call():
				continue
			var p := it.p()
			var reach := RELIC_NEAR if it.id.begins_with("pick_relic") else NEAR
			if p.distance_to(cp) > reach or not cam.is_position_in_frustum(p):
				continue
			if it != best and g.house.blocked(cam.global_position, p + Vector3(0, 0.05, 0)):
				continue
			want[it] = STRONG if it == best else FAINT
	for it in want.keys() + _k.keys():
		var to: float = want.get(it, 0.0)
		var k: float = move_toward(_k.get(it, 0.0), to, dt / 0.2)
		_apply(it, k, it == best)
		if k <= 0.0:
			_k.erase(it)
		else:
			_k[it] = k
	g.ui.prompt_at(_screen_pos(best) if best else null)


func _apply(it: Interactions.Interactable, k: float, strong: bool) -> void:
	var meshes := _meshes_of(it)
	if meshes.is_empty():
		return
	if k <= 0.0:
		for m: MeshInstance3D in meshes:
			if is_instance_valid(m) and m.material_overlay == _mats.get(it):
				m.material_overlay = null
		return
	var mat: ShaderMaterial = _mats.get(it)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = OUTLINE
		_mats[it] = mat
	mat.set_shader_parameter("alpha", k)
	mat.set_shader_parameter("width_px", 2.8 if strong else 1.7)
	for m: MeshInstance3D in meshes:
		if is_instance_valid(m) and m.material_overlay != mat:
			m.material_overlay = mat


## where the button goes: just above the thing on the screen (null when it is behind the camera)
func _screen_pos(it: Interactions.Interactable):
	var cam := g.cam
	var p := it.p() + Vector3(0, 0.25, 0)
	if cam == null or cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)
