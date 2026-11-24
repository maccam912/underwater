extends MeshInstance3D
## A large, slow shark that comes up to the lights at the edge of a diver's lamp.
## It never approaches. Held in the beam, it turns away and sinks out of sight.

const LENGTH := 4.3
var active := false
var elapsed := 0.0
var lit_time := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _velocity := Vector3.ZERO
var _turned := false
var _duration := 30.0

func _ready() -> void:
	name = "Sleeper"
	mesh = _body()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

## Glide from one point to another at the speed of something in no hurry.
func pass_by(from: Vector3, to: Vector3, speed := 0.75) -> void:
	_from = from
	_to = to
	_velocity = from.direction_to(to) * speed
	_duration = from.distance_to(to) / speed
	position = from
	elapsed = 0.0
	lit_time = 0.0
	_turned = false
	active = true
	visible = true
	_face(_velocity, 1.0)

## Seconds spent inside the diver's beam on this pass.
func in_beam(lamp: Transform3D, half_angle: float, reach: float) -> bool:
	if not active:
		return false
	var offset := global_position - lamp.origin
	if offset.length() > reach:
		return false
	return (-lamp.basis.z).angle_to(offset) < deg_to_rad(half_angle)

func turn_away(from: Vector3) -> void:
	if _turned:
		return
	_turned = true
	var away := from.direction_to(global_position)
	away.y = 0.0
	_velocity = (away.normalized() * 1.1 + Vector3.DOWN * 0.55)
	_duration = elapsed + 16.0

func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	position += _velocity * delta
	_face(_velocity, 1.0 - exp(-0.8 * delta))
	if elapsed >= _duration:
		active = false
		visible = false

func _face(direction: Vector3, blend: float) -> void:
	var x := basis.x.normalized().slerp(direction.normalized(), blend).normalized()
	var side := x.cross(Vector3.UP)
	if side.length() < 0.2:
		return
	side = side.normalized()
	basis = Basis(x, side.cross(x), side)

func _body() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Blunt, heavy head and a long body that tapers into a lopsided tail.
	var profiles := [
		Vector3(2.16, 0.09, 0.07), Vector3(2.02, 0.25, 0.20), Vector3(1.70, 0.37, 0.32),
		Vector3(1.05, 0.45, 0.40), Vector3(0.20, 0.44, 0.39), Vector3(-0.55, 0.36, 0.31),
		Vector3(-1.25, 0.22, 0.19), Vector3(-1.72, 0.11, 0.10), Vector3(-1.95, 0.07, 0.07)]
	var back := Color("3a3d37")
	var flank := Color("57564b")
	var belly := Color("858475")
	var sides := 10
	var rings: Array[PackedVector3Array] = []
	for section: Vector3 in profiles:
		var ring := PackedVector3Array()
		for j in sides:
			var phi := TAU * j / sides
			ring.append(Vector3(section.x, section.z * cos(phi), section.y * sin(phi)))
		rings.append(ring)
	for n in range(rings.size() - 1):
		for j in sides:
			var k := (j + 1) % sides
			for point: Vector3 in [rings[n][j], rings[n+1][k], rings[n][k], rings[n][j], rings[n+1][j], rings[n+1][k]]:
				var up := clampf(point.y / 0.4, -1.0, 1.0)
				surface.set_color(flank.lerp(back, smoothstep(0.0, 0.8, up)).lerp(belly, smoothstep(0.0, 1.0, -up)))
				surface.add_vertex(point)
	for j in sides:
		var k := (j + 1) % sides
		_triangle(surface, rings.front()[j], rings.front()[k], Vector3(2.22, -0.02, 0), flank)
		_triangle(surface, rings.back()[k], rings.back()[j], Vector3(-2.0, 0, 0), back)
	# Long upper tail lobe, small lower lobe, two small dorsals set far back.
	_triangle(surface, Vector3(-1.9, 0.06, 0), Vector3(-2.62, 0.46, 0), Vector3(-2.42, 0.02, 0), back)
	_triangle(surface, Vector3(-1.9, -0.06, 0), Vector3(-2.42, 0.02, 0), Vector3(-2.3, -0.30, 0), back)
	for fin: Vector3 in [Vector3(-0.35, 0.18, 0.38), Vector3(-1.05, 0.15, 0.20)]:
		_triangle(surface, Vector3(fin.x + fin.y, fin.z, 0), Vector3(fin.x - 0.08, fin.z + 0.15, 0), Vector3(fin.x - fin.y, fin.z - 0.02, 0), back)
	for side in [-1.0, 1.0]:
		_triangle(surface, Vector3(1.15, -0.24, side * 0.36), Vector3(0.62, -0.30, side * 0.40), Vector3(0.55, -0.42, side * 0.88), flank)
		# Pale, clouded eyes catch a lamp from a long way off.
		var eye := Vector3(1.88, 0.07, side * 0.235)
		_triangle(surface, eye + Vector3(0, 0.035, 0), eye + Vector3(-0.04, 0, side * 0.006), eye - Vector3(0, 0.035, 0), Color("b9bfae"))
		_triangle(surface, eye + Vector3(0, 0.035, 0), eye - Vector3(0, 0.035, 0), eye + Vector3(0.04, 0, side * 0.006), Color("b9bfae"))
	surface.generate_normals()
	var skin := ShaderMaterial.new()
	skin.shader = preload("res://world/sleeper_skin.gdshader")
	surface.set_material(skin)
	return surface.commit()

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
