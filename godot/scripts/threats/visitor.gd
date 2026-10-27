class_name VisitorThreat
extends Threat
## O Visitante: a very tall man in a hat who knocks at night with a familiar voice ("é a mamãe").
## The target goes to open. The only way to be rid of him is for the cat to go outside and hiss at him
## up close: then he may simply vanish (VANISH_ODDS), or he comes for the cat, starting at the cat's
## walking pace and getting faster until he matches its running pace. He only stops once the cat is
## back inside the house; then he touches his hat and is gone.
## At the door he knocks (the arm on the beat) and leans his head on the wood to listen; at a window
## he stands still, arms down; his head follows the voice he fakes. He chases with strides far too
## long and slow.

var entrances: Array = []
var cur = null
var fig: GhostBody
var vis := 0.0
var knock_t := 0.0
var fig_pos := Vector3.ZERO
var fig_yaw := 0.0

const CAT_WALK := 2.1          # the cat's walking and running pace (Cat.tick): the chase goes from one to the other
const CAT_RUN := 4.4
const RAMP_SECS := 14.0        # how long the chase takes to reach the cat's running pace
const VANISH_ODDS := 0.4       # chance that a hiss makes him vanish instead of chase

var _listen_t := 0.0
var _leave_t := -1.0
var _cat_look := 0.0        # 0 its head follows the voice it fakes, 1 it looks at the cat
var _breathed := false


func _init() -> void:
	threat_id = "visitor"
	display_name = "O Visitante"


func setup(world: Game) -> void:
	super.setup(world)
	entrances = [
		{"id": "front", "name": "a porta da frente", "spot": "frontDoor", "knock": Vector3(6.45, 1.2, -0.05), "figure": Vector3(6.45, 0, -0.42), "yaw": 0.0, "door": "d_front"},
		{"id": "sala", "name": "a janela da sala", "spot": "salaWindow", "knock": Vector3(-0.05, 1.5, 2.75), "figure": Vector3(-0.42, -0.9, 2.75), "yaw": PI / 2},
		{"id": "coz", "name": "a janela da cozinha", "spot": "kitchenWindow", "knock": Vector3(12.05, 1.6, 4.35), "figure": Vector3(12.45, -0.9, 4.35), "yaw": -PI / 2},
	]
	fig = GhostBody.new("visitor", Color(0.006, 0.006, 0.008), Color(0.12, 0.13, 0.16), 0.0, Color(0.0, 0.0, 0.0, 0.4), 2.3, Color(1.0, 0.95, 0.85))
	fig.height_scale = 1.18
	fig.limb_stretch = 1.15
	add_child(fig)
	fig.alpha = 0.0
	fig.rig.set_loco_anims("idle", "walk_formal", "walk_formal")


func reset() -> void:
	stage = 0
	t = 0.0
	cur = null
	vis = 0.0
	_leave_t = -1.0
	if fig:
		fig.alpha = 0.0
		fig.rig.style = "normal"
		fig.rig.look_target = null
	if w:
		if target and target.task_name == "visitor":
			target.abort()
		(w.house.doors["d_front"] as Door).set_state("closed")


func on_stage(s: int, _prev: int) -> void:
	if s == 1:
		cur = pick(entrances)
		knock_t = 0.0
		fig_pos = cur["figure"]
		fig_yaw = cur["yaw"]
	if s == 2 and cur:
		knock_t = 0.0
		Sfx.voice(cur["knock"], 10, "call", 1.0)
		get_tree().create_timer(0.3).timeout.connect(func():
			if stage >= 2 and cur:
				w.hint(tr("“Clara... é a mamãe... abre %s...”") % ("a porta" if cur["id"] == "front" else "a janela"), 3.2))
	if s == 3 and cur:
		_send_owner()
	if s == 5 and cur:
		w.sting(0.7)
		target.add_fear(38)
		if cur.has("door"):
			(w.house.doors[cur["door"]] as Door).set_state("open")
		Sfx.shriek(cur["knock"], 0.5)


func _send_owner() -> void:
	target.run("visitor", [
		{"t": "say", "text": pick(["Mãe? A essa hora?", "Quem é...? Mãe?", "Já vai! Calma..."]), "dur": 2.6, "kind": "call"},
		{"t": "spot", "spot": Layout.spot(cur["spot"]), "style": "normal"},
		{"t": "until", "cond": func(): return stage == 0, "pose": "reach"},
	], 3)


static func cat_outside(p: Vector3) -> bool:
	var r := Layout.room_at(p)
	return (r == "" or r == "quintal") and p.y < 1.5


## a burst of knocks, the arm hitting on each one
func _knock(count: int, strength: float) -> void:
	var tt := 0.0
	var e = cur
	for i in count:
		get_tree().create_timer(tt + 0.001).timeout.connect(func():
			if e == cur and stage > 0:
				Sfx.play("knock", e["knock"], 0.9 * strength * randf_range(0.85, 1.0), randf_range(0.95, 1.05), 2.0)
				if e.has("door"):
					fig.rig.beat())
		tt += randf_range(0.22, 0.3) if i % 3 != 2 else 0.55


func on_hunt_start() -> void:
	fig_pos = cur["figure"] if cur else fig.global_position
	fig_yaw = cur["yaw"] if cur else 0.0
	if target.task_name == "visitor":
		target.abort()
		target.go_to_bed(2)
	Sfx.shriek(fig_pos + Vector3(0, 2.0, 0), 0.8)
	w.burst_smoke(fig_pos + Vector3(0, 1.4, 0))


func on_hunt_end() -> void:
	if enabled and _leave_t < 0.0:
		# he gives up: a touch of the hat, then gone
		_leave_t = 1.6
		fig.rig.style = "normal"
		fig.rig.speed = 0.0
		fig.rig.pose = "stand"
		fig.rig.gesture("hat_tip")


func _tick_leave(dt: float) -> void:
	_leave_t -= dt
	fig.global_position = fig_pos
	fig.rotation = Vector3(0, fig_yaw, 0)
	fig.rig.speed = 0.0
	fig.tick(dt)
	if _leave_t <= 0.0:
		_leave_t = -1.0
		w.burst_smoke(fig_pos + Vector3(0, 1.4, 0))
		repel()


func _chase(dt: float) -> void:
	var cp := w.cat.global_position
	if not cat_outside(cp) or hunt_t > 90.0:
		end_hunt()
		return
	# from the cat's walking pace up to its running pace
	var speed := lerpf(CAT_WALK, CAT_RUN, clampf((hunt_t - 1.0) / RAMP_SECS, 0.0, 1.0))
	var dir := Vector3(cp.x - fig_pos.x, 0, cp.z - fig_pos.z)
	var dist := dir.length()
	# startled: it turns and shrieks for a second before it runs, time for the cat to flee
	var startled := hunt_t < 1.0
	if startled:
		fig_yaw = lerp_angle(fig_yaw, atan2(dir.x, dir.z), 1.0 - exp(-6.0 * dt))
	if dist > 0.05 and not startled:
		fig_pos += dir / dist * minf(dist, speed * dt)
		fig_yaw = lerp_angle(fig_yaw, atan2(dir.x, dir.z), 1.0 - exp(-8.0 * dt))
	var g := w.house.ground_height(fig_pos.x, fig_pos.z, cp.y + 1.0)
	if g > -500:
		fig_pos.y = g
	fig.alpha = 0.95
	fig.global_position = fig_pos
	fig.rotation = Vector3(0, fig_yaw, 0)
	fig.rig.pose = "stand"
	fig.rig.style = "stalk"
	fig.rig.speed = 0.0 if startled else speed
	fig.rig.look_target = cp + Vector3(0, 0.2, 0)
	fig.tick(dt)
	if randf() < dt * 1.3:
		Sfx.human_step(fig_pos, false)
	if not startled:
		try_catch(fig_pos, 0.7)


func tick(dt: float) -> void:
	if _leave_t >= 0.0:
		_tick_leave(dt)
		return
	if hunting_cat:
		_chase(dt)
		return
	var e = cur
	if e == null:
		return
	knock_t -= dt
	# looking at the cat it falls silent, and breathes once against the glass
	if _cat_look > 0.5:
		knock_t = maxf(knock_t, 0.6)
		if not _breathed:
			_breathed = true
			Sfx.breath(e["knock"] + Vector3(0, 0.3, 0), 0.5)
	elif _cat_look <= 0.0:
		_breathed = false
	if stage <= 2 and knock_t <= 0:
		knock_t = d(3.2) if stage == 1 else d(2.2)
		_knock(3, 0.4 if stage == 1 else 1.0)
		_listen_t = 1.4
	if stage == 1 and t > d(8):
		set_stage(2)
	elif stage == 2 and t > d(9):
		set_stage(3)
	elif stage == 3:
		if target.task_name != "visitor":
			if t > d(7):
				t = 0.0
				_send_owner()
		elif target.global_position.distance_to(Layout.spot_pos(e["spot"])) < 0.3 and may_attack:
			set_stage(4)
			target.say("Já vai, mãe... só um segundo...", 2.6, "call")
		if randf() < dt * 0.4:
			_knock(2, 0.7)
			_listen_t = 1.2
	elif stage == 4:
		target.add_fear(1.5 * dt)
		if t > d(3.2 if target.cfg["skeptic"] else 6.0):
			set_stage(5)
		if target.task_name != "visitor":
			set_stage(3)
	elif stage == 5:
		target.add_fear(8.0 * dt)
	vis = lerpf(vis, 1.0 if stage >= 2 else 0.0, 1.0 - exp(-2.0 * dt))
	fig.alpha = 0.95 * vis
	var fp: Vector3 = e["figure"]
	if stage >= 5 and e.has("door"):
		fp = fp.lerp(Vector3(6.45, 0, 0.3), 0.5)
	fig_pos = fp
	fig_yaw = e["yaw"]
	fig.global_position = fp
	fig.rotation = Vector3(0, e["yaw"], 0)
	fig.rig.style = "normal"
	fig.rig.speed = 0.0
	# at the door: knock, then the head on the wood, listening; at a window: pressed on the glass
	_listen_t -= dt
	if not e.has("door"):
		fig.rig.pose = "stand"   # at a window he only stands there, arms down
	elif stage >= 4:
		fig.rig.pose = "loom"
	else:
		fig.rig.pose = "listen" if _listen_t < 0.0 and stage >= 2 else "knock"
	# the head follows the voice it fakes: toward whoever it is calling
	var lt: Vector3 = e["knock"]
	if stage >= 2 and target and target.present:
		var tp := target.head_pos()
		lt += Vector3(tp.x - lt.x, 0, tp.z - lt.z).limit_length(1.2)
	# ...until the cat comes close: then it stops calling for a moment and looks down at the cat
	var cp := w.cat.global_position
	var k: Vector3 = e["knock"]
	var near := Vector2(cp.x - k.x, cp.z - k.z).length() < 3.2 and absf(cp.y - Layout.spot_pos(e["spot"]).y) < 1.6
	_cat_look = move_toward(_cat_look, 1.0 if near and stage >= 2 else 0.0, dt * (0.7 if near else 1.5))
	if _cat_look > 0.0:
		lt = lt.lerp(cp + Vector3(0, 0.25, 0), smoothstep(0.0, 1.0, _cat_look))
	fig.rig.look_target = lt
	fig.tick(dt)


## only from outside, up close to him
func can_hiss(p: Vector3) -> bool:
	if hunting_cat or cur == null or stage < 2 or not cat_outside(p):
		return false
	var k: Vector3 = cur["knock"]
	return p.distance_to(Vector3(k.x, p.y, k.z)) < 3.0 and absf(p.y - Layout.spot_pos(cur["spot"]).y) < 1.6


func describe_death() -> Dictionary:
	return {
		"title": tr("%s abriu a porta") % target.display_name,
		"why": tr("O Visitante imitou uma voz conhecida, %s foi atender e deixou entrar o que estava lá fora.") % target.display_name,
		"tip": "Saia de casa e bufe para ele de perto. Se ele perseguir, corra para dentro de casa.",
	}


func on_hiss(p: Vector3, strong: bool) -> bool:
	if hunting_cat or not strong or not can_hiss(p):
		return false
	w.shake(0.5)
	# he does not like it: off the door and after the cat, faster and faster, until it is back indoors
	# (or, with some luck, he just goes; also when another ghost already hunts the cat)
	if randf() >= VANISH_ODDS and start_hunt():
		w.hint("Ele vem atrás de você! Corra para dentro de casa!", 3.6)
		return true
	var was := target.task_name == "visitor"
	Sfx.shriek(cur["knock"], 0.6)
	w.burst_smoke(fig.global_position + Vector3(0, 1.4, 0))
	repel()
	if was:
		target.add_fear(6)
		target.say(pick(["...Foi embora? Mãe?", "Ninguém... não tem ninguém aí.", "{cat}, você bufou pra quem?"]), 2.8, "scared")
		target.go_to_bed(2)
	return true


func focus():
	if hunting_cat:
		return fig_pos + Vector3(0, 1.5, 0)
	if cur == null or stage == 0:
		return null
	return cur["knock"]


func entity():
	if hunting_cat or _leave_t >= 0.0:
		return fig_pos
	return cur["knock"] if cur != null and stage >= 2 else null
