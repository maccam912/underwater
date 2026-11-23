extends Control

signal command(action: String)
const HEAD = preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
const BODY = preload("res://ui/fonts/Barlow-Regular.ttf")
const MONO = preload("res://ui/fonts/CourierPrime-Regular.ttf")
const INK := Color("#10292d")
const DEEP := Color("#0b2024")
const PAPER := Color("#e6e4d6")
const PALE := Color("#b2c9c1")
const TEAL := Color("#79a7a2")
const AMBER := Color("#f0bc69")
const RULE := Color("#4c7273")
const FILM = preload("res://ui/curtain.gdshader")

var mode := ""
var view := {}
var page: Control
var touch := false
var edge := 32.0
var right_edge := 32.0
var top_edge := 18.0
var bottom_edge := 18.0
var depth_text: Label
var destination_text: Label
var context_button: Button
var radio_text: Label
var joystick := Vector2.ZERO
var joystick_origin := Vector2.ZERO
var bearing := 0.0
var in_reach := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_resized)

func _resized() -> void:
	if is_inside_tree() and not mode.is_empty():
		rebuild.call_deferred()

func display(new_mode: String, data: Dictionary) -> void:
	mode = new_mode
	view = data
	touch = bool(view.get("touch", false))
	rebuild()

func _safe_edges() -> void:
	edge = 32
	right_edge = 32
	top_edge = 18
	bottom_edge = 18
	if not OS.has_feature("mobile"):
		return
	var safe := DisplayServer.get_display_safe_area()
	var physical := DisplayServer.screen_get_size()
	if safe.size.x <= 0 or physical.x <= 0:
		return
	var scale_factor := size.x / physical.x
	edge = maxf(edge, safe.position.x * scale_factor + 10)
	right_edge = maxf(right_edge, (physical.x - safe.end.x) * scale_factor + 10)
	top_edge = maxf(top_edge, safe.position.y * scale_factor + 6)
	bottom_edge = maxf(bottom_edge, (physical.y - safe.end.y) * scale_factor + 6)

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
	depth_text = null
	destination_text = null
	radio_text = null
	match mode:
		"title": _title()
		"board": _board()
		"log": _logbook()
		"pause": _pause()
		"dive": _dive()
	queue_redraw()

func _box(x: float,y: float,w: float,h: float,color: Color) -> ColorRect:
	var item := ColorRect.new()
	item.color = color
	item.position = Vector2(x,y)
	item.size = Vector2(w,h)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(item)
	return item

func _text(value: String, x: float, y: float, width: float, height: float, font: Font, pixels: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var item := Label.new()
	item.text = value
	if wrap:
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_override("font",font)
	item.add_theme_font_size_override("font_size",pixels)
	item.add_theme_color_override("font_color",color)
	item.horizontal_alignment = align
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.position = Vector2(x,y)
	item.size = Vector2(width,height)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(item)
	return item

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	return style

func _button(value: String, action: String, x: float,y: float,w: float,h: float, primary := false, pixels := 22) -> Button:
	var button := Button.new()
	button.name = action
	button.text = value
	button.add_theme_font_override("font", HEAD)
	button.add_theme_font_size_override("font_size", pixels)
	for kind in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(kind, INK if primary else PAPER)
	button.add_theme_color_override("font_disabled_color", TEAL)
	button.add_theme_stylebox_override("normal", _style(AMBER if primary else Color("#163034ef"), AMBER if primary else RULE))
	button.add_theme_stylebox_override("hover", _style(Color("#ffd095") if primary else Color("#2d4d4e"), PAPER))
	button.add_theme_stylebox_override("pressed", _style(Color("#d8a158") if primary else Color("#1d494b"), AMBER))
	button.add_theme_stylebox_override("disabled", _style(DEEP, RULE))
	var focus := _style(Color.TRANSPARENT, PAPER)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus",focus)
	button.position = Vector2(x,y)
	button.size = Vector2(w,h)
	button.pressed.connect(func(): command.emit(action))
	page.add_child(button)
	return button

func _curtain() -> void:
	var film := _box(0,0,size.x,size.y,Color.WHITE)
	var shader := ShaderMaterial.new()
	shader.shader = FILM
	film.material = shader

func _brand(x: float,y: float) -> void:
	_box(x,y+1,5,16,AMBER)
	_box(x+8,y+5,5,12,AMBER)
	_box(x+16,y+9,5,8,AMBER)
	_text("KESTREL   /   SUBSEA OPERATIONS",x+32,y-3,310,24,MONO,15,PALE)

func _title() -> void:
	_curtain()
	var x := edge + 10
	var y := size.y * 0.30
	_brand(x,top_edge+8)
	_text("Underwater",x-3,y-20,530,114,HEAD,102,PAPER)
	_box(x,y+97,39,3,AMBER)
	_text("Maintenance watch",x,y+111,410,35,BODY,29,PAPER)
	_text("East jacket   /   North Sea",x,y+151,440,28,MONO,17,PALE)
	_button("RESUME WATCH    ›" if view.resume else "OPEN DIVE SHEET    ›","start",x,y+209,242,57,true)
	var fy := size.y-bottom_edge-39
	_box(x,fy,size.x-x-right_edge,1,Color("#53716f99"))
	_text("KST–04     /     BELL OPERATIONS",x,fy+8,390,25,MONO,14,PALE)
	_text("STORAGE DEPTH    126 m",size.x-right_edge-244,fy+8,244,25,MONO,14,PAPER,HORIZONTAL_ALIGNMENT_RIGHT)

func _sheet(title: String, sub: String) -> Vector2:
	_curtain()
	var x := edge + 10
	var y := maxf(top_edge+4,(size.y-502)*0.5)
	_box(x,y,540,4,AMBER)
	_box(x,y+4,540,471,Color("#10282bf4"))
	_text(sub,x+22,y+15,494,24,MONO,15,PALE)
	_text(title,x+20,y+36,500,67,HEAD,52,PAPER)
	_box(x+22,y+108,496,1,RULE)
	return Vector2(x+22,y)

func _board() -> void:
	var p := _sheet("Dive sheet", "KST–04    /    WATCH %02d    /    BELL 2" % view.watch)
	_text("EAST JACKET   /   AVAILABLE WORK",p.x,p.y+119,494,27,MONO,16,AMBER)
	for i in 2:
		var done: bool = view.done[i]
		var y := p.y+156+i*89
		var wording := ["A2     Wall thickness survey","B4     Fit survey clamp"][i] as String
		var b := _button(wording,"job%d"%i,p.x,y,496,65,false,25)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = done
		var status := "FILED" if done else "TAKE  ›"
		if i == view.job and not done:
			status = "RESUME  ›"
		_text(status,p.x+327,y+17,151,30,MONO,16,TEAL if done else AMBER,HORIZONTAL_ALIGNMENT_RIGHT)
	var desc := str(view.message)
	_text(desc,p.x,p.y+328,496,54,BODY,20,PAPER,HORIZONTAL_ALIGNMENT_LEFT,true)
	_button("HANDOVER BOOK","log",p.x,p.y+395,210,57)
	if view.done[0] and view.done[1]:
		_button("NEXT WATCH    ›","next",p.x+225,p.y+395,271,57,true)
	else:
		_button("TITLE","title",p.x+351,p.y+395,145,57)

func _logbook() -> void:
	var p := _sheet("Handover book","KST–04    /    BELL COPY")
	_text("FROM THE PREVIOUS WATCH",p.x,p.y+120,492,26,MONO,16,AMBER)
	_text("“Two clean marks at A2. Carrier was still in our basket. Left them for you to look at.”  — Mara",p.x,p.y+155,493,69,BODY,22,PAPER,HORIZONTAL_ALIGNMENT_LEFT,true)
	_box(p.x,p.y+242,496,1,RULE)
	_text("LAST SIGNED ENTRIES",p.x,p.y+254,490,23,MONO,15,TEAL)
	var lines: Array = view.history
	if lines.is_empty():
		_text("Your first sheet is still open.",p.x,p.y+285,490,30,BODY,21,PAPER)
	else:
		for i in mini(3,lines.size()):
			_text(str(lines[lines.size()-1-i]),p.x,p.y+282+i*30,495,29,BODY,19,PAPER)
	_button("BACK TO DIVE SHEET","board",p.x,p.y+395,232,57,true)

func _pause() -> void:
	var p := _sheet("Holding position","HARDLINE    /    BELL 2")
	_text("Your line is tended. Take your time.",p.x,p.y+122,490,40,BODY,23,PALE)
	_button("CONTINUE DIVE    ›","continue",p.x,p.y+179,496,58,true)
	_button("FOLLOW LINE BACK TO BELL","recover",p.x,p.y+251,496,58)
	_button("SAVE & RETURN TO TITLE","title",p.x,p.y+323,496,58)
	_text("Watch progress is saved aboard this device.",p.x,p.y+407,496,34,BODY,19,PALE)

func _dive() -> void:
	var x := edge
	var y := top_edge
	_box(x,y,266,68,Color("#0a2227df"))
	_box(x,y,4,68,AMBER)
	_text("DIVE CONTROL   /   02",x+13,y+5,246,21,MONO,14,PALE)
	destination_text = _text("",x+13,y+25,246,36,HEAD,26,PAPER)
	depth_text = _text("",size.x*0.5-100,y,200,25,MONO,17,PAPER,HORIZONTAL_ALIGNMENT_CENTER)
	_button("II","pause",size.x-right_edge-64,y,64,60,false,25)
	radio_text = _text("",x,y+78,minf(580,size.x*0.62),64,BODY,20,PAPER,HORIZONTAL_ALIGNMENT_LEFT,true)
	radio_text.add_theme_constant_override("outline_size",5)
	radio_text.add_theme_color_override("font_outline_color",Color("#10272b"))
	radio_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	context_button = _button("BEARING","context",size.x-right_edge-175,size.y-bottom_edge-65,175,65)
	if not touch:
		_text("WASD  Swim     Mouse  Look     Q / Space  Trim",x,size.y-bottom_edge-44,600,42,MONO,15,PALE)
	else:
		_text("SWIM",x+10,size.y-bottom_edge-24,106,24,MONO,15,PALE,HORIZONTAL_ALIGNMENT_CENTER)

func update_helm(depth: float, target: String, distance: float, relative_bearing: float, action: String, msg: String, near: bool) -> void:
	if not is_instance_valid(context_button):
		return
	destination_text.text = "%s    /    %d m" % [target,roundi(distance)]
	depth_text.text = "DEPTH  %.1f m" % depth
	radio_text.text = msg
	context_button.text = action if touch else "[E]  " + action
	bearing = relative_bearing
	in_reach = near
	queue_redraw()

func _draw() -> void:
	if mode != "dive":
		return
	var middle := size * 0.5
	var c := AMBER if in_reach else Color("#d7e6d497")
	draw_arc(middle,6,0,TAU,24,c,1.25,true)
	draw_circle(middle,1.3,c)
	var center := Vector2(size.x*0.5,top_edge+40)
	for i in range(-5,6):
		var tick := center+Vector2(i*12,0)
		draw_line(tick,tick+Vector2(0,7 if i%5==0 else 3),PALE,1)
	var pointer := center+Vector2(clampf(bearing/PI,-1,1)*60,-2)
	draw_colored_polygon(PackedVector2Array([pointer,pointer+Vector2(-4,-6),pointer+Vector2(4,-6)]),AMBER)
	if touch:
		var origin := joystick_origin if joystick_origin != Vector2.ZERO else Vector2(edge+63,size.y-bottom_edge-78)
		draw_circle(origin,48,Color("#18343a55"))
		draw_arc(origin,48,0,TAU,64,Color("#abc1b687"),2,true)
		draw_circle(origin+joystick*32,19,Color("#c1d2bc77"))
