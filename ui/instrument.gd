extends Control
## The diver braces against the member while this field instrument is open.

signal adjusted(values: Array)
signal submitted(success: bool, detail: String)
signal exited

const HEAD := preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
const BODY := preload("res://ui/fonts/Barlow-Regular.ttf")
const MONO := preload("res://ui/fonts/CourierPrime-Regular.ttf")
const PLATE := Vector2(872, 478)
const SCOPE := Rect2(30, 121, 517, 220)
const INK := Color("#122524")
const FRAME := Color("#233330")
const EDGE := Color("#64756a")
const PAPER := Color("#e7e7d2")
const MUTED := Color("#b0beb0")
const AMBER := Color("#eac174")
const SIGNAL := Color("#97d8b6")
const GRID := Color("#29453c")
const BLACK := Color("#0b1b1a")

var _job := 0
var _watch := 0
var _settings: Array[int] = [3, 0]
var _feedback := ""
var _failed := false
var _plate_scale := 1.0
var _origin := Vector2.ZERO
var _controls: Control


func configure(job: int, watch: int, values: Array) -> void:
	_job = job
	_watch = maxi(0, watch)
	var defaults: Array = [3, 0] if job == 0 else [1, 7]
	for i in 2:
		var maximum := 24 if _job == 0 else 8
		if i < values.size() and int(values[i]) >= 0:
			_settings[i] = clampi(int(values[i]), 0, maximum)
		else:
			_settings[i] = defaults[i]
	_feedback = _initial_note()
	_failed = false
	if is_node_ready():
		_rebuild_buttons()
	queue_redraw()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_controls = Control.new()
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_controls)
	if _feedback.is_empty():
		_feedback = _initial_note()
	_rebuild_buttons()
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	_plate_scale = minf((size.x - 24.0) / PLATE.x, (size.y - 16.0) / PLATE.y)
	_plate_scale = clampf(_plate_scale, 0.1, 1.25)
	_origin = ((size - PLATE * _plate_scale) * 0.5).round()
	_controls.position = _origin
	_controls.scale = Vector2.ONE * _plate_scale
	queue_redraw()


func _initial_note() -> String:
	if _job == 0:
		return "The tall pulse at zero is the near face.\nFind the first strong return beyond it."
	return "The dark shoes ride with the carrier.\nLine up each white notch with its brass mark."


func _target(side: int = 0) -> int:
	if _job == 0:
		return 9 + posmod(_watch * 3 + 1, 4)
	if side == 0:
		return 3 + posmod(_watch * 2 + 1, 4)
	return 2 + posmod(_watch * 3 + 2, 4)


func _rebuild_buttons() -> void:
	for node in _controls.get_children():
		_controls.remove_child(node)
		node.queue_free()
	_button("UNBRACE", Rect2(688, 20, 154, 52), func(): exited.emit())
	if _job == 0:
		_button("−", Rect2(578, 232, 125, 62), _adjust.bind(0, -1))
		_button("+", Rect2(716, 232, 125, 62), _adjust.bind(0, 1))
	else:
		for side in 2:
			var y := 164 + side * 87
			_button("−", Rect2(680, y, 73, 59), _adjust.bind(side, -1))
			_button("+", Rect2(765, y, 76, 59), _adjust.bind(side, 1))
	_button("RECORD READING" if _job == 0 else "SEAT CARRIER", Rect2(578, 383, 263, 66), _submit, true)


func _button(title: String, rect: Rect2, action: Callable, primary := false) -> void:
	var button := Button.new()
	button.text = title
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", HEAD)
	button.add_theme_font_size_override("font_size", 32 if title in ["+", "−"] else 22)
	var background := AMBER if primary else Color("#354740")
	var foreground := INK if primary else PAPER
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = background.lightened(0.08) if state == "hover" else background
		if state == "pressed":
			style.bg_color = background.darkened(0.18)
		style.set_border_width_all(1)
		style.border_color = AMBER if primary else EDGE
		style.set_corner_radius_all(2)
		button.add_theme_stylebox_override(state, style)
		if state != "normal":
			button.add_theme_color_override("font_" + state + "_color", foreground)
	button.add_theme_color_override("font_color", foreground)
	button.pressed.connect(action)
	_controls.add_child(button)


func _adjust(side: int, step: int) -> void:
	_set_value(side, _settings[side] + step)


func _set_value(side: int, value: int) -> void:
	var clipped := clampi(value, 0, 24 if _job == 0 else 8)
	if _settings[side] == clipped:
		return
	_settings[side] = clipped
	adjusted.emit(_settings.duplicate())
	queue_redraw()


func _submit() -> void:
	var ok := _settings[0] == _target()
	if _job == 0:
		if ok:
			_feedback = "A2  /  %d.0 mm. Back-wall return recorded." % _settings[0]
		elif _settings[0] <= 2:
			_feedback = "That is the near-face pulse.\nMove the gate past the start of the trace."
		elif _settings[0] >= _target() * 2 - 1:
			_feedback = "That is a later reflection.\nLook left for the first strong return."
		else:
			_feedback = "Gate is off the crest.\nCentre it on the first strong return."
	else:
		ok = ok and _settings[1] == _target(1)
		if ok:
			_feedback = "B4  /  Both shoes are flush. Carrier seated."
		else:
			var side := 0 if _settings[0] != _target() else 1
			var direction := "down (+)" if _settings[side] < _target(side) else "up (−)"
			_feedback = "%s shoe is %s the witness mark.\nMove its white notch %s." % [
				"Left" if side == 0 else "Right",
				"above" if _settings[side] < _target(side) else "below", direction]
	_failed = not ok
	queue_redraw()
	submitted.emit(ok, _feedback.replace("\n", " "))


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var viewport := get_viewport()
	match event.keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			exited.emit()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_submit()
		KEY_A, KEY_LEFT:
			_adjust(0, -1)
		KEY_D, KEY_RIGHT:
			_adjust(0, 1)
		KEY_J, KEY_UP:
			if _job == 1:
				_adjust(1, -1)
		KEY_L, KEY_DOWN:
			if _job == 1:
				_adjust(1, 1)
		_:
			return
	viewport.set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if _job != 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pick_gate(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_pick_gate(event.position)
	elif event is InputEventScreenDrag:
		_pick_gate(event.position)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_pick_gate(event.position)


func _pick_gate(pointer: Vector2) -> void:
	var p := (pointer - _origin) / _plate_scale
	if SCOPE.has_point(p):
		_set_value(0, roundi((p.x - 54.0) / 19.4))
		accept_event()


func _text(at: Vector2, s: String, font: Font, px: int, color: Color) -> void:
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.009, 0.027, 0.026, 0.66))
	draw_set_transform(_origin, 0.0, Vector2.ONE * _plate_scale)
	draw_rect(Rect2(Vector2(3, 6), PLATE), Color(0, 0, 0, 0.42))
	draw_rect(Rect2(Vector2.ZERO, PLATE), FRAME)
	draw_rect(Rect2(Vector2.ZERO, PLATE), EDGE, false, 1)
	draw_rect(Rect2(0, 0, 7, 84), AMBER)
	for p in [Vector2(13, 13), Vector2(858, 13), Vector2(13, 464), Vector2(858, 464)]:
		draw_circle(p, 3.5, BLACK)
		draw_line(p - Vector2(2, 0), p + Vector2(2, 0), EDGE)
	_text(Vector2(30, 33), "KESTREL  /  EAST JACKET     •     %s" % ("A2" if _job == 0 else "B4"), MONO, 16, AMBER)
	_text(Vector2(29, 77), "Wall thickness survey" if _job == 0 else "Survey carrier alignment", HEAD, 39, PAPER)
	_text(Vector2(31, 103), "Set the gate on the first back-wall echo." if _job == 0 else "Bring both carrier shoes to their witness marks.", BODY, 19, MUTED)
	draw_rect(SCOPE, BLACK)
	draw_rect(SCOPE, EDGE, false, 1.0)
	if _job == 0:
		_draw_survey()
	else:
		_draw_carrier()
	draw_line(Vector2(30, 358), Vector2(841, 358), EDGE)
	_text(Vector2(30, 384), "CHECK AGAIN" if _failed else "FIELD NOTE", MONO, 15, AMBER if _failed else SIGNAL)
	var row := 0
	for line in _feedback.split("\n"):
		_text(Vector2(30, 411 + row * 24), line, BODY, 20, PAPER)
		row += 1


func _draw_survey() -> void:
	_text(Vector2(45, 144), "A-SCAN  /  PULSE ECHO", MONO, 14, SIGNAL)
	var y0 := 286.0
	for i in 25:
		var x := 54 + i * 19.4
		draw_line(Vector2(x, 158), Vector2(x, y0 + 4), GRID, 1)
		if i % 4 == 0:
			_text(Vector2(x - 5, 312), str(i), MONO, 15, MUTED)
	for i in 5:
		var y := y0 - i * 31
		draw_line(Vector2(54, y), Vector2(520, y), GRID)
	var trace := PackedVector2Array()
	var peak := float(_target())
	for i in 350:
		var t := 24.0 * i / 349.0
		var jitter := 1.7 * absf(sin(t * 8.1 + _watch) + sin(t * 5.3))
		var h := jitter + _pulse(t, 0.9, 0.48, 118) + _pulse(t, 3.8, 0.7, 14) + _pulse(t, 5.5, 0.6, 10) + _pulse(t, peak, 0.82, 97) + _pulse(t, peak * 2.0, 0.92, 68)
		trace.append(Vector2(54 + t * 19.4, y0 - h))
	draw_polyline(trace, SIGNAL, 2.6, true)
	var cursor := 54 + _settings[0] * 19.4
	draw_rect(Rect2(cursor - 5, 155, 10, 137), Color(0.95, 0.76, 0.4, 0.15))
	draw_line(Vector2(cursor, 154), Vector2(cursor, 294), AMBER, 2)
	draw_colored_polygon(PackedVector2Array([Vector2(cursor - 6, 152), Vector2(cursor + 6, 152), Vector2(cursor, 160)]), AMBER)
	_text(Vector2(445, 331), "mm STEEL", MONO, 13, MUTED)
	_text(Vector2(578, 154), "MEASUREMENT GATE", MONO, 17, MUTED)
	_text(Vector2(576, 211), "%02d.0 mm" % _settings[0], HEAD, 48, AMBER)
	_text(Vector2(578, 323), "Tap the trace or use  − / +", BODY, 18, MUTED)


func _pulse(t: float, centre: float, width: float, amplitude: float) -> float:
	return amplitude * pow(maxf(0.0, 1.0 - absf(t - centre) / width), 1.55)


func _draw_carrier() -> void:
	_text(Vector2(45, 144), "CARRIER  /  JACKET ELEVATION", MONO, 14, SIGNAL)
	for i in 9:
		var y := 173 + i * 14
		draw_line(Vector2(53, y), Vector2(521, y), GRID)
	var left_y := 173 + _settings[0] * 14
	var right_y := 173 + _settings[1] * 14
	draw_line(Vector2(165, left_y), Vector2(413, right_y), Color("#607368"), 11, true)
	draw_line(Vector2(165, left_y - 4), Vector2(413, right_y - 4), MUTED, 1, true)
	for side in 2:
		var x := 165 + side * 248
		var current := 173 + _settings[side] * 14
		var expected := 173 + _target(side) * 14
		draw_rect(Rect2(x - 8, 158, 16, 143), Color("#53655a"))
		draw_line(Vector2(x - 5, 158), Vector2(x - 5, 301), MUTED, 1)
		draw_rect(Rect2(x - 22, current - 12, 44, 24), FRAME)
		draw_rect(Rect2(x - 22, current - 12, 44, 24), MUTED, false, 1)
		draw_line(Vector2(x - 21, current), Vector2(x + 21, current), PAPER, 3)
		for sign_x in [-1, 1]:
			draw_line(Vector2(x + sign_x * 27, expected), Vector2(x + sign_x * 57, expected), AMBER, 3)
		_text(Vector2(x - 26, 326), "LEFT" if side == 0 else "RIGHT", MONO, 16, MUTED)
	_text(Vector2(578, 148), "TRIM  /  DETENTS", MONO, 17, MUTED)
	for side in 2:
		var y := 190 + side * 87
		_text(Vector2(578, y), "LEFT" if side == 0 else "RIGHT", MONO, 15, MUTED)
		_text(Vector2(578, y + 32), "%02d" % _settings[side], HEAD, 34, AMBER)
