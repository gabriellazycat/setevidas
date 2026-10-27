extends SceneTree
## Dev: renders the Shadow's peeking head alone, identity frame (face should be +Z), from +Z and
## from the side, to check which way the face points.
##   godot --path godot --script res://scripts/dev/peek_probe.gd -- --out=DIR [--body=shadow|ivone|visitor]

var _f := 0
var _pk: ShadowPeek
var _body: GhostBody        # --body=ID: a walking ghost body instead (its head, from the front)
var _c := Vector3.ZERO
var _cam: Camera3D
var _out := "user://peek_probe"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 1.0
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.3, 0)
	root3d.add_child(sun)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--body="):
			_body = GhostBody.new(a.substr(7))
	if _body:
		root3d.add_child(_body)
	else:
		_pk = ShadowPeek.new()
		root3d.add_child(_pk)
	_cam = Camera3D.new()
	_cam.fov = 30
	root3d.add_child(_cam)
	_cam.current = true


func _process(_dt: float) -> bool:
	_f += 1
	var c := Vector3(0, 0.08, 0)
	if _body:
		_body.alpha = 1.0
		_body.tick(0.016)
		c = _body.rig.bone_world("head").origin + Vector3(0, 0.08, 0) if _f > 3 else c
	else:
		if _f == 2:
			_pk.alpha = 1.0
			_pk.heat = 0.6
			_pk.place(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), [Transform3D(Basis.IDENTITY, Vector3(0.3, -0.2, 0)), Transform3D(Basis.IDENTITY, Vector3(-0.3, -0.2, 0))])
		_pk.tick(0.016)
	if _f == 4:
		_c = c
		_cam.look_at_from_position(_c + Vector3(0, 0, 1.0), _c)
	if _f == 4 + 6:
		_save("front")
		_cam.look_at_from_position(_c + Vector3(1.0, 0, 0), _c)
	if _f == 4 + 12:
		_save("side_x")
		return true
	return false


func _save(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(nm + ".png"))
	print("PROBE ", nm)
