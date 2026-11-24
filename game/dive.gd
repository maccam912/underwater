extends Node3D

const Jacket = preload("res://world/jacket.gd")
const Helmet = preload("res://ui/helmet.gd")
const Sound = preload("res://audio/sound.gd")
const FieldTool = preload("res://game/field_tool.gd")
const Visor = preload("res://ui/visor.gdshader")
const TAGS := ["A2", "B4"]
const BELL := Jacket.BELL
const SITES := [Jacket.A2, Jacket.B4]
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
var brace_start := Transform3D.IDENTITY
var brace_time := 0.0
var brace_duration := 0.8
var work_look := Vector2.ZERO
var work_look_finger := -1
var work_hint_time := 0.0
var interface := CanvasLayer.new()
var mode := "title"
var watch := 1
var done := [false,false]
var values := [[-1,-1],[-1,-1]]
var history: Array = []
var job := -1
var sample := ""
var brief := "Ellis has the bell. Choose a docket when you’re ready."
var callout := ""
var radio_time := 0.0
var yaw := 0.0
var pitch := 0.0
var last_pos := BELL
var underway := false
var move_finger := -1
var look_finger := -1
var move_origin := Vector2.ZERO
var stick := Vector2.ZERO
var save_tick := 0.0
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
		var field_tool := FieldTool.new()
		jacket.add_child(field_tool)
		tools_at_sites.append(field_tool)
		field_tool.adjusted.connect(_tool_adjusted)
		field_tool.submitted.connect(_tool_submitted)
		field_tool.hint_changed.connect(_tool_hint)
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
	mode = next
	stick = Vector2.ZERO
	hud.joystick = Vector2.ZERO
	hud.joystick_origin = Vector2.ZERO
	move_finger = -1
	look_finger = -1
	work_look_finger = -1
	diver.velocity = Vector3.ZERO
	if DisplayServer.get_name() != "headless" and not touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if next=="dive" else Input.MOUSE_MODE_VISIBLE
	_focus_lamp(0.0)
	light.rotation.y = -0.018
	spill.rotation.y = 0.0
	if next in ["title","board","log"]:
		_stage_camera()
	else:
		_align_camera()
	sound.set_outside(next in ["dive","tool","pause"])
	hud.display(next,{"touch":touch,"watch":watch,"done":done,"job":job,"message":brief,"history":history,"resume":underway})
	hud.set_lamp(lamp_on)
	if next == "tool":
		instrument = tools_at_sites[job]
		brace_start = camera.global_transform
		brace_time = 0.0
		brace_duration = clampf(diver.position.distance_to(instrument.stance()) / 2.2,0.35,1.5)
		work_look = Vector2.ZERO
		instrument.set_working(true)
		_tool_hint(instrument.instruction(touch))
	elif next == "dive":
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
				brief = "Mara moved the survey kit to the next pair of pads."
				_save_watch()
				_show("board")
		"context": _context()
		"unbrace": _release_grip()
		"lamp":
			if mode in ["dive","tool"]:
				lamp_on = not lamp_on
				_set_light(lamp_on)
				hud.set_lamp(lamp_on)
				sound.cue("adjust")
				_save_watch()
		"pause": _show("pause")
		"continue": _show("dive")
		"recover": _at_bell()
		"log","board","title":
			if mode in ["dive","pause","tool"]:
				_save_watch()
			_show(action)

func _take_job(index: int) -> void:
	if done[index]:
		return
	job = index
	sample = ""
	underway = true
	diver.position = BELL
	_face(Vector3(0.2,-0.7,-9.0))
	last_pos = BELL
	sound.cue("hatch")
	_show("dive")
	var direction := "left, at the upright" if job==0 else "right and slightly down"
	var controls := "Swim left thumb, look right thumb." if touch else "WASD to fin. F for your lamp."
	_say("Noor — %s is %s. %s" % [TAGS[job],direction,controls],13)
	_save_watch()

func _at_bell() -> void:
	sound.cue("hatch")
	diver.position = BELL
	last_pos = BELL
	underway = false
	if job>=0 and not sample.is_empty():
		done[job] = true
		history.append("Watch %02d   ·   %s" % [watch,sample])
		if history.size()>12:
			history.pop_front()
		brief = "Signed by Noor. " + sample
		job = -1
		sample = ""
		sound.cue("accept")
	else:
		brief = "Back on the bell. Your tool settings are on the sheet."
	_show("board")
	_save_watch()

func _face(point: Vector3) -> void:
	var offset := point-diver.position
	if offset.length_squared()<0.001:
		return
	yaw = atan2(-offset.x,-offset.z)
	pitch = asin(clampf(offset.normalized().y,-1,1))

func _align_camera() -> void:
	camera.position = diver.position
	camera.rotation = Vector3(pitch,yaw,0.0)
	_set_light(lamp_on)

func _target() -> Vector3:
	return BELL if not sample.is_empty() or job<0 else SITES[job]

func _can_work() -> bool:
	if job < 0 or diver.position.distance_to(SITES[job]) >= REACH:
		return false
	return diver.position.z > tools_at_sites[job].focus_point().z + 0.2

func _context() -> void:
	if mode != "dive":
		return
	if not sample.is_empty() and diver.position.distance_to(BELL)<BELL_REACH:
		_at_bell()
	elif sample.is_empty() and _can_work():
		_show("tool")
	else:
		_face(_target())
		_align_camera()
		_say("Ellis  /  Bell lamp straight ahead. I’ve got your line." if not sample.is_empty() else "Noor  /  On that heading. Look for the %s plate."%TAGS[job])

func _release_grip() -> void:
	if mode == "tool":
		_show("dive")
		if not sample.is_empty():
			_say("Noor — Got it. Bring the sheet home.",5.0)

func _tool_hint(words: String) -> void:
	if mode == "tool":
		work_hint_time = 9.0
		hud.update_work(words)

func _tool_adjusted(settings: Array) -> void:
	values[job] = settings.duplicate()
	sound.cue("adjust")
	_save_watch()

func _tool_submitted(success: bool, detail: String) -> void:
	sound.cue("accept" if success else "reject")
	if not success:
		_tool_hint(detail)
		return
	sample = detail
	jacket.set_station_filed(job,true)
	instrument.set_filed(true)
	var release := "Let go when ready." if touch else "E to let go."
	_tool_hint("Noor — %s  %s" % [detail,release])
	_save_watch()

func _say(words: String, seconds := 8.0) -> void:
	callout = words
	radio_time = seconds
	sound.cue("comms")
	_update_helm()

func _physics_process(delta: float) -> void:
	if mode == "tool":
		_settle_on_grip(delta)
		return
	if mode != "dive":
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
			_face(_target())
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
	diver.position.y = clampf(diver.position.y,-8.5,7.0)
	last_pos = diver.position
	_align_camera()
	jacket.update_diver(diver.position)
	radio_time = maxf(0,radio_time-delta)
	save_tick += delta
	if save_tick>2.5:
		save_tick = 0
		_save_watch()
	_update_helm()

func _settle_on_grip(delta: float) -> void:
	if work_hint_time > 0.0:
		work_hint_time = maxf(0.0,work_hint_time-delta)
		if work_hint_time == 0.0:
			hud.update_work("")
	brace_time = minf(brace_time + delta, brace_duration)
	var blend := smoothstep(0.0,brace_duration,brace_time)
	var stance: Vector3 = instrument.stance()
	var point: Vector3 = instrument.focus_point()
	var facing := Basis.looking_at((point-stance).normalized(),Vector3.UP)
	var angles := facing.get_euler() + Vector3(work_look.y,work_look.x,0.0)
	var rotation_goal := Basis.from_euler(angles)
	camera.global_transform = Transform3D(brace_start.basis.slerp(rotation_goal,blend),brace_start.origin.lerp(stance,blend))
	diver.position = camera.position
	yaw = camera.rotation.y
	pitch = camera.rotation.x
	last_pos = diver.position
	_focus_lamp(blend)
	_set_light(lamp_on)
	jacket.update_diver(diver.position)

func _key(a: Key,b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0

func _update_helm() -> void:
	if mode != "dive":
		return
	var offset := _target()-diver.position
	var near := offset.length()<BELL_REACH if not sample.is_empty() else _can_work()
	var relative := wrapf(yaw-atan2(-offset.x,-offset.z),-PI,PI)
	var target := "Bell 2" if not sample.is_empty() else "%s  %s" % [TAGS[job],"Survey" if job==0 else "Clamp"]
	var action := "BEARING"
	if near:
		action = "FILE SHEET" if not sample.is_empty() else "BRACE"
	var words := callout if radio_time>0 else ""
	hud.update_helm(126-diver.position.y,target,offset.length(),relative,action,words,near)

func _look(delta: Vector2,sensitivity: float) -> void:
	yaw = wrapf(yaw-delta.x*sensitivity,-PI,PI)
	pitch = clampf(pitch-delta.y*sensitivity,-1.38,1.38)
	_align_camera()

func _input(event: InputEvent) -> void:
	if mode!="dive":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative,0.0025)
	if event is InputEventScreenTouch and not event.pressed:
		if event.index==move_finger:
			move_finger=-1
			stick=Vector2.ZERO
			hud.joystick=stick
			hud.joystick_origin=Vector2.ZERO
		if event.index==look_finger:
			look_finger=-1
	elif event is InputEventScreenDrag:
		if event.index==move_finger:
			stick=((event.position-move_origin)/53.0).limit_length(1)
			hud.joystick=stick
		elif event.index==look_finger:
			_look(event.relative,0.005)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			_back()
			get_viewport().set_input_as_handled()
			return
		if mode in ["dive","tool"] and event.physical_keycode == KEY_F:
			_command("lamp")
			get_viewport().set_input_as_handled()
			return
		if mode in ["dive","tool"] and event.physical_keycode==KEY_E:
			if mode=="tool":
				_release_grip()
			else:
				_context()
			get_viewport().set_input_as_handled()
			return
	if mode == "tool":
		_work_input(event)
		return
	if mode!="dive" or not event is InputEventScreenTouch or not event.pressed:
		return
	var p: Vector2=event.position
	if p.x < hud.size.x*0.49 and move_finger<0:
		move_finger=event.index
		move_origin=p
		hud.joystick_origin=p
	elif p.x>=hud.size.x*0.49 and look_finger<0:
		look_finger=event.index

func _work_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if brace_time < brace_duration:
		return
	if sample.is_empty() and instrument.handle_input(event,camera):
		get_viewport().set_input_as_handled()
		return
	var motion := Vector2.ZERO
	if event is InputEventScreenTouch:
		if event.pressed:
			work_look_finger = event.index
		elif work_look_finger==event.index:
			work_look_finger = -1
	elif event is InputEventScreenDrag and event.index == work_look_finger:
		motion = event.relative
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		motion = event.relative
	if motion != Vector2.ZERO:
		work_look.x = clampf(work_look.x-motion.x*0.002,-0.25,0.25)
		work_look.y = clampf(work_look.y-motion.y*0.002,-0.18,0.18)

func _back() -> void:
	match mode:
		"dive": _show("pause")
		"tool": _release_grip()
		"pause": _show("dive")
		"log": _show("board")
		"board": _show("title")

func _notification(what: int) -> void:
	if not ready_for_save:
		return
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_CLOSE_REQUEST,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_save_watch()
		if mode in ["dive","tool"]:
			_show("pause")

func _save_watch() -> void:
	if save_path.is_empty() or not ready_for_save:
		return
	var config := ConfigFile.new()
	for field in ["watch","job","done","values","sample","history","last_pos","yaw","pitch","underway","lamp_on"]:
		config.set_value("watch",field,get(field))
	if config.save(save_path+".tmp")==OK:
		var error := DirAccess.rename_absolute(save_path+".tmp",save_path)
		if error!=OK:
			push_warning("Could not replace watch log (%d)"%error)

func _load_watch() -> void:
	var config := ConfigFile.new()
	if config.load(save_path)!=OK:
		return
	var saved_done = config.get_value("watch","done",[])
	var saved_values = config.get_value("watch","values",[])
	if not saved_done is Array or saved_done.size()!=2 or not saved_values is Array or saved_values.size()!=2:
		return
	for pair in saved_values:
		if not pair is Array or pair.size()!=2:
			return
	lamp_on = bool(config.get_value("watch","lamp_on",true))
	watch = maxi(1,int(config.get_value("watch","watch",1)))
	done = saved_done
	values = saved_values
	job = clampi(int(config.get_value("watch","job",-1)),-1,1)
	sample = str(config.get_value("watch","sample",""))
	var records = config.get_value("watch","history",[])
	if records is Array:
		history = records
	var position_value = config.get_value("watch","last_pos",BELL)
	if position_value is Vector3 and position_value.is_finite():
		last_pos = BELL+(position_value-BELL).limit_length(EXCURSION)
	yaw = float(config.get_value("watch","yaw",0))
	pitch = clampf(float(config.get_value("watch","pitch",0)),-1.38,1.38)
	underway = bool(config.get_value("watch","underway",false)) and job>=0 and not done[job]
