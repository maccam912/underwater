@abstract
extends Node3D
## Every pick intersects the front of a physical component in the station's local space.

signal adjusted(values: Array)
signal submitted(success: bool, detail: String)
signal hint_changed(text: String)

const FONT := preload("res://ui/fonts/CourierPrime-Regular.ttf")
const STEEL := preload("res://art/jacket.webp")
const ENAMEL := preload("res://art/enamel.webp")
const GLASS := preload("res://game/scope_glass.gdshader")
const DiverGlove = preload("res://game/diver_glove.gd")
const FINISH := preload("res://game/tool_finish.gdshader")
const ANCHORS := [Vector3(-4,0,-5.615), Vector3(7,-2,-9.52)]
const METER := Vector3(.72,-.045,.21)
const GLASS_WIDTH := .56
const GLASS_HEIGHT := .27
const GLASS_C := METER + Vector3(0,.087,.098)
const DIAL := METER + Vector3(-.145,-.189,.142)
const STAMP := METER + Vector3(.196,-.191,.134)
const PROBE_REST := Vector3(-.37,-.12,.31)
const CABLE_SEGMENTS := 12
var _job := -1
var _watch := 1
var _working := false
var _accepted := false
var _touch := false
var _content: Node3D
var _shapes := {}
var _surfaces := {}
var _batch := {}
var _glass: ShaderMaterial
var _reading: Label3D
var _probe: Node3D
var _dial: Node3D
var _stamp: Node3D
var _lead: MultiMesh
var _carrier: Node3D
var _glove := DiverGlove.new()
var _drag := ""
var _finger := -2
var _press := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _start_detent := 0
var _feedback := ""
var _stamp_travel := 0.0

func set_working(active:bool) -> void:
	_working = active
	_drag = ""
	_finger = -2
	_feedback = ""
	_refresh(true)

func focus_point() -> Vector3:
	return to_global(Vector3(.28,-.05,.04) if _job == 0 else Vector3(0,0,.03))

@abstract func instruction(touch: bool) -> String
@abstract func _refresh(instant := false) -> void
@abstract func _press_at(camera: Camera3D, at: Vector2, finger: int) -> bool
@abstract func _drag_to(camera: Camera3D, at: Vector2, finger: int) -> bool
@abstract func _release_at(camera: Camera3D, at: Vector2, finger: int) -> bool

func control_point(id: String) -> Vector3:
	match id:
		"dial": return to_global(DIAL)
		"stamp": return to_global(STAMP)
	return global_position

func _build() -> void:
	if _content != null:
		remove_child(_content)
		_content.queue_free()
	_content = Node3D.new()
	add_child(_content)
	_shapes.clear()
	_surfaces.clear()
	_batch.clear()
	_surface("iron","6d6655",STEEL)
	_surface("ochre","e3c39d",ENAMEL)
	_surface("rubber","364541")
	_surface("boot","49564a")
	_surface("steel","a7a69a")
	_surface("brass","b99a63")
	_surface("white","c1c0a5")
	_surface("red","9c5a43")
	_surface("glove","6b786b")
	_surface("sleeve","67674e")
	_surface("scratch","82735f")
	_build_equipment()
	add_child(_glove)
	_flush()

func _surface(key:String, tint:String, tex:Texture2D = null) -> void:
	if tex == ENAMEL:
		var paint := ShaderMaterial.new()
		paint.shader = preload("res://game/worn_enamel.gdshader")
		paint.set_shader_parameter("enamel", ENAMEL)
		paint.set_shader_parameter("wear", STEEL)
		paint.set_shader_parameter("tint", Color(tint))
		_surfaces[key] = paint
		return
	if tex == null:
		var finish:=ShaderMaterial.new()
		finish.shader=FINISH
		finish.set_shader_parameter("pigment",Color(tint))
		finish.set_shader_parameter("wear",STEEL)
		finish.set_shader_parameter("metal",.87 if key in ["steel","brass","red","scratch"] else .10)
		_surfaces[key]=finish
		return
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(tint)
	skin.roughness = .88
	skin.albedo_texture = tex
	skin.uv1_triplanar = true
	skin.uv1_world_triplanar = true
	skin.uv1_scale = Vector3.ONE*2.5
	_surfaces[key] = skin

func _primitive(kind:String) -> PrimitiveMesh:
	if _shapes.has(kind):
		return _shapes[kind]
	var shape:PrimitiveMesh
	if kind == "box":
		shape = BoxMesh.new()
	elif kind == "round":
		var ball := SphereMesh.new()
		ball.radial_segments = 9
		ball.rings = 5
		shape = ball
	else:
		var tube := CylinderMesh.new()
		tube.top_radius = .5
		tube.bottom_radius = .5
		tube.height = 1
		tube.radial_segments = int(kind)
		tube.rings = 0
		shape = tube
	_shapes[kind] = shape
	return shape

func _part(parent:Node3D, kind:String, mat:String, basis:Basis, loc:Vector3) -> void:
	if not _batch.has(parent):
		_batch[parent] = {}
	var groups:Dictionary = _batch[parent]
	var key := kind+"|"+mat
	if not groups.has(key):
		groups[key] = []
	groups[key].append(Transform3D(basis,loc))

func _box(parent:Node3D, loc:Vector3, size:Vector3, mat:String, angle := 0.0) -> void:
	_part(parent,"box",mat,Basis(Vector3.BACK,angle).scaled_local(size),loc)

func _round(parent:Node3D,loc:Vector3,size:Vector3,mat:String) -> void:
	_part(parent,"round",mat,Basis.from_scale(size),loc)

func _shaft_frame(a:Vector3,b:Vector3,r:float) -> Transform3D:
	var axis := b-a
	var frame := Basis(Quaternion(Vector3.UP,axis.normalized()))
	return Transform3D(frame.scaled_local(Vector3(r*2,axis.length(),r*2)),(a+b)*.5)

func _rod(parent:Node3D,a:Vector3,b:Vector3,r:float,mat:String,sides:=10) -> void:
	var t := _shaft_frame(a,b,r)
	_part(parent,str(sides),mat,t.basis,t.origin)

func _face_disc(parent:Node3D, at:Vector3,r:float,depth:float,mat:String,sides:=12) -> void:
	_rod(parent,at-Vector3.BACK*depth*.5,at+Vector3.BACK*depth*.5,r,mat,sides)

func _flush() -> void:
	for parent:Node3D in _batch:
		var groups:Dictionary=_batch[parent]
		for key:String in groups:
			var parts:=key.split("|")
			var instances:=MultiMesh.new()
			instances.transform_format=MultiMesh.TRANSFORM_3D
			instances.mesh=_primitive(parts[0])
			var poses:Array=groups[key]
			instances.instance_count=poses.size()
			for i in poses.size():
				instances.set_instance_transform(i,poses[i])
			var draw:=MultiMeshInstance3D.new()
			draw.multimesh=instances
			# The case, shoes and gauntlet cast distinct silhouettes. Fine
			# scratches and engraved ticks share their parent’s shadow.
			var casts := key in ["box|ochre","6|brass","round|glove","10|sleeve","10|red"]
			draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			draw.material_override=_surfaces[parts[1]]
			parent.add_child(draw)
	_batch.clear()

func _pivot(parent:Node3D, loc:Vector3) -> Node3D:
	var node:=Node3D.new()
	node.position=loc
	parent.add_child(node)
	return node

func _label(parent:Node3D,word:String,at:Vector3,height:float,tint:Color, tilt:=0.0) -> Label3D:
	var label:=Label3D.new()
	label.text=word
	label.font=FONT
	label.font_size=48
	label.pixel_size=height/48.
	label.outline_size=0
	label.shaded=true
	label.double_sided=false
	label.modulate=tint
	label.position=at
	label.rotation.z=tilt
	label.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)
	return label

func _scrapes(parent:Node3D,center:Vector3,w:float,h:float,seed_value:int) -> void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	for i in 24:
		var at:=center+Vector3(rng.randf_range(-w,w),rng.randf_range(-h,h),0)
		_box(parent,at,Vector3(rng.randf_range(.009,.052),rng.randf_range(.002,.006),.002),"scratch",rng.randf_range(-.8,.8))

func _build_equipment() -> void:
	var mount:=_pivot(_content,METER)
	# Twin rubber straps hold the survey meter to a grab rail above the excursion lead.
	for x in [-.235,.235]:
		_box(mount,Vector3(x,0,-.105),Vector3(.055,.81,.09),"rubber")
		_rod(mount,Vector3(x,.37,-.12),Vector3(x,.37,-.42),.022,"steel")
	_box(mount,Vector3.ZERO,Vector3(.73,.64,.14),"ochre")
	_box(mount,Vector3(0,.085,.071),Vector3(.631,.34,.042),"rubber")
	for x in [-.325,.325]:
		for y in [-.269,.269]:
			_box(mount,Vector3(x,y,0),Vector3(.08,.093,.173),"boot")
			_face_disc(mount,Vector3(x,y,.092),.018,.018,"steel",6)
	_scrapes(mount,Vector3(0,-.19,.0715),.29,.102,779)
	_box(mount,Vector3(-.06,.277,.073),Vector3(.337,.050,.010),"rubber")
	_label(mount,"UT   0–24 mm",Vector3(-.06,.277,.081),.043,Color("#d9cfaf"))
	var scope:=MeshInstance3D.new()
	var face:=QuadMesh.new()
	face.size=Vector2(GLASS_WIDTH,GLASS_HEIGHT)
	scope.mesh=face
	_glass=ShaderMaterial.new()
	_glass.shader=GLASS
	_glass.set_shader_parameter("wear",STEEL)
	scope.material_override=_glass
	scope.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scope.position=GLASS_C-METER
	mount.add_child(scope)
	_box(mount,Vector3(0,-.074,.097),Vector3(.59,.047,.014),"rubber")
	_label(mount,"0     6     12     18     24",Vector3(0,-.071,.108),.030,Color("#c4c4a8"))
	_dial=_pivot(mount,DIAL-METER)
	_face_disc(_dial,Vector3.ZERO,.086,.10,"rubber",14)
	for i in 14:
		var a:=float(i)/14.*TAU
		var v:=Vector3(cos(a),sin(a),0)
		_rod(_dial,v*.063+Vector3.BACK*.025,v*.086+Vector3.BACK*.025,.006,"iron",6)
	_box(_dial,Vector3(0,.042,.056),Vector3(.018,.063,.009),"white")
	_box(mount,Vector3(-.18,-.296,.074),Vector3(.115,.044,.009),"rubber",-.035)
	_label(mount,"GATE",Vector3(-.18,-.296,.082),.040,Color("#d9cfaf"),-.035)
	_stamp=_pivot(mount,STAMP-METER)
	_face_disc(mount,STAMP-METER-Vector3.BACK*.023,.075,.044,"iron")
	_face_disc(_stamp,Vector3.ZERO,.061,.074,"red",12)
	_box(_stamp,Vector3(0,0,.039),Vector3(.061,.009,.006),"white")
	_box(mount,Vector3(.185,-.296,.076),Vector3(.117,.044,.009),"rubber",.02)
	_label(mount,"MARK",Vector3(.185,-.296,.084),.041,Color("#d9cfaf"),.02)
	_box(mount,Vector3(.03,-.178,.074),Vector3(.157,.082,.016),"rubber")
	_reading=_label(mount,"03",Vector3(.03,-.176,.086),.073,Color("#cec9ac"))
	# A blunt prehensile glove grips the insulated barrel. Its brass nose moves onto bare steel.
	_probe=_pivot(_content,PROBE_REST)
	_face_disc(_probe,Vector3(0,0,.047),.060,.092,"steel",12)
	_face_disc(_probe,Vector3(0,0,.127),.070,.095,"ochre",12)
	_face_disc(_probe,Vector3(0,0,.203),.052,.075,"rubber",10)
	# The lead hangs in a loop between the handheld transducer and the housing.
	_lead=MultiMesh.new()
	_lead.transform_format=MultiMesh.TRANSFORM_3D
	_lead.mesh=_primitive("8")
	_lead.instance_count=CABLE_SEGMENTS
	var lead_mesh:=MultiMeshInstance3D.new()
	lead_mesh.multimesh=_lead
	lead_mesh.material_override=_surfaces["rubber"]
	lead_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_content.add_child(lead_mesh)
	_face_disc(mount,Vector3(-.25,-.314,-.024),.046,.069,"brass",6)

func _hold_tool(point: Vector3, axis: Vector3, radius: float, roll := 0.) -> void:
	_glove.hold(to_global(point),global_basis*axis,radius,roll)

func follow_view(camera: Camera3D) -> void:
	# A stationary finger still moves across the work when the diver fins sideways.
	if _finger != -2:
		_drag_to(camera, _last_pointer, _finger)
	if _glove.visible:
		_glove.pose(camera)

func set_filed(filed: bool) -> void:
	_accepted = filed
	_refresh(true)

func _update_lead() -> void:
	var socket:=METER+Vector3(-.25,-.33,-.020)
	var tail:=_probe.transform*Vector3(-.015,-.022,.234)
	var old:=tail
	for i in CABLE_SEGMENTS:
		var t:=float(i+1)/CABLE_SEGMENTS
		var next:=tail.lerp(socket,t)+Vector3(-sin(t*PI)*.079,-sin(t*PI)*.274,sin(t*PI)*.125)
		_lead.set_instance_transform(i,_shaft_frame(old,next,.016))
		old=next

func _emit_hint(words:String="") -> void:
	_feedback=words
	hint_changed.emit(instruction(_touch))

func _plane_point(camera:Camera3D, screen:Vector2, depth:float) -> Vector3:
	var start:=to_local(camera.project_ray_origin(screen))
	var dir:=global_transform.basis.inverse()*camera.project_ray_normal(screen)
	if absf(dir.z)<.003 or (depth-start.z)/dir.z<0:
		return Vector3.INF
	return start+dir*((depth-start.z)/dir.z)

func _within(point:Vector3,centre:Vector3,half:Vector2) -> bool:
	return absf(point.x-centre.x)<=half.x and absf(point.y-centre.y)<=half.y

func handle_input(event:InputEvent,camera:Camera3D) -> bool:
	if not _working or _accepted:
		return false
	if event is InputEventScreenTouch:
		if event.pressed:
			if _finger == -2:
				_last_pointer = event.position
			return _press_at(camera,event.position,event.index)
		return _release_at(camera,event.position,event.index)
	if event is InputEventScreenDrag:
		if _finger == event.index:
			_last_pointer = event.position
		return _drag_to(camera,event.position,event.index)
	if event.device==InputEvent.DEVICE_ID_EMULATION:
		return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			_last_pointer = event.position
			return _press_at(camera,event.position,-1)
		return _release_at(camera,event.position,-1)
	if event is InputEventMouseMotion and _finger==-1:
		_last_pointer = event.position
		return _drag_to(camera,event.position,-1)
	return false
