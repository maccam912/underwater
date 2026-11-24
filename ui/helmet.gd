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
		"dive": _underwater()
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

func _button(words: String, action: String, at: Vector2, area: Vector2, font: Font, pixels: int, ink: Color, on_paper := true, on_press := Callable()) -> Button:
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
	button.pressed.connect(on_press if on_press.is_valid() else func(): command.emit(action))
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
	_heading(p,"BELL 2   /   TWO-PERSON RUN   /   126 m","Diver’s sheet")
	_text("Watch %02d" % view.watch,p+Vector2(322,85),Vector2(125,34),TYPE,20,STAMP)
	for i in 2:
		var y := 143+i*76
		var done: bool = view.done[i]
		var wording := ["A2   Survey the sleeve","B4   Fit the carriers"][i] as String
		var b := _button(wording,"job%d"%i,p+Vector2(2,y),Vector2(447,49),TYPE,22,PENCIL)
		b.disabled = done
		var status := "Filed" if done else ("Resume →" if i==view.job else "Take →")
		var status_label := _text(status,p+Vector2(333,y+9),Vector2(110,38),HAND,25,STAMP if done else BIRO)
		status_label.rotation = deg_to_rad(-3 if done else -1)
		_text("Signed by Noor" if done else str(view.stops[i]),p+Vector2(3,y+44),Vector2(441,20),TYPE,15,FADED)
		_rule(p+Vector2(1,y+70),447)
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
	var reports: Array = view.get("reports", [])
	var selection: int = view.get("selected_report", -1)
	if selection >= 0 and selection < reports.size() and reports[selection] is Dictionary:
		_inspection_sheet(p, reports[selection])
		return

	_heading(p, "BELL COPY    /    KESTREL", "Handover")
	var sheets: Array = []
	var recorded := {}
	for i in reports.size():
		if reports[i] is Dictionary:
			recorded[reports[i].get("entry", "")] = i
	# Older saves have only the signed line. Keep those entries in the same book.
	for entry in view.get("history", []):
		sheets.append(recorded.get(entry,entry))
	for i in reports.size():
		if reports[i] is Dictionary and not sheets.has(i):
			sheets.append(i)
	sheets.reverse()
	if sheets.is_empty():
		_text("I’ll look at your readings when I take the next watch.  — Mara",
			p+Vector2(1,145), Vector2(437,90), HAND,25,BIRO,true)
		_rule(p+Vector2(0,244),447)
		_text("First sheet still open.",p+Vector2(1,255),Vector2(439,45),TYPE,18,FADED)
	else:
		var index_page: int = clampi(view.get("book_index", 0), 0, ceili(sheets.size()/4.0)-1)
		for offset in mini(4, sheets.size()-index_page*4):
			var item = sheets[index_page*4+offset]
			var pos := p+Vector2(2,147+offset*54)
			if item is int:
				var report: Dictionary = reports[item]
				var tag := str(report.get("tag",""))
				var title := "Wall thickness" if tag=="A2" else "Riser guides"
				var label := "Watch %02d   %s   %s  →" % [int(report.get("watch",1)),tag,title]
				_button(label,"sheet_%d"%item,pos,Vector2(445,51),TYPE,19,PENCIL,true,
					_open_report.bind(item))
			else:
				_text(str(item),pos,Vector2(446,51),TYPE,16,PENCIL,true)
			_rule(pos+Vector2(0,52),445)
		_book_paging(p,index_page,ceili(sheets.size()/4.0),"book_index")
	_button("← Dive sheet","board",p+Vector2(0,385),Vector2(163,60),HAND,25,BIRO)

func _open_report(index: int) -> void:
	view.selected_report = index
	view.readings_page = 0
	rebuild()

func _turn_book(field: String, number: int) -> void:
	view[field] = number
	rebuild()

func _book_paging(p: Vector2, number: int, total: int, field: String) -> void:
	if total <= 1:
		return
	if number > 0:
		_button("‹ Prev","prev",p+Vector2(194,383),Vector2(90,60),HAND,23,BIRO,true,
			_turn_book.bind(field,number-1))
	_text("%d / %d" % [number+1,total],p+Vector2(288,388),Vector2(70,49),TYPE,17,FADED)
	if number+1 < total:
		_button("Next ›","more",p+Vector2(366,383),Vector2(80,60),HAND,23,BIRO,true,
			_turn_book.bind(field,number+1))

func _inspection_sheet(p: Vector2, report: Dictionary) -> void:
	var site := str(report.get("tag",""))
	var title := "Wall thickness" if site=="A2" else "Riser guides"
	_heading(p, "WATCH %02d    /    %s    /    BELL COPY" % [int(report.get("watch",1)),site],title)
	var readings: Array = report.get("readings", [])
	if site=="A2" and not readings.is_empty():
		var total := ceili(readings.size()/8.0)
		var number := clampi(view.get("readings_page",0),0,total-1)
		var cols := [1,105,257,355]
		var headers := ["BAND","POINT","WALL mm","REPEAT mm"]
		for c in cols.size():
			_text(headers[c],p+Vector2(cols[c],144),Vector2(105,25),TYPE,16,FADED)
		for j in mini(8,readings.size()-number*8):
			var r: Dictionary = readings[number*8+j]
			var repeat_reading = r.get("repeat_mm")
			var repeat_text := "%.1f" % float(repeat_reading) if repeat_reading is float or repeat_reading is int else "—"
			var fields := [str(r.get("band","")).capitalize(),str(r.get("point","")),
				"%.1f" % float(r.get("thickness_mm",0)),repeat_text]
			for c in cols.size():
				_text(fields[c],p+Vector2(cols[c],170+j*25),Vector2(150,26),TYPE,17,PENCIL)
		_book_paging(p,number,total,"readings_page")
	elif site=="B4" and not readings.is_empty():
		var total := ceili(readings.size()/2.0)
		var number := clampi(view.get("readings_page",0),0,total-1)
		for j in mini(2,readings.size()-number*2):
			var r: Dictionary = readings[number*2+j]
			var pos := p+Vector2(2,142+j*116)
			var bolting := "%d fasteners at %s N·m" % [int(r.get("fasteners",0)),r.get("torque_nm","—")]
			var gaps := "Gap   left %s mm    right %s mm" % [r.get("left_gap_mm","—"),r.get("right_gap_mm","—")]
			_text(str(r.get("location","B4")),pos,Vector2(109,36),HAND,25,BIRO)
			_text(bolting,pos+Vector2(115,0),Vector2(332,36),TYPE,17,PENCIL)
			_text(gaps,pos+Vector2(0,35),Vector2(445,28),TYPE,17,PENCIL)
			_text(str(r.get("fit","")),pos+Vector2(0,62),Vector2(445,44),TYPE,16,FADED,true)
			_rule(pos+Vector2(0,111),445)
		_book_paging(p,number,total,"readings_page")
	else:
		_text(str(report.get("entry","")),p+Vector2(2,151),Vector2(445,185),TYPE,18,PENCIL,true)
	_button("← Handover","book_index",p+Vector2(0,385),Vector2(178,60),HAND,25,BIRO,true,
		_open_report.bind(-1))

func _pause() -> void:
	var p := _sheet()
	_heading(p,"BELL 2    /    HARDLINE","Holding station")
	var resume_work: bool = view.returning and not view.sheet_ready
	for i in 3:
		var words := ["Continue the dive","Get a bearing to the job" if resume_work else "Get a bearing to the bell","Close the book"][i] as String
		var action := ["continue","resume_job" if resume_work else "recover","title"][i] as String
		_button(words+"  →",action,p+Vector2(1,150+i*75),Vector2(446,66),HAND,29,BIRO)
		_rule(p+Vector2(1,216+i*75),446)
	var note := "The line is tended. Your watch is saved."
	if not touch:
		note = "WASD swim · mouse look · Q / Space trim\nAim + drag to work · E call · F lamp"
	_text(note,p+Vector2(0,381),Vector2(448,65),TYPE,16,PENCIL,true)

func _underwater() -> void:
	if touch:
		_button("","pause",Vector2(size.x-right_edge-51,top_edge),Vector2(54,54),TYPE,16,CHALK,false)
		context_button = _button("Call bell","context",Vector2(size.x-right_edge-138,size.y-bottom_edge-62),Vector2(138,62),HAND,25,CHALK,false)
		context_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_button("","lamp",Vector2(_lamp_x()-27,top_edge),Vector2(56,54),TYPE,16,CHALK,false)
	else:
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

func update_helm(message: String, at_bell: bool, sheet_ready: bool, can_reach: bool, faint := false) -> void:
	if mode != "dive" or not is_instance_valid(context_button):
		return
	var verb := "Call bell"
	if at_bell:
		verb = "Hand over" if sheet_ready else "Enter bell"
	context_button.text = verb if touch else "[E] "+verb
	radio_text.text = message
	# Crosstalk on the hardline arrives thin and greenish, from no one in particular.
	radio_text.add_theme_color_override("font_color",Color("93a99a") if faint else Color("#e0dcca"))
	if in_reach != can_reach:
		in_reach = can_reach
		queue_redraw()

func _lamp_x() -> float:
	return size.x-right_edge-87

func _draw() -> void:
	if mode != "dive":
		return
	if not touch:
		if in_reach:
			draw_circle(size * 0.5, 2.0, SHADOW)
			draw_circle(size * 0.5, 1.1, CHALK)
		return
	var controls := Color(CHALK,0.74)
	var pause_at := Vector2(size.x-right_edge-23,top_edge+26)
	draw_line(pause_at+Vector2(-3,-6),pause_at+Vector2(-3,6),controls,2,true)
	draw_line(pause_at+Vector2(3,-6),pause_at+Vector2(3,6),controls,2,true)
	var bulb := Vector2(_lamp_x(),top_edge+26)
	draw_polyline(PackedVector2Array([bulb+Vector2(-10,-3),bulb+Vector2(-3,-3),bulb+Vector2(3,-6),bulb+Vector2(3,6),bulb+Vector2(-3,3),bulb+Vector2(-10,3),bulb+Vector2(-10,-3)]),controls,1.5,true)
	var beam := controls if lamp_on else Color(CHALK,0.22)
	for i in range(-1,2):
		draw_line(bulb+Vector2(6,3*i),bulb+Vector2(13,6*i),beam,1.4,true)
	if joystick_origin!=Vector2.ZERO:
		draw_arc(joystick_origin,40,0,TAU,36,Color(CHALK,0.22),1.4,true)
		draw_circle(joystick_origin+joystick*28,11,Color(CHALK,0.29))
