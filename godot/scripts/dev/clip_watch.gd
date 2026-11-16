extends Node
## Clipping watch (autopilot --clipwatch[=OUT.json]): every 0.2 s of game time, every visible skeleton
## in the scene (Clara, Davi, the ghosts' HumanRigs, the hound, the doll, the thing, the cat) is tested
## against the world's collision (layer 1, and the cat-only blockers on 32, tagged):
##   - along each bone (parent -> child, both ways, back faces and starts inside on): a hit means the
##     bone's AXIS crosses into a solid, i.e. a deep clip, not a graze of the skin;
##   - key points (pelvis, head, hands, feet / the cat's head and hips) inside a solid: a short ray up
##     whose first hit is a back face (closed trimesh) or starts inside (convex).
## Findings are grouped by (actor, situation, bone, collider); the first of each prints a CLIP line, the
## summary (CLIPSUM) prints and is written to OUT.json at exit. --clipquit=SEC quits after SEC game
## seconds; --clipphase quits when the phase changes (an afternoon played to bed with --steplog).
## Blind spots: anything with no collider (most small props, the held things, the bodies themselves).

var ap: Node
var g: Game
var out := ""
var acc := 0.0
var t := 0.0
var quit_after := -1.0
var start_phase := ""
var found := {}            # key -> {n, first, pos, actor, ctx, bone, col, kind}
var tested := 0
var vis: Array = []        # [AABB (world), name] of every furniture-size visible mesh of the house
var min_depth := 0.03
var shots_dir := ""         # --clipshots=DIR: a photo of each new finding seen in a mesh (window runs)
var shot_q: Array = []      # [deep point, actor root point, file name]
var shot_seen := {}         # actor|ctx|mesh -> true (one photo each)
var shot_stage := 0
var shot_cam: Camera3D
var shot_prev: Camera3D
var shot_n := 0      # --clipdepth=M: how far the bone axis must go under the collider's surface

const HUMAN_SEGS := [["pelvis", "spine_02"], ["spine_02", "neck_01"], ["neck_01", "head"],
	["upperarm_l", "lowerarm_l"], ["lowerarm_l", "hand_l"], ["upperarm_r", "lowerarm_r"], ["lowerarm_r", "hand_r"],
	["thigh_l", "calf_l"], ["calf_l", "foot_l"], ["foot_l", "ball_l"], ["thigh_r", "calf_r"], ["calf_r", "foot_r"], ["foot_r", "ball_r"]]
const HUMAN_PTS := ["pelvis", "head", "hand_l", "hand_r", "foot_l", "foot_r", "spine_02"]


func start(o: String) -> void:
	out = o if o != "1" else ""
	if ap.args.has("clipquit"):
		quit_after = float(ap.args["clipquit"])
	start_phase = g.phase
	min_depth = float(ap.args.get("clipdepth", "0.03"))
	if ap.args.has("posefix") and not ap.args.has("clarasurvey"):
		var pj = JSON.parse_string(FileAccess.get_file_as_string(str(ap.args["posefix"])))
		if pj is Dictionary:
			for pn in pj:
				for jn in pj[pn]:
					var v = pj[pn][jn]
					HumanRig.POSES[pn][jn] = Vector3(v[0], v[1], v[2]) if v is Array else float(v)
	shots_dir = str(ap.args.get("clipshots", ""))
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	_collect_vis()
	print("CLIPWATCH on phase=%s day=%d, %d furniture meshes" % [g.phase, g.day, vis.size()])


## the visible meshes a finding must also be inside to count as seen (a collider can be bigger than its
## mesh: a sofa block down to the floor, a solid tub). Whole walls / floors (> 3 m) are left out
func _collect_vis() -> void:
	vis.clear()
	for mi in g.house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var ab := m.global_transform * m.get_aabb()
		if ab.size[ab.get_longest_axis_index()] > 3.0:
			continue
		var nm := str(m.name)
		var p := m.get_parent()
		for i in 3:
			if p == null or p == g.house:
				break
			nm = str(p.name) + "/" + nm
			p = p.get_parent()
		vis.append([ab, nm])


func _vis_at(p: Vector3) -> String:
	var best := ""
	var bv := INF
	for v in vis:
		var ab: AABB = v[0]
		if ab.grow(0.005).has_point(p) and ab.get_volume() < bv:
			bv = ab.get_volume()
			best = v[1]
	return best


func _process(_dt: float) -> void:
	if shots_dir == "" or (shot_q.is_empty() and shot_stage == 0):
		return
	if shot_stage == 0:
		var q: Array = shot_q[0]
		var deep: Vector3 = q[0]
		var root: Vector3 = q[1]
		# from the actor's side, away from the thing, a little above: the contact in the middle
		var away := root - deep
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3(1, 0, 0)
		var cpos := deep + away.normalized().rotated(Vector3.UP, 0.6) * 1.3 + Vector3(0, 0.55, 0)
		shot_prev = get_viewport().get_camera_3d()
		shot_cam = Camera3D.new()
		shot_cam.fov = 55.0
		get_tree().root.add_child(shot_cam)
		shot_cam.global_position = cpos
		shot_cam.look_at(deep, Vector3.UP)
		shot_cam.current = true
		Engine.time_scale = 0.0
		shot_stage = 1
	elif shot_stage < 4:
		shot_stage += 1
	else:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shots_dir.path_join(str(shot_q[0][2])))
		shot_q.pop_front()
		shot_cam.queue_free()
		if is_instance_valid(shot_prev):
			shot_prev.current = true
		Engine.time_scale = float(ap.args.get("timescale", "1"))
		shot_stage = 0


func _physics_process(dt: float) -> void:
	if g == null or g.mode == "boot":
		return
	t += dt
	acc += dt
	if acc < 0.2:
		return
	acc = 0.0
	if ap.args.has("clipphase") and g.phase != start_phase and t > 2.0:
		print("CLIPWATCH phase %s -> %s" % [start_phase, g.phase])
		get_tree().quit()
		return
	if quit_after > 0 and t >= quit_after:
		get_tree().quit()
		return
	if ap.args.has("clipdebug") and t > 3.0 and t < 3.3:
		var c := str(ap.args["clipdebug"]).split(",")
		var pp := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var sp := get_viewport().world_3d.direct_space_state
		var ex: Array[RID] = []
		for d in DIRS:
			var hb := _cast(sp, pp, pp + d * 0.6, ex, true)
			var hf := _cast(sp, pp, pp + d * 0.6, ex, false)
			print("CLIPDEBUG %s back=%s front=%s" % [d, str([hb.get("position"), hb.get("normal"), _col_name(hb["collider"], int(hb.get("shape", -1))) if not hb.is_empty() else ""]), str([hf.get("position"), _col_name(hf["collider"], int(hf.get("shape", -1))) if not hf.is_empty() else ""])])
		print("CLIPDEBUG inside=", _inside(sp, pp, ex))
	_scan()


func _scan() -> void:
	var space := get_viewport().world_3d.direct_space_state
	for r in get_tree().root.find_children("*", "HumanRig", true, false):
		var rig := r as HumanRig
		if not rig.is_visible_in_tree() or rig.cur_outfit == "" or not rig.outfits.has(rig.cur_outfit):
			continue
		var idx: Dictionary = rig.outfits[rig.cur_outfit]["maps"]["idx"]
		var pos := {}
		for b in idx:
			pos[b] = rig.bone_world(b).origin
		if pos.has("head"):
			pos["head_top"] = rig.bone_world("head") * Vector3(0, 0.17, 0.02)
		var segs: Array = HUMAN_SEGS.duplicate()
		segs.append(["head", "head_top"])
		_test(space, rig, _actor(rig), _ctx_human(rig), pos, segs, HUMAN_PTS)
	for s in get_tree().root.find_children("*", "Skeleton3D", true, false):
		var sk := s as Skeleton3D
		if not sk.is_visible_in_tree() or _under_human(sk):
			continue
		var pos := {}
		var segs := []
		for i in sk.get_bone_count():
			var p := sk.get_bone_parent(i)
			pos[sk.get_bone_name(i)] = sk.global_transform * sk.get_bone_global_pose(i).origin
			if p >= 0:
				var a: Vector3 = sk.global_transform * sk.get_bone_global_pose(p).origin
				if a.distance_to(pos[sk.get_bone_name(i)]) > 0.04:
					segs.append([sk.get_bone_name(p), sk.get_bone_name(i)])
		var pts := []
		for b in pos:
			var lb := str(b).to_lower()
			if lb == "head" or lb.begins_with("hip") or lb == "pelvis" or lb.begins_with("spine"):
				pts.append(b)
		_test(space, sk, _actor(sk), _ctx_other(sk), pos, segs, pts)


func _under_human(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is HumanRig:
			return true
		p = p.get_parent()
	return false


func _actor(n: Node) -> String:
	var p := n
	while p:
		if p is Owner:
			return str((p as Owner).cfg.get("id", p.name))
		if p is Threat:
			return "threat:" + (p as Threat).threat_id
		if p is CatRig or p == g.cat:
			return "cat"
		p = p.get_parent()
	return "?" + str(n.get_parent().name)


func _owner_of(n: Node) -> Node:
	var p := n
	while p:
		if p is Owner or p is Threat or p == g.cat:
			return p
		p = p.get_parent()
	return null


func _ctx_human(rig: HumanRig) -> String:
	var c := "%s/%s" % [rig.pose, str(rig._state)]
	if rig.holding() != "":
		c += "/hold:" + rig.holding()
	if rig._gest != "":
		c += "/g:" + rig._gest
	var o := _owner_of(rig)
	if o is Owner and (o as Owner).task != null:
		var tk: Dictionary = (o as Owner).task
		var st := ""
		if tk.has("steps") and tk.has("idx") and int(tk["idx"]) < (tk["steps"] as Array).size():
			var s = tk["steps"][int(tk["idx"])]
			st = str(s.get("t", "")) + (":" + str(s.get("pose", s.get("to", s.get("anim", ""))))) if s is Dictionary else ""
		c += "/task:%s:%s" % [str(tk.get("name", "")), st]
	elif o is Threat:
		c += "/stage:%d" % (o as Threat).stage
	return c


func _ctx_other(sk: Skeleton3D) -> String:
	var o := _owner_of(sk)
	if o == g.cat:
		return "mode:" + str(g.cat.mode)
	if o is Threat:
		return "stage:%d" % (o as Threat).stage
	return ""


func _excl(n: Node) -> Array[RID]:
	var o := _owner_of(n)
	var ex: Array[RID] = []
	if o:
		for c in o.find_children("*", "CollisionObject3D", true, false):
			ex.append((c as CollisionObject3D).get_rid())
		if o is CollisionObject3D:
			ex.append((o as CollisionObject3D).get_rid())
	# whatever the cat holds or a person holds is part of the act, not the world
	if g.cat and g.cat.get("carrying") and g.cat.carrying is Node:
		for c in (g.cat.carrying as Node).find_children("*", "CollisionObject3D", true, false):
			ex.append((c as CollisionObject3D).get_rid())
	return ex


func _test(space: PhysicsDirectSpaceState3D, n: Node, actor: String, ctx: String, pos: Dictionary, segs: Array, pts: Array) -> void:
	var ex := _excl(n)
	for sg in segs:
		if not pos.has(sg[0]) or not pos.has(sg[1]):
			continue
		var a: Vector3 = pos[sg[0]]
		var b: Vector3 = pos[sg[1]]
		var hf := _ray(space, a, b, ex)
		var hb := _ray(space, b, a, ex)
		if hf.is_empty() and hb.is_empty():
			continue
		# how far the axis goes under the surface: from the entry face (its normal) to the deepest end
		# of the inside part (the other ray's hit, or the segment's end)
		var depth := 0.0
		var nf: Vector3 = hf.get("normal", Vector3.ZERO)
		var nb: Vector3 = hb.get("normal", Vector3.ZERO)
		if not hf.is_empty() and nf.length_squared() > 1e-6:
			var endp: Vector3 = hb["position"] if not hb.is_empty() and nb.length_squared() > 1e-6 else b
			depth = maxf(depth, -(endp - (hf["position"] as Vector3)).dot(nf))
		if not hb.is_empty() and nb.length_squared() > 1e-6:
			var endq: Vector3 = hf["position"] if not hf.is_empty() and nf.length_squared() > 1e-6 else a
			depth = maxf(depth, -(endq - (hb["position"] as Vector3)).dot(nb))
		# an end inside a solid (convex or a closed trimesh, where the rays above cross no face)
		for e in [sg[0], sg[1]]:
			var ins := _inside(space, pos[e], ex)
			if not ins.is_empty():
				depth = maxf(depth, ins["depth"])
				if hf.is_empty():
					hf = ins
		if depth >= min_depth and not hf.is_empty():
			_hit(actor, ctx, "%s-%s" % sg, hf, "seg", depth)
		elif depth >= min_depth:
			_hit(actor, ctx, "%s-%s" % sg, hb, "seg", depth)
	for p in pts:
		if not pos.has(p):
			continue
		var ins := _inside(space, pos[p], ex)
		if not ins.is_empty() and float(ins["depth"]) >= min_depth:
			_hit(actor, ctx, str(p), ins, "inside", ins["depth"])


const DIRS := [Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]


## {collider, shape, position, depth} when P is inside a solid. Each of 6 directions votes: its first
## hit counting back faces is nearer than its first front-face hit (or the ray starts inside a convex
## shape) = inside; the front face first = outside; nothing = no vote. Inside needs 3+ votes and more
## than the outside ones (open meshes, a mattress without a bottom, would fool a single ray).
## depth: the shortest way out among the inside votes.
func _inside(space: PhysicsDirectSpaceState3D, p: Vector3, ex: Array[RID]) -> Dictionary:
	var best := {}
	var vin := 0
	var vout := 0
	for d in DIRS:
		var hb := _cast(space, p, p + d * 0.6, ex, true)
		if hb.is_empty():
			continue
		var db: float = ((hb["position"] as Vector3) - p).length()
		var convex := (hb["normal"] as Vector3).length_squared() < 1e-6
		var inside := convex
		if not convex:
			var hf := _cast(space, p, p + d * 0.6, ex, false)
			inside = hf.is_empty() or ((hf["position"] as Vector3) - p).length() > db + 0.002
		if not inside:
			vout += 1
			continue
		vin += 1
		if convex:
			# the way out along d: from outside, back toward p
			var ho := _cast(space, p + d * 0.6, p, ex, false)
			db = 0.6 - ((ho["position"] as Vector3) - (p + d * 0.6)).length() if not ho.is_empty() else 0.6
		if best.is_empty() or db < float(best["depth"]):
			best = {"collider": hb["collider"], "shape": hb.get("shape", -1), "position": hb["position"], "depth": db, "point": p}
	if vin >= 3 and vin > vout:
		return best
	return {}


func _cast(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, ex: Array[RID], back: bool) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1 | 32, ex)
	q.hit_back_faces = back
	q.hit_from_inside = back
	tested += 1
	return space.intersect_ray(q)


func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, ex: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1 | 32, ex)
	q.hit_back_faces = true
	q.hit_from_inside = true
	tested += 1
	return space.intersect_ray(q)


func _col_name(c: Object, shape := -1) -> String:
	if c is CollisionObject3D and shape >= 0:
		var co := c as CollisionObject3D
		var own := co.shape_find_owner(shape)
		var sn: Object = co.shape_owner_get_owner(own) if own >= 0 else null
		if sn is Node and (sn as Node) != co:
			return _col_name(c) + ":" + str((sn as Node).name)
	if c is Node:
		var nd := c as Node
		var nm := str(nd.name)
		var p := nd.get_parent()
		if p and p != g and p.name != "House":
			nm = str(p.name) + "/" + nm
		if c is CollisionObject3D and ((c as CollisionObject3D).collision_layer & 1) == 0:
			nm += "[catonly]"
		return nm
	return str(c)


func _hit(actor: String, ctx: String, bone: String, h: Dictionary, kind: String, depth: float) -> void:
	var col := _col_name(h["collider"], int(h.get("shape", -1)))
	var key := "%s|%s|%s|%s|%s" % [actor, ctx, bone, col, kind]
	if found.has(key):
		found[key]["n"] += 1
		found[key]["depth"] = maxf(found[key]["depth"], depth)
		return
	var p: Vector3 = h["position"]
	var nrm: Vector3 = h.get("normal", Vector3.ZERO)
	var deep: Vector3 = h["point"] if h.has("point") else (p - nrm.normalized() * depth if nrm.length_squared() > 1e-6 and depth < 0.5 else p)
	found[key] = {"vis": _vis_at(deep), "n": 1, "first": t, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "actor": actor, "ctx": ctx, "bone": bone, "col": col, "kind": kind, "depth": depth}
	var sk := "%s|%s|%s" % [actor, ctx.split("/task:")[0], found[key]["vis"]]
	if shots_dir != "" and found[key]["vis"] != "" and depth >= 0.08 and not shot_seen.has(sk):
		shot_seen[sk] = true
		shot_n += 1
		var fn := "%03d_%s_%s_%s.png" % [shot_n, actor.replace("threat:", ""), ctx.split("/task:")[0].replace("/", "-").replace(":", "-").replace("<", "").replace(">", ""), str(found[key]["vis"]).get_file().replace("/", "-")]
		shot_q.append([deep, _root_of(actor, deep), fn])
		found[key]["shot"] = fn
	print("CLIP t=%.1f %s %s %s d=%.2f %s in %s vis=%s @(%.2f,%.2f,%.2f)" % [t, actor, kind, bone, depth, ctx, col, found[key]["vis"], p.x, p.y, p.z])


func _root_of(actor: String, near: Vector3) -> Vector3:
	match actor:
		"clara":
			return g.clara.global_position
		"davi":
			return g.davi.global_position
		"cat":
			return g.cat.global_position
	return near + Vector3(1, 0, 0)


func _exit_tree() -> void:
	var keys := found.keys()
	keys.sort_custom(func(a, b): return found[a]["n"] > found[b]["n"])
	print("CLIPSUM %d findings, %d rays, %.0f s" % [keys.size(), tested, t])
	for k in keys:
		var f: Dictionary = found[k]
		print("CLIPSUM n=%d d=%.2f %s %s %s %s in %s first=%.1f @%s" % [f["n"], f["depth"], f["actor"], f["kind"], f["bone"], f["ctx"], f["col"], f["first"], str(f["pos"])])
	if out != "":
		var fa := FileAccess.open(out, FileAccess.WRITE)
		if fa:
			fa.store_string(JSON.stringify(found.values(), "  "))
