extends Node
## The water around the job. Everything here has an ordinary explanation, and the
## crew gives it. Nothing approaches the diver, nothing is timed against them, and
## the docket still reads like ordinary work. The first minute of every watch is quiet.

const Sleeper = preload("res://world/sleeper.gd")
const FarLight = preload("res://world/far_light.gd")
# The far light hangs on a downline deep in the jacket, in a bay with no docket,
# beyond the reach of the umbilical. It is in clear sight of both worksites.
const FAR_LIGHT := Vector3(21.0, -6.0, -33.0)
const INTERIOR := Vector3(19.0, -8.0, -36.0)
const GAP := 22.0

# Each beat waits for its time on the watch clock and for its conditions.
const BEATS := [
	{"id": "company", "after": 38.0},
	{"id": "groan", "after": 80.0},
	{"id": "dropout", "after": 150.0},
	{"id": "crosstalk", "after": 215.0},
	{"id": "visitor", "after": 265.0},
]

var game: Node
var watch := 1
var clock := 0.0
var fired: Array = []
var said: Array = []
var lamp_gain := 1.0
var disturb := 0.0
var shake := 0.0
var garble := 0.0
var far_light: Node3D
var sleeper: MeshInstance3D
var _since_beat := 0.0
var _next_sound := 0.0
var _later: Array = []
var _dropout := -1.0
var _dark := 0.0
var _far_hold := -1.0
var _far_rest := 0.0
var _crosstalk_window := 0.0
var _sleeper_seen := 0.0
var _visitor_window := 0.0
var _rng := RandomNumberGenerator.new()

func setup(dive: Node, world: Node3D) -> void:
	game = dive
	far_light = FarLight.new()
	far_light.position = FAR_LIGHT
	world.add_child(far_light)
	far_light.rotation.y = PI * 0.08
	sleeper = Sleeper.new()
	world.add_child(sleeper)

func state() -> Dictionary:
	return {"watch": watch, "clock": clock, "fired": fired.duplicate(), "said": said.duplicate()}

func restore(saved: Variant, current_watch: int) -> void:
	begin_watch(current_watch)
	if saved is Dictionary and int(saved.get("watch", -1)) == current_watch:
		clock = maxf(0.0, float(saved.get("clock", 0.0)))
		if saved.get("fired") is Array:
			fired = saved.fired.duplicate()
		if saved.get("said") is Array:
			said = saved.said.duplicate()

func begin_watch(number: int) -> void:
	watch = number
	clock = 0.0
	fired.clear()
	said.clear()
	_rng.seed = 7919 * number + 17
	_next_sound = 55.0

## Leaving the bell. Short-lived effects end; the watch clock carries on.
func lock_out() -> void:
	_later.clear()
	_dropout = -1.0
	_dark = 0.0
	_crosstalk_window = 0.0
	_visitor_window = 0.0
	_since_beat = 0.0
	lamp_gain = 1.0
	disturb = 0.0
	garble = 0.0
	if far_light:
		far_light.set_lit(false, true)

func later(seconds: float, action: Callable) -> void:
	_later.append([seconds, action])

## Ellis answers a call to the bell differently just after something odd.
func context_reply() -> String:
	if _crosstalk_window > 0.0:
		_crosstalk_window = 0.0
		return "Ellis — That wasn't me. Hardline's been quiet a good minute."
	if _visitor_window > 0.0:
		_visitor_window = 0.0
		return "Ellis — A sleeper, maybe. They come up to the lights. It won't bother you."
	if far_light and far_light.visible_level() > 0.08 and _looking_at(FAR_LIGHT, 14.0) and "far_light" not in said:
		said.append("far_light")
		return "Ellis — Nobody's rigged lights in that bay. That'll be your own lamp off a guide plate."
	return ""

func garbled(words: String) -> String:
	if garble <= 0.01 or words.is_empty():
		return words
	var out := ""
	var frame := floori(Time.get_ticks_msec() / 90.0)
	for i in words.length():
		var c := words[i]
		var h := fposmod(sin(float(i) * 12.9898 + float(frame) * 78.233) * 43758.5453, 1.0)
		if c != " " and h < garble * 0.55:
			out += "·" if h < garble * 0.3 else " "
		else:
			out += c
	return out

func tick(delta: float, outside: bool, working: bool) -> void:
	var before := [lamp_gain, disturb, shake, garble]
	disturb = move_toward(disturb, 0.0, delta * 0.9)
	shake = move_toward(shake, 0.0, delta * 1.6)
	garble = move_toward(garble, 0.0, delta * 0.08)
	_crosstalk_window = maxf(0.0, _crosstalk_window - delta)
	_visitor_window = maxf(0.0, _visitor_window - delta)
	for i in range(_later.size() - 1, -1, -1):
		_later[i][0] -= delta
		if _later[i][0] <= 0.0:
			var action: Callable = _later[i][1]
			_later.remove_at(i)
			if action.is_valid():
				action.call()
	if not outside:
		return
	clock += delta
	_since_beat += delta
	_run_dropout(delta)
	_watch_the_dark(delta)
	_watch_the_visitor(delta)
	if _since_beat >= GAP:
		for beat: Dictionary in BEATS:
			if beat.id not in fired and clock >= float(beat.after) * _pace():
				if _try(beat.id, working):
					fired.append(beat.id)
					_since_beat = 0.0
				break
	if "groan" in fired and clock >= _next_sound:
		_ambient()
	if before != [lamp_gain, disturb, shake, garble]:
		game.atmosphere_changed()

# Later watches move a little sooner. The diver knows the sounds by then.
func _pace() -> float:
	return 1.0 if watch <= 1 else 0.75

func _quiet() -> bool:
	return game.radio_time <= 0.0

func _diver() -> Vector3:
	return game.diver.global_position

func _try(id: String, working: bool) -> bool:
	match id:
		"company":
			if not _quiet() or _diver().distance_to(game.BELL) < 4.0:
				return false
			var lines := [
				"Ellis — Your toast's on the heater, butter side in. It'll keep.",
				"Ellis — Mara's awake. She asked which leg you were on.",
				"Ellis — Cook's sent soup down the lock. I'll keep it warm for you.",
			]
			game.say(lines[(watch - 1) % lines.size()], 7.0)
			return true
		"groan":
			_groan()
			return true
		"dropout":
			if not _quiet() or not game.lamp_on or _diver().distance_to(game.BELL) < 5.0:
				return false
			_dropout = 0.0
			game.sound.cue("flicker")
			return true
		"crosstalk":
			if not _quiet():
				return false
			_crosstalk()
			return true
		"visitor":
			return not working and _send_visitor()
	return false

func _groan() -> void:
	var below := _diver() + Vector3(_rng.randf_range(-14, 14), -26.0, _rng.randf_range(-30, -10))
	game.sound.distant("groan", below, _rng.randf_range(0.92, 1.0))
	game.sound.hush(9.0)
	game.sound.startle(0.75)
	game.jacket.fish.startle(_diver() + Vector3.DOWN * 6.0, 55.0)
	later(0.7, _jolt)
	var line := "Ellis — That's the jacket taking the tide. She talks when it turns." if watch <= 1 \
		else "Ellis — Tide's turning. You know her by now."
	later(6.5, func(): game.say(line, 7.0))

# The pressure wave arrives a moment after the sound.
func _jolt() -> void:
	shake = 1.0
	disturb = maxf(disturb, 0.35)

func _crosstalk() -> void:
	game.sound.cue("static")
	garble = 0.62
	disturb = maxf(disturb, 0.5)
	var station: String = game.current_station()
	var lines := [
		"…ver at %s… I have your line… say again, Bell 2…" % station,
		"…toast's on the heater… butter side in… it'll keep…",
		"…Bell 2, we have two divers on the jacket. Confirm… confirm two…",
	]
	game.say(lines[(watch - 1) % lines.size()], 6.0, true)
	_crosstalk_window = 14.0

# The lamp sputters, dies for a few seconds and comes back on the breaker.
func _run_dropout(delta: float) -> void:
	if _dropout < 0.0:
		return
	_dropout += delta
	var t := _dropout
	if t < 0.75:
		lamp_gain = 0.15 if fmod(t, 0.25) < 0.11 else 0.85
		disturb = maxf(disturb, 0.3)
	elif t < 3.9:
		lamp_gain = 0.0
		if far_light.level <= 0.0:
			far_light.set_lit(true, true)
	elif t < 4.5:
		lamp_gain = 0.2 if fmod(t, 0.2) < 0.09 else 1.0
		if t - delta < 3.9:
			game.sound.cue("flicker")
		disturb = maxf(disturb, 0.25)
	else:
		lamp_gain = 1.0
		_dropout = -1.0
		_far_hold = 1.1
		game.sound.startle(0.45)
		var line := "Ellis — Lost your lamp on the panel for a second. Breaker's reset itself." if watch <= 1 \
			else "Ellis — Lamp again. I've put it in the book for the techs."
		later(2.2, func(): game.say(line, 7.0))

# Sitting in the dark lets the eye find what the lamp's backscatter hides.
func _watch_the_dark(delta: float) -> void:
	var lamp: float = lamp_gain if game.lamp_on else 0.0
	far_light.set_veil(lamp)
	_far_rest = maxf(0.0, _far_rest - delta)
	if _far_hold >= 0.0:
		_far_hold -= delta
		if _far_hold < 0.0:
			far_light.set_lit(false, true)
			_far_rest = 70.0
		return
	if not game.lamp_on:
		_dark += delta
		if _dark > 4.0 and _far_rest <= 0.0 and ("groan" in fired or watch > 1):
			far_light.set_lit(true)
		if _dark > 10.0 and "dark" not in said and _quiet():
			said.append("dark")
			game.say("Noor — Your picture's gone black up here. Lamp?", 6.0)
	else:
		if _dark > 0.0 and far_light.level > 0.0:
			# It stays a breath longer than it should, then goes out.
			_far_hold = 1.3
		_dark = 0.0

func _send_visitor() -> bool:
	if not game.lamp_on or game.mode != "dive":
		return false
	var eye: Vector3 = game.camera.global_position
	var ahead: Vector3 = -game.camera.global_basis.z
	ahead.y = 0.0
	if ahead.length() < 0.3:
		return false
	ahead = ahead.normalized()
	var across := ahead.cross(Vector3.UP).normalized()
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var middle := eye + ahead * 7.5 + Vector3.DOWN * 0.9
	var from := middle - across * side * 10.0
	var to := middle + across * side * 10.0 + ahead * 2.5
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for segment in [[eye, middle], [from, middle], [middle, to]]:
		var query := PhysicsRayQueryParameters3D.create(segment[0], segment[1])
		query.exclude = [game.diver.get_rid()]
		if not space.intersect_ray(query).is_empty():
			return false
	sleeper.pass_by(from, to, 0.8)
	game.jacket.fish.startle(from, 40.0)
	_sleeper_seen = 0.0
	return true

func _watch_the_visitor(delta: float) -> void:
	if not sleeper.active:
		return
	if sleeper.in_beam(game.light.global_transform, game.light.spot_angle * 0.6, 15.0) and game.lamp_on and lamp_gain > 0.5:
		_sleeper_seen += delta
		if _sleeper_seen > 0.6:
			game.sound.startle(0.6)
			_visitor_window = 20.0
		if _sleeper_seen > 2.2:
			sleeper.turn_away(_diver())

func _ambient() -> void:
	var roll := _rng.randf()
	var around := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU) * 24.0
	if roll < 0.32:
		game.sound.distant("knock", _diver() + around + Vector3.DOWN * _rng.randf_range(0, 12), _rng.randf_range(0.85, 1.05))
		game.sound.startle(0.2)
	elif roll < 0.55:
		game.sound.cue("tick")
	elif roll < 0.75:
		game.sound.distant("chain", _diver() + around * 0.6 + Vector3.UP * 30.0, _rng.randf_range(0.9, 1.0))
	else:
		# Always from the bay where nobody is working.
		game.sound.distant("double_knock", INTERIOR, _rng.randf_range(0.95, 1.02))
		game.sound.startle(0.35)
	_next_sound = clock + _rng.randf_range(32.0, 85.0)

func _looking_at(point: Vector3, degrees: float) -> bool:
	return (-game.camera.global_basis.z).angle_to(point - game.camera.global_position) < deg_to_rad(degrees)
