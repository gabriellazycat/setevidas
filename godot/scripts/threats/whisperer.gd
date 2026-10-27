class_name WhispererThreat
extends Threat
## O Sussurrador: lives in the wires. A device switches itself on, whispers, and the target
## sleepwalks to it. Pull the plug to silence it; it may jump to another appliance. Fake noises in
## other rooms are bait (even the cat's ears can be fooled). Port of Whisperer.ts.
## Pulling the plug is a gamble: it dies, jumps to another device, or comes out of the socket as a
## white ball that floats after the cat. The ball fades out on its own.
## The possessed device and its plug and cord blink green, yellow and red in no order (every
## 0.4-1.2 s; the harsher the static, the more red). The colour when the plug comes out decides the
## ball: green never, yellow 25%, red 60%. The static changes with it (a hum, crackles, a harsh hiss),
## so it can be told apart by ear too.

const DEVICE_SPOT := {"tv": "tv", "radio": "radio", "laptop": "laptop"}


## where the sleepwalker stands in front of a device; the night light moves, so it gets one on the fly
func dev_spot(dv) -> Dictionary:
	if DEVICE_SPOT.has(dv.id):
		return Layout.spot(DEVICE_SPOT[dv.id])
	var front: Vector3 = dv.pos + Vector3(0, 0, 0.6)
	front.y = dv.floor_y
	# the walk there needs a nav node, like the spots of layout.json
	return {"p": [front.x, front.y, front.z], "yaw": PI, "node": w.house.nav.nearest(front).id}


static func usable(d) -> bool:
	return d.plugged and not d.hidden

var dev = null   # House.Device
var whisper = null
var stat = null
var replug := {}
var owner_sent := false
var hops := 0
var decoy_t := 6.0
var decoy_pos = null
var decoy_until := 0.0
var shown_decoy_hint := false
var harsh := 0.0          # 0..1: how much the colours lean to red
var light := 0            # 0 green, 1 yellow, 2 red: the traffic light on the device
var _light_t := 0.0
const LIGHT_COLS := [Color(0.3, 1.0, 0.42), Color(1.0, 0.82, 0.22), Color(1.0, 0.18, 0.12)]
const ORB_ODDS := [0.0, 0.25, 0.6]
var crackle_t := 0.0
var orb: Node3D
var orb_light: OmniLight3D
var orb_mat: ShaderMaterial
var orb_from := Vector3.ZERO   # where it came out of the device
var orb_out := Vector3.ZERO    # where it hangs in the air staring
var orb_smoke: GPUParticles3D
var orb_voice = null
var orb_pos := Vector3.ZERO
var orb_life := 0.0
var orb_path: Array = []
var orb_i := 0
var orb_repath := 0.0
var woke := false         # a meow broke the trance: it waits for her to lie down again
var _bed_t := 0.0
var dev_log := false      # dev: print the trance being broken and resumed (autopilot --whisperlog)

const REWAKE_SECS := 6.0  # she has to lie in bed this long before it calls her again

## the ball comes out of the device's screen / speaker, swells into a face, hangs in the air staring
## at the cat (ORB_STARE), then drifts after it slowly and faster and faster, never as fast as the
## cat running (4.4), until it burns out
const ORB_RISE := 1.4
const ORB_STARE := 3.0
const ORB_CHASE := 11.0
const ORB_LIFE := ORB_RISE + ORB_STARE + ORB_CHASE
const ORB_V0 := 0.6
const ORB_VMAX := 3.6


func _init() -> void:
	threat_id = "whisperer"
	display_name = "O Sussurrador"


func setup(world: Game) -> void:
	super.setup(world)
	dev_log = OS.get_cmdline_user_args().has("--whisperlog")
	orb = Node3D.new()
	add_child(orb)
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.6, 0.6)
	mi.mesh = qm
	orb_mat = ShaderMaterial.new()
	orb_mat.shader = load("res://shaders/whisper_face.gdshader")
	mi.material_override = orb_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.add_child(mi)
	orb_light = OmniLight3D.new()
	orb_light.light_color = Color(0.8, 0.92, 1.0)
	orb_light.omni_range = 3.2
	orb_light.light_energy = 1.4
	orb.add_child(orb_light)
	orb_smoke = FX.wisps(Color(0.8, 0.95, 1.0, 0.45), 0.4, 0.12, 30, true, 0.1)
	orb.add_child(orb_smoke)
	orb.visible = false


func reset() -> void:
	stage = 0
	t = 0.0
	if dev:
		dev.glow = 0.0
		if w:
			_clear_light(dev)
	dev = null
	if whisper:
		whisper.stop(0.5)
	if stat:
		stat.stop(0.5)
	whisper = null
	stat = null
	owner_sent = false
	woke = false
	_bed_t = 0.0
	hops = 0
	decoy_pos = null
	decoy_until = 0.0
	if w:
		w.house.lights.get_light(14).set_on(false)
		if target and target.task_name == "whisper":
			target.abort()


func replug_all() -> void:
	for d in w.house.devices:
		w.house.set_plugged(d, true)
	replug.clear()


func on_stage(s: int, _prev: int) -> void:
	if s == 1:
		var plugged := []
		for d in w.house.devices:
			if usable(d):
				plugged.append(d)
		if plugged.is_empty():
			stage = 0
			cooldown = 8.0
			return
		dev = pick(plugged)
		hops = 0
		_roll_harsh()
		decoy_t = 4.0
		whisper = Sfx.loop("whisper", dev.pos, 0.9)
		whisper.set_level(0.25)
	if s == 2 and dev and _prev < 2:
		_light_up(dev, 0.45, 0.6)
	if s == 3 and dev:
		_send_owner()
	if s == 5 and dev:
		w.sting(0.45)
		Sfx.shriek(dev.pos, 0.3)


func _light_up(dv, static_level: float, whisper_level: float) -> void:
	if stat:
		stat.stop(0.2)
	stat = Sfx.loop("static", dv.pos, 0.8)
	stat.set_level(static_level)
	_pick_light(dv)
	if whisper:
		whisper.set_level(whisper_level)
	Sfx.click(dv.pos, 0.5)
	var sl = w.house.lights.get_light(14)
	var off := Vector3(0, 0.1, -0.5) if dv.id != "radio" else Vector3(-0.5, 0.1, 0)
	sl.light.global_position = dv.pos + off
	sl.base_color = Color("#ffb36b") if dv.id == "radio" else Color("#9fc8ff")
	sl.light.light_color = sl.base_color
	sl.set_on(true)
	sl.flicker = 0.35


## a new colour, at random, leaning to red with the harshness; the device, its plug and cord, the
## light in the room and the static all follow
func _pick_light(dv) -> void:
	var wg := (1.0 - harsh) * 1.2 + 0.2
	var wy := 0.6
	var wr := harsh * 1.2 + 0.2
	var r := randf() * (wg + wy + wr)
	var nl := 0 if r < wg else (1 if r < wg + wy else 2)
	light = nl
	_light_t = randf_range(0.4, 1.2)
	_show_light(dv)


func _show_light(dv) -> void:
	var c: Color = LIGHT_COLS[light]
	if dv.screen_mat:
		dv.screen_mat.set_shader_parameter("light_col", c)
		dv.screen_mat.set_shader_parameter("light_mix", 1.0)
	var pm := dv.plug.material_override as StandardMaterial3D
	if pm:
		pm.emission_enabled = true
		pm.emission = c
		pm.emission_energy_multiplier = 2.5
	if dv.id == "nightlight" and w.house.nightlight_glow:
		w.house.nightlight_glow.light_color = c
	var sl = w.house.lights.get_light(14)
	if sl and sl.on:
		# the room is only tinted: the colour is on the device itself
		sl.base_color = (Color("#ffb36b") if dv.id == "radio" else Color("#9fc8ff")).lerp(c, 0.35)
		sl.light.light_color = sl.base_color
	# by ear: a low hum, crackling, a harsh hiss
	if stat and is_instance_valid(stat.player):
		stat.player.pitch_scale = [0.62, 1.0, 1.35][light]
		stat.set_level([0.3, 0.55, 0.95][light] * (1.0 if stage >= 2 else 0.6))


func _clear_light(dv) -> void:
	if dv == null:
		return
	if dv.screen_mat:
		dv.screen_mat.set_shader_parameter("light_mix", 0.0)
	var pm := dv.plug.material_override as StandardMaterial3D
	if pm:
		pm.emission_enabled = false
	if dv.id == "nightlight" and w.house.nightlight_glow:
		w.house.nightlight_glow.light_color = Color(1.0, 0.76, 0.46)


func _hop_to(nxt) -> void:
	var old = dev
	old.glow = 0.0
	_clear_light(old)
	Sfx.shriek(old.pos, 0.3)
	Sfx.click(old.pos, 0.6)
	replug[old] = d(randf_range(70, 100))
	hops += 1
	dev = nxt
	_roll_harsh()
	if whisper:
		whisper.stop(0.2)
	whisper = Sfx.loop("whisper", nxt.pos, 0.9)
	_light_up(nxt, 0.6, 0.7)
	Sfx.shriek(nxt.pos, 0.2)
	w.shake(0.25)
	w.hint(tr("Ele pulou para %s!") % tr(nxt.name), 3.2)
	if stage >= 3:
		if target.task_name == "whisper":
			target.abort()
		owner_sent = false
		_send_owner()


func _play_decoy() -> void:
	var rooms := []
	for r in Layout.rooms():
		if r["id"] != "sotao" and r["id"] != "varanda" and (dev == null or r["id"] != dev.room):
			rooms.append(r)
	var r: Dictionary = pick(rooms)
	var p := Vector3((r["x0"] + r["x1"]) / 2, r["y"] + 1.0, (r["z0"] + r["z1"]) / 2)
	if p.distance_to(w.cat.global_position) < 4:
		return
	var kind := randi() % 4
	if kind == 0:
		for i in 4:
			get_tree().create_timer(i * 0.52).timeout.connect(func(): Sfx.human_step(Vector3(p.x, r["y"], p.z), false))
	elif kind == 1:
		Sfx.voice(p, 8, "call", 1.05)
	elif kind == 2:
		Sfx.knock(p, 3, 0.6)
	else:
		Sfx.creak(p, 0.5, 1.4, 1.0)
	decoy_pos = p
	decoy_until = 3.4
	if not shown_decoy_hint:
		shown_decoy_hint = true
		w.hint("Nem todo som é de verdade. O Sussurrador imita a casa.", 4.0)


func _send_owner() -> void:
	if dev == null:
		return
	var spot := dev_spot(dev)
	owner_sent = target.run("whisper", [
		{"t": "say", "text": "...", "dur": 1.0},
		{"t": "spot", "spot": spot, "style": "hypno"},
		{"t": "until", "cond": func(): return stage == 0 or stage >= 3, "pose": "stare"},
		{"t": "until", "cond": func(): return stage == 0, "pose": "stare"},
	], 3)


## she lost the trance (a meow woke her and sent her to bed) while the device is still possessed:
## it goes back to waiting and calls her again once she has been lying down for a while, until the
## plug comes out
func _lost_owner() -> void:
	woke = true
	_bed_t = 0.0
	owner_sent = false
	target.paralysis = false
	if dev_log:
		print("[whisper] trance broken on %s (stage %d): waiting for bed" % [dev.name, stage])
	set_stage(2)


func tick_threat(dt: float) -> void:
	if enabled:
		for dv in replug.keys():
			var tl: float = replug[dv] - dt
			if tl <= 0:
				replug.erase(dv)
				w.house.set_plugged(dv, true)
				Sfx.creak(dv.outlet, 0.15, 0.6, 2.5)
				Sfx.click(dv.outlet, 0.4)
			else:
				replug[dv] = tl
	super.tick_threat(dt)


func tick(dt: float) -> void:
	if hunting_cat:
		_orb_tick(dt)
		return
	var dv = dev
	if dv == null:
		return
	if not dv.plugged:
		var others := []
		for x in w.house.devices:
			if usable(x) and x != dv:
				others.append(x)
		var r := randf()
		var ball := _orb_chance()
		print_verbose(tr("WHISPER unplugged on %s: chance %.2f") % [["green", "yellow", "red"][light], ball])
		_clear_light(dv)
		if stage >= 1 and r < ball and _release_orb():
			return
		var chance := 0.7 - hops * 0.28
		if stage >= 2 and not others.is_empty() and randf() < chance:
			_hop_to(pick(others))
		else:
			_banish()
		return
	if stage >= 1:
		_light_t -= dt
		if _light_t <= 0.0:
			_pick_light(dv)
	_crackle(dt, dv)
	if decoy_until > 0:
		decoy_until -= dt
	if stage >= 1 and stage <= 3:
		decoy_t -= dt
		if decoy_t <= 0:
			decoy_t = randf_range(7, 11) / maxf(0.6, w.threat_speed)
			_play_decoy()
	var glow_target := 0.0
	if stage == 1:
		glow_target = 0.12 + randf() * 0.15
	elif stage >= 2:
		glow_target = 0.85 + randf() * 0.15
	dv.glow = lerpf(dv.glow, glow_target, 1.0 - exp(-10.0 * dt))
	if stage == 1 and t > d(8):
		set_stage(2)
	elif stage == 2 and woke:
		# back in bed after the meow: no fear while she lies there, then it calls her again
		_bed_t = _bed_t + dt if target.in_bed else 0.0
		# (if she never gets to bed, it does not wait forever)
		if (_bed_t >= REWAKE_SECS or (t > d(30) and not target.in_bed)) and (may_attack or target.in_bed):
			woke = false
			if dev_log:
				print("[whisper] calling %s again from %s" % [target.display_name, dev.name])
			set_stage(3)
	elif stage == 2 and t > d(9):
		if may_attack or target.in_bed:
			set_stage(3)
	elif stage == 3:
		if owner_sent and target.task_name != "whisper":
			_lost_owner()
			return
		if not owner_sent:
			if t > d(9):
				t = 0.0
				_send_owner()
		else:
			var sp := Layout.v3(dev_spot(dv)["p"])
			if target.global_position.distance_to(sp) < 0.25 and may_attack:
				set_stage(4)
		if stat:
			stat.set_level(0.6)
		target.add_fear(0.4 * dt)
	elif stage == 4:
		target.add_fear(6.0 * dt)
		if target.task_name != "whisper":
			_lost_owner()
		elif t > d(7):
			set_stage(5)
	elif stage == 5:
		if target.task_name != "whisper":
			_lost_owner()
			return
		target.add_fear(9.0 * dt)
		dv.glow = 1.0


# ---------------------------------------------------------------------- the gamble and the ball


## how harsh the static sounds on this device; later nights crackle more often
func _roll_harsh() -> void:
	var week := clampf((w.night - 2) / 5.0, 0.0, 1.0)
	harsh = clampf(randf() * (0.55 + 0.45 * week) + 0.15 * week, 0.0, 1.0)


## the colour on the device when the plug comes out: green never, yellow 25%, red 60%
func _orb_chance() -> float:
	return ORB_ODDS[light]


## yellow crackles, red crackles and spits sparks: the colour by ear
func _crackle(dt: float, dv) -> void:
	if stage < 1 or light == 0:
		return
	crackle_t -= dt
	if crackle_t <= 0:
		crackle_t = (0.45 if light == 1 else 0.2) * randf_range(0.6, 1.4)
		Sfx.click(dv.pos, 0.3 if light == 1 else 0.6)
		if light == 2 and randf() < 0.3:
			Sfx.buzz(dv.pos, 0.4)
			if w.cat.global_position.distance_to(dv.pos) < 4.0:
				w.sparks_at(dv.outlet)


## something to haunt: a device plugged in somewhere (else it does not wake at all)
func can_wake() -> bool:
	for d in w.house.devices:
		if usable(d):
			return true
	return false


func _release_orb() -> bool:
	if not start_hunt():
		return false
	return true


func on_hunt_start() -> void:
	var dv = dev
	# out of the device itself (its screen / speaker), not the wall socket
	orb_from = dv.light_pos if dv.light_pos != Vector3.ZERO else dv.pos + Vector3(0, 0.3, 0)
	var away: Vector3 = dv.normal if dv.normal.length() > 0.1 else Vector3(0, 0, 1)
	var cp0 := w.cat.global_position
	orb_out = orb_from + away.normalized() * 0.55 + Vector3(0, 0.25, 0)
	orb_out.y = maxf(orb_out.y, cp0.y + 0.6)
	orb_pos = orb_from
	orb_life = ORB_LIFE
	orb_path = []
	orb_repath = 0.0
	dv.glow = 0.0
	replug[dv] = d(randf_range(70, 100))
	Sfx.shriek(dv.pos, 0.55)
	w.sparks_at(dv.outlet)
	w.flash(0.2, Color("#dff4ff"))
	if whisper:
		whisper.stop(0.3)
	if stat:
		stat.stop(0.3)
	whisper = null
	stat = null
	w.house.lights.get_light(14).set_on(false)
	if target.task_name == "whisper":
		target.abort()
		target.go_to_bed(2)
	dev = null
	orb_voice = Sfx.loop("whisper", orb_pos, 0.9)
	orb_voice.set_level(0.8)
	orb.visible = true
	orb.global_position = orb_pos


func on_hunt_end() -> void:
	orb.visible = false
	if orb_voice:
		orb_voice.stop(0.6)
	orb_voice = null
	w.burst_smoke(orb_pos, Color(0.8, 0.9, 1.0, 0.4))
	Sfx.click(orb_pos, 0.4)
	if enabled and dev == null:
		repel()


func _orb_tick(dt: float) -> void:
	orb_life -= dt
	var age := ORB_LIFE - orb_life
	var rise := clampf(age / ORB_RISE, 0.0, 1.0)
	orb.scale = Vector3.ONE * maxf(0.05, rise)
	orb_mat.set_shader_parameter("glitch", 0.9 - rise * 0.6)
	if age < ORB_RISE + ORB_STARE:
		# out of the device and up into the air, then still, staring, the mouth slowly dropping open
		var k := smoothstep(0.0, 1.0, rise)
		orb_pos = orb_from.lerp(orb_out, k)
		var stare := clampf((age - ORB_RISE) / ORB_STARE, 0.0, 1.0)
		orb_mat.set_shader_parameter("scream", stare * 0.6)
		orb_mat.set_shader_parameter("alpha", rise)
		orb.global_position = orb_pos + Vector3(0, sin(age * 2.0) * 0.03, 0)
		orb_light.light_energy = 1.2 * rise * (0.8 + 0.2 * sin(age * 23.0))
		if orb_voice:
			orb_voice.set_pos(orb_pos)
			orb_voice.set_level(0.6 + stare * 0.4)
		return
	var cp := w.cat.global_position + Vector3(0, 0.25, 0)
	var nav := w.house.nav
	var goal := cp
	# straight at the cat only when nothing solid is in the way (it never floats through furniture)
	var sees := absf(orb_pos.y - cp.y) < 1.4 and not w.house.blocked(orb_pos, cp) and path_clear(w.house.space, orb_pos, cp, 0.14, 0.0)
	if not sees:
		orb_repath -= dt
		if orb_repath <= 0 or orb_path.is_empty():
			orb_repath = 0.7
			# the orb floats 0.45 m over the nav line
			var foot := orb_pos - Vector3(0, 0.45, 0)
			orb_path = nav.route_from(foot, nav.nearest(cp))
			orb_i = 1 if orb_path.size() > 1 and NavGraph.on_first_leg(foot, orb_path[0].p, orb_path[1].p) else 0
		while orb_i < orb_path.size() and Vector2(orb_pos.x - orb_path[orb_i].p.x, orb_pos.z - orb_path[orb_i].p.z).length() < 0.2:
			orb_i += 1
		if orb_i < orb_path.size():
			goal = orb_path[orb_i].p + Vector3(0, 0.45, 0)
	var dir := goal - orb_pos
	var dist := dir.length()
	# slow at first, faster and faster, never as fast as the cat running
	var chase_k := clampf((age - ORB_RISE - ORB_STARE) / (ORB_CHASE * 0.8), 0.0, 1.0)
	var sp := minf(lerpf(ORB_V0, ORB_VMAX, chase_k * chase_k), ORB_VMAX)
	if dist > 0.01:
		orb_pos += dir / dist * minf(dist, sp * dt)
	var fade := clampf(orb_life / 2.0, 0.0, 1.0)
	orb.global_position = orb_pos + Vector3(0, sin(Time.get_ticks_msec() * 0.004) * 0.06, 0)
	orb_mat.set_shader_parameter("alpha", fade)
	orb_mat.set_shader_parameter("scream", 0.6 + 0.4 * chase_k)
	orb_light.light_energy = 1.4 * fade * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.02))
	if orb_voice:
		orb_voice.set_pos(orb_pos)
	if orb_life <= 0:
		end_hunt()
		return
	try_catch(orb_pos - Vector3(0, 0.25, 0), 0.5)


func _banish() -> void:
	var dv = dev
	Sfx.shriek(dv.pos, 0.35)
	Sfx.click(dv.pos, 0.6)
	w.sparks_at(dv.outlet)
	dv.glow = 0.0
	replug[dv] = d(randf_range(70, 100))
	var was_hypno := target.task_name == "whisper"
	repel()
	if was_hypno:
		target.add_fear(5)
		target.say(pick(["O que eu tô fazendo aqui...?", "Ai... eu tava sonhando com uma voz...", "{cat}? Por que a TV... deixa pra lá."]), 3.0, "whisper")
		target.go_to_bed(2)


func can_hiss(p: Vector3) -> bool:
	if hunting_cat:
		return p.distance_to(orb_pos) < 2.0
	return dev != null and stage >= 1 and p.distance_to(dev.pos) < 2.2


func describe_death() -> Dictionary:
	return {
		"title": tr("%s foi levado(a) pelo Sussurrador") % target.display_name,
		"why": tr("O Sussurrador chamou %s até %s e não largou mais.") % [target.display_name, tr(dev.name) if dev else tr("um aparelho")],
		"tip": "Puxe o fio da tomada do aparelho que acendeu. Ele pode pular para outro aparelho: continue de olho. Sons falsos em outros cômodos são isca; as orelhas do gato também podem enganar.",
	}


func on_hiss(p: Vector3, strong: bool) -> bool:
	if hunting_cat:
		if strong and p.distance_to(orb_pos) < 2.0:
			end_hunt()
			return true
		return false
	if dev == null or stage < 1 or not strong:
		return false
	if p.distance_to(dev.pos) > 2.2:
		return false
	stall = d(6)
	Sfx.shriek(dev.pos, 0.2)
	return true


func focus():
	if hunting_cat:
		return orb_pos
	if dev == null or stage == 0:
		return null
	if decoy_until > 0 and decoy_pos != null:
		return decoy_pos
	return dev.pos


func entity():
	if hunting_cat:
		return orb_pos
	return dev.pos if dev != null and stage >= 2 else null
