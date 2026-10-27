class_name GameUI
extends CanvasLayer
## Every screen and HUD element: loading, menu, pause, settings, fail / summary / ending / credits
## panels, letterboxed story cards, subtitles, hints, title and threat cards, the interact prompt
## with its hold ring ("Segure" under it when the button has to be held), the hiss prompt, the attack
## alert, the tasks (always on screen while playing) with the "como vencer" cards under them, the
## ghosts under way, the objective marker, clock and assist bars. Built in
## code on Godot Controls with the original's look (Cormorant Garamond + Inter, amber accents).
## Port of UI.ts + style.css.

signal sound(kind)   # hover | select | back

const C_TEXT := Color("#e9e1d3")
const C_MUTED := Color("#9a958c")
const C_AMBER := Color("#e8b46a")
const C_CYAN := Color("#7ff4ff")
const C_RED := Color("#d9574a")
const C_PANEL := Color(0.035, 0.043, 0.067, 0.88)
const C_LINE := Color(0.91, 0.84, 0.73, 0.14)

var serif: FontFile
var serif_i: FontFile
var serif_m: FontFile
var sans: FontFile
var sans_m: FontFile
var sans_b: FontFile
var theme_: Theme

var hud: Control
var overlay_root: Control
var overlay: Control = null
var back_handler: Callable = Callable()
var skip_handler: Callable = Callable()
## frame an overlay was closed by ESC/back, so the same key press doesn't reopen the pause
var back_frame := -1
var loading_el: Control = null

var _prompt: Control
var _prompt_ring: HoldRing
var _prompt_text: Label
var _prompt_placed := false
var _prompt_state := ""
var _subs: VBoxContainer
var _hints: VBoxContainer
var _title: VBoxContainer
var _title_big: Label
var _title_small: Label
var _title_tw: Tween
var _threat: VBoxContainer
var _threat_nm: Label
var _threat_ds: Label
var _threat_tw: Tween
var _side: VBoxContainer          # top right, under the lives: the tasks, then the "como vencer" cards
var _tasks: PanelContainer
var _tasks_box: VBoxContainer
var _tasks_key := ""
var _tasks_on := false
var _tasks_tw: Tween
var _howto_box: VBoxContainer
var _howto_ids: Array = []
var _objective: ObjectiveMarker
var _clock: VBoxContainer
var _clock_big: Label
var _clock_small: Label
var _assist: VBoxContainer
var _arrow: DangerArrow
var _click: Label
var _alert: PanelContainer
var _alert_nm: Label
var _alert_ds: Label
var _alert_key := ""
var _hiss: PanelContainer
var _hiss_lbl: RichTextLabel
var _hiss_state := ""
var _lives: HBoxContainer
var _vitals: HBoxContainer       # bottom left: Clara and Davi (red, empty = broken by fear), the cat (green, empty = exhausted)
var _vital_icons := {}
var _lives_shown := -1


class HoldRing extends Control:
	var progress := 0.0
	var key := "E"
	var font: Font
	var needs_hold := false   # "Segure" under the ring: this button is held, not tapped

	func _draw() -> void:
		var c := size / 2
		var r := minf(size.x, size.y) / 2 - 2
		draw_circle(c, r, Color(0, 0, 0, 0.35))
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.25), 1.5, true)
		if needs_hold:
			# a dashed track around it: the ring will fill
			for i in 12:
				var a0 := -PI / 2 + i * TAU / 12.0
				draw_arc(c, r + 3.0, a0, a0 + TAU / 24.0, 4, Color(0.91, 0.71, 0.42, 0.45), 1.2, true)
		if progress > 0.001:
			draw_arc(c, r, -PI / 2, -PI / 2 + TAU * progress, 48, Color("#e8b46a"), 2.4, true)
		if font:
			var fs := 12 if key.length() <= 2 else 9
			var w := font.get_string_size(key, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			draw_string(font, Vector2(c.x - w / 2, c.y + fs * 0.36), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f2ead9"))
			if needs_hold:
				var hs := 10
				var label := "Segure"
				var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, hs).x
				var at := Vector2(c.x - lw / 2, size.y + 13)
				draw_string(font, at + Vector2(0, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(0, 0, 0, 0.85))
				draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color("#e8b46a"))


## where to go: a marker over the target when it is on screen, an arrow at the edge pointing to it
## when it is not (UI.objective)
class ObjectiveMarker extends Control:
	var on_screen := true
	var angle := 0.0          # off screen: where the arrow points, 0 = up, clockwise
	var dist := 0.0
	var font: Font
	var t := 0.0

	func _draw() -> void:
		var c := size / 2
		var gold := Color(0.91, 0.71, 0.42, 0.92)
		var shade := Color(0, 0, 0, 0.55)
		if on_screen:
			# a small diamond bobbing over the target, the distance under it
			var p := c + Vector2(0, sin(t * 3.0) * 3.0)
			var pts := PackedVector2Array([p + Vector2(0, -9), p + Vector2(7, 0), p + Vector2(0, 9), p + Vector2(-7, 0)])
			var sh := PackedVector2Array()
			for q in pts:
				sh.append(q + Vector2(0, 1.5))
			draw_colored_polygon(sh, shade)
			draw_colored_polygon(pts, gold)
			var ring := pts.duplicate()
			ring.append(pts[0])
			draw_polyline(ring, Color(1, 0.95, 0.85, 0.9), 1.2, true)
		else:
			var dir := Vector2(0, -1).rotated(angle)
			var side := Vector2(-dir.y, dir.x)
			var tip := c + dir * 16.0
			var tri := PackedVector2Array([tip, c - dir * 6.0 + side * 11.0, c - dir * 1.0, c - dir * 6.0 - side * 11.0])
			var sh2 := PackedVector2Array()
			for q in tri:
				sh2.append(q + Vector2(0, 1.5))
			draw_colored_polygon(sh2, shade)
			draw_colored_polygon(tri, gold)
		if font and dist >= 2.0:
			var txt := tr("%d m") % roundi(dist)
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
			var at := c + Vector2(-w / 2, 26 if on_screen else 30)
			draw_string(font, at + Vector2(0, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, shade)
			draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f2ead9"))


## one of the seven lives: a little cat head. 0 = still there, 1 = lost tonight (struck in red),
## 2 = lost on an earlier night (faded)
class CatLife extends Control:
	var state := 0
	var strike := 1.0

	func _init(st := 0, sz := 22.0) -> void:
		state = st
		custom_minimum_size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := Vector2(size.x / 2, size.y * 0.58)
		var r := s * 0.34
		var col := Color("#f4efe6") if state != 2 else Color(0.95, 0.93, 0.9, 0.18)
		var ear := r * 0.95
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.95, -r * 0.2), c + Vector2(-r * 0.78, -r - ear * 0.55), c + Vector2(-r * 0.1, -r * 0.82)]), col)
		draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.95, -r * 0.2), c + Vector2(r * 0.78, -r - ear * 0.55), c + Vector2(r * 0.1, -r * 0.82)]), col)
		draw_circle(c, r, col)
		if state != 2:
			var eye := Color(0.08, 0.07, 0.08, 0.85)
			draw_circle(c + Vector2(-r * 0.38, -r * 0.05), r * 0.13, eye)
			draw_circle(c + Vector2(r * 0.38, -r * 0.05), r * 0.13, eye)
		if state == 1 and strike > 0.0:
			var a := Vector2(size.x * 0.12, size.y * 0.88)
			var b := Vector2(size.x * 0.88, size.y * 0.12)
			draw_line(a, a.lerp(b, strike), Color("#d9574a"), maxf(2.0, s * 0.11), true)


## a silhouette that empties from the top as `level` (1 = full .. 0 = empty): a person (Clara, Davi) or the cat.
## A faint full outline stays behind; a clipped copy in the colour of the bar shows what is left.
class VitalIcon extends Control:
	var kind := "person"
	var level := 1.0
	var col := Color("#d9574a")
	var _fill: Control
	var _t := 0.0

	func _init(k := "person", c := Color("#d9574a")) -> void:
		kind = k
		col = c
		custom_minimum_size = Vector2(32, 54)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fill = Control.new()
		_fill.clip_contents = true
		_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fill.draw.connect(_draw_fill)
		add_child(_fill)

	func set_level(v: float) -> void:
		level = clampf(v, 0.0, 1.0)
		var h := size.y * level
		_fill.position = Vector2(0, size.y - h)
		_fill.size = Vector2(size.x, h)
		_fill.queue_redraw()
		queue_redraw()

	func _process(dt: float) -> void:
		_t += dt
		# nearly empty: the whole icon breathes so it cannot be missed
		modulate.a = 1.0 if level > 0.25 else 0.55 + 0.45 * absf(sin(_t * 5.0))

	func _draw() -> void:
		_paint(self, Color(0.04, 0.04, 0.05, 0.55), Vector2(1.2, 1.2))
		_paint(self, Color(0.96, 0.93, 0.88, 0.3), Vector2.ZERO)

	func _draw_fill() -> void:
		_paint(_fill, col, Vector2(0, -_fill.position.y))

	## the silhouette in a 26 x 44 box scaled to the control, shifted by `off` (pixels)
	func _paint(c: CanvasItem, color: Color, off: Vector2) -> void:
		var k := Vector2(size.x / 26.0, size.y / 44.0)
		var pts: Array = []
		if kind == "person":
			c.draw_circle(off + Vector2(13, 7) * k, 5.6 * minf(k.x, k.y), color)
			pts = [Vector2(7, 14), Vector2(19, 14), Vector2(22, 17), Vector2(22, 30), Vector2(18.5, 30), Vector2(18.5, 43), Vector2(13.8, 43), Vector2(13.8, 32), Vector2(12.2, 32), Vector2(12.2, 43), Vector2(7.5, 43), Vector2(7.5, 30), Vector2(4, 30), Vector2(4, 17)]
		else:
			# a sitting cat seen from the front: ears, head, body, tail curling round the paws
			c.draw_circle(off + Vector2(13, 13) * k, 6.6 * minf(k.x, k.y), color)
			c.draw_colored_polygon(PackedVector2Array([off + Vector2(6.8, 11) * k, off + Vector2(7.2, 2.6) * k, off + Vector2(12, 7.2) * k]), color)
			c.draw_colored_polygon(PackedVector2Array([off + Vector2(19.2, 11) * k, off + Vector2(18.8, 2.6) * k, off + Vector2(14, 7.2) * k]), color)
			pts = [Vector2(8, 19), Vector2(18, 19), Vector2(21, 27), Vector2(22, 36), Vector2(21, 43), Vector2(5, 43), Vector2(4, 36), Vector2(5, 27)]
			c.draw_colored_polygon(PackedVector2Array([off + Vector2(20, 38) * k, off + Vector2(25, 36) * k, off + Vector2(25.5, 30) * k, off + Vector2(23.4, 29.4) * k, off + Vector2(23, 34) * k, off + Vector2(20, 35) * k]), color)
		var poly := PackedVector2Array()
		for q: Vector2 in pts:
			poly.append(off + q * k)
		c.draw_colored_polygon(poly, color)


class DangerArrow extends Control:
	var angle := 0.0

	func _draw() -> void:
		var c := size / 2
		var tip := Vector2(0, -38).rotated(angle)
		var l := Vector2(-11, -22).rotated(angle)
		var r := Vector2(11, -22).rotated(angle)
		draw_colored_polygon(PackedVector2Array([c + tip, c + l, c + (tip * 0.62), c + r]), Color(0.85, 0.34, 0.29, 0.85))


# ====================================================================== setup


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	serif = load("res://assets/fonts/cormorant-garamond-latin-400-normal.woff2")
	serif_i = load("res://assets/fonts/cormorant-garamond-latin-400-italic.woff2")
	serif_m = load("res://assets/fonts/cormorant-garamond-latin-500-normal.woff2")
	sans = load("res://assets/fonts/inter-latin-400-normal.woff2")
	sans_m = load("res://assets/fonts/inter-latin-500-normal.woff2")
	sans_b = load("res://assets/fonts/inter-latin-600-normal.woff2")
	_make_theme()
	hud = _full(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	overlay_root = _full(Control.new())
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.theme = theme_
	add_child(overlay_root)
	_build_hud()
	Settings.changed.connect(_apply_sub_size)


func _make_theme() -> void:
	theme_ = Theme.new()
	theme_.default_font = sans
	theme_.default_font_size = 15
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.content_margin_left = 2
	flat.content_margin_right = 2
	flat.content_margin_top = 6
	flat.content_margin_bottom = 6
	var hover := flat.duplicate()
	hover.border_color = C_AMBER
	hover.border_width_left = 2
	hover.content_margin_left = 14
	theme_.set_stylebox("normal", "Button", flat)
	theme_.set_stylebox("hover", "Button", hover)
	theme_.set_stylebox("focus", "Button", hover)
	theme_.set_stylebox("pressed", "Button", hover)
	theme_.set_stylebox("disabled", "Button", flat)
	theme_.set_font("font", "Button", serif_m)
	theme_.set_font_size("font_size", "Button", 30)
	theme_.set_color("font_color", "Button", C_TEXT)
	theme_.set_color("font_hover_color", "Button", Color("#fff3df"))
	theme_.set_color("font_focus_color", "Button", Color("#fff3df"))
	theme_.set_color("font_pressed_color", "Button", C_AMBER)
	theme_.set_color("font_disabled_color", "Button", Color(0.6, 0.58, 0.55, 0.35))
	var panel := StyleBoxFlat.new()
	panel.bg_color = C_PANEL
	panel.border_color = C_LINE
	panel.set_border_width_all(1)
	panel.set_content_margin_all(34)
	panel.content_margin_left = 40
	panel.content_margin_right = 40
	panel.shadow_color = Color(0, 0, 0, 0.6)
	panel.shadow_size = 40
	theme_.set_stylebox("panel", "PanelContainer", panel)
	theme_.set_color("font_color", "Label", C_TEXT)
	theme_.set_font("normal_font", "RichTextLabel", sans)
	theme_.set_font("bold_font", "RichTextLabel", sans_b)
	theme_.set_font("italics_font", "RichTextLabel", serif_i)
	theme_.set_color("default_color", "RichTextLabel", C_TEXT)
	# sliders, toggles, selects, text fields
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.12)
	grab.content_margin_top = 2
	grab.content_margin_bottom = 2
	theme_.set_stylebox("slider", "HSlider", grab)
	var fill := grab.duplicate()
	fill.bg_color = C_AMBER.darkened(0.15)
	theme_.set_stylebox("grabber_area", "HSlider", fill)
	theme_.set_stylebox("grabber_area_highlight", "HSlider", fill)
	theme_.set_icon("grabber", "HSlider", _dot_icon(C_AMBER, 9))
	theme_.set_icon("grabber_highlight", "HSlider", _dot_icon(Color("#fff3df"), 10))
	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.05)
	field.border_color = C_LINE
	field.set_border_width_all(1)
	field.set_content_margin_all(6)
	field.content_margin_left = 10
	var field_f := field.duplicate()
	field_f.border_color = C_AMBER
	for cls in ["LineEdit", "OptionButton"]:
		theme_.set_stylebox("normal", cls, field)
		theme_.set_stylebox("focus", cls, field_f)
		theme_.set_stylebox("hover", cls, field_f)
		theme_.set_stylebox("pressed", cls, field_f)
		theme_.set_font("font", cls, sans)
		theme_.set_font_size("font_size", cls, 14)
		theme_.set_color("font_color", cls, C_TEXT)
	theme_.set_stylebox("read_only", "LineEdit", field)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var s := flat.duplicate()
		if st == "focus" or st == "hover" or st == "hover_pressed":
			s.border_color = C_AMBER
			s.border_width_bottom = 1
		theme_.set_stylebox(st, "CheckButton", s)
	theme_.set_font("font", "CheckButton", sans)
	theme_.set_font_size("font_size", "CheckButton", 14)
	var tab_bg := StyleBoxFlat.new()
	tab_bg.bg_color = Color(0, 0, 0, 0)
	tab_bg.set_content_margin_all(8)
	tab_bg.content_margin_left = 12
	tab_bg.content_margin_right = 12
	var tab_on := tab_bg.duplicate()
	tab_on.border_color = C_AMBER
	tab_on.border_width_bottom = 2
	theme_.set_stylebox("tab_selected", "TabBar", tab_on)
	theme_.set_stylebox("tab_unselected", "TabBar", tab_bg)
	theme_.set_stylebox("tab_hovered", "TabBar", tab_bg)
	theme_.set_stylebox("tab_focus", "TabBar", tab_on)
	theme_.set_font("font", "TabBar", sans_m)
	theme_.set_font_size("font_size", "TabBar", 14)
	theme_.set_color("font_selected_color", "TabBar", C_AMBER)
	theme_.set_color("font_unselected_color", "TabBar", C_MUTED)
	theme_.set_color("font_hovered_color", "TabBar", C_TEXT)
	var pm := StyleBoxFlat.new()
	pm.bg_color = Color("#0b0e15")
	pm.border_color = C_LINE
	pm.set_border_width_all(1)
	pm.set_content_margin_all(6)
	theme_.set_stylebox("panel", "PopupMenu", pm)
	theme_.set_font("font", "PopupMenu", sans)
	theme_.set_color("font_hover_color", "PopupMenu", C_AMBER)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(1, 1, 1, 0.04)
	theme_.set_stylebox("scroll", "VScrollBar", sc)
	var gb := StyleBoxFlat.new()
	gb.bg_color = Color(1, 1, 1, 0.18)
	theme_.set_stylebox("grabber", "VScrollBar", gb)
	theme_.set_stylebox("grabber_highlight", "VScrollBar", gb)


static func _dot_icon(c: Color, r: int) -> Texture2D:
	var img := Image.create(r * 2 + 2, r * 2 + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x - r - 0.5, y - r - 0.5).length()
			if d <= r:
				img.set_pixel(x, y, Color(c, clampf(r - d + 0.5, 0, 1)))
	return ImageTexture.create_from_image(img)


static func _full(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


func _label(text: String, font: Font, size: int, color := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rich(bb: String, size := 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_override("normal_font", sans)
	r.add_theme_font_override("bold_font", sans_b)
	r.add_theme_font_override("italics_font", serif_i)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", int(size * 1.25))
	r.add_theme_color_override("default_color", C_TEXT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bb
	return r


static func _box(bg: Color, border := Color(0, 0, 0, 0), left := 0, pad := Vector4(14, 10, 14, 10)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = left
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	return s


## keyboard / gamepad glyph for an action, as BBCode
func kbd(action_or_text: String) -> String:
	var t := Controls.key_label(action_or_text) if Controls.LABELS.has(action_or_text) else action_or_text
	return tr("[bgcolor=#ffffff1f][color=#f6ecd9][font_size=12] %s [/font_size][/color][/bgcolor]") % t


func key(action: String) -> String:
	return Controls.key_label(action)


# ====================================================================== HUD


func _build_hud() -> void:
	# interact prompt
	# placed by prompt_at: over the thing it is for, or low in the middle of the screen
	_prompt = HBoxContainer.new()
	_prompt.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_prompt.add_theme_constant_override("separation", 10)
	_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_ring = HoldRing.new()
	_prompt_ring.custom_minimum_size = Vector2(30, 30)
	_prompt_ring.font = sans_b
	_prompt.add_child(_prompt_ring)
	_prompt_text = _label("", sans, 15, Color("#f2ead9"))
	_prompt_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_prompt_text.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.add_child(_prompt_text)
	_prompt.modulate.a = 0.0
	hud.add_child(_prompt)
	# hiss prompt
	_hiss = PanelContainer.new()
	_hiss.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.06, 0.7), C_CYAN, 2, Vector4(12, 6, 14, 6)))
	_hiss.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hiss.anchor_top = 0.80
	_hiss.anchor_bottom = 0.80
	_hiss.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hiss_lbl = _rich("", 14)
	_hiss_lbl.fit_content = true
	_hiss_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hiss.add_child(_hiss_lbl)
	_hiss.modulate.a = 0.0
	hud.add_child(_hiss)
	# attack alert (top centre)
	_alert = PanelContainer.new()
	_alert.add_theme_stylebox_override("panel", _box(Color(0.06, 0.02, 0.02, 0.72), C_RED, 3, Vector4(16, 10, 18, 12)))
	_alert.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_alert.offset_top = 22
	_alert.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 2)
	av.add_child(_label("ATAQUE EM ANDAMENTO", sans_b, 10, Color("#ff9d8a")))
	_alert_nm = _label("", serif_m, 24)
	av.add_child(_alert_nm)
	_alert_ds = _label("", sans, 13, Color("#d8cfc2"))
	_alert_ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_ds.custom_minimum_size.x = 380
	av.add_child(_alert_ds)
	_alert.add_child(av)
	_alert.modulate.a = 0.0
	hud.add_child(_alert)
	# subtitles
	_subs = VBoxContainer.new()
	_subs.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subs.anchor_top = 0.81
	_subs.anchor_bottom = 0.81
	_subs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subs.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_subs.custom_minimum_size.x = 900
	_subs.alignment = BoxContainer.ALIGNMENT_END
	_subs.add_theme_constant_override("separation", 6)
	_subs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_subs)
	# hints
	_hints = VBoxContainer.new()
	_hints.position = Vector2(28, 26)
	_hints.custom_minimum_size.x = 420
	_hints.add_theme_constant_override("separation", 8)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hints)
	# title card
	_title = VBoxContainer.new()
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.anchor_top = 0.36
	_title.anchor_bottom = 0.36
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_big = _label("", serif_m, 72)
	_title_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title_big.add_theme_constant_override("shadow_offset_y", 2)
	_title_big.add_theme_constant_override("shadow_outline_size", 8)
	_title.add_child(_title_big)
	_title_small = _label("", sans_m, 13, C_MUTED)
	_title_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_child(_title_small)
	_title.modulate.a = 0.0
	hud.add_child(_title)
	# threat card (right, middle)
	_threat = VBoxContainer.new()
	_threat.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_threat.offset_right = -46
	_threat.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_threat.custom_minimum_size.x = 340
	_threat.add_theme_constant_override("separation", 4)
	_threat.add_child(_label("NOVA AMEAÇA", sans_b, 11, C_CYAN))
	_threat_nm = _label("", serif_m, 40)
	_threat.add_child(_threat_nm)
	_threat_ds = _label("", sans, 14, Color("#d8cfc2"))
	_threat_ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_threat.add_child(_threat_ds)
	_threat.modulate.a = 0.0
	hud.add_child(_threat)
	# the right column (top right, under the clock and the lives): tasks, then the "como vencer" cards
	_side = VBoxContainer.new()
	_side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_side.offset_top = 118
	_side.offset_right = -28
	_side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_side.custom_minimum_size.x = 330
	_side.add_theme_constant_override("separation", 10)
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_side)
	_tasks = PanelContainer.new()
	_tasks.add_theme_stylebox_override("panel", _box(Color(0.024, 0.031, 0.05, 0.72), C_AMBER, 2, Vector4(16, 12, 18, 12)))
	_tasks.custom_minimum_size.x = 330
	_tasks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tasks_box = VBoxContainer.new()
	_tasks_box.add_theme_constant_override("separation", 6)
	_tasks.add_child(_tasks_box)
	_tasks.visible = false
	_tasks.modulate.a = 0.0
	_side.add_child(_tasks)
	_howto_box = VBoxContainer.new()
	_howto_box.add_theme_constant_override("separation", 8)
	_howto_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_howto_box.modulate.a = 0.0
	_side.add_child(_howto_box)
	# where to go next
	_objective = ObjectiveMarker.new()
	_objective.size = Vector2(64, 64)
	_objective.font = sans_m
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.visible = false
	hud.add_child(_objective)
	# clock (top right)
	_clock = VBoxContainer.new()
	_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock.offset_top = 22
	_clock.offset_right = -30
	_clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_clock.alignment = BoxContainer.ALIGNMENT_END
	_clock_small = _label("", sans_m, 11, C_MUTED)
	_clock_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.add_child(_clock_small)
	_clock_big = _label("", serif_m, 40)
	_clock_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.add_child(_clock_big)
	_clock.visible = false
	hud.add_child(_clock)
	# the seven lives (top right, under the clock)
	_lives = HBoxContainer.new()
	_lives.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lives.offset_top = 84
	_lives.offset_right = -30
	_lives.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_lives.add_theme_constant_override("separation", 3)
	_lives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives.visible = false
	hud.add_child(_lives)
	_build_vitals()
	# assist bars (bottom left)
	_assist = VBoxContainer.new()
	_assist.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_assist.offset_left = 28
	_assist.offset_bottom = -26
	_assist.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_assist.custom_minimum_size.x = 210
	_assist.add_theme_constant_override("separation", 5)
	_assist.visible = false
	hud.add_child(_assist)
	_arrow = DangerArrow.new()
	_arrow.set_anchors_preset(Control.PRESET_CENTER)
	_arrow.custom_minimum_size = Vector2(160, 160)
	_arrow.offset_left = -80
	_arrow.offset_top = -80
	_arrow.offset_right = 80
	_arrow.offset_bottom = 80
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	hud.add_child(_arrow)
	_click = _label("Clique para continuar", serif_i, 26, Color(0.95, 0.92, 0.86, 0.8))
	_click.set_anchors_preset(Control.PRESET_CENTER)
	_click.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_click.grow_vertical = Control.GROW_DIRECTION_BOTH
	_click.visible = false
	hud.add_child(_click)


func _apply_sub_size() -> void:
	pass


## the button over the thing it is for (a screen point), or low in the middle of the screen (null)
func prompt_at(p) -> void:
	var vs := hud.size
	var want: Vector2 = p if p != null else Vector2(vs.x * 0.5, vs.y * 0.87)
	var sz := _prompt.get_combined_minimum_size()
	var at := (want - Vector2(sz.x * 0.5, sz.y)).clamp(Vector2(16, 16), vs - sz - Vector2(16, 16))
	if not _prompt_placed or _prompt.modulate.a < 0.05:
		_prompt.position = at
		_prompt_placed = true
	else:
		_prompt.position = _prompt.position.lerp(at, 1.0 - exp(-14.0 * get_process_delta_time()))


## the button: its text, the key, how far a hold has gone and whether it has to be held ("Segure")
func prompt(text, action := "interact", hold := 0.0, needs_hold := false) -> void:
	if text is String and text != "":
		text = tr(text)
	if text == null or text == "":
		if _prompt_state != "":
			_prompt_state = ""
			create_tween().tween_property(_prompt, "modulate:a", 0.0, 0.2)
		return
	var k := key(action)
	var st: String = str(text) + k
	if st != _prompt_state:
		var was_empty := _prompt_state == ""
		_prompt_state = st
		_prompt_text.text = text
		_prompt_ring.key = k if k.length() <= 3 else k.substr(0, 1)
		if was_empty:
			create_tween().tween_property(_prompt, "modulate:a", 1.0, 0.2)
	_prompt_ring.progress = hold
	_prompt_ring.needs_hold = needs_hold
	_prompt_ring.queue_redraw()


func say(speaker: String, text: String, dur: float, kind := "normal") -> void:
	text = tr(text)
	if not Settings.g("subtitles") and kind != "narrator" and kind != "ghost":
		return
	var big: bool = Settings.g("subtitle_size") == "l"
	var pc := PanelContainer.new()
	var bg := Color(0, 0, 0, 0.35 if kind == "narrator" else 0.55)
	pc.add_theme_stylebox_override("panel", _box(bg, Color(0, 0, 0, 0), 0, Vector4(14, 7, 14, 7)))
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := 25 if big else 19
	var body := text.replace("[", "[lb]")
	var bb := ""
	if speaker != "":
		var sc := "#ff9d8a" if kind == "scared" else "#e8b46a"
		bb += tr("[font=res://assets/fonts/inter-latin-600-normal.woff2][font_size=%d][color=%s]%s[/color][/font_size][/font]  ") % [int(fs * 0.8), sc, speaker.to_upper()]
	match kind:
		"whisper":
			bb += "[i][color=#cfc7b8]%s[/color][/i]" % body
		"narrator":
			bb += "[i][color=#d9d0c0]%s[/color][/i]" % body
		"ghost":
			bb += "[i][color=#7ff4ff]%s[/color][/i]" % body
		_:
			bb += body
	var r := _rich(bb, fs)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_theme_font_size_override("italics_font_size", int(fs * (1.22 if kind == "narrator" else 1.15)))
	r.fit_content = true
	pc.add_child(r)
	_subs.add_child(pc)
	await get_tree().process_frame
	if not is_instance_valid(r):
		return
	var w := r.get_content_width()
	if w > 860:
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.custom_minimum_size.x = 860
	else:
		r.custom_minimum_size.x = w + 4
	while _subs.get_child_count() > 3:
		_subs.get_child(0).free()
	pc.modulate.a = 0.0
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.25)
	tw.tween_interval(dur)
	tw.tween_property(pc, "modulate:a", 0.0, 0.4)
	tw.tween_callback(pc.queue_free)


func hint(bb: String, dur := 6.0) -> void:
	bb = tr(bb)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(Color(0.024, 0.031, 0.05, 0.75), C_AMBER, 2))
	pc.custom_minimum_size.x = 420
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := _rich(bb, 14)
	r.custom_minimum_size.x = 390
	pc.add_child(r)
	_hints.add_child(pc)
	while _hints.get_child_count() > 3:
		_hints.get_child(0).free()
	pc.modulate.a = 0.0
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.35)
	tw.tween_interval(dur)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)
	tw.tween_callback(pc.queue_free)


func clear_hints() -> void:
	for c in _hints.get_children():
		c.queue_free()
	for c in _subs.get_children():
		c.queue_free()


## a title card is on screen (the tasks and the marker step aside for it)
func title_showing() -> bool:
	return _title.modulate.a > 0.05


func title(big: String, small: String, dur := 3.5) -> void:
	_title_big.text = tr(big)
	_title_small.text = tr(small).to_upper()
	if _title_tw:
		_title_tw.kill()
	_title_tw = create_tween()
	_title_tw.tween_property(_title, "modulate:a", 1.0, 1.2)
	_title_tw.tween_interval(dur)
	_title_tw.tween_property(_title, "modulate:a", 0.0, 1.2)


func threat(nm: String, desc: String) -> void:
	_threat_nm.text = tr(nm)
	_threat_ds.text = tr(desc)
	if _threat_tw:
		_threat_tw.kill()
	_threat.offset_right = -20
	_threat_tw = create_tween().set_parallel(true)
	_threat_tw.tween_property(_threat, "modulate:a", 1.0, 0.8)
	_threat_tw.tween_property(_threat, "offset_right", -46.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_threat_tw.chain().tween_interval(7.2)
	_threat_tw.chain().tween_property(_threat, "modulate:a", 0.0, 1.0)


## the task list: rows {text, done, opt (optional, drawn smaller), warn (urgent, in red)}. Rebuilt only
## when something changed; a change pulses the panel.
func tasks(title_text, list: Array, foot := "") -> void:
	if title_text != null:
		title_text = tr(str(title_text))
	foot = tr(foot)
	var tl := []
	for it in list:
		var d2: Dictionary = (it as Dictionary).duplicate()
		d2["text"] = tr(str(d2.get("text", "")))
		tl.append(d2)
	list = tl
	if title_text == null:
		_tasks_key = ""
		_tasks.visible = false
		return
	var k := "%s|%s|%s" % [title_text, str(list), foot]
	if k == _tasks_key:
		return
	var had := _tasks_key != ""
	_tasks_key = k
	_tasks.visible = true
	for c in _tasks_box.get_children():
		c.queue_free()
	_tasks_box.add_child(_label(str(title_text).to_upper(), sans_b, 11, C_AMBER))
	var opt_head := false
	for t in list:
		var done: bool = t["done"]
		var opt: bool = t.get("opt", false)
		if opt and not opt_head:
			opt_head = true
			_tasks_box.add_child(_label(tr("PARA A PACIÊNCIA DELA (OPCIONAL)"), sans_m, 10, C_MUTED))
		var bb := ""
		if done:
			bb = tr("[color=#7fd88a]✓[/color]  [color=#8d887f]%s[/color]") % t["text"]
		elif t.get("warn", false):
			bb = tr("[color=#d9574a]●[/color]  [color=#ffb4a6]%s[/color]") % t["text"]
		elif opt:
			bb = tr("[color=#9a958c]◇[/color]  [color=#cfc6b8]%s[/color]") % t["text"]
		else:
			bb = tr("[color=#e8b46a]○[/color]  %s") % t["text"]
		var row := _rich(bb, 13 if opt else 14)
		row.custom_minimum_size.x = 300
		_tasks_box.add_child(row)
	if foot != "":
		var f := _label(foot, sans, 12, C_MUTED)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f.custom_minimum_size.x = 300
		_tasks_box.add_child(f)
	if had and _tasks_on:
		tasks_pulse()


## shown or hidden (a fade, with the "como vencer" cards); called every frame, it only tweens on a change
func tasks_visible(v: bool) -> void:
	if v == _tasks_on:
		return
	_tasks_on = v
	if _tasks_tw:
		_tasks_tw.kill()
	_tasks_tw = create_tween().set_parallel(true)
	_tasks_tw.tween_property(_tasks, "modulate:a", 1.0 if v else 0.0, 0.4)
	_tasks_tw.tween_property(_howto_box, "modulate:a", 1.0 if v else 0.0, 0.4)


## something on the list changed: a short glow
func tasks_pulse() -> void:
	var tw := _tasks.create_tween()
	tw.tween_property(_tasks, "self_modulate", Color(1.35, 1.25, 1.05), 0.15)
	tw.tween_property(_tasks, "self_modulate", Color.WHITE, 0.6)


## the "como vencer" card of a ghost, stacked under the tasks; it stays until howto_clear
func howto(id: String, nm: String, text: String) -> void:
	nm = tr(nm)
	text = tr(text)
	if id in _howto_ids:
		return
	_howto_ids.append(id)
	var pc := PanelContainer.new()
	pc.name = "howto_" + id
	pc.add_theme_stylebox_override("panel", _box(Color(0.024, 0.031, 0.05, 0.66), C_CYAN, 2, Vector4(14, 9, 16, 10)))
	pc.custom_minimum_size.x = 330
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := _rich(tr("[font_size=10][color=#7ff4ff]COMO VENCER · %s[/color][/font_size]\n%s") % [nm.to_upper(), text], 13)
	r.custom_minimum_size.x = 300
	pc.add_child(r)
	_howto_box.add_child(pc)
	pc.modulate.a = 0.0
	pc.create_tween().tween_property(pc, "modulate:a", 1.0, 0.5)


func howto_shown() -> Array:
	return _howto_ids.duplicate()


func howto_clear() -> void:
	_howto_ids.clear()
	for c in _howto_box.get_children():
		c.queue_free()


## the objective marker: p = a world point (null hides it), cam = the game camera, dist = metres from
## the cat (written under it). On screen it sits over the point, off screen an arrow on the edge.
func objective(p, cam: Camera3D, dist := 0.0) -> void:
	if p == null or cam == null:
		_objective.visible = false
		return
	var vs := hud.size
	var wp: Vector3 = p
	var margin := 56.0
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp)
	var inside := not behind and sp.x > margin and sp.x < vs.x - margin and sp.y > margin and sp.y < vs.y - margin
	_objective.visible = true
	_objective.dist = dist
	_objective.t += get_process_delta_time()
	if inside:
		_objective.on_screen = true
		_objective.position = sp - _objective.size * 0.5 + Vector2(0, -18)
	else:
		# the direction in the camera's view plane (also right for points behind it), on the edge
		var lp := cam.global_transform.affine_inverse() * wp
		var d2 := Vector2(lp.x, -lp.y)
		if d2.length() < 0.001:
			d2 = Vector2(0, 1)
		d2 = d2.normalized()
		_objective.on_screen = false
		_objective.angle = atan2(d2.x, -d2.y)
		var half := vs * 0.5 - Vector2(margin, margin)
		var k := minf(half.x / maxf(0.001, absf(d2.x)), half.y / maxf(0.001, absf(d2.y)))
		_objective.position = vs * 0.5 + d2 * k - _objective.size * 0.5
	_objective.queue_redraw()


func clock(text, small := "") -> void:
	if text == null:
		_clock.visible = false
		return
	_clock.visible = true
	_clock_big.text = text
	_clock_small.text = small.to_upper()


func _build_vitals() -> void:
	_vitals = HBoxContainer.new()
	_vitals.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_vitals.offset_left = 28
	_vitals.offset_bottom = -26
	_vitals.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_vitals.add_theme_constant_override("separation", 14)
	_vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vitals.visible = false
	hud.add_child(_vitals)
	for d in [["clara", "person", C_RED, "Clara"], ["davi", "person", C_RED, "Davi"], ["cat", "cat", Color("#6fcf7b"), "Gato"]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := VitalIcon.new(d[1], d[2])
		icon.custom_minimum_size = Vector2(32, 54) if d[1] == "person" else Vector2(34, 54)
		col.add_child(icon)
		var nm := _label(d[3], sans, 10, C_MUTED)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nm)
		_vitals.add_child(col)
		_vital_icons[d[0]] = icon
		icon.get_parent().set_meta("id", d[0])


## the silhouettes of the night: `v` = {clara, davi, cat} as 1 (fine) .. 0 (broken / exhausted), a missing
## key hides that one; null hides all of them
func vitals(v) -> void:
	if v == null:
		_vitals.visible = false
		return
	_vitals.visible = true
	for id in _vital_icons:
		var icon: VitalIcon = _vital_icons[id]
		var on: bool = v.has(id)
		icon.get_parent().visible = on
		if on:
			icon.set_level(float(v[id]))


## left < 0 hides the row. Lives lost tonight stay struck; a new loss draws its strike.
func lives(left: int, lost_tonight := 0) -> void:
	if left < 0:
		_lives.visible = false
		_lives_shown = -1
		return
	_lives.visible = true
	var fresh := _lives_shown >= 0 and left < _lives_shown
	for ch in _lives.get_children():
		ch.queue_free()
	for i in SaveGame.LIVES:
		var st := 0 if i < left else (1 if i < left + lost_tonight else 2)
		var icon := CatLife.new(st, 22)
		_lives.add_child(icon)
		if fresh and i == left:
			icon.strike = 0.0
			icon.pivot_offset = Vector2(11, 11)
			var tw := create_tween()
			tw.tween_property(icon, "scale", Vector2(1.6, 1.6), 0.18)
			tw.tween_property(icon, "scale", Vector2.ONE, 0.25)
			tw.parallel().tween_method(func(v: float):
				icon.strike = v
				icon.queue_redraw(), 0.0, 1.0, 0.45)
	_lives_shown = left


func assist(v) -> void:
	if v == null:
		_assist.visible = false
		_arrow.visible = false
		return
	_assist.visible = true
	for c in _assist.get_children():
		c.queue_free()
	for p in v["people"]:
		_assist.add_child(_bar(tr("Medo · %s") % p["name"], p["fear"], C_RED))
		_assist.add_child(_bar(tr("Paciência · %s") % p["name"], p["patience"], C_AMBER))
	_assist.add_child(_bar("Foco", v["focus"], C_CYAN))
	if v.get("sleep", 100.0) < 99.0:
		_assist.add_child(_bar("Sono", v["sleep"], C_AMBER))
	if v["arrow"] == null:
		_arrow.visible = false
	else:
		_arrow.visible = true
		_arrow.angle = v["arrow"]
		_arrow.queue_redraw()


func _bar(label: String, x: float, color: Color) -> Control:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 2)
	b.add_child(_label(label, sans_m, 11, C_MUTED))
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.1)
	bg.custom_minimum_size = Vector2(200, 4)
	var fg := ColorRect.new()
	fg.color = color
	fg.size = Vector2(200 * clampf(x / 100.0, 0, 1), 4)
	bg.add_child(fg)
	b.add_child(bg)
	return b


func alert(title_text, hint_text := "") -> void:
	var k := "" if title_text == null else "%s|%s" % [title_text, hint_text]
	if k == _alert_key:
		return
	_alert_key = k
	if title_text == null:
		create_tween().tween_property(_alert, "modulate:a", 0.0, 0.4)
		return
	_alert_nm.text = title_text
	_alert_ds.text = hint_text
	create_tween().tween_property(_alert, "modulate:a", 1.0, 0.3)


func hiss(state: String) -> void:
	var k := "%s|%d" % [state, Controls.last_device]
	if k == _hiss_state:
		return
	_hiss_state = k
	if state == "off":
		create_tween().tween_property(_hiss, "modulate:a", 0.0, 0.2)
		return
	_hiss_lbl.text = "%s  %s" % [kbd("hiss"), "Bufar (pouco Foco)" if state == "weak" else "Bufar"]
	_hiss.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.06, 0.7), C_MUTED if state == "weak" else C_CYAN, 2, Vector4(12, 6, 14, 6)))
	create_tween().tween_property(_hiss, "modulate:a", 1.0, 0.2)


func show_click_to_play(v: bool) -> void:
	_click.visible = v


func hud_visible(v: bool) -> void:
	hud.visible = v


# ====================================================================== overlays


var overlay_open: bool:
	get:
		return overlay != null


func _set_overlay(o: Control, back: Callable = Callable()) -> void:
	if overlay:
		overlay.queue_free()
	overlay = o
	back_handler = back
	skip_handler = Callable()
	if o:
		overlay_root.add_child(o)
		o.modulate.a = 0.0
		o.create_tween().tween_property(o, "modulate:a", 1.0, 0.35)
		await get_tree().process_frame
		if is_instance_valid(o) and overlay == o:
			_focus_first(o)


func _focus_first(o: Control) -> void:
	for c in o.find_children("*", "BaseButton", true, false):
		var b := c as BaseButton
		if b.visible and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
			return


func close_overlay() -> void:
	if overlay:
		overlay.queue_free()
	overlay = null
	back_handler = Callable()
	skip_handler = Callable()


func _input(event: InputEvent) -> void:
	if overlay == null:
		return
	if skip_handler.is_valid() and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_back") or event.is_action_pressed("jump") or (event is InputEventMouseButton and event.pressed)):
		var s := skip_handler
		skip_handler = Callable()
		get_viewport().set_input_as_handled()
		back_frame = Engine.get_process_frames()
		s.call()
		return
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		if back_handler.is_valid():
			get_viewport().set_input_as_handled()
			back_frame = Engine.get_process_frames()
			sound.emit("back")
			back_handler.call()


func _veil() -> Control:
	var v := _full(ColorRect.new()) as ColorRect
	v.color = Color(0.008, 0.01, 0.016, 0.62)
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	return v


func _center_panel(parent: Control, min_w := 460.0) -> VBoxContainer:
	var cc := _full(CenterContainer.new())
	parent.add_child(cc)
	var p := PanelContainer.new()
	p.custom_minimum_size.x = min_w
	cc.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	return vb


func button(label: String, cb: Callable, disabled := false, extra := "", size := 30) -> Button:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = disabled
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus())
	b.focus_entered.connect(func(): sound.emit("hover"))
	b.pressed.connect(func():
		sound.emit("select")
		cb.call())
	if extra != "":
		return _with_sub(b, extra)
	return b


func _with_sub(b: Button, extra: String) -> Button:
	var l := _label(extra, sans, 12, C_MUTED)
	b.add_child(l)
	b.resized.connect(func():
		var f: Font = b.get_theme_font("font")
		var w := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		var st := b.get_theme_stylebox("normal")
		l.position = Vector2(st.content_margin_left + w + 14, b.size.y / 2 - l.size.y / 2 + 3))
	return b


func small_button(label: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_override("font", sans_m)
	b.add_theme_font_size_override("font_size", 14)
	var n := _box(Color(1, 1, 1, 0.04) if not primary else Color(0.91, 0.71, 0.42, 0.16), C_AMBER if primary else C_LINE, 1, Vector4(18, 9, 18, 9))
	n.border_width_right = 1
	n.border_width_top = 1
	n.border_width_bottom = 1
	var h := n.duplicate()
	h.border_color = C_AMBER
	h.bg_color = Color(0.91, 0.71, 0.42, 0.22)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("pressed", h)
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): sound.emit("hover"))
	b.pressed.connect(func():
		sound.emit("select")
		cb.call())
	return b


# ---------------------------------------------------------------------- loading


func show_loading() -> void:
	var l := _full(ColorRect.new()) as ColorRect
	l.color = Color("#05070c")
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	var t := _label("Sete Vidas", serif_m, 76, Color("#f1e9db"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.08)
	bar.custom_minimum_size = Vector2(320, 2)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.name = "fill"
	fill.color = C_AMBER
	fill.size = Vector2(0, 2)
	bar.add_child(fill)
	vb.add_child(bar)
	var msg := _label("Preparando a casa", sans, 13, C_MUTED)
	msg.name = "msg"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(msg)
	l.add_child(vb)
	var tip := _label("Use fones de ouvido. Neste jogo, o som é metade do medo.", serif_i, 20, Color(0.8, 0.77, 0.72, 0.8))
	tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tip.offset_top = -70
	tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.add_child(tip)
	overlay_root.add_child(l)
	loading_el = l
	set_meta("bar", fill)
	set_meta("msg", msg)


func loading(p: float, msg: String) -> void:
	if loading_el == null:
		return
	(get_meta("bar") as ColorRect).size.x = 320 * p
	(get_meta("msg") as Label).text = msg


func hide_loading() -> void:
	var l := loading_el
	if l == null:
		return
	loading_el = null
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 1.3)
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------------- menu


func show_menu(o: Dictionary) -> void:
	var m := _full(Control.new())
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var grad := _full(TextureRect.new()) as TextureRect
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.012, 0.02, 0.88))
	g.set_color(1, Color(0.01, 0.012, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.75, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(grad)
	var block := VBoxContainer.new()
	block.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	block.offset_left = 110
	block.grow_vertical = Control.GROW_DIRECTION_BOTH
	block.add_theme_constant_override("separation", 0)
	var h1 := _label("Sete Vidas", serif_m, 120, Color("#f1e9db"))
	h1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	h1.add_theme_constant_override("shadow_offset_y", 3)
	h1.add_theme_constant_override("shadow_outline_size", 10)
	block.add_child(h1)
	var tag := _label("Ela não vê o que anda pela casa. Você vê.", serif_i, 26, Color("#c9bfae"))
	block.add_child(tag)
	var sp := Control.new()
	sp.custom_minimum_size.y = 42
	block.add_child(sp)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 2)
	nav.custom_minimum_size.x = 420
	if o.get("can_continue", false):
		nav.add_child(button("Continuar", o["on_continue"], false, o.get("continue_label", "")))
	nav.add_child(button("Novo jogo", o["on_new"]))
	var nights := VBoxContainer.new()
	nights.add_theme_constant_override("separation", 4)
	nights.visible = false
	var unlocked: int = o.get("unlocked", 1)
	nav.add_child(button("Escolher noite", func():
		nights.visible = not nights.visible
		if nights.visible:
			(nights.get_child(0).get_child(0) as Button).grab_focus(), unlocked < 2))
	var rows: Array = o.get("nights", [])
	for i in range(1, 8):
		var info: Dictionary = rows[i - 1] if i - 1 < rows.size() else {"start": 7, "lost": 0}
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var b := small_button(tr("Noite %d") % i, func(): o["on_night"].call(i))
		b.disabled = i > unlocked
		b.custom_minimum_size = Vector2(118, 34)
		row.add_child(b)
		var icons := HBoxContainer.new()
		icons.add_theme_constant_override("separation", 3)
		icons.alignment = BoxContainer.ALIGNMENT_CENTER
		var start: int = info["start"]
		var lost: int = info["lost"]
		for k in 7:
			var st := 0 if k < start - lost else (1 if k < start else 2)
			icons.add_child(CatLife.new(st, 22))
		icons.modulate.a = 1.0 if i <= unlocked else 0.3
		row.add_child(icons)
		nights.add_child(row)
	nav.add_child(nights)
	nav.add_child(button("Opções", o["on_settings"]))
	nav.add_child(button("Créditos", o["on_credits"]))
	nav.add_child(button("Sair", func(): get_tree().quit()))
	block.add_child(nav)
	m.add_child(block)
	var foot := _label("Fones de ouvido recomendados · v2.0 (Godot)", sans, 12, Color(0.6, 0.58, 0.55, 0.6))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 110
	foot.offset_top = -46
	m.add_child(foot)
	_set_overlay(m)


# ---------------------------------------------------------------------- pause / fail / summary


func show_pause(o: Dictionary) -> void:
	var v := _veil()
	var p := _center_panel(v)
	p.add_child(_label("Pausado", serif_m, 46))
	p.add_child(_label(o["title"], sans, 13, C_MUTED))
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 0)
	nav.add_child(button("Continuar", o["on_resume"], false, "", 26))
	if o.get("on_restart_night") != null:
		nav.add_child(button("Recomeçar a noite", o["on_restart_night"], false, "", 26))
	if o.get("on_restart_day") != null:
		nav.add_child(button("Recomeçar o dia", o["on_restart_day"], false, "", 26))
	if o.get("on_skip_night") != null:
		nav.add_child(button("Passar a noite", o["on_skip_night"], false, "só para teste", 26))
	nav.add_child(button("Opções", o["on_settings"], false, "", 26))
	nav.add_child(button("Menu principal", o["on_menu"], false, "", 26))
	p.add_child(nav)
	_set_overlay(v, o["on_resume"])


func show_fail(o: Dictionary) -> void:
	var v := _veil()
	v.color = Color(0.03, 0.0, 0.0, 0.72)
	var p := _center_panel(v, 560)
	var t := _label(o["title"], serif_m, 42, Color("#ffd9cf"))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 480
	p.add_child(t)
	p.add_child(_label(o["sub"], sans, 13, C_MUTED))
	if o.get("why", "") != "":
		var w := _label(o["why"], serif_i, 21, Color("#e2d6c6"))
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size.x = 480
		p.add_child(w)
	for f in o.get("facts", []):
		p.add_child(_label("•  " + str(f), sans, 13, Color("#bfb6a8")))
	if o.get("tip", "") != "":
		var tp := PanelContainer.new()
		tp.add_theme_stylebox_override("panel", _box(Color(0.91, 0.71, 0.42, 0.07), C_AMBER, 2))
		var r := _rich("[b][color=#e8b46a]COMO EVITAR[/color][/b]\n" + str(o["tip"]), 14)
		r.custom_minimum_size.x = 450
		tp.add_child(r)
		p.add_child(tp)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 0)
	nav.add_child(button("Recomeçar a noite", o["on_night"], false, "mantém o preparo", 26))
	var has_day: bool = o.get("on_day") != null
	nav.add_child(button("Recomeçar o dia", o["on_day"] if has_day else func(): pass, not has_day, "volta para a manhã" if has_day else "não há manhã antes da noite 1", 26))
	nav.add_child(button("Menu principal", o["on_menu"], false, "", 26))
	p.add_child(nav)
	_set_overlay(v)


func show_summary(o: Dictionary) -> void:
	var v := _veil()
	var p := _center_panel(v, 480)
	p.add_child(_label(o["title"], serif_m, 44))
	p.add_child(_label(o.get("sub", "Clara sobreviveu"), sans, 13, C_MUTED))
	for ln in o["lines"]:
		var hb := HBoxContainer.new()
		var a := _label(ln[0], sans, 15, Color("#cfc6b8"))
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(a)
		hb.add_child(_label(ln[1], serif_m, 24, C_AMBER))
		p.add_child(hb)
	var act := HBoxContainer.new()
	act.alignment = BoxContainer.ALIGNMENT_END
	act.add_child(small_button(o.get("button", "Continuar"), o["on_continue"], true))
	p.add_child(act)
	_set_overlay(v)


# ---------------------------------------------------------------------- story cards / ending / credits


func show_cards(cards: Array, on_done: Callable, per_card := 3.6) -> void:
	cards = cards.map(func(c): return tr(str(c)) if c is String else c)
	var v := _full(ColorRect.new()) as ColorRect
	v.color = Color(0, 0, 0, 1)
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	var card := _label("", serif_i, 38, Color("#efe6d6"))
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.offset_left = 160
	card.offset_right = -160
	card.modulate.a = 0.0
	v.add_child(card)
	var skip := _rich(tr("[right][color=#8d887f]Pular  [/color]%s[/right]") % kbd("jump"), 13)
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -260
	skip.offset_top = -50
	skip.offset_right = -36
	v.add_child(skip)
	_set_overlay(v)
	var state := {"done": false}
	var finish := func():
		if state["done"]:
			return
		state["done"] = true
		var tw := v.create_tween()
		tw.tween_property(v, "modulate:a", 0.0, 0.9)
		tw.tween_callback(func():
			if overlay == v:
				close_overlay()
			on_done.call())
	await get_tree().process_frame
	skip_handler = finish
	var tw := v.create_tween()
	for i in cards.size():
		tw.tween_callback(func(): card.text = cards[i])
		tw.tween_property(card, "modulate:a", 1.0, 1.1)
		tw.tween_interval(per_card)
		tw.tween_property(card, "modulate:a", 0.0, 1.0)
	tw.tween_callback(finish)


func show_ending(title_text: String, lines: Array, on_done: Callable) -> void:
	title_text = tr(title_text)
	var v := _full(ColorRect.new()) as ColorRect
	v.color = Color(0.01, 0.01, 0.015, 0.94)
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 22)
	vb.custom_minimum_size.x = 860
	var h := _label(title_text, serif_m, 84, Color("#f1e9db"))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.modulate.a = 0.0
	vb.add_child(h)
	var ps := []
	for l in lines:
		var p := _label(l, serif_i, 26, Color("#ddd3c3"))
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.custom_minimum_size.x = 820
		p.modulate.a = 0.0
		vb.add_child(p)
		ps.append(p)
	var cont := small_button("Continuar", on_done, true)
	cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cont.modulate.a = 0.0
	cont.focus_mode = Control.FOCUS_NONE
	vb.add_child(cont)
	v.add_child(vb)
	_set_overlay(v)
	var tw := v.create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(h, "modulate:a", 1.0, 2.0)
	for p in ps:
		tw.tween_interval(1.2)
		tw.tween_property(p, "modulate:a", 1.0, 2.0)
	tw.tween_interval(2.5)
	tw.tween_property(cont, "modulate:a", 1.0, 1.5)
	tw.tween_callback(func():
		cont.focus_mode = Control.FOCUS_ALL
		cont.grab_focus())


func show_credits(on_done: Callable) -> void:
	var v := _full(ColorRect.new()) as ColorRect
	v.color = Color(0.01, 0.01, 0.015, 0.95)
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	for c in Story.CREDITS:
		var a := _label(c[0], serif_m, 34 if c[1] == "" else 28, Color("#f1e9db"))
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(a)
		if c[1] != "":
			var b := _label(c[1], sans, 13, C_MUTED)
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(b)
	var back := small_button("Voltar", on_done)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(back)
	v.add_child(vb)
	_set_overlay(v, on_done)


# ---------------------------------------------------------------------- settings


var _settings_close := Callable()


func _reopen_settings() -> void:
	if _settings_close.is_valid():
		close_overlay()
		show_settings(_settings_close)


func show_settings(on_close: Callable) -> void:
	_settings_close = on_close
	var v := _veil()
	var p := _center_panel(v, 720)
	p.add_child(_label("Opções", serif_m, 46))
	p.add_child(_label("As mudanças são salvas automaticamente", sans, 13, C_MUTED))
	var tabs := TabBar.new()
	for n in ["Jogo", "Controles", "Vídeo", "Áudio", "Acessibilidade"]:
		tabs.add_tab(n)
	tabs.focus_mode = Control.FOCUS_ALL
	p.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	var render := func(i: int):
		for c in rows.get_children():
			c.queue_free()
		for r in _settings_page(i):
			rows.add_child(r)
	tabs.tab_changed.connect(func(i):
		sound.emit("hover")
		render.call(i))
	render.call(0)
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 10)
	act.alignment = BoxContainer.ALIGNMENT_END
	act.add_child(small_button("Restaurar padrões", func():
		Settings.reset()
		render.call(tabs.current_tab)))
	act.add_child(small_button("Voltar", on_close, true))
	p.add_child(act)
	_set_overlay(v, on_close)
	await get_tree().process_frame
	if is_instance_valid(tabs):
		tabs.grab_focus()


func _row(label: String, desc: String, ctrl: Control) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 0)
	lv.add_child(_label(label, sans_m, 14))
	if desc != "":
		var d := _label(desc, sans, 12, C_MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 330
		lv.add_child(d)
	hb.add_child(lv)
	ctrl.custom_minimum_size.x = maxf(ctrl.custom_minimum_size.x, 250)
	ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ctrl)
	return hb


func _slider(label: String, k: String, mn: float, mx: float, step: float, desc := "", fmt := "") -> Control:
	var hb := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Settings.g(k))
	s.custom_minimum_size.x = 190
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_ALL
	var val := _label("", sans, 12, C_MUTED)
	val.custom_minimum_size.x = 48
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var show := func(x: float):
		match fmt:
			"pct":
				val.text = "%d%%" % roundi(x * 100)
			"deg":
				val.text = "%d°" % roundi(x)
			_:
				val.text = "%.2f" % x
	show.call(s.value)
	s.value_changed.connect(func(x):
		Settings.set_value(k, x)
		show.call(x))
	hb.add_child(s)
	hb.add_child(val)
	return _row(label, desc, hb)


func _toggle(label: String, k: String, desc := "") -> Control:
	var t := CheckButton.new()
	t.button_pressed = bool(Settings.g(k))
	t.focus_mode = Control.FOCUS_ALL
	t.toggled.connect(func(on):
		Settings.set_value(k, on)
		sound.emit("select"))
	t.custom_minimum_size.x = 60
	t.size_flags_horizontal = Control.SIZE_SHRINK_END
	return _row(label, desc, t)


func _select(label: String, k: String, opts: Array, desc := "") -> Control:
	var ob := OptionButton.new()
	for i in opts.size():
		ob.add_item(opts[i][1], i)
		if str(Settings.g(k)) == str(opts[i][0]):
			ob.select(i)
	ob.item_selected.connect(func(i):
		Settings.set_value(k, opts[i][0])
		if k == "lang":
			# rebuild the options in the new language
			_reopen_settings.call_deferred())
	return _row(label, desc, ob)


func _text(label: String, k: String, desc := "") -> Control:
	var le := LineEdit.new()
	le.text = str(Settings.g(k))
	le.max_length = 16
	le.text_changed.connect(func(tx): Settings.set_value(k, tx.strip_edges() if tx.strip_edges() != "" else "Mingau"))
	return _row(label, desc, le)


func _settings_page(i: int) -> Array:
	match i:
		0:
			return [
				_select("Idioma / Language", "lang", [["pt_BR", "Português (Brasil)"], ["en", "English"]]),
				_text("Nome do gato", "cat_name", "Como Clara chama você"),
				_slider("Velocidade das noites", "night_speed", 0.7, 1.0, 0.05, "Valores menores deixam as assombrações mais lentas", "pct"),
				_toggle("Esgueirar alterna", "sneak_toggle", "Desligado: segure o botão"),
				_toggle("Tremor de câmera", "camera_shake"),
			]
		1:
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 24)
			grid.add_theme_constant_override("v_separation", 6)
			for hdr in ["Ação", "Teclado", "Controle"]:
				grid.add_child(_label(hdr.to_upper(), sans_b, 11, C_AMBER))
			for r in [["Mover", "W A S D", "Analógico esq."], ["Câmera", "Mouse", "Analógico dir."], ["Pular (aponte para o círculo)", "Espaço", "A"],
					["Interagir / segurar", "E · clique", "X"], ["Miar", "Q", "Y"], ["Bufar", "F", "RB"],
					["Correr", "Shift", "RT"], ["Esgueirar", "Ctrl · C", "B"], ["Ver a hora", "Tab", "Select"], ["Pausar", "Esc", "Start"]]:
				grid.add_child(_label(r[0], sans, 13))
				grid.add_child(_rich(kbd(r[1]), 13))
				grid.add_child(_rich(kbd(r[2]), 13))
			return [
				_slider("Sensibilidade do mouse", "sensitivity", 0.2, 3.0, 0.05),
				_slider("Sensibilidade do controle", "pad_sensitivity", 0.3, 2.5, 0.05),
				_toggle("Inverter eixo vertical", "invert_y"),
				grid,
			]
		2:
			return [
				_select("Qualidade", "quality", [["low", "Baixa"], ["medium", "Média"], ["high", "Alta"], ["ultra", "Ultra"]], "Sombras, iluminação global, névoa volumétrica e reflexos"),
				_toggle("Tela cheia", "fullscreen"),
				_slider("Escala de resolução", "render_scale", 0.5, 1.0, 0.05, "Abaixo de 100% usa FSR 2", "pct"),
				_slider("Campo de visão", "fov", 55, 90, 1, "", "deg"),
				_slider("Brilho", "brightness", 0.7, 1.6, 0.02, "Ajuste até o gato quase sumir no escuro", "pct"),
				_toggle("Brilho das luzes (bloom)", "bloom"),
				_toggle("Granulado de filme", "grain"),
			]
		3:
			return [
				_slider("Volume geral", "master", 0, 1, 0.01, "", "pct"),
				_slider("Música", "music", 0, 1, 0.01, "", "pct"),
				_slider("Efeitos", "sfx", 0, 1, 0.01, "", "pct"),
				_slider("Ambiente", "ambience", 0, 1, 0.01, "", "pct"),
			]
		_:
			return [
				_toggle("Modo assistido", "assist", "Mostra barras de Medo, Paciência e Foco, e uma seta para o perigo"),
				_toggle("Legendas", "subtitles"),
				_select("Tamanho das legendas", "subtitle_size", [["m", "Normal"], ["l", "Grande"]]),
				_toggle("Reduzir sustos e flashes", "reduce_flashes", "Sem clarões e com sustos mais suaves"),
			]
