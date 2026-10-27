class_name Director
extends Node3D
## The night's pacing, in the manner of Left 4 Dead. The Director commands, the ghosts only obey:
## an intensity I (0..1) climbs while the cat plays the mission (progress P: how many of Ivone's
## things were taken, stacked or delivered), the ghosts out and the cat hunted; it is capped by a
## ceiling that grows with P and with each cycle. At the ceiling, or when the cat is hunted /
## attacked, the cycle peaks; a cost (a life lost) closes it into a relax of 30-45 s where I falls
## and nothing new comes; then the next cycle builds higher. A ghost driven off without a cost only
## relieves I a little: the Director calls another one soon.
##
## Who comes: the ghost that is new tonight first, then a shuffle bag of the others (no repeats
## until all came). The hound is not a common enemy: it keeps its own rhythm, takes no slot and may
## walk with the ghosts. The Thing wakes on its own when half of the mission has been moved.

## the ceiling of I with nothing of the mission touched; it rises to 1 with P
const CEIL_MIN := 0.45
## per cycle the ceiling grows this much
const CEIL_CYCLE := 0.05
## from this intensity a second ghost may be out
const SECOND_AT := 0.7
## a ghost driven off takes this much off I
const REPEL_RELIEF := 0.25
## I per second: the clock alone, the mission (at P = 1), a ghost out (at stage 5), the cat hunted
const RISE_TIME := 0.003
const RISE_MISSION := 0.012
const RISE_PRESENCE := 0.012
const RISE_HUNTED := 0.03
## I per second while the house relaxes
const RELAX_FALL := 0.03
## relax over: I must also be under this
const RELAX_EXIT_I := 0.3
## a peak that was only the ceiling (nobody pressing the cat) ends when the ghosts are gone, or by
## itself after this long
const PEAK_HOLD := 90.0
## the Thing's weight on the night
const THING_FLOOR := 0.3
const THING_RELAX := 0.7

var w: Game
var shadow: ShadowThreat
var whisperer: WhispererThreat
var drowner: DrownerThreat
var doll: DollThreat
var visitor: VisitorThreat
var thing: ThingThreat
var hound: Hound
var decay := HouseDecay.new()
var all: Array = []
var base_speed := 1.0
var overtime := 0.0   # seconds the night has dragged on: the house gets faster and meaner
var dev_log := false
## dev: false = nobody is called (tests that drive a single threat by hand)
var summons_on := true

var intensity := 0.0       # I
var progress := 0.0        # P, smoothed
var cycle := 0
var relax_t := 0.0
var _state := "build"      # build / peak / relax
var _phase := "calm"       # what the rest of the game sees: calm / buildup / peak / relax
var _peak_t := 0.0
var _peak_real := false    # something really pressed the cat during this peak
var _cost := false         # the cat paid (lost a life) during this cycle
var _summon_t := 0.0
var _opening_id := ""      # the ghost new tonight, called before the bag
var _bag: Array = []
var _last_id := ""
var _since_wake := 999.0   # seconds since a ghost came (HouseDecay reads it)
var _thing_was := false


## the calm between two ghosts on night n (seconds), shorter while the intensity is high
static func wake_gap(n: int) -> float:
	if n <= 3:
		return randf_range(60.0, 80.0)
	if n <= 6:
		return randf_range(45.0, 60.0)
	return randf_range(30.0, 40.0)


## the moment a ghost arrives (the hound keeps its own clock and counts for nothing here)
func woke(who) -> void:
	if who == "hound":
		if dev_log:
			print("[director] t=%.0f WAKE hound I=%.2f" % [Time.get_ticks_msec() / 1000.0, intensity])
		return
	_since_wake = 0.0
	if dev_log:
		print("[director] t=%.0f WAKE %s I=%.2f P=%.2f cycle=%d" % [Time.get_ticks_msec() / 1000.0, who, intensity, progress, cycle])


## ghosts awake (stage >= 1), not counting the Thing; the hound is not a common enemy
func awake() -> int:
	var k := 0
	for th: Threat in all:
		if th.enabled and th.stage >= 1 and th.threat_id != "thing":
			k += 1
	return k


func thing_awake() -> bool:
	return thing != null and thing.enabled and thing.stage > 0


## how many ghosts may be out together right now
func cap_now() -> int:
	return 2 if intensity >= SECOND_AT or thing_awake() else 1


## the finale (night 7) and a night that drags on are the only times attacks / hunts overlap
func attack_cap() -> int:
	return 2 if w.night >= 7 or overtime > 150.0 else 1


func hunt_cap() -> int:
	return 2 if w.night >= 7 else 1


## ambient scares (eyes, window figure, door) only fill a calm house: never over a build-up, a
## peak or the quiet that follows one
func allows_ambient() -> bool:
	return _phase == "calm"


func phase() -> String:
	return _phase


## the ceiling of this cycle's intensity
func ceiling() -> float:
	return minf(1.0, lerpf(CEIL_MIN, 1.0, progress) + CEIL_CYCLE * cycle + minf(0.3, overtime / 600.0))


## a ghost was driven off (the cat won): a little relief and a pause before the next call
func on_repelled(_id: String) -> void:
	intensity = maxf(0.0, intensity - REPEL_RELIEF)
	_summon_t = maxf(_summon_t, randf_range(10.0, 20.0) / maxf(0.5, base_speed))
	if dev_log:
		print("[director] repelled %s: I=%.2f" % [_id, intensity])


func _real_peak() -> bool:
	if hound.active and hound.hunting:
		return true
	for th: Threat in all:
		if th.enabled and (th.hunting_cat or th.stage >= 4):
			return true
	return false


func _out_now() -> bool:
	if hound.active:
		return true
	for th: Threat in all:
		if th.enabled and th.stage >= 1 and th.threat_id != "thing":
			return true
	return false


func _set_state(s: String) -> void:
	if s == _state:
		return
	if dev_log:
		print("[director] t=%.0f %s -> %s I=%.2f ceil=%.2f cycle=%d awake=%d" % [Time.get_ticks_msec() / 1000.0, _state, s, intensity, ceiling(), cycle, awake()])
	_state = s
	if s == "peak":
		_peak_t = 0.0
		_peak_real = false
	elif s == "relax":
		relax_t = randf_range(30.0, 45.0) * (1.0 - (w.night - 1) * 0.05) * (THING_RELAX if thing_awake() else 1.0)
		_cost = false
	elif s == "build":
		_cost = false
		_summon_t = randf_range(8.0, 15.0) / maxf(0.5, base_speed)


func _update_intensity(dt: float) -> void:
	if _state == "relax":
		intensity = maxf(0.0, intensity - RELAX_FALL * dt)
		return
	var rise := RISE_TIME + RISE_MISSION * progress
	var top := 0.0
	for th: Threat in all:
		if th.enabled and th.threat_id != "thing":
			top = maxf(top, th.stage / 5.0)
	rise += RISE_PRESENCE * top
	if w.cat.hunted > 0.25:
		rise += RISE_HUNTED
	intensity = clampf(intensity + rise * dt, 0.0, ceiling())
	if thing_awake():
		intensity = maxf(intensity, THING_FLOOR)


func _update_cycle(dt: float) -> void:
	var real := _real_peak()
	match _state:
		"build":
			if real or (intensity >= ceiling() - 0.01 and awake() > 0):
				_set_state("peak")
				_peak_real = real
		"peak":
			_peak_t += dt
			if real:
				_peak_real = true
			elif _cost:
				_set_state("relax")
			elif _peak_real:
				# the cat got away or won, at no cost: the Director keeps building
				_set_state("build")
			elif (awake() == 0 and not hound.active) or _peak_t > PEAK_HOLD:
				# the ceiling was reached and nothing came of it, or everything went away: breathe out
				_set_state("relax")
		"relax":
			relax_t -= dt
			if relax_t <= 0.0 and (intensity < RELAX_EXIT_I or relax_t < -15.0):
				cycle += 1
				_set_state("build")
	if dev_log and thing_awake() != _thing_was:
		_thing_was = thing_awake()
		print("[director] t=%.0f THING %s P=%.2f taken=%d/%d" % [Time.get_ticks_msec() / 1000.0, "awake" if _thing_was else "asleep", progress, w.mission_taken(), w._mission.size()])
	var p := _state
	if p == "build":
		p = "buildup" if _out_now() else "calm"
	if p != _phase and dev_log:
		print("[director] t=%.0f phase %s -> %s awake=%d relax=%.0f" % [Time.get_ticks_msec() / 1000.0, _phase, p, awake(), relax_t])
	_phase = p


## the next ghost to call: the one new tonight first, then the bag; null = none right now
func _pick_ghost() -> Threat:
	if _opening_id != "":
		var o := get_threat(_opening_id)
		if o != null and o.enabled:
			if o.ready():
				_opening_id = ""
				_last_id = o.threat_id
				return o
			if o.stage == 0 and o.can_wake():
				return null   # it has priority: wait for its first delay
		_opening_id = ""
	if _bag.is_empty():
		_refill_bag()
	for id: String in _bag:
		var th := get_threat(id)
		if th != null and th.ready():
			_bag.erase(id)
			_last_id = id
			return th
	return null


func _refill_bag() -> void:
	_bag.clear()
	for id: String in Config.NIGHT_THREATS.get(w.night, []):
		if id != "thing":
			_bag.append(id)
	_bag.shuffle()
	if _bag.size() > 1 and _bag[0] == _last_id:
		_bag.push_back(_bag.pop_front())


func _try_summon() -> bool:
	if awake() >= cap_now() or cat_hunters(null) > 0:
		return false
	var th := _pick_ghost()
	if th == null:
		return false
	th.summon()
	return true


func setup(world: Game) -> void:
	w = world
	shadow = ShadowThreat.new()
	whisperer = WhispererThreat.new()
	drowner = DrownerThreat.new()
	doll = DollThreat.new()
	visitor = VisitorThreat.new()
	thing = ThingThreat.new()
	all = [shadow, whisperer, drowner, doll, visitor, thing]
	for th: Threat in all:
		add_child(th)
		th.setup(w)
	hound = Hound.new()
	add_child(hound)
	hound.setup(w)
	decay.setup(w)


func get_threat(id: String) -> Threat:
	for th: Threat in all:
		if th.threat_id == id:
			return th
	return null


func start_night(n: int, speed_setting: float) -> void:
	base_speed = float(Config.NIGHT_SPEED.get(n, 1.0)) * speed_setting
	w.threat_speed = base_speed
	intensity = 0.0
	progress = 0.0
	cycle = 0
	relax_t = 0.0
	_state = "build"
	_phase = "calm"
	_cost = false
	_since_wake = 999.0
	_bag.clear()
	_last_id = ""
	for th: Threat in all:
		th.disable()
	whisperer.replug_all()
	drowner.dry_all()
	var ids: Array = Config.NIGHT_THREATS.get(n, [])
	var fresh = Config.NEW_ON_NIGHT.get(n)
	_opening_id = fresh if fresh != null and fresh != "thing" else ""
	for id: String in ids:
		# the ghost that is new tonight shows up early, so its night teaches it; the others rest a while
		# (the Director paces them: the bag, the gap, the cap)
		var first: float = (24.0 + (8.0 if n == 1 else 0.0)) if id == fresh else 20.0
		get_threat(id).enable(first / base_speed)
	_summon_t = (12.0 if n > 1 else 20.0) / base_speed
	decay.start_night(n)
	if n >= Config.HOUND_FROM:
		hound.start_night(n, base_speed)
	else:
		hound.stop()


func stop_all() -> void:
	for th: Threat in all:
		th.disable()
	decay.stop()
	hound.stop()


func tick(dt: float) -> void:
	# fairness: limit simultaneous attacks
	# one at a time (readable, scarier); only the finale overlaps
	var cap := attack_cap()
	var attackers := 0
	for th: Threat in all:
		if th.enabled and th.stage >= 4 and th.threat_id != "thing":
			attackers += 1
	for th: Threat in all:
		th.may_attack = th.stage >= 4 or attackers < cap
	# the awakened Thing makes everything faster
	decay.tick(dt)
	w.threat_speed = base_speed * (1.18 if thing_awake() else 1.0) * (1.0 + decay.pressure() + minf(0.45, overtime / 300.0))
	for th: Threat in all:
		th.tick_threat(dt)
	_since_wake += dt
	progress = lerpf(progress, w.mission_progress(), 1.0 - exp(-2.0 * dt))
	_update_intensity(dt)
	# the Director calls the ghosts, only while the cycle builds
	if _state == "build" and summons_on:
		_summon_t -= dt
		if _summon_t <= 0.0:
			if _try_summon():
				_summon_t = wake_gap(w.night) * lerpf(1.0, 0.5, intensity) / maxf(0.5, base_speed)
			else:
				_summon_t = 3.0
	# the hound is no common enemy: it takes no slot and keeps its own cooldown; the Director only
	# lets it come in while the cycle builds, and never while the cat is already hunted by a ghost
	var hunters := cat_hunters(hound)   # the hound's own hunt must not count against it
	if hound.active:
		hound.may_hunt = hunters == 0
	else:
		hound.may_hunt = _state == "build" and summons_on and hunters == 0
	hound.tick(dt)
	_update_cycle(dt)


## how many are hunting the cat right now (ghosts and the hound), not counting `except`
func cat_hunters(except) -> int:
	var n := 0
	for th: Threat in all:
		if th.enabled and th.hunting_cat and th != except:
			n += 1
	if hound.active and hound.hunting and hound != except:
		n += 1
	return n


## one hunter at a time (two on the last night), so a chase is always readable and escapable
func may_hunt_cat(th: Threat) -> bool:
	return cat_hunters(th) < hunt_cap()


## the cat dived into a cardboard box while hunted: whoever hunts it goes in after it and is gone
func box_trap(at: Vector3) -> bool:
	var any := false
	for th: Threat in all:
		if th.enabled and th.hunting_cat:
			th.end_hunt()
			th.repel()
			any = true
	# the bold Shadow stalking the cat (not hunting yet) follows it in too
	if shadow.enabled and shadow.mode == "stalk":
		shadow.repel()
		any = true
	if hound.active and hound.hunting:
		hound.cat_down()
		any = true
	if any:
		Sfx.shriek(at + Vector3(0, 0.4, 0), 0.6)
		w.burst_smoke(at + Vector3(0, 0.3, 0), Color(0.05, 0.05, 0.06, 0.7))
		w.shake(0.5)
	return any


## the cat just lost a life: everyone hunting it lets go, and the cycle closes into a relax
func cat_down() -> void:
	_cost = true
	for th: Threat in all:
		if th.enabled:
			th.end_hunt()
	hound.cat_down()
	drowner.cat_wet = 0.0
	drowner.trail.clear()


## the most urgent danger: where the cat's ears point. {id, focus, urgency, stage} or {}
func most_urgent() -> Dictionary:
	var best := {}
	var bu := 0.05
	for th: Threat in all:
		if not th.enabled or th.stage == 0:
			continue
		var u := 1.0 if th.hunting_cat else th.urgency()
		if u > bu:
			bu = u
			best = {"id": th.threat_id, "focus": th.focus(), "urgency": u, "stage": th.stage}
	var hu := hound.threat_level()
	if hu > bu and hound.active:
		best = {"id": "hound", "focus": hound.focus(), "urgency": hu, "stage": 4 if hound.hunting else 2}
	return best


func tension() -> float:
	var m := 0.0
	for th: Threat in all:
		if th.enabled:
			m = maxf(m, th.stage / 5.0)
	return maxf(m, hound.threat_level() * 0.8)


## nearest visible entity to p (for the fur bristling)
func nearest_entity(p: Vector3) -> float:
	var bd := INF
	for th: Threat in all:
		if not th.enabled:
			continue
		var e = th.entity()
		if e == null:
			continue
		bd = minf(bd, (e as Vector3).distance_to(p))
	if hound.active:
		bd = minf(bd, hound.pos.distance_to(p))
	return bd


func hiss(p: Vector3, strong: bool) -> bool:
	var any := false
	for th: Threat in all:
		if th.enabled and th.on_hiss(p, strong):
			any = true
	if hound.on_hiss(p, strong):
		any = true
	return any


## would a hiss from here do anything? (for the on-screen prompt)
func can_hiss_at(p: Vector3) -> bool:
	for th: Threat in all:
		if th.enabled and th.stage > 0 and th.can_hiss(p):
			return true
	return hound.can_hiss(p)


## sounds made in the house: lure or alert whoever hunts by ear
func hear_noise(p: Vector3, loud: float, kind: String) -> void:
	hound.hear_noise(p, loud, kind)
	drowner.hear_noise(p, loud)
