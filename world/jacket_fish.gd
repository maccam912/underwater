extends MultiMeshInstance3D

# A loose shoal cuts across the working level. A smaller group patrols below
# the walkway, visible chiefly when a diver looks away from their own job.
const UPPER_COUNT := 9
const FISH_COUNT := 15
var elapsed := 0.0
var offsets: Array[Vector3] = []
var lengths: Array[float] = []
var sidesteps: Array[Vector3] = []
# After a disturbance the shoal bolts out of the light and stays away a while.
var flee_dirs: Array[Vector3] = []
var travel := 0.0
var rush := 0.0
var away := 0.0
var absence := 0.0

func _ready() -> void:
	name = "JacketFish"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _pollock()
	multimesh.custom_aabb = AABB(Vector3(-44,-37,-26),Vector3(92,64,62))
	multimesh.instance_count = FISH_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 9162
	for i in FISH_COUNT:
		offsets.append(Vector3(rng.randf_range(-2.4,2.4),rng.randf_range(-0.7,0.8),rng.randf_range(-0.9,0.9)))
		lengths.append(rng.randf_range(0.40,0.68) if i < UPPER_COUNT else rng.randf_range(0.62,0.98))
		sidesteps.append(Vector3.ZERO)
		flee_dirs.append(Vector3.ZERO)
		multimesh.set_instance_color(i, Color.WHITE)
		multimesh.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),0,1))
	_process(0.0)

## Fish nearest the source bolt first. They return once the water is quiet.
func startle(origin: Vector3, seconds := 50.0) -> void:
	for i in FISH_COUNT:
		var from_source := multimesh.get_instance_transform(i).origin - origin
		from_source.y = absf(from_source.y) * 0.3 + 0.15
		flee_dirs[i] = from_source.normalized() if from_source.length() > 0.01 else Vector3.FORWARD
	rush = 1.0
	absence = maxf(absence, seconds)


## 1 when the shoal is in its usual water, 0 when it has gone.
func presence() -> float:
	return 1.0 - away


func _process(delta: float) -> void:
	elapsed += delta
	rush = move_toward(rush, 0.0, delta / 7.0)
	absence = maxf(0.0, absence - delta)
	away = move_toward(away, 1.0 if absence > 0.0 else 0.0, delta * (0.8 if absence > 0.0 else 0.03))
	travel += delta * (1.0 + 2.4 * rush)
	var flight := smoothstep(0.0, 1.0, away) * 19.0
	var camera := get_viewport().get_camera_3d()
	for i in FISH_COUNT:
		var upper := i < UPPER_COUNT
		var angle := travel * (0.090 if upper else -0.058) + (-0.22 if upper else 1.22)
		var spread := offsets[i]
		angle += 0.24*sin(elapsed*0.16) + spread.x*0.12
		var centre := Vector3(0,-0.3,0.1) if upper else Vector3(2,-9,4)
		var radius_x := 13.0 if upper else 16.0
		var radius_z := 2.6 if upper else 4.8
		var lift := sin(elapsed*0.31+spread.z*2.7)*0.17
		var pos := centre + Vector3(sin(angle)*radius_x, sin(angle*2.0)*0.7+spread.y+lift, cos(angle)*radius_z+spread.z)
		var heading := Vector3(cos(angle)*radius_x,cos(angle*2.0)*1.4,-sin(angle)*radius_z).normalized()
		if not upper:
			heading = -heading
		pos += flee_dirs[i] * flight
		if rush > 0.0 and absence > 0.0:
			heading = heading.lerp(flee_dirs[i], rush).normalized()
		var avoid := Vector3.ZERO
		if camera:
			var separation := pos - camera.global_position
			var range_m := separation.length()
			if range_m < 3.0:
				avoid = separation.normalized() * (3.0 - range_m)
		var old_offset := sidesteps[i]
		sidesteps[i] = old_offset.lerp(avoid,1.0-exp(-2.2*delta))
		heading = (heading + (avoid-old_offset)*0.7).normalized()
		var side := heading.cross(Vector3.UP).normalized()
		var frame := Basis(heading,side.cross(heading),side).scaled(Vector3.ONE*lengths[i])
		multimesh.set_instance_transform(i,Transform3D(frame,pos+sidesteps[i]))

func _pollock() -> ArrayMesh:
	var meshout := SurfaceTool.new()
	meshout.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Torpedo-shaped trunk, narrow peduncle and slightly projecting lower jaw.
	# Each profile records longitudinal position, girth and height.
	var profiles := [
		Vector3(-0.36,0.024,0.038), Vector3(-0.23,0.065,0.101),
		Vector3(-0.015,0.097,0.155), Vector3(0.185,0.091,0.143),
		Vector3(0.31,0.070,0.094), Vector3(0.447,0.016,0.023)]
	var near_side := Color("82948a")
	var back := Color("354b4b")
	var belly := Color("bbc2a5")
	var rings: Array[PackedVector3Array] = []
	for section: Vector3 in profiles:
		var ring := PackedVector3Array()
		for j in 8:
			var phi := TAU*j/8.0
			ring.append(Vector3(section.x,section.z*cos(phi)-maxf(section.x,0)*0.056,section.y*sin(phi)))
		rings.append(ring)
	for n in range(rings.size()-1):
		for j in 8:
			var k := (j+1)%8
			var a := rings[n][j]
			var b := rings[n][k]
			var c := rings[n+1][k]
			var d := rings[n+1][j]
			for point: Vector3 in [a,c,b,a,d,c]:
				var vertical := Vector2(point.y+maxf(0.0,point.x)*0.056,point.z*1.6).normalized().x
				var flank := near_side.lerp(back,smoothstep(0.0,0.82,vertical))
				meshout.set_color(flank.lerp(belly,smoothstep(0.0,1.0,-vertical)))
				meshout.add_vertex(point)
	for j in 8:
		var k := (j+1)%8
		_triangle(meshout,rings.back()[j],rings.back()[k],Vector3(0.456,-0.022,0),near_side)
		_triangle(meshout,rings.front()[k],rings.front()[j],Vector3(-0.38,0,0),back)
	# Forked tail, three dorsal fins, two anal fins and swept pectorals.
	var root_top := Vector3(-0.33,0.036,0)
	var root_bottom := Vector3(-0.33,-0.036,0)
	var notch := Vector3(-0.477,0,0)
	_triangle(meshout,root_top,Vector3(-0.557,0.155,0),notch,back)
	_triangle(meshout,notch,root_bottom,root_top,back)
	_triangle(meshout,notch,Vector3(-0.55,-0.124,0),root_bottom,near_side)
	for fin: Vector3 in [Vector3(-0.21,-0.30,0.14),Vector3(-0.02,-0.16,0.21),Vector3(0.17,0.008,0.23)]:
		_triangle(meshout,Vector3(fin.x,0.084,0),Vector3(fin.y,fin.z,0),Vector3(fin.y-0.035,0.064,0),back)
	for fin_x in [-0.13, 0.065]:
		_triangle(meshout,Vector3(fin_x,-0.10,0),Vector3(fin_x-0.125,-0.17,0),Vector3(fin_x-0.15,-0.07,0),near_side)
	for flank in [-1.0,1.0]:
		_triangle(meshout,Vector3(0.16,-0.014,flank*0.091),Vector3(0.07,-0.035,flank*0.095),Vector3(-0.033,-0.089,flank*0.152),back)
		# The lateral line and gill cover read during a broadside turn in the lamp.
		for n in range(1,4):
			var a: Vector3 = profiles[n]
			var b: Vector3 = profiles[n+1]
			var start := Vector3(a.x,a.z*0.20,flank*a.y*0.96)
			var end := Vector3(b.x,b.z*0.20,flank*b.y*0.96)
			_triangle(meshout,start,end,end+Vector3.UP*0.009,belly)
			_triangle(meshout,start,end+Vector3.UP*0.009,start+Vector3.UP*0.009,belly)
		var eye := Vector3(0.31,0.018,flank*0.067)
		_triangle(meshout,eye+Vector3.UP*0.024,eye-Vector3.RIGHT*0.022,eye-Vector3.UP*0.024,Color("242e2d"))
		_triangle(meshout,eye+Vector3.UP*0.024,eye-Vector3.UP*0.024,eye+Vector3.RIGHT*0.022,Color("242e2d"))
		var gill := Vector3(0.19,0.030,flank*0.090)
		_triangle(meshout,gill,gill+Vector3(-0.027,-0.083,flank*0.002),gill+Vector3(-0.004,-0.062,0),Color("485957"))
	meshout.generate_normals()
	var skin := ShaderMaterial.new()
	skin.shader = preload("res://world/fish_skin.gdshader")
	meshout.set_material(skin)
	return meshout.commit()

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
