extends Node3D

const Jacket = preload("res://world/jacket.gd")
const Helmet = preload("res://ui/helmet.gd")
const Sound = preload("res://audio/sound.gd")
const SurveyWork = preload("res://game/survey_work.gd")
const ClampWork = preload("res://game/clamp_work.gd")
const Visor = preload("res://ui/visor.gdshader")
const TAGS := ["A2", "B4"]
const BELL := Jacket.BELL
const REACH := 2.15
const BELL_REACH := 3.0
const EXCURSION := 42.0


var jacket: Node3D
var diver := CharacterBody3D.new()
var suit := SphereShape3D.new()
var camera := Camera3D.new()
var light := SpotLight3D.new()
var spill := SpotLight3D.new()
var lamp_on := true
var hud = Helmet.new()
var sound = Sound.new()
var tools_at_sites: Array[Node3D] = []
var instrument: Node3D
var last_hand_view := Transform3D.IDENTITY
var work_hint := ""
var lamp_focus := 0.0
var interface := CanvasLayer.new()
var mode := "title"
var watch := 1
var done := [false,false]
var values := [[-1,-1],[-1,-1]]
var history: Array = []
var reports: Array = []
var job := -1
var sample := ""
var sheet_readings: Array = []
var brief := "Just you outside. Ellis tends your line. Noor has you on the hardline."
var callout := ""
var radio_time := 0.0
var yaw := 0.0
var pitch := 0.0
var last_pos := BELL
var underway := false
var returning := false
var move_finger := -1
var look_finger := -1
var move_origin := Vector2.ZERO
var stick := Vector2.ZERO
var save_tick := 0.0
var work_dirty := false
var last_tool_sound := -1000
var touch := false
var save_path := "user://watch.cfg"
var ready_for_save := false
var check_resume_clearance := false

func _ready() -> void:
	touch = OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args()
	if not save_path.is_empty():
		_load_watch()
	jacket = Jacket.new()
	add_child(jacket)
	diver.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	diver.floor_snap_length = 0.0
	var collision := CollisionShape3D.new()
	suit.radius = 0.38
	collision.shape = suit
	diver.add_child(collision)
	add_child(diver)
	diver.position = BELL
	add_child(camera)
	camera.current = true
	camera.fov = 68
	camera.near = 0.1
	camera.far = 110
	# A warm sealed-beam work lamp sits above the diver’s left temple.
	light.name = "HelmetLamp"
	light.position = Vector3(-0.24,0.16,0.02)
	light.rotation.y = -0.018
	light.light_color = Color("#f1eaca")
	light.spot_range = 28.0
	light.spot_attenuation = 0.54
	light.spot_angle_attenuation = 2.85
	light.shadow_enabled = true
	light.shadow_bias = 0.11
	light.shadow_reverse_cull_face = true
	camera.add_child(light)
	spill.name = "LampSpill"
	spill.position = light.position
	spill.light_color = Color("#9ebbb3")
	spill.spot_range = 13.5
	spill.spot_attenuation = 0.72
	spill.spot_angle_attenuation = 2.65
	camera.add_child(spill)
	add_child(sound)
	add_child(interface)
	var grain := ColorRect.new()
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = Visor
	grain.material = material
	interface.add_child(grain)
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.command.connect(_command)
	for i in 2:
		var field_tool: Node3D = SurveyWork.new() if i == 0 else ClampWork.new()
		jacket.add_child(field_tool)
		tools_at_sites.append(field_tool)
		field_tool.adjusted.connect(_tool_adjusted)
		field_tool.submitted.connect(_tool_submitted)
		field_tool.hint_changed.connect(_tool_hint)
		field_tool.station_changed.connect(_station_changed)
		_prepare_site(i)
	ready_for_save = true
	_show("title")

func _prepare_site(index: int) -> void:
	var filed: bool = done[index] or (job==index and not sample.is_empty())
	tools_at_sites[index].configure(index,watch,values[index])
	tools_at_sites[index].set_filed(filed)
	jacket.set_station_filed(index,filed)

func _set_light(active: bool) -> void:
	light.visible = active
	spill.visible = active
	jacket.update_lamp(light.global_transform,active)

func _focus_lamp(work: float) -> void:
	# Flood at the workface so the diver can read both sides of the fitting.
	light.spot_angle = lerpf(33.0,48.0,work)
	light.light_energy = lerpf(3.6,1.25,work)
	spill.spot_angle = lerpf(57.0,61.0,work)
	spill.light_energy = lerpf(0.83,0.86,work)
	jacket.update_lamp_focus(light.spot_angle, work)

func _stage_camera() -> void:
	jacket.update_diver(Vector3(9,-5,18))
	camera.position = Vector3(-11.5,-1.4,12.2)
	camera.look_at(Vector3(-4.7,0.35,-5.2), Vector3.UP)
	light.rotation.y = deg_to_rad(-21.0)
	light.spot_angle = 41.0
	jacket.update_lamp_focus(light.spot_angle)
	spill.rotation.y = light.rotation.y
	_set_light(true)

func _show(next: String) -> void:
	if instrument != null:
		instrument.set_working(false)
		instrument = null
	work_hint = ""
	mode = next
	stick = Vector2.ZERO
	hud.joystick = Vector2.ZERO
	hud.joystick_origin = Vector2.ZERO
	move_finger = -1
	look_finger = -1
	diver.velocity = Vector3.ZERO
	if DisplayServer.get_name() != "headless" and not touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if next=="dive" else Input.MOUSE_MODE_VISIBLE
	lamp_focus = 0.0
	_focus_lamp(lamp_focus)
	light.rotation.y = -0.018
	spill.rotation.y = 0.0
	if next in ["title","board","log"]:
		_stage_camera()
	else:
		_align_camera()
	sound.set_outside(next in ["dive","tool","pause"])
	var stops := [tools_at_sites[0].station_name(), tools_at_sites[1].station_name()]
	hud.display(next,{"touch":touch,"watch":watch,"done":done,"job":job,"message":brief,"history":history,"reports":reports,"stops":stops,"resume":underway,"returning":returning,"sheet_ready":not sample.is_empty()})
	hud.set_lamp(lamp_on)
	if next == "dive":
		_update_helm()

func _command(action: String) -> void:
	match action:
		"start":
			if underway and job >= 0:
				diver.position = last_pos
				check_resume_clearance = true
				_show("dive")
				_say("Ellis  /  Still with you. Same sheet.")
			else:
				_show("board")
		"job0","job1": _take_job(0 if action=="job0" else 1)
		"next":
			if done[0] and done[1]:
				watch += 1
				done = [false,false]
				values = [[-1,-1],[-1,-1]]
				for i in 2:
					_prepare_site(i)
				brief = "Mara’s relief sheet is in. Same crew today. Ellis has the bell."
				_save_watch()
				_show("board")
		"context": _context()
		"lamp":
			if mode in ["dive","tool"]:
				lamp_on = not lamp_on
				_set_light(lamp_on)
				hud.set_lamp(lamp_on)
				sound.cue("adjust")
				_save_watch()
		"pause":
			_show("pause")
			_save_watch()
		"continue": _show("dive")
		"recover","resume_job":
			returning = action == "recover"
			_show("dive")
			_say("Ellis — " + _bearing())
			_save_watch()
		"log","board","title":
			if mode in ["dive","pause","tool"]:
				_save_watch()
			_show(action)

func _take_job(index: int) -> void:
	if done[index]:
		return
	job = index
	sample = ""
	sheet_readings.clear()
	underway = true
	returning = false
	diver.position = BELL
	last_pos = BELL
	sound.cue("hatch")
	_show("dive")
	var controls := "Left thumb swims. Drag the water to look." if touch else "WASD to fin. Mouse to look."
	_say("Ellis — I have your line. %s %s" % [_bearing(), controls], 10)
	_save_watch()

func _at_bell() -> void:
	sound.cue("hatch")
	diver.position = BELL
	last_pos = BELL
	underway = false
	returning = false
	if job>=0 and not sample.is_empty():
		done[job] = true
		var entry := "Watch %02d   ·   %s" % [watch,sample]
		history.append(entry)
		if not sheet_readings.is_empty():
			reports.append({"watch": watch, "tag": TAGS[job], "entry": entry, "readings": sheet_readings.duplicate(true)})
		if history.size() > 12:
			var expired: String = history.pop_front()
			if not reports.is_empty() and reports.front().entry == expired:
				reports.pop_front()
		brief = "Signed by Noor. " + sample
		job = -1
		sample = ""
		sheet_readings.clear()
		sound.cue("accept")
	else:
		brief = "Back on the bell. Your place and tool settings are on the sheet."
	_show("board")
	_save_watch()

func _align_camera() -> void:
	camera.position = diver.position
	camera.rotation = Vector3(pitch,yaw,0.0)
	_set_light(lamp_on)

func _target() -> Vector3:
	return BELL if _heading_home() or job < 0 else tools_at_sites[job].swim_target()

func _heading_home() -> bool:
	return returning or not sample.is_empty()

func _can_work(reach: float) -> bool:
	if job < 0 or _heading_home():
		return false
	var tool := tools_at_sites[job]
	var offset: Vector3 = tool.focus_point() - diver.position
	return (offset.length_squared() <= reach * reach and tool.to_local(diver.global_position).z > 0.15
			and -camera.global_basis.z.dot(offset.normalized()) > 0.02)

func _bearing() -> String:
	var offset := _target() - diver.position
	var station: String = "Bell 2" if _heading_home() else tools_at_sites[job].station_name()
	if offset.length() < 0.8:
		return "%s is within reach." % station
	var vertical := ""
	if absf(offset.y) > 1.0:
		vertical = ", %.0f m %s" % [absf(offset.y), "above" if offset.y > 0.0 else "below"]
	if Vector2(offset.x, offset.z).length() < 1.0:
		return "%s%s you." % [station, vertical] if not vertical.is_empty() else "%s is within reach." % station
	var clockwise := wrapf(yaw - atan2(-offset.x, -offset.z), -PI, PI)
	var hour := posmod(roundi(clockwise * 12.0 / TAU), 12)
	return "%s, %d o’clock%s. Range %.0f m." % [station, 12 if hour == 0 else hour, vertical, offset.length()]

func _context() -> void:
	if mode not in ["dive","tool"]:
		return
	if _heading_home() and diver.position.distance_to(BELL) < BELL_REACH:
		_at_bell()
	else:
		_say("Ellis — " + _bearing())

func _leave_work() -> void:
	if instrument == null:
		return
	instrument.set_working(false)
	instrument = null
	mode = "dive"
	work_hint = ""
	_save_watch()

func _update_work() -> void:
	if mode == "tool":
		if not _can_work(REACH + 0.35):
			_leave_work()
	elif _can_work(REACH):
		instrument = tools_at_sites[job]
		mode = "tool"
		radio_time = 0.0
		instrument.set_working(true)
		_tool_hint(instrument.instruction(touch))

func _tool_hint(words: String) -> void:
	if mode == "tool":
		work_hint = words
		_update_helm()

func _tool_adjusted(settings: Array) -> void:
	if mode != "tool" or instrument == null:
		return
	values[job] = settings.duplicate(true)
	work_dirty = true
	if Time.get_ticks_msec() - last_tool_sound > 200:
		last_tool_sound = Time.get_ticks_msec()
		sound.cue("adjust")

func _station_changed(detail: String) -> void:
	if mode != "tool":
		return
	_leave_work()
	sound.cue("accept")
	_say(detail, 14)

func _tool_submitted(success: bool, detail: String) -> void:
	sound.cue("accept" if success else "reject")
	if not success:
		_tool_hint(detail)
		return
	sample = detail
	sheet_readings = instrument.inspection_record().duplicate(true)
	jacket.set_station_filed(job,true)
	values[job] = instrument.snapshot()
	_leave_work()
	tools_at_sites[job].set_filed(true)
	_say("Noor — %s Bring the sheet back to Ellis." % detail, 12.0)

func _say(words: String, seconds := 8.0) -> void:
	callout = words
	radio_time = seconds
	sound.cue("comms")
	_update_helm()

func _physics_process(delta: float) -> void:
	if mode not in ["dive","tool"]:
		return
	if check_resume_clearance:
		check_resume_clearance = false
		# A saved swim from the earlier jacket can now be inside a larger member.
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = suit
		query.transform = diver.global_transform
		query.exclude = [diver.get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
			diver.position = BELL
			_say("Ellis — You're on my line at the bell. I've kept your sheet.")
	var axes := Vector2(
		_key(KEY_D,KEY_RIGHT)-_key(KEY_A,KEY_LEFT),
		_key(KEY_S,KEY_DOWN)-_key(KEY_W,KEY_UP)
	) + stick
	axes = axes.limit_length(1.0)
	var rise := _key(KEY_SPACE,KEY_R)-_key(KEY_Q,KEY_PAGEDOWN)
	var direction := camera.basis.x*axes.x + camera.basis.z*axes.y + Vector3.UP*rise
	var wanted := direction.limit_length(1.0)*1.65
	diver.velocity = diver.velocity.move_toward(wanted,delta*4.5)
	diver.move_and_slide()
	# Ellis tends a short excursion around this working level.
	var offset := diver.position - BELL
	diver.position = BELL+offset.limit_length(EXCURSION)
	last_pos = diver.position
	_align_camera()
	_update_work()
	if instrument != null and not last_hand_view.is_equal_approx(camera.global_transform):
		last_hand_view = camera.global_transform
		instrument.follow_view(camera)
	var new_focus := move_toward(lamp_focus, 1.0 if instrument != null else 0.0, delta*2.5)
	if lamp_focus != new_focus:
		lamp_focus = new_focus
		_focus_lamp(lamp_focus)
	jacket.update_diver(diver.position)
	var horizontal := Vector2(diver.position.x, diver.position.z)
	var near_face := Geometry2D.get_closest_point_to_segment(horizontal,
		Vector2(Jacket.A2.x, Jacket.A2.z), Vector2(Jacket.B4.x, Jacket.B4.z))
	sound.set_distance_to_steel(horizontal.distance_to(near_face))
	radio_time = maxf(0,radio_time-delta)
	save_tick += delta
	if save_tick > (1.5 if work_dirty else 2.5):
		save_tick = 0
		_save_watch()
	_update_helm()

func _key(a: Key,b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0

func _update_helm() -> void:
	if mode not in ["dive","tool"]:
		return
	var at_bell := _heading_home() and diver.position.distance_to(BELL) < BELL_REACH
	var words := callout if radio_time > 0.0 else work_hint
	hud.update_helm(words, at_bell, not sample.is_empty(), instrument != null)

func _look(delta: Vector2,sensitivity: float) -> void:
	yaw = wrapf(yaw-delta.x*sensitivity,-PI,PI)
	pitch = clampf(pitch-delta.y*sensitivity,-1.565,1.565)
	_align_camera()

func _input(event: InputEvent) -> void:
	if mode not in ["dive","tool"]:
		return
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and not touch:
		_look(event.relative, 0.0025)
	if event is InputEventScreenTouch and not event.pressed:
		if event.index == move_finger:
			move_finger = -1
			stick = Vector2.ZERO
			hud.joystick = stick
			hud.joystick_origin = Vector2.ZERO
			hud.queue_redraw()
		if event.index == look_finger:
			look_finger = -1
	elif event is InputEventScreenDrag:
		if event.index == move_finger:
			stick = ((event.position-move_origin)/53.0).limit_length(1)
			hud.joystick = stick
			hud.queue_redraw()
		elif event.index == look_finger:
			_look(event.relative, 0.005)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
			get_viewport().set_input_as_handled()
			return
		if mode in ["dive","tool"]:
			match event.physical_keycode:
				KEY_F: _command("lamp")
				KEY_E: _context()
				_: return
			get_viewport().set_input_as_handled()
			return
	if mode not in ["dive","tool"]:
		return
	# Leave space for the swimming thumb even when the diver is close to steel.
	if touch and event is InputEventScreenTouch and event.pressed and move_finger < 0:
		if event.position.x < hud.size.x*0.14 and event.position.y > hud.size.y*0.74:
			_begin_swim_touch(event)
			get_viewport().set_input_as_handled()
			return
	if instrument != null and not event is InputEventKey:
		var hand_event := event
		if event is InputEventMouse:
			if event.device == InputEvent.DEVICE_ID_EMULATION:
				return
			if not touch:
				# The hand follows the same ray as the centre of the moving helmet.
				hand_event = event.duplicate()
				hand_event.position = get_viewport().get_visible_rect().get_center()
		if instrument.handle_input(hand_event, camera):
			last_hand_view = camera.global_transform
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventScreenTouch or not event.pressed:
		return
	if event.position.x < hud.size.x * 0.49 and move_finger < 0:
		_begin_swim_touch(event)
	elif look_finger < 0:
		look_finger = event.index

func _begin_swim_touch(event: InputEventScreenTouch) -> void:
	move_finger = event.index
	move_origin = event.position
	hud.joystick_origin = move_origin
	hud.queue_redraw()

func _back() -> void:
	match mode:
		"dive","tool": _command("pause")
		"pause": _show("dive")
		"log": _show("board")
		"board": _show("title")

func _notification(what: int) -> void:
	if not ready_for_save:
		return
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_CLOSE_REQUEST,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if mode in ["dive","tool"]:
			_show("pause")
		_save_watch()

func _save_watch() -> void:
	if save_path.is_empty() or not ready_for_save:
		return
	if mode == "tool" and instrument != null:
		values[job] = instrument.snapshot()
	var config := ConfigFile.new()
	for field in ["watch","job","done","values","sample","sheet_readings","history","reports","last_pos","yaw","pitch","underway","returning","lamp_on"]:
		config.set_value("watch",field,get(field))
	if config.save(save_path+".tmp")==OK:
		var error := DirAccess.rename_absolute(save_path+".tmp",save_path)
		if error!=OK:
			push_warning("Could not replace watch log (%d)"%error)
		else:
			work_dirty = false
			save_tick = 0.0

func _load_watch() -> void:
	var config := ConfigFile.new()
	if config.load(save_path)!=OK:
		return
	var saved_done = config.get_value("watch","done",[])
	var saved_values = config.get_value("watch","values",[])
	if not saved_done is Array or saved_done.size()!=2 or not saved_values is Array or saved_values.size()!=2:
		return
	for pair in saved_values:
		if not pair is Array:
			return
	lamp_on = bool(config.get_value("watch","lamp_on",true))
	watch = maxi(1,int(config.get_value("watch","watch",1)))
	done = saved_done
	values = saved_values
	job = clampi(int(config.get_value("watch","job",-1)),-1,1)
	sample = str(config.get_value("watch","sample",""))
	var saved_sheet = config.get_value("watch","sheet_readings",[])
	if saved_sheet is Array and not sample.is_empty():
		sheet_readings = saved_sheet
	var records = config.get_value("watch","history",[])
	if records is Array:
		history = records
	var saved_reports = config.get_value("watch","reports",[])
	if saved_reports is Array:
		for report in saved_reports:
			if report is Dictionary and report.get("entry") in history and report.get("readings") is Array:
				reports.append(report)
	var position_value = config.get_value("watch","last_pos",BELL)
	if position_value is Vector3 and position_value.is_finite():
		last_pos = BELL+(position_value-BELL).limit_length(EXCURSION)
	yaw = float(config.get_value("watch","yaw",0))
	pitch = clampf(float(config.get_value("watch","pitch",0)),-1.565,1.565)
	underway = bool(config.get_value("watch","underway",false)) and job>=0 and not done[job]
	returning = underway and bool(config.get_value("watch","returning", false))
