extends Node3D

const BELL := Vector3(0, 0, 8)
const A2 := Vector3(-4, 0, -4)
const B4 := Vector3(7, -2, -8)

const FRONT_LEFT := Vector3(-8.8, 0, -6.9)
const FRONT_RIGHT := Vector3(11.1, 0, -11.1)
const BACK_LEFT := Vector3(-12.6, 0, -25.4)
const BACK_RIGHT := Vector3(8, 0, -30.5)
const UP := Vector3.UP
const FRONT := Vector3.BACK
const CABLE_ORIGIN := Vector3(-2.62, -1.02, 7.5)
const HOSE_SEGMENTS := 18

var _materials: Dictionary = {}
var _shapes: Dictionary = {}
var _groups: Dictionary = {}
var _station_leds: Array[MeshInstance3D] = []
var _hose: MultiMesh
var _collision := StaticBody3D.new()
var _last_diver := Vector3(999, 999, 999)

func _ready() -> void:
	_collision.name = "SolidSteel"
	add_child(_collision)
	_materials_setup()
	_environment()
	_jacket()
	_risers()
	_service_gear()
	_station_a()
	_station_b()
	_bell()
	_emit_batches()
	_hose_setup()
	_suspended_particles()
	update_diver(BELL)

func _material(key: String, color: String, metal := 0.0, glow := 0.0, texture_path := "") -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.86
	material.metallic = metal
	if texture_path != "" and ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE * 0.50
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = Color(color)
		material.emission_energy_multiplier = glow
	_materials[key] = material

func _materials_setup() -> void:
	var steel := "res://art/jacket.webp"
	var enamel := "res://art/enamel.webp"
	_material("jacket", "b3b2a4", 0.11, 0.0, steel)
	_material("shadowsteel", "777f74", 0.09, 0.0, steel)
	_material("pipe", "a89a88", 0.12, 0.0, steel)
	_material("galvanized", "879a96", 0.18)
	_material("edge", "485953", 0.13)
	_material("iron", "364442", 0.15)
	_material("rubber", "222d2b")
	_material("brass", "bb8554", 0.14)
	_material("chalk", "d1c8aa", 0.06)
	_material("yellow", "efbb6c", 0.05, 0.0, enamel)
	_material("hull", "efad55", 0.09, 0.0, enamel)
	_material("maroon", "94634d", 0.08)
	_material("navy", "2b494b", 0.10)
	_material("glass", "90bcb5", 0.19, 0.13)
	_material("amber_glass", "ffbe67", 0.07, 0.9)
	_material("amber_bulb", "ffdb97", 0.0, 2.2)
	_material("cold_bulb", "b5dfcf", 0.0, 1.5)
	_material("filed_bulb", "a8f3b5", 0.0, 1.6)
	_material("rope", "b09862")
	_material("growth", "798172")
	_material("cast", "d8ccc6", 0.16, 0.0, steel)

func _environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var water := Sky.new()
	var backdrop := ShaderMaterial.new()
	backdrop.shader = preload("res://world/water.gdshader")
	water.sky_material = backdrop
	env.sky = water
	env.background_color = Color("132d30")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("acc3b6")
	env.ambient_light_energy = 0.57
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 1.0
	env.fog_depth_end = 44.0
	env.fog_depth_curve = 1.05
	env.fog_light_color = Color("173436")
	env.fog_light_energy = 0.94
	env.fog_sky_affect = 0.79
	world_env.environment = env
	add_child(world_env)
	var key := DirectionalLight3D.new()
	key.light_color = Color("acc7b5")
	key.light_energy = 1.06
	key.rotation_degrees = Vector3(-38, -33, 12)
	add_child(key)

func _shape(kind: String) -> PrimitiveMesh:
	if _shapes.has(kind):
		return _shapes[kind]
	var result: PrimitiveMesh
	if kind == "box":
		result = BoxMesh.new()
	elif kind == "dome":
		var dome := SphereMesh.new()
		dome.radial_segments = 16
		dome.rings = 7
		result = dome
	else:
		var tube := CylinderMesh.new()
		tube.top_radius = 1.0
		tube.bottom_radius = 1.0
		tube.height = 1.0
		tube.radial_segments = int(kind)
		tube.rings = 0
		result = tube
	_shapes[kind] = result
	return result

func _place(kind: String, material: String, pose: Transform3D) -> void:
	var key := kind + "|" + material
	if not _groups.has(key):
		_groups[key] = []
	_groups[key].append(pose)

func _box(center: Vector3, size: Vector3, mat: String, solid := false) -> void:
	_place("box", mat, Transform3D(Basis.from_scale(size), center))
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		_solid(shape, Basis.IDENTITY, center)

func _solid(geom: Shape3D, attitude: Basis, center: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = geom
	collider.transform = Transform3D(attitude, center)
	_collision.add_child(collider)

func _axis_basis(axis: Vector3) -> Basis:
	var unit_y := axis.normalized()
	var guide := Vector3.RIGHT if absf(unit_y.x) < 0.9 else Vector3.BACK
	var unit_z := guide.cross(unit_y).normalized()
	return Basis(unit_y.cross(unit_z), unit_y, unit_z)

func _tube(a: Vector3, b: Vector3, radius: float, mat: String, sides := 10, solid := false) -> void:
	var axis := b - a
	var frame := _axis_basis(axis)
	var center := (a + b) * 0.5
	_place(str(sides), mat, Transform3D(frame.scaled_local(Vector3(radius, axis.length(), radius)), center))
	if solid:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = axis.length()
		_solid(shape, frame, center)

func _band(p: Vector3, axis: Vector3, length: float, radius: float, mat: String, sides := 12) -> void:
	var half := axis.normalized() * length * 0.5
	_tube(p - half, p + half, radius, mat, sides)

func _dome(center: Vector3, size: Vector3, mat: String) -> void:
	_place("dome", mat, Transform3D(Basis.from_scale(size), center))

func _emit_batches() -> void:
	for key: String in _groups:
		var parts := key.split("|")
		var poses: Array = _groups[key]
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = _shape(parts[0])
		batch.instance_count = poses.size()
		for i in poses.size():
			batch.set_instance_transform(i, poses[i])
		var draw := MultiMeshInstance3D.new()
		draw.name = "%s_%s" % [parts[1], parts[0]]
		draw.multimesh = batch
		draw.material_override = _materials[parts[1]]
		draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(draw)
	_groups.clear()

func _jacket() -> void:
	var feet := [FRONT_LEFT, FRONT_RIGHT, BACK_RIGHT, BACK_LEFT]
	# Front legs open slightly toward the seabed. Ring welds divide the cans.
	for i in feet.size():
		var foot: Vector3 = feet[i]
		var slope := Vector3(0.027 if i == 0 or i == 3 else -0.027, 1.0, -0.015 if i < 2 else 0.015)
		_tube(foot - 65.0 * slope, foot + 65.0 * slope, 1.08, "jacket", 16, true)
		for j in range(-6, 7):
			var site := foot + slope * (j * 7.2 + 2.7)
			_band(site, slope, 0.15, 1.108, "edge", 16)
			_band(site + slope * 0.10, slope, 0.048, 1.115, "pipe", 16)
		for level in [-17.0, -6.8, 6.7, 20.2]:
			_band(foot + slope * level, slope, 0.91, 1.18, "shadowsteel", 16)
	for level in range(-3, 4):
		var bottom := -6.8 + 13.5 * level
		for j in 4:
			var p: Vector3 = feet[j]
			var q: Vector3 = feet[(j + 1) % 4]
			var a := p + UP * bottom
			var b := q + UP * bottom
			_tube(a, b, 0.56 if j == 0 else 0.50, "jacket", 12, true)
			var c := p.lerp(q, 0.5) + UP * (bottom + 13.5)
			# Paired K braces leave generous open bays at the working level.
			var material := "jacket" if j == 0 else "shadowsteel"
			_tube(a + UP * 0.18, c, 0.48, material, 12, true)
			_tube(b + UP * 0.18, c, 0.48, material, 12, true)
			if j == 0:
				for member in [a, b]:
					var v: Vector3 = c - member
					for u in [0.20, 0.66]:
						_band(member.lerp(c, u), v, 0.085, 0.505, "edge")
	# An internal tower and hanging tool lines give the near face some parallax.
	for x in [-5.2, -2.3, 1.5, 4.0]:
		var z: float = -21.0 - x * 0.08
		_tube(Vector3(x, -54, z), Vector3(x, 54, z), 0.18 if x > 0 else 0.30, "pipe")
		for i in range(-3, 4):
			_band(Vector3(x, i * 8.0, z), UP, 0.18, 0.36, "edge")
	for offset in [-0.36, 0.36]:
		_tube(Vector3(-8.0 + offset, -27, -5.75), Vector3(-8.0 + offset, 25, -5.75), 0.045, "iron", 8)
	for i in range(-52, 50):
		var y := i * 0.50
		_tube(Vector3(-8.38, y, -5.74), Vector3(-7.62, y, -5.74), 0.040, "galvanized", 8)
	for i in range(-6, 7):
		_box(Vector3(-8.0, i * 4.0, -5.94), Vector3(1.08, 0.13, 0.40), "edge")
	# Tie-off lines run between stations; the red and cream lashing indicates the bell side.
	var ends := [Vector3(-8.15, -3.8, -5.72), Vector3(-4, -2.7, -5.7), Vector3(1,-3.48,-7.1), Vector3(7,-4.4,-9.7),Vector3(10.5,-4.7,-10.2)]
	for i in ends.size() - 1:
		var a: Vector3 = ends[i]
		var b: Vector3 = ends[i + 1]
		var low := a.lerp(b, 0.50) + Vector3.DOWN * 0.19
		_tube(a, low, 0.040, "rope", 8)
		_tube(low, b, 0.040, "rope", 8)
		for k in 3:
			_band(a.lerp(low, 0.42 + k * 0.055), low-a, 0.060, 0.052, "maroon" if k % 2 == 0 else "chalk", 8)

func _risers() -> void:
	for spec in [[-4.0,-6.70,0.69],[-5.65,-7.24,0.38],[6.95,-10.62,0.71],[8.55,-11.10,0.31]]:
		var x: float = spec[0]
		var z: float = spec[1]
		var r: float = spec[2]
		_tube(Vector3(x,-48,z),Vector3(x,46,z), r, "pipe", 16, true)
		for j in range(-5, 6):
			var y := 8.6 * j + (2.9 if x < 0 else 1.35)
			_band(Vector3(x,y,z), UP, 0.22, r + 0.10, "edge", 16)
			_band(Vector3(x,y+0.14,z), UP, 0.065, r + 0.14, "galvanized", 16)
	# Two clipped hydraulic lines on the sheltered side of the right riser.
	for offset in [0.0,0.18]:
		_tube(Vector3(5.79+offset,-21,-10.29),Vector3(5.79+offset,21,-10.29),0.063,"iron",8)
	for j in range(-8,9):
		_box(Vector3(5.96,j*2.4,-10.28),Vector3(0.68,0.13,0.15),"edge")

func _service_gear() -> void:
	# The equipment basket is flown separately from the bell and floats clear of the structure.
	var center := Vector3(5.35, -4.45, -1.9)
	var corners := [Vector3(-0.83,0,-0.51),Vector3(0.83,0,-0.51),Vector3(0.83,0,0.51),Vector3(-0.83,0,0.51)]
	for i in 4:
		var a: Vector3 = center+corners[i]
		var b: Vector3 = center+corners[(i+1)%4]
		_tube(a,a+UP*0.84,0.057,"yellow",8)
		_tube(a,b,0.071,"iron",8)
		_tube(a+UP*0.79,b+UP*0.79,0.060,"yellow",8)
		var count := int(ceil(a.distance_to(b)*5.0))
		for j in range(1,count):
			var post := a.lerp(b,float(j)/count)
			_tube(post,post+UP*0.75,0.022,"edge",6)
		_tube(a+UP*0.81,center+UP*2.2,0.021,"iron",6)
	_tube(center+UP*2.2,center+Vector3(0.33,48,-0.34),0.023,"rope",8)
	_box(center,Vector3(1.68,0.14,1.03),"edge",true)
	_box(center+Vector3(-0.19,0.22,0),Vector3(0.80,0.33,0.46),"maroon")
	_box(center+Vector3(-0.19,0.39,0),Vector3(0.87,0.08,0.50),"iron")
	# Sacrificial anodes sit proud of the front braces on short brackets.
	for i in range(4):
		var base := Vector3(-7.08+i*4.53,-6.81,-6.56-i*1.01)
		for x in [-0.44,0.44]:
			_box(base+Vector3(x,0,0.22),Vector3(0.10,0.14,0.35),"edge")
		_box(base+FRONT*0.44,Vector3(1.25,0.16,0.19),"growth")
	# A low cable tray takes bundled services round the near leg and away to the rear.
	var near := Vector3(-8.32,-3.15,-5.65)
	var far := Vector3(-12.10,-3.55,-24.65)
	for i in 3:
		var lift := UP * (i*0.17)
		_tube(near+lift,far+lift,0.052,"iron",8)
	for i in range(8):
		var hanger := near.lerp(far,i/8.0)
		_box(hanger+Vector3(-0.12,0.12,0),Vector3(0.46,0.55,0.09),"edge")

func _plate(center: Vector3, text: String, width: float, height: float) -> void:
	_box(center, Vector3(width,height,0.075), "iron")
	_box(center + FRONT * 0.045, Vector3(width-0.045,height-0.045,0.025), "yellow")
	_label(center + FRONT * 0.065, text, height * 0.76, Color("292f29"))
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var at := center + Vector3(x*(width/2.0-0.065), y*(height/2.0-0.065), 0.062)
			_band(at, FRONT, 0.027, 0.026, "iron", 6)

func _label(at: Vector3, text: String, height: float, tint: Color, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
	label.double_sided = false
	label.font_size = 64
	label.outline_size = 0
	label.pixel_size = height / 64.0
	label.modulate = tint
	label.position = at
	label.rotation.y = yaw
	label.shaded = true
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)

func _studs(center: Vector3, radius: float, count: int, stud: float, mat: String) -> void:
	for i in count:
		var angle := TAU * float(i) / count
		var p := center + Vector3(cos(angle),sin(angle),0.0) * radius
		_band(p, FRONT, stud, stud, mat, 6)

func _rail(a: Vector3, b: Vector3, z: float, radius := 0.04) -> void:
	var aa := a + FRONT * z
	var bb := b + FRONT * z
	_tube(a, aa, radius, "galvanized", 8)
	_tube(aa, bb, radius, "galvanized", 8)
	_tube(bb, b, radius, "galvanized", 8)

func _station_a() -> void:
	var hub := Vector3(-4,0,-5.99)
	# The wall probe lands on an exposed inspection pad in a ring of original coating.
	_band(hub, FRONT, 0.31, 0.64, "edge", 16)
	_band(hub + FRONT*0.18, FRONT, 0.10, 0.55, "cast", 16)
	_band(hub + FRONT*0.25, FRONT, 0.07, 0.43, "maroon", 16)
	_band(hub + FRONT*0.30, FRONT, 0.045, 0.315, "iron", 16)
	_band(hub + FRONT*0.33, FRONT, 0.034, 0.25, "edge", 16)
	_band(hub + FRONT*0.355, FRONT, 0.014, 0.21, "cast", 16)
	_label(hub + FRONT * 0.369, "+", 0.14, Color("a5a48a"))
	_studs(hub + FRONT*0.246, 0.493, 10, 0.047, "brass")
	_band(hub + UP*1.09 - FRONT*0.59, UP, 0.23, 0.73, "edge", 16)
	_plate(hub + Vector3(0,1.15,0.12), "A2", 1.16, 0.54)
	_rail(hub + Vector3(-0.66,-0.53,-0.09), hub + Vector3(-0.66,0.55,-0.09), 0.32)
	_rail(hub + Vector3(0.66,-0.53,-0.09), hub + Vector3(0.66,0.55,-0.09), 0.32)
	_work_light(hub + Vector3(-0.88,1.68,0.20), false)
	_led(hub + Vector3(0.76,0.53,0.11))
	# Two narrow clean scars left by a previous carrier. Exposed metal has no growth.
	for sx in [-0.28,0.28]:
		var mount := hub + Vector3(sx,-0.99,-0.065)
		_box(mount,Vector3(0.105,0.24,0.034),"galvanized")
		_box(mount+Vector3(-0.030,0.012,0.021),Vector3(0.022,0.19,0.012),"chalk")
	# Pencil ticks next to the sample pad.
	for i in 5:
		_box(hub + Vector3(-0.18 + i * 0.09,-0.76,0.02), Vector3(0.04,0.09 if i % 2 == 0 else 0.06,0.035),"chalk")

func _station_b() -> void:
	var hub := Vector3(7,-2,-9.95)
	for dy in [-0.40,0.40]:
		_band(hub + Vector3(0,dy,-0.66), UP, 0.22, 0.82, "edge", 16)
		_box(hub + Vector3(0,dy,0.10), Vector3(1.80,0.20,0.35),"yellow", true)
		for side in [-1.0,1.0]:
			var foot := hub + Vector3(side*0.71,dy,0.30)
			_band(foot, FRONT, 0.14, 0.102,"galvanized",6)
	_box(hub + Vector3(0,0,-0.025), Vector3(1.03,0.92,0.15), "navy")
	_box(hub + Vector3(0,0,0.26), Vector3(1.19,0.25,0.17), "brass")
	for side in [-1.0,1.0]:
		_box(hub + Vector3(side*0.48,0,0.37), Vector3(0.08,0.27,0.025), "chalk")
		_box(hub + Vector3(side*0.65,0.06,0.19), Vector3(0.13,1.23,0.12), "iron")
	_rail(hub + Vector3(-0.98,-0.40,0.01), hub + Vector3(-0.98,0.40,0.01), 0.29)
	_box(hub + Vector3(0,1.06,0.20),Vector3(0.42,0.18,0.72),"edge")
	_plate(hub + Vector3(0,1.08,0.58), "B4", 1.16, 0.54)
	_work_light(hub + Vector3(0.98,1.56,0.13), true)
	_led(hub + Vector3(0.94,0.60,0.14))

func _led(at: Vector3) -> void:
	_box(at, Vector3(0.21,0.31,0.15), "rubber")
	var lens := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.13,0.20,0.04)
	lens.mesh = mesh
	lens.position = at + FRONT * 0.086
	lens.material_override = _materials["amber_glass"]
	add_child(lens)
	_station_leds.append(lens)

func set_station_filed(index: int, filed: bool) -> void:
	if index >= 0 and index < _station_leds.size():
		_station_leds[index].material_override = _materials["filed_bulb" if filed else "amber_glass"]

func _work_light(at: Vector3, warm: bool) -> void:
	var bulb := "amber_bulb" if warm else "cold_bulb"
	_box(at-Vector3(0,0.02,0.27),Vector3(0.13,0.26,0.65),"edge")
	_box(at,Vector3(0.66,0.29,0.34),"iron")
	_box(at+Vector3(0,-0.02,0.185),Vector3(0.50,0.15,0.035),bulb)
	_box(at+Vector3(0,0.17,0.09),Vector3(0.72,0.045,0.55),"edge")
	for x in [-0.15,0.0,0.15]:
		_box(at+Vector3(x,-0.02,0.214),Vector3(0.018,0.22,0.02),"iron")
	var light := OmniLight3D.new()
	light.position = at + Vector3(0,0,0.65)
	light.light_color = Color("ffcb8d") if warm else Color("cee7ce")
	light.light_energy = 2.2
	light.omni_range = 4.9
	light.omni_attenuation = 1.2
	add_child(light)
	_scatter(at + FRONT*0.24, 2.15, warm)

func _scatter(at: Vector3, radius: float, warm: bool) -> void:
	var skin := ShaderMaterial.new()
	skin.shader = preload("res://world/light_scatter.gdshader")
	skin.set_shader_parameter("tint",Color("ffc783") if warm else Color("b8e4c9"))
	var veil := QuadMesh.new()
	veil.size = Vector2.ONE * radius
	var halo := MeshInstance3D.new()
	halo.mesh = veil
	halo.material_override = skin
	halo.position = at
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

func _bell() -> void:
	var center := Vector3(-4.10,0.40,7.4)
	_band(center,UP,2.5,1.42,"hull",20)
	_dome(center+UP*1.20,Vector3(2.83,1.31,2.83),"hull")
	_dome(center-UP*1.20,Vector3(2.83,1.38,2.83),"hull")
	for y in [-1.15,0.94]:
		_band(center+UP*y,UP,0.12,1.46,"edge",20)
	_band(center-UP*1.60,UP,0.35,0.96,"rubber",16)
	_band(center-UP*1.82,UP,0.15,1.02,"yellow",16)
	_band(center+UP*1.83,UP,0.24,0.67,"edge",16)
	_band(center+UP*1.98,UP,0.14,0.42,"brass",12)
	_tube(center+UP*2.01,center+Vector3(0.16,50,-0.45),0.094,"iron",8)
	_tube(center+Vector3(-0.36,1.34,0.45),center+Vector3(-1.15,53,0.18),0.078,"rope",8)
	# Guards around the viewport and a roll cage around the pressure hull.
	for yaw in [-PI*0.77, -0.97, PI*0.57, 0.12]:
		var face := Vector3(sin(yaw),0,cos(yaw))
		var port := center + face*1.38 + UP*0.12
		_band(port,face,0.20,0.42,"iron",16)
		_band(port+face*0.12,face,0.06,0.325,"brass",16)
		_band(port+face*0.16,face,0.035,0.263,"amber_glass",16)
		var lateral := UP.cross(face)
		for k in 10:
			var angle := TAU * k / 10.0
			var bolt := port + face*0.113 + (lateral*cos(angle) + UP*sin(angle))*0.365
			_band(bolt,face,0.030,0.036,"galvanized",6)
		for k in [-1.0,0.0,1.0]:
			_tube(port+face*0.20+lateral*k*0.10-UP*0.235,port+face*0.20+lateral*k*0.10+UP*0.235,0.017,"iron",8)
	var corners := [Vector3(-1.52,0,-1.37),Vector3(1.52,0,-1.37),Vector3(1.52,0,1.37),Vector3(-1.52,0,1.37)]
	for i in 4:
		var a: Vector3 = center+corners[i]
		var b: Vector3 = center+corners[(i+1)%4]
		_tube(a-UP*2.19,a+UP*1.73,0.087,"edge",8,true)
		for level in [-2.20,1.65]:
			_tube(a+UP*level,b+UP*level,0.091,"edge",8)
		_tube(a+UP*1.60,center+UP*2.08,0.064,"iron",8)
		for level in [-1.88,-1.68,1.21]:
			_band(a+UP*level,UP,0.13,0.091,"yellow",8)
	var hull_shape := CylinderShape3D.new()
	hull_shape.radius = 1.43
	hull_shape.height = 3.25
	_solid(hull_shape,Basis.IDENTITY,center)
	for side in [-1.0,1.0]:
		_box(center+Vector3(side*0.79,0.90,-1.18),Vector3(0.38,0.25,0.18),"iron")
		_box(center+Vector3(side*0.79,0.90,-1.30),Vector3(0.26,0.16,0.08),"amber_bulb")
	_work_light(center+Vector3(1.28,1.52,-0.10),true)
	var stencil_normal := Vector3(sin(-0.97),0,cos(-0.97))
	_label(center+stencil_normal*1.47-UP*0.62,"BELL   02",0.245,Color("373b32"),-0.97)
	_label(center+stencil_normal*1.47-UP*0.87,"KESTREL",0.105,Color("444537"),-0.97)
	# A paired bent lifting lug and cable run interrupt the lid silhouette.
	for direction in [-1.0,1.0]:
		var lug := center + Vector3(direction*0.54,1.63,0.15)
		_tube(lug,lug+UP*0.27,0.068,"edge",8)
		_tube(lug+UP*0.27,lug+Vector3(0,0.27,0.26),0.068,"edge",8)
		_tube(lug+Vector3(0,0.27,0.26),lug+FRONT*0.26,0.068,"edge",8)
	var line_base := center+Vector3(-1.245,-0.86,-0.65)
	_tube(line_base,line_base+UP*1.80,0.049,"brass",8)
	_tube(line_base+UP*1.80,center+Vector3(-0.70,1.66,-0.65),0.049,"brass",8)
	_label(center+Vector3(0,-0.58,-1.431),"BELL  02",0.27,Color("302f28"),PI)
	_label(center+Vector3(1.44,-0.57,0),"B-02",0.24,Color("302f28"),PI/2.0)
	# Stowed gas bottles held to the rear of the frame by paired bands.
	for i in 3:
		var p := center+Vector3(-0.69+i*0.46,0,1.41)
		_band(p,UP,1.70,0.215,"maroon",12)
		_dome(p+UP*0.82,Vector3(0.43,0.37,0.43),"maroon")
		_band(p+UP*1.04,UP,0.22,0.08,"brass",8)
		for y in [-0.58,0.55]:
			_band(p+UP*y,UP,0.11,0.232,"galvanized",12)

func _hose_setup() -> void:
	_hose = MultiMesh.new()
	_hose.transform_format = MultiMesh.TRANSFORM_3D
	_hose.use_colors = true
	_hose.mesh = _shape("8")
	_hose.instance_count = HOSE_SEGMENTS
	var draw := MultiMeshInstance3D.new()
	var jacket := StandardMaterial3D.new()
	jacket.vertex_color_use_as_albedo = true
	jacket.roughness = 0.91
	draw.material_override = jacket
	draw.name = "ExcursionUmbilical"
	draw.multimesh = _hose
	add_child(draw)
	for i in HOSE_SEGMENTS:
		_hose.set_instance_color(i,Color("c1a56b") if i % 6 < 5 else Color("52645b"))

func update_diver(pos: Vector3) -> void:
	if _hose == null or pos.distance_squared_to(_last_diver) < 0.0004:
		return
	_last_diver = pos
	var end := pos + Vector3(0.12,-0.88,0.06)
	var gap := CABLE_ORIGIN.distance_to(end)
	var sag := minf(gap * 0.19 + 0.20,2.30)
	var last := CABLE_ORIGIN
	for i in HOSE_SEGMENTS:
		var t := float(i+1) / HOSE_SEGMENTS
		var bow := sin(t*PI)
		var sample := CABLE_ORIGIN.lerp(end,t) + Vector3(-bow * 0.32,-bow*sag, bow * 0.43)
		var axis := sample-last
		var frame := _axis_basis(axis).scaled_local(Vector3(0.047,axis.length()+0.004,0.047))
		_hose.set_instance_transform(i,Transform3D(frame,(sample+last)*0.5))
		last = sample

func _suspended_particles() -> void:
	var particles := CPUParticles3D.new()
	particles.name = "SuspendedMatter"
	particles.amount = 175
	particles.lifetime = 19.0
	particles.preprocess = 19.0
	particles.position = Vector3(1,5,-5)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(14,8,14)
	particles.direction = Vector3(0.47,-0.50,0.15)
	particles.spread = 20.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.15
	particles.initial_velocity_max = 0.34
	particles.scale_amount_min = 0.38
	particles.scale_amount_max = 1.36
	var flake := QuadMesh.new()
	flake.size = Vector2(0.028,0.024)
	var skin := StandardMaterial3D.new()
	skin.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.albedo_color = Color("6e8a80")
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	flake.material = skin
	particles.mesh = flake
	add_child(particles)
