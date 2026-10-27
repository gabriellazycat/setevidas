extends Node
## Progress: checkpoints at the start of each morning and night, unlocked nights, endings seen.

const PATH := "user://save.json"
const CLUES := ["foto", "coleira", "chave"]
const LIVES := 7


static func fresh_flags() -> Dictionary:
	return {
		"duct_open": false,
		"basculante_open": false,
		"hatch_open": false,
		"clues": {"foto": null, "coleira": null, "chave": null},
		"marks_seen": [],
		"bath_scene_done": false,
		"boxes": [null, null],      # {x, y, z, yaw, moved, used} once that morning unlocked it
		"nightlight": null,         # {x, y, z} once morning 6 unlocked it
		"flap_open": false,
		"porao_win_open": false,
	}


static func new_save() -> Dictionary:
	var snap := {"day": 1, "phase": "night", "flags": fresh_flags(), "patience": 70.0, "start_fear": 0.0}
	# a new game starts on the afternoon of day 1 (the move); "night" is where night 1 restarts
	var first := {"day": 1, "phase": "afternoon", "flags": fresh_flags(), "patience": 45.0, "start_fear": 0.0}
	return {
		"version": 3,
		"current": first,
		"morning": null,
		"night": snap.duplicate(true),
		"unlocked_night": 1,
		"ever_locked": false,
		"endings_seen": [],
		"stats": {"threats_repelled": 0, "times_locked": 0},
		"nights": {},
		"tips": fresh_tips(),
	}


## what the player was already taught (an optional key: v3 saves without it just start empty):
## introduced = ghosts whose card was shown, hints = one-time hints, howto = per night, the ghosts
## whose "como vencer" card comes back when the night restarts (they took a life there)
static func fresh_tips() -> Dictionary:
	return {"introduced": [], "hints": [], "howto": {}}


static func tips_of(d: Dictionary) -> Dictionary:
	var t = d.get("tips")
	if typeof(t) != TYPE_DICTIONARY:
		t = fresh_tips()
		d["tips"] = t
	for k in fresh_tips():
		if not (t as Dictionary).has(k):
			t[k] = fresh_tips()[k]
	return t


## lives the cat has when night n starts: 7 minus what the earlier nights cost
static func lives_at(d: Dictionary, n: int) -> int:
	var lost := 0
	var nights: Dictionary = d.get("nights", {})
	for i in range(1, n):
		lost += int(nights.get(str(i), {}).get("lost", 0))
	return maxi(0, LIVES - lost)


## lives lost on night n (0 if never played)
static func lost_on(d: Dictionary, n: int) -> int:
	return int(d.get("nights", {}).get(str(n), {}).get("lost", 0))


## records a finished night; a replay only replaces the old result when it lost fewer lives
static func record_night(d: Dictionary, n: int, lost: int) -> void:
	if not d.has("nights"):
		d["nights"] = {}
	var old = d["nights"].get(str(n))
	if old == null or not old.get("done", false) or lost < int(old.get("lost", 0)):
		d["nights"][str(n)] = {"lost": lost, "done": true}


func load_save():
	if not FileAccess.file_exists(PATH):
		return null
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return null
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return null
	return migrate(d)


## v2 saves had no lives: every night played so far counts as lossless
static func migrate(d: Dictionary):
	var v := int(d.get("version", 0))
	if v == 3:
		tips_of(d)
		return d
	if v != 2:
		return null
	d["version"] = 3
	d["nights"] = {}
	for i in range(1, int(d.get("unlocked_night", 1))):
		d["nights"][str(i)] = {"lost": 0, "done": true}
	tips_of(d)
	return d


func write_save(d: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
