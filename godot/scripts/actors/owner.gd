class_name Owner
extends Node3D
## A person the cat protects (Clara, Davi). Fear, patience, sleep; a task queue of steps (walk the
## nav graph, pose, wait, speak, run code, wait until, go to bed); reacts to meows and noises.
## Port of Owner.ts.

signal said(text, dur, kind, who)
signal stepped(pos)
signal opened_door(door)
signal wants_lamp(who)

const CLARA := {
	"id": "clara", "name": "Clara", "skeptic": false, "fear_scale": 1.0,
	"bed_spot": "bed", "bedside_spot": "bedside", "bed_room": "quarto", "bed_node": "f_quarto_bed",
	"bed_side": Vector3(1.6, 3, 1.4), "bed_top": Vector3(1.55, 3.6, 2.15), "purr_pos": Vector3(0.9, 3.4, 2.93), "purr_yaw": -PI / 2,
	"lamp": 8, "voice_pitch": 1.0, "bed_offset": Vector3(-0.11, 0, -0.3),
}
const DAVI := {
	"id": "davi", "name": "Davi", "skeptic": true, "fear_scale": 0.7,
	"bed_spot": "davBed", "bedside_spot": "davBedside", "bed_room": "hospedes", "bed_node": "f_hosp_bed",
	"bed_side": Vector3(1.5, 3, 7.3), "bed_top": Vector3(1.55, 3.58, 7.95), "purr_pos": Vector3(1.1, 3.57, 7.98), "purr_yaw": -PI / 2,
	"lamp": 17, "voice_pitch": 0.62, "bed_offset": Vector3(-0.2, -0.12, 0), "seat_deep": 0.45, "seat_adj": 0.01,
}

var cfg: Dictionary
var model: HumanRig
var nav: NavGraph
var doors: Array = []
var display_name: String
var present := true
var following := false
var yaw := 0.0
var fear := 0.0
var patience := 70.0
var in_bed := false:
	set(v):
		in_bed = v
		# the night outfits come with shoes (VRoid): off in bed
		if model:
			model.hide_shoes(v)
var asleep := false
var task = null          # {name, steps, idx, timer, priority, on_done, started}
var purring := false
var paralysis := false
var hypno := false
var night := true
var paused := false
var scripted := false
var _fear_feed := 0.0
var _since_fear := 99.0
var _path: Array = []      # the smoothed walking line (corners rounded), walked by arc length
var _path_i := 0
var _path_len := PackedFloat32Array()
var _path_s := 0.0
var _v := 0.0               # walking speed: accelerates, brakes before the end
var _turn_first := false    # facing far from the way: turn on the spot first, in little steps
var cat_ref: Node3D         # the cat, for the automatic glances (set by the game)
var head_mark := Node3D.new()   # follows the head (tick): what the cat looks at when it tilts or blinks at her
var look_hint = null        # something to keep an eye on (the TV), set by the scene
var _look_at = null         # a timed glance: a point or a node
var _look_at_t := 0.0
var _cat_seen := false
var _cat_check := 0.0
var _glance_t := 0.0        # walking: a short look at the cat, then a while before the next one
var _glance_cd := 0.0
var _body_turn := false     # standing, turning the body toward what she looks at (little steps)
var _style := "normal"
var _step_acc := 0.0
var _call_t := 6.0
var _noise_cd := 0.0
var _lamp_done := false
var _wake_t := 0.0
var _pause_t := 0.0
var _turning := false
var _seg_from := Vector3.ZERO
var force_pose := ""        # dev: hold this pose in bed (autopilot --bedpose)
var _bed_door = null        # awake in bed she keeps an eye on the bedroom door
var _look_t := 0.0
var _look_door := false
var _noise_at = null
var _noise_look_t := 0.0
var _side_t := 8.0
var _on_side := false
var _says: Array = []        # falas esperando a vez: {text, dur, kind, age}
var _say_left := 0.0         # quanto falta para a fala atual terminar

const SAY_GAP := 0.3         # pausa entre duas falas da mesma pessoa
const SAY_QUEUE_MAX := 3     # falas esperando; passou disso, sai a mais antiga
const SAY_STALE := 5.0       # fala que esperou demais já não faz sentido (chamados)
const SAY_REPLY_MIN := 0.12  # entrando logo depois da fala de outra pessoa: um respiro curto e variado,
const SAY_REPLY_MAX := 0.55  # nem colado (robótico) nem demorado (conversa estranha)
static var _everyone: Array = []   # todos os falantes: uma pessoa só fala quando a outra termina
var _was_blocked := false
var _reply_in := -1.0


func _init(c: Dictionary, n: NavGraph, door_list: Array) -> void:
	_everyone = _everyone.filter(func(o): return is_instance_valid(o))
	_everyone.append(self)
	cfg = c
	nav = n
	doors = door_list
	display_name = c["name"]
	model = HumanRig.new(c["id"])
	add_child(model)
	head_mark.name = "head_mark"
	head_mark.top_level = true
	add_child(head_mark)


var pos: Vector3:
	get:
		return global_position
	set(v):
		global_position = v


## an outfit by key, the night one if this model has no such outfit (the bath towel)
func set_outfit_k(k: String) -> void:
	model.set_outfit(k if model.outfits.has(k) else "night")
	model.reset_springs()


## standing around or sitting in a scripted wait: the cat can ask for a pet
func interruptible() -> bool:
	if paused or not visible:
		return false
	if task == null:
		return true
	var st: Dictionary = task["steps"][task["idx"]]
	return str(st["t"]) in ["wait", "until", "pose"] and model.pose in ["stand", "sit"]


func set_night(v: bool) -> void:
	night = v
	model.set_outfit("night" if v else "day")


func place(spot: Dictionary) -> void:
	global_position = Layout.v3(spot["p"])
	yaw = spot["yaw"]
	rotation.y = yaw
	model.seat_back = false
	model.seat_lift = 0.0
	model.reset_springs()


func put_in_bed(sleeping := true) -> void:
	place(Layout.spot(cfg["bed_spot"]))
	# from the bed spot to where the head lands on the pillow, clear of the headboard (Clara's pillow
	# centre x 0.34 / top 3.53, headboard 0.13; guest pillow x 0.40 / top 3.66, mattress 3.55: Davi's
	# lying pelvis, 1.045 - 0.38 over the root, needs the root 12 cm lower to rest on it)
	global_position += cfg.get("bed_offset", Vector3.ZERO)
	in_bed = true
	asleep = sleeping
	model.snap_pose("lie")
	model.sleep_side = -1.0 if randf() < 0.5 else 1.0
	_on_side = false
	_bed_door = null
	var best := 6.0
	for d: Door in doors:
		var c := d.center()
		if absf(c.y - global_position.y) < 1.5 and c.distance_to(global_position) < best:
			best = c.distance_to(global_position)
			_bed_door = c
	task = null
	_path = []
	_lamp_done = false


func hide_model() -> void:
	visible = false


func show_model() -> void:
	visible = true


var busy: bool:
	get:
		return task != null


var task_name: String:
	get:
		return task["name"] if task != null else ""


func head_pos() -> Vector3:
	return model.head_world()


func add_fear(v: float) -> void:
	if v > 0:
		v *= cfg["fear_scale"]
		_fear_feed += v
		_since_fear = 0.0
		# a real fright shows: a start, wide eyes
		if v >= 8.0 and not asleep and visible:
			startle()
	fear = clampf(fear + v, 0, 100)


func add_patience(v: float) -> void:
	patience = clampf(patience + v, 0, 100)


## one line at a time, like a person talking: a line that comes while she is still talking waits its turn
## (the subtitle and the voice start together with it). Narration ("read") does not wait.
func say(text: String, dur := 3.0, kind := "normal") -> void:
	if kind == "read":
		_speak(text, dur, kind)
		return
	if _say_left > 0.0 or not _says.is_empty() or _other_talking():
		_was_blocked = _was_blocked or _other_talking()
		_says.append({"text": text, "dur": dur, "kind": kind, "age": 0.0})
		if _says.size() > SAY_QUEUE_MAX:
			_says.pop_front()
		return
	_speak(text, dur, kind)


func _speak(text: String, dur: float, kind: String) -> void:
	var line := tr(text).replace("{cat}", Settings.cat_name)
	if kind != "read":
		_say_left = dur + SAY_GAP
		model.talk(line, dur)
	said.emit(line, dur, kind, self)


## the next queued line starts when the current one is over; lines that waited too long are dropped
func _tick_says(dt: float) -> void:
	for s: Dictionary in _says:
		s["age"] += dt
	_says = _says.filter(func(s): return s["age"] <= SAY_STALE)
	if _say_left > 0.0:
		_say_left -= dt
	elif not _says.is_empty():
		if _other_talking():
			_was_blocked = true
			_reply_in = -1.0
			return
		if _was_blocked:
			# the other one just finished: answer after a short, uneven beat
			if _reply_in < 0.0:
				_reply_in = randf_range(SAY_REPLY_MIN, SAY_REPLY_MAX)
			_reply_in -= dt
			if _reply_in > 0.0:
				return
			_was_blocked = false
			_reply_in = -1.0
		var nxt: Dictionary = _says.pop_front()
		_speak(nxt["text"], nxt["dur"], nxt["kind"])


## someone else in the house is in the middle of a line (the voices never overlap)
func _other_talking() -> bool:
	for o: Owner in _everyone:
		if o != self and is_instance_valid(o) and o._say_left > SAY_GAP:
			return true
	return false


func startle() -> void:
	model.set_mood("surprised", 1.0, 1.6)
	if not in_bed and model.pose in ["stand", "phone", "fold", "talk"]:
		model.play_once("hit", 0.08, 0.35)


## glance at a point or a node (another person, the cat) for a while
func look_for(what, dur := 2.0) -> void:
	_look_at = what
	_look_at_t = dur


func _point_of(what):
	if what is Owner:
		return (what as Owner).head_pos()
	if what is Node3D:
		return (what as Node3D).global_position + Vector3(0, 0.15, 0)
	return what


## what the eyes go to when nobody scripted it: a glance, a noise, the cat close by and in sight,
## the thing she is watching (TV)
func _auto_look(dt: float):
	_look_at_t -= dt
	_noise_look_t -= dt
	if model.holding() == "book_open":
		return (model.held["hand"][0] as Node3D).global_position
	if model.pose == "read":
		return global_position + Vector3(sin(yaw), 0, cos(yaw)) * 0.42 + Vector3(0, 0.62, 0)
	if _look_at_t > 0 and _look_at != null and (not (_look_at is Node) or is_instance_valid(_look_at)):
		return _point_of(_look_at)
	if _noise_look_t > 0 and _noise_at != null:
		return _noise_at
	_cat_check -= dt
	if cat_ref != null and _cat_check <= 0:
		_cat_check = 0.3
		var cp := cat_ref.global_position + Vector3(0, 0.2, 0)
		_cat_seen = false
		if cp.distance_to(global_position) < 3.0 and cat_ref.visible:
			var q := PhysicsRayQueryParameters3D.create(head_pos(), cp, HouseBuilder.LAYER_WORLD)
			_cat_seen = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	# walking: eyes on the way, the cat only gets a short glance now and then (and only when ahead)
	_glance_t -= dt
	_glance_cd -= dt
	if _v > 0.2 and _path.size() > 1:
		if _cat_seen and cat_ref != null:
			var to_cat := cat_ref.global_position - global_position
			var ahead := Vector3(sin(yaw), 0, cos(yaw)).angle_to(Vector3(to_cat.x, 0, to_cat.z)) < deg_to_rad(60)
			if _glance_t <= 0 and _glance_cd <= 0 and ahead:
				_glance_t = 0.8
				_glance_cd = randf_range(5.0, 8.0)
			if _glance_t > 0:
				return cat_ref.global_position + Vector3(0, 0.15, 0)
		var left: float = _path_len[_path_len.size() - 1] - _path_s
		if left > 0.6:
			return _sample_path(_path_s + minf(2.0, left)) + Vector3(0, 1.3, 0)
		return null
	# watching something (the TV): mostly that, a glance at the cat now and then
	var watching := look_hint != null and fmod(Time.get_ticks_msec() / 1000.0, 7.0) < 5.2
	if _cat_seen and cat_ref != null and not watching:
		return cat_ref.global_position + Vector3(0, 0.15, 0)
	if look_hint != null:
		return _point_of(look_hint)
	return null


func run(nm: String, steps: Array, priority := 1, on_done: Callable = Callable()) -> bool:
	if task != null and task["priority"] > priority:
		return false
	task = {"name": nm, "steps": steps, "idx": 0, "timer": 0.0, "priority": priority, "on_done": on_done, "started": false}
	_path = []
	in_bed = false
	asleep = false
	paralysis = false
	return true


## a short errand in the middle of whatever she is doing (filling the water bowl): the steps go in
## before the current one, and she picks her routine up again after
func side_trip(steps: Array) -> void:
	if task == null:
		run("side", steps, 1)
		return
	var st: Array = task["steps"]
	var i: int = task["idx"]
	task["steps"] = st.slice(0, i) + steps + st.slice(i)
	task["started"] = false
	task["timer"] = 0.0
	_path = []


func abort() -> void:
	task = null
	_path = []
	hypno = false
	model.style = "normal"


func go_to_bed(priority := 0, line := "") -> void:
	var steps: Array = []
	if line != "":
		steps.append({"t": "say", "text": line, "dur": 2.6})
	steps.append({"t": "spot", "spot": Layout.spot(cfg["bedside_spot"])})
	steps.append({"t": "bed"})
	run("bed", steps, priority)


static func pick(a: Array):
	return a[randi() % a.size()]


## the cat meowed nearby: 'none' | 'trance' | 'woke' | 'paused' | 'coming'
func hear_meow(cat_pos: Vector3, hops: int) -> String:
	if scripted or not present:
		return "none"
	# in a trance (the Whisperer's call) any meow in the house snaps her out of it, however far
	if hypno:
		# drop the "whisper" task (priority 3) first, or the priority-2 walk to bed is refused
		abort()
		add_patience(-3)
		say(pick(["Hã...? O que eu tô fazendo aqui...?", "Ai... {cat}? Eu tava sonâmbula?" if cfg["id"] == "clara" else "Ai... {cat}? Eu tava sonâmbulo?", "Que frio... como eu vim parar aqui?"]), 3.2, "whisper")
		go_to_bed(2)
		return "trance"
	var d := cat_pos.distance_to(global_position) + hops * 3.0
	if d > 18:
		return "none"
	if paralysis:
		return "none"
	var sk: bool = cfg["skeptic"]
	var result := "none"
	_noise_at = cat_pos + Vector3(0, 0.2, 0)
	_noise_look_t = 3.0
	if asleep and in_bed:
		if d > 9:
			return "none"
		add_patience(0.0 if fear > 50 else (-6.0 if sk else -4.0))
		asleep = false
		_wake_t = 3.5
		if fear < 50:
			say(pick(["Ô, gato... são três da manhã.", "Shh. Dorme, bicho.", "Cara, de novo?"] if sk else ["{cat}... dorme, gato.", "Hmm... {cat}, são três da manhã...", "Shhh... {cat}..."]), 2.6, "annoyed")
		else:
			say(pick(["{cat}? Você também ouviu?", "Tá aí, {cat}? Fica aqui comigo."]), 2.6, "scared")
		result = "woke"
	if task != null and task["name"] == "visitor":
		_pause_t = 4.0
		say("{cat}? O que foi?", 2.0, "call")
		return "paused"
	if (in_bed or task == null) and fear < 68 and d < 14:
		var delay := 2.4 if in_bed else 0.2
		add_patience(-2)
		following = true
		var target := cat_pos
		get_tree().create_timer(delay).timeout.connect(func():
			if following and not paralysis and not hypno:
				come_to(target))
		return "coming" if result == "none" else "woke"
	return result


func come_to(target: Vector3) -> void:
	if task != null and task["priority"] >= 3:
		following = false
		return
	var near := nav.nearest(target)
	var sk: bool = cfg["skeptic"]
	run("follow", [
		{"t": "say", "text": pick(["Tô indo, tô indo.", "O que foi agora?"] if sk else ["Já vou, {cat}!", "Tô indo, {cat}..."]), "dur": 2.0, "kind": "call"},
		{"t": "walk", "node": near.id, "style": "hurry"},
		{"t": "wait", "dur": 3.2},
		{"t": "say", "text": pick(["Tá tudo bem aqui... acho.", "Nada. Você me enganou, {cat}.", "O que você queria me mostrar?"]), "dur": 2.4, "kind": "whisper"},
		{"t": "do", "fn": func(): following = false},
		{"t": "spot", "spot": Layout.spot(cfg["bedside_spot"])},
		{"t": "bed"},
	], 2, func(): following = false)


func hear_noise(p: Vector3, loudness: float, hops: int, kind: String) -> void:
	if scripted or not present or _noise_cd > 0:
		return
	var d := p.distance_to(global_position) + hops * 2.5
	var eff := loudness * clampf(1.0 - d / 16.0, 0, 1)
	if eff < 0.12:
		return
	_noise_cd = 5.0
	_noise_at = p + Vector3(0, 0.6, 0)
	_noise_look_t = 4.0
	var cost := 10.0 if kind == "break" else (3.0 if kind == "scratch" else 5.0)
	var sk: bool = cfg["skeptic"]
	if asleep or in_bed:
		asleep = false
		_wake_t = 4.0
		add_patience(-cost * clampf(eff * 1.5, 0.4, 1) * (1.3 if sk else 1.0))
		if fear > 55:
			say(pick(["O que foi isso?!", "Tem alguém aí?"]), 2.4, "scared")
		elif sk:
			say(pick(["Hm? ...Gato idiota.", "Que barulho foi esse? Vou ver."]), 2.6, "annoyed")
		else:
			say(pick(["{cat}! O que você derrubou?", "Sério, {cat}?", "Mas que barulho é esse..."]), 2.6, "annoyed")
		if sk and fear < 45 and task == null:
			var near := nav.nearest(p)
			run("investigate", [
				{"t": "wait", "dur": 1.5},
				{"t": "walk", "node": near.id},
				{"t": "wait", "dur": 2.5},
				{"t": "say", "text": pick(["Ninguém. Só o gato aprontando.", "Nada aqui... estranho."]), "dur": 2.4, "kind": "whisper"},
				{"t": "spot", "spot": Layout.spot(cfg["bedside_spot"])},
				{"t": "bed"},
			], 2)
	else:
		add_patience(-cost * 0.5 * clampf(eff * 1.5, 0.4, 1))
		if kind == "break":
			say(pick(["{cat}!! Era meu copo!", "Ah não... {cat}!"]), 2.4, "annoyed")


func _next_step() -> void:
	if task == null:
		return
	task["idx"] += 1
	task["timer"] = 0.0
	task["started"] = false
	_path = []
	if task["idx"] >= task["steps"].size():
		var done: Callable = task["on_done"]
		task = null
		if done.is_valid():
			done.call()


## a walk along given points (outside the house, where there are no nav nodes)
func _start_points(pts: Array) -> void:
	_start_raw([global_position] + pts)


func _start_path(node_id: String, end = null) -> void:
	_start_raw([global_position] + nav.path_to(global_position, node_id, end))


func _start_raw(raw: Array) -> void:
	_path = _smooth_path(raw)
	_path_len = PackedFloat32Array()
	var acc := 0.0
	_path_len.append(0.0)
	for i in range(1, _path.size()):
		acc += (_path[i] as Vector3).distance_to(_path[i - 1])
		_path_len.append(acc)
	_path_s = 0.0
	_path_i = 0
	_seg_from = global_position
	# a sharp turn from where she faces: turn on the spot first
	_turn_first = false
	if _path.size() > 1:
		var d: Vector3 = _sample_path(0.5) - global_position
		if Vector2(d.x, d.z).length() > 0.05:
			_turn_first = absf(wrapf(atan2(d.x, d.z) - yaw, -PI, PI)) > 1.1


## round each corner of the node line with a quadratic curve (up to 0.4 m on each side). The nodes are
## placed so the straight segments clear the furniture: the radius stays small next to short segments
## and the curve never strays more than r * sin(turn) / 4 (<= 0.1 m) from the straight segments
static func _smooth_path(pts: Array) -> Array:
	var clean: Array = []
	for p in pts:
		if clean.is_empty() or (p as Vector3).distance_to(clean[-1]) > 0.02:
			clean.append(p)
	if clean.size() < 3:
		return clean
	var out: Array = [clean[0]]
	for i in range(1, clean.size() - 1):
		var a: Vector3 = clean[i - 1]
		var b: Vector3 = clean[i]
		var c: Vector3 = clean[i + 1]
		var r := minf(0.4, minf(a.distance_to(b), b.distance_to(c)) * 0.35)
		var p0 := b + (a - b).normalized() * r
		var p2 := b + (c - b).normalized() * r
		for k in 7:
			var u := k / 6.0
			out.append(p0.lerp(b, u).lerp(b.lerp(p2, u), u))
	out.append(clean[-1])
	return out


func _sample_path(s_at: float) -> Vector3:
	if _path.is_empty():
		return global_position
	s_at = clampf(s_at, 0.0, _path_len[_path_len.size() - 1])
	var i := 1
	while i < _path.size() - 1 and _path_len[i] < s_at:
		i += 1
	var l0 := _path_len[i - 1]
	var l1 := _path_len[i]
	var f := (s_at - l0) / maxf(1e-5, l1 - l0)
	return (_path[i - 1] as Vector3).lerp(_path[i], clampf(f, 0.0, 1.0))


func tick(dt: float) -> void:
	_tick_says(dt)
	if visible:
		head_mark.global_position = head_pos()
	_noise_cd -= dt
	_since_fear += dt
	_fear_feed = 0.0
	if purring:
		fear = maxf(0.0, fear - 7.0 * dt)
	elif _since_fear > 2.5:
		fear = maxf(0.0, fear - (1.4 if in_bed else 0.9) * dt)
	if asleep and fear < 25:
		patience = minf(100.0, patience + 0.05 * dt)
	var speed := 0.0
	if paused:
		model.speed = 0.0
		model.update(dt)
		rotation.y = yaw
		return
	if _pause_t > 0:
		_pause_t -= dt
		model.pose = "stand"
		model.speed = 0.0
		model.update(dt)
		rotation.y = yaw
		return
	_turning = false
	if task != null:
		var st: Dictionary = task["steps"][task["idx"]]
		task["timer"] += dt
		match st["t"]:
			"walk", "spot":
				if not task["started"]:
					task["started"] = true
					_style = st.get("style", "normal")
					hypno = _style == "hypno"
					model.style = _style
					if st["t"] == "walk" and st.has("points"):
						_start_points(st["points"])
					elif st["t"] == "walk":
						_start_path(st["node"], st.get("end", null))
					else:
						# a seat (the next step sits down): stop on the floor in front of it, back to it,
						# and let the sit-down clip take the hips back onto the seat
						var sp3 := Layout.v3(st["spot"]["p"])
						var nxt: Dictionary = task["steps"][task["idx"] + 1] if task["idx"] + 1 < task["steps"].size() else {}
						task["seat"] = model.has_clips and str(nxt.get("t", "")) == "pose" and str(nxt.get("pose", "")) in ["sit", "read", "sit_talk"]
						if task["seat"]:
							var floor_y: float = nav.get_node(st["spot"]["node"]).p.y
							var sy: float = st["spot"]["yaw"]
							model.seat_lift = sp3.y - floor_y + float(cfg.get("seat_adj", 0.0))
							model.seat_back = true
							model.seat_deep = float(cfg.get("seat_deep", 0.0))
							sp3 = Vector3(sp3.x, floor_y, sp3.z) + Vector3(sin(sy), 0, cos(sy)) * 0.3
							task["seat_p"] = sp3
						_start_path(st["spot"]["node"], sp3)
					model.pose = "stand"
				var sp := 1.75 if _style == "hurry" else (0.62 if _style == "hypno" else 1.2)
				var total := _path_len[_path_len.size() - 1] if _path.size() > 1 else 0.0
				if _turn_first:
					# turning on the spot: small shuffling steps until she faces the way
					var ahead := _sample_path(0.5) - global_position
					var err := wrapf(atan2(ahead.x, ahead.z) - yaw, -PI, PI)
					yaw += clampf(err, -3.2 * dt, 3.2 * dt)
					speed = 0.35
					if absf(err) < 0.25:
						_turn_first = false
				elif _path_s >= total - 0.001:
					_v = 0.0
					if _path.size() > 0:
						global_position = _path[-1]
					if st["t"] == "spot":
						global_position = task.get("seat_p", Layout.v3(st["spot"]["p"]))
						# turn to face the way the spot wants (sofa, bed...) before the next step
						var want: float = st["spot"]["yaw"]
						task["turn_t"] = task.get("turn_t", 0.0) + dt
						var err2 := wrapf(want - yaw, -PI, PI)
						yaw += clampf(err2, -3.5 * dt, 3.5 * dt)
						if absf(err2) > 0.05 and task["turn_t"] < 1.5:
							_turning = true
							speed = 0.3 if absf(err2) > 0.4 else 0.0
						else:
							yaw = want
					if not _turning:
						task.erase("turn_t")
						task.erase("seat_p")
						_next_step()
				else:
					# accelerate (0 -> 1.2 m/s in ~0.4 s), brake to stop on the end point
					var left := total - _path_s
					var vmax := minf(sp, sqrt(2.0 * 2.6 * left) + 0.15)
					_v = move_toward(_v, vmax, (3.0 if _v < vmax else 6.0) * dt)
					var step := minf(left, _v * dt)
					_path_s += step
					var prev := global_position
					global_position = _sample_path(_path_s)
					# face a point a little ahead on the curve
					var ahead2 := _sample_path(_path_s + 0.6) - global_position
					if Vector2(ahead2.x, ahead2.z).length() > 0.05:
						yaw = lerp_angle(yaw, atan2(ahead2.x, ahead2.z), 1.0 - exp(-7.0 * dt))
					speed = Vector2(global_position.x - prev.x, global_position.z - prev.z).length() / maxf(dt, 1e-4)
					_step_acc += step
					if _step_acc > 0.62:
						_step_acc = 0.0
						stepped.emit(global_position)
					_open_doors_ahead()
			"pose":
				model.pose = st["pose"]
				if not st.has("dur") or task["timer"] >= st["dur"]:
					_next_step()
			"wait":
				if task["timer"] >= st["dur"]:
					_next_step()
			"say":
				say(st["text"], st.get("dur", 3.0), st.get("kind", "normal"))
				_next_step()
			"do":
				(st["fn"] as Callable).call()
				_next_step()
			"until":
				if st.has("pose"):
					model.pose = st["pose"]
				if (st["cond"] as Callable).call() or (st.has("timeout") and task["timer"] >= st["timeout"]):
					_next_step()
			"face":
				yaw = lerp_angle(yaw, st["yaw"], 1.0 - exp(-8.0 * dt))
				if task["timer"] > 0.5:
					_next_step()
			"bed":
				put_in_bed(true)
				_next_step()
			"if":
				# {cond, then: [steps]}: the steps run next only if the condition holds now
				if (st["cond"] as Callable).call():
					var at_i: int = task["idx"] + 1
					for k in (st["then"] as Array).size():
						task["steps"].insert(at_i + k, st["then"][k])
				_next_step()
			"look":
				# {at: point | node | "cat", dur, turn: face it with the body too}
				var at = cat_ref if str(st.get("at", "")) == "cat" else st.get("at")
				if not task["started"]:
					task["started"] = true
					look_for(at, st.get("dur", 1.5))
				if st.get("turn", false):
					var lp = _point_of(at)
					if lp != null:
						yaw = lerp_angle(yaw, atan2((lp as Vector3).x - global_position.x, (lp as Vector3).z - global_position.z), 1.0 - exp(-6.0 * dt))
				if not st.get("wait", true) or task["timer"] >= st.get("dur", 1.5):
					_next_step()
			"anim":
				# {clip: mocap one-shot | gesture: procedural, wait}
				if not task["started"]:
					task["started"] = true
					if st.has("clip"):
						model.play_once(st["clip"])
					else:
						model.gesture(st.get("gesture", ""))
				if not st.get("wait", true) or (task["timer"] > 0.3 and not model.shot_playing() and not model.gesturing()) or task["timer"] > 6.0:
					_next_step()
			"kneel_talk":
				# crouch facing the cat, say something to it, get up
				var tm: float = task["timer"]
				if cat_ref != null:
					var cdir := cat_ref.global_position - global_position
					yaw = lerp_angle(yaw, atan2(cdir.x, cdir.z), 1.0 - exp(-6.0 * dt))
					look_for(cat_ref, 0.5)
				model.pose = "kneel" if tm < float(st.get("dur", 2.5)) + 0.9 else "stand"
				if tm >= 0.9 and not task.get("said", false):
					task["said"] = true
					if st.has("text"):
						say(st["text"], st.get("dur", 2.5), st.get("kind", "normal"))
					model.set_mood("joy", 0.7, float(st.get("dur", 2.5)))
				if tm >= float(st.get("dur", 2.5)) + 1.6:
					task.erase("said")
					_next_step()
	elif in_bed:
		_bed_behaviour(dt)
	if not in_bed:
		model.look_target = _auto_look(dt)
		# standing around, a target out of the neck's reach turns the whole body, in little steps
		# (starts past 0.15 rad and goes on down to 0.02: one threshold flipped the steps on and off
		# every frame, a shiver)
		var walking: bool = task != null and str(task["steps"][task["idx"]]["t"]) in ["walk", "spot"]
		var excess := absf(model.look_yaw)
		_body_turn = not walking and model.pose == "stand" and (excess > 0.15 or (_body_turn and excess > 0.02))
		if _body_turn:
			yaw += clampf(model.look_yaw, -2.0 * dt, 2.0 * dt)
			speed = maxf(speed, 0.3)
	if task == null:
		hypno = false
	model.speed = speed
	# the face follows the mood: ^^ with the cat purring, sad when very afraid
	if purring:
		model.set_mood("eye_joy", 0.8, 0.5)
	elif fear > 70 and not asleep:
		model.set_mood("sorrow", clampf((fear - 70.0) / 25.0, 0.3, 1.0), 0.5)
	model.tremble = (fear - 60.0) / 40.0 if fear > 60 and in_bed else 0.0
	model.eyes_wide = clampf((fear - 40.0) / 50.0, 0, 1) + (1.0 if paralysis else 0.0)
	model.asleep = asleep and in_bed
	model.update(dt)
	rotation.y = yaw


func _bed_behaviour(dt: float) -> void:
	_wake_t -= dt
	_bed_look(dt)
	if force_pose != "":
		model.pose = force_pose
		asleep = force_pose == "lie" and fear < 32
		return
	if paralysis:
		model.pose = "paralysis"
		asleep = false
		return
	var f := fear
	var want := "lie"
	if f < 32 and not purring:
		want = "sitUp" if _wake_t > 0 else "lie"
		if _wake_t <= 0:
			asleep = true
	elif f < 58:
		# awake lying down: now and then she rolls to her side and back
		_side_t -= dt
		if _side_t < 0:
			_on_side = not _on_side
			_side_t = randf_range(6, 10) if _on_side else randf_range(8, 15)
		want = "sitUp" if _wake_t > 0 or purring else ("lieSide" if _on_side else "lie")
		asleep = false
		if not _lamp_done and f > 38:
			_lamp_done = true
			wants_lamp.emit(self)
	elif f < 82:
		want = "sitUp" if purring else "hug"
		asleep = false
		_call_t -= dt
		if _call_t < 0:
			_call_t = randf_range(9, 14)
			if cfg["skeptic"]:
				say(pick(["Gato? ...Isso aí não tá certo.", "Tem alguma coisa aqui, não tem?", "Ô, {cat}... vem pra cá."]), 2.8, "call")
			else:
				say(pick(["{cat}? Cadê você?", "{cat}... vem cá...", "Tem alguém aí?", "{cat}? Você tá vendo isso?"]), 2.8, "call")
	else:
		want = "cry"
		asleep = false
		_call_t -= dt
		if _call_t < 0:
			_call_t = randf_range(7, 11)
			say(pick(["Por favor... por favor...", "Vai embora... vai embora...", "{cat}... me ajuda...", "Isso não é real..."]), 3.0, "scared")
	if purring and f < 32:
		want = "lie"
	model.pose = want


## awake in bed the eyes go to the door and to noises; asleep they rest
func _bed_look(dt: float) -> void:
	_noise_look_t -= dt
	if asleep:
		model.look_target = null
		return
	if _noise_look_t > 0 and _noise_at != null:
		model.look_target = _noise_at
		return
	_look_t -= dt
	if _look_t <= 0:
		_look_t = randf_range(3.0, 7.0)
		_look_door = randf() < 0.6
	model.look_target = _bed_door if _look_door and _bed_door != null else null


func _open_doors_ahead() -> void:
	var fx := sin(yaw)
	var fz := cos(yaw)
	for d: Door in doors:
		if d.def["style"] == "front":
			continue
		var c := d.center()
		if absf(c.y - global_position.y) > 1.2:
			continue
		var dx := c.x - global_position.x
		var dz := c.z - global_position.z
		var dist := Vector2(dx, dz).length()
		if dist < 1.3 and (dx * fx + dz * fz) > -0.2 and d.state != "open" and not d.locked:
			d.set_state("open")
			opened_door.emit(d)
