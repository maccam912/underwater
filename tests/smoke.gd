extends SceneTree

const Dive = preload("res://game/dive.tscn")
const SurveyRoute = preload("res://tests/survey_route.gd")
const ClampRoute = preload("res://tests/clamp_route.gd")
var failed := false
var desktop_route := "--desktop-route" in OS.get_cmdline_user_args()
var reload_checked := [false, false]

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		printerr("FAILED  ",message)
		failed = true

func check_grip(work, handle: Vector3) -> void:
	var glove = work._glove
	check(glove.is_visible_in_tree(), "a working hand is visible on the held tool")
	check(glove.gauntlet.global_position.distance_to(handle) < 0.004, "the glove grips the tool's actual handle")
	var elbow: Vector3 = glove.upper.to_global(Vector3.UP * glove.UPPER_LENGTH)
	check(elbow.distance_to(glove.forearm.global_position) < 0.004, "the upper sleeve meets the forearm")
	check(is_equal_approx(glove.forearm.global_basis.y.length(), 1.0), "reaching does not stretch the forearm")
	var eye: Vector3 = work.get_viewport().get_camera_3d().global_position
	var cuff: Vector3 = glove.gauntlet.to_global(glove.WRIST + Vector3.BACK * glove._size / glove.HAND_SCALE)
	var sleeve_end: Vector3 = glove.forearm.to_global(Vector3.UP * glove.FOREARM_LENGTH)
	var across_cuff := (cuff - eye).slide(eye.direction_to(sleeve_end))
	check(across_cuff.length() < 0.035, "the visible sleeve ends inside the wrist seal")

func _aim(game, target: Vector3) -> void:
	var offset := (target - Vector3(game.diver.position)).normalized()
	var yaw := atan2(-offset.x, -offset.z)
	var pitch := asin(clampf(offset.y,-1.0,1.0))
	game._look(Vector2(wrapf(game.yaw-yaw,-PI,PI), game.pitch-pitch), 1.0)

func _swim(game) -> void:
	if game.mode == "dive" and game.job >= 0 and game.values[game.job].size() > 2 and not reload_checked[game.job]:
		_check_restore(game)
		reload_checked[game.job] = true
	var initial: Transform3D = game.camera.global_transform
	game._context()
	check(game.camera.global_transform.is_equal_approx(initial), "calling the bell preserves the diver's viewpoint")
	if game.mode == "board":
		return
	var destination: Vector3 = game._target()
	_aim(game,destination)
	game.stick = Vector2.UP
	for tick in 1400:
		await physics_frame
		if game.diver.position.distance_to(destination) < 0.32:
			break
	game.stick = Vector2.ZERO
	for tick in 35:
		await physics_frame
	if not game._heading_home():
		_aim(game, game.tools_at_sites[game.job].focus_point())
	else:
		game._context()
	await physics_frame
	await physics_frame

func _check_free_movement(game) -> void:
	var start: Vector3 = game.diver.position
	var direction: float = game.yaw
	game._look(Vector2(0.7,-0.1),1.0)
	var turned: Transform3D = game.camera.global_transform
	game._context()
	for frame in 4:
		await physics_frame
	check(turned.is_equal_approx(game.camera.global_transform), "a tool in reach never recentres or moves the diver")
	game.stick = Vector2.RIGHT
	for frame in 17:
		await physics_frame
	game.stick = Vector2.ZERO
	for frame in 23:
		await physics_frame
	check(game.diver.position.distance_to(start) > 0.12, "the diver can fin sideways with tools in reach")
	game._look(Vector2(PI,0),1.0)
	await physics_frame
	await physics_frame
	check(game.mode == "dive" and absf(wrapf(game.yaw-direction,-PI,PI)) > 2, "the diver can turn completely away from a job")
	check(not game.tools_at_sites[game.job]._glove.is_visible_in_tree(), "leaving a worksite stows the working hand")
	_aim(game, game.tools_at_sites[game.job].focus_point())
	await physics_frame
	await physics_frame
	check(game.mode == "tool", "looking back puts the same equipment within reach")

func _settle() -> void:
	for i in 100:
		await physics_frame

func _mouse_to(game, target: Vector3, held: bool) -> void:
	var ray := (target-Vector3(game.diver.position)).normalized()
	var event := InputEventMouseMotion.new()
	event.position = root.get_visible_rect().get_center()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	event.relative = Vector2(wrapf(game.yaw-atan2(-ray.x,-ray.z),-PI,PI), game.pitch-asin(ray.y)) / 0.0025
	root.push_input(event,true)

func _touch_at(game, point: Vector3, pressed: bool) -> void:
	if desktop_route:
		_mouse_to(game, point, not pressed)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = root.get_visible_rect().get_center()
		root.push_input(click,true)
	else:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = game.camera.unproject_position(point)
		event.pressed = pressed
		root.push_input(event,true)

func _tap(game, point: Vector3) -> void:
	_touch_at(game,point,true)
	_touch_at(game,point,false)

func _drag_at(game, point: Vector3, previous: Vector3) -> void:
	if desktop_route:
		_mouse_to(game, point, true)
	else:
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = game.camera.unproject_position(point)
		event.relative = event.position-game.camera.unproject_position(previous)
		root.push_input(event,true)

func _instance(path: String):
	var game = Dive.instantiate()
	game.save_path = path
	root.add_child(game)
	return game

func _check_restore(game) -> void:
	game._save_watch()
	var restored = _instance(game.save_path)
	check(restored.values == game.values, "partial tool state survives a cold start")
	check(restored._target().distance_to(game._target()) < 0.01, "saved station remains the active destination")
	restored._command("start")
	check(restored.mode == "dive" and restored.diver.position.distance_to(game.last_pos) < 0.01, "cold start restores dive location")
	root.remove_child(restored)
	restored.free()
	game.camera.make_current()

func _check_interrupted_stroke(game, id: int) -> void:
	var work = game.instrument
	var start: Vector3 = work.spot_point(0) if id == 0 else work.control_point("patch0")
	var finish := start + (Vector3.RIGHT if id == 0 else Vector3.DOWN) * 0.08
	var before: Array = work.snapshot()
	_touch_at(game,start,true)
	_drag_at(game,finish,start)
	var partial: Array = work.snapshot()
	check(partial != before, "a brush stroke removes part of the coating")
	game._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(game.mode == "pause", "backgrounding releases the active tool")
	var restored = _instance(game.save_path)
	check(var_to_str(restored.tools_at_sites[id].snapshot()) == var_to_str(partial), "cold start preserves a stroke interrupted before release")
	root.remove_child(restored)
	restored.free()
	game.camera.make_current()
	_touch_at(game,finish,false)
	game._command("continue")
	_aim(game,work.focus_point())
	await _settle()

func _check_legacy(path: String) -> void:
	var config := ConfigFile.new()
	config.set_value("watch", "done", [false, true])
	config.set_value("watch", "values", [[13, 1], [3, 7]])
	config.set_value("watch", "history", ["Watch 01 · B4"])
	config.set_value("watch", "job", 0)
	config.set_value("watch", "underway", true)
	config.save(path)
	var restored = _instance(path)
	check(restored.underway and restored.done[1] and restored.history.size() == 1, "old watches retain signed work")
	check(restored.tools_at_sites[0].inspection_record().is_empty(), "old meter settings start with an empty inspection sheet")
	root.remove_child(restored)
	restored.free()
	DirAccess.remove_absolute(path)

func _run() -> void:
	var directory := OS.get_environment("TMPDIR")
	if directory.is_empty():
		directory = OS.get_environment("RUNNER_TEMP")
	if directory.is_empty():
		directory = "user://"
	var path := directory.path_join("underwater-test-%d.cfg" % Time.get_ticks_usec())
	_check_legacy(path + ".legacy")
	create_timer(1800.0).timeout.connect(func():
		printerr("FAILED  gameplay test timed out")
		quit(1)
	)
	var game = _instance(path)
	await process_frame
	check(game.mode=="title","main scene starts on the logbook")
	game.hud.page.get_node("start").pressed.emit()
	game.hud.page.get_node("log").pressed.emit()
	check(game.mode=="log","previous watch is readable before a job")
	game._back()
	for id in 2:
		game.hud.page.get_node("job%d"%id).pressed.emit()
		game._command("lamp")
		check(not game.light.visible and not game.spill.visible,"lamp off extinguishes both beams")
		game._command("lamp")
		check(game.light.visible and game.spill.visible,"lamp restores the beam")
		await _swim(game)
		check(game.mode=="tool","swim within working reach of %s"%game.TAGS[id])
		if game.mode!="tool":
			break
		var work = game.instrument
		check(work is Node3D and work.get_parent()==game.jacket,"tools are attached to the rig")
		await _settle()
		await _check_free_movement(game)
		await _check_interrupted_stroke(game, id)
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		root.push_input(enter, true)
		check(game.sample.is_empty(), "pressing Enter cannot finish a fresh docket")
		if id == 0:
			await SurveyRoute.new().exercise(self, game)
		else:
			await ClampRoute.new().exercise(self, game)
		check(not game.sample.is_empty() and game.mode=="dive", "all stations completed before a record can be filed")
		if game.sample.is_empty():
			break
		await _swim(game)
		check(game.mode=="board" and game.done[id],"return to the bell to file the signed record")
		if game.mode!="board":
			break
	check(reload_checked == [true, true], "both routes restored from saved work")
	check(game.history.size()==2,"two signed records filed")
	check(game.reports.size()==2 and game.reports[0].readings.size() >= 4 and game.reports[1].readings.size()==4, "the handover stores the actual survey and fitting results")
	if not failed:
		var reopened = _instance(path)
		check(JSON.stringify(reopened.reports) == JSON.stringify(game.reports), "signed inspection locations and measurements survive a cold start")
		root.remove_child(reopened)
		reopened.free()
		game.camera.make_current()
	if not failed:
		game.hud.page.get_node("next").pressed.emit()
		check(game.watch==2 and not game.done.has(true),"fresh watch resets both stations")
		game.hud.page.get_node("job1").pressed.emit()
		await _swim(game)
		var site_view: Transform3D = game.camera.global_transform
		game._command("pause")
		game._command("recover")
		check(game.returning and game.camera.global_transform.is_equal_approx(site_view), "requesting a return bearing leaves the diver in place")
		await _swim(game)
		check(game.mode=="board" and game.job==1 and not game.done[1],"swimming back with an unfinished docket keeps it open")
	root.remove_child(game)
	game.free()
	await process_frame
	DirAccess.remove_absolute(path)
	if not failed:
		print("Underwater smoke passed: free swim and look, both hands-on jobs, lamp, cold resume, signed inspections and repeat watch.")
	quit(1 if failed else 0)
