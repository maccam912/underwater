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
}
# Recording-specific gains are measured against the other cues in the mix.
const LEVEL_DB := {
	"bell": 0.0, "steel": 11.0, "breath": -4.0,
	"comms": 1.0, "adjust": 13.0, "accept": -7.0,
	"reject": -5.0, "hatch": -10.0,
}
var _beds: Dictionary[String, AudioStreamPlayer] = {}
var _foley: Dictionary[String, AudioStreamPlayer] = {}
var _outside := false
var _mix := 0.0


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
	_update_levels()


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player


func _exit_tree() -> void:
	for player: AudioStreamPlayer in get_children():
		player.stop()
		player.stream = null
	_beds.clear()
	_foley.clear()
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


func _process(delta: float) -> void:
	var previous := _mix
	_mix = move_toward(_mix, 1.0 if _outside else 0.0, delta * 0.6)
	if _mix != previous:
		_update_levels()


func _update_levels() -> void:
	_beds["bell"].volume_db = LEVEL_DB["bell"] + linear_to_db(maxf(0.0001, 1.0 - _mix))
	_beds["steel"].volume_db = LEVEL_DB["steel"] + linear_to_db(maxf(0.0001, _mix))
	_beds["breath"].volume_db = LEVEL_DB["breath"] + linear_to_db(maxf(0.0001, _mix))
