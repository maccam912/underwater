extends SceneTree
## Playtest capture: drives the real scene in a window and saves frames of the
## title, lock-out and each undercurrent beat. Needs a display, not --headless.
##   SHOTS=/some/folder godot --path . --fixed-fps 60 --script res://tests/capture.gd
const Dive = preload("res://game/dive.tscn")
var out := OS.get_environment("SHOTS") if not OS.get_environment("SHOTS").is_empty() else OS.get_user_data_dir()
var game

func _initialize() -> void:
	call_deferred("_run")

func _snap(name: String, frames := 20) -> void:
	for i in frames:
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)

func _face(target: Vector3) -> void:
	var offset := (target - Vector3(game.diver.position)).normalized()
	game.yaw = atan2(-offset.x, -offset.z)
	game.pitch = asin(clampf(offset.y,-1,1))
	game._align_camera()

func _beat(id: String, clock: float) -> void:
	var u = game.undercurrent
	u.clock = clock
	u._since_beat = 99.0
	game.radio_time = 0.0
	while id not in u.fired:
		game.radio_time = 0.0
		await physics_frame

func _run() -> void:
	print("Saving playtest frames to ", out)
	game = Dive.instantiate()
	game.save_path = ""
	root.add_child(game)
	await _snap("20-title-drift", 200)
	game._command("job0")
	game.diver.position = Vector3(2.0, -1.0, 2.0)
	_face(Vector3(-4, 0, -6))
	await _snap("21-lockout-black", 15)
	await _snap("22-lockout-fading", 50)
	var u = game.undercurrent
	u.fired = ["company"]
	await _beat("groan", 80.0)
	await _snap("23-groan-jolt", 160)
	_face(u.FAR_LIGHT)
	await _beat("dropout", 150.0)
	await _snap("24-dropout-dark", 110)
	await _snap("25-lamp-back", 140)
	await _beat("crosstalk", 215.0)
	await _snap("26-crosstalk", 40)
	game.yaw = PI
	game.pitch = 0.0
	game._align_camera()
	game.radio_time = 0.0
	await _beat("visitor", 265.0)
	await _snap("27-visitor-a", 90)
	await _snap("28-visitor-b", 90)
	await _snap("29-visitor-c", 90)
	await _snap("29-visitor-d", 120)
	game.diver.position = Vector3(-2.0, -1.0, -3.0)
	_face(u.FAR_LIGHT)
	u._far_rest = 0.0
	game._command("lamp")
	await _snap("30-dark-far-light", 420)
	game.diver.position = Vector3(-3.2, 0.0, -2.6)
	game.yaw = 0.0
	game._align_camera()
	await _snap("31-dark-at-A2", 30)
	game._command("lamp")
	await _snap("32-lamp-on-veil", 20)
	quit()
