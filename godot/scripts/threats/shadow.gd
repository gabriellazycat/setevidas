class_name ShadowThreat
extends Threat
## A Sombra: rises somewhere in the house (never the bedroom floor) and walks through the dark toward
## whoever it is after. It cannot stand light: lighting the room it walks in banishes it. It avoids
## lit rooms, drains any light in its way, and bulbs die on their own, so a lit room is only a
## short-lived shield. Port of Shadow.ts.
##
## It is the player who looks, not the Shadow: seen in the open (on screen, in plain sight, not
## through a wall with Cat Vision) it flees on all fours to the nearest dark nook (SHADOW_NOOKS in
## layout.json). Staring at the nook (close, near the middle of the screen, no furniture in between)
## makes its head come out of hiding, turn to the cat and heat up: after 5 s of staring it charges the
## cat and takes a life. Left alone for 5 s (or 20 s in all) it comes out and goes back to its target;
## stepping out into a lit room banishes it. Hiding only delays it.
##   walk -> flee -> hidden <-> peek -> charge   (it never runs past the cat: with no safe nook it
##   retreats away from it and looks again from there)
##                   hidden -> emerge -> walk (or banished in the light)
##
## It gets bolder every time it is caught in the open (boldness; only being banished by the light
## resets it): the second time it hides for half as long and keeps its place by the bed; from the
## third on it no longer hides at all ("stalk"): it backs off a couple of metres without leaving the
## frame, stands and stares at the cat heating up and charges after ~5 s. Walk away and it follows,
## slow at first and faster and faster (it never cools down); catching up is a charge. Only a lit
## room (light the one it is in, or lead it into one) or a cardboard box gets rid of it.

const SPAWNS := [
	{"node": "b_porao_mid", "room": "porao", "min": 1},
	{"node": "b_lav_mid", "room": "lavanderia", "min": 2},
	{"node": "g_esc_mid", "room": "escritorio", "min": 2},
	{"node": "g_coz_n", "room": "cozinha", "min": 3},
	{"node": "g_sala_mid", "room": "sala", "min": 3},
	{"node": "a_mid", "room": "sotao", "min": 5},
]
const SEEN_SECS := 0.3     # in plain sight this long before it reacts (a glance does nothing)
const SEE_REACH := 14.0
const FLEE_SPEED := 6.0
const PEEK_SECS := 5.0     # stared at this long, it charges
const HIDE_SECS := 5.0     # nobody looking this long, it comes out
const BORED_SECS := 20.0   # in the nook this long without being stared down, it comes out anyway
const STARE_REACH := 9.0   # the nook only counts as stared at from this close...
const STARE_SCREEN := 0.4  # ...and this near the middle of the screen (fraction of its half size)
const CHARGE_SPEED := 8.0  # faster than the cat running (4.4)
const CLEAR_R := 1.6       # running away it never passes the cat closer than this
const CAUGHT_SECS := 0.55  # seen walking: frozen, staring back, this long before it bolts
const STARE_SECS := 2.0    # the 1st and 2nd time it is seen it looks like Clara and stares this long first
const CORNER_SECS := 6.0  # cornered by the cat this long, it charges
const LOOK_MAX := 1.3     # how far the peeking head turns from facing out of the nook (rad)
const SOLID := {"dissolve": 0.12, "foot_fade": 0.3}   # less see-through than the other ghosts
const STALK_FROM := 3         # caught in the open this many times, it stops hiding
const STALK_BACK := Vector2(2.0, 3.0)   # how far it backs off from where it was seen
const STALK_STARE := 5.0      # staring this long, it charges
const STALK_KEEP := 4.5       # the cat farther than this (or out of sight): it follows
const STALK_SLOW := 0.8       # following: starts this slow...
const STALK_FAST := 6.0       # ...and speeds up to this
const STALK_ACCEL := 0.5      # m/s per second
const STALK_REACH := 1.4      # following, this close it charges
const STALK_LOST := 12.0      # the cat hidden this long, it gives up and goes back to its target
const CUE_SECS := Vector2(8.0, 12.0)    # hidden: a low breath or a giggle from the nook this often

var body: GhostBody         # walking
var runner: GhostBody       # running and charging (shadow_run.glb)
var peek: ShadowPeek        # hiding: head and hands
var route: Array = []
var ri := 0
var pos := Vector3.ZERO
var yaw := 0.0
var draining := ""
var drain_t := 0.0
var vis := 0.0
var breath_t := 0.0
var last_spawn := ""
var spawn: Dictionary = SPAWNS[0]
var retarget_t := 0.0
var mode := "walk"          # walk | flee | hidden | peek | charge | emerge
var nook: Dictionary = {}
var _seen_t := 0.0
var _unseen_t := 0.0
var _nook_t := 0.0
var _path: Array = []
var _path_i := 0
var _repath_t := 0.0
var _tic_t := 0.0
var _sfx_t := 0.0
var _hum = null
var _scare_t := -1.0
var _moving := 0.0
var dev_nook := ""          # dev: always flee to this nook (autopilot --shadownook)
var dev_log := false        # dev: print the flee choices and how close it ran to the cat
var dev_min_cat := 99.0
var dev_no_look := false    # dev: the peeking head keeps facing out of the nook (autopilot --peeklook=0)
var _recheck_t := 0.0
var _retreat_t := 0.0
var _cur_form := ""
var _glare := 0.0
var _out := 0.0
var _tic := 0.0
var _caught := false        # seen walking, frozen for a moment
var _look_k := 0.0         # 0 facing out of the nook, 1 turned to the cat
var boldness := 0          # times caught in the open since it was last banished (see STALK_FROM)
var dev_bold := 0          # dev: boldness it starts the night with (--shadowbold=N)
var _stalk := ""           # stalk: back | stare | follow
var _stalk_goal := Vector3.ZERO
var _stalk_t := 0.0
var _stalk_speed := 0.0
var _stalk_lost := 0.0
var _stalk_log_t := 0.0
var _cue_t := 0.0
var _lit_t := 0.0           # the light of the room it hides in was on less than LIT_MEMORY s ago
var _red: OmniLight3D      # the red light on the cat while it stares in the open
# a route to a moving point (charge, stalk, its last steps to the bed): straight only while clear
var _cpath: Array = []
var _ci := 0
var _crepath := 0.0


func _init() -> void:
	threat_id = "shadow"
	display_name = "A Sombra"


func setup(world: Game) -> void:
	super.setup(world)
	# walking it wears Clara's own model (toon, pale and a little too tall): the player takes it for her
	# until it stops and stares, then it drops to all fours and runs as the spider form
	body = GhostBody.new("clara_night", Color(0.002, 0.002, 0.003), Color(0.07, 0.08, 0.11), 0.0, Color(0.0, 0.0, 0.005, 0.7), 1.9, Color(0.85, 0.92, 1.0), true)
	body.height_scale = 1.08
	body.limb_stretch = 1.1
	add_child(body)
	body.alpha = 0.0
	runner = GhostBody.new("shadow_run", Color(0.002, 0.002, 0.003), Color(0.07, 0.08, 0.11), 0.0, Color(0.0, 0.0, 0.005, 0.7), 1.2)
	add_child(runner)
	runner.flesh(SOLID.merged({"foot_fade": 0.06}))   # hands and feet on the floor: no fade there
	runner.alpha = 0.0
	peek = ShadowPeek.new()
	add_child(peek)
	_red = OmniLight3D.new()
	_red.light_color = Color(1.0, 0.1, 0.04)
	_red.omni_range = 3.2
	_red.omni_attenuation = 1.4
	_red.shadow_enabled = false
	_red.light_energy = 0.0
	_red.visible = false
	add_child(_red)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shadowbold="):
			dev_bold = int(a.get_slice("=", 1))
	# a slow, heavy walk: the zombie clips
	body.rig.set_loco_anims("zombie_idle", "zombie_walk", "zombie_walk")
	route = [w.house.nav.get_node(SPAWNS[0]["node"])]
	pos = route[0].p


func _nav() -> NavGraph:
	return w.house.nav


func _pick_spawn() -> void:
	var lights := w.house.lights
	var opts := []
	for s in SPAWNS:
		if s["min"] <= w.night and s["node"] != last_spawn:
			opts.append(s)
	if opts.is_empty():
		for s in SPAWNS:
			if s["min"] <= maxi(1, w.night):
				opts.append(s)
	var best = null
	var bs := -INF
	for s in opts:
		var n := _nav().get_node(s["node"])
		var dist := n.p.distance_to(w.cat.global_position)
		var score := randf() * 2.0 + minf(dist, 12.0) * 0.2
		if lights.is_room_lit(s["room"]):
			score -= 1.5
		if dist < 4.5:
			score -= 5.0
		if score > bs:
			bs = score
			best = s
	spawn = best if best != null else SPAWNS[0]
	last_spawn = spawn["node"]


func _lit_penalty(n) -> float:
	return 14.0 if w.house.lights.is_room_lit(n.room) else 0.0


## from a node, or (null) from where it stands, even mid-staircase
func _build_route(from = null) -> void:
	var nav := _nav()
	var to = nav.get_node(target.cfg["bed_node"])
	if not target.in_bed:
		to = nav.nearest(target.global_position)
	route = nav.route(from, to, true, _lit_penalty) if from != null else nav.route_from(pos, to, true, _lit_penalty)
	ri = 0


## a new night: it starts shy again (dev: --shadowbold)
func enable(delay: float) -> void:
	boldness = dev_bold
	super.enable(delay)


func reset() -> void:
	stage = 0
	t = 0.0
	ri = 0
	draining = ""
	vis = 0.0
	mode = "walk"
	nook = {}
	_seen_t = 0.0
	_scare_t = -1.0
	_stalk = ""
	_cpath = []
	_stop_hum()
	if _red:
		_red.visible = false
	if body:
		body.alpha = 0.0
		body.glare = 0.0
		body.heat = 0.0
		body.rig.jerky = 0.0
		runner.alpha = 0.0
		peek.alpha = 0.0
		_glare = 0.0
		_out = 0.0
		_cur_form = ""
	if target:
		target.paralysis = false
	if w:
		for l in w.house.lights.lights:
			if l.flicker > 0 and l.def["room"] != "dynamic":
				l.flicker = 0.0
		_pick_spawn()
		_build_route(_nav().get_node(spawn["node"]))
		pos = route[0].p


var room: String:
	get:
		if mode in ["flee", "hidden", "peek", "emerge"] and not nook.is_empty():
			return nook["room"]
		if mode in ["retreat", "stalk", "charge"]:
			var r := Layout.room_at(pos)
			if r != "":
				return r
		if route.is_empty():
			return "porao"
		return route[mini(ri, route.size() - 1)].room


func on_stage(s: int, _prev: int) -> void:
	var lights := w.house.lights
	if s == 1:
		_build_route(_nav().get_node(spawn["node"]))
		pos = route[0].p
		var at := pos + Vector3(0, 1.2, 0)
		if spawn["room"] == "porao":
			var door: Door = w.house.doors["d_porao"]
			if door.state == "closed":
				get_tree().create_timer(2.5).timeout.connect(func():
					if stage >= 1:
						door.set_state("ajar")
						Sfx.creak(door.center() + Vector3(0, 1, 0), 0.6, 2.2, 0.7))
		else:
			Sfx.creak(at, 0.5, 1.8, 0.65)
		Sfx.breath(Vector3(pos.x, pos.y + 1.6, pos.z), 0.55)
	if s == 2:
		var l = lights.by_room.get(spawn["room"])
		if l and l.on:
			draining = spawn["room"]
			l.flicker = 1.0
			Sfx.buzz(l.light.global_position, 1.5)
			get_tree().create_timer(1.5).timeout.connect(func():
				l.flicker = 0.0
				l.set_on(false)
				l.dead = 2.0
				draining = ""
				Sfx.click(l.light.global_position, 0.6)
				Sfx.bulb_pop(l.light.global_position))
		Sfx.creak(pos + Vector3(0, 1, 0), 0.35, 1.6, 0.6)
	if s == 4:
		target.say(pick(["Hmm... quem tá aí...?", "...{cat}? É você?", "Que frio..."]), 2.6, "whisper")
		var lamp = lights.get_light(target.cfg["lamp"])
		if lamp.on:
			draining = target.cfg["bed_room"]
			lamp.flicker = 1.0
			get_tree().create_timer(1.8).timeout.connect(func():
				lamp.flicker = 0.0
				lamp.set_on(false)
				lamp.dead = 2.0
				draining = "")
		Sfx.breath(pos + Vector3(0, 1.6, 0), 0.8)
	if s == 5:
		if target.in_bed:
			target.paralysis = true
		w.sting(0.55)
		w.distort(0.6)


func tick(dt: float) -> void:
	breath_t -= dt
	_moving = 0.0
	_track_light(dt)
	if _scare_t >= 0.0:
		_tick_scare(dt)
		return
	match mode:
		"flee":
			_tick_flee(dt)
		"retreat":
			_tick_retreat(dt)
		"hidden":
			_tick_hidden(dt)
		"peek":
			_tick_peek(dt)
		"charge":
			_tick_charge(dt)
		"stalk":
			_tick_stalk(dt)
		"emerge":
			_tick_emerge(dt)
		_:
			_tick_walk(dt)
	_update_visual(dt)


# ---------------------------------------------------------------------- walking to the target


func _tick_walk(dt: float) -> void:
	var lights := w.house.lights
	var tgt := target
	if stage >= 2:
		var here := Layout.room_at(pos)
		if here == "":
			here = room
		if lights.is_room_lit(here) and draining != here and t > 0.3:
			_banish()
			return
		# looked at in the open: it freezes, its head snaps round to the cat, then it runs and hides
		var caught_secs := STARE_SECS if boldness < 2 else CAUGHT_SECS
		if _seen(_body_points(), dt * SEEN_SECS / caught_secs):
			_spotted()
			return
		if _seen_t > 0.0 and not _caught and breath_t <= 0.0:
			breath_t = 3.0
			Sfx.breath(pos + Vector3(0, 1.7, 0), 0.5)
		_caught = _seen_t > 0.0
		if _caught:
			return
	if stage == 1 and t > d(9):
		set_stage(2)
	elif stage == 2 and t > d(5):
		set_stage(3)
	elif stage == 3:
		retarget_t -= dt
		if retarget_t <= 0:
			retarget_t = 3.0
			var want_room: String = tgt.cfg["bed_room"]
			if not tgt.in_bed:
				var rr := Layout.room_at(tgt.global_position)
				want_room = rr if rr != "" else tgt.cfg["bed_room"]
			var last = route[route.size() - 1] if not route.is_empty() else null
			if last == null or last.room != want_room:
				_build_route()
		if ri + 1 >= route.size():
			set_stage(4)
			return
		var nxt = route[ri + 1]
		var next_room: String = nxt.room
		var reaches_bed: bool = next_room == tgt.cfg["bed_room"] or ri + 1 >= route.size() - 1
		if next_room != room and reaches_bed and not may_attack:
			return
		if next_room != room and lights.is_room_lit(next_room):
			# stand at the threshold and drain the light
			if draining != next_room:
				draining = next_room
				drain_t = 0.0
				var nl = lights.by_room.get(next_room)
				Sfx.buzz(nl.light.global_position if nl else nxt.p, d(3.5))
			drain_t += dt
			var l = lights.by_room.get(next_room)
			var is_bed: bool = next_room == tgt.cfg["bed_room"]
			var lamp = lights.get_light(tgt.cfg["lamp"]) if is_bed else null
			if l:
				l.flicker = minf(1.0, 0.4 + drain_t / d(3.5))
			if lamp:
				lamp.flicker = l.flicker if l else 1.0
			if drain_t > d(3.5):
				var dead_t := 5.5 if is_bed else 2.2
				if l:
					l.flicker = 0.0
					l.set_on(false)
					l.dead = dead_t
					Sfx.bulb_pop(l.light.global_position)
				if lamp:
					lamp.flicker = 0.0
					lamp.set_on(false)
					lamp.dead = dead_t
				Sfx.click(l.light.global_position if l else pos, 0.6)
				draining = ""
			return
		draining = ""
		var dir: Vector3 = nxt.p - pos
		var dist := dir.length()
		var sp := 0.85 * w.threat_speed
		if dist < 0.05:
			ri += 1
			if room == tgt.cfg["bed_room"] and tgt.in_bed:
				set_stage(4)
			elif breath_t <= 0 and randf() < 0.35:
				breath_t = 6.0
				Sfx.breath(pos + Vector3(0, 1.6, 0), 0.45)
		else:
			pos += dir.normalized() * minf(dist, sp * dt)
			_moving = sp
			yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-6.0 * dt))
		if randf() < dt * 0.25:
			Sfx.creak(pos + Vector3(0, 0.1, 0), 0.25, 0.8, 0.7)
		tgt.add_fear(0.25 * dt)
		if not tgt.in_bed and pos.distance_to(tgt.global_position) < 2.0:
			set_stage(4)
	elif stage == 4:
		var tp: Vector3
		if tgt.in_bed:
			tp = tgt.cfg["bed_side"]
		else:
			tp = tgt.global_position + Vector3(sin(tgt.yaw + PI) * 1.1, 0, cos(tgt.yaw + PI) * 1.1)
		_approach(tp, 0.8, dt)
		yaw = lerp_angle(yaw, atan2(tgt.global_position.x - pos.x, tgt.global_position.z - pos.z), 1.0 - exp(-4.0 * dt))
		tgt.add_fear(4.0 * dt)
		if t > d(8) and may_attack:
			set_stage(5)
	elif stage == 5:
		var bp: Vector3 = tgt.cfg["bed_side"]
		var tp2 := Vector3(bp.x - 0.05, bp.y + 0.05, bp.z + 0.8) if tgt.in_bed else tgt.global_position + Vector3(0, 0, 0.8)
		_approach(tp2, 0.6, dt)
		tgt.add_fear(8.5 * dt)


## its last steps to the person (stages 4 and 5): it eases in when the way is clear or it is
## nearly there (stage 5 leans over the bed), otherwise it walks the route round the furniture
func _approach(tp: Vector3, k: float, dt: float) -> void:
	var flat := Vector2(tp.x - pos.x, tp.z - pos.z).length()
	if flat < 1.2 or (absf(tp.y - pos.y) < 0.4 and path_clear(w.house.space, pos, tp)):
		pos = pos.lerp(tp, 1.0 - exp(-dt * k))
		_cpath = []
		return
	_chase_step(tp, 0.85 * w.threat_speed, dt, 6.0)


## one step toward a (moving) goal: straight when a ball its size gets there without touching walls
## or furniture and it is on the same floor off the stairs, otherwise along the nav route (renewed
## every 0.4 s); past the route's last node it slides along whatever is still in the way
func _chase_step(goal: Vector3, sp: float, dt: float, turn := 14.0) -> void:
	var to := goal
	var flat_goal := Vector3(goal.x, pos.y, goal.z)
	var slide := false
	var straight := absf(goal.y - pos.y) < 0.4 and not Layout.on_stairs(goal) and not Layout.on_stairs(pos) \
		and path_clear(w.house.space, pos, flat_goal)
	if straight:
		_cpath = []
	else:
		_crepath -= dt
		if _crepath <= 0 or _cpath.is_empty():
			_crepath = 0.4
			var nav := _nav()
			_cpath = nav.route_from(pos, nav.nearest(goal, true), true)
			_ci = 1 if _cpath.size() > 1 and NavGraph.on_first_leg(pos, _cpath[0].p, _cpath[1].p) else 0
			# already nearer the goal than the route's last node, on its floor: no walking back to it
			# (só sem parede no meio: perto mas do outro lado da parede ela tem de dar a volta pela porta)
			if not _cpath.is_empty() and absf(goal.y - pos.y) < 0.4 and _cpath[-1].p.distance_to(goal) > pos.distance_to(goal) \
					and not w.house.blocked(pos + Vector3(0, 0.5, 0), goal + Vector3(0, 0.5, 0)):
				_ci = _cpath.size()
		while _ci < _cpath.size() and pos.distance_to(_cpath[_ci].p) < 0.15:
			_ci += 1
		if _ci < _cpath.size():
			to = _cpath[_ci].p
		else:
			# past the route's last node with something still in the way: it slides along it
			slide = absf(goal.y - pos.y) < 0.4
	var dir := to - pos
	var dist := dir.length()
	if dist > 0.02:
		var np := pos + dir / dist * minf(dist, sp * dt)
		if slide:
			np = push_out(w.house.space, np)
			np.y = pos.y
		pos = np
		_moving = sp
		if Vector2(dir.x, dir.z).length() > 0.02:
			yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-turn * dt))


# ---------------------------------------------------------------------- the player's eyes


## a few points of its body (head, chest, feet)
func _body_points() -> Array:
	var s := 1.08
	return [pos + Vector3(0, 1.6 * s, 0), pos + Vector3(0, 1.0 * s, 0), pos + Vector3(0, 0.15, 0)]


## any of the points on screen, close enough and in plain sight (a wall in between does not count,
## Cat Vision or not), for SEEN_SECS in a row
func _seen(points: Array, dt: float) -> bool:
	if _player_sees(points):
		_seen_t += dt
	else:
		_seen_t = 0.0
	return _seen_t >= SEEN_SECS


func _player_sees(points: Array) -> bool:
	var cam := w.cam
	if cam == null or w.mode != "play":
		return false
	var cp := cam.global_position
	for p in points:
		var pv: Vector3 = p
		if cp.distance_to(pv) > SEE_REACH or not cam.is_position_in_frustum(pv):
			continue
		if not w.house.blocked(cp, pv):
			return true
	return false


## the nook is stared at, not just somewhere in the frame: close, near the middle of the screen and
## with nothing in between, furniture included (what it leans on, within 0.6 m of the head, does not
## count)
func _player_stares(p: Vector3) -> bool:
	var cam := w.cam
	if cam == null or w.mode != "play":
		return false
	var cp := cam.global_position
	if cp.distance_to(p) > STARE_REACH or not cam.is_position_in_frustum(p):
		return false
	var vp := cam.get_viewport().get_visible_rect().size
	var s := (cam.unproject_position(p) - vp * 0.5) / (vp * 0.5)
	if absf(s.x) > STARE_SCREEN or absf(s.y) > STARE_SCREEN * 1.4:
		return false
	if w.house.blocked(cp, p):
		return false
	var q := PhysicsRayQueryParameters3D.create(cp, p, HouseBuilder.LAYER_WORLD)
	var hit := w.house.space.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.6


# ---------------------------------------------------------------------- fleeing and hiding


func _nooks() -> Array:
	return Layout.data().get("SHADOW_NOOKS", [])


## the dark route costs more near the cat: it would rather go around than run through it
func _avoid_cost(n) -> float:
	var c := _lit_penalty(n)
	var cp := w.cat.global_position
	if absf(n.p.y - cp.y) < 1.2 and Vector2(n.p.x - cp.x, n.p.z - cp.z).length() < CLEAR_R + 0.6:
		c += 40.0
	return c


## no leg of the polyline passes the cat closer than CLEAR_R (the first may start near it if it
## leads away)
func _points_clear(pts: Array) -> bool:
	var cp := w.cat.global_position
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var q := Geometry3D.get_closest_point_to_segment(cp, a, b)
		if absf(q.y - cp.y) > 1.2 or Vector2(q.x - cp.x, q.z - cp.z).length() >= CLEAR_R:
			continue
		if i == 1 and q.distance_to(a) < 0.05 and b.distance_to(cp) > a.distance_to(cp):
			continue
		return false
	return true


## where it will run along a route from where it stands (skipping the node behind it)
func _route_points(r: Array, end = null) -> Array:
	var pts := [pos]
	var i0 := 1 if r.size() > 1 and NavGraph.on_first_leg(pos, r[0].p, r[1].p) else 0
	for i in range(i0, r.size()):
		pts.append((r[i] as NavGraph.NavNode).p)
	if end != null:
		pts.append(end)
	return pts


static func _length(pts: Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += (pts[i - 1] as Vector3).distance_to(pts[i])
	return l


## the nearest nook (by the dark route) the camera cannot see, in a dark room, that it can reach
## without running past the cat; nooks behind it (away from the cat) are cheaper. {nook, route} or {}
func _pick_nook() -> Dictionary:
	var nav := _nav()
	var best := {}
	var bl := INF
	var cp := w.cat.global_position
	var to_cat := Vector3(cp.x - pos.x, 0, cp.z - pos.z).normalized()
	for nk in _nooks():
		var p := Layout.v3(nk["p"])
		if dev_nook != "" and nk["id"] != dev_nook:
			continue
		if w.house.lights.is_room_lit(nk["room"]):
			continue
		if dev_nook == "" and _player_sees([p + Vector3(0, 1.0, 0), p + Vector3(0, 0.3, 0)]):
			continue
		var r := nav.route_from(pos, nav.nearest(p, true), true, _avoid_cost)
		var pts := _route_points(r, p)
		if not _points_clear(pts):
			continue
		var l := _length(pts)
		if absf(p.y - pos.y) > 2.0:
			l += 6.0
		var away := Vector3(p.x - pos.x, 0, p.z - pos.z)
		if away.length() > 0.1:
			l += 3.0 * away.normalized().dot(to_cat)
		if l < bl:
			bl = l
			best = {"nook": nk, "route": r}
	return best


## no nook it can reach safely: a dark spot 4-9 m away, as far from the cat as it can get without
## passing it. [] when even that is cut off (it cowers where it is)
func _pick_retreat() -> Array:
	var nav := _nav()
	var cp := w.cat.global_position
	var best := []
	var bs := -INF
	var now := Vector2(pos.x - cp.x, pos.z - cp.z).length()
	for n: NavGraph.NavNode in nav.nodes.values():
		var dd := n.p.distance_to(pos)
		if dd < 4.0 or dd > 9.0 or absf(n.p.y - pos.y) > 2.0:
			continue
		if w.house.lights.is_room_lit(n.room):
			continue
		# always farther from the cat than it is now (no running back and forth)
		if Vector2(n.p.x - cp.x, n.p.z - cp.z).length() < now + 1.0:
			continue
		var r := nav.route_from(pos, n, true, _avoid_cost)
		var pts := _route_points(r)
		if not _points_clear(pts):
			continue
		var score := Vector2(n.p.x - cp.x, n.p.z - cp.z).length() - _length(pts) * 0.3
		if score > bs:
			bs = score
			best = r
	return best


func _start_flee(quiet := false) -> void:
	_seen_t = 0.0
	sight = 0.0
	_stop_hum()
	draining = ""
	# the second time on it keeps its place by the bed: hiding only buys a moment
	if stage >= 4 and boldness < 2:
		set_stage(3)
	target.paralysis = false
	_recheck_t = 0.3
	var pick := _pick_nook()
	if pick.is_empty():
		_start_retreat()
	else:
		nook = pick["nook"]
		mode = "flee"
		_path = (pick["route"] as Array).duplicate()
		_path.append(null)   # the nook itself
		_path_i = 1 if _path.size() > 2 and NavGraph.on_first_leg(pos, _path[0].p, _path[1].p) else 0
	if dev_log:
		print("[shadow] flee -> %s (cat %.2f m)" % [nook["id"] if mode == "flee" else "retreat", _cat_dist()])
	if quiet:
		return
	Sfx.shriek(pos + Vector3(0, 1.2, 0), 0.3)
	Sfx.claws(pos, 0.6)
	w.hint_once("shadow_look", "A Sombra [b]foge do seu olhar[/b]... mas não encare onde ela se esconde.", 7)


func _start_retreat() -> void:
	mode = "retreat"
	nook = {}
	_retreat_t = 0.0
	_path = _pick_retreat()
	_path_i = 1 if _path.size() > 1 and NavGraph.on_first_leg(pos, _path[0].p, _path[1].p) else 0


## flat distance to the cat on its floor (99 on another floor)
func _cat_dist() -> float:
	var cp := w.cat.global_position
	return Vector2(cp.x - pos.x, cp.z - pos.z).length() if absf(cp.y - pos.y) < 1.2 else 99.0


## running away from the cat with no nook: every half second it looks for one again; after 4 s it
## gives up and walks on (not while the cat is still close)
func _tick_retreat(dt: float) -> void:
	var here := Layout.room_at(pos)
	if here != "" and w.house.lights.is_room_lit(here):
		_banish()
		return
	_retreat_t += dt
	_recheck_t -= dt
	if _recheck_t <= 0.0:
		_recheck_t = 0.5
		if not _pick_nook().is_empty():
			_start_flee(true)
			return
		if _path_i >= _path.size():
			_path = _pick_retreat()
			_path_i = 0
	# cornered with the cat right there it stays curled up where it is, heating up like in a nook:
	# kept cornered too long, it turns on the cat
	if _retreat_t > 4.0 and _cat_dist() > 3.0:
		mode = "walk"
		sight = 0.0
		_stop_hum()
		_build_route()
		return
	var cornered := _path_i >= _path.size() and _cat_dist() < 3.0
	sight = clampf(sight + (dt / CORNER_SECS if cornered else -dt * 0.5), 0.0, 1.0)
	_hum_level(sight)
	if sight >= 1.0:
		_stop_hum()
		if start_hunt():
			mode = "charge"
			Sfx.shriek(pos + Vector3(0, 0.6, 0), 0.8)
			w.sting(0.6)
			return
		sight = 0.6
	if _path_i < _path.size():
		_run_to((_path[_path_i] as NavGraph.NavNode).p, dt)
	_dev_track()


## one step of the run toward goal (the node counter moves on once there)
func _run_to(goal: Vector3, dt: float) -> void:
	var dir := goal - pos
	var dist := dir.length()
	var sp := FLEE_SPEED * clampf(w.threat_speed, 0.85, 1.15)
	if dist < 0.08:
		_path_i += 1
		return
	pos += dir / dist * minf(dist, sp * dt)
	_moving = sp
	if Vector2(dir.x, dir.z).length() > 0.05:
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-12.0 * dt))
	# scratching and knocking: where it went can be heard
	_sfx_t -= dt
	if _sfx_t <= 0:
		_sfx_t = randf_range(0.18, 0.4)
		if randf() < 0.6:
			Sfx.claws(pos, 0.45)
		else:
			Sfx.thud(pos + Vector3(0, 0.1, 0), 0.25, 110)


func _dev_track() -> void:
	if dev_log:
		if _cat_dist() < dev_min_cat - 0.05 and _cat_dist() < CLEAR_R:
			print("[shadow] %s close to the cat: %.2f m at %s (path %d/%d)" % [mode, _cat_dist(), pos, _path_i, _path.size()])
		dev_min_cat = minf(dev_min_cat, _cat_dist())


func _tick_flee(dt: float) -> void:
	var lights := w.house.lights
	var here := Layout.room_at(pos)
	if here != "" and lights.is_room_lit(here) and here != nook["room"]:
		_banish()
		return
	# the cat stepped into its way: another way, or another nook
	_recheck_t -= dt
	if _recheck_t <= 0.0:
		_recheck_t = 0.3
		var pts := [pos]
		for i in range(_path_i, _path.size()):
			pts.append(Layout.v3(nook["p"]) if _path[i] == null else (_path[i] as NavGraph.NavNode).p)
		if not _points_clear(pts):
			_start_flee(true)
			return
	var goal: Vector3 = Layout.v3(nook["p"]) if _path_i >= _path.size() or _path[_path_i] == null else (_path[_path_i] as NavGraph.NavNode).p
	_run_to(goal, dt)
	_dev_track()
	if _path_i >= _path.size():
		_hide()


func _hide() -> void:
	mode = "hidden"
	_cue_t = randf_range(2.0, 4.0)
	_unseen_t = 0.0
	_seen_t = 0.0
	_nook_t = 0.0
	pos = Layout.v3(nook["p"])
	var dn: String = nook.get("door", "")
	if dn != "" and w.house.doors.has(dn):
		var door: Door = w.house.doors[dn]
		door.set_state("ajar")
		Sfx.creak(door.center() + Vector3(0, 1, 0), 0.45, 1.4, 0.75)
	else:
		Sfx.creak(pos + Vector3(0, 0.8, 0), 0.3, 1.0, 0.6)


## where the head shows when it peeks ("head" when the lean puts it away from the feet)
func _peek_head() -> Vector3:
	var pk: Dictionary = nook["peek"]
	if pk.has("head"):
		return Layout.v3(pk["head"])
	return Layout.v3(pk["p"]) + Vector3(0, float(pk.get("h", 1.75)), 0)


## bolder, it does not stay hidden as long
func _hide_secs() -> float:
	return HIDE_SECS * (0.5 if boldness >= 2 else 1.0)


func _bored_secs() -> float:
	return BORED_SECS * (0.5 if boldness >= 2 else 1.0)


func _tick_hidden(dt: float) -> void:
	if _lit_recent():
		_forced_out()
		return
	sight = maxf(0.0, sight - dt * 0.6)
	_nook_t += dt
	# where it hides can be heard: a slow breath, now and then a low giggle
	_cue_t -= dt
	if _cue_t <= 0.0:
		_cue_t = randf_range(CUE_SECS.x, CUE_SECS.y)
		var hp := _peek_head()
		if randf() < 0.65:
			Sfx.play("breath", hp, 0.34, randf_range(0.66, 0.76), 1.3)
		else:
			Sfx.play("giggle", hp, 0.22, randf_range(0.55, 0.62), 1.2, "Voice")
	if _player_stares(_peek_head()):
		_seen_t += dt
	else:
		_seen_t = 0.0
	if _seen_t >= SEEN_SECS:
		mode = "peek"
		_tic_t = randf_range(0.4, 0.9)
		Sfx.creak(_peek_head(), 0.3, 0.7, 0.8)
		return
	_unseen_t += dt
	if _unseen_t >= _hide_secs() or _nook_t >= _bored_secs():
		mode = "emerge"
		_seen_t = 0.0
		var nav := _nav()
		_path = nav.route_from(pos, nav.get_node(nook["exit"]), true)
		_path_i = 0


func _tick_peek(dt: float) -> void:
	if _lit_recent():
		_forced_out()
		return
	_nook_t += dt
	var stared := _player_stares(_peek_head())
	if stared:
		sight = minf(1.0, sight + dt / PEEK_SECS)
	else:
		sight = maxf(0.0, sight - dt * 0.8)
	_hum_level(sight)
	if sight >= 1.0:
		_stop_hum()
		if start_hunt():
			mode = "charge"
			body.rig.snap_pose("stand")
			Sfx.shriek(_peek_head(), 0.8)
			w.sting(0.6)
		else:
			# another ghost is already after the cat: it ducks back in
			sight = 0.0
			mode = "hidden"
			_unseen_t = 0.0
		return
	if not stared and sight <= 0.02:
		_stop_hum()
		mode = "hidden"
		_unseen_t = 0.0
		_seen_t = 0.0
		return
	# a tic of the head now and then
	_tic_t -= dt
	if _tic_t <= 0:
		_tic_t = randf_range(0.5, 1.4)
		_tic = randf_range(-0.25, 0.25)


func _tick_charge(dt: float) -> void:
	var cp := w.cat.global_position
	var sp := CHARGE_SPEED * clampf(w.threat_speed, 0.85, 1.15)
	# straight at the cat only through clear air; round the furniture by the route otherwise
	_chase_step(cp, sp, dt)
	var flat := Vector2(cp.x - pos.x, cp.z - pos.z).length()
	if flat < 0.7 and absf(cp.y - pos.y) < 1.2:
		w.cat_hit(threat_id, pos)
		_scare_t = 0.0
		end_hunt()
	elif hunt_t > 10.0:
		# lost it: gone in a puff, the slow way (no light: it stays as bold as it was)
		end_hunt()
		_banish(false)


# ---------------------------------------------------------------------- stalking (bold)


## caught in the open: the first times it runs and hides; from STALK_FROM on it stalks the cat
func _spotted() -> void:
	boldness += 1
	if dev_log:
		print("[shadow] spotted: boldness=%d -> %s" % [boldness, "stalk" if boldness >= STALK_FROM else "flee"])
	if boldness >= STALK_FROM:
		_start_stalk()
	else:
		_start_flee()


func _start_stalk() -> void:
	_seen_t = 0.0
	_caught = false
	draining = ""
	nook = {}
	target.paralysis = false
	mode = "stalk"
	_stalk_t = 0.0
	_stalk_lost = 0.0
	_stalk_speed = STALK_SLOW
	_cpath = []
	_path_i = 0
	var spot = _pick_stalk_spot()
	if spot == null:
		_stalk = "stare"
	else:
		_stalk = "back"
		_stalk_goal = spot
	if dev_log:
		print("[shadow] boldness=%d mode=stalk phase=%s goal=%s cat %.2f m" % [boldness, _stalk, _stalk_goal if _stalk == "back" else pos, _cat_dist()])
	Sfx.shriek(pos + Vector3(0, 1.2, 0), 0.25)
	Sfx.claws(pos, 0.5)
	w.hint_once("shadow_stalk", "A Sombra [b]não se esconde mais[/b]. Só a luz a expulsa: acenda o cômodo onde ela está ou leve-a até um cômodo aceso.", 8)


## where to back off to: 2-3 m from where it stands, away from the cat, on its floor and in the dark,
## reached in a straight line, and still on screen in plain sight (it wants to be watched). null if
## nowhere fits (it stares from where it is)
func _pick_stalk_spot():
	var cam := w.cam
	if cam == null:
		return null
	var cp := w.cat.global_position
	var cam_p := cam.global_position
	var away := Vector3(pos.x - cp.x, 0, pos.z - cp.z)
	if away.length() < 0.1:
		away = Vector3(-cam.global_basis.z.x, 0, -cam.global_basis.z.z)
	away = away.normalized()
	var vp := cam.get_viewport().get_visible_rect().size
	var best = null
	var bs := -INF
	for k in 13:
		var a := (k - 6) / 12.0 * PI * 1.2   # up to ~100 degrees either side of straight away
		var dir := away.rotated(Vector3.UP, a)
		for r in [STALK_BACK.y, (STALK_BACK.x + STALK_BACK.y) * 0.5, STALK_BACK.x]:
			var p: Vector3 = pos + dir * r
			var gy := w.house.ground_height(p.x, p.z, pos.y + 0.8)
			if absf(gy - pos.y) > 0.3:
				continue
			p.y = gy
			var rm := Layout.room_at(p)
			if rm == "" or w.house.lights.is_room_lit(rm):
				continue
			var head := p + Vector3(0, 1.6, 0)
			var chest := p + Vector3(0, 1.0, 0)
			if not cam.is_position_in_frustum(head) or not cam.is_position_in_frustum(chest):
				continue
			if cam_p.distance_to(chest) > SEE_REACH or w.house.blocked(cam_p, chest) or w.house.blocked(cam_p, chest, HouseBuilder.LAYER_WORLD):
				continue
			if not path_clear(w.house.space, pos, p) or not _points_clear([pos, p]):
				continue
			var sc := cam.unproject_position(chest) / vp - Vector2(0.5, 0.5)
			var score := Vector2(p.x - cp.x, p.z - cp.z).length() - absf(a) * 0.6 - sc.length() * 3.0
			if score > bs:
				bs = score
				best = p
	return best


## the cat can see it and it can see the cat (same floor, nothing solid in between)
func _eye_to_cat() -> bool:
	var cp := w.cat.global_position
	if absf(cp.y - pos.y) > 1.2:
		return false
	return not w.house.blocked(pos + Vector3(0, 1.5, 0), cp + Vector3(0, 0.25, 0))


func _tick_stalk(dt: float) -> void:
	_stalk_t += dt
	# only the light: standing in a lit room (lit on it, or it followed the cat into one)
	var here := Layout.room_at(pos)
	if here != "" and w.house.lights.is_room_lit(here):
		_banish()
		return
	var cat := w.cat
	var cp := cat.global_position
	var dist := _cat_dist()
	# the cat hidden away for long: it gives up for now and goes back for its person, as bold as ever
	if cat.mode == "hidden":
		_stalk_lost += dt
		if _stalk_lost > STALK_LOST:
			if dev_log:
				print("[shadow] stalk: lost the cat, back to its target (boldness %d)" % boldness)
			_stop_hum()
			sight = 0.0
			mode = "walk"
			_stalk = ""
			_build_route()
			return
	else:
		_stalk_lost = 0.0
	var may_heat := cat.mode != "hidden" and not w.cat_safe()
	match _stalk:
		"back":
			_run_to(_stalk_goal, dt)
			if _path_i > 0 or pos.distance_to(_stalk_goal) < 0.1 or _stalk_t > 1.5:
				_path_i = 0
				_stalk = "stare"
				Sfx.breath(pos + Vector3(0, 1.7, 0), 0.6)
		"stare":
			yaw = lerp_angle(yaw, atan2(cp.x - pos.x, cp.z - pos.z), 1.0 - exp(-5.0 * dt))
			if may_heat:
				sight = minf(1.0, sight + dt / STALK_STARE * (2.0 if dist < 1.2 else 1.0))
			if dist > STALK_KEEP or (not _eye_to_cat() and cat.mode != "hidden"):
				_stalk = "follow"
				_stalk_speed = STALK_SLOW
				_cpath = []
				if dev_log:
					print("[shadow] stalk: the cat walks away (%.2f m) -> follow" % dist)
		"follow":
			# slow at first, then faster and faster; it never cools down
			_stalk_speed = minf(STALK_FAST, _stalk_speed + STALK_ACCEL * dt)
			if cat.mode != "hidden":
				_chase_step(cp, _stalk_speed * clampf(w.threat_speed, 0.85, 1.15), dt, 8.0)
			if may_heat and _eye_to_cat():
				sight = minf(1.0, sight + dt / (STALK_STARE * 2.0))
			# colada no gato conta como alcançado mesmo com um móvel baixo no meio (senão ela fica
			# parada a meio metro, sem disparar)
			if dist < STALK_REACH and (_eye_to_cat() or dist < 0.8):
				sight = 1.0
	_hum_level(sight)
	if _hum:
		_hum.set_pos(pos + Vector3(0, 1.2, 0))
	if dev_log:
		_stalk_log_t -= dt
		if _stalk_log_t <= 0.0:
			_stalk_log_t = 0.5
			print("[shadow] boldness=%d mode=stalk phase=%s speed=%.2f sight=%.2f cat=%.2f in_view=%s" % [boldness, _stalk, _stalk_speed if _stalk == "follow" else _moving, sight, dist, _player_sees(_body_points())])
	if sight >= 1.0 and may_heat:
		# always through the Director: with another hunter after the cat it holds, staring, red hot
		if start_hunt():
			_stop_hum()
			if dev_log:
				print("[shadow] stalk: charge (cat %.2f m)" % dist)
			_stalk = ""
			_cpath = []
			mode = "charge"
			Sfx.shriek(pos + Vector3(0, 1.4, 0), 0.8)
			w.sting(0.6)
			return
		sight = 0.97


## the jump scare: its face fills the camera for a few frames, then smoke
func _tick_scare(dt: float) -> void:
	_scare_t += dt
	var cam := w.cam
	var fwd := -cam.global_basis.z
	body.alpha = 1.0
	body.glare = 1.0
	body.heat = 1.0
	runner.alpha = 0.0
	peek.alpha = 0.0
	body.rig.pose = "stand"
	body.rig.jerky = 0.0
	var hs := 1.12
	body.global_position = cam.global_position + fwd * 0.55 - Vector3(0, 1.85 * hs, 0)
	body.rotation.y = atan2(-fwd.x, -fwd.z)
	body.rig.look_target = cam.global_position
	body.tick(dt)
	if _scare_t > 0.35:
		_scare_t = -1.0
		w.flash(0.5, Color("#200000"))
		w.burst_smoke(cam.global_position + fwd * 0.8)
		Sfx.shriek(cam.global_position + fwd, 0.8)
		repel()


const LIT_MEMORY := 0.5


## the light of the nook's room (or the room it is in): remembered for a moment, so a flicker or
## a bulb dying on the wrong frame doesn't let it walk out of a lit room; while it is in the nook
## or crawling out, the bulb holds on
func _track_light(dt: float) -> void:
	var rm: String = nook.get("room", "") if not nook.is_empty() else Layout.room_at(pos)
	var lights := w.house.lights
	if rm != "" and lights.is_room_lit(rm):
		_lit_t = LIT_MEMORY
		if mode == "hidden" or mode == "peek" or mode == "emerge":
			var l = lights.by_room.get(rm)
			if l and l.on:
				l.life = maxf(l.life, 5.0)
				l.warn = 0.0
	else:
		_lit_t -= dt


func _lit_recent() -> bool:
	return _lit_t > 0.0


## the light came on in the room where it hides: it has to crawl out, and out in the light it dies
func _forced_out() -> void:
	_stop_hum()
	sight = 0.0
	mode = "emerge"
	_seen_t = 0.0
	Sfx.shriek(_peek_head(), 0.45)
	var nav := _nav()
	_path = nav.route_from(pos, nav.get_node(nook["exit"]), true)
	_path_i = 0
	if dev_log:
		print("[shadow] light on in %s: forced out of the nook" % nook["room"])


func _tick_emerge(dt: float) -> void:
	var lights := w.house.lights
	var lit := _lit_recent()
	# in a lit room it doesn't run for another nook when seen: it is already done for
	if not lit and _seen(_body_points(), dt):
		_spotted()
		return
	var goal: Vector3 = _path[_path_i].p if _path_i < _path.size() else _nav().get_node(nook["exit"]).p
	var dir := goal - pos
	var dist := dir.length()
	var sp := (1.4 if lit else 0.85) * w.threat_speed
	if dist < 0.06:
		_path_i += 1
		if _path_i >= _path.size():
			# out in the room: the light kills it, the dark sends it on its way again
			if lit or lights.is_room_lit(nook["room"]):
				_banish()
				return
			mode = "walk"
			nook = {}
			_build_route()
	else:
		pos += dir / dist * minf(dist, sp * dt)
		_moving = sp
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-6.0 * dt))


func _hum_level(v: float) -> void:
	if _hum == null and v > 0.05:
		_hum = Sfx.loop("hum", _peek_head() if mode == "peek" else pos + Vector3(0, 0.6, 0), 1.0)
	if _hum:
		_hum.set_level(v * 0.9)


func _stop_hum() -> void:
	if _hum:
		_hum.stop(0.3)
		_hum = null


func on_hunt_end() -> void:
	sight = 0.0


## gone in a flash of light (only the light makes it shy again); light = false: it just loses the
## cat and vanishes in a puff
func _banish(light := true) -> void:
	if light:
		if dev_log and boldness > 0:
			print("[shadow] banished in the light: boldness %d -> 0" % boldness)
		boldness = 0
	_stop_hum()
	Sfx.shriek(pos + Vector3(0, 1.5, 0), 0.7)
	w.flash(0.25, Color("#ffe6c0"))
	w.shake(0.6)
	w.burst_smoke(pos + Vector3(0, 1.0, 0))
	if stage >= 4:
		target.say(pick(["Ah! A luz...", "Ufa... foi só um sonho...", "O que... o que era aquilo?"]), 2.6, "scared")
	target.paralysis = false
	repel()


func can_hiss(p: Vector3) -> bool:
	return stage >= 2 and mode == "walk" and p.distance_to(pos) < 2.6 and absf(p.y - pos.y) < 1.5


func on_hiss(p: Vector3, strong: bool) -> bool:
	if not strong or not can_hiss(p):
		return false
	if stage >= 4:
		set_stage(3)
	ri = maxi(0, ri - 1)
	pos = route[ri].p
	target.paralysis = false
	stall = d(5)
	Sfx.shriek(pos + Vector3(0, 1.5, 0), 0.35)
	return true


func tick_stalled(dt: float) -> void:
	_update_visual(dt)


## which of its three bodies shows: walking (the MPFB body), running (shadow_run, on its back like a
## spider; it also charges in it) or hiding (shadow_peek: only the head and the hands on the edge)
func _form() -> String:
	if mode in ["flee", "retreat", "charge"]:
		return "run"
	if mode == "stalk":
		return "run" if _stalk == "back" or (_stalk == "follow" and _stalk_speed > 2.2) else "walk"
	# it crawls out of the nook on all fours, and only stands up once clear of the furniture
	if mode == "emerge" and _path_i == 0:
		return "run"
	if mode in ["hidden", "peek"] and not nook.is_empty():
		return "peek"
	return "walk"


func _update_visual(dt: float) -> void:
	if _scare_t >= 0.0:
		return
	var show := stage >= 2
	vis = lerpf(vis, 1.0 if show else 0.0, 1.0 - exp(-3.0 * dt))
	var form := _form()
	if form != _cur_form:
		# a puff of smoke hides the swap
		if vis > 0.3 and _cur_form != "" and form != "peek":
			w.burst_smoke(pos + Vector3(0, 0.8, 0), Color(0.0, 0.0, 0.0, 0.55))
		if form == "run":
			runner.rig.snap_pose("spider")
		_cur_form = form
	_glare = lerpf(_glare, 1.0 if mode == "charge" else sight, 1.0 - exp(-6.0 * dt))
	_update_red()
	body.alpha = vis if form == "walk" else 0.0
	runner.alpha = vis if form == "run" else 0.0
	# hidden it does not show at all; peeking, it slides out from behind the edge in a quarter second
	_out = move_toward(_out, 1.0 if mode == "peek" else 0.0, dt / (0.25 if mode == "peek" else 0.15))
	peek.alpha = vis * _out if form == "peek" else 0.0
	# the turn starts once the head is out, slow at first; hiding again it snaps back
	if mode == "peek" and _out > 0.9 and not dev_no_look:
		_look_k = move_toward(_look_k, 1.0, dt * (0.6 + 1.6 * _look_k))
	elif mode != "peek":
		_look_k = 0.0
	if form == "walk":
		body.glare = _glare
		body.heat = _glare * (1.0 if mode == "stalk" else 0.6)
		var rig := body.rig
		rig.jerky = 0.0
		rig.pose = "reach" if stage == 5 else "stand"
		rig.speed = _moving
		rig.look_target = w.cat.global_position + Vector3(0, 0.25, 0) if (_caught and mode == "walk") or mode == "stalk" else null
		body.global_position = pos + Vector3(0, sin(Time.get_ticks_msec() * 0.0012) * 0.03 if mode == "walk" else 0.0, 0)
		body.rotation.y = yaw
		body.tick(dt)
	elif form == "run":
		runner.glare = _glare
		runner.heat = _glare * (1.0 if mode == "stalk" else 0.55)
		var rr := runner.rig
		rr.jerky = 10.0
		rr.pose = "spider"
		rr.speed = _moving
		runner.global_position = pos
		# on its back it runs head first: the model faces away from where it goes
		runner.rotation.y = yaw + PI
		runner.tick(dt)
	else:
		peek.heat = _glare
		var fr := _peek_frames()
		peek.place(fr[0], fr[1])
		peek.tick(dt)


## stalking in the open it casts red on the cat, like the peeking head does
func _update_red() -> void:
	var on := mode in ["stalk", "charge"] and vis > 0.3
	var h := _glare if on else 0.0
	_red.light_energy = 1.8 * h * h * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.001 * lerpf(5.0, 15.0, h)))
	_red.visible = _red.light_energy > 0.01
	if _red.visible:
		var cp := w.cat.global_position
		var f := Vector3(cp.x - pos.x, 0, cp.z - pos.z)
		f = f.normalized() if f.length() > 0.05 else Vector3(sin(yaw), 0, cos(yaw))
		_red.global_position = pos + Vector3(0, 1.3, 0) + f * 0.5


## the head and the two hands of the hiding body: [head frame, [hand_l, hand_r]] (ShadowPeek.place).
## Behind an edge the head leans out past it, tipped toward the lean; both hands grip the edge, one low
## and one above, the fingers coming round to the front. From under a bed or a sofa ("low") the head
## lies almost on its side on the floor and the hands are flat beside it. "tilt" and "hands" in the
## nook's "peek" override these.
func _peek_frames() -> Array:
	var pk: Dictionary = nook["peek"]
	var yw := float(pk["yaw"])
	var f := Vector3(sin(yw), 0, cos(yw))
	var lean := Vector3(-cos(yw), 0, sin(yw)) * (-1.0 if pk.get("side", "r") == "l" else 1.0)
	var low: bool = nook.get("low", false)
	var hp := _peek_head()
	if nook.get("over", false):
		return _peek_over(pk, f, hp)
	var tilt := float(pk.get("tilt", 1.2 if low else 0.55))
	# tic: the head twitches now and then
	var up := (Vector3.UP * cos(tilt + _tic) + lean * sin(tilt + _tic)).normalized()
	var back := (f if low else lean) * -0.3 * (1.0 - _out)
	# the neck goes back behind the edge, where the furniture hides its cut
	var hb := Basis(up.cross(f).normalized(), up, f)
	# once out it turns, slowly, to look straight at the cat (no further than the edge hides the neck)
	if _look_k > 0.001:
		var want := (w.cat.global_position + Vector3(0, 0.25, 0) - hp).normalized()
		var ang := f.angle_to(want)
		if ang > 0.01:
			var axis := f.cross(want).normalized()
			if axis.is_normalized():
				hb = Basis(axis, minf(ang, LOOK_MAX) * _look_k) * hb
		# the longer it is stared at, the further the head cocks over, like a curious bird
		hb = Basis(hb.z.normalized(), _glare * 0.5 * _look_k) * hb
	var head := Transform3D(hb, hp - up * 0.07 - f * (0.0 if low else 0.08) + back)
	var hands := []
	var given: Array = pk.get("hands", [])
	if low:
		var x := Vector3.UP.cross(f).normalized()
		var fy := Layout.v3(nook["p"]).y + 0.03
		for i in 2:
			var p: Vector3 = Layout.v3(given[i]) if given.size() == 2 else hp + x * (0.22 if i == 0 else -0.22) + f * 0.12
			p.y = fy
			# fingers ahead, palms down
			hands.append(Transform3D(Basis(f.cross(Vector3.UP).normalized(), f, Vector3.UP), p + back))
	else:
		var grip: Vector3 = Layout.v3(pk["hand"]) if pk.has("hand") else hp + Vector3(0, -0.3, 0) - lean * 0.08
		var spots := [grip, grip + Vector3(0, 0.42, 0)]
		if given.size() == 2:
			spots = [Layout.v3(given[0]), Layout.v3(given[1])]
		# the hand on its leaning side goes low
		if pk.get("side", "r") != "l":
			spots.reverse()
		for i in 2:
			# the wrist behind the edge, the fingers toward us, the back of the hand outward
			var wrist: Vector3 = spots[i] - f * 0.1
			hands.append(Transform3D(Basis(f.cross(lean).normalized(), f, lean), wrist + back))
	return [head, hands]


## "over": hiding behind a bed, it rises over the far edge of the mattress: the head comes up from
## behind it (the mattress hides the neck), both hands flat on top, the fingers curling toward us
func _peek_over(pk: Dictionary, f: Vector3, hp: Vector3) -> Array:
	var sink := Vector3.DOWN * 0.32 * (1.0 - _out)
	var tilt := float(pk.get("tilt", 0.25)) + _tic
	var x := Vector3.UP.cross(f).normalized()
	var up := (Vector3.UP * cos(tilt) + x * sin(tilt)).normalized()
	var hb := Basis(up.cross(f).normalized(), up, f).orthonormalized()
	if _look_k > 0.001:
		var want := (w.cat.global_position + Vector3(0, 0.25, 0) - hp).normalized()
		var ang := f.angle_to(want)
		if ang > 0.01:
			var axis := f.cross(want).normalized()
			if axis.is_normalized():
				hb = Basis(axis, minf(ang, LOOK_MAX) * _look_k) * hb
		hb = Basis(hb.z.normalized(), _glare * 0.5 * _look_k) * hb
	var head := Transform3D(hb, hp + sink)
	var hands := []
	var given: Array = pk.get("hands", [])
	for i in 2:
		var p: Vector3 = Layout.v3(given[i]) if given.size() == 2 else hp + x * (0.26 if i == 0 else -0.26) + f * 0.1 + Vector3(0, -0.1, 0)
		# palms down on the mattress, fingers ahead; they slide back off it as it sinks
		hands.append(Transform3D(Basis(f.cross(Vector3.UP).normalized(), f, Vector3.UP), p - f * 0.18 * (1.0 - _out) + sink * 0.4))
	return [head, hands]


func focus():
	if stage == 0:
		return null
	return pos + Vector3(0, 1, 0)


## the room it hides in ("" unless it is in a nook: hidden, peeking or crawling out), for the HUD
func hidden_room() -> String:
	if not enabled or stage == 0 or nook.is_empty() or not mode in ["hidden", "peek", "emerge"]:
		return ""
	return nook["room"]


## where its head shows in that nook (the objective marker points here); ZERO when not hiding
func hidden_nook_pos() -> Vector3:
	if hidden_room() == "":
		return Vector3.ZERO
	return _peek_head() if nook.has("peek") else Layout.v3(nook["p"]) + Vector3(0, 0.8, 0)


func entity():
	return pos if stage >= 2 and mode != "hidden" else null


func urgency() -> float:
	if mode == "peek":
		return 0.5 + sight * 0.5
	if mode == "stalk":
		return 0.6 + sight * 0.4
	if stage == 3:
		return 0.45 + (float(ri) / maxf(1.0, route.size())) * 0.3
	return stage / 5.0


func describe_death() -> Dictionary:
	var where := tr("no quarto de %s") % target.display_name if target.in_bed else "no escuro"
	return {
		"title": tr("%s foi levado(a) pela Sombra") % target.display_name,
		"why": tr("A Sombra atravessou a casa e chegou %s. Ela só se aproxima onde não há luz.") % where,
		"tip": "Olhe para ela: ela foge e se esconde. Acenda a luz do cômodo onde ela vai sair e ela some ao pisar na luz. Não encare o esconderijo: ela vem atrás de você.",
	}
