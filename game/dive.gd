extends Node3D

const Jacket = preload("res://world/jacket.gd")
const Helmet = preload("res://ui/helmet.gd")
const Sound = preload("res://audio/sound.gd")
const Instrument = preload("res://ui/instrument.gd")
const Visor = preload("res://ui/visor.gdshader")
const TAGS := ["A2", "B4"]
const BELL := Jacket.BELL
const SITES := [Jacket.A2, Jacket.B4]
const REACH := 3.25


var jacket: Node3D
var diver := CharacterBody3D.new()
var camera := Camera3D.new()
var light := SpotLight3D.new()
var hud = Helmet.new()
var sound = Sound.new()
var instrument: Control
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

func _ready() -> void:
	touch = OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args()
	if not save_path.is_empty():
		_load_watch()
	jacket = Jacket.new()
	add_child(jacket)
	diver.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	diver.floor_snap_length = 0.0
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.38
	collision.shape = shape
	diver.add_child(collision)
	add_child(diver)
	diver.position = BELL
	add_child(camera)
	camera.current = true
	camera.fov = 68
	camera.near = 0.1
	camera.far = 110
	light.light_color = Color("#c9e5d8")
	light.light_energy = 2.2
	light.spot_range = 17.0
	light.spot_angle = 32.0
	light.spot_angle_attenuation = 0.85
	light.shadow_enabled = false
	camera.add_child(light)
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
		jacket.set_station_filed(i,done[i] or (job==i and not sample.is_empty()))
	ready_for_save = true
	_show("title")

func _stage_camera() -> void:
	jacket.update_diver(Vector3(9,-5,18))
	camera.position = Vector3(-11.5,-1.4,12.2)
	camera.look_at(Vector3(-4.7,0.35,-5.2), Vector3.UP)
	light.visible = true

func _show(next: String) -> void:
	mode = next
	stick = Vector2.ZERO
	hud.joystick = Vector2.ZERO
	hud.joystick_origin = Vector2.ZERO
	move_finger = -1
	look_finger = -1
	diver.velocity = Vector3.ZERO
	if is_instance_valid(instrument):
		interface.remove_child(instrument)
		instrument.queue_free()
		instrument = null
	if DisplayServer.get_name() != "headless" and not touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if next=="dive" else Input.MOUSE_MODE_VISIBLE
	if next in ["title","board","log"]:
		_stage_camera()
	else:
		_align_camera()
	sound.set_outside(next in ["dive","tool","pause"])
	hud.display(next,{"touch":touch,"watch":watch,"done":done,"job":job,"message":brief,"history":history,"resume":underway})
	if next == "tool":
		instrument = Instrument.new()
		interface.add_child(instrument)
		instrument.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		instrument.adjusted.connect(_tool_adjusted)
		instrument.submitted.connect(_tool_submitted)
		instrument.exited.connect(func(): _show("dive"))
		instrument.configure(job,watch,values[job])
	if next == "dive":
		_update_helm()

func _command(action: String) -> void:
	match action:
		"start":
			if underway and job >= 0:
				diver.position = last_pos
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
					jacket.set_station_filed(i,false)
				brief = "Mara moved the survey kit to the next pair of pads."
				_save_watch()
				_show("board")
		"context": _context()
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
	var controls := "Left thumb swims. Drag right to look." if touch else "Move with WASD. Look with the mouse."
	_say("Noor  /  %s is %s. %s" % [TAGS[job],direction,controls],13)
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
	light.visible = true

func _target() -> Vector3:
	return BELL if not sample.is_empty() or job<0 else SITES[job]

func _context() -> void:
	if mode != "dive":
		return
	if not sample.is_empty() and diver.position.distance_to(BELL)<REACH:
		_at_bell()
	elif sample.is_empty() and job>=0 and diver.position.distance_to(SITES[job])<REACH:
		_face(SITES[job]+Vector3(0,0,-1.6))
		_show("tool")
	else:
		_face(_target())
		_align_camera()
		_say("Ellis  /  Bell lamp straight ahead. I’ve got your line." if not sample.is_empty() else "Noor  /  On that heading. Look for the %s plate."%TAGS[job])

func _tool_adjusted(settings: Array) -> void:
	values[job] = settings.duplicate()
	sound.cue("adjust")
	_save_watch()

func _tool_submitted(success: bool, detail: String) -> void:
	sound.cue("accept" if success else "reject")
	if not success:
		return
	sample = detail
	jacket.set_station_filed(job,true)
	_show("dive")
	_say("Noor  /  %s Turn back to the amber bell." % detail,12)
	_save_watch()

func _say(words: String, seconds := 8.0) -> void:
	callout = words
	radio_time = seconds
	sound.cue("comms")
	_update_helm()

func _physics_process(delta: float) -> void:
	if mode != "dive":
		return
	var axes := Vector2(
		_key(KEY_D,KEY_RIGHT)-_key(KEY_A,KEY_LEFT),
		_key(KEY_S,KEY_DOWN)-_key(KEY_W,KEY_UP)
	) + stick
	axes = axes.limit_length(1.0)
	var rise := _key(KEY_SPACE,KEY_R)-_key(KEY_Q,KEY_F)
	var direction := camera.basis.x*axes.x + camera.basis.z*axes.y + Vector3.UP*rise
	var wanted := direction.limit_length(1.0)*1.65
	diver.velocity = diver.velocity.move_toward(wanted,delta*4.5)
	diver.move_and_slide()
	# Ellis tends a short excursion around this working level.
	var offset := diver.position - BELL
	diver.position = BELL+offset.limit_length(30)
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

func _key(a: Key,b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0

func _update_helm() -> void:
	if mode != "dive":
		return
	var offset := _target()-diver.position
	var near := offset.length()<REACH
	var relative := wrapf(yaw-atan2(-offset.x,-offset.z),-PI,PI)
	var target := "Bell 2" if not sample.is_empty() else "%s  %s" % [TAGS[job],"Survey" if job==0 else "Clamp"]
	var action := "BEARING"
	if near:
		action = "FILE SHEET" if not sample.is_empty() else "BRACE"
	var words := callout if radio_time>0 else ""
	if touch and words.is_empty() and not near:
		words = "Swim toward the amber bearing. Tap Bearing to face the mark."
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
		elif mode=="dive" and event.physical_keycode==KEY_E:
			_context()
			get_viewport().set_input_as_handled()
	if mode!="dive" or not event is InputEventScreenTouch or not event.pressed:
		return
	var p: Vector2=event.position
	if p.x < hud.size.x*0.49 and move_finger<0:
		move_finger=event.index
		move_origin=p
		hud.joystick_origin=p
	elif p.x>=hud.size.x*0.49 and look_finger<0:
		look_finger=event.index

func _back() -> void:
	match mode:
		"dive": _show("pause")
		"tool","pause": _show("dive")
		"log": _show("board")
		"board": _show("title")

func _notification(what: int) -> void:
	if not ready_for_save:
		return
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_CLOSE_REQUEST,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_save_watch()
		if mode=="dive":
			_show("pause")

func _save_watch() -> void:
	if save_path.is_empty() or not ready_for_save:
		return
	var config := ConfigFile.new()
	for field in ["watch","job","done","values","sample","history","last_pos","yaw","pitch","underway"]:
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
		last_pos = BELL+(position_value-BELL).limit_length(30)
	yaw = float(config.get_value("watch","yaw",0))
	pitch = clampf(float(config.get_value("watch","pitch",0)),-1.38,1.38)
	underway = bool(config.get_value("watch","underway",false)) and job>=0 and not done[job]
