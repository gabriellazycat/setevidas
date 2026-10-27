class_name Threat
extends Node3D
## Base of every haunting: a stage machine (0 idle .. 5 attacking), a cooldown before it wakes, a
## target person picked when it starts, stalls when hissed at. Port of Threat.ts.
## Ghosts are after the people, but the cat is in their way: one that notices it can drop its target
## and hunt the cat for a while (hunting_cat). Getting caught costs one of the seven lives.

var threat_id := ""
var display_name := ""
var stage := 0
var t := 0.0
var cooldown := 0.0
var enabled := false
var may_attack := true
var stall := 0.0
var target: Owner
var w: Game   # the world: house, cat, people, audio, fx
var hunting_cat := false
var hunt_t := 0.0
var sight := 0.0   # 0..1: how long it has been looking at the cat (the warning before a hunt)


func setup(world: Game) -> void:
	w = world
	target = w.clara


func fear_all(v: float) -> void:
	for o: Owner in w.household_present():
		o.add_fear(v)


## seconds scaled by the night's speed
func d(sec: float) -> float:
	return sec / maxf(0.3, w.threat_speed)


func enable(delay: float) -> void:
	enabled = true
	reset()
	cooldown = delay


func disable() -> void:
	enabled = false
	end_hunt()
	reset()


func set_stage(s: int) -> void:
	if s == stage:
		return
	var prev := stage
	stage = s
	t = 0.0
	if prev == 0 and s == 1:
		target = w.pick_target(threat_id)
		if threat_id != "thing":
			w.director.woke(threat_id)
		w.introduce(threat_id)
	on_stage(s, prev)


## is there anything for this ghost to do if it wakes now? (overridden where it needs a prop)
func can_wake() -> bool:
	return true


## rested, with something to do: the Director may call it now
func ready() -> bool:
	return enabled and stage == 0 and stall <= 0.0 and cooldown <= 0.0 and can_wake()


## the Director calls it: it wakes up (stage 1) and the house learns about it
func summon() -> void:
	set_stage(1)


func repel(cool = null) -> void:
	end_hunt()
	if stage >= 1:
		w.director.on_repelled(threat_id)
	w.repelled(threat_id)
	reset()
	cooldown = cool if cool != null else d(randf_range(32, 55))


func tick_threat(dt: float) -> void:
	if not enabled:
		return
	if stall > 0:
		stall -= dt
		tick_stalled(dt)
		return
	if stage == 0:
		# asleep: it only counts down its rest; the Director decides when it comes (summon)
		cooldown = maxf(0.0, cooldown - dt)
		return
	t += dt
	if hunting_cat:
		hunt_t += dt
	tick(dt)


# ---------------------------------------------------------------------- hunting the cat


## starts chasing the cat if the Director allows another hunter right now
func start_hunt() -> bool:
	if hunting_cat:
		return true
	if not w.director.may_hunt_cat(self):
		return false
	hunting_cat = true
	hunt_t = 0.0
	w.cat_hunted(self)
	on_hunt_start()
	return true


func end_hunt() -> void:
	if not hunting_cat:
		sight = 0.0
		return
	hunting_cat = false
	hunt_t = 0.0
	sight = 0.0
	on_hunt_end()


func on_hunt_start() -> void:
	pass


func on_hunt_end() -> void:
	pass


## can it see the cat from `eye` (no walls in between, close enough, the cat not hidden)?
func sees_cat(eye: Vector3, reach: float) -> bool:
	var cat := w.cat
	if cat.mode == "hidden" or w.cat_safe():
		return false
	var cp := cat.global_position + Vector3(0, 0.2, 0)
	if eye.distance_to(cp) > reach or absf(eye.y - cp.y) > 2.6:
		return false
	return not w.house.blocked(eye, cp)


## the cat is easier to notice while it carries one of Ivone's things
func sight_gain() -> float:
	return 1.6 if w.cat.carrying != null else 1.0


## close enough to grab the cat: it loses a life and the hunt ends
func try_catch(p: Vector3, reach := 0.65) -> bool:
	var cp := w.cat.global_position
	if Vector2(p.x - cp.x, p.z - cp.z).length() > reach or absf(p.y - cp.y) > 1.2:
		return false
	if w.cat_hit(threat_id, p):
		end_hunt()
		return true
	return false


## is the straight way from a to b free of walls and furniture (LAYER_WORLD) for a ball of radius r?
## a and b are floor points: the ball goes `lift` m above them, over rugs and thresholds but into
## anything as tall as a coffee table. Starting inside something counts as blocked. Ghosts only run
## straight at the cat when this holds; otherwise they take the nav route.
static func path_clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, r := 0.2, lift := 0.35) -> bool:
	if space == null:
		return true
	var shape := SphereShape3D.new()
	shape.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = HouseBuilder.LAYER_WORLD
	q.transform = Transform3D(Basis.IDENTITY, a + Vector3(0, lift, 0))
	q.motion = b - a
	var res := space.cast_motion(q)
	return res.size() == 2 and res[0] >= 1.0


## p pushed out of walls and furniture (LAYER_WORLD) on the floor plane, for a ball of radius r
## `lift` m above it: the last steps of a chase that slide along what is in the way
static func push_out(space: PhysicsDirectSpaceState3D, p: Vector3, r := 0.2, lift := 0.35) -> Vector3:
	if space == null:
		return p
	var shape := SphereShape3D.new()
	shape.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = HouseBuilder.LAYER_WORLD
	for _i in 3:
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, lift, 0))
		var rest := space.get_rest_info(q)
		if rest.is_empty():
			break
		var n: Vector3 = rest["normal"]
		n.y = 0
		if n.length() < 0.01:
			break
		var cp: Vector3 = rest["point"]
		var depth := r - Vector2(p.x - cp.x, p.z - cp.z).length()
		p += n.normalized() * maxf(0.01, depth)
	return p


func tick_stalled(_dt: float) -> void:
	pass


func reset() -> void:
	pass


func tick(_dt: float) -> void:
	pass


func on_stage(_s: int, _prev: int) -> void:
	pass


## where the cat should go (the ears point here); null if nothing
func focus():
	return null


## the visible entity (for the fur bristling)
func entity():
	return null


func on_hiss(_p: Vector3, _strong: bool) -> bool:
	return false


func can_hiss(_p: Vector3) -> bool:
	return false


func urgency() -> float:
	return stage / 5.0


func describe_death() -> Dictionary:
	return {
		"title": tr("%s foi levado(a)") % target.display_name,
		"why": tr("%s chegou até %s.") % [display_name, target.display_name],
		"tip": "Fique de olho nos sinais sonoros e resolva a ameaça antes que ela chegue.",
	}


var attacking: bool:
	get:
		return stage >= 4


static func pick(a: Array):
	return a[randi() % a.size()]
