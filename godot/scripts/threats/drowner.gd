class_name DrownerThreat
extends Threat
## A Afogadora (Dona Ivone, who drowned in this house): comes through the water, then WALKS.
## 1-2 a faucet drips, then runs and the basin overflows (close it to banish her). 3 the puddle
## spreads and arms rise from it. 4 she rises and walks toward her target leaving wet footprints and
## slippery puddles; she hunts by sound (knock something over to lure her) and melts as she walks.
## 5 cold hands on the person. Port of Drowner.ts.
## She is blind. A cat that steps in her water (the overflowing puddle or her wet footprints) splashes:
## she turns and follows the cat's wet paw prints. They dry in ~8 s, or at once on a rug; with no
## trail left she goes back to her target. Walking still melts her, so leading her around ends her.

var source = null     # House.Faucet
var water = null
var drip_t := 0.0
var hands: GhostBody
var hands_vis := 0.0
var body: GhostBody
var pos := Vector3.ZERO
var yaw := 0.0
var essence := 100.0
var path: Array = []
var pi := 0
var seg_from := Vector3.ZERO
var lure = null
var lure_t := 0.0
var lure_wait := 0.0
var step_acc := 0.0
var repath_t := 0.0
var body_vis := 0.0
var feet: Array = []   # [Decal, life]
var foot_i := 0
var closed_by_cat := false
var cold_t := 0.0
var drips: GPUParticles3D
var _last := Vector3.ZERO
var cat_wet := 0.0          # seconds the cat's paws stay wet
var paws: Array = []        # [Decal, life] the cat's wet prints
var paw_i := 0
var trail: Array = []       # [{p, life}] newest last: what she follows
var _paw_acc := 0.0
var _last_cat := Vector3.ZERO
var _hunt_goal := Vector3.ZERO
var _hunt_repath := 0.0

const WET_SECS := 8.0
const HUNT_SPEED := 1.6     # never faster than the cat walking (Cat.walk_speed, 2.1)


func _init() -> void:
	threat_id = "drowner"
	display_name = "A Afogadora"


func setup(world: Game) -> void:
	super.setup(world)
	var wet_col := Color(0.03, 0.06, 0.07)
	# a cold sea-green rim: in a dark kitchen the drowned woman has to read against the grey floor
	body = GhostBody.new("ivone", wet_col, Color(0.2, 0.46, 0.52), 1.0, Color(0.15, 0.25, 0.3, 0.25), 1.7)
	add_child(body)
	body.alpha = 0.0
	hands = GhostBody.new("ivone", wet_col, Color(0.24, 0.5, 0.56), 1.0, Color(0.2, 0.3, 0.35, 0.15), 0.5)
	add_child(hands)
	hands.alpha = 0.0
	drips = FX.drip()
	add_child(drips)
	var tex: Texture2D = load("res://assets/textures/gen/footprint.png")
	for i in 28:
		var dc := Decal.new()
		dc.texture_albedo = tex
		dc.size = Vector3(0.12, 0.2, 0.2)
		dc.modulate = Color(0.02, 0.04, 0.05, 0.0)
		dc.albedo_mix = 1.0
		dc.visible = false
		add_child(dc)
		feet.append([dc, 0.0])
	for i in 24:
		var pc := Decal.new()
		pc.texture_albedo = tex
		pc.size = Vector3(0.06, 0.2, 0.09)
		pc.modulate = Color(0.02, 0.04, 0.05, 0.0)
		pc.albedo_mix = 1.0
		pc.visible = false
		add_child(pc)
		paws.append([pc, 0.0])


func reset() -> void:
	stage = 0
	t = 0.0
	if w:
		for f in w.house.faucets:
			f.running = 0.0
	source = null
	if water:
		water.stop(0.6)
	water = null
	if hands:
		hands.alpha = 0.0
	hands_vis = 0.0
	if body:
		body.alpha = 0.0
	body_vis = 0.0
	essence = 100.0
	lure = null
	path = []
	closed_by_cat = false
	if target and target.task_name == "drown":
		target.abort()


func dry_all() -> void:
	for f in w.house.faucets:
		f.level = 0.0
		f.puddle = 0.0
		f.running = 0.0
	for ft in feet:
		ft[1] = 0.0
		(ft[0] as Decal).visible = false
	for pw in paws:
		pw[1] = 0.0
		(pw[0] as Decal).visible = false
	trail.clear()
	cat_wet = 0.0


func on_stage(s: int, _prev: int) -> void:
	if s == 1:
		var opts := []
		for f in w.house.faucets:
			if f != source:
				opts.append(f)
		source = pick(opts if not opts.is_empty() else w.house.faucets)
		drip_t = 0.0
	if s == 2 and source:
		source.running = 1.0
		water = Sfx.loop("water", source.spout, 0.7)
		water.set_level(0.6)
		Sfx.creak(source.handle, 0.25, 0.5, 2.2)
	if s == 4 and source:
		pos = Vector3(source.puddle_center.x, source.floor_y, source.puddle_center.z)
		essence = 100.0
		yaw = 0.0
		body_vis = 0.0
		path = []
		pi = 0
		_repath()
		Sfx.thud(pos + Vector3(0, 0.3, 0), 0.4, 50)
		Sfx.breath(pos + Vector3(0, 1.5, 0), 0.5)
		w.hint("Algo molhado saiu da água e está andando.", 3.5)
	if s == 5:
		w.sting(0.5)
		Sfx.shriek(pos + Vector3(0, 1.4, 0), 0.3)


func close_faucet(f) -> void:
	if stage >= 1 and stage <= 3 and f == source:
		closed_by_cat = true
	f.running = 0.0
	Sfx.creak(f.handle, 0.2, 0.4, 2.4)
	if f == source and water:
		water.stop(0.5)


func hear_noise(p: Vector3, loud: float) -> void:
	if not enabled or stage < 4 or loud < 0.22:
		return
	if w.hops(p, pos) > 4:
		return
	lure = p
	lure_t = 14.0
	lure_wait = 0.0
	_repath()


func _destination() -> Vector3:
	if lure != null and lure_t > 0:
		return lure
	return w.house.nav.get_node(target.cfg["bed_node"]).p if target.in_bed else target.global_position


func _repath() -> void:
	var nav := w.house.nav
	var nodes := nav.route_from(pos, nav.nearest(_destination()), false)
	path = []
	for n in nodes:
		path.append(n.p)
	if path.size() > 1:
		if pos.distance_to(path[1]) < (path[0] as Vector3).distance_to(path[1]) and absf(pos.y - (path[0] as Vector3).y) < 0.6 or NavGraph.on_first_leg(pos, path[0], path[1]):
			path.pop_front()
	pi = 0
	seg_from = pos


func _walk(dt: float, speed: float) -> bool:
	if pi >= path.size():
		return true
	var tg: Vector3 = path[pi]
	var dx := tg.x - pos.x
	var dz := tg.z - pos.z
	var dist := Vector2(dx, dz).length()
	if dist < 0.1:
		pi += 1
		seg_from = pos
		return pi >= path.size()
	var step := minf(dist, speed * dt)
	pos.x += dx / dist * step
	pos.z += dz / dist * step
	var seg_len := Vector2(tg.x - seg_from.x, tg.z - seg_from.z).length()
	var done := 1.0 - dist / seg_len if seg_len > 1e-3 else 1.0
	pos.y = seg_from.y + (tg.y - seg_from.y) * clampf(done, 0, 1)
	yaw = lerp_angle(yaw, atan2(dx, dz), 1.0 - exp(-6.0 * dt))
	essence -= step * 3.0
	step_acc += step
	if step_acc > 0.55:
		step_acc = 0.0
		_place_foot()
		Sfx.drip(pos + Vector3(0, 0.1, 0))
	return false


func _place_foot() -> void:
	var ft: Array = feet[foot_i % feet.size()]
	foot_i += 1
	ft[1] = 14.0
	var dc: Decal = ft[0]
	dc.visible = true
	var ground := w.house.ground_height(pos.x, pos.z, pos.y + 0.4)
	var side := 1.0 if foot_i % 2 else -1.0
	dc.global_position = Vector3(pos.x + cos(yaw) * 0.08 * side, (ground if ground > -500 else pos.y) + 0.02, pos.z - sin(yaw) * 0.08 * side)
	dc.rotation = Vector3(0, yaw, 0)


func wet_at(p: Vector3) -> float:
	var wet := 0.0
	for f in w.house.faucets:
		if f.puddle < 0.05 or absf(p.y - f.floor_y) > 0.6:
			continue
		var r: float = f.puddle * 1.4
		var dd := Vector2(p.x - f.puddle_center.x, p.z - f.puddle_center.z).length()
		if dd < r:
			wet = maxf(wet, clampf(1.0 - dd / r, 0, 1) * 0.6 + 0.4)
	if stage >= 4 and body_vis > 0.3 and absf(p.y - pos.y) < 0.6:
		if Vector2(p.x - pos.x, p.z - pos.z).length() < 1.0:
			wet = maxf(wet, 0.8)
	return wet


func tick(dt: float) -> void:
	var src = source
	if src == null:
		return
	if closed_by_cat or (stage >= 2 and stage <= 3 and src.running <= 0.01):
		closed_by_cat = false
		_banish(false)
		return
	if stage == 1:
		drip_t -= dt
		if drip_t <= 0:
			drip_t = 0.5 + randf() * 0.7
			Sfx.drip(src.spout)
			src.running = 0.06
			drips.global_position = src.spout
			drips.emitting = true
		if t > d(10):
			set_stage(2)
	elif stage == 2:
		src.level = minf(1.0, src.level + dt / d(16))
		if src.level >= 1.0:
			set_stage(3)
	elif stage == 3:
		src.puddle = minf(1.0, src.puddle + dt / d(14))
		target.add_fear(0.3 * dt)
		if src.puddle >= 1.0 and may_attack:
			set_stage(4)
	elif stage >= 4:
		_update_walker(dt)
	# arms rising from the overflowing water
	var hand_target := 1.0 if stage >= 3 and stage < 4 else 0.0
	hands_vis = lerpf(hands_vis, hand_target, 1.0 - exp(-2.0 * dt))
	hands.alpha = 0.55 * hands_vis
	if hands_vis > 0.02:
		var base_y: float = src.bottom_y if src.id == "tub" else src.floor_y
		var c: Vector3 = src.puddle_center if src.id != "tub" else Vector3(10.9, 0, 9.55)
		hands.global_position = Vector3(c.x, base_y - 1.62 + hands_vis * 0.45 + sin(Time.get_ticks_msec() * 0.002) * 0.03, c.z)
		hands.rig.pose = "arms_up"
		hands.tick(dt)


func _update_walker(dt: float) -> void:
	var tgt := target
	lure_t -= dt
	cold_t -= dt
	var at_target := pos.distance_to(tgt.global_position) < 2.0 and absf(pos.y - tgt.global_position.y) < 1.5
	_track_cat(dt)
	if hunting_cat:
		_hunt(dt)
	elif lure != null and lure_t > 0:
		var arrived: bool = pos.distance_to(lure) < 1.2 or pi >= path.size()
		if arrived:
			lure_wait += dt
			yaw += sin(lure_wait * 2.0) * dt
			if lure_wait > 3.5:
				lure = null
				_repath()
		else:
			_walk(dt, 0.8 * w.threat_speed)
	else:
		repath_t -= dt
		if repath_t <= 0:
			repath_t = 2.5
			_repath()
		if stage == 4:
			var done := _walk(dt, 0.72 * w.threat_speed)
			if done or at_target:
				set_stage(5)
			tgt.add_fear((2.2 if Layout.room_at(pos) == Layout.room_at(tgt.global_position) else 0.35) * dt)
		elif stage == 5:
			tgt.add_fear(9.5 * dt)
			yaw = lerp_angle(yaw, atan2(tgt.global_position.x - pos.x, tgt.global_position.z - pos.z), 1.0 - exp(-4.0 * dt))
			if not at_target:
				set_stage(4)
			if cold_t <= 0:
				cold_t = 3.2
				Sfx.breath(pos + Vector3(0, 1.4, 0), 0.5)
	if source and source.running > 0.05:
		essence = minf(100.0, essence + 4.0 * dt)
	if essence <= 0:
		_banish(true)
		return
	body_vis = lerpf(body_vis, 1.0, 1.0 - exp(-1.5 * dt))
	body.alpha = 0.86 * body_vis * clampf(0.35 + essence / 100.0, 0, 1)
	var sp := (pos - _last).length() / maxf(dt, 1e-4)
	_last = pos
	body.global_position = pos
	body.rotation.y = yaw
	body.rig.speed = sp
	body.rig.style = "hypno"
	body.rig.pose = "reach" if stage == 5 or hunting_cat else "stare"
	body.tick(dt)
	drips.global_position = pos + Vector3(0, 1.2, 0)
	drips.emitting = true


# ---------------------------------------------------------------------- the cat's wet paws


## the cat stepped in the overflow puddle or on one of her fresh footprints
func _cat_in_water(p: Vector3) -> bool:
	for f in w.house.faucets:
		if f == source and f.puddle > 0.3 and absf(p.y - f.floor_y) < 0.6:
			if Vector2(p.x - f.puddle_center.x, p.z - f.puddle_center.z).length() < f.puddle * 1.2:
				return true
	for ft in feet:
		if ft[1] > 3.0:
			var fp: Vector3 = (ft[0] as Decal).global_position
			if absf(fp.y - p.y) < 0.5 and Vector2(p.x - fp.x, p.z - fp.z).length() < 0.22:
				return true
	return false


static func _on_rug(p: Vector3) -> bool:
	for r in Layout.data().get("RUGS", []):
		if p.x > r[0] and p.x < r[2] and p.z > r[1] and p.z < r[3] and absf(p.y - r[4]) < 0.3:
			return true
	return false


func _track_cat(dt: float) -> void:
	var cat := w.cat
	var cp := cat.global_position
	if stage >= 4 and cat.mode != "hidden" and _cat_in_water(cp):
		if cat_wet < WET_SECS - 1.0:
			# splash: loud enough for her to turn
			Sfx.drip(cp + Vector3(0, 0.05, 0))
			Sfx.thud(cp, 0.18, 320)
		cat_wet = WET_SECS
		if not hunting_cat and not w.cat_safe():
			if start_hunt():
				Sfx.breath(pos + Vector3(0, 1.5, 0), 0.8)
	if cat_wet > 0:
		cat_wet -= dt
		if _on_rug(cp) and cat_wet > 0.5:
			cat_wet = 0.0
			Sfx.creak(cp, 0.12, 0.5, 2.5)
			w.hint_once("rug_dry", "Patas secas no tapete: a trilha acabou.", 3.0)
		var moved := Vector2(cp.x - _last_cat.x, cp.z - _last_cat.z).length()
		_paw_acc += moved
		if _paw_acc > 0.28 and cat.mode != "hidden":
			_paw_acc = 0.0
			_place_paw(cp, cat.yaw)
	_last_cat = cp
	for i in range(trail.size() - 1, -1, -1):
		trail[i]["life"] -= dt
		if trail[i]["life"] <= 0:
			trail.remove_at(i)


func _place_paw(cp: Vector3, cyaw: float) -> void:
	var pw: Array = paws[paw_i % paws.size()]
	paw_i += 1
	var life := clampf(cat_wet, 2.0, WET_SECS)
	pw[1] = life
	var dc: Decal = pw[0]
	dc.visible = true
	var ground := w.house.ground_height(cp.x, cp.z, cp.y + 0.3)
	dc.global_position = Vector3(cp.x, (ground if ground > -500 else cp.y) + 0.02, cp.z)
	dc.rotation = Vector3(0, cyaw, 0)
	trail.append({"p": cp, "life": life})


func on_hunt_start() -> void:
	if stage == 5:
		set_stage(4)
	lure = null
	_hunt_repath = 0.0
	w.hint_once("paws", "A Afogadora ouviu o respingo e segue as suas pegadas molhadas. Corra até secarem ou seque as patas num tapete.", 6)


func on_hunt_end() -> void:
	if enabled and stage >= 4:
		_repath()


## follows the newest wet paw print; with no trail left she loses the cat
func _hunt(dt: float) -> void:
	if trail.is_empty():
		end_hunt()
		return
	var goal: Vector3 = trail[trail.size() - 1]["p"]
	_hunt_repath -= dt
	if pi >= path.size() or (_hunt_repath <= 0 and goal.distance_to(_hunt_goal) > 0.6):
		_hunt_repath = 0.7
		_hunt_goal = goal
		var nav := w.house.nav
		var nodes := nav.route_from(pos, nav.nearest(goal), false)
		path = []
		for n in nodes:
			path.append(n.p)
		if path.size() > 1 and NavGraph.on_first_leg(pos, path[0], path[1]):
			path.pop_front()
		# skip nodes behind her: head for the first one that brings her closer
		while path.size() > 0 and pos.distance_to(goal) < (path[0] as Vector3).distance_to(goal) + 0.3 and absf(pos.y - goal.y) < 0.6:
			path.pop_front()
		path.append(goal)
		pi = 0
		seg_from = pos
	_walk(dt, minf(HUNT_SPEED * clampf(w.threat_speed, 0.85, 1.15), w.cat.walk_speed()))
	try_catch(pos, 0.7)


func _fade_foot(ft: Array, dt: float) -> void:
	if ft[1] <= 0:
		return
	ft[1] -= dt
	var dc: Decal = ft[0]
	dc.modulate.a = clampf(ft[1] / 4.0, 0, 1) * 0.6
	if ft[1] <= 0:
		dc.visible = false


func _banish(melted: bool) -> void:
	var at: Vector3 = pos + Vector3(0, 1, 0) if stage >= 4 else source.spout
	Sfx.shriek(at, 0.4)
	if melted:
		source.puddle = maxf(source.puddle, 0.5)
		Sfx.thud(pos + Vector3(0, 0.2, 0), 0.4, 60)
		w.burst_smoke(pos + Vector3(0, 0.6, 0), Color(0.3, 0.45, 0.5, 0.4))
	var was_near := stage >= 5
	repel()
	body.alpha = 0.0
	drips.emitting = false
	if was_near:
		target.add_fear(4)
		target.say(pick(["Ah! Tava tão gelado... mas passou.", "Foi só um pesadelo... molhado.", "{cat}... obrigada." if target.cfg["id"] == "clara" else "{cat}... valeu."]), 3.0, "scared")


func can_hiss(p: Vector3) -> bool:
	return stage >= 4 and p.distance_to(pos) < 2.6 and absf(p.y - pos.y) < 1.4


func on_hiss(p: Vector3, strong: bool) -> bool:
	if not strong or not can_hiss(p):
		return false
	essence -= 38.0
	Sfx.shriek(pos + Vector3(0, 1.3, 0), 0.3)
	if stage == 5:
		set_stage(4)
	pi = maxi(0, pi - 1)
	lure = null
	stall = d(3.5)
	w.shake(0.3)
	return true


func tick_threat(dt: float) -> void:
	super.tick_threat(dt)
	for ft in feet:
		_fade_foot(ft, dt)
	for pw in paws:
		_fade_foot(pw, dt)
	if not w:
		return
	for f in w.house.faucets:
		if f.running <= 0.05 and (stage == 0 or f != source):
			f.level = maxf(0.0, f.level - dt * 0.03)
			f.puddle = maxf(0.0, f.puddle - dt * 0.01)
	if stage == 0 or stage >= 4:
		if stage == 0:
			drips.emitting = false


func focus():
	if source == null or stage == 0:
		return null
	return pos + Vector3(0, 1, 0) if stage >= 4 else source.spout


func entity():
	if stage >= 4 and body_vis > 0.2:
		return pos
	return hands.global_position if stage >= 3 else null


var running_faucet:
	get:
		return source if stage >= 1 and stage <= 4 else null


func urgency() -> float:
	if stage >= 4:
		return 0.5 + (stage - 4) * 0.35
	return stage / 5.0


func describe_death() -> Dictionary:
	return {
		"title": tr("%s foi levado(a) pela Afogadora") % target.display_name,
		"why": "A Afogadora saiu da poça, atravessou a casa deixando pegadas molhadas e agarrou a pessoa com mãos geladas.",
		"tip": "Feche a torneira que abre sozinha antes de a poça crescer. Se ela já saiu, faça barulho longe (derrube um copo) para atraí-la, ou bufe de perto: ela derrete ao andar.",
	}
