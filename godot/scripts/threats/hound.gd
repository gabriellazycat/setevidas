class_name Hound
extends Node3D
## O Cão Fantasma: the cat's own enemy. It hunts the *cat*, never the people. A rare, telegraphed
## presence (signs -> hunt -> short chase) on a budget set by the Director, so the game never turns
## into "just run". The cat can hide, climb onto furniture, use the duct / window, or hiss it away
## at close range. Being caught never kills: the cat is flung, dazed and drained. Port of Hound.ts.

signal caught(hound)

## it prowls the house slowly, sniffing; when it sees the cat it stops and barks, then runs after it
## at the cat's walking pace (a running cat gets away). Up on furniture out of its reach, it barks
## at it for a few seconds and fades away, to turn up somewhere else later.
const PATROL_SPEED := 0.8
const CHASE_SPEED := 2.1
const ALERT_SECS := 1.1
const BARK_UP_SECS := 3.0
const PATROL_MAX := 80.0

enum S { ABSENT, TRACKING, HUNTING, CHASING, LURKING, SEARCHING, RECOIL }

var w: Game
var body: HoundBody
var state := S.ABSENT
var enabled := false
var pos := Vector3(0, -50, 0)
var yaw := 0.0
var may_hunt := true   # the Director clears this while a ghost is attacking someone
var night := 1
var hunts_done := 0
var max_hunts := 3
var cooldown := 40.0
var hunt_time := 0.0
var catches := 0

var _state_t := 0.0
var _awareness := 0.0
var _last_known := Vector3.ZERO
var _path: Array = []
var _pi := 0
var _seg_from := Vector3.ZERO
var _vis := 0.0
var _growl_t := 0.0
var _sniff_t := 0.0
var _claws_t := 0.0
var _windup := 0.0
var _lunge := 0.0
var _lunge_cd := 0.0
var _lost_t := 0.0
var _immune := 0.0
var _give_up_t := -1.0
var _repath_t := 0.0
var _pause_t := 0.0
var _snarl_t := 0.0   # stands and snarls before running at the cat: time to react
var _speed := 0.0
var _probe := ShapeCast3D.new()
var _straight := false   # running straight at the cat (nothing solid in between) rather than by the route


func setup(world: Game) -> void:
	w = world
	body = HoundBody.new()
	add_child(body)
	body.alpha = 0.0
	body.visible = false


# ---------------------------------------------------------------------- control


func start_night(n: int, speed_scale := 1.0) -> void:
	night = n
	enabled = true
	hunts_done = 0
	hunt_time = 0.0
	catches = 0
	max_hunts = 3 if n <= 4 else 4
	cooldown = (40.0 if n == 2 else 55.0) / speed_scale + randf_range(0, 14)
	_set_state(S.ABSENT)


## ready to come in (its cooldown is over, it has hunts left tonight) but not in the house yet
func waiting() -> bool:
	return enabled and state == S.ABSENT and cooldown <= 0.0 and hunts_done < max_hunts


func stop() -> void:
	enabled = false
	_set_state(S.ABSENT)
	body.visible = false


## how hunted the cat should feel, 0..1
func threat_level() -> float:
	match state:
		S.TRACKING:
			return clampf(0.12 + _awareness * 0.4, 0, 1)
		S.HUNTING:
			return 0.65
		S.CHASING:
			return 1.0
		S.LURKING:
			return 0.85
		S.SEARCHING:
			return 0.4
	return 0.0


var active: bool:
	get:
		return state != S.ABSENT

var hunting: bool:
	get:
		return state == S.HUNTING or state == S.CHASING or state == S.LURKING


## the dog goes up and down the stairs like the people: the whole house (not the attic) is its ground
func _can_climb() -> bool:
	return true


func _set_state(s: int) -> void:
	var prev := state
	state = s
	_state_t = 0.0
	_lost_t = 0.0
	if s == S.ABSENT:
		pos = Vector3(0, -50, 0)
		_path = []
	if s == S.TRACKING:
		_awareness = 0.0
		w.director.woke("hound")
		_spawn()
		w.introduce("hound")
	if s == S.HUNTING and prev != S.HUNTING:
		# seen: it stops dead and barks at the cat, then comes
		hunts_done += 1
		_windup = ALERT_SECS
		Sfx.bark(pos + Vector3(0, 0.6, 0), 1.0)
		w.sting(0.35)
		w.shake(0.25)
	if s == S.CHASING:
		_snarl_t = 0.0
	if s == S.LURKING:
		_growl_t = 0.0


func _leave(extra := 0.0) -> void:
	cooldown = randf_range(25, 40) + extra
	_set_state(S.ABSENT)


## gone in a puff where it stands (it turns up again somewhere else after the cooldown)
func _vanish() -> void:
	w.burst_smoke(pos + Vector3(0, 0.4, 0), Color(0.05, 0.05, 0.06, 0.7))
	Sfx.growl(pos + Vector3(0, 0.4, 0), 0.5, 0.6)
	_leave()


## something more urgent is happening, or the cat is safe: retreat quickly
func give_up() -> void:
	if hunting and _give_up_t < 0:
		_give_up_t = 2.2


func pause_for(sec: float) -> void:
	cooldown = maxf(cooldown, sec)


# ---------------------------------------------------------------------- sensing


func hear_noise(p: Vector3, loud: float, kind: String) -> void:
	if not enabled or state == S.ABSENT or state == S.RECOIL:
		return
	var dd := pos.distance_to(p)
	var reach := 10.0 if state == S.TRACKING else 18.0
	if dd > reach:
		return
	var cat := w.cat
	var gain: float = loud * float({"run": 0.5, "meow": 0.9, "break": 1.6, "thud": 0.9}.get(kind, 0.6))
	if state == S.TRACKING:
		if cat.mode != "hidden":
			_awareness += gain * (1.0 - dd / (reach + 2.0)) * 0.9
		_last_known = p
	elif state == S.SEARCHING or state == S.HUNTING:
		_last_known = p
		_lost_t = 0.0
		if state == S.SEARCHING:
			state = S.HUNTING
			_state_t = 0.0
			_windup = 0.4
			_go(_last_known)
	elif state == S.LURKING:
		_state_t = maxf(0.0, _state_t - 1.0)


func _los() -> bool:
	var cat := w.cat
	if cat.mode == "hidden":
		return false
	if absf(pos.y - cat.global_position.y) > 2.2:
		return false
	return not w.house.blocked(pos + Vector3(0, 0.47, 0), cat.global_position + Vector3(0, 0.2, 0))


## the cat is on something tall: the hound cannot reach it
func _cat_is_high() -> bool:
	var cp := w.cat.global_position
	var room := Layout.room_at(cp)
	if room == "":
		return false
	return cp.y - Layout.floor_of(room) > 0.62


# ---------------------------------------------------------------------- movement


func _spawn() -> void:
	var nav := w.house.nav
	var cp := w.cat.global_position
	var cat_room := Layout.room_at(cp)
	var cands := []
	# far from the cat first (>= 12 m); relax to 8 m if the house offers nothing that far
	for min_d in [12.0, 8.0]:
		for n: NavGraph.NavNode in nav.nodes.values():
			if n.p.y > 2.5 and not _can_climb():
				continue
			if n.room == "sotao" or n.room == cat_room or n.p.distance_to(cp) < min_d:
				continue
			cands.append(n)
		if cands.size() > 0:
			break
	var pk: NavGraph.NavNode = cands[randi() % cands.size()] if cands.size() > 0 else nav.get_node("b_porao_mid")
	pos = pk.p
	yaw = atan2(cp.x - pos.x, cp.z - pos.z)
	_last_known = cp
	_pick_patrol()


## wander to another node of the house; now and then drift toward the cat's part of it
func _pick_patrol() -> void:
	var nav := w.house.nav
	var cp := w.cat.global_position
	var climb := _can_climb()
	var cands := []
	for n: NavGraph.NavNode in nav.nodes.values():
		if n.room == "sotao" or (n.p.y > 2.5 and not climb):
			continue
		if n.p.distance_to(pos) < 4.0:
			continue
		cands.append(n)
	if cands.is_empty():
		_path = []
		return
	var pick: NavGraph.NavNode = cands[randi() % cands.size()]
	if randf() < 0.35:
		var best := INF
		for n: NavGraph.NavNode in cands:
			var dc := n.p.distance_to(cp)
			if dc > 5.0 and dc < best:
				best = dc
				pick = n
	_go(pick.p)


func _go(dest: Vector3) -> void:
	var nav := w.house.nav
	var a := nav.nearest(pos)
	var b := nav.nearest(dest)
	var climb := _can_climb()
	var nodes := nav.route(a, b, false, func(n: NavGraph.NavNode) -> float: return 400.0 if n.p.y > 2.5 and not climb else 0.0)
	if not climb:
		for i in nodes.size():
			if (nodes[i] as NavGraph.NavNode).p.y > 2.5:
				nodes = nodes.slice(0, i)
				break
	_path = []
	for n: NavGraph.NavNode in nodes:
		_path.append(n.p)
	if _path.size() > 0 and (_path[-1] as Vector3).distance_to(b.p) < 0.05 and dest.y - b.p.y < 1.5 and (climb or dest.y < 2.5):
		_path.append(Vector3(dest.x, b.p.y, dest.z))
	# skip a first node that lies behind us
	if _path.size() > 1:
		var d0 := pos.distance_to(_path[1])
		var d01 := (_path[0] as Vector3).distance_to(_path[1])
		if d0 < d01 and absf(pos.y - (_path[0] as Vector3).y) < 0.6:
			_path.pop_front()
	_pi = 0
	_seg_from = pos


## follow the current path; true when it is finished
func _follow(dt: float, speed: float) -> bool:
	if _pi >= _path.size():
		return true
	var tg: Vector3 = _path[_pi]
	var dx := tg.x - pos.x
	var dz := tg.z - pos.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 0.1:
		_pi += 1
		_seg_from = pos
		return _pi >= _path.size()
	var step := minf(dist, speed * dt)
	pos.x += dx / dist * step
	pos.z += dz / dist * step
	var seg_len := Vector2(tg.x - _seg_from.x, tg.z - _seg_from.z).length()
	var done := 1.0 - dist / seg_len if seg_len > 1e-3 else 1.0
	pos.y = _seg_from.y + (tg.y - _seg_from.y) * clampf(done, 0, 1)
	yaw = lerp_angle(yaw, atan2(dx, dz), 1.0 - exp(-9.0 * dt))
	_speed = speed
	return false


## push out of furniture and walls while running straight at the cat
func _resolve(p: Vector3, r: float) -> Vector3:
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	q.shape = sh
	q.collision_mask = HouseBuilder.LAYER_WORLD
	for _i in 3:
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.5, 0))
		var rest := w.house.space.get_rest_info(q)
		if rest.is_empty():
			break
		var n: Vector3 = rest["normal"]
		if n.y > 0.4:
			break   # a stair ramp or the floor under its paws, not a wall to be pushed out of
		n.y = 0
		if n.length() < 0.01:
			break
		var cp: Vector3 = rest["point"]
		var depth := r - Vector2(p.x - cp.x, p.z - cp.z).length()
		p += n.normalized() * maxf(0.01, depth)
	return p


# ---------------------------------------------------------------------- update


func tick(dt: float) -> void:
	var cat := w.cat
	_speed = 0.0
	if not enabled:
		_update_visual(dt, 0.0)
		return
	var cp := cat.global_position
	_immune = maxf(0.0, _immune - dt)
	_lunge_cd = maxf(0.0, _lunge_cd - dt)
	_state_t += dt
	if hunting:
		hunt_time += dt
	if not may_hunt and hunting:
		give_up()
	if _give_up_t >= 0:
		_give_up_t -= dt
		if _give_up_t < 0:
			_give_up_t = -1.0
			if hunting or state == S.SEARCHING:
				_leave()
	match state:
		S.ABSENT:
			cooldown -= dt
			if cooldown <= 0 and hunts_done < max_hunts and cat.mode != "frozen" and may_hunt:
				_set_state(S.TRACKING)
		S.TRACKING:
			# patrol: it walks the house on its own, sniffing; it only turns on the cat when it notices it
			var dd := pos.distance_to(cp)
			if _path.is_empty() or _pi >= _path.size():
				_sniff_t -= dt
				if _sniff_t <= 0:
					_sniff_t = 1.3
					Sfx.sniff(pos + Vector3(0, 0.3, 0), 0.4)
				yaw += sin(_state_t * 1.4) * dt * 0.9
				_pause_t -= dt
				if _pause_t <= 0:
					_pause_t = randf_range(1.6, 3.2)
					_pick_patrol()
			else:
				_follow(dt, PATROL_SPEED)
				_signs(dt)
			var up := 0.0
			if cat.mode != "hidden":
				if dd < 9 and _los():
					up += 1.6 if dd < 5 else 0.9
				elif cat.running and dd < 7:
					up += 0.15
				up *= 0.35 if cat.sneaking else 1.0
			_awareness = clampf(_awareness + up * dt - 0.1 * dt, 0, 1)
			if _awareness >= 1:
				_last_known = cp
				_set_state(S.HUNTING)
			elif _state_t > PATROL_MAX or (not may_hunt and _state_t > 5.0):
				_vanish()
		S.HUNTING:
			if _windup > 0:
				# stands and barks at the cat: the tell before it comes
				_windup -= dt
				_speed = 0.0
				yaw = lerp_angle(yaw, atan2(cp.x - pos.x, cp.z - pos.z), 1.0 - exp(-10.0 * dt))
				if _windup <= 0.0:
					Sfx.bark(pos + Vector3(0, 0.6, 0), 0.9)
					if _los() and not _cat_is_high():
						_set_state(S.CHASING)
					elif _cat_is_high():
						_set_state(S.LURKING)
			else:
				var dd := pos.distance_to(cp)
				if _los() and dd < 9:
					_last_known = cp
					_lost_t = 0.0
					if dd < 7:
						_set_state(S.CHASING)
				else:
					_lost_t += dt
				if state == S.HUNTING:
					_repath_t -= dt
					if _repath_t <= 0:
						_repath_t = 1.2
						_go(_last_known)
					_follow(dt, 1.9)
					_signs(dt)
					if _lost_t > 9 or _state_t > 22:
						_set_state(S.SEARCHING)
		S.CHASING:
			_chase(dt)
		S.LURKING:
			# cannot reach: circles, growls, then loses interest
			if not _cat_is_high() or cat.mode == "hidden":
				_set_state(S.SEARCHING if cat.mode == "hidden" else S.CHASING)
			else:
				var ang := _state_t * 0.8
				var tg := cp + Vector3(cos(ang) * 1.1, 0, sin(ang) * 1.1)
				tg.y = pos.y
				var to := tg - pos
				if to.length() > 0.1:
					pos += to.normalized() * minf(1.8 * dt, to.length())
					_speed = 1.8
				yaw = lerp_angle(yaw, atan2(cp.x - pos.x, cp.z - pos.z), 1.0 - exp(-6.0 * dt))
				pos = _resolve(pos, 0.3)
				_growl_t -= dt
				if _growl_t <= 0:
					_growl_t = 0.6
					Sfx.bark(pos + Vector3(0, 0.5, 0), 0.9)
				if _state_t > BARK_UP_SECS:
					# gives up barking and vanishes; turns up far away after the cooldown
					_vanish()
		S.SEARCHING:
			if _path.is_empty() or _pi >= _path.size():
				_sniff_t -= dt
				if _sniff_t <= 0:
					_sniff_t = 1.3
					Sfx.sniff(pos + Vector3(0, 0.4, 0), 0.45)
				yaw += sin(_state_t * 1.4) * dt * 1.2
			else:
				_follow(dt, 1.7)
				_signs(dt)
			if cat.mode != "hidden" and _los() and pos.distance_to(cp) < 6 and not _cat_is_high():
				_set_state(S.CHASING)
			elif _state_t > (8.5 if cat.mode == "hidden" else 7.0):
				_leave()
		S.RECOIL:
			if _state_t > 2.4:
				_set_state(S.SEARCHING)
	# keep the dog on the floor under it
	if state != S.ABSENT and state != S.TRACKING:
		var ground := w.house.ground_height(pos.x, pos.z, pos.y + 0.5)
		if ground > -500 and absf(ground - pos.y) < 0.6:
			pos.y = lerpf(pos.y, ground, 1.0 - exp(-14.0 * dt))
	var show_amt := 0.0
	if state == S.TRACKING:
		show_amt = 0.35 + _awareness * 0.5
	elif state != S.ABSENT:
		show_amt = 1.0
	_update_visual(dt, show_amt)


func _chase(dt: float) -> void:
	var cat := w.cat
	var cp := cat.global_position
	var dd := pos.distance_to(cp)
	var los := _los()
	if cat.mode == "hidden":
		# it saw the cat slip away
		_last_known = cp
		_go(_last_known)
		_set_state(S.SEARCHING)
		return
	if _cat_is_high() and dd < 3.2:
		_set_state(S.LURKING)
		return
	if los:
		_last_known = cp
		_lost_t = 0.0
	else:
		_lost_t += dt
	if _lost_t > 6 or _state_t > 26:
		_set_state(S.SEARCHING)
		_go(_last_known)
		return
	# the cat left through the duct / window or fled upstairs: it cannot follow
	if not _can_climb() and cp.y > 2.6:
		if _state_t > 6:
			_leave()
		return
	# at the cat's walking pace: a running cat gets away, a walking one is caught
	var speed := CHASE_SPEED
	if _snarl_t > 0:
		_snarl_t -= dt
		_speed = 0.0
		yaw = lerp_angle(yaw, atan2(cp.x - pos.x, cp.z - pos.z), 1.0 - exp(-8.0 * dt))
		_signs(dt, true)
		return
	# straight at it only when a ball its size gets there without touching walls or furniture
	if los and dd < 9 and absf(cp.y - pos.y) < 0.4 and Threat.path_clear(w.house.space, pos, Vector3(cp.x, pos.y, cp.z), 0.2):
		_straight = true
		var dir := Vector3(cp.x - pos.x, 0, cp.z - pos.z)
		var dl := dir.length()
		if dl > 0.01:
			dir /= dl
			pos += dir * minf(dl, speed * dt)
			yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-11.0 * dt))
			pos = _resolve(pos, 0.28)
			_speed = speed
	else:
		_repath_t -= dt
		if _straight:
			# the way got blocked (a chair, a corner): a fresh route to where the cat is now
			_straight = false
			_repath_t = 0.0
			if los:
				_last_known = cp
		if _repath_t <= 0:
			_repath_t = 0.8
			_go(_last_known)
		_follow(dt, speed)
	# lunge with a telegraph: crouch + growl, then a short burst
	if _lunge > 0:
		_lunge -= dt
	if _windup > 0:
		_windup -= dt
		if _windup <= 0:
			_lunge = 0.5
			_lunge_cd = 2.5
			Sfx.bark(pos + Vector3(0, 0.6, 0), 0.9)

	_claws_t -= dt
	if _claws_t <= 0:
		_claws_t = 0.16
		Sfx.claws(pos, 0.45)
	if dd < 0.45 and absf(cp.y - pos.y) < 0.7 and _immune <= 0 and cat.stun_t <= 0:
		catches += 1
		_immune = 10.0
		caught.emit(self)
		cooldown = randf_range(50, 70)
		_set_state(S.ABSENT)


## claws, sniffs and a distant growl
func _signs(dt: float, still := false) -> void:
	var near := pos + Vector3(0, 0.4, 0)
	_claws_t -= dt
	if not still and _claws_t <= 0:
		_claws_t = 0.55 if state == S.TRACKING else 0.3
		Sfx.claws(pos, 0.3 if state == S.TRACKING else 0.4)
	_sniff_t -= dt
	if _sniff_t <= 0:
		_sniff_t = randf_range(3.5, 5.5)
		Sfx.sniff(near, 0.35)
	_growl_t -= dt
	if _growl_t <= 0:
		_growl_t = randf_range(7, 10) if state == S.TRACKING else randf_range(2.8, 4)
		Sfx.growl(near, 0.45 if state == S.TRACKING else 0.8, 1.4)


# ---------------------------------------------------------------------- reactions


func can_hiss(p: Vector3) -> bool:
	return (state == S.CHASING or state == S.HUNTING or state == S.LURKING) and p.distance_to(pos) < 1.5 and absf(p.y - pos.y) < 1.0


func on_hiss(p: Vector3, strong: bool) -> bool:
	if not strong or not can_hiss(p):
		return false
	Sfx.growl(pos + Vector3(0, 0.6, 0), 0.5, 0.6)
	Sfx.shriek(pos + Vector3(0, 0.6, 0), 0.25)
	_lunge = 0.0
	_windup = 0.0
	_set_state(S.RECOIL)
	_immune = maxf(_immune, 3.0)
	w.burst_smoke(pos + Vector3(0, 0.6, 0), Color(0.05, 0.0, 0.0, 0.6))
	return true


## the cat lost a life: whoever caught it backs off for a while
func cat_down() -> void:
	if state != S.ABSENT:
		_immune = 10.0
		_leave()


## the cat used the duct / window: it loses the trail
func cat_vanished() -> void:
	if hunting:
		_set_state(S.SEARCHING)
		_lost_t = 99.0


# ---------------------------------------------------------------------- visual


func _update_visual(dt: float, amt: float) -> void:
	_vis = lerpf(_vis, amt, 1.0 - exp(-5.0 * dt))
	body.alpha = 0.96 * _vis if state != S.ABSENT else 0.0
	if state == S.ABSENT and _vis < 0.02:
		body.visible = false
		return
	body.global_position = pos
	body.rotation = Vector3(-0.15 if _lunge > 0 else 0.0, yaw, 0)
	var crouch := 1.0 if _windup > 0 or state == S.RECOIL else 0.0
	var sniff := 1.0 if state == S.SEARCHING and _pi >= _path.size() else 0.0
	var snarl := 1.0 if state == S.CHASING or state == S.LURKING or _windup > 0 else (0.4 if state == S.HUNTING else 0.0)
	body.update_pose(dt, _speed, crouch, sniff, snarl, 1.0 if _lunge > 0 else 0.0, state == S.CHASING)


func focus():
	return null if state == S.ABSENT else pos + Vector3(0, 0.6, 0)

