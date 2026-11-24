extends Node
## The hardline and the tools stay close to the listener. Outside, the bell's
## ventilation gives way to the regulator and the steel's conducted vibration.

const BEDS := {
	"bell": preload("res://audio/generated/bell.mp3"),
	"steel": preload("res://audio/generated/steel.mp3"),
	"breath": preload("res://audio/generated/breath.mp3"),
}
const FOLEY := {
	"comms": preload("res://audio/generated/comms.mp3"),
	"adjust": preload("res://audio/generated/adjust.mp3"),
	"accept": preload("res://audio/generated/accept.mp3"),
	"reject": preload("res://audio/generated/reject.mp3"),
	"hatch": preload("res://audio/generated/hatch.mp3"),
	"tick": preload("res://audio/generated/tick.mp3"),
	"static": preload("res://audio/generated/static.mp3"),
	"flicker": preload("res://audio/generated/flicker.mp3"),
}
# Heard through water from somewhere out in the structure. Direction is vague,
# as it is for a real diver, and everything arrives muffled with a long tail.
const DISTANT := {
	"groan": preload("res://audio/generated/groan.mp3"),
	"knock": preload("res://audio/generated/knock.mp3"),
	"double_knock": preload("res://audio/generated/double_knock.mp3"),
	"chain": preload("res://audio/generated/chain.mp3"),
}
# The regulator loop holds four cut breaths (see tools/generate_sfx.py).
const BREATHS := [4.55, 4.72, 4.48, 4.65]
# Recording-specific gains are measured against the other cues in the mix.
const LEVEL_DB := {
	"bell": 0.0, "steel": 11.0, "breath": -4.0,
	"comms": 1.0, "adjust": 13.0, "accept": -7.0,
	"reject": -5.0, "hatch": -10.0,
	"tick": 2.0, "static": -12.0, "flicker": -17.0,
	"groan": -8.0, "knock": -6.0, "double_knock": 1.0, "chain": -15.0,
}
var _beds: Dictionary[String, AudioStreamPlayer] = {}
var _foley: Dictionary[String, AudioStreamPlayer] = {}
var _distant: Dictionary[String, AudioStreamPlayer3D] = {}
var _outside := false
var _mix := 0.0
var _steel_gain := 0.0
var _steel_goal := 0.0
var _stress := 0.0
var _hush := 0.0
var _hush_time := 0.0


func _ready() -> void:
	for name_id: String in BEDS:
		var stream: AudioStreamMP3 = BEDS[name_id].duplicate()
		stream.loop = true
		var player := _make_player(stream)
		_beds[name_id] = player
		player.volume_db = -80.0
		player.play()
	for name_id: String in FOLEY:
		var player := _make_player(FOLEY[name_id])
		player.volume_db = LEVEL_DB[name_id]
		_foley[name_id] = player
	var far_bus := _far_bus()
	for name_id: String in DISTANT:
		var player := AudioStreamPlayer3D.new()
		player.stream = DISTANT[name_id]
		player.bus = far_bus
		player.volume_db = LEVEL_DB[name_id]
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.panning_strength = 0.5
		player.max_db = 6.0
		add_child(player)
		_distant[name_id] = player
	_update_levels()


func _far_bus() -> StringName:
	var index := AudioServer.get_bus_index("Far")
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, "Far")
		AudioServer.set_bus_send(index, "Master")
		var muffle := AudioEffectLowPassFilter.new()
		muffle.cutoff_hz = 1500.0
		AudioServer.add_bus_effect(index, muffle)
		var hall := AudioEffectReverb.new()
		hall.predelay_msec = 70.0
		hall.room_size = 0.93
		hall.damping = 0.62
		hall.spread = 0.85
		hall.dry = 0.85
		hall.wet = 0.36
		AudioServer.add_bus_effect(index, hall)
	return &"Far"


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player


func _exit_tree() -> void:
	for player in get_children():
		player.stop()
		player.stream = null
	_beds.clear()
	_foley.clear()
	_distant.clear()
	# The mixer releases stopped MP3 playbacks on its own thread. At process
	# shutdown no more scene frames run, so wait for two 512-frame mix blocks.
	var drained := AudioEffectCapture.new()
	var slot := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, drained, slot)
	var deadline := Time.get_ticks_msec() + 300
	while drained.get_frames_available() < 1024 and Time.get_ticks_msec() < deadline:
		OS.delay_msec(2)
	AudioServer.remove_bus_effect(0, slot)


func set_outside(outside: bool) -> void:
	_outside = outside


func cue(id: String) -> void:
	if _foley.has(id):
		_foley[id].play()


func distant(id: String, from: Vector3, pitch := 1.0) -> void:
	if _distant.has(id):
		_distant[id].global_position = from
		_distant[id].pitch_scale = pitch
		_distant[id].play()


## Breathing quickens after a fright and settles over half a minute.
func startle(amount: float) -> void:
	_stress = clampf(maxf(_stress, amount), 0.0, 1.0)


func stress() -> float:
	return _stress


## The jacket's own machinery falls silent for a while after it moves.
func hush(seconds: float) -> void:
	_hush_time = maxf(_hush_time, seconds)


## 0 while drawing air, rising through the exhale. The visor mists on it.
func exhale() -> float:
	if _mix < 0.5 or not _beds.has("breath"):
		return 0.0
	var t: float = _beds["breath"].get_playback_position()
	for period: float in BREATHS:
		if t < period:
			var u := t / period
			if u < 0.36:
				return 0.4 * (1.0 - smoothstep(0.0, 0.3, u))
			if u < 0.79:
				return smoothstep(0.36, 0.79, u)
			return 1.0 - 0.6 * smoothstep(0.79, 1.0, u)
		t -= period
	return 0.0


func set_distance_to_steel(metres: float) -> void:
	# The machinery in a jacket leg falls away as the diver fins out into the dark.
	_steel_goal = lerpf(0.0, -16.0, smoothstep(1.0, 16.0, metres))


func _process(delta: float) -> void:
	var previous := _mix
	var previous_gain := _steel_gain
	var previous_hush := _hush
	_steel_gain = move_toward(_steel_gain, _steel_goal, delta * 12.0)
	_mix = move_toward(_mix, 1.0 if _outside else 0.0, delta * 0.6)
	_hush_time = maxf(0.0, _hush_time - delta)
	_hush = move_toward(_hush, 1.0 if _hush_time > 0.0 else 0.0, delta * (1.5 if _hush_time > 0.0 else 0.12))
	_stress = move_toward(_stress, 0.0, delta / 30.0)
	if _beds.has("breath"):
		_beds["breath"].pitch_scale = 1.0 + 0.12 * _stress
	if _mix != previous or _steel_gain != previous_gain or _hush != previous_hush:
		_update_levels()


func _update_levels() -> void:
	_beds["bell"].volume_db = LEVEL_DB["bell"] + linear_to_db(maxf(0.0001, 1.0 - _mix))
	_beds["steel"].volume_db = LEVEL_DB["steel"] + _steel_gain + linear_to_db(maxf(0.0001, _mix * (1.0 - 0.9 * _hush)))
	_beds["breath"].volume_db = LEVEL_DB["breath"] + linear_to_db(maxf(0.0001, _mix))
