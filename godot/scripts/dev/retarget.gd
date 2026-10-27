extends SceneTree
## Retargets the Quaternius Universal Animation Library clips (CC0, tools/vendor/quaternius/) onto
## the game skeletons and saves one AnimationLibrary per model: res://assets/anims/<model>.res.
##
## Run: godot --headless --path godot --script res://scripts/dev/retarget.gd [-- --only=clara_day,...]
##
## Rotations are transferred as world-space deltas from a reference pose: each source bone is first
## aligned onto the target bone's rest direction (so the source is "posed" into our 42.5 degree A-pose),
## then target_world = source_world(frame) * offset, offset = source_ref^-1 * target_rest. The pelvis
## translation is the source's, scaled by the ratio of the hip heights. Tracks are written as the
## target's local bone poses (tracks ".:bone" for an AnimationPlayer rooted on the Skeleton3D).
## Done in Godot rather than Blender so the tracks match the skeleton rests exactly as imported.

const VENDOR := "../tools/vendor/quaternius/"
const PACKS := {
	"ual1": "ual1/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb",
	"ual2": "ual2/Universal Animation Library 2 [Standard]/Unreal-Godot/UAL2_Standard.glb",
}
# out name: [pack, source clip, loop]
const CLIPS := {
	"idle": ["ual1", "Idle_Loop", true],
	"talk": ["ual1", "Idle_Talking_Loop", true],
	"walk": ["ual1", "Walk_Loop", true],
	"walk_formal": ["ual1", "Walk_Formal_Loop", true],
	"jog": ["ual1", "Jog_Fwd_Loop", true],
	"sit_down": ["ual1", "Sitting_Enter", false],
	"stand_up": ["ual1", "Sitting_Exit", false],
	"sit_idle": ["ual1", "Sitting_Idle_Loop", true],
	"sit_talk": ["ual1", "Sitting_Talking_Loop", true],
	"crouch_idle": ["ual1", "Crouch_Idle_Loop", true],
	"crouch_walk": ["ual1", "Crouch_Fwd_Loop", true],
	"kneel_fix": ["ual1", "Fixing_Kneeling", false],
	"interact": ["ual1", "Interact", false],
	"pickup": ["ual1", "PickUp_Table", false],
	"hit": ["ual1", "Hit_Chest", false],
	"push": ["ual1", "Push_Loop", true],
	"fold_arms": ["ual2", "Idle_FoldArms_Loop", true],
	"phone": ["ual2", "Idle_TalkingPhone_Loop", true],
	"consume": ["ual2", "Consume", false],
	"chest_open": ["ual2", "Chest_Open", false],
	"carry_walk": ["ual2", "Walk_Carry_Loop", true],
	"no": ["ual2", "Idle_No_Loop", false],
	"yes": ["ual2", "Yes", false],
	"lay_to_idle": ["ual2", "LayToIdle", false],
	"zombie_walk": ["ual2", "Zombie_Walk_Fwd_Loop", true],
	"zombie_idle": ["ual2", "Zombie_Idle_Loop", true],
	"zombie_scratch": ["ual2", "Zombie_Scratch", false],
	"plant": ["ual2", "Farm_PlantSeed", false],
	"harvest": ["ual2", "Farm_Harvest", false],
	"knockback": ["ual2", "Hit_Knockback", false],
}
const MODELS := ["clara_day", "clara_night", "clara_bath", "davi_day", "davi_night", "shadow", "visitor"]
const FPS := 30.0

# game bone -> parent-to-child direction bone (for the reference alignment)
const DIR_CHILD := {
	"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head",
	"clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "hand_l": "middle_01_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "middle_01_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l", "thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r",
}


func _init() -> void:
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	var src := {}
	for pk in PACKS:
		src[pk] = _load_source(ProjectSettings.globalize_path("res://").path_join(VENDOR + PACKS[pk]), pk)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/anims"))
	for model in MODELS:
		if not only.is_empty() and not model in only:
			continue
		var ps: PackedScene = load("res://assets/models/people/%s.glb" % model)
		var inst: Node3D = ps.instantiate()
		var tsk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		var tgt := _skel_info(tsk, _model_xform(inst, tsk))
		var lib := AnimationLibrary.new()
		for out in CLIPS:
			var c: Array = CLIPS[out]
			var s: Dictionary = src[c[0]]
			var anim: Animation = s["anims"].get(c[1])
			if anim == null:
				push_warning("missing clip %s" % c[1])
				continue
			lib.add_animation(out, _retarget(s, tgt, anim, c[2]))
		for an in lib.get_animation_list():
			var a2 := lib.get_animation(an)
			print("  %-14s len=%.2f speed=%.2f pelvis0=%s pelvis1=%s" % [an, a2.length, a2.get_meta("speed"), a2.get_meta("pelvis_first"), a2.get_meta("pelvis_last")])
		var path := "res://assets/anims/%s.res" % model
		ResourceSaver.save(lib, path, ResourceSaver.FLAG_COMPRESS)
		print("RETARGET %s clips=%d -> %s" % [model, lib.get_animation_list().size(), path])
		inst.free()
	quit()


func _model_xform(root: Node, sk: Skeleton3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## the source pack: skeleton, clips and a source-bone -> game-bone map
func _load_source(path: String, pack: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("cannot read %s" % path)
		return {}
	var root: Node = doc.generate_scene(state)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var anims := {}
	for ln in ap.get_animation_library_list():
		var l := ap.get_animation_library(ln)
		for an in l.get_animation_list():
			anims[str(an)] = l.get_animation(an)
	var info := _skel_info(sk, _model_xform(root, sk))
	var gmap := {}   # source bone index -> game name
	for i in sk.get_bone_count():
		var g := _game_name(sk.get_bone_name(i))
		if g != "":
			gmap[i] = g
	info["gmap"] = gmap
	info["anims"] = anims
	info["ap_root"] = ap.get_node(ap.root_node)
	info["sk_node"] = sk
	print("SOURCE %s bones=%d mapped=%d clips=%d" % [pack, sk.get_bone_count(), gmap.size(), anims.size()])
	return info


static func _game_name(n: String) -> String:
	if n == "Head":
		return "head"
	if not n.begins_with("DEF-"):
		return n if n in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"] or n.ends_with("_l") or n.ends_with("_r") else ""
	var b := n.substr(4)
	var side := ""
	if b.ends_with(".L"):
		side = "_l"
	elif b.ends_with(".R"):
		side = "_r"
	b = b.trim_suffix(".L").trim_suffix(".R")
	var plain := {"hips": "pelvis", "spine.001": "spine_01", "spine.002": "spine_02", "spine.003": "spine_03", "neck": "neck_01", "head": "head",
		"shoulder": "clavicle", "upper_arm": "upperarm", "forearm": "lowerarm", "hand": "hand", "thigh": "thigh", "shin": "calf", "foot": "foot", "toe": "ball"}
	if plain.has(b):
		return plain[b] + side
	# fingers: f_index.01 -> index_01, thumb.01 -> thumb_01
	var f := b.trim_prefix("f_")
	var parts := f.split(".")
	if parts.size() == 2 and side != "":
		return "%s_%s%s" % [parts[0], parts[1], side]
	return ""


## rest globals in model space (rotation and position), by bone name
func _skel_info(sk: Skeleton3D, model: Transform3D) -> Dictionary:
	var rot := {}
	var pos := {}
	var idx := {}
	for i in sk.get_bone_count():
		var g := model * sk.get_bone_global_rest(i)
		rot[i] = g.basis.get_rotation_quaternion()
		pos[i] = g.origin
		idx[sk.get_bone_name(i)] = i
	return {"sk": sk, "model": model, "rot": rot, "pos": pos, "idx": idx}


func _retarget(s: Dictionary, t: Dictionary, anim: Animation, loop: bool) -> Animation:
	var ssk: Skeleton3D = s["sk"]
	var tsk: Skeleton3D = t["sk"]
	var gmap: Dictionary = s["gmap"]
	var g2s := {}
	for si in gmap:
		g2s[gmap[si]] = si
	# facing: both models must look the same way (+Z), else turn the source half around
	var face := Quaternion.IDENTITY
	if g2s.has("foot_l") and g2s.has("ball_l"):
		var sd: float = (s["pos"][g2s["ball_l"]] as Vector3).z - (s["pos"][g2s["foot_l"]] as Vector3).z
		var td: float = (t["pos"][t["idx"]["ball_l"]] as Vector3).z - (t["pos"][t["idx"]["foot_l"]] as Vector3).z
		if sd * td < 0.0:
			face = Quaternion(Vector3.UP, PI)
	# per mapped target bone: offset = source_ref^-1 * target_rest
	var offs := {}
	for g in g2s:
		if not t["idx"].has(g):
			continue
		var si: int = g2s[g]
		var ti: int = t["idx"][g]
		var s_rest: Quaternion = face * (s["rot"][si] as Quaternion)
		var align := Quaternion.IDENTITY
		var ch: String = DIR_CHILD.get(g, "")
		if ch == "" and g.length() > 5 and g.substr(g.length() - 4, 2).is_valid_int():
			# fingers: toward the next joint of the same finger (index_01_l -> index_02_l)
			var num := int(g.substr(g.length() - 4, 2))
			ch = "%s%02d%s" % [g.substr(0, g.length() - 4), num + 1, g.substr(g.length() - 2)]
		if ch != "" and g2s.has(ch) and t["idx"].has(ch):
			var sdir: Vector3 = face * ((s["pos"][g2s[ch]] as Vector3) - (s["pos"][si] as Vector3))
			var tdir: Vector3 = (t["pos"][t["idx"][ch]] as Vector3) - (t["pos"][ti] as Vector3)
			if sdir.length() > 1e-5 and tdir.length() > 1e-5:
				align = Quaternion(sdir.normalized(), tdir.normalized())
		var s_ref := align * s_rest
		offs[ti] = s_ref.inverse() * (t["rot"][ti] as Quaternion)
	# hip heights over the feet, for the pelvis translation
	var s_hip: float = (s["pos"][g2s["pelvis"]] as Vector3).y - minf((s["pos"][g2s["foot_l"]] as Vector3).y, (s["pos"][g2s["foot_r"]] as Vector3).y)
	var t_hip: float = (t["pos"][t["idx"]["pelvis"]] as Vector3).y - minf((t["pos"][t["idx"]["foot_l"]] as Vector3).y, (t["pos"][t["idx"]["foot_r"]] as Vector3).y)
	var k := t_hip / maxf(1e-4, s_hip)
	# source tracks by bone index
	var tr := {}
	for ti2 in anim.get_track_count():
		var p := anim.track_get_path(ti2)
		var bn := str(p.get_concatenated_subnames())
		var bi := ssk.find_bone(bn)
		if bi < 0:
			continue
		if not tr.has(bi):
			tr[bi] = {}
		tr[bi][anim.track_get_type(ti2)] = ti2
	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var t_tracks := {}
	for g in g2s:
		if t["idx"].has(g):
			var ti3: int = t["idx"][g]
			var rt := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(rt, NodePath(".:" + g))
			t_tracks[ti3] = rt
	var pel_t: int = t["idx"]["pelvis"]
	var pt := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pt, NodePath(".:pelvis"))
	var s_model: Transform3D = s["model"]
	var t_model: Transform3D = t["model"]
	var s_pel_rest: Vector3 = face * (s["pos"][g2s["pelvis"]] as Vector3)
	var n := int(ceil(anim.length * FPS)) + 1
	var foot_i: int = t["idx"]["foot_l"]
	var fz_min := 1e9
	var fz_max := -1e9
	var pel_first := Vector3.ZERO
	var pel_last := Vector3.ZERO
	for f in n:
		var time := minf(f / FPS, anim.length)
		# source model-space globals for this frame
		var sg := {}
		for i in ssk.get_bone_count():
			var lp := ssk.get_bone_rest(i)
			var lr := lp.basis.get_rotation_quaternion()
			var lo := lp.origin
			var lsc := lp.basis.get_scale()
			if tr.has(i):
				var d: Dictionary = tr[i]
				if d.has(Animation.TYPE_ROTATION_3D):
					lr = anim.rotation_track_interpolate(d[Animation.TYPE_ROTATION_3D], time)
				if d.has(Animation.TYPE_POSITION_3D):
					lo = anim.position_track_interpolate(d[Animation.TYPE_POSITION_3D], time)
				if d.has(Animation.TYPE_SCALE_3D):
					lsc = anim.scale_track_interpolate(d[Animation.TYPE_SCALE_3D], time)
			var lt := Transform3D(Basis(lr).scaled(lsc), lo)
			var par := ssk.get_bone_parent(i)
			sg[i] = (sg[par] as Transform3D) * lt if par >= 0 else s_model * lt
		# target globals (model space), parents first
		var tg := {}
		for i in tsk.get_bone_count():
			var par2 := tsk.get_bone_parent(i)
			var rest := tsk.get_bone_rest(i)
			var pg: Transform3D = tg[par2] if par2 >= 0 else t_model
			var g3 := pg * rest
			if offs.has(i):
				var gname := tsk.get_bone_name(i)
				var sw: Quaternion = face * (sg[g2s[gname]] as Transform3D).basis.get_rotation_quaternion()
				var wq := (sw * (offs[i] as Quaternion)).normalized()
				var origin := g3.origin
				if i == pel_t:
					var sp: Vector3 = face * (sg[g2s["pelvis"]] as Transform3D).origin
					origin = (t["pos"][pel_t] as Vector3) + (sp - s_pel_rest) * k
				g3 = Transform3D(Basis(wq), origin)
			tg[i] = g3
			if t_tracks.has(i):
				var pgb: Basis = (tg[par2] as Transform3D).basis.orthonormalized() if par2 >= 0 else t_model.basis.orthonormalized()
				var local_q := (pgb.inverse() * Basis(g3.basis.get_rotation_quaternion())).get_rotation_quaternion()
				out.rotation_track_insert_key(t_tracks[i], time, local_q)
			if i == pel_t:
				var pgt: Transform3D = tg[par2] if par2 >= 0 else t_model
				out.position_track_insert_key(pt, time, pgt.affine_inverse() * g3.origin)
				if f == 0:
					pel_first = g3.origin - (t["pos"][pel_t] as Vector3)
				pel_last = g3.origin - (t["pos"][pel_t] as Vector3)
			if i == foot_i:
				fz_min = minf(fz_min, g3.origin.z)
				fz_max = maxf(fz_max, g3.origin.z)
	# metadata for the rig: in-place gait speed (a foot sweeps its range twice a cycle) and how far
	# the pelvis is from rest at the start and the end (seat height, kneeling drop)
	out.set_meta("speed", 2.0 * (fz_max - fz_min) / maxf(0.01, anim.length) if loop else 0.0)
	out.set_meta("pelvis_first", pel_first)
	out.set_meta("pelvis_last", pel_last)
	return out
