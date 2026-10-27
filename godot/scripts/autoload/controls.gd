extends Node
## Input actions (keyboard, mouse and gamepad) are registered here so they can be rebound in code.
## Also tracks which device was used last, to show the right glyphs in prompts.

enum Device { KBM, PAD }

var last_device := Device.KBM
var look_delta := Vector2.ZERO  # mouse motion accumulated this frame

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"meow": [KEY_Q],
	"hiss": [KEY_F],
	"run": [KEY_SHIFT],
	"sneak": [KEY_CTRL, KEY_C],
	"info": [KEY_TAB],
	"pause": [KEY_ESCAPE],
	"ui_back": [KEY_ESCAPE, KEY_BACKSPACE],
}
const MOUSE := {"interact": MOUSE_BUTTON_LEFT}
const PAD := {
	"jump": JOY_BUTTON_A,
	"interact": JOY_BUTTON_X,
	"meow": JOY_BUTTON_Y,
	"hiss": JOY_BUTTON_RIGHT_SHOULDER,
	"sneak": JOY_BUTTON_B,
	"info": JOY_BUTTON_BACK,
	"pause": JOY_BUTTON_START,
	"ui_back": JOY_BUTTON_B,
}
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"run": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}

const LABELS := {
	"jump": ["Espaço", "A"],
	"interact": ["E", "X"],
	"meow": ["Q", "Y"],
	"hiss": ["F", "RB"],
	"run": ["Shift", "RT"],
	"sneak": ["Ctrl", "B"],
	"info": ["Tab", "Select"],
	"pause": ["Esc", "Start"],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for action in BINDINGS.keys():
		_ensure(action)
		for k in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in MOUSE.keys():
		_ensure(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE[action]
		InputMap.action_add_event(action, mb)
	for action in PAD.keys():
		_ensure(action)
		var jb := InputEventJoypadButton.new()
		jb.button_index = PAD[action]
		InputMap.action_add_event(action, jb)
	for action in PAD_AXES.keys():
		_ensure(action)
		var jm := InputEventJoypadMotion.new()
		jm.axis = PAD_AXES[action][0]
		jm.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, jm)
	for a in ["move_forward", "move_back", "move_left", "move_right", "look_up", "look_down", "look_left", "look_right"]:
		InputMap.action_set_deadzone(a, 0.2)
	InputMap.action_set_deadzone("run", 0.4)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			look_delta += (event as InputEventMouseMotion).relative
		last_device = Device.KBM
	elif event is InputEventKey or event is InputEventMouseButton:
		last_device = Device.KBM
	elif event is InputEventJoypadButton:
		last_device = Device.PAD
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.35:
		last_device = Device.PAD


func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_back", "move_forward")


func pad_look() -> Vector2:
	return Input.get_vector("look_left", "look_right", "look_up", "look_down")


func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d


func key_label(action: String) -> String:
	var l: Array = LABELS.get(action, [action, action])
	return l[1] if last_device == Device.PAD else l[0]


func capture(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
