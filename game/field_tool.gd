extends Node3D
## Every pick intersects the front of a physical component in the station's local space.

signal adjusted(values: Array)
signal submitted(success: bool, detail: String)
signal hint_changed(text: String)

const FONT := preload("res://ui/fonts/CourierPrime-Regular.ttf")
const STEEL := preload("res://art/jacket.webp")
const ENAMEL := preload("res://art/enamel.webp")
const GLASS := preload("res://game/scope_glass.gdshader")
const FINISH := preload("res://game/tool_finish.gdshader")
const ANCHORS := [Vector3(-4,0,-5.615), Vector3(7,-2,-9.52)]
const METER := Vector3(.72,-.045,.21)
const GLASS_WIDTH := .56
const GLASS_HEIGHT := .27
const GLASS_C := METER + Vector3(0,.087,.098)
const DIAL := METER + Vector3(-.145,-.189,.142)
const STAMP := METER + Vector3(.196,-.191,.134)
const PROBE_REST := Vector3(-.37,-.12,.31)
const BAR_Z := .19
const SHOE_X := .51
const DETENT := .070
const CABLE_SEGMENTS := 12
var _job := -1
var _watch := 1
var _settings := [3,0]
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
var _probe_goal := PROBE_REST
var _dial: Node3D
var _stamp: Node3D
var _lead: MultiMesh
var _carrier: Node3D
var _shoes: Array[Node3D] = []
var _marks: Array[Node3D] = []
var _latch: Node3D
var _gripper: Node3D
var _forearm: MeshInstance3D
var _nuts: Array[Node3D] = []
var _drag := ""
var _finger := -2
var _press := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _start_detent := 0
var _grab_offset := 0.0
var _feedback := ""
var _stamp_travel := 0.0

func configure(job:int, watch:int, settings:Array) -> void:
	var changed := job != _job
	_job = job
	_watch = watch
	_settings = [3,0] if job == 0 else [1,7]
	for i in mini(settings.size(),2):
		if int(settings[i]) >= 0:
			var upper := 24 if job == 0 and i == 0 else (1 if job == 0 else 8)
			_settings[i] = clampi(int(settings[i]),0,upper)
	position = ANCHORS[job]
	if changed:
		_build()
	_feedback = ""
	_accepted = false
	_refresh(true)

func set_working(active:bool) -> void:
	_working = active
	_drag = ""
	_finger = -2
	_feedback = ""
	_refresh(true)

func stance() -> Vector3:
	return to_global(Vector3(.27,.06,1.42) if _job == 0 else Vector3(.03,.075,1.52))

func focus_point() -> Vector3:
	return to_global(Vector3(.28,-.05,.04) if _job == 0 else Vector3(0,0,.03))

func instruction(touch:bool) -> String:
	_touch = touch
	if not _feedback.is_empty():
		return _feedback
	if _job == 0:
		if _settings[1] == 0:
			return "Plant the probe on the bare round patch." if touch else "Click the bare steel or press Space to plant the probe."
		return "Slide the gate to the first tall return after zero. Press MARK." if touch else "Set the gate on the first return after zero. Click MARK or press Enter."
	return "Drag each nut until its white nick meets the brass cut. Throw the red latch." if touch else "Drag both nuts to their brass cuts. Click the latch or press Enter."

func _target(side := 0) -> int:
	if _job == 0:
		return 9 + posmod(_watch*3+1,4)
	return 3+posmod(_watch*2+1,4) if side == 0 else 2+posmod(_watch*3+2,4)

func _shoe_local(side:int, step:int) -> Vector3:
	return Vector3(-SHOE_X if side==0 else SHOE_X,(4-step)*DETENT,BAR_Z+.09)

func shoe_point(side:int, step:int) -> Vector3:
	return to_global(_shoe_local(side,step))

func gate_point(step:int) -> Vector3:
	return to_global(GLASS_C+Vector3((float(step)/24.0-.5)*GLASS_WIDTH,0,0))

func control_point(id:String) -> Vector3:
	match id:
		"probe": return to_global(_probe.position)
		"pad": return global_position
		"gate": return gate_point(_settings[0])
		"dial": return to_global(DIAL)
		"stamp": return to_global(STAMP)
		"left": return shoe_point(0,_settings[0])
		"right": return shoe_point(1,_settings[1])
		"latch": return to_global(_latch.position+Vector3(0,-.045,.105))
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
	_shoes.clear()
	_marks.clear()
	_nuts.clear()
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
	if _job == 0:
		_survey()
	else:
		_clamp()
	_make_forearm()
	_flush()

func _surface(key:String, tint:String, tex:Texture2D = null) -> void:
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
	# The meter's enamel still carries a soft reflection between chips.
	skin.roughness = .52 if tex == ENAMEL else .88
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

func _survey() -> void:
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
	_label(mount,"UT   0–24 mm",Vector3(-.06,.277,.080),.043,Color("#514531"),.012)
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
	_label(mount,"GATE",Vector3(-.18,-.307,.082),.040,Color("#33362e"),-.035)
	_stamp=_pivot(mount,STAMP-METER)
	_face_disc(mount,STAMP-METER-Vector3.BACK*.023,.075,.044,"iron")
	_face_disc(_stamp,Vector3.ZERO,.061,.074,"red",12)
	_box(_stamp,Vector3(0,0,.039),Vector3(.061,.009,.006),"white")
	_label(mount,"MARK",Vector3(.176,-.300,.084),.041,Color("#302e27"),.02)
	_box(mount,Vector3(.03,-.178,.074),Vector3(.157,.082,.016),"rubber")
	_reading=_label(mount,"03",Vector3(.03,-.176,.086),.073,Color("#cec9ac"))
	# A blunt prehensile glove grips the insulated barrel. Its brass nose moves onto bare steel.
	_probe=_pivot(_content,PROBE_REST)
	_face_disc(_probe,Vector3(0,0,.047),.060,.092,"steel",12)
	_face_disc(_probe,Vector3(0,0,.127),.070,.095,"ochre",12)
	_face_disc(_probe,Vector3(0,0,.203),.052,.075,"rubber",10)
	_gloved_hand(_probe)
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

func _gloved_hand(parent:Node3D) -> void:
	# Segmented neoprene gauntlet: the turned thumb and three bent fingers wrap the probe.
	_rod(parent,Vector3(-.30,-.30,.29),Vector3(-.145,-.135,.218),.100,"sleeve",10)
	_rod(parent,Vector3(-.162,-.151,.226),Vector3(-.12,-.106,.207),.088,"boot",10)
	_round(parent,Vector3(-.089,-.073,.175),Vector3(.196,.157,.136),"glove")
	for i in 3:
		var y := -.060+float(i)*.036
		_rod(parent,Vector3(-.085,y,.167),Vector3(.033,y-.012,.167),.023,"glove",8)
		_round(parent,Vector3(.034,y-.014,.15),Vector3(.046,.045,.063),"boot")
	_rod(parent,Vector3(-.093,.028,.16),Vector3(-.024,.058,.116),.028,"glove",8)
	_round(parent,Vector3(-.017,.059,.112),Vector3(.067,.047,.057),"boot")

func _clamp() -> void:
	# These are two independent jack screws on an open carrier, with a shim and pin at each end.
	for side in 2:
		var x := -SHOE_X if side == 0 else SHOE_X
		_box(_content,Vector3(x,0,-.025),Vector3(.30,.84,.105),"iron")
		_rod(_content,Vector3(x,-.39,.095),Vector3(x,.39,.095),.038,"steel")
		for k in 26:
			var y := -.36 + k*.028
			_box(_content,Vector3(x,y,.120),Vector3(.080,.014,.021),"iron",.18)
		for y in [-.383,.383]:
			_box(_content,Vector3(x,y,.073),Vector3(.196,.075,.152),"ochre")
		var mark:=_pivot(_content,Vector3.ZERO)
		_marks.append(mark)
		# Brass wedges stay with the bracket. The shoe's pale cut moves against them.
		for sign_x in [-1.,1.]:
			_box(mark,Vector3(sign_x*.17,0,.052),Vector3(.119,.024,.020),"brass")
			_box(mark,Vector3(sign_x*.221,.018,.049),Vector3(.020,.057,.015),"brass",sign_x*.18)
		var shoe:=_pivot(_content,Vector3.ZERO)
		_shoes.append(shoe)
		_box(shoe,Vector3(0,0,-.090),Vector3(.224,.141,.137),"iron")
		var nut:=_pivot(shoe,Vector3.ZERO)
		_nuts.append(nut)
		_face_disc(nut,Vector3(0,0,-.011),.098,.064,"brass",6)
		_face_disc(nut,Vector3(0,0,.020),.058,.057,"steel",6)
		_face_disc(nut,Vector3(0,0,.050),.029,.005,"rubber",6)
		_box(nut,Vector3(.039,.049,.023),Vector3(.032,.011,.006),"scratch",.63)
		for sign_x in [-1.,1.]:
			_box(shoe,Vector3(sign_x*.085,0,.027),Vector3(.063,.017,.012),"white")
	_carrier=_pivot(_content,Vector3.ZERO)
	_box(_carrier,Vector3.ZERO,Vector3(2*SHOE_X,.107,.114),"ochre")
	_box(_carrier,Vector3(0,-.026,.065),Vector3(.77,.023,.022),"iron")
	_scrapes(_carrier,Vector3(0,.023,.058),.43,.027,955)
	_latch=_pivot(_content,Vector3(0,0,BAR_Z+.118))
	_face_disc(_latch,Vector3.ZERO,.090,.068,"iron",10)
	_face_disc(_latch,Vector3(0,0,.04),.042,.042,"steel",6)
	_rod(_latch,Vector3(0,.009,.058),Vector3(.005,-.133,.092),.029,"red",8)
	_rod(_latch,Vector3(.005,-.133,.092),Vector3(.006,-.196,.103),.044,"red",10)
	_gripper=_pivot(_content,Vector3.ZERO)
	_gripper.rotation.z=-.56
	_gloved_hand(_gripper)
	_gripper.visible=false

func _make_forearm() -> void:
	var sleeve:=CylinderMesh.new()
	sleeve.top_radius=.092
	sleeve.bottom_radius=.143
	sleeve.height=1
	sleeve.radial_segments=11
	sleeve.rings=0
	_forearm=MeshInstance3D.new()
	_forearm.mesh=sleeve
	_forearm.material_override=_surfaces["sleeve"]
	_forearm.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_content.add_child(_forearm)

func _pose_arm(hand:Node3D) -> void:
	var wrist:=hand.position+hand.basis*Vector3(-.18,-.16,.23)
	var elbow:=Vector3(-.59,-.72,.86)
	var delta:=wrist-elbow
	_forearm.transform=Transform3D(Basis(Quaternion(Vector3.UP,delta.normalized())).scaled_local(Vector3(1.,delta.length(),1.)),(elbow+wrist)*.5)

func set_filed(filed:bool) -> void:
	_accepted=filed
	if filed and _job==1:
		_settings=[_target(),_target(1)]
	_refresh(true)

func _refresh(instant := false) -> void:
	if _content == null:
		return
	if _job == 0:
		_glass.set_shader_parameter("gate",float(_settings[0]))
		_glass.set_shader_parameter("wall",float(_target()))
		_glass.set_shader_parameter("contact",_working and _settings[1]==1)
		_reading.text="%02d" % _settings[0]
		_dial.rotation.z=-float(_settings[0])/24.*TAU*.83
		_probe_goal=Vector3.ZERO if _settings[1] == 1 else PROBE_REST
		# Only the diver carries the probe; in free swim its clip follows the meter.
		if not _working:
			_probe_goal=METER+Vector3(-.39,-.135,.005)
		_probe.visible=_working
		_forearm.visible=_working
		_lead.visible_instance_count=CABLE_SEGMENTS if _working else 0
		if instant:
			_probe.position=_probe_goal
			_update_lead()
			_pose_arm(_probe)
	else:
		for side in 2:
			_marks[side].position=_shoe_local(side,_target(side))-Vector3.BACK*.028
			_nuts[side].rotation.z=float(_settings[side])*.82
			_shoes[side].position=_shoe_local(side,_settings[side])
		var left:=_shoes[0].position
		var right:=_shoes[1].position
		_carrier.position=(left+right)*.5-Vector3.BACK*.10
		var v:=right-left
		_carrier.rotation.z=atan2(v.y,v.x)
		_carrier.scale.x=v.length()/(2*SHOE_X)
		_latch.position=_carrier.position+Vector3.BACK*.115
		_latch.rotation.z=-.14 if _accepted else -.98
		_gripper.visible=_working and _drag in ["left","right"]
		_forearm.visible=_gripper.visible
		if _gripper.visible:
			_gripper.position=_shoes[0 if _drag=="left" else 1].position+Vector3(-.025,-.03,.0)
			_pose_arm(_gripper)

func _update_lead() -> void:
	var socket:=METER+Vector3(-.25,-.33,-.020)
	var tail:=_probe.position+Vector3(-.015,-.022,.234)
	var old:=tail
	for i in CABLE_SEGMENTS:
		var t:=float(i+1)/CABLE_SEGMENTS
		var next:=tail.lerp(socket,t)+Vector3(-sin(t*PI)*.079,-sin(t*PI)*.274,sin(t*PI)*.125)
		_lead.set_instance_transform(i,_shaft_frame(old,next,.016))
		old=next

func _process(delta:float) -> void:
	if _job==0 and _working:
		if not _probe.position.is_equal_approx(_probe_goal):
			_probe.position=_probe.position.move_toward(_probe_goal,delta*2.4)
			_update_lead()
			_pose_arm(_probe)
		if _stamp_travel>0.0:
			_stamp_travel=maxf(0.,_stamp_travel-delta*4.5)
			_stamp.position.z=STAMP.z-METER.z-.041*minf(1.,_stamp_travel*2.)

func _emit_hint(words:String="") -> void:
	_feedback=words
	hint_changed.emit(instruction(_touch))

func _set_value(side:int, value:int) -> void:
	var clipped:=clampi(value,0,24 if _job==0 and side==0 else (1 if _job==0 else 8))
	if _settings[side]==clipped:
		return
	_settings[side]=clipped
	_refresh()
	adjusted.emit(_settings.duplicate())
	_emit_hint()

func _submit() -> void:
	var ok:=false
	var words:=""
	if _job==0:
		_stamp_travel=1.0
		if _settings[1]!=1:
			words="No contact. Bring the probe nose onto the bare patch."
		elif _settings[0]==_target():
			ok=true
			words="A2  /  %d.0 mm. Back-wall return recorded." % _settings[0]
		elif _settings[0]>=_target()*2-1:
			words="That's the second reflection. Bring the gate back to the first."
		else:
			words="Move the amber line onto the first tall reflection after zero."
	else:
		ok=_settings[0]==_target() and _settings[1]==_target(1)
		if ok:
			words="B4  /  Both shoes are flush. Carrier seated."
		else:
			var side:=0 if _settings[0]!=_target() else 1
			words="The %s shoe is %s its brass cut." % [
				"left" if side==0 else "right",
				"above" if _settings[side]<_target(side) else "below"]
	_accepted=ok
	_refresh()
	_emit_hint(words)
	submitted.emit(ok,words)

func _plane_point(camera:Camera3D, screen:Vector2, depth:float) -> Vector3:
	var start:=to_local(camera.project_ray_origin(screen))
	var dir:=global_transform.basis.inverse()*camera.project_ray_normal(screen)
	if absf(dir.z)<.003 or (depth-start.z)/dir.z<0:
		return Vector3.INF
	return start+dir*((depth-start.z)/dir.z)

func _within(point:Vector3,centre:Vector3,half:Vector2) -> bool:
	return absf(point.x-centre.x)<=half.x and absf(point.y-centre.y)<=half.y

func _pick(camera:Camera3D, screen:Vector2) -> String:
	if _job==0:
		var panel:=_plane_point(camera,screen,GLASS_C.z)
		if _within(panel,GLASS_C,Vector2(GLASS_WIDTH*.5+.02,GLASS_HEIGHT*.5+.015)):
			return "gate"
		if _within(_plane_point(camera,screen,STAMP.z),STAMP,Vector2(.115,.11)):
			return "stamp"
		if _within(_plane_point(camera,screen,DIAL.z),DIAL,Vector2(.11,.12)):
			return "dial"
		var patch:=_plane_point(camera,screen,0.0)
		if Vector2(patch.x,patch.y).length()<=.213:
			return "pad"
		if _within(_plane_point(camera,screen,_probe.position.z+.13),_probe.position,Vector2(.20,.20)):
			return "probe"
	else:
		for side in 2:
			var foot:=_shoes[side].position
			if _within(_plane_point(camera,screen,foot.z),foot,Vector2(.19,.145)):
				return "left" if side==0 else "right"
		var latch:=_plane_point(camera,screen,_latch.position.z+.08)
		if _within(latch,_latch.position+Vector3(-.036,-.04,0),Vector2(.16,.16)):
			return "latch"
	return ""

func _gate_under(camera:Camera3D, screen:Vector2) -> void:
	var place:=_plane_point(camera,screen,GLASS_C.z)
	if place.is_finite():
		_set_value(0,roundi((.5+(place.x-GLASS_C.x)/GLASS_WIDTH)*24.0))

func _press_at(camera:Camera3D, at:Vector2, finger:int) -> bool:
	if _finger!=-2:
		return false
	var part:=_pick(camera,at)
	if part.is_empty():
		return false
	_finger=finger
	_drag=part
	_press=at
	_last_pointer=at
	if part=="gate":
		_gate_under(camera,at)
	elif part=="dial":
		_start_detent=_settings[0]
	elif part in ["left","right"]:
		var side:=0 if part=="left" else 1
		var foot:=_shoes[side].position
		_grab_offset=_plane_point(camera,at,foot.z).y-foot.y
		_refresh()
	return true

func _drag_to(camera:Camera3D, at:Vector2, finger:int) -> bool:
	if finger!=_finger:
		return false
	_last_pointer=at
	match _drag:
		"gate": _gate_under(camera,at)
		"dial":
			var a:=_plane_point(camera,_press,DIAL.z)
			var b:=_plane_point(camera,at,DIAL.z)
			if b.is_finite():
				_set_value(0,_start_detent+roundi((b.x-a.x+b.y-a.y)/.036))
		"probe","pad":
			var point:=_plane_point(camera,at,0.)
			if point.is_finite() and at.distance_to(_press)>4:
				_set_value(1,0)
				_probe_goal=Vector3(clampf(point.x,-.55,.32),clampf(point.y,-.30,.34),.07)
		"left","right":
			var side:=0 if _drag=="left" else 1
			var point:=_plane_point(camera,at,_shoes[side].position.z)
			if point.is_finite():
				_set_value(side,4-roundi((point.y-_grab_offset)/DETENT))
	return true

func _release_at(camera:Camera3D, at:Vector2, finger:int) -> bool:
	if finger!=_finger:
		return false
	var part:=_drag
	if at.distance_to(_last_pointer)>1.0:
		_drag_to(camera,at,finger)
	_drag=""
	_finger=-2
	match part:
		"pad","probe":
			var point:=_plane_point(camera,at,0.)
			if Vector2(point.x,point.y).length()<=.213:
				_set_value(1,1)
			else:
				_set_value(1,0)
				_emit_hint("The coating gives no trace. Land the probe on the bright metal.")
			_refresh()
		"stamp","latch":
			if _pick(camera,at)==part:
				_submit()
		"left","right":
			_refresh()
	return true

func handle_input(event:InputEvent,camera:Camera3D) -> bool:
	if not _working or _accepted:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if _job==0:
					_set_value(1,1)
				else:
					_submit()
			KEY_ENTER,KEY_KP_ENTER: _submit()
			KEY_LEFT,KEY_A: _set_value(0,_settings[0]-1)
			KEY_RIGHT,KEY_D: _set_value(0,_settings[0]+1)
			KEY_UP,KEY_J:
				if _job==1:
					_set_value(1,_settings[1]-1)
			KEY_DOWN,KEY_L:
				if _job==1:
					_set_value(1,_settings[1]+1)
			_: return false
		return true
	if event is InputEventScreenTouch:
		if event.pressed:
			return _press_at(camera,event.position,event.index)
		return _release_at(camera,event.position,event.index)
	if event is InputEventScreenDrag:
		return _drag_to(camera,event.position,event.index)
	if event.device==InputEvent.DEVICE_ID_EMULATION:
		return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			return _press_at(camera,event.position,-1)
		return _release_at(camera,event.position,-1)
	if event is InputEventMouseMotion and _finger==-1:
		return _drag_to(camera,event.position,-1)
	return false
