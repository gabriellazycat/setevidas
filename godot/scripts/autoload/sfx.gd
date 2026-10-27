extends Node
## The audio engine: buses (music, sfx, ambience, voice, ui), a pool of 3D voices with room
## occlusion (sounds in other rooms go through progressively darker low-pass buses), looping
## emitters with smooth levels, a global muffle (pause menu, locked in the bathroom), and one
## method per sound of the game. The sounds are WAVs made offline (tools/audio/synth.py, CC0 recordings by
## tools/audio/import_cc0.py); only the kibble crunch is generated here.

## an enemy screamed (the cat jumps at it, Game.scare_cat); people and the ritual pass scare = false
signal shrieked(pos: Vector3)

const DIR := "res://assets/audio/"
const OCC_CUTOFF := [20000.0, 2600.0, 1300.0, 650.0]
const OCC_GAIN := [1.0, 0.75, 0.5, 0.33]

var streams := {}          # base name -> Array[AudioStream]
var pool3d: Array = []
var pool2d: Array = []
var loops: Array = []
var occlusion: Callable = Callable()   # Callable(Vector3) -> int hops (0..3)
const STING_GAP := 0.6     # s: stings closer than this are one scare
var _sting_at := -10.0
var _sting_gain := 0.0
var _missing := {}         # sound names already warned about
var muffled := 0.0
var _muffle_fx: AudioEffectLowPassFilter
var _rain_fx: AudioEffectLowPassFilter


class Loop:
	var player: Node
	var level := 0.0
	var target := 0.0
	var base_db := 0.0
	var ref := 1.0
	var stopping := false
	var stop_rate := 1.0
	var spatial := true

	func set_level(v: float) -> void:
		target = maxf(0.0, v)

	func set_pos(p: Vector3) -> void:
		if spatial and is_instance_valid(player):
			(player as Node3D).global_position = p

	func stop(fade_s := 0.4) -> void:
		stopping = true
		target = 0.0
		stop_rate = 1.0 / maxf(0.02, fade_s)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_streams()
	for i in 40:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Sfx"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_distance = 30.0
		p.panning_strength = 0.9
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		pool3d.append(p)
	for i in 16:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "Sfx"
		add_child(p2)
		pool2d.append(p2)
	Settings.changed.connect(apply_volumes)
	apply_volumes()


func _setup_buses() -> void:
	var names := ["Music", "Sfx", "Amb", "Voice", "UI", "Occ1", "Occ2", "Occ3", "Rain"]
	for n in names:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, n)
	for n in names:
		var i := AudioServer.get_bus_index(n)
		AudioServer.set_bus_send(i, "Master")
	# room reverb on effects and voices
	for n in ["Sfx", "Voice"]:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.45
		rv.damping = 0.6
		rv.wet = 0.12
		rv.dry = 1.0
		rv.spread = 0.8
		rv.hipass = 0.15
		AudioServer.add_bus_effect(AudioServer.get_bus_index(n), rv)
	var mrv := AudioEffectReverb.new()
	mrv.room_size = 0.8
	mrv.damping = 0.4
	mrv.wet = 0.22
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), mrv)
	# occluded rooms: darker and further
	for k in [1, 2, 3]:
		var bi := AudioServer.get_bus_index("Occ%d" % k)
		var f := AudioEffectLowPassFilter.new()
		f.cutoff_hz = OCC_CUTOFF[k]
		f.resonance = 0.5
		AudioServer.add_bus_effect(bi, f)
		var rv2 := AudioEffectReverb.new()
		rv2.room_size = 0.6
		rv2.wet = 0.2
		AudioServer.add_bus_effect(bi, rv2)
		AudioServer.set_bus_send(bi, "Sfx")
	_rain_fx = AudioEffectLowPassFilter.new()
	_rain_fx.cutoff_hz = 20000
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Rain"), _rain_fx)
	AudioServer.set_bus_send(AudioServer.get_bus_index("Rain"), "Amb")
	var master := AudioServer.get_bus_index("Master")
	_muffle_fx = AudioEffectLowPassFilter.new()
	_muffle_fx.cutoff_hz = 20000
	AudioServer.add_bus_effect(master, _muffle_fx)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14
	comp.ratio = 3.5
	comp.attack_us = 5000
	comp.release_ms = 250
	AudioServer.add_bus_effect(master, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(master, lim)


## the voices of Clara and Davi (Animal Crossing style): a bank of syllables recorded by a human
## voice (tools/audio/animalese.py), sped up and chained one per syllable of the line, in any language
const VOICE_BANK := "res://assets/audio/voice_bank/"
const VB_RATE := 1.7      # how much the syllables are sped up (pitch rises with it)
const VB_STEP := 0.115    # seconds between two syllables (the "E2" pace)
const VB_CONS := ["b", "d", "f", "g", "k", "l", "m", "n", "p", "r", "s", "t", "v", "x", "j"]
var vbank := {}


func _load_voice_bank() -> void:
	var d := DirAccess.open(VOICE_BANK)
	if d == null:
		return
	for f in d.get_files():
		var fn := f.trim_suffix(".remap").trim_suffix(".import")
		if fn.ends_with(".wav") and not vbank.has(fn.get_basename()):
			var s: AudioStream = load(VOICE_BANK + fn)
			if s:
				vbank[fn.get_basename()] = s
				streams["vb_" + fn.get_basename()] = [s]


## the line cut into consonant+vowel pieces (accents dropped), the way the voice reads it; " " is
## a gap between words, punctuation a pause
static func voice_syllables(text: String) -> Array:
	var t := text.to_lower()
	for pr in [["á", "a"], ["à", "a"], ["â", "a"], ["ã", "a"], ["é", "e"], ["ê", "e"], ["í", "i"], ["ó", "o"], ["ô", "o"], ["õ", "o"], ["ú", "u"],
			["ç", "s"], ["ch", "x"], ["sh", "x"], ["qu", "k"], ["c", "k"], ["h", ""], ["w", "v"], ["y", "i"], ["z", "s"], ["lh", "l"], ["nh", "n"], ["q", "k"]]:
		t = t.replace(pr[0], pr[1])
	var out := []
	var word := ""
	for ch in t + " ":
		if ch >= "a" and ch <= "z":
			word += ch
			continue
		var i := 0
		while i < word.length():
			var c := word[i]
			if c in "aeiou":
				out.append(["", c])
				i += 1
			elif i + 1 < word.length() and word[i + 1] in "aeiou":
				out.append([c if c in VB_CONS else "", word[i + 1]])
				i += 2
			else:
				i += 1
		if word != "":
			out.append(" ")
		word = ""
		if ch in "?!.,":
			out.append(ch)
	return out


func _load_streams() -> void:
	_load_voice_bank()
	var d := DirAccess.open(DIR)
	if d == null:
		return
	var files := []
	for f in d.get_files():
		var fn := f.trim_suffix(".remap").trim_suffix(".import")
		if fn.ends_with(".wav") and not files.has(fn):
			files.append(fn)
	for f in files:
		var s: AudioStream = load(DIR + f)
		if s == null:
			continue
		var nm: String = f.get_basename()
		var parts := nm.rsplit("_", true, 1)
		var base := nm
		if parts.size() == 2 and parts[1].is_valid_int():
			base = parts[0]
		if nm.begins_with("loop_") or nm.begins_with("music_") or nm == "cat_purr_loop":
			var w := s as AudioStreamWAV
			if w:
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				w.loop_end = int(w.get_length() * w.mix_rate)
		if not streams.has(base):
			streams[base] = []
		streams[base].append(s)
		if base != nm:
			streams[nm] = [s]


func apply_volumes() -> void:
	var s := Settings
	_bus_vol("Master", s.g("master"))
	_bus_vol("Sfx", s.g("sfx"))
	_bus_vol("Voice", s.g("sfx"))
	_bus_vol("UI", s.g("sfx") * 0.7)
	_bus_vol("Amb", s.g("ambience") * _duck_k)
	_bus_vol("Music", s.g("music") * 0.8 * _duck_k)


## ducking: the room tone and the score sink under a scare (and into the hush before one), so the
## sting stands out and the silence is felt. amount 0..1 of the way down, held `hold` seconds
var _duck := 0.0
var _duck_hold := 0.0
var _duck_k := 1.0


func duck(amount: float, hold := 0.8) -> void:
	_duck = maxf(_duck, clampf(amount, 0.0, 1.0))
	_duck_hold = maxf(_duck_hold, hold)


func _tick_duck(dt: float) -> void:
	_duck_hold -= dt
	if _duck_hold <= 0.0:
		_duck = move_toward(_duck, 0.0, dt * 0.35)
	var k := 1.0 - _duck * 0.9
	if absf(k - _duck_k) > 0.002:
		_duck_k = lerpf(_duck_k, k, 1.0 - exp(-10.0 * dt))
		apply_volumes()


func _bus_vol(n: String, v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(n), linear_to_db(maxf(0.0001, float(v))))


## muffle everything (0..1): pause menu, being locked in
func set_muffle(v: float) -> void:
	muffled = v


func set_rain_indoor(k: float) -> void:
	_rain_fx.cutoff_hz = lerpf(20000.0, 900.0, k)


func _process(dt: float) -> void:
	_tick_duck(dt)
	var tgt := 20000.0 * pow(0.03, muffled)
	_muffle_fx.cutoff_hz = lerpf(_muffle_fx.cutoff_hz, tgt, 1.0 - exp(-8.0 * dt))
	for lp: Loop in loops.duplicate():
		var rate := lp.stop_rate if lp.stopping else 1.6
		lp.level = move_toward(lp.level, lp.target, rate * dt * maxf(0.3, absf(lp.target - lp.level) * 3.0 + 0.2))
		var occ_k := 1.0
		if lp.spatial and is_instance_valid(lp.player):
			var h := _occ((lp.player as Node3D).global_position)
			occ_k = OCC_GAIN[h]
			var bus := "Sfx" if h == 0 else "Occ%d" % h
			if (lp.player as AudioStreamPlayer3D).bus != bus and not (lp.player as AudioStreamPlayer3D).bus in ["Amb", "Music", "Voice"]:
				(lp.player as AudioStreamPlayer3D).bus = bus
		var db := lp.base_db + linear_to_db(maxf(0.00001, lp.level * occ_k))
		if lp.player is AudioStreamPlayer3D:
			(lp.player as AudioStreamPlayer3D).volume_db = db
		elif lp.player is AudioStreamPlayer:
			(lp.player as AudioStreamPlayer).volume_db = db
		if lp.stopping and lp.level <= 0.001:
			lp.player.queue_free()
			loops.erase(lp)


func _occ(p: Vector3) -> int:
	if occlusion.is_valid():
		return clampi(int(occlusion.call(p)), 0, 3)
	return 0


# ---------------------------------------------------------------------- playback core


func _pick(name: String) -> AudioStream:
	var a: Array = streams.get(name, [])
	if a.is_empty():
		return null
	return a[randi() % a.size()]


## play a one-shot. pos == null -> flat (non-positional).
func play(name: String, pos = null, gain := 1.0, pitch := 1.0, ref := 1.5, bus := "Sfx", delay := 0.0) -> void:
	var s := _pick(name)
	if s == null:
		if not streams.is_empty() and not _missing.has(name):
			_missing[name] = true
			push_warning("Sfx: no sound named '%s'" % name)
		return
	if delay > 0.0:
		get_tree().create_timer(delay, true).timeout.connect(func(): _play_now(s, pos, gain, pitch, ref, bus))
		return
	_play_now(s, pos, gain, pitch, ref, bus)


func _play_now(s: AudioStream, pos, gain: float, pitch: float, ref: float, bus: String) -> void:
	if gain <= 0.0005:
		return
	if pos == null:
		var p2 := _free2d()
		p2.stream = s
		p2.bus = bus
		p2.volume_db = linear_to_db(gain)
		p2.pitch_scale = maxf(0.05, pitch)
		p2.play()
		return
	var p := _free3d()
	var hops := _occ(pos)
	p.stream = s
	p.global_position = pos
	p.unit_size = ref * 2.0
	p.bus = bus if hops == 0 or bus != "Sfx" else "Occ%d" % hops
	if bus == "Voice" and hops > 0:
		p.bus = "Occ%d" % hops
	p.volume_db = linear_to_db(gain * OCC_GAIN[hops])
	p.pitch_scale = maxf(0.05, pitch)
	p.play()


func _free3d() -> AudioStreamPlayer3D:
	var best: AudioStreamPlayer3D = pool3d[0]
	var best_pos := -1.0
	for p: AudioStreamPlayer3D in pool3d:
		if not p.playing:
			return p
		var pp := p.get_playback_position()
		if pp > best_pos:
			best_pos = pp
			best = p
	best.stop()
	return best


## a full flat pool gives up its oldest sound, never a sting or a thunderclap
func _free2d() -> AudioStreamPlayer:
	var best: AudioStreamPlayer = null
	var best_pos := -1.0
	for p: AudioStreamPlayer in pool2d:
		if not p.playing:
			return p
		if p.stream in streams.get("sting", []) or p.stream in streams.get("thunder", []):
			continue
		var pp := p.get_playback_position()
		if pp > best_pos:
			best_pos = pp
			best = p
	if best == null:
		best = pool2d[0]
	best.stop()
	return best


## a looping emitter. pos == null -> flat. Returns a Loop handle (set_level / set_pos / stop).
func loop(kind: String, pos = null, ref := 1.0, bus := "Sfx") -> Loop:
	var nm: String = {"static": "loop_static", "whisper": "loop_whisper", "water": "loop_water", "rain": "loop_rain", "fridge": "loop_fridge",
		"hum": "loop_hum", "wind": "loop_wind", "rumble": "loop_rumble", "drone": "music_drone", "tension": "music_tension",
		"pad": "music_pad", "purr": "cat_purr_loop", "tv": "loop_tv"}.get(kind, kind)
	var s := _pick(nm)
	var h := Loop.new()
	h.ref = ref
	if pos == null:
		var p2 := AudioStreamPlayer.new()
		p2.stream = s
		p2.bus = bus
		p2.volume_db = -80
		add_child(p2)
		p2.play(randf() * maxf(0.0, s.get_length() - 0.1) if s else 0.0)
		h.player = p2
		h.spatial = false
	else:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.bus = bus
		p.unit_size = ref * 2.0
		p.max_distance = 30.0
		p.volume_db = -80
		add_child(p)
		p.global_position = pos
		p.play(randf() * maxf(0.0, s.get_length() - 0.1) if s else 0.0)
		h.player = p
	loops.append(h)
	return h


# ---------------------------------------------------------------------- the cat


func meow(pos, pitch := 1.0) -> void:
	play("cat_meow", pos, 0.75, pitch * randf_range(0.96, 1.05), 1.5, "Voice")


func mrrp(pos) -> void:
	play("cat_mrrp", pos, 0.55, randf_range(0.97, 1.04), 1.2, "Voice")


func hiss(pos, strong: bool) -> void:
	if strong:
		play("cat_hiss", pos, 0.85, randf_range(0.95, 1.05), 1.6)
	else:
		play("cat_hiss_weak", pos, 0.5, randf_range(0.95, 1.05), 1.2)


func purr() -> Loop:
	return loop("purr", null, 1.0, "Voice")


func cat_cry(pos, gain := 0.8) -> void:
	play("cat_cry", pos, gain, randf_range(0.95, 1.05), 2.0, "Voice")


func paw_step(pos: Vector3, run: bool, sneak: bool, surface := "wood") -> void:
	var g := 0.18 if sneak else (0.5 if run else 0.32)
	play("paw_%s%s" % [surface, "_run" if run else ""], pos, g, randf_range(0.9, 1.12), 0.6)


## the cat eating: a few dry crunches (made here: there is no recording of kibble)
func chew(pos: Vector3, gain := 0.35) -> void:
	if not streams.has("cat_chew"):
		streams["cat_chew"] = [_make_crunch(11), _make_crunch(23), _make_crunch(37)]
	play("cat_chew", pos, gain, randf_range(0.9, 1.12), 0.5)


## ~0.14 s of short noise bursts with a fast decay, a little low-passed: one bite of dry food
static func _make_crunch(seed_v: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.14)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var bursts := [0.0, 0.035 + rng.randf() * 0.01, 0.07 + rng.randf() * 0.02]
	for i in n:
		var ts := float(i) / rate
		var env := 0.0
		for b: float in bursts:
			if ts >= b:
				env = maxf(env, exp(-(ts - b) * 90.0))
		var x := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, x, 0.55)
		var v := clampf((x - lp * 0.6) * env * 0.8, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


# ---------------------------------------------------------------------- people


func human_step(pos: Vector3, creak := false) -> void:
	play("step_creak" if creak else "step", pos, 0.55, randf_range(0.92, 1.08), 1.2)


## mumbled speech ("game language"): one soft syllable per few letters, with the melody of the
## line: a question rises at the end, a statement falls, "!" lifts the stressed syllable, commas and
## "..." leave little pauses; scared talk is faster and higher, annoyed lower and clipped
func voice(pos, syllables: int, kind: String, pitch := 1.0, text := "") -> void:
	var male := pitch < 0.8
	if text != "" and not vbank.is_empty():
		_bank_voice(pos, text, kind, "davi" if male else "clara")
		return
	var set_name := "voice_w" if kind == "whisper" else ("voice_m" if male else "voice_f")
	var gain: float = {"whisper": 0.45, "call": 0.95, "scared": 0.8, "annoyed": 0.85}.get(kind, 0.75)
	var p0: float = {"scared": 1.1, "call": 1.05, "annoyed": 0.95}.get(kind, 1.0)
	var gap: float = {"scared": 0.085, "call": 0.13, "annoyed": 0.095}.get(kind, 0.105)
	var tx := text.strip_edges()
	var question := tx.ends_with("?")
	var exclaim := tx.ends_with("!")
	# pauses where the line has commas / ellipses, spread over the syllables by position
	var pauses := []
	var L := maxi(1, tx.length())
	for k in tx.length():
		if tx[k] == "," or tx[k] == "." and k < tx.length() - 1:
			pauses.append(float(k) / L)
	var t := 0.0
	var n := clampi(syllables, 1, 28)
	for i in n:
		var u := float(i) / maxf(1.0, n - 1)
		var melody := 1.0 + sin(i * 1.7) * 0.035
		if question:
			melody *= 1.0 + smoothstep(0.6, 1.0, u) * 0.22
		else:
			melody *= 1.0 - smoothstep(0.65, 1.0, u) * 0.1
		if exclaim and i == 0:
			melody *= 1.12
		var pp: float = p0 * melody * randf_range(0.985, 1.015)
		var gg: float = gain * randf_range(0.85, 1.0) * (1.15 if exclaim and i < 2 else 1.0)
		play(set_name, pos, gg, pp, 1.8, "Voice", t)
		t += gap * randf_range(0.9, 1.15)
		for pz in pauses:
			if absf(u - pz) < 0.5 / n:
				t += 0.16


func _bank_voice(pos, text: String, kind: String, who: String) -> void:
	var sy := voice_syllables(text)
	if OS.get_cmdline_user_args().has("--voicelog"):
		print("VOICE %s %s: %s" % [who, kind, text])
	var n := 0
	for s in sy:
		if s is Array:
			n += 1
	if n == 0:
		return
	# "whisper" is her own voice, sleepy: softer, a little lower and slower (not the ghostly bank)
	var rate: float = VB_RATE * (0.88 if who == "davi" else 1.0) * {"scared": 1.08, "annoyed": 0.95, "call": 1.03, "whisper": 0.94}.get(kind, 1.0)
	var step: float = VB_STEP * {"scared": 0.85, "call": 1.1, "whisper": 1.2}.get(kind, 1.0)
	var gain: float = {"call": 1.05, "scared": 0.9, "annoyed": 0.95, "whisper": 0.55}.get(kind, 0.85)
	var tx := text.strip_edges()
	var q := tx.ends_with("?")
	var t := 0.0
	var k := 0
	for s in sy:
		if s is String:
			t += step * (0.35 if s == " " else (1.4 if s == "," else 2.5))
			continue
		var u := float(k) / maxf(1.0, n - 1)
		var mel := 1.0 + 0.04 * sin(k * 1.7)
		if q:
			mel += 0.18 * maxf(0.0, (u - 0.6) / 0.4)
		else:
			mel -= 0.06 * maxf(0.0, (u - 0.65) / 0.35)
		var nm := "vb_%s_%s%s" % [who, s[0] if s[0] != "" else "_", s[1]]
		if streams.has(nm):
			play(nm, pos, gain * randf_range(0.9, 1.0), rate * mel, 1.8, "Voice", t)
		t += step * randf_range(0.9, 1.1)
		k += 1


# ---------------------------------------------------------------------- house


func click(pos, gain := 0.4) -> void:
	play("click", pos, gain, randf_range(0.95, 1.05), 0.8)


func creak(pos, gain := 0.5, length := 1.4, pitch := 1.0) -> void:
	var nm := "creak_door" if length > 1.1 else "creak_floor"
	if length > 2.2:
		nm = "creak_long"
	play(nm, pos, gain, pitch * randf_range(0.92, 1.08), 1.8)


func thud(pos, gain := 0.6, low := 70.0) -> void:
	play("thud", pos, gain, clampf(low / 85.0, 0.4, 2.5) * randf_range(0.95, 1.05), 1.8)


func knock(pos: Vector3, count := 3, strength := 1.0) -> void:
	var t := 0.0
	for i in count:
		play("knock", pos, 0.9 * strength * randf_range(0.85, 1.0), randf_range(0.95, 1.05), 2.0, "Sfx", t)
		t += randf_range(0.22, 0.3) if i % 3 != 2 else 0.55


func glass(pos: Vector3) -> void:
	play("glass", pos, 0.8, randf_range(0.95, 1.05), 2.0)


func drip(pos: Vector3) -> void:
	play("drip", pos, 0.35, randf_range(0.85, 1.2), 0.8)


func porcelain(pos: Vector3) -> void:
	play("porcelain", pos, 0.45, randf_range(0.95, 1.05), 1.0)


func giggle(pos) -> void:
	play("giggle", pos, 0.5, randf_range(0.92, 1.0), 1.4, "Voice")


func bell(pos, count := 1, gain := 0.4) -> void:
	for i in clampi(count, 1, 12):
		play("bell", pos, gain, 1.0, 3.0, "Sfx", i * 1.6)


func tick(pos: Vector3) -> void:
	play("tick" if (Time.get_ticks_msec() / 1000) % 2 == 0 else "tock", pos, 0.12, 1.0, 0.5)


func buzz(pos: Vector3, dur := 3.0) -> void:
	play("buzz", pos, 0.35, clampf(3.2 / maxf(0.5, dur), 0.8, 1.3), 1.0)


func crawl(gain := 0.5) -> void:
	play("crawl", null, gain, randf_range(0.95, 1.05))


# ---------------------------------------------------------------------- ghosts & the hound


func growl(pos, gain := 0.6, dur := 1.5) -> void:
	play("growl_short" if dur < 0.9 else "growl", pos, gain, randf_range(0.9, 1.05), 2.0)


func sniff(pos, gain := 0.4) -> void:
	play("sniff", pos, gain, randf_range(0.9, 1.1), 1.0)


func claws(pos: Vector3, gain := 0.4) -> void:
	play("claws", pos, gain, randf_range(0.85, 1.15), 0.8)


func bark(pos, gain := 0.8) -> void:
	play("bark", pos, gain, randf_range(0.72, 0.82), 3.0)


func shriek(pos, gain := 0.7, scare := true) -> void:
	play("shriek", pos, gain, randf_range(0.9, 1.08), 3.0)
	if scare and pos is Vector3:
		shrieked.emit(pos)


func breath(pos, gain := 0.5) -> void:
	play("breath", pos, gain, randf_range(0.8, 0.95), 1.5)


## afternoons: the car on the dirt road, its horn, Davi's sneeze, keys, the front-door lock, the dust
## sheet, a bulb dying, the slow voice on the TV
func car_arrive(pos: Vector3) -> void:
	play("car_arrive", pos, 0.9, 1.0, 6.0)


func horn(pos: Vector3) -> void:
	play("horn", pos, 0.8, 1.0, 6.0)


func sneeze(pos: Vector3) -> void:
	play("sneeze", pos, 0.7, randf_range(0.96, 1.04), 2.0)


func keys(pos: Vector3) -> void:
	play("keys", pos, 0.5, randf_range(0.95, 1.05), 1.0)


func lock_turn(pos: Vector3) -> void:
	play("lock_turn", pos, 0.6, 1.0, 1.2)


func puff(pos: Vector3) -> void:
	play("puff", pos, 0.6, 1.0, 1.5)


func bulb_pop(pos: Vector3) -> void:
	play("bulb_pop", pos, 0.7, 1.0, 1.5)


func tv_vem(pos: Vector3) -> void:
	play("tv_vem", pos, 1.0, 1.0, 2.5)


func sting(gain := 0.6) -> void:
	if Settings.g("reduce_flashes"):
		gain *= 0.5
	# two threats scaring in the same breath are one scare: the second only counts if it is louder
	var now := Time.get_ticks_msec() / 1000.0
	if now - _sting_at < STING_GAP and gain <= _sting_gain:
		return
	_sting_at = now
	_sting_gain = gain
	duck(0.85, 1.2)
	play("sting", null, gain * 1.25, randf_range(0.97, 1.03), 1.0, "Sfx")


func heartbeat(gain: float, pos = null) -> void:
	play("heartbeat", pos, gain, 1.0, 1.0)


func thunder(delay: float, power := 1.0) -> void:
	play("thunder", null, 0.55 * power, randf_range(0.9, 1.05), 1.0, "Rain", delay)


func ui(kind: String) -> void:
	play("ui_" + kind, null, 0.35, 1.0, 1.0, "UI")
