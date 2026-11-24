extends RefCounted
## A first watch treading water between the bell and the jacket. The undercurrent
## stays quiet at first, every odd thing resolves, and the lamp always comes back.

var test: SceneTree
var game
var lowest_lamp := INF
var brightest_far := 0.0
var heard: Array[String] = []

func exercise(runner: SceneTree, dive) -> void:
	test = runner
	game = dive
	var work = game.undercurrent
	game._command("start")
	game._command("job0")
	game.diver.position = Vector3(2.0, -1.0, 2.0)
	game.yaw = PI
	game.pitch = 0.0
	game._align_camera()
	await _wait(1.0)
	test.check(game.curtain.modulate.a > 0.2, "the lock-out opens from black water")
	await _wait(5.0)
	test.check(game.curtain.modulate.a < 0.01, "the eyes adjust within a few seconds")
	test.check(heard.size() >= 2 and heard[1].contains("o’clock"), "Ellis gives the first bearing after the lock-out")
	await _wait(24.0)
	test.check(work.fired.is_empty(), "the first half minute in the water is quiet")
	await _until(func(): return "company" in work.fired, 30.0)
	test.check("company" in work.fired and heard.back().contains("toast"), "Ellis keeps the diver company")
	await _until(func(): return "groan" in work.fired, 60.0)
	test.check("groan" in work.fired, "the jacket groans once the diver has settled in")
	var view: Transform3D = game.camera.global_transform
	await _wait(5.0)
	test.check(game.jacket.fish.presence() < 0.5, "the shoal leaves the light after the groan")
	test.check(view.is_equal_approx(game.camera.global_transform), "the jolt never moves the diver's actual view")
	test.check(game.sound.stress() > 0.3, "the diver's breathing quickens")
	await _until(func(): return heard.back().contains("tide"), 10.0)
	test.check(heard.back().contains("tide"), "Ellis explains the groan")
	lowest_lamp = INF
	brightest_far = 0.0
	await _until(func(): return "dropout" in work.fired, 90.0)
	test.check("dropout" in work.fired, "the lamp drops out")
	await _wait(8.0)
	test.check(lowest_lamp < 0.01, "the lamp goes fully dark")
	test.check(brightest_far > 0.5, "a far work light shows in the dark")
	test.check(is_equal_approx(game.light.light_energy, game.lamp_energy), "the lamp comes back at full strength")
	test.check(work.far_light.visible_level() < 0.01, "the far light goes out once the lamp is back")
	test.check(heard.back().contains("Breaker"), "Ellis blames the breaker")
	await _until(func(): return "crosstalk" in work.fired, 90.0)
	test.check(game.callout_faint and game.callout.contains("I have your line"), "crosstalk arrives with no speaker")
	test.check(work.garbled(game.callout) != game.callout, "crosstalk breaks up")
	game._context()
	test.check(game.callout.contains("wasn't me"), "Ellis did not say it")
	test.check(game.jacket.fish.presence() > 0.9, "the fish come back")
	await _until(func(): return "visitor" in work.fired, 80.0)
	test.check(work.sleeper.active, "something large passes at the edge of the light")
	await _until(func(): return not work.sleeper.active, 60.0)
	test.check(not work.sleeper.active, "it leaves and does not return")
	game._context()
	test.check(game.callout.contains("sleeper"), "Ellis names it")
	# Darkness by choice shows the same light, which goes out after the lamp returns.
	game._command("lamp")
	await _wait(7.0)
	test.check(work.far_light.visible_level() > 0.3, "sitting in the dark finds the far light")
	game._command("lamp")
	await _wait(3.0)
	test.check(work.far_light.level < 0.01, "the far light goes out after the diver's lamp comes on")
	game._save_watch()
	var restored = test.call("_instance", game.save_path)
	test.check(restored.undercurrent.fired == work.fired, "the watch remembers what has happened")
	test.root.remove_child(restored)
	restored.free()
	game.camera.make_current()
	print("Hardline heard on the first watch:\n  " + "\n  ".join(heard))
	game._command("pause")
	game._command("title")

func _frame() -> void:
	await test.physics_frame
	lowest_lamp = minf(lowest_lamp, game.light.light_energy)
	brightest_far = maxf(brightest_far, game.undercurrent.far_light.visible_level())
	if game.radio_time > 0.0 and (heard.is_empty() or heard.back() != game.callout):
		heard.append(game.callout)

func _wait(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await _frame()

func _until(done: Callable, seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		if done.call():
			return
		await _frame()
