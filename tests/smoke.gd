extends SceneTree

const Dive = preload("res://game/dive.tscn")
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		printerr("FAILED  ",message)
		failed = true

func _swim_straight(game, frames: int) -> void:
	game.stick = Vector2.UP
	for i in frames:
		await physics_frame
		if game.diver.position.distance_to(game._target()) < 2.5:
			break
	game.stick = Vector2.ZERO
	await physics_frame

func _run() -> void:
	# Drive the same physics/input state as the touch stick with a fixed simulation rate.
	var game = Dive.instantiate()
	var temporary_dir := OS.get_environment("TMPDIR")
	if temporary_dir.is_empty():
		temporary_dir = OS.get_environment("RUNNER_TEMP")
	if temporary_dir.is_empty():
		temporary_dir = "user://"
	var test_file := temporary_dir.path_join("underwater-smoke-%d.cfg" % Time.get_ticks_usec())
	create_timer(120.0).timeout.connect(func():
		printerr("FAILED  gameplay test timed out")
		quit(1)
	)
	game.save_path = test_file
	root.add_child(game)
	await process_frame
	check(game.mode=="title","main scene starts on title")
	game.hud.page.get_node("start").pressed.emit()
	check(game.mode=="board","title opens the bell sheet")
	game.hud.page.get_node("log").pressed.emit()
	check(game.mode=="log","prior shift note accessible without a job")
	game._back()
	for id in 2:
		game.hud.page.get_node("job%d"%id).pressed.emit()
		check(game.mode=="dive" and game.job==id,"selected job locks out")
		game._context()  # Ask for a bearing before finning.
		await _swim_straight(game,900)
		game._context()
		check(game.mode=="tool","diver can swim from the bell to %s"%game.TAGS[id])
		if game.mode!="tool":
			break
		var tool = game.instrument
		tool._submit()
		check(game.mode=="tool" and game.sample.is_empty(),"bad reading remains retryable")
		tool._adjust(0,1)
		var kept: Array = game.values[id].duplicate()
		tool.exited.emit()
		check(game.mode=="dive","unbrace leaves tool")
		game._context()
		tool = game.instrument
		check(tool._settings[0]==kept[0],"partial instrument settings survive unbracing")
		if id==0:
			# A mobile OS can terminate the app while the diver is working.
			var saved_position: Vector3 = game.diver.position
			root.remove_child(game)
			game.free()
			game = Dive.instantiate()
			game.save_path = test_file
			root.add_child(game)
			game._command("start")
			check(game.mode=="dive" and game.diver.position.is_equal_approx(saved_position),"cold start restores the underwater position")
			game._context()
			tool = game.instrument
			if not is_instance_valid(tool):
				check(false,"reloaded diver can reach the instrument")
				break
			check(tool._settings[0]==kept[0],"cold start restores meter setting")
		tool._set_value(0,tool._target())
		if id==1:
			tool._set_value(1,tool._target(1))
		tool._submit()
		check(game.mode=="dive" and not game.sample.is_empty() and not game.done[id],"accepted work awaits handover")
		if game.mode!="dive":
			break
		game._context()  # Ask for a bearing before finning.
		await _swim_straight(game,900)
		game._context()
		check(game.mode=="board" and game.done[id],"swim back and file signed sheet")
		if game.mode!="board":
			break
	check(game.history.size()==2,"both distinct signed records are filed")
	if not failed:
		game.hud.page.get_node("next").pressed.emit()
		check(game.watch==2 and not game.done.has(true) and game.history.size()==2,"new watch retains handover history and renews dockets")
		game.hud.page.get_node("job1").pressed.emit()
		game._command("pause")
		game._command("recover")
		check(game.mode=="board" and not game.done[1],"line recovery keeps unfinished work open")
		game.hud.page.get_node("job1").pressed.emit()
		game._command("pause")
		game._command("title")
		game._command("start")
		check(game.mode=="dive" and game.underway,"return to title resumes the working dive")
	root.remove_child(game)
	game.free()
	await process_frame
	DirAccess.remove_absolute(test_file)
	if not failed:
		print("Underwater smoke passed: two physical routes, both instruments, handovers, repeat watch, pause and recovery.")
	quit(1 if failed else 0)
