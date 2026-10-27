class_name Game
extends Node3D
## The whole game: boot, menu, the seven nights (threats, fear, patience, being locked in the
## bathroom, the ritual), the mornings (preparing the house, clues, marks seen with Cat Vision),
## the afternoons (Clara and Davi at home, pets, food, toy, the day scenes, the missions of day 1, the
## end of the day lying down with Clara), the HUD that always says what to do next (tasks, the
## objective marker, the "como vencer" cards, the ghosts under way), endings and saves; plus the world
## API the threats use (pick_target, introduce, hint, fx, hops, is_observed...).
## Port of Game.ts.

const MORNING_LEN := 240.0
const CLUES := ["foto", "coleira", "chave"]
const CLUE_HOMES := {"foto": Vector3(6.75, -2.98, 0.55), "coleira": Vector3(8.5, -3, 0.16), "chave": Vector3(2.0, 6.8, 2.2), "toy": Vector3(3.6, 0, 4.0), "yarn": Vector3(1.6, 0.47, 1.6)}
## day 1: the padlock key on top of the moving box (the box goes down at 4.15, 0.21, 1.15, 0.42 m tall,
## on the free floor past the sofa's arm)
const PORAO_KEY := "porao_key"
const KEY_ON_BOX := Vector3(4.13, 0.425, 1.12)
## day 1: where the cat starts the afternoon (on the round kitchen table, 0.76 m top)
const KITCHEN_TABLE_TOP := Vector3(9.2, 0.77, 6.7)
const BOWL_POS := Vector3(8.6, 0, 3.9)
const EAT_SECS := 4.0
## how long the cat purrs next to Clara before the afternoon gives way to the night
const AFT_PURR_SECS := 2.0

var house: House
var cat: Cat
var clara: Owner
var davi: Owner
var cam: Camera3D
var rig: CameraRig
var director: Director
var inter := Interactions.new()
var marks: InteractMarks   # outlines on what the cat can use, the button over it
var env: GameEnv
var ui: GameUI
var ambient: Ambient

var save: Dictionary = SaveGame.new_save()
var flags: Dictionary = SaveGame.fresh_flags()
var mode := "boot"           # boot | menu | play | paused | over
var phase := "none"          # none | morning | afternoon | night
var day := 1
var night := 1
var hour := 0.0
var phase_t := 0.0
var night_len := 360.0
var controls := false
var threat_speed := 1.0
var aft: Dictionary = {}
var _tilt_next := 0.0        # the cat's head tilt at someone talking: not before this (s, ticks clock)
var _blink_next := 0.0       # the slow blink at Clara while it sits by her

var fx := {"flash": 0.0, "flash_color": Color.WHITE, "distort": 0.0, "ca": 0.0, "fade": 1.0, "fade_target": 1.0, "fade_speed": 1.5, "letterbox": 0.0, "letter_target": 0.0, "fear": 0.0, "vignette": 0.0, "hunt": 0.0}
var lock := {"active": false, "t": 0.0}
var lock_by: Owner = null
var stats := {"repelled": 0, "max_fear": 0.0, "locked": 0, "caught": 0}
var lives := SaveGame.LIVES   # the cat's lives left (the whole week shares seven)
var lost_tonight := 0
var _cat_immune := 0.0
var relics: Array = []        # tonight's mission: [{c: Carryable, text, done, aura}]
var relics_done := 0
var _pushing := -1            # index of the cardboard box the cat is pushing (mornings)
var pulse := 0.0
var _hold_t := 0.0
var _hold_target = null
var _heart_t := 0.0
var _cat_heart_t := 0.0
var _tick_t := 0.0
var _behind_t := 30.0
var _creak_t := 10.0
var _last_hour := 0
var _wind = null
var _fridge = null
var _purr_loop = null
var _introduced := {}
var _hints_shown := {}
var _failing := false
var _winning := false
var _owner_wakes: Array = []
var _info_held := 0.0
var _menu_t := 0.0
var _transitioning := false
var _purr_who: Owner = null
var _hide_spot = null
var _epoch := 0
var _night7_lamp := false     # night 7: the bedroom light Clara left on, until it burns out near 01:00
var _eat_t := 0.0             # the cat eating at the bowl (cat.eating on), moving cancels
var _chew_t := 0.0
var _hud_t := 0.0             # the task list and the ghosts' corner refresh a few times a second


# ====================================================================== boot


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui = GameUI.new()
	add_child(ui)
	ui.sound.connect(func(k): Sfx.ui(k))
	ui.show_loading()
	_boot()


func _step(p: float, msg: String) -> void:
	ui.loading(p, msg)
	await get_tree().process_frame
	await get_tree().process_frame


func _boot() -> void:
	await _step(0.05, "Pintando as paredes")
	cam = Camera3D.new()
	cam.near = 0.03
	cam.far = 260.0
	cam.fov = float(Settings.g("fov"))
	add_child(cam)
	cam.current = true
	rig = CameraRig.new(cam)
	add_child(rig)
	await _step(0.2, "Construindo a casa")
	house = House.new()
	house.name = "House"
	add_child(house)
	house.build()
	await house.measure_beds()
	rig.house = house
	await _step(0.4, "Acordando o gato")
	cat = Cat.new()
	cat.house = house
	add_child(cat)
	rig.exclude = [cat.get_rid()]
	var door_list := house.doors.values()
	clara = Owner.new(Owner.CLARA, house.nav, door_list)
	add_child(clara)
	davi = Owner.new(Owner.DAVI, house.nav, door_list)
	add_child(davi)
	davi.present = false
	davi.hide_model()
	await _step(0.55, "Abrindo as janelas")
	env = GameEnv.new()
	add_child(env)
	env.build(house)
	env.flashed.connect(func(pw):
		if Settings.g("reduce_flashes"):
			return
		fx["flash"] = maxf(fx["flash"], 0.12 * pw)
		fx["flash_color"] = Color("#bcd0ff"))
	ambient = Ambient.new()
	add_child(ambient)
	await _step(0.65, "Chamando as assombrações")
	director = Director.new()
	add_child(director)
	director.setup(self)
	director.thing.wave.connect(_on_thing_wave)
	director.hound.caught.connect(func(h): cat_hit("hound", h.pos))
	# day 1: the key the cat brings Clara in the basement (hidden until she asks for it)
	var key := PropSystem.add_carryable(house.carryables, house, PORAO_KEY, "a chave do cadeado", PropSystem.make_key(), Vector3(0, -50, 0))
	key.enabled = false
	key.node.visible = false
	house.lights.warned.connect(func(l): Sfx.buzz(l.light.global_position, 3.2))
	house.lights.burned_out.connect(func(l):
		Sfx.click(l.light.global_position, 0.6)
		hint_once("burn", "As lâmpadas queimam sozinhas depois de 10–20 s. Pule no interruptor de novo para religar."))
	inter.register(self)
	marks = InteractMarks.new(self)
	_wire_events()
	Sfx.occlusion = _occlusion_hops
	await _step(0.8, "Acendendo a casa")
	apply_env("menu")
	_setup_menu_scene()
	# bounce light: bake once with the static house
	env.bake_gi()
	await _step(0.95, "Apagando as luzes")
	await get_tree().process_frame
	ui.loading(1.0, "Pronto")
	ui.hide_loading()
	to_menu()
	if OS.get_cmdline_user_args().size() > 0:
		var ap: Node = load("res://scripts/dev/autopilot.gd").new()
		ap.set("g", self)
		add_child(ap)


func _wire_events() -> void:
	cat.stepped.connect(func(run, sneak):
		var room := Layout.room_at(cat.global_position)
		var fl: String = Layout.room(room)["floor"] if room != "" else "floor_wood"
		var surface := "tile" if ("tile" in fl or "checker" in fl) else ("concrete" if "concrete" in fl else ("carpet" if "attic" in fl else "wood"))
		Sfx.paw_step(cat.global_position, run, sneak, surface)
		if run and phase == "night":
			emit_noise(cat.global_position, 0.12, "run")
			director.hound.hear_noise(cat.global_position, 0.22, "run"))
	cat.jumped.connect(func(_big): Sfx.paw_step(cat.global_position, true, false))
	cat.landed.connect(func(imp):
		Sfx.thud(cat.global_position, clampf(imp / 14.0, 0.05, 0.25), 120)
		env.dust_puff(cat.global_position, imp, Layout.room_at(cat.global_position + Vector3(0, 0.2, 0)))
		if imp > 7 and phase == "night":
			emit_noise(cat.global_position, 0.2, "thud"))
	cat.meowed.connect(func():
		if cat.mode == "purr":
			Sfx.mrrp(cat.head())
		else:
			Sfx.meow(cat.head(), 1.0)
		if phase == "night":
			director.hear_noise(cat.global_position, 0.7, "meow")
		if phase == "night" or phase == "afternoon":
			for who: Owner in household_present():
				var r := who.hear_meow(cat.global_position, hops(cat.global_position, who.global_position))
				if r == "trance":
					hint_once("trance", tr("Seu miado tirou %s do transe. Mas o problema continua lá.") % who.display_name)
				if r == "coming" or r == "woke":
					hint_once("call", "Miar chama as pessoas até você. Use isso para tirá-las de perigo, mas elas andam pela casa escura."))
	cat.hissed.connect(func(strong):
		Sfx.hiss(cat.head(), strong)
		if not strong:
			hint_once("weakhiss", "Pouco [b]Foco[/b]: o bufo saiu fraco. Espere o Foco recarregar.")
		if director.hiss(cat.global_position, strong):
			fx["ca"] = maxf(fx["ca"], 0.6))
	# an enemy's scream makes the cat jump (nothing else does)
	Sfx.shrieked.connect(_on_shriek)
	# the jump of a scare: a short spit, quieter than a real hiss
	cat.startled.connect(func(_from):
		Sfx.play("cat_hiss_weak", cat.head(), 0.42, randf_range(1.1, 1.2), 1.2))
	for who: Owner in [clara, davi]:
		who.cat_ref = cat
		who.said.connect(func(text, dur, kind, from):
			ui.say(from.display_name, text, dur, "narrator" if kind == "read" else kind)
			if kind != "read":
				Sfx.voice(from.head_pos(), ceili(text.length() / 4.0), kind, from.cfg["voice_pitch"], text)
				_cat_listens(from)
				# whoever else is around turns to the one talking
				for other: Owner in [clara, davi]:
					if other != from and other.present and other.visible and other.global_position.distance_to(from.global_position) < 8.0:
						other.look_for(from, minf(dur, 3.0)))
		who.stepped.connect(func(p): Sfx.human_step(p, randf() < 0.12))
		who.opened_door.connect(func(d): Sfx.creak(d.center() + Vector3(0, 1, 0), 0.3, 0.9))
		who.wants_lamp.connect(func(from: Owner):
			var sh := director.shadow
			if sh.enabled and sh.stage >= 3 and sh.target == from and sh.room == from.cfg["bed_room"]:
				return
			var lamp := house.lights.get_light(from.cfg["lamp"])
			if lamp and not lamp.on and lamp.dead <= 0:
				lamp.set_on(true)
				Sfx.click(lamp.light.global_position, 0.4))
	house.props.noise.connect(func(pos, loud, kind):
		if kind == "break":
			# a teacup is porcelain, the rest is glass
			if house.props.last_broken == "cup":
				Sfx.porcelain(pos)
			else:
				Sfx.glass(pos)
		else:
			Sfx.thud(pos, 0.3 * loud + 0.1, 140)
		emit_noise(pos, loud, kind))
	for d: Door in house.doors.values():
		d.moved.connect(func(door, opening):
			if opening and randf() < 0.6:
				Sfx.creak(door.center() + Vector3(0, 1.2, 0), 0.18, 0.7))


# ====================================================================== world API (threats)


func household_present() -> Array:
	var a := []
	for m: Owner in [clara, davi]:
		if m.present:
			a.append(m)
	return a


## weighted pick: prefers people that are not already under attack
func pick_target(threat: String) -> Owner:
	var lst := household_present()
	if lst.size() <= 1:
		return lst[0] if lst.size() == 1 else clara
	var under := []
	for th: Threat in director.all:
		if th.enabled and th.stage >= 3:
			under.append(th.target)
	var weights := []
	var total := 0.0
	for m: Owner in lst:
		var wv := 1.0
		if m in under:
			wv *= 0.3
		if m.paralysis or m.hypno:
			wv *= 0.2
		if m.purring:
			wv *= 0.6
		if threat == "visitor" and m.cfg["skeptic"]:
			wv *= 1.9
		if (threat == "shadow" or threat == "doll") and m.in_bed:
			wv *= 1.2
		weights.append(wv)
		total += wv
	var r := randf() * total
	for i in lst.size():
		r -= weights[i]
		if r <= 0:
			return lst[i]
	return lst[0]


func any_broken() -> Owner:
	for m: Owner in household_present():
		if m.fear >= 100:
			return m
	return null


func hops(a: Vector3, b: Vector3) -> int:
	var ra := Layout.room_at(a)
	var rb := Layout.room_at(b)
	if ra == "" or rb == "":
		return 3
	return house.nav.hops(ra, rb)


func _occlusion_hops(p: Vector3) -> int:
	var lr := Layout.room_at(cam.global_position)
	if lr == "":
		lr = Layout.room_at(cat.global_position)
	var sr := Layout.room_at(p)
	if lr == "" or sr == "":
		return 0 if lr == sr else 1
	return mini(3, house.nav.hops(lr, sr))


func is_observed(p: Vector3, need_light: bool) -> bool:
	if p.distance_to(cam.global_position) > 11.0:
		return false
	if cam.is_position_behind(p):
		return false
	var sp := cam.unproject_position(p)
	var vs := get_viewport().get_visible_rect().size
	var nx := sp.x / vs.x * 2.0 - 1.0
	var ny := sp.y / vs.y * 2.0 - 1.0
	if absf(nx) > 0.95 or absf(ny) > 0.95:
		return false
	if house.blocked(cam.global_position, p):
		return false
	if need_light:
		var room := Layout.room_at(p)
		var lit := house.lights.is_room_lit(room) if room != "" else false
		if not lit and cam.global_position.distance_to(p) > 3.0:
			return false
	return true


func introduce(id: String) -> void:
	# the night it is new, how to beat it shows up the moment it spawns (every time it does, even on a
	# restart of the night or when it was taught in an earlier session) and stays until dawn
	if phase == "night" and Config.is_new_on(id, night):
		_show_howto(id)
	if _introduced.has(id):
		return
	_introduced[id] = true
	var info: Dictionary = Story.THREAT_INFO[id]
	ui.threat(info["name"], info["hint"])
	if id == "shadow" and day == 1:
		_later(2.5, func(): hint_once("ears", tr("Ouça. As [b]orelhas[/b] do %s apontam para o perigo.") % Settings.cat_name))
		_later(17.0, func(): hint_once("switch", tr("Pule nos interruptores com %s. Acenda a luz do cômodo onde a Sombra está.") % ui.kbd("interact")))


## the "como vencer" card of a ghost, under the tasks, until the night ends
func _show_howto(id: String) -> void:
	var info: Dictionary = Story.THREAT_INFO.get(id, {})
	if info.has("howto"):
		ui.howto(id, info["name"], info["howto"])


## a night starts without cards: the one of the ghost that is new tonight comes with its spawn
func _night_howtos(_d: int) -> void:
	ui.howto_clear()


func hint(text: String, dur := 4.0) -> void:
	ui.say("", text, dur, "ghost")


func repelled(id: String) -> void:
	stats["repelled"] += 1
	save["stats"]["threats_repelled"] += 1
	if not _hints_shown.has("rep_" + id) and day == 1:
		_hints_shown["rep_" + id] = true
		_later(1.5, func(): hint_once("after_rep", "Ela vai voltar. Leve os objetos de Ivone ao porão para a noite acabar."))


func shake(a: float) -> void:
	rig.shake(a * 0.5 if Settings.g("reduce_flashes") else a)


func sting(a := 0.6) -> void:
	Sfx.sting(a)


func flash(a: float, color := Color.WHITE) -> void:
	if Settings.g("reduce_flashes"):
		a *= 0.2
	fx["flash"] = maxf(fx["flash"], a)
	fx["flash_color"] = color


func distort(a: float) -> void:
	fx["distort"] = maxf(fx["distort"], a * 0.3 if Settings.g("reduce_flashes") else a)


func ca(a: float) -> void:
	fx["ca"] = maxf(fx["ca"], a * 0.3 if Settings.g("reduce_flashes") else a)


func burst_smoke(p: Vector3, color := Color(0.02, 0.02, 0.03, 0.7)) -> void:
	var s := FX.wisps(color, 0.8, 0.35, 40, false, 0.6)
	s.one_shot = true
	s.explosiveness = 0.8
	s.preprocess = 0.0
	s.lifetime = 1.8
	add_child(s)
	s.global_position = p
	s.emitting = true
	_later(2.5, s.queue_free)


func sparks_at(p: Vector3) -> void:
	var s := FX.sparks()
	add_child(s)
	s.global_position = p
	s.emitting = true
	_later(1.5, s.queue_free)


func shockwave(center: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 64
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.25, 0.15, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = center + Vector3(0, 0.1, 0)
	ring.scale = Vector3(0.5, 0.2, 0.5)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(5.2, 0.4, 5.2), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(ring.queue_free)
	distort(0.5)


## automated test runs (command-line args) never touch the player's save
func _write_save() -> void:
	_store_tips()
	if OS.get_cmdline_user_args().is_empty():
		SaveGame.write_save(save)


## what was already taught goes into the save (introduced ghosts, one-time hints)...
func _store_tips() -> void:
	var tips := SaveGame.tips_of(save)
	tips["introduced"] = _introduced.keys()
	tips["hints"] = _hints_shown.keys()


## ...and comes back from it (added to what this session already showed)
func _load_tips(sv: Dictionary) -> void:
	var tips := SaveGame.tips_of(sv)
	for id in tips["introduced"]:
		_introduced[str(id)] = true
	for id in tips["hints"]:
		_hints_shown[str(id)] = true


func _later(sec: float, fn: Callable) -> void:
	var ep := _epoch
	get_tree().create_timer(sec).timeout.connect(func():
		if ep == _epoch:
			fn.call())


# ====================================================================== environment


func apply_env(kind: String) -> void:
	env.apply(kind, night)
	var h := house
	var nightish := kind == "night" or kind == "menu"
	h.lights.get_light(13).set_on(kind != "morning" and kind != "dawn")
	h.lights.get_light(16).set_on(kind == "night")
	h.clock_hour = 9.0 if kind == "morning" else (18.0 if kind == "afternoon" else (6.0 if kind == "dawn" else 0.0))
	if nightish:
		h.clock_hour = 0.0


# ====================================================================== menu


func _setup_menu_scene() -> void:
	director.stop_all()
	house.lights.set_all(false)
	var l8 := house.lights.get_light(8)
	l8.set_on(true)
	l8.level = 1.0
	# a warm glow upstairs: Clara reads before sleeping
	var l7 := house.lights.get_light(7)
	l7.set_on(true)
	l7.scale = 0.55
	house.lights.get_light(13).set_on(true)
	clara.set_night(true)
	clara.put_in_bed(true)
	clara.show_model()
	davi.hide_model()
	cat.teleport(Vector3(11.55, 4.02, 0.0), PI * 0.9)
	cat.mode = "frozen"


func to_menu() -> void:
	_epoch += 1
	for l: LightSystem.RoomLight in house.lights.lights:
		l.scale = 1.0
	mode = "menu"
	phase = "none"
	controls = false
	Controls.capture(false)
	Sfx.set_muffle(0.0)
	apply_env("menu")
	_setup_menu_scene()
	Music.set_mode("menu")
	_ensure_ambience()
	ui.hud_visible(false)
	ui.clear_hints()
	ui.howto_clear()
	ui.lives(-1)
	fx["fade_target"] = 0.0
	fx["letter_target"] = 0.0
	var sv = SaveGame.load_save()
	if sv:
		_load_tips(sv)
	var unlocked: int = int(sv["unlocked_night"]) if sv else 1
	var label := ""
	if sv:
		label = tr("Noite %d") % int(sv["current"]["day"]) if sv["current"]["phase"] == "night" else tr("Dia %d · manhã") % int(sv["current"]["day"])
	var rows := []
	for n in range(1, Config.LAST_NIGHT + 1):
		rows.append({"start": SaveGame.lives_at(sv, n) if sv else SaveGame.LIVES, "lost": SaveGame.lost_on(sv, n) if sv else 0})
	ui.show_menu({
		"can_continue": sv != null, "continue_label": label, "unlocked": unlocked, "nights": rows,
		"on_new": new_game, "on_continue": continue_game, "on_night": start_at_night,
		"on_settings": func(): ui.show_settings(to_menu),
		"on_credits": func(): ui.show_credits(to_menu),
	})


func _ensure_ambience() -> void:
	if _wind == null:
		_wind = Sfx.loop("wind", null, 1.0, "Amb")
	if _fridge == null:
		_fridge = Sfx.loop("fridge", Vector3(7.9, 1.0, 3.9), 0.8, "Sfx")
	_wind.set_level(0.12 if phase == "morning" else 0.3)
	_fridge.set_level(0.25)


func new_game() -> void:
	ui.close_overlay()
	var prev = SaveGame.load_save()
	save = SaveGame.new_save()
	if prev:
		save["unlocked_night"] = prev["unlocked_night"]
		save["endings_seen"] = prev["endings_seen"]
		# a new game starts the week with all seven lives: old runs stay out of it
		save["tips"] = SaveGame.tips_of(prev).duplicate(true)
		_load_tips(save)
	_write_save()
	fx["fade"] = 1.0
	fx["fade_target"] = 1.0
	Music.set_mode("none")
	ui.show_cards(Story.INTRO_CARDS, func(): _begin_snapshot(save["current"]))


func continue_game() -> void:
	var s = SaveGame.load_save()
	if s == null:
		new_game()
		return
	save = s
	_load_tips(s)
	ui.close_overlay()
	if s["current"]["phase"] == "morning":
		_begin_snapshot(s["morning"] if s["morning"] else s["current"])
	elif s["current"]["phase"] == "afternoon":
		_begin_snapshot(s["current"])
	else:
		_begin_snapshot(s["night"] if s["night"] else s["current"])


func start_at_night(n: int) -> void:
	var s = SaveGame.load_save()
	save = s if s else SaveGame.new_save()
	_load_tips(save)
	var f := SaveGame.fresh_flags()
	if n >= 2:
		f["duct_open"] = true
	if n >= 3:
		f["boxes"][0] = _box_flag(0)
	if n >= 4:
		f["basculante_open"] = true
	if n >= 5:
		f["flap_open"] = true
	if n >= 6:
		f["boxes"][1] = _box_flag(1)
		var nh: Vector3 = House.NIGHTLIGHT_HOME
		f["nightlight"] = {"x": nh.x, "y": nh.y, "z": nh.z}
	if n >= 7:
		f["hatch_open"] = true
		f["porao_win_open"] = true
	var snap := {"day": n, "phase": "night", "flags": f, "patience": 65.0, "start_fear": 0.0}
	save["current"] = snap.duplicate(true)
	save["night"] = snap.duplicate(true)
	save["morning"] = null
	ui.close_overlay()
	_begin_snapshot(snap)


func _begin_snapshot(s: Dictionary) -> void:
	flags = (s["flags"] as Dictionary).duplicate(true)
	day = int(s["day"])
	if s["phase"] == "morning":
		start_morning(day)
	elif s["phase"] == "afternoon":
		_reset_world()
		start_afternoon()
	else:
		start_night(day, s)


# ====================================================================== world reset


func _reset_world() -> void:
	for k in SaveGame.fresh_flags():
		if not flags.has(k):
			flags[k] = SaveGame.fresh_flags()[k]
	var h := house
	h.props.reset_all()
	for d: Door in h.doors.values():
		d.locked = false
		d.set_state(d.def.get("state", "closed"), true)
	h.lights.set_all(false)
	for l: LightSystem.RoomLight in h.lights.lights:
		l.flicker = 0.0
		l.dead = 0.0
		l.scale = 1.0
	h.set_hatch(flags["hatch_open"], true)
	h.set_duct(flags["duct_open"], true)
	h.set_basculante(flags["basculante_open"], true)
	h.set_chest(false)
	h.ritual_glow = 1.0 if day == Config.LAST_NIGHT else 0.0
	davi.present = phase == "night" and day >= Config.DAVI_DAY
	h.set_guest_move_in(day >= Config.DAVI_DAY and (phase == "night" or day > Config.DAVI_DAY))
	for o: Owner in [clara, davi]:
		o.purring = false
		o.paralysis = false
		o.scripted = false
		o.paused = false
		o.following = false
		o.abort()
	h.set_food(0.0)
	for f: House.Faucet in h.faucets:
		f.running = 0.0
		f.level = 0.0
		f.puddle = 0.0
	for id: String in h.carryables.keys():
		if id == "doll" or id.begins_with("relic_"):
			continue
		if id == PORAO_KEY:
			_show_porao_key(false)
			continue
		if id == "nightlight":
			var nlf = flags.get("nightlight")
			var c2: PropSystem.Carryable = h.carryables[id]
			c2.carried = false
			c2.enabled = nlf != null
			c2.node.visible = nlf != null
			c2.place(Vector3(nlf["x"], nlf["y"], nlf["z"]) if nlf != null else Vector3(0, -50, 0))
			continue
		var c: PropSystem.Carryable = h.carryables[id]
		c.carried = false
		c.enabled = true
		c.node.visible = true
		var saved = flags["clues"].get(id) if id in CLUES else null
		if saved:
			c.place(Vector3(saved["x"], saved["y"], saved["z"]))
		else:
			c.place(CLUE_HOMES[id])
	cat.carrying = null
	_pushing = -1
	_purr_who = null
	_stop_eating()
	_sync_boxes()
	_sync_nightlight()
	cat.mode = "free"
	cat.locked_movement = false
	cat.focus = 100.0
	lock["active"] = false
	Sfx.set_muffle(0.0)
	if _purr_loop:
		_purr_loop.stop(0.3)
		_purr_loop = null
	_failing = false
	_winning = false
	ui.clear_hints()
	ui.tasks(null, [])
	ui.howto_clear()
	_hold_t = 0.0
	_hold_target = null
	_transitioning = false
	_hud_t = 0.0


# ====================================================================== NIGHT


func start_night(d: int, snap = null) -> void:
	_epoch += 1
	ui.close_overlay()
	ui.clear_talk_log()
	day = d
	night = d
	phase = "night"
	mode = "play"
	phase_t = 0.0
	hour = 0.0
	_last_hour = 0
	night_len = float(Config.NIGHT_LENGTH_MIN[d]) * 60.0
	stats = {"repelled": 0, "max_fear": 0.0, "locked": 0, "caught": 0}
	lives = maxi(1, SaveGame.lives_at(save, d))
	lost_tonight = 0
	_cat_immune = 0.0
	ui.lives(lives, 0)
	if snap:
		flags = (snap["flags"] as Dictionary).duplicate(true)
	if aft.has("props"):
		_clear_props()
	_reset_world()
	_night_howtos(d)
	_setup_relics(d)
	_night7_lamp = d == Config.LAST_NIGHT
	if _night7_lamp:
		var ql := house.lights.get_light(7)
		ql.set_on(true)
		ql.life = 99999.0
	apply_env("night")
	_ensure_ambience()
	clara.set_night(true)
	clara.show_model()
	clara.put_in_bed(true)
	clara.fear = float(snap["start_fear"]) if snap else 0.0
	clara.patience = float(snap["patience"]) if snap else 65.0
	_setup_davi()
	cat.teleport(Layout.v3(Layout.data()["CAT_START"]), -PI / 2)
	cat.sleep = 100.0
	rig.snap(cat.global_position + Vector3(0, 0.32, 0), -PI / 2)
	rig.pitch = -0.25
	director.start_night(d, float(Settings.g("night_speed")))
	ambient.reset()
	Music.set_mode("night")
	ui.hud_visible(true)
	controls = true
	Controls.capture(true)
	fx["fade"] = 1.0
	fx["fade_target"] = 0.0
	fx["fade_speed"] = 0.6
	fx["letter_target"] = 0.0
	_owner_wakes = []
	if d >= 2:
		_owner_wakes.append({"who": clara, "at": randf_range(1.2, 2.4), "kind": "water", "done": false})
	if d >= 4:
		_owner_wakes.append({"who": clara, "at": randf_range(3.4, 4.6), "kind": "toilet", "done": false})
	if d >= Config.DAVI_DAY:
		_owner_wakes.append({"who": davi, "at": randf_range(2.8, 3.8), "kind": "water", "done": false})
	var s := {"day": d, "phase": "night", "flags": flags.duplicate(true), "patience": clara.patience, "start_fear": clara.fear}
	save["current"] = s.duplicate(true)
	save["night"] = s.duplicate(true)
	save["unlocked_night"] = maxi(int(save["unlocked_night"]), d)
	_write_save()
	_later(0.6, func(): ui.title(tr("Noite %d") % d, "00:00", 4))
	# what the night is about, before anything else: she sleeps, the cat keeps watch
	_later(4.8, func():
		if phase == "night":
			hint("Proteja a Clara. Enquanto ela dorme, os fantasmas vêm atrás dela. Só você consegue vê-los." if d == 1 else "Proteja a Clara dos fantasmas esta noite.", 6.0 if d == 1 else 3.5))
	if d < Config.LAST_NIGHT:
		_schedule_hint(8 if d == 1 else 3, "relics", tr("Esta noite só termina quando você levar [b]%d objetos de Dona Ivone[/b] ao círculo do porão. Chegue perto e eles se destacam no escuro. A lista no canto mostra quantos faltam.") % relics.size())
	if d == 1:
		_later(2.2, func(): clara.say("Primeira noite na casa nova, {cat}. Boa noite...", 3.5, "whisper"))
		_schedule_hint(5, "move", tr("Mova-se com %s e olhe com o mouse. %s corre.") % [ui.kbd("W A S D"), ui.kbd("run")])
		_schedule_hint(13, "jump", tr("Quando aparecer um [b]círculo[/b] no chão ou num móvel, %s pula até ele.") % ui.kbd("jump"))
	elif d == 2:
		_schedule_hint(4, "meow", tr("%s mia e [b]chama[/b] as pessoas até você. Também tira alguém de um transe, mas irrita quem dorme.") % ui.kbd("meow"))
		_schedule_hint(14, "noise", "Derrubar coisas faz barulho: quem caça pelo som vai até lá. Use isso como isca.")
	elif d == 3:
		_schedule_hint(4, "hiss", tr("%s bufa: espanta ou enfraquece o que estiver por perto. O botão aparece na tela quando adianta. Gasta Foco.") % ui.kbd("hiss"))
	elif d == 4:
		_schedule_hint(4, "tab", tr("Segure %s para ver a hora. Mas a hora não salva ninguém: a noite só acaba com os objetos de Ivone no círculo.") % ui.kbd("info"))
		_schedule_hint(11, "two", "Agora são [b]dois[/b] para proteger. Cada ameaça escolhe um alvo.")


func _schedule_hint(at: float, id: String, bb: String) -> void:
	_later(at, func():
		if phase == "night" and mode != "menu":
			hint_once(id, bb, 7))


func hint_once(id: String, bb: String, dur := 7.0) -> void:
	if _hints_shown.has(id):
		return
	_hints_shown[id] = true
	ui.hint(bb, dur)


## Davi stays up late working in the study, then goes to bed
func _setup_davi() -> void:
	var dv := davi
	if not dv.present:
		dv.hide_model()
		return
	dv.set_night(true)
	dv.show_model()
	dv.fear = 0.0
	dv.patience = 70.0
	dv.in_bed = false
	dv.asleep = false
	# on the desk chair: the hips over the seat's centre, the seat top 0.47 (0.01 over the sofa's)
	dv.place(Layout.spot("desk"))
	dv.model.seat_lift = 0.21
	dv.model.snap_pose("sit")
	var bedtime := randf_range(0.9, 1.3)
	dv.run("work", [
		{"t": "until", "cond": func(): return hour >= bedtime, "pose": "read"},
		{"t": "say", "text": "Chega por hoje. Boa noite, casa velha.", "dur": 3.0, "kind": "whisper"},
		{"t": "pose", "pose": "stand", "dur": 0.4},
		{"t": "spot", "spot": Layout.spot("davBedside")},
		{"t": "bed"},
	], 1)


func _night_update(dt: float) -> void:
	var people := household_present()
	phase_t += dt
	# dawn only comes with the mission done: the clock stops just short of six and the house worsens
	hour = minf(phase_t / night_len * 6.0, 5.98)
	if _night7_lamp and hour >= 1.0:
		_night7_lamp = false
		var ql := house.lights.get_light(7)
		if ql.on:
			ql.life = 3.0
			_later(3.0, func(): Sfx.bulb_pop(ql.light.global_position))
	director.overtime = maxf(0.0, phase_t - night_len * 0.8)
	house.clock_hour = hour
	_tick_relics()
	_sync_nightlight()
	for m: Owner in people:
		stats["max_fear"] = maxf(stats["max_fear"], m.fear)
	var h_int := floori(hour)
	if h_int > _last_hour and h_int < 6:
		_last_hour = h_int
		Sfx.bell(house.clock_pos, h_int, 0.35)
	for wk in _owner_wakes:
		var who: Owner = wk["who"]
		if wk["done"] or hour < wk["at"] or not who.present:
			continue
		# the upstairs bathroom is locked while the cat is shut in it: no trip there until it opens
		if not who.in_bed or who.busy or who.fear > 45 or director.tension() > 0.55 or (wk["kind"] == "toilet" and lock["active"]):
			wk["at"] += 0.15
			continue
		wk["done"] = true
		_owner_trip(who, wk["kind"])
	_cat_immune = maxf(0.0, _cat_immune - dt)
	var broken := any_broken()
	if broken and not _failing:
		_fail(broken)
	if not lock["active"] and not _failing:
		for m: Owner in people:
			if m.patience <= 0:
				_lock_cat(m)
				break
	if lock["active"]:
		lock["t"] -= dt
		if lock["t"] <= 0:
			_release_lock()
	if people.is_empty():
		return
	var scared: Owner = people[0]
	var annoyed: Owner = people[0]
	for p: Owner in people:
		if p.fear > scared.fear:
			scared = p
		if p.patience < annoyed.patience:
			annoyed = p
	if scared.fear > 26:
		hint_once("fear", "Quando alguém tem medo, a casa perde a cor. Ouça o coração.")
	if scared.fear > 45:
		hint_once("purr", tr("Deite com %s na cama (%s) e ronrone para acalmar.") % [scared.display_name, ui.kbd("interact")])
	if annoyed.patience < 30:
		hint_once("patience", tr("%s está perdendo a paciência. Se ficar irritado(a), vai te trancar no banheiro.") % annoyed.display_name)


func _owner_trip(o: Owner, kind: String) -> void:
	var bedside := Layout.spot(o.cfg["bedside_spot"])
	var steps: Array
	if kind == "water":
		steps = [
			{"t": "say", "text": "Que sede...", "dur": 2.0, "kind": "whisper"},
			{"t": "spot", "spot": Layout.spot("kitchenSink")},
			{"t": "pose", "pose": "drink", "dur": 3.0},
			{"t": "pose", "pose": "stand", "dur": 0.4},
			{"t": "spot", "spot": bedside},
			{"t": "bed"},
		]
	else:
		steps = [
			{"t": "say", "text": "Hmm... banheiro...", "dur": 2.0, "kind": "whisper"},
			{"t": "spot", "spot": Layout.spot("bathroomUp")},
			{"t": "wait", "dur": 6.0},
			{"t": "spot", "spot": bedside},
			{"t": "bed"},
		]
	o.run(kind, steps, 1)


func _night_won() -> void:
	_winning = true
	controls = false
	director.stop_all()
	SaveGame.record_night(save, day, lost_tonight)
	_write_save()
	Sfx.bell(house.clock_pos, 6, 0.45)
	fx["letter_target"] = 1.0
	if cat.mode == "purr":
		toggle_purr()
	if day == Config.LAST_NIGHT:
		_later(4.0, func(): _ending("bad"))
		return
	apply_env("dawn")
	clara.say(Story.MORNING_LINES.get(day, "Bom dia, {cat}... que noite estranha."), 4.0, "whisper")
	ui.title("06:00", "Amanhecer", 4)
	_later(4.5, func():
		fx["fade_target"] = 1.0
		fx["fade_speed"] = 0.8)
	_later(6.2, func():
		Controls.capture(false)
		mode = "over"
		ui.clear_hints()
		ui.show_summary({
			"title": tr("Noite %d sobrevivida") % day,
			"sub": "Clara e Davi sobreviveram" if davi.present else "Clara sobreviveu",
			"lines": [["Assombrações afastadas", str(stats["repelled"])], ["Medo máximo", "%d%%" % roundi(stats["max_fear"])], ["Vezes trancado no banheiro", str(stats["locked"])], ["Vezes pego pelo cão", str(stats["caught"])], ["Vidas perdidas", tr("%d (restam %d)") % [lost_tonight, lives]]],
			"on_continue": func():
				fx["letter_target"] = 0.0
				start_morning(day + 1),
		}))


func _fail(who: Owner) -> void:
	_failing = true
	controls = false
	var attackers := []
	for th: Threat in director.all:
		if th.enabled and th.stage >= 3:
			attackers.append(th)
	attackers.sort_custom(func(a, b): return a.stage > b.stage)
	var killer: Threat = null
	for th: Threat in attackers:
		if th.target == who:
			killer = th
			break
	if killer == null and attackers.size() > 0:
		killer = attackers[0]
	var info: Dictionary
	if killer:
		info = killer.describe_death()
	else:
		info = {"title": tr("%s não aguentou o medo") % who.display_name, "why": "O medo foi se acumulando sem parar, até não restar coragem.", "tip": "Ronronar na cama acalma. Resolva as ameaças cedo, antes de o medo disparar."}
	if killer and killer.target != who:
		info["title"] = tr("%s foi levado(a) pelo medo") % who.display_name
	var others := []
	for th: Threat in director.all:
		if th.enabled and th.stage >= 2 and th != killer:
			others.append(th.display_name)
	var cat_room := Layout.room_at(cat.global_position)
	var facts := [tr("Medo de %s: %d%%") % [who.display_name, roundi(who.fear)], tr("Você estava: %s") % Layout.room_name(cat_room) if cat_room != "" else "Você estava fora de casa"]
	if others.size() > 0:
		facts.append(tr("Também estavam ativas: %s") % ", ".join(others))
	var dead := 0
	for l: LightSystem.RoomLight in house.lights.lights:
		if l.ticks() and l.dead > 0:
			dead += 1
	if dead > 1:
		facts.append(tr("Lâmpadas queimadas no momento: %d") % dead)
	Sfx.shriek(who.head_pos(), 1.0, false)
	Sfx.sting(0.9)
	flash(0.6, Color("#5a0000"))
	distort(1.0)
	rig.shake(1.4)
	director.stop_all()
	if cat.mode == "purr":
		toggle_purr()
	fx["fade_target"] = 1.0
	fx["fade_speed"] = 0.5
	_later(1.5, func(): who.hide_model())
	_later(3.6, func():
		Controls.capture(false)
		mode = "over"
		ui.clear_hints()
		Music.set_mode("none")
		var has_day: bool = day > 1 and save["morning"] != null
		ui.show_fail({
			"title": info["title"], "sub": tr("Noite %d · %s") % [day, _fmt_clock(hour)], "why": info["why"], "tip": info["tip"], "facts": facts,
			"on_night": func(): start_night(day, save["night"]),
			"on_day": (func(): _begin_snapshot(save["morning"])) if has_day else null,
			"on_menu": to_menu,
		}))


static func _fmt_clock(hours: float) -> String:
	var hh := floori(hours)
	var mm := floori((hours - hh) * 60.0)
	return "%02d:%02d" % [hh, mm]


# ---------------------------------------------------------------------- lock


func _lock_cat(who: Owner) -> void:
	if phase != "night":
		who.patience = 5.0
		return
	lock_by = who
	lock["active"] = true
	lock["t"] = night_len / 6.0 + 1.7
	stats["locked"] += 1
	save["stats"]["times_locked"] += 1
	save["ever_locked"] = true
	controls = false
	if cat.mode == "purr":
		toggle_purr()
	who.say("{cat}! Fora do meu quarto. Banheiro, já." if who.cfg["skeptic"] else "{cat}! CHEGA! Banheiro, agora.", 3.0, "annoyed")
	fx["fade_target"] = 1.0
	fx["fade_speed"] = 1.2
	_later(1.7, func():
		if cat.carrying:
			drop_carried()
		cat.teleport(Vector3(9.4, 3, 7.6), -PI / 2)
		rig.snap(cat.global_position + Vector3(0, 0.32, 0), -PI / 2)
		var d: Door = house.doors["d_banc"]
		d.set_state("closed", true)
		d.locked = true
		Sfx.thud(d.center() + Vector3(0, 1, 0), 0.8, 90)
		Sfx.click(d.center() + Vector3(0, 1, 0), 0.8)
		who.put_in_bed(false)
		who.patience = 45.0
		fx["fade_target"] = 0.0
		controls = true
		Sfx.set_muffle(0.15)
		ui.hint(tr("Você foi trancado no banheiro por uma hora. Arranhe a porta (segure %s)%s") % [ui.kbd("interact"), " ou fuja pela janela basculante." if flags["basculante_open"] else ". Da próxima vez, abra a basculante de manhã."], 8))


func _release_lock() -> void:
	lock["active"] = false
	Sfx.set_muffle(0.0)
	var d: Door = house.doors["d_banc"]
	if d.locked:
		d.locked = false
		d.set_state("ajar")
		(lock_by if lock_by else clara).say("Tá... pode sair. Mas fica quieto, {cat}.", 3.0, "annoyed")


func on_escaped_lock() -> void:
	if lock["active"]:
		lock["active"] = false
		Sfx.set_muffle(0.0)
		(lock_by if lock_by else clara).say("{cat}!! Para de arranhar essa porta!", 2.6, "annoyed")


# ---------------------------------------------------------------------- ritual & thing


func ritual_placed(id: String) -> bool:
	return id in CLUES and flags["clues"][id] != null and flags["clues"][id]["on_circle"]


func all_clues_on_circle() -> bool:
	for k in CLUES:
		if not ritual_placed(k):
			return false
	return true


## the photo, the collar and the key on the circle and every thing of Ivone's delivered
func ritual_ready() -> bool:
	return all_clues_on_circle() and relics_done >= relics.size()


func on_ritual_item() -> void:
	var n := 0
	for k in CLUES:
		if ritual_placed(k):
			n += 1
	house.ritual_glow = 1.0 + n * 0.15
	director.thing.ritual_items = n
	if phase == "morning":
		on_task("ritual")
	if phase == "night":
		refresh_night_tasks()
	if n == 3 and ritual_ready():
		ui.say("", "O círculo está completo. Segure sobre ele para terminar o ritual.", 5, "narrator")
	elif n == 3:
		ui.say("", "Faltam as coisas de Dona Ivone. Leve-as ao círculo para terminar o ritual.", 5, "narrator")


func _on_thing_wave(hit: bool) -> void:
	if not hit:
		return
	var c := house.ritual_center
	var dir := cat.global_position - c
	dir.y = 0
	if dir.length_squared() < 0.01:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	var to := c + dir * 4.2
	to.x = clampf(to.x, 0.6, 7.4)
	to.z = clampf(to.z, 0.6, 9.4)
	to.y = house.ground_height(to.x, to.z, -2.5)
	if cat.mode != "free":
		cat.mode = "free"
	cat.arc = {"from": cat.global_position, "to": to, "t": 0.0, "dur": 0.5, "h": 0.6}
	_hold_t = 0.0
	_hold_target = null
	Sfx.hiss(cat.head(), false)
	cat_hit("thing", c, false)
	hint_once("wave", tr("Quando os tentáculos se erguerem, [b]bufe[/b] (%s) para cancelar a onda.") % ui.kbd("hiss"))


func complete_ritual() -> void:
	director.thing.kill()
	director.stop_all()
	controls = false
	_winning = true
	for id in CLUES:
		(house.carryables[id] as PropSystem.Carryable).node.visible = false
	_later(1.2, func():
		apply_env("dawn")
		for m: Owner in household_present():
			m.fear = 0.0)
	_later(3.5, func(): _ending("good" if save["ever_locked"] else "secret"))


## the good endings first show what really happened those nights: the same house, no ghosts, a cat
## looking after her (five short shots, each a slow push of a fixed camera)
const MEMORY_SECS := 4.8
const MEMORY_SHOTS := [
	{"text": "No corredor, de madrugada, não tinha nada.", "cam": [Vector3(6.6, 3.45, 3.3), Vector3(6.7, 3.38, 3.9)], "look": Vector3(6.8, 3.25, 7.5)},
	{"text": "Ela, sentada no escuro da sala, às três da manhã.", "cam": [Vector3(1.9, 1.45, 4.7), Vector3(2.1, 1.35, 4.2)], "look": Vector3(3.4, 0.6, 1.8)},
	{"text": "A TV ligada, falando sozinha a noite inteira.", "cam": [Vector3(2.6, 0.9, 2.3), Vector3(2.55, 0.85, 2.9)], "look": Vector3(2.5, 0.75, 5.2)},
	{"text": "A torneira que ela esqueceu aberta.", "cam": [Vector3(8.0, 1.5, 7.4), Vector3(8.2, 1.4, 7.9)], "look": Vector3(8.8, 0.85, 9.3)},
	{"text": "E a porta do banheiro, trancada por dentro, por tempo demais.", "cam": [Vector3(6.75, 4.05, 8.0), Vector3(6.85, 3.95, 8.35)], "look": Vector3(7.45, 3.3, 9.1)},
]


func _memory_montage(done: Callable) -> void:
	_epoch += 1
	director.stop_all()
	phase = "memory"
	mode = "play"
	controls = false
	Controls.capture(false)
	ui.hud_visible(false)
	ui.tasks(null, [])
	ui.clear_hints()
	ui.howto_clear()
	apply_env("night")
	Music.set_mode("none")
	house.lights.set_all(false)
	davi.hide_model()
	clara.abort()
	clara.set_night(true)
	clara.in_bed = false
	clara.scripted = true
	fx["fade_speed"] = 2.2
	for i in MEMORY_SHOTS.size():
		_later(i * MEMORY_SECS, func(): _memory_shot(i))
	_later(MEMORY_SHOTS.size() * MEMORY_SECS - 0.6, func(): fx["fade_target"] = 1.0)
	_later(MEMORY_SHOTS.size() * MEMORY_SECS + 0.6, func():
		rig.override_pose = {}
		clara.scripted = false
		done.call())


func _memory_shot(i: int) -> void:
	var sh: Dictionary = MEMORY_SHOTS[i]
	fx["fade"] = 1.0
	fx["fade_target"] = 0.0
	cat.mode = "free"
	clara.hide_model()
	match i:
		0:
			cat.teleport(Vector3(6.8, 3, 5.4), 0.0)
			_cat_stay("busy")
			_later(1.4, func(): Sfx.hiss(cat.head(), false))
		1:
			clara.show_model()
			clara.place(Layout.spot("sofa"))
			clara.model.snap_pose("sit")
			var l: LightSystem.RoomLight = house.lights.get_light(2)
			var sw: Vector3 = l.switch_pos if l and l.switch_pos != null else Vector3(4.6, 1.2, 2.0)
			cat.teleport(Vector3(sw.x, 0.0, sw.z) + Vector3(-0.25, 0, 0.0), PI / 2)
			_cat_stay("busy")
			_later(1.8, func():
				if l:
					house.lights.toggle(l)
				Sfx.click(sw, 0.6))
		2:
			var tvd := _device("tv")
			if tvd:
				house.set_plugged(tvd, true)
			_tv_show(true)
			cat.teleport(Vector3(3.3, 0, 4.85), 0.6)
			_cat_stay("busy")
			_later(2.0, func():
				if tvd:
					house.set_plugged(tvd, false)
				_tv_show(false)
				Sfx.click(Vector3(3.55, 0.3, 5.4), 0.6))
		3:
			var fc: House.Faucet = null
			for f: House.Faucet in house.faucets:
				if f.id == "coz":
					fc = f
			if fc:
				fc.running = 1.0
				# up on the counter next to the sink, a paw on the tap
				cat.teleport(Vector3(fc.handle.x - 0.32, fc.top_y + 0.02, fc.handle.z), PI / 2)
				_cat_stay("busy")
				_later(2.2, func():
					fc.running = 0.0
					Sfx.click(fc.handle, 0.4))
		4:
			var bd: Door = house.doors["d_banc"]
			bd.set_state("closed", true)
			cat.teleport(Vector3(7.15, 3, 9.1), PI / 2)
			_cat_stay("scratch")
	var cams: Array = sh["cam"]
	var look: Vector3 = sh["look"]
	var tw := create_tween()
	tw.tween_method(func(k: float): rig.override_pose = {"pos": (cams[0] as Vector3).lerp(cams[1], k), "look": look, "blend": 1.0}, 0.0, 1.0, MEMORY_SECS)
	ui.say("", sh["text"], MEMORY_SECS - 0.6, "narrator")


func _ending(kind: String, remembered := false) -> void:
	if not remembered and kind in ["good", "secret"]:
		_memory_montage(func(): _ending(kind, true))
		return
	Controls.capture(false)
	mode = "over"
	controls = false
	director.stop_all()
	Music.set_mode("ending")
	ui.clear_hints()
	if not kind in save["endings_seen"]:
		save["endings_seen"].append(kind)
	save["unlocked_night"] = Config.LAST_NIGHT
	_write_save()
	var e: Dictionary = Story.ENDINGS[kind]
	var lines := []
	for l: String in e["lines"]:
		lines.append(tr(l).replace("{cat}", Settings.cat_name))
	ui.show_ending(e["title"], lines, func(): ui.show_credits(to_menu))


# ====================================================================== MORNING


func start_morning(d: int) -> void:
	_epoch += 1
	ui.close_overlay()
	ui.clear_talk_log()
	day = d
	ui.lives(SaveGame.lives_at(save, d))
	_setup_relics(0)
	phase = "morning"
	mode = "play"
	phase_t = 0.0
	_reset_world()
	_unlock_morning(d)
	# morning 4 sends the cat up to the attic chest: the hatch is found open
	if d == 4 and not flags["hatch_open"]:
		house.set_hatch(true, true)
	director.stop_all()
	apply_env("morning")
	_ensure_ambience()
	clara.hide_model()
	clara.abort()
	clara.in_bed = false
	davi.hide_model()
	cat.teleport(house.cat_bed + Vector3(0.2, 0, -0.5), PI)
	rig.snap(cat.global_position + Vector3(0, 0.32, 0), PI * 0.8)
	Music.set_mode("morning")
	ui.hud_visible(true)
	controls = true
	Controls.capture(true)
	fx["fade"] = 1.0
	fx["fade_target"] = 0.0
	fx["fade_speed"] = 0.7
	fx["letter_target"] = 0.0
	var s := {"day": d, "phase": "morning", "flags": flags.duplicate(true), "patience": 50.0, "start_fear": 0.0}
	save["current"] = s.duplicate(true)
	save["morning"] = s.duplicate(true)
	_write_save()
	_later(0.5, func(): ui.title(tr("Dia %d") % d, "Manhã · a casa está vazia", 4))
	refresh_tasks()
	if d == 2:
		_later(6.0, func():
			if phase == "morning":
				hint_once("morning", "De manhã a casa é segura. Prepare-se para a noite: as tarefas ficam no canto da tela.", 8))
		_later(14.0, func():
			if phase == "morning":
				hint_once("morningvision", "Procure de perto as [b]marcas[/b] que as assombrações deixaram.", 8))


func _task_done(id: String) -> bool:
	if id.begins_with("mark"):
		var dd := int(id.substr(4))
		for m: House.Mark in house.marks:
			if m.day == dd and m.id in flags["marks_seen"]:
				return true
		return false
	match id:
		"duct":
			return flags["duct_open"]
		"basculante":
			return flags["basculante_open"]
		"hatch":
			return flags["hatch_open"]
		"box0", "box1":
			var b = flags["boxes"][int(id.substr(3))]
			return b != null and b["moved"]
		"nightlight":
			var nl = flags.get("nightlight")
			return nl != null and Layout.room_at(Vector3(nl["x"], nl["y"], nl["z"])) != "despensa"
		"flap":
			return flags.get("flap_open", false)
		"porao_win":
			return flags.get("porao_win_open", false)
		"foto", "coleira", "chave":
			return flags["clues"][id] != null
		"ritual":
			return all_clues_on_circle()
	return false


func refresh_tasks() -> void:
	if phase != "morning":
		return
	var lst := []
	for t in Story.MORNING_TASKS.get(day, []):
		lst.append({"text": t["text"], "done": _task_done(t["id"])})
	var left := maxf(0.0, MORNING_LEN - phase_t)
	ui.tasks("Preparo da manhã", lst, tr("Clara volta em %d:%02d · ou durma na caminha") % [floori(left / 60.0), floori(fmod(left, 60.0))])


func on_task(_id: String) -> void:
	refresh_tasks()


func on_clue_found(id: String) -> void:
	var names := {"foto": "uma foto antiga", "coleira": "uma coleira antiga", "chave": "uma chave pequena"}
	var lines := {
		"foto": "Dona Ivone, com um gato preto no colo. Atrás: “Sete anos juntos”.",
		"coleira": "Uma coleira vermelha com um sininho. No pingente: “Breu”.",
		"chave": "Uma chave pequena e enferrujada. Abre o baú do sótão.",
	}
	ui.say("", tr("Você encontrou %s. %s") % [tr(names[id]), tr(lines[id])], 6, "narrator")
	on_task(id)


func _morning_update(dt: float) -> void:
	phase_t += dt
	if floori(phase_t) != floori(phase_t - dt):
		refresh_tasks()
	if true:
		for m: House.Mark in house.marks:
			if m.day != day or m.id in flags["marks_seen"]:
				continue
			if m.pos.distance_to(cam.global_position) > 4.5:
				continue
			if cam.is_position_behind(m.pos):
				continue
			var sp := cam.unproject_position(m.pos)
			var vs := get_viewport().get_visible_rect().size
			if absf(sp.x / vs.x * 2 - 1) > 0.55 or absf(sp.y / vs.y * 2 - 1) > 0.55:
				continue
			if house.blocked(cam.global_position, m.pos + (cam.global_position - m.pos).normalized() * 0.08):
				continue
			flags["marks_seen"].append(m.id)
			ui.say("", m.text, 6, "narrator")
			Sfx.bell(null, 1, 0.12)
			on_task("mark%d" % day)
	if phase_t >= MORNING_LEN and not _transitioning:
		ui.say("", tr("%s cochilou no sol da janela...") % Settings.cat_name, 3, "narrator")
		skip_phase()


# ====================================================================== AFTERNOON


## the afternoon's state. Day 1 missions: wait_eat (she kneels by the bowl), key_asked / wait_key /
## key_given / key_missed (the padlock key); lapped, bath_saved, scene_done tick the day's task;
## purr_t counts the purring next to her in bed that ends the day.
func _fresh_aft() -> Dictionary:
	return {"pets": 0, "pet_cd": 0.0, "fed": false, "played": false, "bowl_filled": false, "scene": "", "bathing": false, "bath_t": 0.0, "bath_wait": false, "private": "",
		"can_skip": false, "ending": false, "kneel_cd": 12.0, "sneeze_cd": 4.0, "lap_open": false, "lap": false, "tv_t": -1.0,
		"tv_scared": false, "props": [],
		"wait_eat": false, "call_t": 12.0, "key_asked": false, "wait_key": false, "key_call_t": 15.0, "key_given": false, "key_missed": false,
		"lapped": false, "bath_saved": false, "scene_done": false, "purr_t": 0.0, "bed_hinted": false}


## where Clara stands to flip a room's switch, and which way she faces
func _switch_stand(li: int) -> Array:
	for d in Layout.data()["LIGHTS"]:
		if int(d.get("index", -1)) == li and d.get("sw") != null:
			var p := Layout.v3(d["sw"]["p"])
			var n := Layout.v3(d["sw"]["n"])
			var floor_y := p.y - 1.1
			return [Vector3(p.x + n.x * 0.42, floor_y, p.z + n.z * 0.42), atan2(-n.x, -n.z), p]
	return []


## walk to a switch, reach for it, the light comes on
func _switch_steps(who: Owner, li: int) -> Array:
	var sw := _switch_stand(li)
	if sw.is_empty():
		return []
	var stand: Vector3 = sw[0]
	return [
		{"t": "walk", "node": house.nav.nearest(stand).id, "end": stand},
		{"t": "face", "yaw": sw[1]},
		{"t": "anim", "gesture": "switch", "wait": false},
		{"t": "wait", "dur": 0.4},
		{"t": "do", "fn": func():
			var l := house.lights.get_light(li)
			if l and not l.on:
				l.set_on(true)
			Sfx.click(sw[2], 0.5)},
		{"t": "wait", "dur": 0.35},
	]


## a prop people carry, copied from the house (box, suitcase, backpack), the doll or a small book
func _prop(kind: String) -> Node3D:
	var pivot := Node3D.new()
	var src: Node3D = null
	match kind:
		"box":
			src = house.find("box_quarto_1")
		"backpack":
			src = house.find("GUEST_MOVEIN_backpack")
		"doll":
			src = (load("res://assets/models/ghosts/doll.glb") as PackedScene).instantiate() if ResourceLoader.exists("res://assets/models/ghosts/doll.glb") else DollThreat._placeholder()
	var vis: Node3D
	if kind == "suitcase":
		# an old brown leather suitcase with a handle on top
		vis = Node3D.new()
		var leather := StandardMaterial3D.new()
		leather.albedo_color = Color(0.42, 0.25, 0.16)
		leather.roughness = 0.7
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.7, 0.55, 0.3)
		brass.metallic = 0.7
		brass.roughness = 0.35
		var body := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.15, 0.4, 0.56)
		body.mesh = bm2
		body.material_override = leather
		body.position = Vector3(0, -0.27, 0)
		vis.add_child(body)
		var handle := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.045
		tm.outer_radius = 0.06
		handle.mesh = tm
		handle.material_override = leather
		handle.rotation = Vector3(0, 0, PI / 2)
		handle.position = Vector3(0, -0.04, 0)
		vis.add_child(handle)
		for zz in [-0.2, 0.2]:
			var clasp := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = Vector3(0.16, 0.05, 0.04)
			clasp.mesh = cb
			clasp.material_override = brass
			clasp.position = Vector3(0, -0.1, zz)
			vis.add_child(clasp)
		aft["props"].append(pivot)
		pivot.add_child(vis)
		add_child(pivot)
		return pivot
	if kind == "cushion":
		# one of the sofa cushions, hugged to the chest
		var cmi := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.4, 0.38, 0.13)
		cmi.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.72, 0.62, 0.7)
		cmat.roughness = 0.95
		cmi.material_override = cmat
		cmi.scale = Vector3(1, 1, 1)
		aft["props"].append(pivot)
		pivot.add_child(cmi)
		add_child(pivot)
		return pivot
	if kind == "book":
		# Ivone's diary: worn brown cover, cream pages; "closed" and "open" (two halves in a shallow V),
		# switched by _book_open
		var cover := StandardMaterial3D.new()
		cover.albedo_color = Color(0.36, 0.2, 0.14)
		cover.roughness = 0.8
		var paper := StandardMaterial3D.new()
		paper.albedo_color = Color(0.86, 0.79, 0.64)
		paper.roughness = 0.9
		var block := func(size: Vector3, at: Vector3, mat: Material, parent: Node3D) -> void:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
			mi.material_override = mat
			mi.position = at
			parent.add_child(mi)
		vis = Node3D.new()
		var closed := Node3D.new()
		closed.name = "closed"
		vis.add_child(closed)
		block.call(Vector3(0.16, 0.035, 0.22), Vector3.ZERO, cover, closed)
		block.call(Vector3(0.006, 0.027, 0.208), Vector3(0.079, 0, 0), paper, closed)
		var open := Node3D.new()
		open.name = "open"
		open.visible = false
		vis.add_child(open)
		for s in [-1.0, 1.0]:
			var half := Node3D.new()
			half.rotation.z = -s * 0.14
			open.add_child(half)
			block.call(Vector3(0.162, 0.005, 0.224), Vector3(s * 0.081, 0, 0), cover, half)
			block.call(Vector3(0.152, 0.012, 0.21), Vector3(s * 0.078, 0.008, 0), paper, half)
	elif src != null:
		vis = src.duplicate() if src.is_inside_tree() else src
		vis.visible = true
		if kind == "doll":
			vis.scale = Vector3.ONE * 0.8
	else:
		vis = Node3D.new()
	pivot.add_child(vis)
	vis.transform = Transform3D(Basis.IDENTITY.scaled(vis.scale), Vector3.ZERO)
	# rest the copy on the pivot: centred, its top at the hand for things that hang, bottom otherwise
	var ab := _node_aabb(vis)
	var c := ab.get_center()
	match kind:
		"box":
			var k := 0.42 / maxf(0.05, ab.size.y)
			vis.scale *= k
			ab = _node_aabb(vis)
			c = ab.get_center()
			vis.position = Vector3(-c.x, -c.y, -c.z)
		"backpack":
			vis.position = Vector3(-c.x, -c.y, -c.z)
		"doll":
			vis.position = Vector3(-c.x, -ab.position.y - ab.size.y * 0.35, -c.z)
	aft["props"].append(pivot)
	add_child(pivot)
	return pivot


func _node_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in [n] + n.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null:
			continue
		var rel := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n.get_parent():
			if p is Node3D:
				rel = (p as Node3D).transform * rel
			p = p.get_parent()
		var ab := rel * (mi as MeshInstance3D).mesh.get_aabb()
		out = ab if first else out.merge(ab)
		first = false
	return out


## the diary in someone's hands: open to read (both hands) or closed against the chest
func _book_open(o: Owner, open: bool) -> void:
	var b := o.model.drop_held("hand")
	if b == null:
		b = _prop("book")
	b.find_child("closed", true, false).visible = not open
	b.find_child("open", true, false).visible = open
	o.model.hold(b, "book_open" if open else "book")


func _drop_prop(o: Owner) -> void:
	var b := o.model.drop_held("hand")
	if b:
		b.queue_free()


func _clear_props() -> void:
	for p in aft.get("props", []):
		if is_instance_valid(p):
			(p as Node).queue_free()
	for o: Owner in [clara, davi]:
		for slot in ["hand", "back"]:
			o.model.drop_held(slot)


func start_afternoon() -> void:
	_epoch += 1
	ui.close_overlay()
	ui.clear_talk_log()
	var d := day
	phase = "afternoon"
	mode = "play"
	phase_t = 0.0
	if aft.has("props"):
		_clear_props()
	aft = _fresh_aft()
	aft["scene"] = Story.DAY_SCENES.get(d, "")
	apply_env("afternoon")
	Music.set_mode("afternoon")
	ui.tasks(null, [])
	# she comes home to a dark house and turns the lights on as she goes
	house.lights.set_all(false)
	house.lights.get_light(13).set_on(true)
	house.set_guest_parts(d > Config.DAVI_DAY, d <= Config.DAVI_DAY)
	house.set_food(0.0)
	# the water bowl starts empty on the days the cat has to ask for it
	var wsurf := house.find("bowl_water_surface")
	if wsurf:
		wsurf.visible = not aft_has("water")
	ui.lives(SaveGame.lives_at(save, d))
	Controls.capture(true)
	var tvd := _device("tv")
	if tvd:
		house.set_plugged(tvd, true)
	var o := clara
	o.set_night(false)
	o.show_model()
	o.fear = 0.0
	o.patience = 45.0
	o.in_bed = false
	o.look_hint = null
	o.place({"node": "g_hall_front", "p": [6.45, 0, -1.0], "yaw": 0.0})
	o.model.snap_pose("stand")
	if d == 1:
		# moving day: the cat is waiting on the kitchen table when she comes in
		cat.teleport(KITCHEN_TABLE_TOP, PI)
		rig.snap(cat.global_position + Vector3(0, 0.32, 0), PI)
		o.model.hold(_prop("box"), "box")
		# the basement door is shut on the first afternoon: she opens it when she goes down
		house.doors["d_porao"].set_state("closed", true)
	var front: Door = house.doors["d_front"]
	front.locked = false
	front.set_state("open")
	Sfx.creak(front.center() + Vector3(0, 1, 0), 0.5, 1.2)
	davi.present = d >= Config.DAVI_DAY
	davi.in_bed = false
	davi.hide_model()
	if davi.present:
		davi.set_night(false)
		davi.fear = 0.0
		davi.patience = 60.0
		davi.look_hint = null
		davi.place({"node": "g_hall_front", "p": [6.45, 0, -2.4], "yaw": 0.0})
		davi.model.snap_pose("stand")
		if d > Config.DAVI_DAY:
			_later(9.0, func():
				if phase == "afternoon":
					_davi_arrives(d))
	fx["fade_target"] = 0.0
	controls = true
	# coming from the menu the HUD is hidden, and it holds her lines (subtitles) and the hints
	ui.hud_visible(true)
	var s := {"day": d, "phase": "afternoon", "flags": flags.duplicate(true), "patience": 45.0, "start_fear": 0.0}
	save["current"] = s.duplicate(true)
	_write_save()
	var sub := {1: "Fim de tarde · a mudança", Config.DAVI_DAY: "Fim de tarde · Davi está chegando"}
	_later(0.4, func(): ui.title(tr("Dia %d") % d, sub.get(d, "Fim de tarde · Clara chegou"), 3.5))
	if d == 1:
		_schedule_aft_hint(5, "move", tr("Mova-se com %s e olhe com o mouse. %s corre.") % [ui.kbd("W A S D"), ui.kbd("run")])
		_schedule_aft_hint(14, "jump", tr("Quando aparecer um [b]círculo[/b] no chão ou num móvel, %s pula até ele.") % ui.kbd("jump"))
		_schedule_aft_hint(22, "marker", "O [b]losango[/b] dourado mostra aonde ir. As tarefas ficam no canto da tela.")
	else:
		_schedule_aft_hint(5, "aft", "Ganhe a [b]Paciência[/b] de Clara para a noite: peça carinho, coma, brinque com o ratinho.")
	var steps: Array = _arrival_steps(d)
	steps.append_array(_scene_steps(aft["scene"]))
	steps.append({"t": "do", "fn": func(): aft["scene_done"] = true})
	steps.append_array(_close_steps(d))
	o.run("afternoon", steps, 1)
	refresh_afternoon_tasks()


func _schedule_aft_hint(at: float, id: String, bb: String) -> void:
	var ep := _epoch
	_later(at, func():
		if phase == "afternoon" and _epoch == ep:
			hint_once(id, bb, 8))


func _device(id: String) -> House.Device:
	for dv: House.Device in house.devices:
		if dv.id == id:
			return dv
	return null


## in through the front door, the hall light, the keys on the hall table (the box on day 1), the
## kitchen light and the bowl
func _arrival_steps(d: int) -> Array:
	var o := clara
	var front: Door = house.doors["d_front"]
	var lines: Dictionary = Story.AFTERNOON_LINES.get(d, Story.AFTERNOON_LINES[2])
	var steps: Array = [
		{"t": "walk", "node": "g_hall_front"},
		{"t": "do", "fn": func():
			if d != Config.DAVI_DAY:
				front.set_state("closed")},
		{"t": "say", "text": lines["arrive"], "dur": 3.0},
	]
	steps.append_array(_switch_steps(o, 4))
	if d == 1:
		# the moving box goes down in the living room
		steps.append_array(_switch_steps(o, 2))
		steps.append_array([
			{"t": "walk", "node": "g_sala_door", "end": Vector3(4.15, 0, 1.72)},
			{"t": "face", "yaw": PI},
			{"t": "pose", "pose": "kneel", "dur": 0.9},
			{"t": "do", "fn": func():
				var b := o.model.drop_held("hand")
				if b:
					o.model.remove_child(b)
					add_child(b)
					b.global_transform = Transform3D(Basis(Vector3.UP, 0.3), Vector3(4.15, 0.21, 1.15))
				Sfx.thud(Vector3(4.15, 0.1, 1.15), 0.4, 90)},
			{"t": "pose", "pose": "stand", "dur": 0.6},
			# done with the boxes: a look at the cat, arms up, a big smile and a cheer
			{"t": "look", "at": "cat", "dur": 0.6, "turn": true},
			{"t": "do", "fn": func(): o.model.set_mood("joy", 1.0, 2.8)},
			{"t": "say", "text": lines["box_down"], "dur": 2.6},
			{"t": "anim", "gesture": "stretch"},
		])
	else:
		steps.append_array([
			{"t": "spot", "spot": Layout.spot("hallPhone")},
			{"t": "anim", "clip": "interact", "wait": false},
			{"t": "wait", "dur": 0.5},
			{"t": "do", "fn": func(): Sfx.keys(Vector3(7.2, 0.8, 2.95))},
			{"t": "wait", "dur": 0.8},
		])
	steps.append_array(_switch_steps(o, 5))
	steps.append_array([
		{"t": "spot", "spot": Layout.spot("bowl")},
		{"t": "pose", "pose": "kneel", "dur": 1.0},
		{"t": "do", "fn": func():
			house.set_food(1.0)
			aft["bowl_filled"] = true
			Sfx.play("porcelain", Vector3(8.6, 0.1, 3.9), 0.25, 1.4)},
		{"t": "say", "text": lines["bowl"], "dur": 2.6},
	])
	if d == 1:
		# mission 1: she stays kneeling by the bowl, calling, until the cat eats (90 s at most)
		steps.append_array([
			{"t": "do", "fn": func():
				aft["wait_eat"] = true
				aft["call_t"] = 12.0
				hint_once("eat_mission", tr("Clara quer que você coma com ela. Vá até a [b]tigela[/b] na cozinha e segure %s.") % ui.kbd("interact"), 9)},
			{"t": "until", "cond": func(): return aft["fed"], "pose": "kneel", "timeout": 90.0},
			{"t": "do", "fn": func():
				aft["wait_eat"] = false
				if aft["fed"]:
					o.model.set_mood("joy", 0.9, 2.6)
				o.say(lines["ate"] if aft["fed"] else lines["ate_late"], 2.6)},
			{"t": "pose", "pose": "kneel", "dur": 2.4},
			{"t": "pose", "pose": "stand", "dur": 0.5},
			{"t": "wait", "dur": 1.0},
		])
	else:
		steps.append_array([
			{"t": "wait", "dur": 1.2},
			{"t": "pose", "pose": "stand", "dur": 0.5},
			{"t": "wait", "dur": 3.0},
		])
	return steps


func _scene_steps(scene: String) -> Array:
	var o := clara
	match scene:
		"move_in":
			return _key_steps()
		"tv":
			var tvd := _device("tv")
			var steps := _switch_steps(o, 2)
			steps.append_array([
				{"t": "spot", "spot": Layout.spot("sofa")},
				{"t": "pose", "pose": "sit", "dur": 1.8},
				{"t": "do", "fn": func():
					_tv_show(true)
					Sfx.buzz(o.head_pos(), 0.4)},
				{"t": "say", "text": "...Mais um \"não\" educado. Tá. Próximo.", "dur": 3.0},
				{"t": "wait", "dur": 1.0},
				{"t": "say", "text": "Casamento na novela? Hoje não. Próximo canal.", "dur": 2.8},
				{"t": "anim", "gesture": "pat", "wait": false},
				{"t": "say", "text": "Vem, {cat}! Vem cá no colo.", "dur": 2.6},
				{"t": "do", "fn": func():
					aft["lap_open"] = true
					hint_once("lap", "Pule no colo de Clara: o [b]círculo[/b] aparece quando você olha para ela.", 7)},
				{"t": "until", "cond": func(): return aft["tv_scared"], "pose": "sit", "timeout": 70.0},
				{"t": "wait", "dur": 1.6},
				{"t": "pose", "pose": "stand", "dur": 1.2},
				{"t": "walk", "node": "g_sala_tv", "end": Vector3(3.35, 0, 4.95)},
				{"t": "face", "yaw": 0.4},
				{"t": "pose", "pose": "kneel", "dur": 0.9},
				{"t": "do", "fn": func():
					if tvd:
						house.set_plugged(tvd, false)
					_tv_show(false)
					Sfx.click(Vector3(3.55, 0.3, 5.4), 0.6)},
				{"t": "pose", "pose": "stand", "dur": 0.6},
				{"t": "say", "text": "Pronto. Sem TV hoje.", "dur": 2.6},
				{"t": "do", "fn": func(): o.look_hint = null},
			])
			return steps
		"bath":
			return _bath_steps()
		"davi":
			return _davi_day_steps()
		"phone":
			return [
				{"t": "spot", "spot": Layout.spot("hallPhone")},
				{"t": "pose", "pose": "phone", "dur": 0.8},
				{"t": "say", "text": "Alô? ...Ah. É você.", "dur": 2.4},
				{"t": "pose", "pose": "phone", "dur": 3.0},
				{"t": "say", "text": "Não, Rafael. Eu tô bem. Tô ótima.", "dur": 2.8},
				{"t": "pose", "pose": "phone", "dur": 3.0},
				{"t": "say", "text": "Não. Não vem. E para de bater na porta dos outros às duas da manhã. Três batidinhas. Eu conheço.", "dur": 4.2},
				{"t": "pose", "pose": "phone", "dur": 1.6},
				{"t": "say", "text": "Tchau, Rafael.", "dur": 1.8, "kind": "annoyed"},
				{"t": "pose", "pose": "stand", "dur": 0.6},
				{"t": "anim", "gesture": "cross_arms"},
				{"t": "say", "text": "...Tá tudo certo, {cat}. Tá tudo certo.", "dur": 2.8},
			]
		"diary":
			return [
				# she waits in the hall for Davi, who tells her about the diary at the door; she opens it standing,
				# hugs it closed to the sofa and reads it sat next to him
				{"t": "spot", "spot": DIARY_WAIT},
				{"t": "do", "fn": func(): aft["diary_wait"] = true},
				{"t": "until", "cond": func(): return aft.get("diary_given", false), "timeout": 30.0},
				{"t": "do", "fn": func():
					if o.model.holding() != "book":
						_book_open(o, false)},
				{"t": "look", "at": davi, "dur": 1.0, "turn": true},
				{"t": "do", "fn": func(): _book_open(o, true)},
				{"t": "wait", "dur": 0.8},
				{"t": "say", "text": "Um diário? ...Faltam páginas. Alguém arrancou.", "dur": 3.2},
				{"t": "wait", "dur": 3.8},
				{"t": "do", "fn": func(): _book_open(o, false)},
				{"t": "spot", "spot": Layout.spot("sofa")},
				{"t": "pose", "pose": "sit", "dur": 1.4},
				{"t": "do", "fn": func(): _book_open(o, true)},
				{"t": "pose", "pose": "read", "dur": 1.5},
				{"t": "say", "text": Story.DIARY_LINES[0], "dur": 5.0, "kind": "read"},
				{"t": "pose", "pose": "read", "dur": 5.0},
				{"t": "say", "text": Story.DIARY_LINES[1], "dur": 5.0, "kind": "read"},
				{"t": "pose", "pose": "read", "dur": 5.0},
				{"t": "say", "text": Story.DIARY_LINES[2], "dur": 6.0, "kind": "read"},
				{"t": "pose", "pose": "read", "dur": 6.0},
				{"t": "do", "fn": func(): _book_open(o, false)},
				{"t": "pose", "pose": "sit", "dur": 1.0},
				{"t": "look", "at": davi, "dur": 1.5},
				{"t": "do", "fn": func():
					_drop_prop(o)
					o.model.hold(_prop("cushion"), "cushion")},
				{"t": "pose", "pose": "sit", "dur": 0.8},
				{"t": "say", "text": "Quarenta anos sozinha aqui. Ninguém veio ver ela.", "dur": 3.2},
				{"t": "do", "fn": func(): aft["diary_read"] = true},
				{"t": "pose", "pose": "sit", "dur": 3.5},
				{"t": "say", "text": "...É. Vou dormir cedo hoje.", "dur": 2.6},
				{"t": "do", "fn": func(): _drop_prop(o)},
				{"t": "pose", "pose": "stand", "dur": 1.2},
			]
		"eve":
			return [
				{"t": "spot", "spot": Layout.spot("sofa")},
				{"t": "pose", "pose": "sit", "dur": 1.5},
				{"t": "do", "fn": func(): o.model.hold(_prop("cushion"), "cushion")},
				{"t": "until", "cond": func(): return aft.get("davi_seated", false), "pose": "sit", "timeout": 30.0},
				{"t": "say", "text": "Hoje a gente dorme de luz acesa, Davi.", "dur": 3.2},
				{"t": "pose", "pose": "sit", "dur": 3.6},
				{"t": "do", "fn": func(): _basement_tremor()},
				{"t": "pose", "pose": "sit", "dur": 1.2},
				{"t": "say", "text": "Você ouviu isso?", "dur": 2.2, "kind": "scared"},
				{"t": "do", "fn": func(): aft["eve_heard"] = true},
				{"t": "pose", "pose": "sit", "dur": 3.0},
				{"t": "say", "text": "Davi... eu tô cansada. Muito.", "dur": 3.0},
				{"t": "do", "fn": func(): aft["eve_confess"] = true},
				{"t": "pose", "pose": "sit", "dur": 4.5},
				{"t": "say", "text": "Seja o que for... a gente passa por essa noite.", "dur": 3.4},
				{"t": "pose", "pose": "sit", "dur": 3.0},
				{"t": "say", "text": "{cat}, fica de olho. Por favor.", "dur": 3.0},
				{"t": "pose", "pose": "sit", "dur": 3.0},
				{"t": "do", "fn": func(): _drop_prop(o)},
				{"t": "pose", "pose": "stand", "dur": 1.2},
			]
	return [{"t": "wait", "dur": 10.0}]


## day 1, mission 2: at the basement door she asks for the padlock key she left on the moving box, opens
## the door, lights the laundry and the basement and waits down there until the cat brings it (or gives
## up after a while); with the key she opens the old padlock and comes back up
func _key_steps() -> Array:
	var o := clara
	var pd: Door = house.doors["d_porao"]
	var lines: Dictionary = Story.AFTERNOON_LINES[1]
	var steps: Array = [
		{"t": "walk", "node": "g_coz_bdoor"},
		{"t": "look", "at": pd.center() + Vector3(0, 0.6, 0), "dur": 1.6, "turn": true},
		{"t": "do", "fn": func(): _show_porao_key(true)},
		{"t": "say", "text": lines["key_ask"], "dur": 3.6},
		{"t": "do", "fn": func():
			aft["key_asked"] = true
			hint_once("key_mission", "Pegue a [b]chave[/b] em cima da caixa da mudança, na sala, e leve para Clara no porão.", 9)},
		{"t": "wait", "dur": 0.8},
		{"t": "say", "text": lines["key_down"], "dur": 2.6},
		{"t": "do", "fn": func():
			pd.set_state("open")
			Sfx.creak(pd.center() + Vector3(0, 1, 0), 0.45, 1.6, 0.85)},
		{"t": "wait", "dur": 0.6},
	]
	steps.append_array(_switch_steps(o, 1))
	steps.append_array(_switch_steps(o, 0))
	steps.append_array([
		{"t": "walk", "node": "b_porao_mid"},
		{"t": "look", "at": house.ritual_center + Vector3(0, 0.4, 0), "dur": 1.8, "turn": true},
		{"t": "do", "fn": func():
			aft["wait_key"] = true
			aft["key_call_t"] = 15.0},
		{"t": "until", "cond": func(): return aft["key_given"], "timeout": 150.0},
		{"t": "do", "fn": func():
			aft["wait_key"] = false
			if not aft["key_given"]:
				aft["key_missed"] = true
				o.say(lines["key_none"], 3.0)},
		{"t": "if", "cond": func(): return aft["key_given"], "then": [
			{"t": "wait", "dur": 2.4},
			{"t": "pose", "pose": "kneel", "dur": 0.9},
			{"t": "do", "fn": func():
				Sfx.keys(o.global_position + Vector3(0, 0.4, 0))
				_later(0.7, func(): Sfx.lock_turn(o.global_position + Vector3(0, 0.4, 0)))},
			{"t": "pose", "pose": "kneel", "dur": 1.6},
			{"t": "say", "text": lines["key_lock"], "dur": 3.4},
			{"t": "pose", "pose": "stand", "dur": 0.8},
		]},
		{"t": "walk", "node": "g_coz_bdoor"},
		{"t": "wait", "dur": 1.0},
	])
	return steps


## the padlock key on the moving box (shown when she asks for it), or put away
func _show_porao_key(on: bool) -> void:
	var c: PropSystem.Carryable = house.carryables.get(PORAO_KEY)
	if c == null:
		return
	if cat and cat.carrying == c:
		cat.carrying = null
	c.carried = false
	c.enabled = on
	c.node.visible = on
	c.place(KEY_ON_BOX if on else Vector3(0, -50, 0), 0.4)


## the cat hands Clara the key (the "Dar a chave" interaction, like play_with_owner)
func give_key() -> void:
	var c: PropSystem.Carryable = cat.carrying
	if c == null or c.id != PORAO_KEY:
		return
	_show_porao_key(false)
	aft["key_given"] = true
	var o := clara
	o.add_patience(10)
	o.say(Story.AFTERNOON_LINES[1]["key_thanks"], 2.6)
	o.paused = true
	o.model.pose = "pet"
	o.model.hand_target = cat.global_position + Vector3(0, 0.18, 0)
	o.model.set_mood("joy", 0.9, 2.6)
	Sfx.keys(cat.head())
	_start_purr(0.5)
	refresh_afternoon_tasks()
	_later(2.2, func():
		o.paused = false
		o.model.hand_target = null
		o.model.pose = "stand"
		_stop_purr())


## closing the house for the night: lock the front door, check the windows (more checks as the week
## goes on), comment on what the cat changed if it is on the way, a call to the cat at the stairs, upstairs, night clothes, bed.
## The afternoon only ends when the cat lies down with her (purr_clara, then AFT_PURR_SECS).
func _close_steps(d: int) -> Array:
	var o := clara
	var front: Door = house.doors["d_front"]
	var stops: Array = [
		{"at": Layout.spot_pos("frontDoor"), "steps": [
			{"t": "spot", "spot": Layout.spot("frontDoor")},
			{"t": "do", "fn": func(): front.set_state("closed")},
			{"t": "anim", "gesture": "key_turn", "wait": false},
			{"t": "wait", "dur": 0.5},
			{"t": "do", "fn": func():
				Sfx.lock_turn(front.center() + Vector3(0, 1.0, 0))
				front.locked = true},
			{"t": "wait", "dur": 0.8},
		]},
		{"at": Layout.spot_pos("salaWindow"), "steps": [
			{"t": "spot", "spot": Layout.spot("salaWindow")},
			{"t": "look", "at": Vector3(0.0, 1.4, 2.75), "dur": 1.4},
		]},
	]
	if d >= 3:
		stops.append({"at": Layout.spot_pos("kitchenWindow"), "steps": [
			{"t": "spot", "spot": Layout.spot("kitchenWindow")},
			{"t": "look", "at": Vector3(12.0, 1.4, 4.35), "dur": 1.2},
		]})
	if d >= 5:
		var pd: Door = house.doors["d_porao"]
		stops.append({"at": house.nav.get_node("g_coz_bdoor").p, "steps": [
			{"t": "walk", "node": "g_coz_bdoor"},
			{"t": "look", "at": pd.center() + Vector3(0, 0.6, 0), "dur": 1.6, "turn": true},
		]})
	var stairs := house.nav.get_node("g_stairs_b").p
	# at the foot of the stairs: a look up into the dark landing, then she calls the cat up with her
	stops.append({"at": stairs, "steps": [
		{"t": "walk", "node": "g_stairs_b"},
		{"t": "look", "at": Vector3(5.55, 3.7, 8.7), "dur": 1.2, "turn": true},
		{"t": "say", "text": "Vem, {cat}. Hora de dormir.", "dur": 2.0, "kind": "call"},
	]})
	stops.append({"at": house.nav.get_node("f_cor_mid").p, "steps": [{"t": "walk", "node": "f_cor_mid"}]})
	if d >= 5:
		stops[-1]["steps"].append({"t": "anim", "gesture": "look_back"})
	stops.append({"at": house.nav.get_node("f_cor_front").p, "steps": [{"t": "walk", "node": "f_cor_front"}]})
	# what the cat changed this morning, said at the stop it is closest to (when it is in view)
	for tk in Story.TASK_COMMENTS:
		if not _task_done(tk):
			continue
		var where := _task_place(tk)
		var best := -1
		var bd := 3.8
		for i in stops.size():
			var sp: Vector3 = stops[i]["at"]
			if absf(sp.y - where.y) < 1.6 and Vector2(sp.x - where.x, sp.z - where.z).length() < bd:
				bd = Vector2(sp.x - where.x, sp.z - where.z).length()
				best = i
		if best >= 0:
			stops[best]["steps"].append_array([
				{"t": "look", "at": where + Vector3(0, 0.4, 0), "dur": 1.4},
				{"t": "say", "text": Story.TASK_COMMENTS[tk][1], "dur": 3.0},
			])
	var steps: Array = [{"t": "do", "fn": func(): aft["can_skip"] = true}]
	for i in stops.size():
		steps.append_array(stops[i]["steps"])
		if i == 1:
			steps.append({"t": "say", "text": Story.CLOSE_LINES.get(d, "Pronto. Tudo trancado."), "dur": 3.0})
	if d == Config.LAST_NIGHT:
		steps.append_array(_switch_steps(o, 7))
		steps.append({"t": "say", "text": "Hoje essa luz fica acesa.", "dur": 2.4})
	steps.append_array([
		# night clothes behind the bedroom doors (day 3 she already changed after the bath)
		{"t": "if", "cond": func(): return not o.night, "then": _pajama_steps()},
		# the house goes dark; the bedside lamp stays on while she waits for the cat
		{"t": "do", "fn": func():
			house.lights.set_all(false, [7, 8] if d == Config.LAST_NIGHT else [8])
			var lamp := house.lights.get_light(8)
			if lamp and not lamp.on:
				lamp.set_on(true)},
		{"t": "spot", "spot": Layout.spot("bedside")},
		{"t": "say", "text": Story.BED_CALL, "dur": 2.6, "kind": "whisper"},
		{"t": "bed"},
	])
	return steps


## where a morning change can be seen from
func _task_place(id: String) -> Vector3:
	match id:
		"box0", "box1":
			var b = flags["boxes"][int(id.substr(3))]
			return Vector3(b["x"], b.get("y", 0.0), b["z"]) if b != null and b.has("x") else Vector3(0, -50, 0)
		"nightlight":
			var nl = flags.get("nightlight")
			return Vector3(nl["x"], nl["y"], nl["z"]) if nl != null else Vector3(0, -50, 0)
	return Story.TASK_COMMENTS[id][0]


# ---------------------------------------------------------------------- day 2: TV and the lap


func _tv_show(on: bool) -> void:
	var tvd := _device("tv")
	if tvd == null or tvd.screen_mat == null:
		return
	var m := tvd.screen_mat
	if on:
		m.set_shader_parameter("program_tex", load("res://assets/textures/gen/tv_show.png"))
		m.set_shader_parameter("program", 1.0)
		m.set_shader_parameter("freeze", 0.0)
		m.set_shader_parameter("face_flash", 0.0)
		m.set_shader_parameter("frame", 0.0)
		tvd.glow = 0.0
		aft["tv_t"] = 0.0
		aft["tv_loop"] = Sfx.loop("tv", tvd.pos, 1.2)
		aft["tv_loop"].set_level(0.55)
		clara.look_hint = tvd.pos
	else:
		m.set_shader_parameter("program", 0.0)
		m.set_shader_parameter("freeze", 0.0)
		m.set_shader_parameter("face_flash", 0.0)
		tvd.glow = 0.0
		aft["tv_t"] = -1.0
		for k in ["tv_loop", "tv_static"]:
			if aft.get(k):
				aft[k].stop(0.2)
				aft[k] = null


## the show runs ~30 s, then the picture freezes, the slow voice, a face flashes, loud static
func _tv_update(dt: float) -> void:
	if aft["tv_t"] < 0.0:
		return
	var tvd := _device("tv")
	aft["tv_t"] += dt
	var t: float = aft["tv_t"]
	var m := tvd.screen_mat
	if t < 30.0:
		var seq := [0, 1, 2, 3, 1, 2, 4, 3, 2]
		m.set_shader_parameter("frame", float(seq[int(t / 3.4) % seq.size()]))
		return
	if not aft.get("tv_froze", false):
		aft["tv_froze"] = true
		m.set_shader_parameter("freeze", 0.6)
		if aft.get("tv_loop"):
			aft["tv_loop"].set_level(0.0)
		Sfx.tv_vem(tvd.pos)
	if t > 33.6 and t < 35.6:
		# the face, a few frames at a time
		m.set_shader_parameter("face_flash", 1.0 if fmod(t, 0.45) < 0.16 else 0.0)
		m.set_shader_parameter("freeze", 1.0)
	if t >= 35.6 and not aft["tv_scared"]:
		aft["tv_scared"] = true
		m.set_shader_parameter("face_flash", 0.0)
		m.set_shader_parameter("program", 0.0)
		tvd.glow = 1.0
		aft["tv_static"] = Sfx.loop("static", tvd.pos, 1.6)
		aft["tv_static"].set_level(1.0)
		sting(0.5)
		if cat.mode == "lap":
			_leave_lap(true)
		clara.startle()
		clara.add_fear(6)
		clara.say("Ai! Que susto!", 2.0, "scared")


func lap_point():
	if phase != "afternoon" or not aft.get("lap_open", false) or aft.get("lap", false) or aft.get("tv_scared", false):
		return null
	if clara.model.pose != "sit":
		return null
	var a := clara.model.bone_world("thigh_l").origin.lerp(clara.model.bone_world("calf_l").origin, 0.45)
	var b := clara.model.bone_world("thigh_r").origin.lerp(clara.model.bone_world("calf_r").origin, 0.45)
	return (a + b) * 0.5 + Vector3(0, 0.07, 0)


func _enter_lap() -> void:
	aft["lap"] = true
	aft["lapped"] = true
	cat.mode = "lap"
	var lp = (clara.model.bone_world("thigh_l").origin + clara.model.bone_world("thigh_r").origin) * 0.5
	var fwd := Vector3(sin(clara.yaw), 0, cos(clara.yaw))
	cat.mode_target = (lp as Vector3) + fwd * 0.12 + Vector3(0, 0.08, 0)
	cat.mode_yaw = clara.yaw + PI / 2
	clara.purring = true
	_start_purr(0.8)
	clara.model.set_mood("joy", 0.8, 3.0)
	clara.say("Isso! Que gato bom.", 2.2)
	hint_once("lapout", "No colo o [b]Foco[/b] recarrega como ronronando. Mexa-se para descer.", 6)


func _leave_lap(jump := false) -> void:
	aft["lap_open"] = false
	cat.mode = "free"
	clara.purring = false
	clara.model.hand_target = null
	_stop_purr()
	var fwd := Vector3(sin(clara.yaw), 0, cos(clara.yaw))
	cat.teleport(Vector3(clara.global_position.x, 0.0, clara.global_position.z) + fwd * 0.9, clara.yaw)
	if jump:
		cat_hop()


# ---------------------------------------------------------------------- day 3: the bath


func _bath_steps() -> Array:
	var o := clara
	var bdoor: Door = house.doors["d_banc"]
	return [
		{"t": "say", "text": "Vou tomar um banho quentinho...", "dur": 2.6},
		{"t": "walk", "node": "f_banc_mid"},
		{"t": "do", "fn": func():
			_go_private("banheiro_cima", ["d_banc"], house.nav.get_node("f_d_banc_c").p, PI / 2)
			aft["shower"] = Sfx.loop("water", Vector3(10.6, 3.6, 8.9), 1.2)
			aft["shower"].set_level(0.7)
			for f: House.Faucet in house.faucets:
				if f.id == "tub":
					f.level = 0.8
					if f.water and f.water.material_override:
						(f.water.material_override as ShaderMaterial).set_shader_parameter("foam", 1.0)},
		{"t": "wait", "dur": 2.5},
		# behind the closed door: the towel, the turban, into the tub
		{"t": "do", "fn": func():
			o.set_outfit_k("bath")
			o.model.set_turban(true)
			o.model.hide_skirt(true)
			if aft.get("shower"):
				aft["shower"].set_level(0.18)
			o.place(Layout.spot("bathTubIn"))
			o.model.snap_pose("bath")
			aft["bath_wait"] = true
			refresh_afternoon_tasks()
			hint_once("bath_door", "Clara se trancou no banho. Arranhe a porta do banheiro.", 6)},
		{"t": "until", "cond": func(): return not aft.get("bath_wait", false), "pose": "bath", "timeout": 50.0},
		{"t": "do", "fn": func():
			if aft.get("bath_wait", false):
				open_bath_door(false)},
		{"t": "until", "cond": func(): return not aft["bathing"], "pose": "bath", "timeout": 45.0},
		{"t": "do", "fn": func():
			if aft["bathing"]:
				end_bath(false)},
		{"t": "pose", "pose": "stand", "dur": 0.6},
		{"t": "anim", "gesture": "hug_self", "wait": false},
		{"t": "say", "text": "Brr...", "dur": 1.6},
		{"t": "wait", "dur": 1.6},
	] + _pajama_steps()


## the bedroom with both its doors shut while she changes into her night clothes (the cat waits
## outside); used by the bath on day 3 and by closing the house every other day
func _pajama_steps() -> Array:
	var o := clara
	return [
		{"t": "walk", "node": "f_quarto_door"},
		{"t": "walk", "node": "f_quarto_s"},
		{"t": "do", "fn": func():
			_go_private("quarto", ["d_quarto", "d_quarto_hosp"], house.nav.get_node("f_d_quarto_c").p, -PI / 2)},
		{"t": "wait", "dur": 3.0},
		{"t": "do", "fn": func():
			o.set_night(true)
			o.model.set_turban(false)
			o.model.hide_skirt(false)
			o.model.reset_springs()
			_end_private()},
	]


## she shuts herself in a room: its doors close and the cat, if it is inside, is put out in a blink
## (it keeps being put out while the room is private: the bathroom window is another way in)
func _go_private(room: String, doors: Array, out_pos: Vector3, out_yaw: float) -> void:
	aft["private"] = room
	aft["private_doors"] = doors
	aft["private_out"] = [out_pos, out_yaw]
	for dn in doors:
		var d: Door = house.doors.get(dn)
		if d and d.state != "closed":
			d.set_state("closed")
			Sfx.creak(d.center() + Vector3(0, 1, 0), 0.3, 0.85)
	_shoo_from_private()


func _end_private() -> void:
	for dn in aft.get("private_doors", []):
		var d: Door = house.doors.get(dn)
		if d:
			d.set_state("open")
			Sfx.creak(d.center() + Vector3(0, 1, 0), 0.25, 1.0)
	aft["private"] = ""
	aft["private_doors"] = []


func _shoo_from_private() -> void:
	var room: String = aft.get("private", "")
	if room == "" or cat == null or Layout.room_at(cat.global_position) != room:
		return
	var out: Array = aft["private_out"]
	blink()
	_stop_eating()
	if cat.mode != "free":
		cat.mode = "free"
	cat.teleport(out[0], out[1])
	rig.snap(cat.global_position + Vector3(0, 0.32, 0), out[1] + PI)
	if not aft.get("shoo_said", false):
		aft["shoo_said"] = true
		clara.say("{cat}, sai! Um minutinho de privacidade, por favor.", 2.6, "annoyed")


## a short black blink that hides a jump cut
func blink() -> void:
	fx["fade"] = 1.0
	fx["fade_target"] = 0.0
	fx["fade_speed"] = 2.5


## the cat scratched the bathroom door (or she got tired of waiting): she calls it in from the tub
func open_bath_door(by_cat: bool) -> void:
	if not aft.get("bath_wait", false):
		return
	aft["bath_wait"] = false
	aft["private"] = ""
	var bdoor: Door = house.doors["d_banc"]
	bdoor.set_state("ajar")
	Sfx.creak(bdoor.center() + Vector3(0, 1, 0), 0.35, 1.1)
	clara.say("Tá aberta, {cat}. Pode entrar, chato." if by_cat else "{cat}? Pode entrar, tá aberta.", 2.6)
	aft["bathing"] = true
	aft["bath_t"] = 0.0
	refresh_afternoon_tasks()
	hint_once("bath", "Algo se mexe na água. Tire Clara da banheira.", 8)


func end_bath(by_cat: bool) -> void:
	if not aft.get("bathing", false):
		return
	aft["bathing"] = false
	director.drowner.hands.alpha = 0.0
	for f: House.Faucet in house.faucets:
		if f.id == "tub":
			f.level = 0.0
			if f.water and f.water.material_override:
				(f.water.material_override as ShaderMaterial).set_shader_parameter("foam", 0.0)
	if aft.get("shower"):
		aft["shower"].stop(0.5)
		aft["shower"] = null
	blink()
	clara.place(Layout.spot("tub"))
	clara.model.hide_skirt(false)
	if by_cat:
		clara.say("Tá bom, tá bom! Já saí, chato.", 3.0, "annoyed")
		flags["bath_scene_done"] = true
		aft["bath_saved"] = true
	else:
		clara.say("Brr... que água gelada de repente.", 3.0, "scared")
		flags["bath_scene_done"] = false


# ---------------------------------------------------------------------- Davi


## day 4: the car, the horn, Clara opens the door, Davi comes in with the suitcase, the guest room
## (suitcase down, dust sheet off, the doll from Ivone's box), then the sofa
func _davi_day_steps() -> Array:
	var front: Door = house.doors["d_front"]
	var road := Vector3(6.45, 0.5, -14.0)
	return [
		{"t": "do", "fn": func():
			Sfx.car_arrive(road)
			_davi_moves_in()},
		{"t": "wait", "dur": 6.6},
		{"t": "do", "fn": func(): Sfx.horn(road + Vector3(0, 0, 6))},
		{"t": "say", "text": "É ele!", "dur": 1.6},
		{"t": "spot", "spot": Layout.spot("frontDoor")},
		# he walks up from the gate and knocks; she opens
		{"t": "until", "cond": func(): return aft.get("davi_knock", false), "timeout": 30.0},
		{"t": "wait", "dur": 0.5},
		{"t": "do", "fn": func():
			front.set_state("open")
			Sfx.creak(front.center() + Vector3(0, 1, 0), 0.5, 1.2)
			aft["davi_door"] = true},
		{"t": "walk", "node": "g_d_sala_h"},
		{"t": "look", "at": davi, "dur": 1.0},
		{"t": "until", "cond": func(): return aft.get("davi_in", false), "timeout": 14.0},
		{"t": "anim", "gesture": "wave", "wait": false},
		{"t": "do", "fn": func(): clara.model.set_mood("joy", 0.8, 3.0)},
		{"t": "until", "cond": func(): return aft.get("davi_greeted", false), "timeout": 14.0},
		{"t": "say", "text": "O quarto de hóspedes é lá em cima, o da direita.", "dur": 3.0},
		{"t": "do", "fn": func(): aft["go_up"] = true},
		{"t": "wait", "dur": 1.5},
		{"t": "walk", "node": "f_d_hosp_c", "end": Vector3(5.0, 3, 9.15)},
		{"t": "look", "at": Vector3(3.0, 4.0, 8.0), "dur": 1.0, "turn": true},
		{"t": "until", "cond": func(): return aft.get("doll_out", false), "timeout": 45.0},
		{"t": "wait", "dur": 0.6},
		{"t": "say", "text": "Guarda isso, Davi.", "dur": 2.0},
		{"t": "until", "cond": func(): return aft.get("doll_put", false), "timeout": 12.0},
		{"t": "say", "text": "...Eu já tinha escolhido o nome, sabia? Deixa pra lá.", "dur": 3.4},
		{"t": "wait", "dur": 0.8},
		{"t": "say", "text": "Obrigada por vir. A mãe que pediu, né?", "dur": 3.0},
		{"t": "do", "fn": func(): aft["talk1"] = true},
		{"t": "until", "cond": func(): return aft.get("davi_ghost", false), "timeout": 8.0},
		{"t": "wait", "dur": 0.8},
		{"t": "say", "text": "Se ouvir barulho de noite, é a casa velha. Né?", "dur": 3.2},
		{"t": "do", "fn": func(): aft["go_down"] = true},
		{"t": "wait", "dur": 2.0},
	]


## the road beyond the gate, where the car stops: Davi gets out there and walks up to the porch
# day 6: where Clara waits in the hall for Davi and the diary (off his way to the phone table)
const DIARY_WAIT := {"node": "g_hall_mid", "p": [5.95, 0.0, 2.2], "yaw": 2.75}
const DAVI_ROAD := [Vector3(6.45, -0.9, -13.0), Vector3(6.45, -0.9, -5.6), Vector3(6.45, -0.9, -2.7), Vector3(6.45, 0.0, -1.55), Vector3(6.45, 0.0, -0.75)]


func _davi_moves_in() -> void:
	var dv := davi
	var front: Door = house.doors["d_front"]
	dv.place({"node": "g_hall_front", "p": [DAVI_ROAD[0].x, DAVI_ROAD[0].y, DAVI_ROAD[0].z], "yaw": 0.0})
	dv.hide_model()
	dv.model.hold(_prop("suitcase"), "suitcase")
	var near_cat := func() -> bool: return cat.global_position.distance_to(dv.global_position) < 3.5 and absf(cat.global_position.y - dv.global_position.y) < 1.0
	dv.run("afternoon", [
		# the car parks out on the road; he gets out there, far beyond the gate
		{"t": "wait", "dur": 6.0},
		{"t": "do", "fn": func(): dv.show_model()},
		{"t": "walk", "points": DAVI_ROAD.slice(1)},
		{"t": "face", "yaw": 0.0},
		{"t": "do", "fn": func():
			Sfx.knock(front.center() + Vector3(0, 1.2, 0), 3, 0.8)
			aft["davi_knock"] = true},
		{"t": "until", "cond": func(): return aft.get("davi_door", false), "timeout": 20.0},
		{"t": "walk", "node": "g_hall_mid"},
		{"t": "do", "fn": func(): aft["davi_in"] = true},
		{"t": "say", "text": "Então é aqui a casa barata? Gostei, mana.", "dur": 3.2},
		{"t": "if", "cond": near_cat, "then": [
			{"t": "look", "at": "cat", "dur": 1.2},
			{"t": "say", "text": "{cat}! Saudade, seu peludo. Ainda sou alérgico, mas tudo bem.", "dur": 3.4},
			{"t": "do", "fn": func(): _sneeze(dv)},
			{"t": "wait", "dur": 1.4},
		]},
		{"t": "do", "fn": func(): aft["davi_greeted"] = true},
		{"t": "until", "cond": func(): return aft.get("go_up", false), "timeout": 20.0},
		{"t": "walk", "node": "f_hosp_door"},
		{"t": "walk", "node": "f_hosp_mid", "end": Vector3(3.95, 3, 8.55)},
		{"t": "face", "yaw": PI / 2},
		{"t": "pose", "pose": "kneel", "dur": 0.7},
		{"t": "do", "fn": func():
			var s := dv.model.drop_held("hand")
			if s:
				s.queue_free()
			house.set_guest_parts(true, true)
			Sfx.thud(Vector3(4.35, 3.1, 8.7), 0.35, 110)},
		{"t": "pose", "pose": "stand", "dur": 0.5},
		{"t": "walk", "node": "f_hosp_bed", "end": Vector3(2.35, 3, 8.3)},
		{"t": "face", "yaw": -PI / 2},
		{"t": "anim", "gesture": "pull", "wait": false},
		{"t": "wait", "dur": 0.75},
		{"t": "do", "fn": func():
			house.set_guest_parts(true, false)
			Sfx.puff(Vector3(1.1, 3.6, 8.3))
			burst_smoke(Vector3(1.2, 3.65, 8.3), Color(0.78, 0.72, 0.64, 0.45))},
		{"t": "wait", "dur": 1.0},
		{"t": "do", "fn": func(): _sneeze(dv)},
		{"t": "wait", "dur": 1.2},
		{"t": "say", "text": "Quarto de hóspedes... cheio de caixa. Perfeito.", "dur": 3.0},
		{"t": "walk", "node": "f_hosp_mid", "end": Vector3(4.0, 3, 7.75)},
		{"t": "face", "yaw": atan2(4.4 - 4.0, 7.2 - 7.75)},
		{"t": "look", "at": Vector3(4.4, 3.3, 7.2), "dur": 0.8},
		{"t": "say", "text": "Ué... esse baú não é nosso.", "dur": 2.2},
		{"t": "pose", "pose": "kneel", "dur": 0.4},
		# Ivone's chest: the lid creaks open, the doll comes up out of it, the lid falls shut
		{"t": "do", "fn": func(): _ivone_box_lid(true)},
		{"t": "anim", "clip": "chest_open"},
		{"t": "do", "fn": func():
			dv.model.hold(_prop("doll"), "doll")
			Sfx.porcelain(Vector3(4.3, 3.4, 7.3))},
		{"t": "pose", "pose": "stand", "dur": 0.7},
		{"t": "do", "fn": func(): _ivone_box_lid(false)},
		{"t": "look", "at": Vector3(4.0, 4.3, 8.0), "dur": 0.4},
		{"t": "say", "text": "Olha o que tinha aqui!", "dur": 2.4},
		{"t": "do", "fn": func(): aft["doll_out"] = true},
		{"t": "wait", "dur": 3.0},
		{"t": "walk", "node": "f_hosp_mid", "end": Vector3(3.4, 3, 6.6)},
		{"t": "face", "yaw": PI},
		{"t": "anim", "gesture": "switch", "wait": false},
		{"t": "wait", "dur": 0.45},
		{"t": "do", "fn": func():
			var dl := dv.model.drop_held("hand")
			if dl:
				dv.model.remove_child(dl)
				add_child(dl)
				# standing on the dresser top, feet on the wood
				dl.global_transform = Transform3D(Basis(Vector3.UP, 0.3).scaled(dl.scale), Vector3(3.4, 4.0, 5.85))
				var ab := _node_aabb(dl)
				dl.global_position.y += _dresser_top() - ab.position.y
				aft["doll_prop"] = dl
			Sfx.porcelain(Vector3(3.4, 4.0, 5.85))
			aft["doll_put"] = true},
		{"t": "until", "cond": func(): return aft.get("talk1", false), "timeout": 10.0},
		{"t": "wait", "dur": 0.5},
		{"t": "say", "text": "Que mãe? Eu vim porque quis. ...E porque ela pediu.", "dur": 3.4},
		{"t": "do", "fn": func(): aft["davi_ghost"] = true},
		{"t": "until", "cond": func(): return aft.get("go_down", false), "timeout": 10.0},
	] + _davi_settle(Config.DAVI_DAY), 1)


## the top of the guest-room dresser (where the doll stands)
func _dresser_top() -> float:
	var d := house.find("DRESSER_hosp")
	return _node_aabb(d).end.y if d else 3.96


## Ivone's chest in the guest room: the lid swings up on its back edge
func _ivone_box_lid(open: bool) -> void:
	var box := house.find("IVONE_BOX")
	if box == null:
		return
	var lid := box.find_child("treasure_chest_lid*", true, false) as Node3D
	if lid == null:
		return
	if not lid.has_meta("rest"):
		lid.set_meta("rest", lid.transform)
	var rest: Transform3D = lid.get_meta("rest")
	var hinge := Vector3(0, 0, -0.27)
	var tw := create_tween()
	tw.tween_method(func(a: float):
		lid.transform = Transform3D(Basis.IDENTITY, rest.origin + hinge) * Transform3D(Basis(Vector3.RIGHT, -a), Vector3.ZERO) * Transform3D(rest.basis, -hinge),
		0.0 if open else 1.75, 1.75 if open else 0.0, 0.7 if open else 0.35)
	Sfx.creak(box.global_position + Vector3(0, 0.3, 0), 0.4, 1.3 if open else 0.6)
	if not open:
		_later(0.35, func(): Sfx.thud(box.global_position + Vector3(0, 0.3, 0), 0.3, 140))


## days 5-7: the car ~10 s after Clara, a line of the day, the keys on the hall table, then the sofa
func _davi_arrives(d: int) -> void:
	var dv := davi
	var front: Door = house.doors["d_front"]
	Sfx.car_arrive(Vector3(6.45, 0.5, -14.0))
	var lines := {5: "Cheguei! Trouxe pão de queijo. Quem tava no telefone?", 6: "Mana, olha isso. Tava no fundo daquele baú. É o diário da antiga dona.", 7: "Cheguei. Último dia dessa semana maluca."}
	_later(1.5, func():
		if phase != "afternoon":
			return
		# out of the car on the road, up through the gate; he has a key now
		dv.show_model()
		dv.place({"node": "g_hall_front", "p": [DAVI_ROAD[0].x, DAVI_ROAD[0].y, DAVI_ROAD[0].z], "yaw": 0.0})
		var steps: Array = [
			{"t": "walk", "points": DAVI_ROAD.slice(1)},
			{"t": "do", "fn": func():
				Sfx.keys(front.center() + Vector3(0, 1.0, 0))
				front.set_state("open")
				Sfx.creak(front.center() + Vector3(0, 1, 0), 0.5, 1.2)},
			{"t": "walk", "node": "g_hall_front"},
			{"t": "do", "fn": func(): front.set_state("closed")},
		]
		if d == 6:
			# Davi no longer holds the diary (the book in his hands kept bugging): he only tells her about it,
			# and she has it by the time she opens it
			steps.append_array([
				{"t": "walk", "points": [Vector3(6.4, 0.0, 1.45)]},
				{"t": "until", "cond": func(): return aft.get("diary_wait", false), "timeout": 15.0},
				{"t": "look", "at": clara, "dur": 0.8, "turn": true},
				{"t": "say", "text": lines[6], "dur": 3.0},
				{"t": "wait", "dur": 1.6},
				{"t": "do", "fn": func(): aft["diary_given"] = true},
				{"t": "wait", "dur": 0.6},
			])
		else:
			steps.append_array([{"t": "walk", "node": "g_hall_mid"}, {"t": "say", "text": lines.get(d, "Cheguei!"), "dur": 3.0}])
		steps.append_array([
			{"t": "spot", "spot": Layout.spot("hallPhone")},
			{"t": "anim", "clip": "interact", "wait": false},
			{"t": "wait", "dur": 0.5},
			{"t": "do", "fn": func(): Sfx.keys(Vector3(7.2, 0.8, 2.95))},
			{"t": "wait", "dur": 0.8},
		])
		dv.run("afternoon", steps + _davi_settle(d), 1))


## Davi's evening: the sofa, the phone and the glasses; on day 7 the talk with Clara
func _davi_settle(d: int) -> Array:
	var dv := davi
	var steps: Array = [{"t": "spot", "spot": Layout.spot("sofaR")}, {"t": "pose", "pose": "sit", "dur": 1.5}, {"t": "do", "fn": func(): aft["davi_seated"] = true}]
	if d == Config.LAST_NIGHT:
		steps.append_array([
			{"t": "until", "cond": func(): return aft.get("eve_heard", false), "pose": "sit", "timeout": 40.0},
			{"t": "say", "text": "Cano velho.", "dur": 2.0},
			{"t": "anim", "gesture": "glasses"},
			{"t": "until", "cond": func(): return aft.get("eve_confess", false), "pose": "sit", "timeout": 30.0},
			{"t": "wait", "dur": 1.2},
			{"t": "say", "text": "Eu sei, mana. Eu tô aqui.", "dur": 2.6},
		])
	if d == 6:
		steps.append_array([
			{"t": "until", "cond": func(): return aft.get("diary_read", false), "pose": "sit", "timeout": 90.0},
			{"t": "wait", "dur": 0.8},
			{"t": "say", "text": "Por isso eu vim, sabia?", "dur": 2.4},
		])
	# reading only with the diary in his hands (day 6); otherwise sat back on the sofa
	steps.append({"t": "until", "cond": func(): return aft["ending"], "pose": "read" if d == 6 else "sit"})
	return steps


func _sneeze(who: Owner) -> void:
	who.model.gesture("sneeze")
	_later(0.4, func(): Sfx.sneeze(who.head_pos()))


func _basement_tremor() -> void:
	var p := Vector3(4.0, -2.0, 5.0)
	Sfx.thud(p, 1.0, 45)
	_later(0.25, func(): Sfx.thud(p, 0.8, 55))
	var rb = Sfx.loop("rumble", p, 3.0)
	rb.set_level(0.8)
	_later(1.6, func(): rb.stop(0.8))
	shake(0.25)
	for l: LightSystem.RoomLight in house.lights.lights:
		if l.on:
			l.flicker = 0.7
	_later(1.2, func():
		for l: LightSystem.RoomLight in house.lights.lights:
			l.flicker = 0.0)
	for o: Owner in [clara, davi]:
		if o.present and o.visible:
			o.look_for(p, 2.0)


## per frame in the afternoon: the TV, the lap, Clara crouching to talk when the cat comes close,
## Davi's allergy
## the lights of a room stutter while a ghost is in it or close by (a warning, before you see it)
func _ghost_presence() -> void:
	var near := {}
	if phase == "night" and director:
		for th: Threat in director.all:
			if not th.enabled or th.stage < 2:
				continue
			var f = th.focus()
			if f == null:
				continue
			var rm := Layout.room_at(f)
			if rm != "":
				near[rm] = maxf(float(near.get(rm, 0.0)), 0.18 + th.stage * 0.07)
	var dt := get_process_delta_time()
	for l: LightSystem.RoomLight in house.lights.lights:
		var want: float = near.get(l.room(), 0.0)
		l.presence = move_toward(l.presence, want, dt * (0.6 if want > l.presence else 0.3))


## the afternoon's small talk: Clara (and Davi) talk to the cat when it hangs around them, and from
## day 4 the two of them talk when they are together and the cat is close (Story.CHATTER / TALKS)
func _tick_chatter(dt: float) -> void:
	aft["chat_t"] = float(aft.get("chat_t", 8.0)) - dt
	if aft["chat_t"] > 0.0 or aft.get("ending", false) or aft.get("private", "") != "":
		return
	aft["chat_t"] = randf_range(9.0, 15.0)
	var cp := cat.global_position
	var talks: Array = Story.TALKS.get(day, [])
	var ti := int(aft.get("talk_i", 0))
	if ti < talks.size() and davi.present and davi.visible and clara.visible and not clara.in_bed:
		if clara.global_position.distance_to(davi.global_position) < 4.5 and cp.distance_to(clara.global_position) < 6.0 and clara.interruptible() and davi.interruptible():
			aft["talk_i"] = ti + 1
			var at := 0.0
			for ln in talks[ti]:
				var who: Owner = clara if ln[0] == "clara" else davi
				var tx: String = ln[1]
				_later(at, func():
					if phase == "afternoon" and who.visible:
						who.say(tx, 2.4 + tx.length() * 0.035))
				at += 2.8 + tx.length() * 0.04
			aft["chat_t"] = at + 8.0
			return
	var lines: Dictionary = Story.CHATTER.get(day, {})
	for who: Owner in [clara, davi]:
		var key := "clara" if who == clara else "davi"
		var pool: Array = lines.get(key, [])
		var i := int(aft.get("chat_" + key, 0))
		if i >= pool.size() or not who.present or not who.visible or who.in_bed or not who.interruptible():
			continue
		if cp.distance_to(who.global_position) < 4.0 and absf(cp.y - who.global_position.y) < 1.5:
			aft["chat_" + key] = i + 1
			who.say(pool[i], 3.2)
			return


func _afternoon_people(dt: float) -> void:
	_tv_update(dt)
	_tick_chatter(dt)
	if aft.get("lap", false):
		var c := cat
		clara.model.hand_target = c.global_position + Vector3(0, 0.16, 0) + Vector3(sin(phase_t * 2.2), 0, cos(phase_t * 2.2)) * 0.05
		if Controls.move_vector().length() > 0.5 or Input.is_action_just_pressed("jump") or clara.model.pose != "sit":
			aft["lap"] = false
			_leave_lap()
	elif aft.get("lap_open", false) and cat.mode == "free" and cat.arc == null and lap_point() != null:
		var lp: Vector3 = lap_point()
		if cat.global_position.distance_to(lp) < 0.3:
			_enter_lap()
	aft["kneel_cd"] -= dt
	aft["sneeze_cd"] -= dt
	var cp := cat.global_position
	var o := clara
	if aft["kneel_cd"] <= 0 and o.visible and o.task != null and o.model.pose == "stand" and o.model.holding() == "" and cp.distance_to(o.global_position) < 1.1 and absf(cp.y - o.global_position.y) < 0.3:
		var st: Dictionary = o.task["steps"][o.task["idx"]]
		if str(st["t"]) in ["wait", "until"] and not st.has("pose"):
			aft["kneel_cd"] = 28.0
			var lines := ["Oi, {cat}! Tá me seguindo, é?", "Que foi, {cat}? Quer atenção?", "Você é o melhor gato do mundo, sabia?", "Ei, coisinha. Tô aqui."]
			o.task["steps"].insert(o.task["idx"], {"t": "kneel_talk", "text": lines[randi() % lines.size()], "dur": 2.4})
			o.task["timer"] = 0.0
			o.task["started"] = false
	# day 1: kneeling by the bowl she calls the cat; down in the basement she asks for the key
	var lines1: Dictionary = Story.AFTERNOON_LINES[1]
	if aft["wait_eat"] and not aft["fed"]:
		aft["call_t"] -= dt
		if aft["call_t"] <= 0:
			aft["call_t"] = 12.0
			if cp.distance_to(o.global_position) > 1.6:
				o.say(lines1["call"][randi() % lines1["call"].size()], 2.4, "call")
	if aft["wait_key"] and not aft["key_given"]:
		aft["key_call_t"] -= dt
		if aft["key_call_t"] <= 0:
			aft["key_call_t"] = 15.0
			if cp.distance_to(o.global_position) > 2.0:
				o.say(lines1["key_wait"][randi() % lines1["key_wait"].size()], 2.6, "call")
	# in bed waiting for the cat: how the day ends
	if o.in_bed and aft["can_skip"] and not aft["bed_hinted"]:
		aft["bed_hinted"] = true
		hint_once("aft_bed", tr("Clara foi deitar. Suba na cama e [b]deite com ela[/b] (%s): a noite começa quando você ronronar com ela.") % ui.kbd("interact"), 9)
	var dv := davi
	if dv.present and dv.visible and not dv.model.pose in ["sit", "read"] and aft["sneeze_cd"] <= 0 and cp.distance_to(dv.global_position) < 1.1 and absf(cp.y - dv.global_position.y) < 0.6:
		aft["sneeze_cd"] = 16.0
		_sneeze(dv)
		if randf() < 0.4:
			_later(1.3, func(): dv.say("...{cat}, sai daqui. Por favor.", 2.4, "annoyed"))
	# sitting quiet by her while she is idle or seated: now and then the slow blink of a cat that trusts her
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _blink_next and cat.mode == "free" and cat.idle_secs() > 3.0 and cat.carrying == null and o.visible and not o.in_bed \
			and o.interruptible() and aft.get("private", "") == "":
		var to := o.global_position - cp
		if Vector2(to.x, to.z).length() <= 2.5 and absf(to.y) < 1.2:
			o.head_mark.global_position = o.head_pos()
			if cat.slow_blink(o.head_mark):
				_blink_next = now + randf_range(25.0, 35.0)


func pet_owner() -> void:
	var o := clara
	aft["pets"] += 1
	aft["pet_cd"] = 6.0
	o.add_patience(12)
	Sfx.meow(cat.head(), 1.15)
	var lines := ["Quem é o gato mais lindo dessa casa?", "Ownn, vem cá, {cat}.", "Que carente você tá hoje!"]
	# her line gets the slow blink, not the head tilt
	_tilt_next = maxf(_tilt_next, Time.get_ticks_msec() / 1000.0 + 4.0)
	o.say(lines[randi() % lines.size()], 2.6)
	o.paused = true
	var seated := o.model.pose in ["sit", "read"]
	if not seated:
		o.model.pose = "pet"
	o.model.hand_target = cat.global_position + Vector3(0, 0.18, 0)
	o.model.set_mood("joy", 0.9, 2.6)
	_start_purr(0.6)
	_later(0.6, func():
		o.head_mark.global_position = o.head_pos()
		cat.slow_blink(o.head_mark))
	_later(2.6, func():
		o.paused = false
		o.model.hand_target = null
		if not seated:
			o.model.pose = "stand"
		_stop_purr())


func play_with_owner() -> void:
	var o := clara
	aft["played"] = true
	var toy: PropSystem.Carryable = cat.carrying
	drop_carried()
	toss_toy(toy)
	o.add_patience(10)
	o.say("Pega! Pega o ratinho! Hahaha.", 2.6)
	o.paused = true
	o.model.pose = "pet"
	_later(2.4, func():
		o.paused = false
		o.model.pose = "stand")


## the cat eats: it faces the bowl and chews for EAT_SECS (cat.eating drives the head-down pose of the
## rig); walking or jumping away stops it. The food counts at once.
func eat() -> void:
	aft["fed"] = true
	clara.add_patience(8)
	_eat_t = EAT_SECS
	_chew_t = 0.25
	cat.eating = 1.0
	Sfx.paw_step(cat.global_position, false, false)
	refresh_afternoon_tasks()


func is_eating() -> bool:
	return _eat_t > 0.0


func _tick_eat(dt: float) -> void:
	if _eat_t <= 0.0:
		return
	_eat_t -= dt
	var moved := Controls.move_vector().length() > 0.3 or Input.is_action_just_pressed("jump") or cat.mode != "free" or not controls or cat.arc != null
	if moved or _eat_t <= 0.0:
		_stop_eating()
		return
	var cp := cat.global_position
	cat.yaw = lerp_angle(cat.yaw, atan2(BOWL_POS.x - cp.x, BOWL_POS.z - cp.z), 1.0 - exp(-8.0 * dt))
	# a boca fica ~0,22 m à frente da origem do gato: encosta na tigela por física, sem atravessar
	var flat := Vector3(BOWL_POS.x - cp.x, 0.0, BOWL_POS.z - cp.z)
	if flat.length() > 0.05:
		var want := flat - flat.normalized() * 0.22
		cat.move_and_collide(want * minf(1.0, 4.0 * dt))
	cat.eating = 1.0
	# the heap goes down in three bites
	_food_left = [1.0, 0.66, 0.33, 0.08][clampi(int((1.0 - _eat_t / EAT_SECS) * 4.0), 0, 3)]
	house.set_food(_food_left)
	_chew_t -= dt
	if _chew_t <= 0.0:
		_chew_t = randf_range(0.28, 0.42)
		Sfx.chew(BOWL_POS + Vector3(0, 0.08, 0))


var _food_left := 1.0


func _stop_eating() -> void:
	var was := _eat_t > 0.0
	_eat_t = 0.0
	if cat:
		cat.eating = 0.0
	if was:
		# what is left: the heap goes down in bites; a full meal leaves a few crumbs
		house.set_food(maxf(0.08, _food_left))


func _end_afternoon() -> void:
	if aft.get("ending", false):
		return
	aft["ending"] = true
	_tv_show(false)
	controls = false
	fx["fade_target"] = 1.0
	fx["fade_speed"] = 0.8
	_later(1.5, func():
		var start_fear := 20.0 if day == 3 and not flags["bath_scene_done"] else 0.0
		var snap := {"day": day, "phase": "night", "flags": flags.duplicate(true), "patience": clampf(clara.patience, 30, 100), "start_fear": start_fear}
		start_night(day, snap))


func skip_phase() -> void:
	if _transitioning:
		return
	if phase == "morning":
		_transitioning = true
		controls = false
		fx["fade_target"] = 1.0
		fx["fade_speed"] = 0.9
		_later(1.4, func():
			_transitioning = false
			start_afternoon())
	elif phase == "afternoon":
		house.lights.set_all(false)
		clara.say("Já tá com sono, {cat}? Então vamos dormir.", 2.6)
		_end_afternoon()


# ====================================================================== purr


func nearest_bed_owner() -> Owner:
	var bst := clara
	var bd := INF
	var cp := cat.global_position
	for m: Owner in household_present():
		var p := Layout.spot_pos(m.cfg["bed_spot"])
		var d := Vector2(p.x - cp.x, p.z - cp.z).length() + absf(p.y - cp.y) * 3.0
		if d < bd:
			bd = d
			bst = m
	return bst


func toggle_purr(who: Owner = null) -> void:
	var c := cat
	if c.mode == "purr":
		var prev := _purr_who if _purr_who else clara
		c.mode = "free"
		c.teleport(Layout.spot_pos(prev.cfg["bedside_spot"]), PI / 2)
		prev.purring = false
		_purr_who = null
		_stop_purr()
		return
	var o := who if who else nearest_bed_owner()
	if o.paralysis:
		o.paralysis = false
		o.add_patience(-6)
		o.add_fear(-12)
		o.say("Ah! {cat}... eu não conseguia me mexer...", 3.0, "scared")
		cat_hop()
		return
	c.mode = "purr"
	c.mode_target = o.cfg["purr_pos"]
	c.mode_yaw = o.cfg["purr_yaw"]
	o.purring = true
	o.asleep = false
	_purr_who = o
	_start_purr(1.0)
	if phase == "afternoon":
		# the end of the day: a word, and the night after AFT_PURR_SECS
		aft["purr_t"] = 0.0
		o.say("Boa noite, {cat}...", 2.4, "whisper")
		return
	if o.fear < 30:
		o.add_patience(-1)
	hint_once("purrout", tr("Ronronar acalma %s, mas você não está patrulhando. %s para levantar.") % [o.display_name, ui.kbd("interact")])


func _start_purr(level: float) -> void:
	if _purr_loop == null:
		_purr_loop = Sfx.purr()
	_purr_loop.set_level(level)


func _stop_purr() -> void:
	if _purr_loop:
		_purr_loop.set_level(0.0)


# ====================================================================== helpers


func cat_hop() -> void:
	var r := cat.rig
	var tw := r.create_tween()
	tw.tween_property(r, "position:y", 0.06, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "position:y", 0.0, 0.12).set_ease(Tween.EASE_IN)
	Sfx.paw_step(cat.global_position, false, false)


## "Derrubar": the paw goes to the prop and the push lands only when it touches it
func cat_swat(p: PropSystem.Prop) -> void:
	if p == null:
		return
	cat.swat_at(p.body, func():
		if p.broken:
			return
		Sfx.paw_step(p.body.global_position, false, true)
		house.props.knock(p, cat.global_position, cat.forward))


## a switch, a plug, a lamp: the paw goes to it and `fx` happens on the touch (at once if the cat
## can't act right now, so the interaction never gets lost)
func cat_reach(at: Vector3, fx: Callable) -> void:
	if not cat.swat_at(at, fx):
		fx.call()


## play: Clara flicks a toy the cat just brought her (it lies at its feet) a short way off over clear
## floor, rolling, and the cat pounces on it; the pounce nudges it on a little
func toss_toy(c: PropSystem.Carryable) -> void:
	if c == null or c.carried:
		return
	var to := _toy_spot(cat.global_position, c.pos)
	if to == Vector3.INF:
		play_toy(c)
		return
	var from := c.pos
	var r := 0.05 if c.id == "yarn" else 0.03
	var tw := c.node.create_tween()
	tw.tween_interval(0.35)
	tw.tween_method(func(s: float):
		if c.carried:
			tw.kill()
			return
		# a low arc, one small bounce, then it rolls the rest of the way
		var k := 0.82 * s / 0.6
		var h := 0.18 * 4.0 * (s / 0.6) * (1.0 - s / 0.6)
		if s >= 0.6:
			var u := (s - 0.6) / 0.4
			k = lerpf(0.82, 1.0, 1.0 - pow(1.0 - u, 2.0))
			h = 0.035 * 4.0 * (u * 2.0) * (1.0 - u * 2.0) if u < 0.5 else 0.0
		_roll_toy(c, from, to, k, r, h), 0.0, 1.0, 0.6)
	# it stops where the cat can see it: then the wiggle and the leap
	tw.tween_callback(func():
		if not c.carried:
			play_toy(c, false))


## "Brincar": the wiggle and the pounce, and the toy ends in the cat's mouth (picked up at once when the
## cat can't leap now; after Clara's throw, `fallback` false leaves it on the floor instead)
func play_toy(c: PropSystem.Carryable, fallback := true) -> void:
	var take := func():
		if not c.carried and cat.carrying == null and c.node.visible:
			Sfx.paw_step(c.pos, false, true)
			inter.pick(self, c.id)
	if not cat.pounce_at(c.node, take) and fallback:
		take.call()


## Clara's throw lands here: 0.6–1.0 m from the cat, off to a side or behind it (never at her), on the
## cat's floor and with nothing in the way
func _toy_spot(cp: Vector3, from: Vector3) -> Vector3:
	var sgn := 1.0 if randf() < 0.5 else -1.0
	for off in [0.8, 1.2, 1.7, 2.3, PI]:
		for s in [sgn, -sgn]:
			for dist in [randf_range(0.8, 1.0), 0.6]:
				var a: float = cat.yaw + off * s
				var q: Vector3 = cp + Vector3(sin(a), 0, cos(a)) * float(dist)
				q.y = house.ground_height(q.x, q.z, cp.y + 0.3)
				if absf(q.y - cp.y) > 0.06:
					continue
				if Vector2(q.x - clara.global_position.x, q.z - clara.global_position.z).length() < 0.7:
					continue
				var lift := Vector3(0, 0.12, 0)
				if not house.clear_path(from + lift, q + lift, 0.06) or not house.clear_path(cp + lift, q + lift, 0.1):
					continue
				return q
	return Vector3.INF


## places a toy k of the way from a to b, h above the floor, turned along the way and rolled by the distance
func _roll_toy(c: PropSystem.Carryable, a: Vector3, b: Vector3, k: float, r: float, h := 0.0) -> void:
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var yw := atan2(d.x, d.z) if d.length() > 0.01 else c.yaw
	c.place(a.lerp(b, k) + Vector3(0, h, 0), yw)
	# the yarn ball turns over as it goes; the mouse only slides and wobbles
	if c.id == "yarn":
		c.node.rotate_object_local(Vector3.RIGHT, d.length() * k / r)
	else:
		c.node.rotate_object_local(Vector3.FORWARD, sin(k * 18.0) * 0.25 * (1.0 - k))


func emit_noise(p: Vector3, loud: float, kind: String) -> void:
	if phase != "night" and phase != "afternoon":
		return
	if director:
		director.hear_noise(p, loud, kind)
	for who: Owner in household_present():
		who.hear_noise(p, loud, hops(p, who.global_position), kind)


func on_light_toggled(index: int, on: bool) -> void:
	if phase != "night":
		return
	# lighting a bedroom while its sleeper is in bed annoys them (unless they are scared)
	var who: Owner = clara if index == 7 or index == 8 else (davi if index == 9 or index == 17 else null)
	if who == null or not who.present:
		return
	if on and who.in_bed and who.fear < 45:
		who.add_patience(-4)
		if who.asleep:
			who.say("Hmm... apaga isso, {cat}...", 2.4, "annoyed")
	if on and who.fear >= 45:
		who.add_fear(-6)


## the pantry cat flap swings when the cat goes through
func swing_flap() -> void:
	Sfx.click(Vector3(10.78, 0.2, 12.9), 0.35)
	for nm in ["CAT_FLAP", "CAT_FLAP_out"]:
		var f = house.find_child(nm, true, false)
		if f is Node3D:
			var n := f as Node3D
			var tw := create_tween()
			tw.tween_property(n, "rotation:x", -1.1, 0.12)
			tw.tween_property(n, "rotation:x", 0.35, 0.25)
			tw.tween_property(n, "rotation:x", 0.0, 0.35)


func passage(to: Vector3, yaw: float, kind: String) -> void:
	controls = false
	fx["fade_target"] = 1.0
	fx["fade_speed"] = 3.5
	director.hound.cat_vanished()
	if kind == "duct":
		Sfx.crawl(0.5)
	else:
		Sfx.paw_step(cat.global_position, true, false)
	_later(1.1 if kind == "duct" else (0.3 if kind == "flap" else 0.45), func():
		cat.teleport(to, yaw)
		rig.snap(to + Vector3(0, 0.32, 0), yaw)
		fx["fade_target"] = 0.0
		controls = not _failing and not _winning)


# ---------------------------------------------------------------------- the night mission


## hides tonight's objects of Ivone around the house, far from each other and from the circle
func _setup_relics(d: int) -> void:
	relics = []
	relics_done = 0
	for i in House.RELIC_SLOTS:
		var c: PropSystem.Carryable = house.carryables["relic_%d" % i]
		c.enabled = false
		c.carried = false
		c.node.visible = false
		c.place(Vector3(0, -50, 0))
	var defs: Array = Story.RELICS.get(d, [])
	_mission = []
	if defs.is_empty():
		ui.tasks(null, [])
		refresh_night_tasks()
		return
	var spots := _relic_spots(defs.size())
	for i in mini(defs.size(), spots.size()):
		var c: PropSystem.Carryable = house.carryables["relic_%d" % i]
		for ch in c.node.get_children():
			ch.queue_free()
		c.node.add_child(Carry.make_relic(defs[i]["kind"]))
		c.node.set_meta("grip", defs[i]["kind"])
		var aura := FX.wisps(Color(0.95, 0.85, 0.55, 0.5), 0.35, 0.12, 16, true, 0.1)
		c.node.add_child(aura)
		c.name = defs[i]["name"]
		c.enabled = true
		c.node.visible = true
		c.place(spots[i], randf() * TAU)
		var r := {"c": c, "text": defs[i]["text"], "done": false, "aura": aura, "rule": str(defs[i].get("rule", "")), "found": true, "order": i}
		relics.append(r)
		_apply_relic_rule(r)
	_capture_mission()
	refresh_night_tasks()


## tonight's mission as the Director reads it: every thing the cat has to take to the circle (Ivone's
## things, and on the last night the photo, the collar and the key as well) with where it started
var _mission: Array = []   # [{c: Carryable, home: Vector3, id: String ("" for a relic), r: Dictionary or null, taken: bool}]


func _capture_mission() -> void:
	_mission = []
	for r in relics:
		var c: PropSystem.Carryable = r["c"]
		_mission.append({"c": c, "home": c.pos, "id": "", "r": r, "taken": false})
	if day != Config.LAST_NIGHT:
		return
	for id in CLUES:
		var cc: PropSystem.Carryable = house.carryables[id]
		var old := cc.node.get_node_or_null("ClueAura")
		if old:
			old.free()
		var aura := FX.wisps(Color(0.95, 0.85, 0.55, 0.5), 0.35, 0.12, 16, true, 0.1)
		aura.name = "ClueAura"
		cc.node.add_child(aura)
		_mission.append({"c": cc, "home": cc.pos, "id": id, "r": null, "taken": false, "aura": aura})


## 0 = still where it was, 0.35 = taken from its place, 0.8 = left by the circle, 1 = delivered. Taken
## never goes back to 0, so stacking things by the circle (or dropping them anywhere) buys no calm.
func _mission_weight(m: Dictionary) -> float:
	var c: PropSystem.Carryable = m["c"]
	var done: bool = m["r"]["done"] if m["r"] != null else ritual_placed(m["id"])
	if done:
		m["taken"] = true
		return 1.0
	if c.carried or c.pos.distance_to(m["home"]) > 0.6:
		m["taken"] = true
	if not m["taken"]:
		return 0.0
	if not c.carried:
		var rc := house.ritual_center
		if Vector2(c.pos.x - rc.x, c.pos.z - rc.z).length() < 4.0 and absf(c.pos.y - rc.y) < 2.0:
			return 0.8
	return 0.35


## P: the mean of the weights (0 outside a night with a mission); the Director reads it every frame
func mission_progress() -> float:
	if _mission.is_empty() or phase != "night":
		return 0.0
	var s := 0.0
	for m: Dictionary in _mission:
		s += _mission_weight(m)
	return s / _mission.size()


## how many of the things were taken from their place (or delivered) at some point
func mission_taken() -> int:
	var n := 0
	for m: Dictionary in _mission:
		_mission_weight(m)
		if m["taken"]:
			n += 1
	return n


## the Thing stirs when half of the mission has been moved (and at 3 a.m. at the latest)
func thing_should_wake() -> bool:
	if hour >= 3.0:
		return true
	return not _mission.is_empty() and mission_taken() >= ceili(_mission.size() / 2.0)


## the mailbox by the gate (night 5: a letter that never came into the house)
const MAILBOX_POS := Vector3(7.75, -0.9, -5.25)
var _mailbox: Node3D


func _apply_relic_rule(r: Dictionary) -> void:
	var c: PropSystem.Carryable = r["c"]
	match r["rule"]:
		"wash":
			r["dirty"] = true
			_relic_mud(c, true)
		"drain":
			# down the drain of the downstairs basin: fished out with a paw
			r["found"] = false
			c.enabled = false
			c.node.visible = false
			for f: House.Faucet in house.faucets:
				if f.id == "banb":
					c.place(f.basin_c + Vector3(0, 0.02, 0))
					r["at"] = f.basin_c
		"dark":
			r["room"] = Layout.room_at(c.pos)
		"mailbox":
			r["found"] = false
			c.enabled = false
			c.node.visible = false
			c.place(MAILBOX_POS + Vector3(0, 1.0, 0))
			r["at"] = MAILBOX_POS
			_build_mailbox()


func _build_mailbox() -> void:
	if _mailbox:
		return
	_mailbox = Node3D.new()
	add_child(_mailbox)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.26, 0.18)
	wood.roughness = 0.9
	var tin := StandardMaterial3D.new()
	tin.albedo_color = Color(0.32, 0.38, 0.36)
	tin.roughness = 0.6
	tin.metallic = 0.5
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.08, 1.0, 0.08)
	post.mesh = pm
	post.material_override = wood
	post.position = Vector3(0, 0.5, 0)
	_mailbox.add_child(post)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.2, 0.38)
	box.mesh = bm
	box.material_override = tin
	box.position = Vector3(0, 1.08, 0)
	_mailbox.add_child(box)
	_mailbox.global_position = MAILBOX_POS


## mud over an object (night 2): darker and brown until it is washed under a tap
func _relic_mud(c: PropSystem.Carryable, on: bool) -> void:
	for mi in c.node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if on:
			var base := m.material_override if m.material_override else (m.mesh.surface_get_material(0) if m.mesh and m.mesh.get_surface_count() > 0 else null)
			m.set_meta("clean_mat", m.material_override)
			if base is StandardMaterial3D:
				var mud := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				mud.albedo_color = mud.albedo_color.lerp(Color(0.24, 0.17, 0.1), 0.75)
				mud.roughness = 1.0
				m.material_override = mud
		elif m.has_meta("clean_mat"):
			m.material_override = m.get_meta("clean_mat")


func relic_of(c) -> Dictionary:
	for r in relics:
		if r["c"] == c:
			return r
	return {}


func carrying_dirty() -> bool:
	return relic_of(cat.carrying).get("dirty", false)


## washed under the tap (held): the mud comes off
func wash_carried(f: House.Faucet) -> void:
	var r := relic_of(cat.carrying)
	if r.is_empty():
		return
	r["dirty"] = false
	_relic_mud(r["c"], false)
	Sfx.drip(f.spout)
	# a short run of the tap: the water loop through Sfx.play never stops (the loop_ streams loop),
	# so it gets its own handle, and the stream shows while it runs (unless the Drowner opened it)
	var snd := Sfx.loop("water", f.spout, 1.2)
	snd.set_level(0.4)
	var ours := f.running <= 0.04
	if ours:
		f.running = 0.5
	# a plain timer, not _later: the sound must stop even if the night ends meanwhile
	get_tree().create_timer(1.8).timeout.connect(func():
		snd.stop(0.4)
		if ours and is_equal_approx(f.running, 0.5):
			f.running = 0.0)
	hint("Limpa. Agora pode ir para o círculo.", 3.0)
	refresh_night_tasks()


## a hidden relic still waiting at this place (the drain, the mailbox)
func hidden_relic_at(p: Vector3, reach: float):
	for r in relics:
		if not r["found"] and not r["done"] and r.has("at") and (r["at"] as Vector3).distance_to(p) < reach:
			return r
	return null


func take_hidden_relic(r: Dictionary) -> void:
	var c: PropSystem.Carryable = r["c"]
	r["found"] = true
	c.enabled = true
	c.node.visible = true
	c.carried = true
	cat.carrying = c
	Sfx.porcelain(cat.global_position + Vector3(0, 0.3, 0))
	if r["rule"] == "drain":
		Sfx.drip(cat.global_position + Vector3(0, 0.4, 0))
	emit_noise(cat.global_position, 0.6, "thud")
	refresh_night_tasks()


## candidate spots: walkable nav nodes (not ghost-only), away from the circle, the cat's bed room and
## each other; the attic only once the hatch is open
func _relic_spots(n: int) -> Array:
	var nav := house.nav
	var cands := []
	var start_room := Layout.room_at(Layout.v3(Layout.data()["CAT_START"]))
	for node: NavGraph.NavNode in nav.nodes.values():
		var walk := false
		for l in node.links:
			if not l["ghost"]:
				walk = true
		if not walk or node.room == "" or node.room == start_room or node.room == "porao":
			continue
		if node.room == "sotao" and not flags["hatch_open"]:
			continue
		cands.append(node)
	cands.shuffle()
	var outside := []
	if flags.get("flap_open", false) or flags.get("porao_win_open", false) or day >= 4:
		for yp in Layout.data().get("YARD_RELIC_SPOTS", []):
			outside.append({"p": Layout.v3(yp), "room": "quintal"})
	outside.shuffle()
	if day == 5:
		cands = outside.slice(0, 2) + cands
	elif outside.size() > 0:
		cands.insert(randi() % maxi(1, cands.size()), outside[0])
	var picked := []
	var rooms := {}
	for min_d in [5.0, 3.5, 2.0, 0.0]:
		for node in cands:
			if picked.size() >= n:
				break
			var nroom: String = node["room"] if node is Dictionary else node.room
			var np2: Vector3 = node["p"] if node is Dictionary else node.p
			if node in picked or (rooms.has(nroom) and min_d > 2.0 and nroom != "quintal"):
				continue
			var ok := true
			for q in picked:
				var qp: Vector3 = q["p"] if q is Dictionary else q.p
				if qp.distance_to(np2) < min_d:
					ok = false
					break
			if ok:
				picked.append(node)
				rooms[nroom] = true
	var out := []
	for node in picked:
		var np: Vector3 = node["p"] if node is Dictionary else node.p
		var p: Vector3 = np + Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35))
		var gy := house.ground_height(p.x, p.z, np.y + 0.4)
		p.y = gy if gy > -500 and absf(gy - np.y) < 0.3 else np.y
		out.append(p + Vector3(0, 0.005, 0))
	return out


func _tick_relics() -> void:
	for m: Dictionary in _mission:
		if m["id"] != "" and m.has("aura"):
			var cc: PropSystem.Carryable = m["c"]
			(m["aura"] as GPUParticles3D).emitting = cc.enabled and not cc.carried and not ritual_placed(m["id"])
	for r in relics:
		var c: PropSystem.Carryable = r["c"]
		(r["aura"] as GPUParticles3D).emitting = not r["done"] and not c.carried and r["found"]
		# night 4: one of the doll's things is only there in the dark
		if r["rule"] == "dark" and not r["done"] and not c.carried:
			var dark := not house.lights.is_room_lit(str(r["room"]))
			c.node.visible = dark
			c.enabled = dark


func refresh_night_tasks() -> void:
	if relics.is_empty():
		return
	var lst := []
	for r in relics:
		var c: PropSystem.Carryable = r["c"]
		var tn := tr(c.name)
		var tx := tn.substr(0, 1).to_upper() + tn.substr(1)
		if day == Story.RELIC_ORDER_NIGHT:
			tx = "%d. %s" % [int(r["order"]) + 1, tx]
		var why := ""
		if not r["done"]:
			if r.get("dirty", false):
				why = Story.RELIC_RULES["wash"]
			elif not r["found"] or r["rule"] == "dark":
				why = Story.RELIC_RULES.get(r["rule"], "")
		if why != "":
			tx += tr(" (%s)") % tr(why)
		lst.append({"text": tx, "done": r["done"]})
	if day == Config.LAST_NIGHT:
		# the last night: the photo, the collar and the key are part of the same mission, then the ritual
		var placed := 0
		for id in CLUES:
			if ritual_placed(id):
				placed += 1
			lst.append({"text": {"foto": "A foto", "coleira": "A coleira", "chave": "A chave"}[id], "done": ritual_placed(id)})
		lst.append_array(_shadow_task())
		ui.tasks(tr("O ritual · %d/%d") % [relics_done + placed, relics.size() + CLUES.size()], lst, "Leve tudo ao círculo do porão e complete o ritual.")
		return
	lst.append_array(_shadow_task())
	ui.tasks(tr("Objetos de Dona Ivone · %d/%d") % [relics_done, relics.size()], lst, "Leve cada um ao círculo do porão. A noite só acaba quando todos estiverem lá.")


## while the Shadow hides, where (the marker points at the nook): lighting that room banishes it
func _shadow_task() -> Array:
	var sh = director.shadow if director else null
	if sh == null or not sh.has_method("hidden_room"):
		return []
	var room := str(sh.hidden_room())
	if room == "":
		return []
	return [{"text": tr("A Sombra está escondida %s: acenda a luz") % _in_room(room), "done": false, "warn": true}]


## the afternoon's list: day 1 the two missions; then the day's scene, the patience extras (optional)
## and, always last, lying down with Clara (the only way the afternoon ends)
func refresh_afternoon_tasks() -> void:
	if phase != "afternoon":
		return
	var lst := []
	for t in Story.AFTERNOON_TASKS.get(day, []):
		var text: String = tr(t["text"])
		if t["id"] == "bath" and not aft.get("bathing", false) and not flags.get("bath_scene_done", false) and aft.get("bath_wait", false):
			text = tr("Arranhe a porta do banheiro")
		if t["id"] == "key" and aft.get("key_missed", false):
			text += tr(" · ela desistiu")
		lst.append({"text": text, "done": _aft_task_done(t["id"])})
	if day > 1:
		for t in _aft_extras(day):
			var text: String = tr(t["text"])
			if t["id"] == "pet":
				text += tr(" (%d/3)") % mini(3, int(aft.get("pets", 0)))
			lst.append({"text": text, "done": _aft_task_done(t["id"]), "opt": true})
	var in_bed: bool = clara.in_bed and aft.get("can_skip", false)
	lst.append({"text": "Deite com a Clara na cama" if in_bed else "Quando ela for dormir, deite com ela", "done": aft.get("ending", false)})
	ui.tasks(tr("Fim de tarde · dia %d") % day, lst, tr("A tarde só acaba quando você deitar com ela. Paciência de Clara: %d%%") % roundi(clara.patience))


func _aft_task_done(id: String) -> bool:
	match id:
		"fed":
			return aft.get("fed", false)
		"key":
			return aft.get("key_given", false)
		"lap":
			return aft.get("lapped", false)
		"bath":
			return aft.get("bath_saved", false)
		"scene":
			return aft.get("scene_done", false)
		"pet":
			return int(aft.get("pets", 0)) >= 3
		"played":
			return aft.get("played", false)
		"yarn":
			return aft.get("yarned", false)
		"water":
			return aft.get("watered", false)
		"sun":
			return aft.get("sunned", false)
	return false


## eating every afternoon, then two of the pool picked by the day (never the same pair two days running)
func _aft_extras(d: int) -> Array:
	var pool: Array = Story.PATIENCE_POOL.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * d + 13
	var a := rng.randi_range(0, pool.size() - 1)
	var b := (a + 1 + rng.randi_range(0, pool.size() - 2)) % pool.size()
	return [{"id": "fed", "text": "Coma a ração"}, pool[a], pool[b]]


func aft_has(id: String) -> bool:
	if phase != "afternoon" or day <= 1:
		return false
	for t in _aft_extras(day):
		if t["id"] == id:
			return true
	return false


func give_yarn() -> void:
	var o := clara
	aft["yarned"] = true
	var ball: PropSystem.Carryable = cat.carrying
	drop_carried()
	toss_toy(ball)
	o.add_patience(10)
	o.say(Story.YARN_LINES[randi() % Story.YARN_LINES.size()], 2.8)
	o.paused = true
	o.model.pose = "pet"
	o.model.set_mood("joy", 0.8, 2.4)
	_later(2.4, func():
		o.paused = false
		o.model.pose = "stand")
	refresh_afternoon_tasks()


## the cat meows at the empty water bowl: she comes over and fills it, then goes back to what she was doing
func ask_water() -> void:
	var o := clara
	Sfx.meow(cat.head(), 1.0)
	aft["water_asked"] = true
	o.side_trip([
		{"t": "say", "text": Story.WATER_LINES[randi() % Story.WATER_LINES.size()], "dur": 2.4},
		{"t": "spot", "spot": Layout.spot("bowl")},
		{"t": "pose", "pose": "kneel", "dur": 0.8},
		{"t": "do", "fn": func():
			var ws := house.find("bowl_water_surface")
			if ws:
				ws.visible = true
			Sfx.drip(Vector3(8.9, 0.1, 3.92))
			Sfx.porcelain(Vector3(8.9, 0.05, 3.92))
			aft["watered"] = true
			o.add_patience(8)
			refresh_afternoon_tasks()},
		{"t": "wait", "dur": 0.8},
		{"t": "pose", "pose": "stand", "dur": 0.5},
	])


## the cat holds a pose where it stands (the held modes slide it to mode_target)
func _cat_stay(m: String) -> void:
	cat.mode = m
	cat.mode_target = cat.global_position
	cat.mode_yaw = cat.yaw


## a nap in the patch of sun under the west window of the living room
const SUN_SPOT := Vector3(0.75, 0.0, 2.75)


func sun_nap() -> void:
	cat.teleport(SUN_SPOT, PI / 2)
	_cat_stay("nap")
	_start_purr(0.4)
	_later(5.0, func():
		if cat.mode == "nap":
			cat.mode = "free"
		_stop_purr()
		aft["sunned"] = true
		clara.add_patience(6)
		if clara.visible and clara.global_position.distance_to(cat.global_position) < 9.0:
			clara.say(Story.SUN_LINES[randi() % Story.SUN_LINES.size()], 2.6)
		refresh_afternoon_tasks())


func is_relic(c) -> bool:
	return c != null and str(c.id).begins_with("relic_")


## the cat lays one of Ivone's things in the circle
func deliver_relic() -> void:
	var c: PropSystem.Carryable = cat.carrying
	if not is_relic(c):
		return
	var rr := relic_of(c)
	if rr.get("dirty", false):
		hint("Está coberta de lama. Lave na pia do banheiro antes de deixar no círculo.", 3.5)
		return
	if day == Story.RELIC_ORDER_NIGHT:
		# the circle wants them in the diary's order
		var want := -1
		for r in relics:
			if not r["done"]:
				want = int(r["order"])
				break
		if int(rr.get("order", want)) != want:
			Sfx.shriek(house.ritual_center + Vector3(0, 0.5, 0), 0.3, false)
			shake(0.3)
			hint(tr("O círculo recusou. O diário dizia a ordem: %s.") % tr(Story.RELIC_ORDER_HINT), 4.5)
			return
	cat.carrying = null
	c.carried = false
	c.enabled = false
	var a := -PI / 2 + float(relics_done) / maxf(1.0, relics.size()) * TAU
	var rc := house.ritual_center
	c.place(Vector3(rc.x + cos(a) * 1.25, rc.y + 0.005, rc.z + sin(a) * 1.25), randf() * TAU)
	relics_done += 1
	var text := ""
	for r in relics:
		if r["c"] == c:
			r["done"] = true
			text = r["text"]
	if day != Config.LAST_NIGHT:
		house.ritual_glow = minf(1.0, float(relics_done) / relics.size())
	Sfx.bell(c.pos, 1, 0.3)
	ui.say("", text, 7, "narrator")
	refresh_night_tasks()
	# the last night ends with the ritual, not with the delivery
	if day == Config.LAST_NIGHT and ritual_ready():
		ui.say("", "O círculo está completo. Segure sobre ele para terminar o ritual.", 5, "narrator")
	if relics_done >= relics.size() and day != Config.LAST_NIGHT:
		_later(2.5, func():
			if phase == "night" and not _failing and not _winning:
				_night_won())


# ---------------------------------------------------------------------- boxes and the night light


func _box_flag(i: int) -> Dictionary:
	var hp: Vector3 = House.BOX_HOMES[i]
	return {"x": hp.x, "y": hp.y, "z": hp.z, "yaw": 0.0, "moved": false, "used": false}


## what this morning hands the cat for the coming night
func _unlock_morning(d: int) -> void:
	if d >= 3 and flags["boxes"][0] == null:
		flags["boxes"][0] = _box_flag(0)
	if d >= 6 and flags["boxes"][1] == null:
		flags["boxes"][1] = _box_flag(1)
	if d >= 6 and flags.get("nightlight") == null:
		var nh: Vector3 = House.NIGHTLIGHT_HOME
		flags["nightlight"] = {"x": nh.x, "y": nh.y, "z": nh.z}
	_sync_boxes()
	_sync_nightlight()
	var c: PropSystem.Carryable = house.carryables["nightlight"]
	var nl = flags.get("nightlight")
	c.enabled = nl != null
	c.node.visible = nl != null
	if nl != null:
		c.place(Vector3(nl["x"], nl["y"], nl["z"]))


func _sync_boxes() -> void:
	for i in house.boxes.size():
		var b = flags["boxes"][i] if flags.has("boxes") else null
		if b == null:
			house.set_box(i, House.BOX_HOMES[i], 0.0, false)
		else:
			house.set_box(i, Vector3(b["x"], b["y"], b["z"]), float(b["yaw"]), true, b["used"])


## the night light keeps its room lit (the Shadow will not enter) and glows warm
func _sync_nightlight() -> void:
	var lights := house.lights
	lights.night_lit.clear()
	var nl = flags.get("nightlight")
	var c: PropSystem.Carryable = house.carryables["nightlight"]
	var dv: House.Device = _nightlight_device()
	if dv:
		dv.hidden = nl == null or c.carried
		if nl != null:
			var at := Vector3(nl["x"], nl["y"], nl["z"])
			dv.pos = at + Vector3(0, 0.06, 0)
			dv.outlet = at + Vector3(0, 0.05, 0)
			dv.normal = Vector3(0, 0, 1)
			dv.floor_y = at.y
			var r0 := Layout.room_at(at)
			dv.room = r0 if r0 != "" else "despensa"
	var on := nl != null and not c.carried and phase == "night" and (dv == null or dv.plugged)
	house.nightlight_glow.visible = nl != null and not c.carried
	if on:
		var r := Layout.room_at(Vector3(nl["x"], nl["y"], nl["z"]))
		if r != "":
			lights.night_lit[r] = true


func _nightlight_device() -> House.Device:
	for dv: House.Device in house.devices:
		if dv.id == "nightlight":
			return dv
	return null


func box_usable(i: int) -> bool:
	var b = flags["boxes"][i]
	return b != null and not b["used"]


func start_push(i: int) -> void:
	_pushing = i
	(house.boxes[i]["shape"] as CollisionShape3D).disabled = true
	Sfx.creak(house.boxes[i]["pos"], 0.2, 0.5, 1.8)


func stop_push() -> void:
	if _pushing < 0:
		return
	var i := _pushing
	_pushing = -1
	var b: Dictionary = house.boxes[i]
	flags["boxes"][i] = {"x": b["pos"].x, "y": b["pos"].y, "z": b["pos"].z, "yaw": b["yaw"], "moved": true, "used": flags["boxes"][i]["used"]}
	house.set_box(i, b["pos"], b["yaw"], true, flags["boxes"][i]["used"])
	on_task("box%d" % i)


func _tick_push() -> void:
	if _pushing < 0:
		return
	var p := cat.global_position + cat.forward * 0.55
	var gy := house.ground_height(p.x, p.z, cat.global_position.y + 0.3)
	p.y = gy if gy > -500 and absf(gy - cat.global_position.y) < 0.4 else cat.global_position.y
	var b: Dictionary = house.boxes[_pushing]
	var n: Node3D = b["node"]
	b["pos"] = p
	b["yaw"] = cat.yaw + PI
	n.global_position = p
	n.rotation = Vector3(0, b["yaw"], 0)
	if cat.vel.length() > 0.3 and randf() < 0.08:
		Sfx.creak(p, 0.08, 0.3, 2.2)


## dive into a box: a hiding place; while hunted, the hunter follows it in and is gone, and the box is ruined
func enter_box(i: int) -> void:
	var b: Dictionary = house.boxes[i]
	var p: Vector3 = b["pos"]
	var out: Vector3 = p + Vector3(sin(b["yaw"]), 0, cos(b["yaw"])) * 0.55
	(b["shape"] as CollisionShape3D).disabled = true
	hide_at({"id": "box%d" % i, "name": "a caixa", "p": [p.x, p.y + 0.02, p.z], "exit": [out.x, out.y, out.z], "yaw": b["yaw"]})
	_later(1.1, func():
		if phase == "night" and cat.mode == "hidden" and director.box_trap(p):
			flags["boxes"][i]["used"] = true
			house.set_box(i, p, b["yaw"], true, true)
			hint_once("box", "A caixa engoliu quem caçava você, mas ficou estragada. Não serve mais.", 5))


func drop_carried() -> void:
	var c: PropSystem.Carryable = cat.carrying
	if c == null:
		return
	cat.carrying = null
	c.carried = false
	var p := cat.global_position + cat.forward * 0.25
	p.y = house.ground_height(p.x, p.z, cat.global_position.y + 0.3)
	if p.y < cat.global_position.y - 1:
		p = cat.global_position
	c.place(p, cat.yaw)
	Sfx.thud(p, 0.1, 200)
	if c.id == "nightlight":
		flags["nightlight"] = {"x": p.x, "y": p.y, "z": p.z}
		_sync_nightlight()
		on_task("nightlight")
	if c.id == "doll":
		director.doll.dropped(p)
	if c.id in CLUES:
		flags["clues"][c.id] = {"x": p.x, "y": p.y, "z": p.z, "on_circle": false}


func hide_at(spot: Dictionary) -> void:
	var c := cat
	if c.carrying:
		drop_carried()
	c.mode = "hidden"
	c.mode_target = Layout.v3(spot["p"])
	c.mode_yaw = spot["yaw"]
	c.vel = Vector3.ZERO
	_hide_spot = spot
	Sfx.paw_step(c.global_position, false, true)
	hint_once("hide", "Parado e escondido, o cão não acha você. Ele fareja por perto e vai embora. Interagir para sair.")


func unhide() -> void:
	if cat.mode != "hidden":
		return
	cat.teleport(Layout.v3(_hide_spot["exit"]) if _hide_spot else cat.global_position, cat.yaw)
	_hide_spot = null
	_sync_boxes()


## something got the cat: one of the seven lives is gone. Returns false while the cat is still
## protected (just hit, stunned, or the night is already over).
func cat_hit(source: String, from: Vector3, knock := true) -> bool:
	if phase != "night" or mode != "play" or _failing or _winning or _cat_immune > 0:
		return false
	var c := cat
	_cat_immune = 6.0
	lives -= 1
	lost_tonight += 1
	ui.lives(lives, lost_tonight)
	director.cat_down()
	drop_carried()
	if knock:
		c.stun(3.6, from)
	Sfx.cat_cry(c.head(), 0.9)
	if source == "hound":
		Sfx.bark(from + Vector3(0, 0.6, 0), 0.8)
		stats["caught"] += 1
	rig.shake(1.2)
	flash(0.35, Color("#7a0000"))
	distort(0.6)
	ca(0.8)
	for who: Owner in household_present():
		if hops(c.global_position, who.global_position) <= 3:
			who.add_fear(7)
			who.add_patience(-3)
			if who.in_bed and who.asleep:
				who.asleep = false
				who.say("Que grito foi esse?!" if who.cfg["skeptic"] else "{cat}?! O que foi isso?!", 2.6, "scared")
	# how to beat whatever took it: the card comes back for the rest of this night (and its restarts)
	# the "como vencer" card belongs to the ghost's first night only
	if Story.THREAT_INFO.has(source) and Config.is_new_on(source, night):
		_show_howto(source)
	if lives <= 0:
		_lives_out(source)
		return true
	if lives == 1:
		ui.title("Última vida", "", 3)
	if source == "hound":
		hint_once("caught", "O cão te pegou e levou uma das suas sete vidas. Esconda-se, suba em móveis ou fuja pelo duto da próxima vez.")
	else:
		hint_once("caught_ghost", "Você perdeu uma das sete vidas. As vidas valem para a semana inteira; dá para rejogar uma noite no menu e recuperá-las.")
	return true


## ghosts cannot see or grab the cat right after it lost a life
func cat_safe() -> bool:
	return _cat_immune > 0 or cat.stun_t > 0


## a ghost noticed the cat and comes for it
func cat_hunted(th: Threat) -> void:
	sting(0.5)
	shake(0.35)
	var info: Dictionary = Story.THREAT_INFO.get(th.threat_id, {})
	if info.has("escape"):
		hint_once("hunt_" + th.threat_id, tr("[b]%s[/b] vem atrás de você! %s") % [info["name"], info["escape"]], 6)


## a sudden scare at night: the cat jumps up arched toward `from` (a point; null does nothing). Only
## in play, with the cat out and about, and `from` within `reach` m; the cat keeps its own cooldown.
## (a method, not a lambda: the Sfx autoload outlives this Game)
func _on_shriek(pos: Vector3) -> void:
	scare_cat(pos, 10.0)


func scare_cat(from, reach := 8.0) -> bool:
	if not (from is Vector3) or phase != "night" or mode != "play" or not controls or _failing or _winning:
		return false
	var c := cat
	if c.mode not in ["free", "busy"] or c.stun_t > 0 or c.global_position.distance_to(from) > reach:
		return false
	return c.startle(from)


## Clara or Davi says a line close by: now and then the cat tilts its head at them (afternoon or a calm
## night, never in a chase, a private scene or with something in its mouth)
func _cat_listens(from: Owner) -> void:
	var c := cat
	if mode != "play" or not controls or c.mode != "free" or c.carrying != null or not from.visible:
		return
	if phase == "afternoon" and (aft.get("private", "") != "" or aft.get("ending", false)):
		return
	if phase == "night" and (director.phase() != "calm" or director.cat_hunters(null) > 0):
		return
	if phase != "afternoon" and phase != "night":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _tilt_next:
		return
	var hp := from.head_pos()
	var to := hp - c.global_position
	if Vector2(to.x, to.z).length() > 4.0 or absf(to.y) > 2.6 or randf() > 0.5:
		return
	# facing her more or less (or sitting idle, when it turns its head round)
	var rel := absf(wrapf(atan2(to.x, to.z) - c.yaw, -PI, PI))
	if rel > 1.6 and Vector2(c.vel.x, c.vel.z).length() > 0.2:
		return
	from.head_mark.global_position = hp
	if c.tilt_to(from.head_mark):
		_tilt_next = now + 5.0

## the seventh life is gone: the ending, then the night again with the lives it started with
func _lives_out(source: String) -> void:
	_failing = true
	controls = false
	director.stop_all()
	if cat.mode == "purr":
		toggle_purr()
	Sfx.sting(0.9)
	flash(0.6, Color("#3a0000"))
	distort(1.0)
	fx["fade_target"] = 1.0
	fx["fade_speed"] = 0.4
	_later(3.2, func():
		Controls.capture(false)
		mode = "over"
		ui.clear_hints()
		Music.set_mode("ending")
		var e: Dictionary = Story.ENDINGS["lives"]
		var lines := []
		for l: String in e["lines"]:
			lines.append(tr(l).replace("{cat}", Settings.cat_name))
		ui.show_ending(e["title"], lines, func():
			Music.set_mode("none")
			var who: String = Story.THREAT_INFO[source]["name"] if Story.THREAT_INFO.has(source) else "a casa"
			var start := maxi(1, SaveGame.lives_at(save, day))
			ui.show_fail({
				"title": "As sete vidas acabaram", "sub": tr("Noite %d · %s") % [day, _fmt_clock(hour)],
				"why": tr("A última vida foi levada por %s.") % who,
				"tip": "Rejogue uma noite anterior no menu (Escolher noite) perdendo menos vidas: elas voltam para as noites seguintes.",
				"facts": [tr("Esta noite começa com 1 vida") if start == 1 else tr("Esta noite começa com %d vidas") % start],
				"on_night": func(): start_night(day, save["night"]),
				"on_day": null,
				"on_menu": to_menu,
			})))


# ====================================================================== pause


func pause() -> void:
	if mode != "play":
		return
	mode = "paused"
	Controls.capture(false)
	Sfx.set_muffle(0.7)
	var is_night := phase == "night"
	var t := tr("Noite %d · %s") % [day, _fmt_clock(hour)] if is_night else tr("Dia %d · %s") % [day, "manhã" if phase == "morning" else "fim de tarde"]
	ui.show_pause({
		"title": t,
		"threats": _night_threat_list() if is_night else [],
		"on_resume": resume,
		"on_restart_night": (func(): start_night(day, save["night"])) if is_night and save["night"] else null,
		"on_restart_day": (func(): _begin_snapshot(save["morning"])) if day > 1 and save["morning"] else null,
		# the night only ends with the mission: skipping it counts it as done (the last night: the ritual)
		"on_skip_night": (func():
			resume()
			if day == Config.LAST_NIGHT:
				complete_ritual()
			else:
				_night_won()) if is_night and not _failing and not _winning else null,
		"on_settings": func(): ui.show_settings(func():
			mode = "play"
			pause()),
		"on_menu": to_menu,
	})


## every ghost that may walk tonight (and the hound), the new one first, for the pause menu
func _night_threat_list() -> Array:
	var ids: Array = Config.NIGHT_THREATS.get(night, []).duplicate()
	if night >= Config.HOUND_FROM:
		ids.append("hound")
	var out := []
	for id in ids:
		var info: Dictionary = Story.THREAT_INFO.get(id, {})
		if info.has("howto"):
			var item := {"name": info["name"], "howto": info["howto"], "new": Config.is_new_on(id, night)}
			if item["new"]:
				out.push_front(item)
			else:
				out.append(item)
	return out


func resume() -> void:
	ui.close_overlay()
	mode = "play"
	Sfx.set_muffle(0.15 if lock["active"] else 0.0)
	Controls.capture(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == "play" and OS.get_cmdline_user_args().is_empty():
		pause()


func _unhandled_input(event: InputEvent) -> void:
	if mode == "play" and event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not ui.overlay_open:
		Controls.capture(true)


# ====================================================================== loop


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if mode == "boot":
		return
	if mode == "play":
		if Input.is_action_just_pressed("pause") and not ui.overlay_open and Engine.get_process_frames() != ui.back_frame:
			pause()
		else:
			_simulate(dt)
	elif mode == "menu":
		_menu_update(dt)
	elif mode == "over" or mode == "paused":
		house.update(0.0 if mode == "paused" else dt, day, phase)
	if mode != "play":
		# menus, the pause, the end-of-night panels: the tasks and the marker step aside
		ui.tasks_visible(false)
		ui.objective(null, cam)
	_post_fx(dt)
	ui.show_click_to_play(mode == "play" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not ui.overlay_open and Controls.last_device == Controls.Device.KBM and controls)


func _menu_update(dt: float) -> void:
	_menu_t += dt
	var t := _menu_t
	var pos := Vector3(4.2 + sin(t * 0.045) * 3.2, 3.0 + sin(t * 0.07) * 0.35, -15.2 + cos(t * 0.045) * 1.2)
	cam.global_position = pos
	cam.look_at(Vector3(7.2 + sin(t * 0.03) * 0.5, 3.3, 2), Vector3.UP)
	cam.fov = 50
	house.update(dt, 1, "menu")
	clara.tick(dt)
	cat.rig.update_pose(dt, {"sit": 1.0, "speed": 0.0, "grounded": true, "tail_up": 0.5})
	env.tick(dt, cam, false, cat.global_position, 0.0, false)
	Music.tick(dt, 0.1)
	ui.prompt(null)


func _simulate(dt: float) -> void:
	var c := cat
	var o := clara
	var h := house
	_info_held = _info_held + dt if Input.is_action_pressed("info") else 0.0
	if phase == "night":
		_night_update(dt)
	elif phase == "morning":
		_morning_update(dt)
	elif phase == "afternoon":
		phase_t += dt
		aft["pet_cd"] -= dt
		_afternoon_people(dt)
		if aft["bathing"]:
			aft["bath_t"] += dt
			# Ivone's hands come up out of the foam slowly at her feet, reaching for her
			var hands := director.drowner.hands
			var k := smoothstep(1.5, 7.0, aft["bath_t"])
			var tub_y := 3.05
			for f: House.Faucet in house.faucets:
				if f.id == "tub":
					tub_y = f.bottom_y
			hands.global_position = Vector3(10.42, tub_y - 1.62 + k * 0.5 + sin(phase_t * 1.3) * 0.03, 9.57)
			hands.rotation.y = PI / 2
			hands.alpha = 0.55 * k
			hands.rig.pose = "arms_up"
			hands.tick(dt)
		_shoo_from_private()
		if o.patience <= 1:
			o.patience = 5.0
		# lying down with her in bed ends the afternoon
		if c.mode == "purr" and not aft["ending"]:
			aft["purr_t"] += dt
			if aft["purr_t"] >= AFT_PURR_SECS:
				_end_afternoon()
	# purr mode exit on movement
	if c.mode == "purr" and controls and (Controls.move_vector().length() > 0.5 or Input.is_action_just_pressed("jump")):
		toggle_purr()
	if c.mode == "purr" and not (_purr_who if _purr_who else o).in_bed:
		toggle_purr()
	# cat
	c.fatigue_on = phase == "night"
	if c.fatigue_on and c.drowsy() > 0.3:
		hint_once("tired", "O gato está cansado: menos Foco e mais lento. Ronronar na cama recupera o sono.")
	_tick_eat(dt)
	c.tick(dt, rig.yaw, controls)
	_tick_push()
	if c.carrying:
		var cr: PropSystem.Carryable = c.carrying
		var mf := c.rig.mouth_frame()
		mf.origin += mf.basis.y * -0.012 + mf.basis.z * -0.005
		cr.node.global_transform = Carry.held_transform(str(cr.node.get_meta("grip", cr.id)), mf, cr.node.scale)
		cr.pos = c.global_position
	if c.mode == "free":
		h.props.interact_cat(c.global_position, c.vel, 0.14)
	# threats / people
	if phase == "night":
		director.tick(dt)
	c.hunted = lerpf(c.hunted, director.hound.threat_level() * (0.6 if c.mode == "hidden" else 1.0) if phase == "night" else 0.0, 1.0 - exp(-3.0 * dt))
	c.slip = lerpf(c.slip, director.drowner.wet_at(c.global_position) if phase == "night" else 0.0, 1.0 - exp(-10.0 * dt))
	rig.distance = lerpf(rig.distance, 0.85 if c.mode == "hidden" else 1.55, 1.0 - exp(-4.0 * dt))
	o.tick(dt)
	if davi.present:
		davi.tick(dt)
	h.update(dt, day, phase)
	_env_fx(dt)
	# threat awareness: ears + fur
	if phase == "night":
		var urgent := director.most_urgent()
		c.ear_target_world = urgent.get("focus") if not urgent.is_empty() else null
		c.alert = clampf(urgent["urgency"] * 2.2, 0, 1) if not urgent.is_empty() else 0.0
		c.bristle = clampf(1.0 - director.nearest_entity(c.global_position) / 3.2, 0, 1)
		if c.bristle > 0.6:
			rig.shake(0.05)
	else:
		c.ear_target_world = null
		c.alert = 0.0
		c.bristle = 0.0
	RenderingServer.global_shader_parameter_set("cat_pos", c.global_position)
	_interactions(dt)
	# the cat's own night sight: a faint cool glow that follows it
	var sight := h.lights.get_light(16)
	if sight and sight.on:
		sight.light.global_position = c.global_position + Vector3(0, 0.55, 0)
	# camera
	var focus := c.global_position + Vector3(0, 0.22 if c.mode == "purr" else 0.32, 0)
	rig.update(dt, focus, controls or c.mode == "purr", c.running and Vector2(c.vel.x, c.vel.z).length() > 3.0)
	c.rig.visible = cam.global_position.distance_to(focus) > 0.3
	_audio_update(dt)
	_hud_update()


func _env_fx(dt: float) -> void:
	var cp := cat.global_position
	var indoors := cp.x > 0 and cp.x < 12 and cp.z > 0 and cp.z < 13.2 and cp.y < 9
	house.lights.indoors = indoors
	env.tick(dt, cam, indoors, cp, cat.hunted, phase == "night")
	var steam := []
	for f: House.Faucet in house.faucets:
		if f.running > 0.2 and f.id != "coz":
			steam.append(f.spout)
	# the hot bath steams while Clara is in the tub
	if phase == "afternoon" and (aft.get("bathing", false) or aft.get("bath_wait", false)):
		steam.append(Layout.spot_pos("bathTubIn") + Vector3(0, 0.4, 0))
	env.steam_at(steam)
	if phase == "night":
		var cf := -cam.global_basis.z
		ambient.tick(dt, house, cp, night, func(p): return is_observed(p, false), func(p):
			var d := (p as Vector3 - cam.global_position).normalized()
			return rad_to_deg(acos(clampf(cf.dot(d), -1, 1))), director.allows_ambient())


func _interactions(dt: float) -> void:
	var c := cat
	if not controls:
		ui.prompt(null)
		marks.tick(dt, null)
		_hold_t = 0.0
		_hold_target = null
		return
	if c.mode == "hidden":
		marks.tick(dt, null)
		ui.prompt("Sair do esconderijo", "interact", 0)
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("jump"):
			unhide()
		return
	var bst: Interactions.Interactable = null
	if (c.mode == "free" or c.mode == "purr") and not c.acting():
		bst = inter.best(c.global_position, c.forward)
	elif (c.mode == "scratch" or c.mode == "busy") and _hold_target and _hold_target.enabled.call():
		bst = _hold_target
	if c.mode == "purr":
		bst = inter.find("purr_" + str((_purr_who if _purr_who else clara).cfg["id"]))
	marks.tick(dt, bst)
	var swat = null
	if bst == null and c.carrying == null and c.mode == "free" and not c.acting():
		swat = house.props.near_swattable(c.global_position)
	var holding := Input.is_action_pressed("interact")
	if bst:
		var hold := bst.hold_time()
		if hold > 0:
			if holding and (_hold_target == bst or _hold_target == null):
				_hold_target = bst
				_hold_t += dt
				c.mode = "scratch" if bst.pose == "scratch" else "busy"
				c.mode_target = c.global_position
				var bp := bst.p()
				c.mode_yaw = atan2(bp.x - c.global_position.x, bp.z - c.global_position.z)
				if bst.pose == "scratch" and randf() < dt * 4.0:
					Sfx.paw_step(bp, true, false, "wood")
				ui.prompt(bst.hold_label.call() if bst.hold_label.is_valid() else bst.prompt.call(), "interact", clampf(_hold_t / hold, 0, 1), true)
				if _hold_t >= hold:
					_hold_t = 0.0
					_hold_target = null
					c.mode = "free"
					bst.on_interact.call()
			else:
				if _hold_target:
					_hold_target = null
					_hold_t = 0.0
					if c.mode == "scratch" or c.mode == "busy":
						c.mode = "free"
				ui.prompt(bst.prompt.call(), "interact", 0, true)
		else:
			ui.prompt(bst.prompt.call(), "interact", 0)
			if Input.is_action_just_pressed("interact"):
				bst.on_interact.call()
	elif c.carrying:
		ui.prompt(tr("Soltar %s") % tr(c.carrying.name), "interact", 0)
		if Input.is_action_just_pressed("interact"):
			drop_carried()
	elif swat:
		ui.prompt("Derrubar", "interact", 0)
		if Input.is_action_just_pressed("interact"):
			cat_swat(swat)
	else:
		ui.prompt(null)
	if not holding and (c.mode == "scratch" or c.mode == "busy"):
		c.mode = "free"
		_hold_t = 0.0
		_hold_target = null


func _audio_update(dt: float) -> void:
	var people := household_present()
	var scared: Owner = clara
	for p: Owner in people:
		if p.fear > scared.fear:
			scared = p
	if phase == "night" and scared.fear > 25 and scared.visible:
		_heart_t -= dt
		var k := (scared.fear - 25.0) / 75.0
		if _heart_t <= 0:
			_heart_t = lerpf(1.15, 0.42, k)
			Sfx.heartbeat(0.25 + k * 0.6, scared.head_pos())
	pulse = lerpf(pulse, 0.0, 1.0 - exp(-7.0 * dt))
	# being hunted, or staring the Shadow down in its hiding place (it charges at 1)
	var hu := maxf(cat.hunted, _shadow_stare())
	if hu > 0.25:
		_cat_heart_t -= dt
		if _cat_heart_t <= 0:
			_cat_heart_t = lerpf(0.85, 0.36, hu)
			Sfx.heartbeat(0.3 + hu * 0.5, null)
			pulse = 1.0
	_tick_t -= dt
	if _tick_t <= 0:
		_tick_t = 1.0
		Sfx.tick(house.clock_pos)
	if phase == "night":
		_night_sound(dt, scared)
	if _wind:
		_wind.set_level(0.1 if phase == "morning" else (0.16 if phase == "afternoon" else 0.28 + env.wind_level * 0.15))
	Music.tick(dt, maxf(director.tension(), scared.fear / 100.0) if phase == "night" else 0.0)


## the night's sound follows the Director's rhythm (docs/SOM.md):
## calm: the house settling, far apart; buildup: closer creaks and footsteps behind the cat, a
## whisper now and then; the moment before a ghost acts (stage 3) everything sinks into a hush;
## peak: the stinger over a ducked mix; relax: the room tone comes back slowly
func _night_sound(dt: float, scared: Owner) -> void:
	var ph: String = director.phase()
	var top := 0
	for th: Threat in director.all:
		if th.enabled:
			top = maxi(top, th.stage)
	if ph == "buildup" and top >= 3:
		Sfx.duck(0.7, 0.4)
	_creak_t -= dt * (1.0 + scared.fear / 50.0) * (1.8 if ph == "buildup" else (0.6 if ph == "relax" else 1.0))
	if _creak_t <= 0:
		_creak_t = randf_range(14, 30)
		var rooms := ["corredor", "hall", "sotao", "hospedes", "escritorio", "porao"]
		var r := Layout.room(rooms[randi() % rooms.size()])
		Sfx.creak(Vector3(randf_range(r["x0"] + 0.5, r["x1"] - 0.5), r["y"] + 2.2, randf_range(r["z0"] + 0.5, r["z1"] - 0.5)), 0.3, randf_range(0.6, 1.4), randf_range(0.7, 1.2))
	# out of place: a step, a creak or a breath a few metres behind the cat, where the camera does
	# not look (only while something is coming, and never on top of a scare)
	_behind_t -= dt
	if _behind_t <= 0.0:
		_behind_t = randf_range(16.0, 28.0) if ph == "buildup" else randf_range(40.0, 70.0)
		if ph == "buildup" or (ph == "calm" and randf() < 0.3):
			var back := -cam.global_basis.z
			back.y = 0
			back = -back.normalized() if back.length() > 0.01 else Vector3(0, 0, 1)
			var p := cat.global_position + back * randf_range(3.0, 5.0) + Vector3(0, 0.3, 0)
			match randi() % 3:
				0:
					Sfx.human_step(p, false)
					_later(0.55, func(): Sfx.human_step(p + back * 0.5, false))
				1:
					Sfx.creak(p + Vector3(0, -0.2, 0), 0.35, 0.8, 0.9)
				2:
					Sfx.play("breath", p + Vector3(0, 0.9, 0), 0.25, randf_range(0.6, 0.7), 1.2)


## the HUD while playing: the tasks are always on screen (not over title cards or fades), the TAB key
## only brings up the clock; the objective marker, the ghosts under way, the assist bars, the alert
func _hud_update() -> void:
	var is_night := phase == "night"
	var clear_view: bool = not ui.overlay_open and fx["fade"] < 0.5 and not ui.title_showing() and not _transitioning
	ui.tasks_visible(clear_view and phase in ["morning", "afternoon", "night"])
	_hud_t -= get_process_delta_time()
	if _hud_t <= 0.0:
		_hud_t = 0.25
		if is_night:
			refresh_night_tasks()
		elif phase == "morning":
			refresh_tasks()
		elif phase == "afternoon":
			refresh_afternoon_tasks()
	if _info_held > 0:
		if is_night:
			ui.clock(_fmt_clock(hour), tr("Noite %d") % day)
		elif phase == "morning":
			ui.clock("Manhã", tr("Dia %d") % day)
		else:
			ui.clock("Fim de tarde", tr("Dia %d") % day)
	else:
		ui.clock(_fmt_clock(hour) if Settings.g("assist") and is_night else null, tr("Noite %d") % day)
	if is_night and clear_view:
		var vit := {"clara": 1.0 - clara.fear / 100.0, "cat": cat.sleep / 100.0}
		if davi.present:
			vit["davi"] = 1.0 - davi.fear / 100.0
		ui.vitals(vit)
	else:
		ui.vitals(null)
	var ot = objective_target() if clear_view else null
	var od := cat.global_position.distance_to(ot) if ot != null else 0.0
	ui.objective(ot if ot != null and od > 1.6 else null, cam, od)
	var urgent := director.most_urgent() if is_night else {}
	if Settings.g("assist") and (is_night or phase == "afternoon"):
		var arrow = null
		if not urgent.is_empty() and urgent["focus"] != null and urgent["stage"] >= 1:
			var d: Vector3 = (urgent["focus"] as Vector3) - cam.global_position
			var fwd := -cam.global_basis.z
			fwd.y = 0
			fwd = fwd.normalized()
			var right := Vector3(-fwd.z, 0, fwd.x)
			d.y = 0
			arrow = atan2(d.dot(right), d.dot(fwd))
		var ppl := []
		for m: Owner in household_present():
			ppl.append({"name": m.display_name, "fear": m.fear, "patience": m.patience})
		ui.assist({"people": ppl, "focus": cat.focus, "sleep": cat.sleep if is_night else 100.0, "arrow": arrow})
	else:
		ui.assist(null)
	if is_night:
		var att: Threat = null
		for th: Threat in director.all:
			if th.enabled and th.stage >= 4 and th.threat_id != "thing" and (att == null or th.stage > att.stage):
				att = th
		if att:
			ui.alert(tr("%s → %s") % [att.display_name, att.target.display_name], Story.THREAT_INFO[att.threat_id]["hint"])
		else:
			ui.alert(null)
		var can := controls and cat.mode == "free" and director.can_hiss_at(cat.global_position)
		ui.hiss("off" if not can else ("ready" if cat.focus >= 22 else "weak"))
	else:
		ui.alert(null)
		ui.hiss("off")


## where the cat should go now (a world point for the marker), or null. Afternoons: Clara by default;
## the bowl, the key and Clara in the basement on day 1; her bed once she lies down. Nights: the
## Shadow's hiding place while it hides (light that room).
func objective_target():
	if mode != "play" or not controls or cat == null:
		return null
	if phase == "afternoon":
		if aft.get("ending", false):
			return null
		if aft.get("wait_eat", false) and not aft.get("fed", false):
			return BOWL_POS + Vector3(0, 0.15, 0)
		if aft.get("key_asked", false) and not aft.get("key_given", false) and not aft.get("key_missed", false):
			var kc: PropSystem.Carryable = house.carryables.get(PORAO_KEY)
			if kc and cat.carrying == kc:
				return clara.head_pos() + Vector3(0, 0.25, 0)
			if kc and kc.enabled and kc.node.visible:
				return kc.pos + Vector3(0, 0.1, 0)
		if not clara.visible:
			return null
		if clara.in_bed:
			return (clara.cfg["purr_pos"] as Vector3) + Vector3(0, 0.3, 0) if aft.get("can_skip", false) and cat.mode != "purr" else null
		return clara.head_pos() + Vector3(0, 0.25, 0)
	if phase == "night" and director:
		# the first night of a ghost, the marker shows where it is (from then on the cat has to know)
		var fresh = Config.NEW_ON_NIGHT.get(night)
		if fresh != null:
			var th: Threat = director.get_threat(fresh)
			# the Shadow gets no marker: the player has to find where it hides
			if th and th.enabled and th.stage >= 1 and not th is ShadowThreat:
				var f = th.focus()
				if f != null:
					return (f as Vector3) + Vector3(0, 0.3, 0)
		if night == Config.HOUND_FROM and director.hound.active:
			var hf = director.hound.focus()
			if hf != null:
				return hf
	return null


## "no quarto da Clara", "na cozinha": a room name after "em"
static func _in_room(room: String) -> String:
	var nm := Layout.room_name(room)
	# in English: "in the kitchen", "in Clara's bedroom"
	if TranslationServer.get_locale().begins_with("en"):
		return "in " + (nm if "'" in nm else "the " + nm.to_lower())
	var fem := room in ["lavanderia", "sala", "cozinha", "varanda", "jantar", "despensa"]
	return "%s %s" % ["na" if fem else "no", nm.substr(0, 1).to_lower() + nm.substr(1)]


## the red at the screen's edges while the cat stares at the hiding Shadow: from halfway to the charge
func _shadow_stare() -> float:
	var sh := director.shadow if director else null
	if sh == null or not sh.mode in ["peek", "retreat", "stalk"]:
		return 0.0
	return smoothstep(0.35, 1.0, sh.sight)


func _post_fx(dt: float) -> void:
	var f := fx
	var ft: float = f["fade_target"]
	f["fade"] = minf(ft, f["fade"] + dt * f["fade_speed"]) if f["fade"] < ft else maxf(ft, f["fade"] - dt * f["fade_speed"])
	f["letterbox"] = lerpf(f["letterbox"], f["letter_target"], 1.0 - exp(-3.0 * dt))
	f["flash"] = maxf(0.0, f["flash"] - dt * 1.8)
	f["distort"] = maxf(0.0, f["distort"] - dt * 0.9)
	f["ca"] = maxf(0.0, f["ca"] - dt * 1.5)
	var max_fear := 0.0
	for p: Owner in household_present():
		max_fear = maxf(max_fear, p.fear)
	var fear_k := smoothstep(22.0, 100.0, max_fear) if phase == "night" and mode != "menu" else 0.0
	f["fear"] = lerpf(f["fear"], fear_k, 1.0 - exp(-2.0 * dt))
	var vig := fear_k * 0.7 + (0.35 if lock["active"] else 0.0) + (0.15 if cat and cat.mode == "purr" else 0.0)
	f["vignette"] = lerpf(f["vignette"], vig, 1.0 - exp(-2.0 * dt))
	f["hunt"] = lerpf(f["hunt"], maxf(cat.hunted * 0.9, _shadow_stare()) if mode == "play" and cat else 0.0, 1.0 - exp(-3.0 * dt))
	env.set_post({
		"fear": f["fear"], "hunt": f["hunt"], "pulse": pulse,
		"vignette": f["vignette"], "ca": f["ca"] + f["distort"] * 0.3 + f["hunt"] * 0.3 + f["fear"] * 0.12, "distort": f["distort"], "flash": f["flash"],
		"flash_color": f["flash_color"], "fade": f["fade"], "letterbox": f["letterbox"], "bright": float(Settings.g("brightness")),
	})
	RenderingServer.global_shader_parameter_set("fear", f["fear"])
	RenderingServer.global_shader_parameter_set("hunt", f["hunt"])
	house.lights.ambient_flicker = clampf((max_fear - 55.0) / 45.0, 0, 1) * 0.35 if phase == "night" else 0.0
	_ghost_presence()
	if phase == "afternoon":
		# the afternoon wanes: about four minutes from the warm sun to dusk
		env.set_daylight(1.0 - phase_t / 240.0)
	house.lights.lifetimes = phase == "night" and mode == "play"
