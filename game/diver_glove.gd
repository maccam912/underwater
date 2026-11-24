extends Node3D
## The gauntlet grips real equipment. The sleeve is a two-bone first-person rig.
## At long interaction distances its cuff projects onto the physical wrist.

const UPPER_LENGTH := .345
const FOREARM_LENGTH := .285
const HAND_SCALE := 1.52
const WRIST := Vector3(-.016,-.194,.027)
const SHELL := Color("#a3936b")
const RUBBER := Color("#343e3b")
const REINFORCEMENT := Color("#645d4e")
const THREAD := Color("#afa27c")
const SUIT := Color("#3d4442")
const FOLD := Color("#303534")

var gauntlet := MeshInstance3D.new()
var upper := MeshInstance3D.new()
var forearm := MeshInstance3D.new()
var grip_center := Vector3.ZERO
var _axis := Vector3.BACK
var _size := .03
var _grasp_axis := Vector3.ZERO
var _roll := 0.
var _grips := {}
var _material := StandardMaterial3D.new()

func _ready() -> void:
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = .82
	_material.metallic_specular = .28
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	gauntlet.name = "Gauntlet"
	upper.name = "UpperSleeve"
	forearm.name = "Forearm"
	for part: MeshInstance3D in [gauntlet,upper,forearm]:
		part.material_override = _material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(part)
	upper.mesh = _sleeve(false)
	forearm.mesh = _sleeve(true)
	visible = false

func stow() -> void:
	_grasp_axis = Vector3.ZERO
	hide()

func hold(point: Vector3, axis: Vector3, radius: float, roll := 0.) -> void:
	if _size != radius:
		_grasp_axis = Vector3.ZERO
	_roll = roll
	grip_center = point
	_axis = axis.normalized()
	if not _grips.has(radius):
		_grips[radius] = _make_grip(radius/HAND_SCALE)
	gauntlet.mesh = _grips[radius]
	_size = radius
	visible = true
	pose(get_viewport().get_camera_3d())

func pose(camera: Camera3D) -> void:
	if not visible or camera == null:
		return
	var shoulder := camera.to_global(Vector3(-.20,-.22,.045))
	# The back of the left hand faces the eye at a crosswise handle.
	# On an end-on barrel, the knuckles sit on its left flank.
	var view := grip_center.direction_to(camera.global_position)
	var dorsal := (view-camera.global_basis.x*.78+camera.global_basis.y*.14).slide(_axis)
	if dorsal.length_squared()<.001:
		dorsal = camera.global_basis.y.slide(_axis)
	var x := _axis
	var z := dorsal.normalized()
	var y := z.cross(x)
	# Pick the thumb side on first grasp and keep it throughout the stroke.
	var orientation := _grasp_axis.dot(x) if _grasp_axis != Vector3.ZERO else y.dot(camera.global_basis.x*.67+camera.global_basis.y*.74)
	if orientation<0.:
		x = -x
		y = -y
	_grasp_axis = x
	# Flex the wrist toward the elbow while keeping the back of the glove in view.
	var rise := (camera.global_basis.x*.72+camera.global_basis.y*.74-camera.global_basis.z*.25).slide(x)
	if rise.length_squared()>.001:
		y = y.rotated(x,clampf(y.signed_angle_to(rise.normalized(),x),-.54,.54))
	if _roll != 0.:
		y = y.rotated(x,_roll)
	z = x.cross(y)
	gauntlet.global_transform = Transform3D(Basis(x,y,z).scaled(Vector3.ONE*HAND_SCALE),grip_center)
	# The sleeve disappears inside the sealed fabric cuff. Its rounded rubber
	# termination fills the joint when the wrist is flexed across the forearm.
	var physical_wrist := gauntlet.to_global(WRIST+Vector3(0,.016,_size/HAND_SCALE))
	var eye := camera.global_position
	var ray := eye.direction_to(physical_wrist)
	if ray == Vector3.ZERO or camera.is_position_behind(physical_wrist):
		upper.hide()
		forearm.hide()
		gauntlet.hide()
		return
	gauntlet.show()
	upper.show()
	forearm.show()
	var offset := shoulder-eye
	var along := offset.dot(ray)
	var reach := UPPER_LENGTH+FOREARM_LENGTH-.12
	var farthest := along+sqrt(maxf(0.,reach*reach-offset.slide(ray).length_squared()))
	var physical_distance := eye.distance_to(physical_wrist)
	var wrist := eye+ray*minf(physical_distance,farthest)
	var separation := shoulder.distance_to(wrist)
	if separation < .001:
		upper.hide()
		forearm.hide()
		return
	var direction := shoulder.direction_to(wrist)
	var pole := camera.global_basis*Vector3(-.83,-.53,.1)
	var bend := pole.slide(direction)
	if bend.length_squared()<.0001:
		bend = camera.global_basis.z.slide(direction)
	var distance_on_arm := (UPPER_LENGTH*UPPER_LENGTH-FOREARM_LENGTH*FOREARM_LENGTH+separation*separation)/(2.*separation)
	var elbow := shoulder+direction*distance_on_arm+bend.normalized()*sqrt(maxf(0.,UPPER_LENGTH*UPPER_LENGTH-distance_on_arm*distance_on_arm))
	upper.global_transform = _bone_frame(shoulder,elbow,camera)
	forearm.global_transform = _bone_frame(elbow,wrist,camera)
	var wrist_scale := clampf(eye.distance_to(wrist)/physical_distance,0.,1.)
	upper.set_blend_shape_value(0,1.-wrist_scale)
	forearm.set_blend_shape_value(0,1.-wrist_scale)

func _bone_frame(start: Vector3, finish: Vector3, camera: Camera3D) -> Transform3D:
	var y := start.direction_to(finish)
	var ref := camera.global_basis.z
	if absf(ref.dot(y))>.96:
		ref = camera.global_basis.x
	var x := y.cross(ref).normalized()
	return Transform3D(Basis(x,y,x.cross(y)),start)

# Each ring has its own elliptical profile and follows the tangent of the
# centreline. The same construction gives fingers curved joints and gives
# the palm, wrist seal and cuff a continuous contour.
func _tube(st: SurfaceTool, centers: PackedVector3Array, widths: PackedVector2Array,
		guide: Vector3, colors: Array, sides: int = 12) -> void:
	var previous := PackedVector3Array()
	var previous_n := PackedVector3Array()
	for i in centers.size():
		var tangent := (centers[mini(i+1,centers.size()-1)]-centers[maxi(0,i-1)]).normalized()
		var across := guide.slide(tangent).normalized()
		var depth := across.cross(tangent).normalized()
		var ring := PackedVector3Array()
		var normals := PackedVector3Array()
		for j in sides:
			var a := TAU*j/sides
			var n := (across*cos(a)/widths[i].x+depth*sin(a)/widths[i].y).normalized()
			if i == 0 or i == centers.size()-1:
				n = (n+tangent*(.60 if i>0 else -.6)).normalized()
			ring.append(centers[i]+across*widths[i].x*cos(a)+depth*widths[i].y*sin(a))
			normals.append(n)
		if i>0:
			for j in sides:
				var k := (j+1)%sides
				_vertex(st,previous[j],previous_n[j],colors[i-1])
				_vertex(st,ring[k],normals[k],colors[i])
				_vertex(st,ring[j],normals[j],colors[i])
				_vertex(st,previous[j],previous_n[j],colors[i-1])
				_vertex(st,previous[k],previous_n[k],colors[i-1])
				_vertex(st,ring[k],normals[k],colors[i])
		previous=ring
		previous_n=normals

func _vertex(st: SurfaceTool, point: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(point)

func _make_grip(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var knuckle := radius+.017
	# A closed rubber wrist seal beneath the flared gauntlet sleeve.
	var seal := WRIST+Vector3.BACK*radius
	_tube(st,[seal+Vector3.DOWN*.028,seal+Vector3.DOWN*.023,seal+Vector3.DOWN*.012,seal,
		seal+Vector3.UP*.012,seal+Vector3.UP*.02],
		[Vector2(.008,.008),Vector2(.028,.024),Vector2(.044,.038),Vector2(.049,.041),
		Vector2(.047,.040),Vector2(.035,.032)],Vector3.RIGHT,[RUBBER,RUBBER,FOLD,FOLD,RUBBER,RUBBER])
	# From the suit seal up to the four metacarpals.
	_tube(st,[WRIST+Vector3(0,-.006,radius),WRIST+Vector3.BACK*radius,
			Vector3(-.016,-.181,radius+.025),Vector3(-.016,-.173,radius+.022),
			Vector3(-.015,-.169,radius+.021),Vector3(-.015,-.158,radius+.019),
			Vector3(-.014,-.154,radius+.018),Vector3(-.014,-.132,radius+.009),
			Vector3(-.012,-.111,radius+.009),Vector3(-.011,-.106,radius+.008),
			Vector3(-.008,-.094,radius+.010),Vector3(-.003,-.065,knuckle),
			Vector3(.002,-.029,knuckle+.003),Vector3(.001,-.004,knuckle),Vector3(0,.009,knuckle-.003)],
		[Vector2(.052,.043),Vector2(.052,.043),Vector2(.050,.042),Vector2(.047,.039),
			Vector2(.049,.040),Vector2(.048,.039),Vector2(.046,.038),Vector2(.043,.035),Vector2(.043,.032),Vector2(.046,.034),
			Vector2(.039,.029),Vector2(.046,.032),Vector2(.053,.031),Vector2(.052,.025),Vector2(.047,.017)],
		Vector3.RIGHT,[RUBBER,THREAD,REINFORCEMENT,RUBBER,THREAD,THREAD,RUBBER,REINFORCEMENT,RUBBER,THREAD,RUBBER,SHELL,SHELL,REINFORCEMENT,SHELL],16)
	# Four separately tapered fingers turn the near knuckle over the handle.
	for finger in 4:
		var x := -.038+float(finger)*.025
		var span: float = [.081,.096,.105,.098][finger]
		var pad: float = [.0105,.0124,.0130,.0120][finger]
		var reach_angle := minf(3.60,span/(radius+pad))
		var path := PackedVector3Array()
		var widths := PackedVector2Array()
		for i in 9:
			var f := i/8.
			var a := -.10+f*reach_angle
			var taper: float = [1.04,1.08,1.02,1.05,.94,.99,.88,.74,.22][i]
			var track := radius+pad*.88
			path.append(Vector3(x*(1.-.08*f),sin(a)*track,cos(a)*track))
			widths.append(Vector2(pad*taper,pad*1.05*taper))
		_tube(st,path,widths,Vector3.RIGHT,[SHELL,REINFORCEMENT,REINFORCEMENT,SHELL,
				RUBBER,REINFORCEMENT,SHELL,RUBBER,RUBBER])
	# Opposed thumb crosses the open side of the grip. Its base overlaps
	# the thenar pad and the tip rests beyond the index finger.
	_tube(st,[Vector3(.019,-.069,radius+.010),Vector3(.036,-.058,radius+.013),
			Vector3(.052,-.043,radius+.008),Vector3(.060,-.028,radius-.004),
			Vector3(.060,-.012,radius-.016),Vector3(.056,.001,radius-.024),
			Vector3(.052,.008,radius-.026)],
		[Vector2(.020,.017),Vector2(.022,.019),Vector2(.018,.016),Vector2(.016,.014),
			Vector2(.014,.014),Vector2(.012,.012),Vector2(.004,.005)],
		Vector3.RIGHT,[SHELL,SHELL,REINFORCEMENT,REINFORCEMENT,SHELL,RUBBER,RUBBER])
	# Sewn back panel and its two bands of thread lie against the knuckles.
	for i in 4:
		var x := -.034+i*.022
		var z := knuckle+.031*(sqrt(maxf(0.,1.-pow(x/.054,2.))))
		_tube(st,[Vector3(x*.74-.003,-.073,z-.008),Vector3(x*.89,-.047,z+.001),
			Vector3(x,-.029,z+.004),Vector3(x,-.016,z)],
			[Vector2(.002,.002),Vector2(.005,.003),Vector2(.006,.004),Vector2(.002,.002)],
			Vector3.RIGHT,[SHELL,REINFORCEMENT,REINFORCEMENT,SHELL],8)
	st.index()
	return st.commit()

func _sleeve(lower: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := FOREARM_LENGTH if lower else UPPER_LENGTH
	var path := PackedVector3Array()
	var widths := PackedVector2Array()
	var colors := []
	# The slight bellows at the elbow and the compressed folds at the cuff
	# keep their spacing while the arm bends.
	var stops := [0.,.04,.075,.105,.16,.22,.32,.49,.66,.73,.78,.82,.858,.90,.965,1.]
	for i in stops.size():
		var f: float = stops[i]
		var r: float = lerpf(.069,.074,f) if lower else lerpf(.080,.069,f)
		var ripple: float = [1.,1.015,.96,1.025,.965,1.025,1.017,1.,1.018,1.039,.965,1.04,.96,1.028,1.,.99][i]
		path.append(Vector3(0.,f*length,0.))
		if lower and f>=.965:
			r *= .84 if f<1. else .39
		widths.append(Vector2(r*ripple,r*ripple*.88))
		colors.append(FOLD if i in [2,4,10,12] else (RUBBER if lower and f>=.965 else SUIT))
	_tube(st,path,widths,Vector3.RIGHT,colors,16)
	# The double-stitched wear strip follows the outer face of the elbow.
	for side in [-1.,1.]:
		var seam_path := PackedVector3Array()
		var seam_widths := PackedVector2Array()
		var seam_colors := []
		for i in range(1,stops.size()-2):
			var w := widths[i]
			var dir := Vector2(side*.60,.80)
			seam_path.append(path[i]+Vector3(dir.x*w.x,0.,dir.y*w.y))
			seam_widths.append(Vector2(.0029,.0018))
			seam_colors.append(REINFORCEMENT)
		_tube(st,seam_path,seam_widths,Vector3.RIGHT,seam_colors,8)
	st.index()
	var raw := st.commit()
	var mesh := ArrayMesh.new()
	mesh.add_blend_shape("Cuff perspective")
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	var arrays := raw.surface_get_arrays(0)
	var displacements := PackedVector3Array()
	var zero_normals := PackedVector3Array()
	for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		displacements.append(Vector3(-p.x,0.,-p.z))
		zero_normals.append(Vector3.ZERO)
	var blend := []
	blend.resize(Mesh.ARRAY_MAX)
	blend[Mesh.ARRAY_VERTEX] = displacements
	blend[Mesh.ARRAY_NORMAL] = zero_normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[blend])
	return mesh
