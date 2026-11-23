extends Control

signal command(action: String)

const TYPE := preload("res://ui/fonts/CourierPrime-Regular.ttf")
const HAND := preload("res://ui/fonts/Kalam-Regular.ttf")
const CLOTH := preload("res://art/kept_logbook.webp")
const SLATE := preload("res://art/dive_slate.webp")
const PROP_LIGHT := preload("res://ui/curtain.gdshader")

const PENCIL := Color("#342b22")
const FADED := Color("#524637")
const BIRO := Color("#2e3838")
const STAMP := Color("#703b29")
const CHALK := Color("#d0c5a9")
const DIM := Color("#aba694")
const SHADOW := Color("#141614")

var mode := ""
var view := {}
var page: Control
var touch := false
var edge := 26.0
var right_edge := 26.0
var top_edge := 12.0
var bottom_edge := 14.0
var context_button: Button
var radio_text: Label
var joystick := Vector2.ZERO
var joystick_origin := Vector2.ZERO
var in_reach := false
var lamp_on := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_resized)

func _resized() -> void:
	if is_inside_tree() and not mode.is_empty():
		rebuild.call_deferred()

func display(new_mode: String, data: Dictionary) -> void:
	mode = new_mode
	view = data
	touch = bool(view.get("touch",false))
	in_reach = false
	rebuild()

func _safe_edges() -> void:
	edge = 26
	right_edge = 26
	top_edge = 12
	bottom_edge = 14
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var physical := DisplayServer.screen_get_size()
		if safe.size.x > 0 and physical.x > 0:
			var ratio := size.x / physical.x
			edge = maxf(edge,safe.position.x * ratio+8)
			right_edge = maxf(right_edge,(physical.x-safe.end.x) * ratio+8)
			top_edge = maxf(top_edge,safe.position.y * ratio+5)
			bottom_edge = maxf(bottom_edge,(physical.y-safe.end.y) * ratio+5)

func rebuild() -> void:
	if not is_inside_tree() or size.x < 1:
		return
	_safe_edges()
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	page = Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	context_button = null
	radio_text = null
	match mode:
		"title": _title()
		"board": _board()
		"log": _logbook()
		"pause": _pause()
		"dive","tool": _underwater()
	queue_redraw()

func _text(words: String, at: Vector2, area: Vector2, font: Font, pixels: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = words
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",color)
	label.add_theme_constant_override("line_spacing",-3)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = at
	label.size = area
	page.add_child(label)
	return label

func _ink_line(points: PackedVector2Array, color: Color, thickness := 1.0) -> void:
	var mark := Line2D.new()
	mark.width = thickness
	mark.default_color = color
	mark.points = points
	mark.antialiased = true
	page.add_child(mark)

func _rule(at: Vector2, width: float, ink := Color("#514630a6")) -> void:
	_ink_line([at,at+Vector2(width*0.42,0.4),at+Vector2(width,0)],ink)

func _button(words: String, action: String, at: Vector2, area: Vector2, font: Font, pixels: int, ink: Color, on_paper := true) -> Button:
	var button := Button.new()
	button.name = action
	button.text = words
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.position = at
	button.size = area
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",pixels)
	button.add_theme_color_override("font_color",ink)
	button.add_theme_color_override("font_disabled_color",FADED)
	var hover := STAMP if on_paper else Color("#e2d7b9")
	for theme_color in ["font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(theme_color,hover)
	for key in ["normal","disabled","pressed","hover"]:
		button.add_theme_stylebox_override(key,StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(ink,0.5)
	focus.border_width_bottom = 1
	button.add_theme_stylebox_override("focus",focus)
	button.pressed.connect(func(): command.emit(action))
	page.add_child(button)
	return button

func _surface(texture: Texture2D, at: Vector2, area: Vector2, tilt: float) -> void:
	page.pivot_offset = at+area*0.5
	page.rotation = deg_to_rad(tilt)
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.position = at
	image.size = area
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lamp := ShaderMaterial.new()
	lamp.shader = PROP_LIGHT
	image.material = lamp
	page.add_child(image)

func _title() -> void:
	var origin := Vector2(edge+15, size.y-bottom_edge-307)
	var dimensions := Vector2(367,306)
	_surface(CLOTH,origin,dimensions,-3.6)
	var heading := _text("Underwater",origin+Vector2(42,54),Vector2(310,80),HAND,52,PENCIL)
	heading.rotation = deg_to_rad(0.9)
	_text("Kestrel   /   east jacket",origin+Vector2(49,147),Vector2(299,27),TYPE,17,CHALK)
	_text("Bell 2,   126 metres",origin+Vector2(51,174),Vector2(290,32),HAND,24,CHALK)
	var words := "Resume watch" if view.resume else "Open dive sheet"
	_button(words+"   →","start",origin+Vector2(48,222),Vector2(291,64),HAND,29,Color("#eee0b8"),false)
	_rule(origin+Vector2(48,272),222,Color("#ddd2b27a"))

func _sheet() -> Vector2:
	var origin := Vector2(edge+11,(size.y-494)*0.5)
	_surface(SLATE,origin,Vector2(533,494),-1.1)
	return origin+Vector2(43,0)

func _heading(p: Vector2, identifier: String, title: String) -> void:
	_text(identifier,p+Vector2(0,57),Vector2(449,24),TYPE,15,FADED)
	_text(title,p+Vector2(-1,80),Vector2(440,53),HAND,38,BIRO)
	_rule(p+Vector2(0,134),448)

func _board() -> void:
	var p := _sheet()
	_heading(p,"BELL 2    EAST JACKET    126 m","Diver’s sheet")
	_text("Watch %02d" % view.watch,p+Vector2(322,85),Vector2(125,34),TYPE,20,STAMP)
	for i in 2:
		var y := 151+i*66
		var done: bool = view.done[i]
		var wording := ["A2   Wall thickness","B4   Fit survey clamp"][i] as String
		var b := _button(wording,"job%d"%i,p+Vector2(2,y),Vector2(447,58),TYPE,22,PENCIL)
		b.disabled = done
		var status := "Filed" if done else ("Resume →" if i==view.job else "Take →")
		var status_label := _text(status,p+Vector2(333,y+9),Vector2(110,38),HAND,25,STAMP if done else BIRO)
		status_label.rotation = deg_to_rad(-3 if done else -1)
		_rule(p+Vector2(1,y+56),447)
	_text(str(view.message),p+Vector2(2,289),Vector2(444,70),HAND,23,BIRO,true)
	_rule(p+Vector2(0,374),447)
	_button("Handover book","log",p+Vector2(0,387),Vector2(215,64),HAND,26,BIRO)
	_rule(p+Vector2(1,436),150,BIRO)
	var both_done: bool = view.done[0] and view.done[1]
	var words := "Next watch →" if both_done else "Close book"
	var act := "next" if both_done else "title"
	_button(words,act,p+Vector2(272,387),Vector2(178,64),HAND,26,BIRO)
	_rule(p+Vector2(274,436),139 if both_done else 128,BIRO)

func _logbook() -> void:
	var p := _sheet()
	_heading(p,"BELL COPY    /    KESTREL","Handover")
	_text("Two clean marks at A2. Carrier was still in our basket. Left them for you to look at.  — Mara",p+Vector2(1,144),Vector2(446,93),HAND,23,BIRO,true)
	_rule(p+Vector2(0,249),447)
	_text("SIGNED SHEETS",p+Vector2(1,259),Vector2(430,24),TYPE,16,FADED)
	var entries: Array = view.history
	if entries.is_empty():
		_text("First sheet still open.",p+Vector2(2,286),Vector2(439,45),HAND,23,BIRO)
	else:
		for i in mini(2,entries.size()):
			_text(str(entries[entries.size()-1-i]),p+Vector2(2,284+i*49),Vector2(446,48),TYPE,16,PENCIL,true)
	_button("←  Dive sheet","board",p+Vector2(0,387),Vector2(233,64),HAND,27,BIRO)
	_rule(p+Vector2(1,437),153,BIRO)

func _pause() -> void:
	var p := _sheet()
	_heading(p,"BELL 2    /    HARDLINE","Holding station")
	for i in 3:
		var words := ["Continue the dive","Follow the line to the bell","Close the book"][i] as String
		var action := ["continue","recover","title"][i] as String
		_button(words+"  →",action,p+Vector2(1,150+i*75),Vector2(446,66),HAND,29,BIRO)
		_rule(p+Vector2(1,216+i*75),446)
	var note := "The line is tended. Your watch is saved."
	if not touch:
		note = "WASD swim · mouse look · Q / Space trim\nE use or call · F lamp · Esc pause"
	_text(note,p+Vector2(0,381),Vector2(448,65),TYPE,16,PENCIL,true)

func _underwater() -> void:
	if touch:
		if mode=="dive":
			_button("","pause",Vector2(size.x-right_edge-51,top_edge),Vector2(54,54),TYPE,16,CHALK,false)
			context_button = _button("Call bell","context",Vector2(size.x-right_edge-138,size.y-bottom_edge-62),Vector2(138,62),HAND,25,CHALK,false)
			context_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			_button("Let go","unbrace",Vector2(size.x-right_edge-104,top_edge),Vector2(105,57),HAND,25,CHALK,false)
		_button("","lamp",Vector2(_lamp_x()-27,top_edge),Vector2(56,54),TYPE,16,CHALK,false)
	elif mode=="dive":
		context_button = _button("","context",Vector2(size.x-right_edge-166,size.y-bottom_edge-60),Vector2(166,60),TYPE,18,CHALK,false)
		context_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var width := minf(size.x*0.61,680)
	radio_text = _text("",Vector2((size.x-width)*0.5,size.y-bottom_edge-79),Vector2(width,75),TYPE,18,Color("#e0dcca"),true)
	radio_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radio_text.add_theme_constant_override("outline_size",3)
	radio_text.add_theme_color_override("font_outline_color",Color("#141712"))

func set_lamp(enabled: bool) -> void:
	if lamp_on != enabled:
		lamp_on = enabled
		queue_redraw()

func update_work(hint: String) -> void:
	if mode=="tool" and is_instance_valid(radio_text):
		radio_text.text = hint

func update_helm(_depth: float, _target: String, _distance: float, _relative_bearing: float, action: String, msg: String, near: bool) -> void:
	if mode!="dive" or not is_instance_valid(context_button):
		return
	var verb := action.capitalize()
	if action=="BEARING":
		verb = "Call bell"
	elif action=="FILE SHEET":
		verb = "Hand over"
	context_button.text = verb if touch else ("[E] "+verb if near else "")
	radio_text.text = msg
	in_reach = near
	queue_redraw()

func _lamp_x() -> float:
	return size.x-right_edge-(87 if mode=="dive" else 140)

func _draw() -> void:
	if mode not in ["tool","dive"]:
		return
	if mode=="dive" and in_reach:
		var center := size*0.5
		draw_circle(center,1.6,Color(CHALK,0.65))
	if not touch:
		return
	var controls := Color(CHALK,0.74)
	if mode=="dive":
		var pause_at := Vector2(size.x-right_edge-23,top_edge+26)
		draw_line(pause_at+Vector2(-3,-6),pause_at+Vector2(-3,6),controls,2,true)
		draw_line(pause_at+Vector2(3,-6),pause_at+Vector2(3,6),controls,2,true)
	var bulb := Vector2(_lamp_x(),top_edge+26)
	draw_polyline(PackedVector2Array([bulb+Vector2(-10,-3),bulb+Vector2(-3,-3),bulb+Vector2(3,-6),bulb+Vector2(3,6),bulb+Vector2(-3,3),bulb+Vector2(-10,3),bulb+Vector2(-10,-3)]),controls,1.5,true)
	var beam := controls if lamp_on else Color(CHALK,0.22)
	for i in range(-1,2):
		draw_line(bulb+Vector2(6,3*i),bulb+Vector2(13,6*i),beam,1.4,true)
	if mode=="dive" and joystick_origin!=Vector2.ZERO:
		draw_arc(joystick_origin,40,0,TAU,36,Color(CHALK,0.22),1.4,true)
		draw_circle(joystick_origin+joystick*28,11,Color(CHALK,0.29))
