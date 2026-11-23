extends Node3D

const BELL := Vector3(0, 0, 8)
const A2 := Vector3(-4, 0, -4)
const B4 := Vector3(7, -2, -8)

# A2 sits on the outward face of the western sleeve. A working diver sees one bay.
const FRONT_LEFT := Vector3(-4.0, 0.0, -8.92)
const LONG_EDGE := Vector3(57.9, 0.0, -14.0)
const SHORT_EDGE := Vector3(-12.0, 0.0, -52.8)
const LEG_RADIUS := 2.97
const UP := Vector3.UP
const FRONT := Vector3.BACK
const CABLE_ORIGIN := Vector3(-2.62, -1.02, 7.5)
const HOSE_SEGMENTS := 18

var _materials: Dictionary = {}
var _shapes: Dictionary = {}
var _groups: Dictionary = {}
var _station_leds: Array[MeshInstance3D] = []
var _lamp_volume: MultiMeshInstance3D
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
	_lamp_haze()
	_suspended_particles()
	update_diver(BELL)

func _material(key: String, color: String, metal := 0.0, glow := 0.0, texture_path := "") -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.86
	material.metallic = metal
	if texture_path == "res://art/jacket.webp" and key in ["jacket","shadowsteel","pipe"]:
		var skin := ShaderMaterial.new()
		skin.shader = preload("res://world/worn_steel.gdshader")
		skin.set_shader_parameter("coating",Color(color))
		skin.set_shader_parameter("steel_albedo",preload("res://art/jacket.webp"))
		skin.set_shader_parameter("corrosion",preload("res://world/corrosion.tres"))
		_materials[key] = skin
		return
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
	_material("tag_enamel", "b8b69e", 0.05, 0.0, enamel)
	_material("hull", "efad55", 0.09, 0.0, enamel)
	_material("maroon", "94634d", 0.08)
	_material("navy", "2b494b", 0.10)
	_material("glass", "90bcb5", 0.19, 0.13)
	_material("amber_glass", "ffbe67", 0.07, 0.9)
	_material("amber_bulb", "ffdb97", 0.0, 2.2)
	_material("cold_bulb", "b5dfcf", 0.0, 1.5)
	_material("filed_bulb", "a8f3b5", 0.0, 1.6)
	_material("rope", "b09862")
	_material("growth", "8d8a71")
	_material("oxides", "976a4e")
	_material("sponge", "978c77")
	_material("shells", "a3a298")
	var pad := ShaderMaterial.new()
	pad.shader = preload("res://world/ground_patch.gdshader")
	pad.set_shader_parameter("steel",preload("res://art/jacket.webp"))
	pad.set_shader_parameter("tarnish",preload("res://world/corrosion.tres"))
	_materials["scrubbed"] = pad
	_service_finish("flange", "554a3c", 0.52)
	_service_finish("stud", "827357", 0.57)
	_service_finish("washer", "44463f", 0.46)
	_service_finish("handhold", "757a71", 0.4)
	_service_finish("carrier_enamel", "9c8956", 0.37)
	_material("guide_lip", "a28868", 0.04, 0.0, steel)
	_materials["guide_lip"].cull_mode = BaseMaterial3D.CULL_DISABLED
	_material("cast", "d8ccc6", 0.16, 0.0, steel)

func _service_finish(key: String, pigment: String, metal: float) -> void:
	var skin := ShaderMaterial.new()
	skin.shader = preload("res://game/tool_finish.gdshader")
	skin.set_shader_parameter("pigment",Color(pigment))
	skin.set_shader_parameter("wear",preload("res://art/jacket.webp"))
	skin.set_shader_parameter("metal",metal)
	_materials[key] = skin

func _environment() -> void:
	var volume := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("030809")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("294247")
	env.ambient_light_energy = 0.055
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 0.4
	env.fog_depth_end = 35.0
	env.fog_depth_curve = 0.94
	env.fog_light_color = Color("050a0c")
	env.fog_light_energy = 0.85
	volume.environment = env
	add_child(volume)

# A low barnacle skirt with a recessed crown. Clusters have gaps and broken edges.
func _shell_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outside: Array[Vector3] = []
	var rim: Array[Vector3] = []
	var inside: Array[Vector3] = []
	for i in 7:
		var theta := TAU * float(i)/7.0
		var ring := Vector3(cos(theta),0,sin(theta))
		outside.append(ring*(0.48 + 0.065*sin(i*2.1)) - UP*0.07)
		rim.append(ring*(0.20+0.035*cos(i*1.7)) + Vector3(0.055,0.49+0.13*cos(i*2.0),0.023))
		inside.append(ring*0.12 + Vector3(0.05,0.17,0.02))
	for i in 7:
		var j := (i+1)%7
		for v in [outside[i],rim[j],rim[i], outside[i],outside[j],rim[j],rim[i],inside[j],inside[i],rim[i],rim[j],inside[j]]:
			surface.add_vertex(v)
	surface.generate_normals()
	return surface.commit()

func _shape(kind: String) -> Mesh:
	if _shapes.has(kind):
		return _shapes[kind]
	var result: Mesh
	if kind == "box":
		result = BoxMesh.new()
	elif kind == "crust":
		result = _shell_mesh()
	elif kind == "guide":
		var funnel := CylinderMesh.new()
		funnel.top_radius = 1.0
		funnel.bottom_radius = 0.78
		funnel.height = 1.0
		funnel.cap_top = false
		funnel.cap_bottom = false
		funnel.radial_segments = 18
		funnel.rings = 0
		result = funnel
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
		if parts[1] in ["jacket", "shadowsteel", "pipe", "hull"]:
			draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else:
			draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(draw)
	_groups.clear()

# A battered, eight-legged jacket. Levels separate by an entire 23 m bay.
func _leg_at(column: int, row: int, h: float) -> Vector3:
	var p := FRONT_LEFT + float(column) / 3.0 * LONG_EDGE + float(row) * SHORT_EDGE
	var centre := FRONT_LEFT + 0.5 * (LONG_EDGE + SHORT_EDGE)
	return p + (centre - p).normalized() * (0.062 * h) + UP * h

func _jacket() -> void:
	for row in 2:
		for column in 4:
			var axis := (_leg_at(column, row, 1.0) - _leg_at(column, row, 0.0)).normalized()
			var radius := LEG_RADIUS if column in [0, 3] else 2.06
			_tube(_leg_at(column, row, -92), _leg_at(column, row, 94), radius, "jacket", 28, true)
			for j in range(-9, 10):
				var p := _leg_at(column, row, j * 9.13 + 2.9)
				_band(p, axis, 0.095, radius + 0.045, "edge", 28)
			for level in range(-3, 4):
				var h := -6.4 + 23.0 * level
				var foot := _leg_at(column, row, h)
				_band(foot, axis, 2.32, radius + 0.105, "shadowsteel", 28)
				if column < 3:
					var next := _leg_at(column + 1, row, h)
					_tube(foot, next, 1.12, "jacket", 18, true)
					var high := _leg_at(column + 1, row, h + 23.0)
					_tube(foot, high, 0.83, "jacket", 16, true)
					_tube(next, _leg_at(column, row, h + 23.0), 0.83, "shadowsteel", 16, true)
				if row==0 and column in [0,3]:
					var back := _leg_at(column, 1, h)
					_tube(foot, back, 1.04, "jacket", 16, true)
					_tube(foot, _leg_at(column, 1, h + 23.0), 0.93, "shadowsteel", 16, true)
					_tube(back, _leg_at(column, 0, h + 23.0), 0.93, "shadowsteel", 16, true)

	# Conductors run as a bundle into the dark interior.
	for column in 6:
		for row in 2:
			var p := Vector3(-1.8 + column * 2.25, 0, -24.0 - row * 2.1 - column * 0.45)
			_tube(p - UP * 75, p + UP * 75, 0.41, "pipe", 12)
			for level in [-31,-9,13,35]:
				_band(p + UP*level, UP, 0.27, 0.48, "edge", 12)
	# A small service ladder gives the near sleeve a human measure.
	var tangent := Vector3(0.83,0.0,0.56).normalized()
	var outward := Vector3(-0.56,0.0,0.83).normalized()
	var face := _leg_at(0,0,0) + outward * (LEG_RADIUS + 0.32)
	var slope := _leg_at(0,0,1) - _leg_at(0,0,0)
	for side in [-0.27,0.27]:
		_tube(face + tangent*side - slope*20, face + tangent*side + slope*16, 0.036,"iron",8)
	for i in range(-56,46):
		var rung := face + slope * i * 0.35
		_tube(rung-tangent*0.27, rung+tangent*0.27, 0.024,"galvanized",8)
		if i % 8 == 0:
			for side in [-0.27,0.27]:
				var end: Vector3 = rung + tangent*side
				_tube(end-outward*0.47,end,0.04,"iron",8)
	var low := _leg_at(0,0,-6.4)
	var high := _leg_at(1,0,16.6)
	_growth(_leg_at(0,0,-17), _leg_at(0,0,19), LEG_RADIUS, 2238, 70)
	_growth(low, high, 0.83, 740, 36)
	_growth(low, _leg_at(1,0,-6.4), 1.12, 391, 40)
	_growth(_leg_at(1,0,-6.4), _leg_at(0,0,16.6), 0.83, 736, 32)
	_piling_guide(Vector3(2.0,-5.3,-9.1))

	# A thin tended guide runs from one workface to the next.
	var ends := [Vector3(-5.0, -2.8, -5.78), Vector3(-4,-2.8,-5.72), Vector3(0,-3.48,-7.1),Vector3(7,-4.4,-9.7)]
	for i in ends.size()-1:
		var a: Vector3 = ends[i]
		var b: Vector3 = ends[i+1]
		var sag := a.lerp(b,0.5)+Vector3.DOWN*0.24
		_tube(a, sag, 0.028,"rope",8)
		_tube(sag, b, 0.028,"rope",8)
		_band(a.lerp(sag,0.38), sag-a, 0.09, 0.034,"chalk",8)

# The lip is built as an open flared sleeve. Its dark aperture remains visible from above.
func _piling_guide(at: Vector3) -> void:
	_place("guide", "guide_lip", Transform3D(Basis.from_scale(Vector3(1.37,1.4,1.37)),at))
	for height in [-0.68,0.69]:
		var radius := 1.37 if height > 0 else 1.07
		for i in 18:
			var a := TAU*i/18.0
			var b := TAU*(i+1)/18.0
			var p := at + Vector3(cos(a)*radius, height, sin(a)*radius)
			var q := at + Vector3(cos(b)*radius, height, sin(b)*radius)
			_tube(p, q, 0.065,"oxides",6)
	for i in [-1.0,1.0]:
		var toe := at+Vector3(i*0.84,-0.48,-0.50)
		_tube(toe, toe+Vector3(i*0.59,-1.03,-1.25),0.18,"shadowsteel",10)

# Patches follow actual cylinder normals so the ragged edges break the silhouette.
func _growth(a: Vector3,b: Vector3,radius: float,seed_value: int,patches: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frame := _axis_basis(b-a)
	var tints := ["growth","oxides","growth","sponge","shells","growth"]
	for patch in patches:
		var t := rng.randf_range(0.025,0.975)
		var angle := rng.randf()*TAU
		var tone: String = tints[rng.randi_range(0,tints.size()-1)]
		for k in rng.randi_range(7,15):
			var theta := angle + rng.randfn(0.0,0.26)/radius
			var normal := frame.x*cos(theta) + frame.z*sin(theta)
			var p := a.lerp(b,t) + normal*(radius+0.018) + frame.y*rng.randfn(0.0,0.34)
			var scale_size := rng.randf_range(0.07,0.26)
			var basis := _axis_basis(normal) * Basis(UP,rng.randf()*TAU)
			var size := Vector3(scale_size*1.33, scale_size*rng.randf_range(0.47,1.28), scale_size)
			_place("crust", tone, Transform3D(basis.scaled_local(size),p))

func _risers() -> void:
	for spec in [[-7.57,-7.65,0.40],[6.95,-10.62,0.71],[8.55,-11.10,0.31]]:
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
		var base := _leg_at(0,0,-6.4).lerp(_leg_at(1,0,-6.4),0.19+i*0.18) + FRONT*0.82
		for x in [-0.44,0.44]:
			_box(base+Vector3(x,0,0.22),Vector3(0.10,0.14,0.35),"edge")
		_box(base+FRONT*0.44,Vector3(1.25,0.16,0.19),"growth")
	# A low cable tray takes bundled services round the near leg and away to the rear.
	var near := Vector3(-6.85,-3.15,-8.75)
	var far := Vector3(-11.66,-3.55,-28.65)
	for i in 3:
		var lift := UP * (i*0.17)
		_tube(near+lift,far+lift,0.052,"iron",8)
	for i in range(8):
		var hanger := near.lerp(far,i/8.0)
		_box(hanger+Vector3(-0.12,0.12,0),Vector3(0.46,0.55,0.09),"edge")

func _plate(center: Vector3, text: String, width: float, height: float) -> void:
	_box(center, Vector3(width,height,0.075), "iron")
	_box(center + FRONT * 0.045, Vector3(width-0.045,height-0.045,0.025), "tag_enamel")
	# Small chips expose the backing around the lower edge and the bolt holes.
	for i in 6:
		var chip := center + Vector3(width*(0.12*i-0.42), -height*(0.38+0.035*sin(i*4.7)), 0.062)
		_box(chip,Vector3(0.045+0.014*cos(i*1.26),0.016,0.009),"oxides")
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
		_band(p - FRONT*stud*0.4, FRONT, stud*0.68, stud*1.42, "washer", 12)
		_band(p, FRONT, stud, stud, mat, 6)

func _rail(a: Vector3, b: Vector3, z: float, radius := 0.04) -> void:
	var aa := a + FRONT * z
	var bb := b + FRONT * z
	_tube(a, aa, radius, "handhold", 8)
	_tube(aa, bb, radius, "handhold", 8)
	_tube(bb, b, radius, "handhold", 8)

func _station_a() -> void:
	var hub := Vector3(-4,0,-5.99)
	# The wall probe lands on an exposed inspection pad in a ring of original coating.
	_band(hub, FRONT, 0.31, 0.64, "flange", 24)
	_band(hub + FRONT*0.18, FRONT, 0.10, 0.55, "cast", 24)
	_band(hub + FRONT*0.25, FRONT, 0.07, 0.43, "flange", 24)
	_band(hub + FRONT*0.30, FRONT, 0.045, 0.315, "washer", 24)
	_band(hub + FRONT*0.33, FRONT, 0.034, 0.25, "washer", 24)
	_band(hub + FRONT*0.355, FRONT, 0.014, 0.21, "scrubbed", 28)
	# Faint punch marks on the outer face identify the surveyed arc.
	for k in 3:
		var angle := -2.2 + k*0.085
		var radial := Vector3(cos(angle),sin(angle),0)
		var nick := hub + FRONT*0.288 + radial*0.399
		_tube(nick-radial*0.018,nick+radial*0.018,0.0035,"handhold",5)
	_studs(hub + FRONT*0.246, 0.493, 10, 0.047, "stud")
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
		_box(hub + Vector3(0,dy,0.10), Vector3(1.80,0.20,0.35),"carrier_enamel", true)
		for side in [-1.0,1.0]:
			var foot := hub + Vector3(side*0.71,dy,0.30)
			_band(foot, FRONT, 0.14, 0.102,"stud",6)
	_box(hub + Vector3(0,0,-0.025), Vector3(1.03,0.92,0.15), "navy")
	for side in [-1.0,1.0]:
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
	light.light_energy = 0.56
	light.omni_range = 2.3
	light.omni_attenuation = 1.2
	add_child(light)
	_scatter(at + FRONT*0.24, 1.3, warm)

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

# Four depth-tested, feathered cross sections integrate a little light scattered by the
# water before it reaches the eye. Nearby opaque steel occludes the farther sections.
func _lamp_haze() -> void:
	var mesh := QuadMesh.new()
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/lamp_haze.gdshader")
	mesh.material = material
	var sections := PackedFloat32Array([1.8,3.9,7.3,13.1])
	var layer := MultiMesh.new()
	layer.transform_format = MultiMesh.TRANSFORM_3D
	layer.mesh = mesh
	layer.instance_count = sections.size()
	for i in sections.size():
		var d := sections[i]
		var diameter := 1.06*d
		layer.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3(diameter,diameter,1.0)),Vector3.FORWARD*d))
	_lamp_volume = MultiMeshInstance3D.new()
	_lamp_volume.name = "IlluminatedWater"
	_lamp_volume.multimesh = layer
	_lamp_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_volume.visible = false
	add_child(_lamp_volume)

func update_lamp(pose: Transform3D, enabled: bool) -> void:
	if _lamp_volume != null:
		_lamp_volume.global_transform = pose
		_lamp_volume.visible = enabled

func _suspended_particles() -> void:
	_particle_layer("Silt", 1880, 7.7, 0.018, false, 582)
	_particle_layer("LooseFlakes", 860, 9.7, 0.034, false, 733)
	_particle_layer("DriftingStrands", 260, 8.3, 0.026, true, 912)

func _particle_layer(id: String, count: int, half_extent: float, size_m: float, strand: bool, seed_value: int) -> void:
	var grain := QuadMesh.new()
	var skin := ShaderMaterial.new()
	skin.shader = preload("res://world/marine_snow.gdshader")
	skin.set_shader_parameter("half_extent", half_extent)
	skin.set_shader_parameter("fleck_size",size_m)
	skin.set_shader_parameter("thread",1.0 if strand else 0.0)
	grain.material = skin
	var swarm := MultiMesh.new()
	swarm.transform_format = MultiMesh.TRANSFORM_3D
	swarm.use_custom_data = true
	swarm.mesh = grain
	swarm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var seed_point := Vector3(rng.randf(),rng.randf(),rng.randf()) * half_extent*2.0
		swarm.set_instance_transform(i,Transform3D(Basis.IDENTITY,seed_point))
		swarm.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),rng.randf(),rng.randf()))
	# The GPU follows the diver; this box keeps lamp selection and culling valid over the full excursion.
	swarm.custom_aabb = AABB(Vector3(-67,-36,-64),Vector3(136,80,140))
	var draw := MultiMeshInstance3D.new()
	draw.name = id
	draw.multimesh = swarm
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(draw)
