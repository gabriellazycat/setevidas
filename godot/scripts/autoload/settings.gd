extends Node
## Player options, persisted in user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"sensitivity": 1.0,
	"pad_sensitivity": 1.0,
	"invert_y": false,
	"fov": 68.0,
	"quality": "high",
	"render_scale": 1.0,
	"brightness": 1.0,
	"bloom": true,
	"grain": true,
	"master": 0.85,
	"music": 0.7,
	"sfx": 0.9,
	"ambience": 0.8,
	"subtitles": true,
	"subtitle_size": "m",
	"assist": false,
	"reduce_flashes": false,
	"camera_shake": true,
	"night_speed": 1.0,
	"sneak_toggle": true,
	"cat_name": "Mingau",
	"fullscreen": false,
	"lang": "",   # "" = Portuguese (the options offer English)
}

var data: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in DEFAULTS.keys():
			data[k] = cfg.get_value("settings", k, DEFAULTS[k])
	apply_display()
	apply_locale()


## the game is written in Portuguese (the text itself is the msgid); English comes from i18n/en.po
func locale() -> String:
	var l := str(data.get("lang", ""))
	if l != "":
		return l
	# the game is Brazilian: Portuguese unless English is picked in the options
	return "pt_BR"


func apply_locale() -> void:
	TranslationServer.set_locale(locale())


func g(key: String):
	return data.get(key, DEFAULTS.get(key))


func set_value(key: String, value) -> void:
	data[key] = value
	save()
	if key == "fullscreen" or key == "render_scale":
		apply_display()
	if key == "lang":
		apply_locale()
	changed.emit()


func reset() -> void:
	data = DEFAULTS.duplicate()
	save()
	apply_display()
	changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("settings", k, data[k])
	cfg.save(PATH)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fs: bool = data.get("fullscreen", false)
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and not (not fs and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(mode)
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(float(data.get("render_scale", 1.0)), 0.5, 1.0)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if float(data.get("render_scale", 1.0)) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR


var cat_name: String:
	get:
		return str(data.get("cat_name", "Mingau"))
