extends Node
## Adaptive score: a dark drone and a dissonant tension layer at night that follow the danger, and
## a gentle generative piano (Am - F - C - G) for the menu, mornings, afternoons and the ending,
## with a warm pad in the afternoon. Port of the web Music class.

const CHORDS := [[220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [130.8, 196.0, 261.6], [196.0, 246.9, 293.7]]
const MELODY := [440.0, 493.9, 523.3, 587.3, 659.3, 783.99]

var mode := "none"
var level := 0.0
var drone = null
var tension = null
var pad = null
var _piano_t := 0.0
var _chord := 0


func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	if m == "night" or m == "menu":
		if drone == null:
			drone = Sfx.loop("drone", null, 1.0, "Music")
		drone.set_level(0.35 if m == "menu" else 0.5)
		if tension == null:
			tension = Sfx.loop("tension", null, 1.0, "Music")
		tension.set_level(0.0)
	else:
		if drone:
			drone.set_level(0.0)
		if tension:
			tension.set_level(0.0)
	if m == "afternoon":
		if pad == null:
			pad = Sfx.loop("pad", null, 1.0, "Music")
		pad.set_level(0.5)
	elif pad:
		pad.set_level(0.0)


func _note(freq: float, vel: float, delay := 0.0) -> void:
	var best := ""
	var bd := INF
	for k in Sfx.streams.keys():
		if not str(k).begins_with("piano_"):
			continue
		var f := float(str(k).substr(6)) / 10.0
		var d := absf(log(freq / f))
		if d < bd:
			bd = d
			best = k
	if best == "":
		return
	var f0 := float(best.substr(6)) / 10.0
	Sfx.play(best, null, vel * 2.2, freq / f0, 1.0, "Music", delay)


func tick(dt: float, t_level: float) -> void:
	level = t_level
	if mode == "night":
		# the score keeps out of the calm: the drone barely there, the tension layer only once
		# something is on its way
		if tension:
			tension.set_level(clampf((t_level - 0.15) / 0.85, 0, 1) * 0.95)
		if drone:
			drone.set_level(0.18 + t_level * 0.5)
	if mode in ["menu", "morning", "ending", "afternoon"]:
		_piano_t -= dt
		if _piano_t <= 0:
			var ch: Array = CHORDS[_chord % CHORDS.size()]
			var v := 0.14 if mode == "menu" else 0.1
			_note(ch[0] / 2.0, v * 0.9)
			_note(ch[randi() % 3], v * 0.7, 0.45)
			_note(ch[randi() % 3] * 2.0, v * 0.55, 0.9)
			if randf() < 0.7:
				_note(MELODY[randi() % MELODY.size()], v * 0.6, 1.35)
			_chord += 1
			_piano_t = 4.5 if mode == "afternoon" else 3.6
