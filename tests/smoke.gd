extends SceneTree

const Dive = preload("res://game/dive.tscn")
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		printerr("FAILED  ",message)
		failed = true

func _swim(game) -> void:
	game._context() # Request a bearing, then use the same movement state as the thumbstick.
	game.stick = Vector2.UP
	for i in 1000:
		await physics_frame
		if game.diver.position.distance_to(game._target()) < 1.5:
			break
	game.stick = Vector2.ZERO
	await physics_frame
	game._context()

func _settle() -> void:
	for i in 100:
		await physics_frame

func _touch_at(game, point: Vector3, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = game.camera.unproject_position(point)
	event.pressed = pressed
	root.push_input(event,true)

func _tap(game, point: Vector3) -> void:
	_touch_at(game,point,true)
	_touch_at(game,point,false)

func _drag(game, start: Vector3, finish: Vector3) -> void:
	_touch_at(game,start,true)
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = game.camera.unproject_position(finish)
	event.relative = event.position-game.camera.unproject_position(start)
	root.push_input(event,true)
	_touch_at(game,finish,false)

func _instance(path: String):
	var game = Dive.instantiate()
	game.save_path = path
	root.add_child(game)
	return game

func _run() -> void:
	var directory := OS.get_environment("TMPDIR")
	if directory.is_empty():
		directory = OS.get_environment("RUNNER_TEMP")
	if directory.is_empty():
		directory = "user://"
	var path := directory.path_join("underwater-test-%d.cfg" % Time.get_ticks_usec())
	create_timer(150.0).timeout.connect(func():
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
		check(game.mode=="tool","swim to a handhold on %s"%game.TAGS[id])
		if game.mode!="tool":
			break
		var work = game.instrument
		check(work is Node3D and work.get_parent()==game.jacket,"tools are attached to the rig")
		await _settle()
		var submit_part := "stamp" if id==0 else "latch"
		_tap(game,work.control_point(submit_part))
		check(game.sample.is_empty(),"incomplete measurement or misaligned feet can be retried")
		if id==0:
			_drag(game,work.control_point("probe"),work.control_point("pad"))
			check(game.values[id][1]==1,"dragging the probe to bare steel makes contact")
			_tap(game,work.gate_point(5))
			game._command("unbrace")
			game._command("lamp")
			var saved_position: Vector3=game.diver.position
			root.remove_child(game)
			game.free()
			game=_instance(path)
			game._command("start")
			await physics_frame
			check(game.mode=="dive" and game.diver.position.distance_to(saved_position)<0.2,"cold start restores dive location")
			check(not game.lamp_on and not game.light.visible,"lamp state survives a restart")
			game._command("lamp")
			game._context()
			if game.mode!="tool":
				check(false,"return to the grip after restart")
				break
			await _settle()
			work=game.instrument
			check(game.values[id]==[5,1],"instrument gate and probe contact survive restart")
			_drag(game,work.control_point("gate"),work.gate_point(9))
		else:
			_drag(game,work.control_point("left"),work.shoe_point(0,6))
			_drag(game,work.control_point("right"),work.shoe_point(1,3))
			check(game.values[id]==[6,3],"two independent shoe drags align both nuts")
		_tap(game,work.control_point(submit_part))
		check(not game.sample.is_empty() and game.mode=="tool","valid work is recorded while the diver still sees the fixture")
		if game.sample.is_empty():
			break
		game._command("unbrace")
		await _swim(game)
		check(game.mode=="board" and game.done[id],"return to the bell to file the signed record")
		if game.mode!="board":
			break
	check(game.history.size()==2,"two signed records filed")
	if not failed:
		game.hud.page.get_node("next").pressed.emit()
		check(game.watch==2 and not game.done.has(true),"fresh watch resets both stations")
		game.hud.page.get_node("job1").pressed.emit()
		game._command("pause")
		game._command("recover")
		check(game.mode=="board" and game.job==1 and not game.done[1],"line recovery keeps the docket open")
	root.remove_child(game)
	game.free()
	await process_frame
	DirAccess.remove_absolute(path)
	if not failed:
		print("Underwater smoke passed: physical rays and drags on both sites, lamp, cold resume, handover and repeat watch.")
	quit(1 if failed else 0)
