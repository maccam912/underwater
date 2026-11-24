extends Node3D
## A cold work light on the far conductor guides, in a bay with no docket.
## Lamp backscatter veils a faint light this far off, so a diver mostly sees it
## with their own lamp dark. It goes out a moment after the diver's lamp returns.

const COLD := Color("b7d7c9")
var level := 0.0
var _goal := 0.0
var _glow: ShaderMaterial
var _veil := 1.0

func _ready() -> void:
	name = "FarWorkLight"
	var housing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.62, 0.27, 0.32)
	housing.mesh = box
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("3c4441")
	iron.roughness = 0.9
	housing.material_override = iron
	add_child(housing)
	# Lowered from somewhere above on a single wire, the way a lamp is hung to light a job.
	var wire := MeshInstance3D.new()
	var strand := CylinderMesh.new()
	strand.top_radius = 0.02
	strand.bottom_radius = 0.02
	strand.height = 60.0
	strand.radial_segments = 6
	wire.mesh = strand
	wire.position = Vector3(0, 30.1, 0)
	wire.material_override = iron
	add_child(wire)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 3.2
	var flare := MeshInstance3D.new()
	flare.mesh = quad
	# The bulb hangs just under its hood, so the housing never hides it.
	flare.position = Vector3(0, -0.3, 0)
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow = ShaderMaterial.new()
	_glow.shader = preload("res://world/far_glow.gdshader")
	_glow.set_shader_parameter("tint", COLD)
	flare.material_override = _glow
	add_child(flare)
	_apply()

## 1 lights it, 0 puts it out. `snap` skips the warm-up, as a breaker would.
func set_lit(lit: bool, snap := false) -> void:
	_goal = 1.0 if lit else 0.0
	if snap:
		level = _goal
		_apply()

## How much of the diver's own lamp is lighting the water between them.
func set_veil(amount: float) -> void:
	_veil = clampf(amount, 0.0, 1.0)

func visible_level() -> float:
	return level * (1.0 - 0.84 * _veil)

func _process(delta: float) -> void:
	var before := level
	level = move_toward(level, _goal, delta * 0.45)
	if before != level or _glow.get_shader_parameter("level") != visible_level():
		_apply()

func _apply() -> void:
	_glow.set_shader_parameter("level", visible_level())
	visible = level > 0.001
