extends SceneTree
## godot --headless --path godot -s res://scripts/dev/probe.gd -- <glb>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://assets/models/people/davi_night.glb" if args.is_empty() else args[0]
	var inst: Node = (load(path) as PackedScene).instantiate()
	for n in inst.find_children("*", "", true, false):
		if n is Node3D:
			print(n.name, " ", n.get_class(), " xf=", (n as Node3D).transform)
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	for b in ["pelvis", "spine_01", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "head"]:
		var i := skel.find_bone(b)
		print(b, " global_rest origin=", skel.get_bone_global_rest(i).origin, " basis_y=", skel.get_bone_global_rest(i).basis.y)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		print("mesh ", m.name, " blend=", m.mesh.get_blend_shape_count() if m.mesh is ArrayMesh else 0, " mat=", m.mesh.surface_get_material(0))
	quit()
