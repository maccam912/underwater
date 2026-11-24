extends "res://game/field_tool.gd"
## A prehung split guide on a small service line. The back saddle stays on the riser.
signal station_changed(detail: String)

enum Phase { BRUSH, FIT, START, TIGHTEN, INSPECT, COMPLETE }

const LEVELS := [-2.0, 1.35, 4.85, -5.70]
const BOLTS := [Vector2(-.405,.235), Vector2(.405,-.235), Vector2(.405,.235), Vector2(-.405,-.235)]
const FACE := .205
const ARM := .285
const SWEEP := 1.27
const BRUSH_X := .385
const BLADE_REST := Vector3(-.08,-.315,.29)
const WRENCH_REST := Vector3(-.13,-.335,.29)
const EDGE := .5
const GAUGE_Z := .139
const TAPER_START := .8
const TAPER_SLOPE := 53.
const FORMAT := "service-guide-2"

var station := 0
var phase := Phase.BRUSH
var _wear := [0.,0.,0.,0.,0.,0.]
var _shell_offset := Vector2.ZERO
var _shell_roll := 0.0
var _threads := [0.,0.,0.,0.]
var _draw := [0.,0.,0.,0.]
var _clearances := [-1.,-1.,-1.,-1.]
var _records: Array[Dictionary] = []
var _approach := -1
var _reading_bolt := -1
var _gauge_side := 1.
var _bolt := -1
var _socket := -1
var _angle := 0.0
var _angle_goal := 0.0
var _last_local := Vector3.ZERO
var _grab_xy := Vector2.ZERO
var _turn_ref := Vector2.ZERO
var _bias := 0.0
var _dirty := false
var _tool_rest := WRENCH_REST
var _stations: Array[Node3D] = []
var _installed: Array[Node3D] = []
var _growth: Array[Node3D] = []
var _caps: Array[Node3D] = []
var _line: Node3D
var _sling: MeshInstance3D
var _brush: Node3D
var _wrench: Node3D
var _blade: Node3D
var _plate: Label3D
var _click: AudioStreamPlayer3D

func configure(job: int, watch: int, settings: Array) -> void:
	_job = job
	_watch = watch
	station = 0
	_records.clear()
	_reset_guide()
	if settings.size()==14 and settings[0] is String and settings[0]==FORMAT:
		_restore(settings)
	elif settings.size()>=13 and settings[2] is int and settings[3] is int:
		_restore_old_carrier(settings)
	position = _anchor()
	if _content == null:
		_build()
	_accepted = false
	_feedback = ""
	_refresh(true)

func _reset_guide() -> void:
	phase = Phase.BRUSH
	_wear.fill(0.)
	_threads.fill(0.)
	_draw.fill(0.)
	_clearances.fill(-1.)
	_approach = -1
	_reading_bolt = -1
	var direction := -1.0 if (_watch+station)%2 else 1.0
	_shell_offset = Vector2(direction*(.19+.028*(station%2)),.135+.024*(station%3))
	_shell_roll = direction*(.24+.055*posmod(_watch+station,4))
	_bolt = -1
	_socket = -1
	_angle = 0.0
	_angle_goal = 0.0
	_tool_rest = WRENCH_REST
	_dirty = false

func snapshot() -> Array:
	return [FORMAT,station,phase,_wear.duplicate(),_shell_offset,_shell_roll,_threads.duplicate(),
		_draw.duplicate(),_clearances.duplicate(),_socket,_angle,_tool_rest,_watch,_records.duplicate(true)]

func _restore(record: Array) -> void:
	for pair in [[3,6],[6,4],[7,4],[8,4]]:
		if not record[pair[0]] is Array or record[pair[0]].size()!=pair[1]:
			return
		for value in record[pair[0]]:
			if not (value is float or value is int) or not is_finite(float(value)):
				return
	if not record[1] is int or not record[2] is int or not record[4] is Vector2 or not record[4].is_finite():
		return
	if not record[11] is Vector3 or not record[11].is_finite():
		return
	for index in [5,9,10]:
		if not (record[index] is float or record[index] is int) or not is_finite(float(record[index])):
			return
	station = clampi(record[1],0,3)
	phase = clampi(record[2],0,Phase.COMPLETE) as Phase
	for i in 6:
		_wear[i] = clampf(record[3][i],0.,_scale_thickness(i))
	_shell_offset = record[4].clamp(Vector2(-.5,-.32),Vector2(.5,.32))
	_shell_roll = clampf(record[5],-.68,.68)
	for i in 4:
		_threads[i] = clampf(record[6][i],0.,_thread_turn(i))
		_draw[i] = clampf(record[7][i],0.,_draw_turn(i))
	for i in 4:
		_clearances[i] = clampf(record[8][i],-1.,12.)
	if record[13] is Array:
		for row in record[13]:
			if row is Dictionary and row.get("location","") is String:
				_records.append(row.duplicate(true))
	_socket = clampi(record[9],-1,3)
	_angle = clampf(record[10],0.,SWEEP)
	_angle_goal = _angle
	_tool_rest = record[11]

func _restore_old_carrier(record: Array) -> void:
	station = clampi(record[2],0,3)
	_reset_guide()
	var old_phase := clampi(record[3],0,4)
	for i in 6:
		if record[7+i] is float or record[7+i] is int:
			_wear[i] = clampf(record[7+i],0.,_scale_thickness(i))
	if old_phase == 0:
		return
	for i in 6:
		_wear[i] = _scale_thickness(i)
	phase = Phase.FIT
	if old_phase < 2:
		return
	_shell_offset = Vector2.ZERO
	_shell_roll = 0.
	phase = Phase.TIGHTEN
	for i in 4:
		_threads[i] = _thread_turn(i)
	if record[4] is int:
		for turn in clampi(record[4],0,7):
			var i := (turn + (2 if (_watch+station)%2==0 else 0))%4
			_draw[i] = _draw_turn(i)*(.50 if turn<4 else 1.)
	if old_phase >= 3:
		for i in 4:
			_draw[i] = _draw_turn(i)
		phase = Phase.INSPECT if old_phase==3 else Phase.COMPLETE

func _checkpoint() -> void:
	_dirty = false
	adjusted.emit(snapshot())

func _anchor() -> Vector3:
	return Vector3(7.0,LEVELS[station],ANCHORS[1].z)

func swim_target() -> Vector3:
	return global_position + Vector3.BACK*1.52

func station_name() -> String:
	return "B4-%d" % (station+1)

func _scale_thickness(i: int) -> float:
	return .15*(5+posmod(31*_watch+i*5+station*7,5+i%2))

func _patch(i: int) -> Vector3:
	return Vector3(-BRUSH_X if i<3 else BRUSH_X,(1-i%3)*.235,.135)

func _thread_turn(i: int) -> float:
	return TAU*(1.0+.125*posmod(station+i+_watch,3))

func _draw_turn(i: int) -> float:
	return SWEEP*(4.25+.32*posmod(station*3+i+_watch,3))

func _fraction(i: int) -> float:
	return float(_draw[i])/_draw_turn(i)

func _min_draw() -> float:
	var least := 1.0
	for i in 4:
		least = minf(least,_fraction(i))
	return least

func _shell_z() -> float:
	var mean := 0.0
	for i in 4:
		mean += _fraction(i)*.25
	return FACE + (.105 if phase==Phase.FIT else .047*(1.-mean))

func _bolt_pos(i: int) -> Vector3:
	return to_local(_caps[i].global_position)

func _arm_dir(i: int, angle: float) -> Vector2:
	var base := 0.0 if BOLTS[i].x<0. else PI
	var slope := -.16 if BOLTS[i].y*BOLTS[i].x<0. else .16
	return Vector2.from_angle(base+slope+SWEEP*.5-angle)

func _grip_point(angle: float) -> Vector3:
	var idx := maxi(0,_socket)
	var dir := _arm_dir(idx,angle)
	return _bolt_pos(idx)+Vector3(dir.x*ARM,dir.y*ARM,.067)

func control_point(id: String) -> Vector3:
	match id:
		"shell": return _carrier.to_global(Vector3(0,0,.14))
		"seat": return to_global(Vector3(0,0,_shell_z()+.14))
		"ear": return _carrier.to_global(Vector3(.32,0,.04))
		"square": return to_global(Vector3(_shell_offset.x+.32,_shell_offset.y,_shell_z()+.04))
		"wrench": return _wrench.global_position
		"handle": return to_global(_grip_point(_angle))
		"drive": return to_global(_grip_point(SWEEP))
		"return": return to_global(_grip_point(0.))
		"blade": return _blade.global_position
	if id.begins_with("patch"):
		return to_global(_patch(clampi(id.trim_prefix("patch").to_int(),0,5)))
	if id.begins_with("bolt"):
		return to_global(_bolt_pos(clampi(id.trim_prefix("bolt").to_int(),0,3)))
	return global_position

func inspection_record() -> Array[Dictionary]:
	return _records.duplicate(true)

func _gap_at(i: int) -> float:
	var sign_x := signf(BOLTS[i].x)
	var inner_face := _carrier.to_global(Vector3(sign_x*EDGE,BOLTS[i].y,-.064))
	return snappedf(1000.*(to_local(inner_face).z-_rear_face(station,sign_x)),.1)

func _rear_face(s: int, sign_x: float) -> float:
	# As-machined land depth on the fixed half, in metres.
	return .137 + .0001*(posmod(s*2+(1 if sign_x>0. else 0),4)-1)

func instruction(touch: bool) -> String:
	_touch = touch
	if not _feedback.is_empty():
		return _feedback
	var lead := station_name()+"  ·  "
	match phase:
		Phase.BRUSH: return lead+"Wire-brush shells and scale from both saddle faces."
		Phase.FIT: return lead+"Move the shell by its lifting handle. Turn a side lug until the four holes line up."
		Phase.START: return lead+"Finger-start all four captive screws. Turn each hex head clockwise."
		Phase.TIGHTEN:
			if _socket<0:
				return lead+"Seat the preset wrench on a head. Draw the shell down evenly, alternating corners."
			return lead+"Pull clockwise, then swing back to ratchet. Lift the socket head to change bolts."
		Phase.INSPECT: return lead+"Slide the taper gauge in from the outside beside each screw. Read it where the blade stops."
	return "B4  /  All four service-line guides inspected."

func set_filed(filed: bool) -> void:
	_accepted = filed
	if filed:
		station = LEVELS.size()-1
		phase = Phase.COMPLETE
		_shell_offset = Vector2.ZERO
		_shell_roll = 0.
		for i in 4:
			_draw[i] = _draw_turn(i)
			_threads[i] = _thread_turn(i)
		position = _anchor()
	_refresh(true)

func set_working(active: bool) -> void:
	if _dirty:
		_checkpoint()
	_angle_goal = _angle
	super.set_working(active)

func _body(parent: Node3D, back: bool) -> void:
	# Contoured liner and two steel bands bridge the pipe. The ears form a mating flange.
	for sign_y in [-1.,1.]:
		var y: float = sign_y*.235
		for s in 8:
			var a := PI*float(s)/8.
			var b := PI*float(s+1)/8.
			var dir := -1.0 if back else 1.0
			var aa := Vector3(.142*cos(a),y,.142*sin(a)*dir-.172)
			var bb := Vector3(.142*cos(b),y,.142*sin(b)*dir-.172)
			_rod(parent,aa,bb,.046,"rubber",8)
			_rod(parent,aa+Vector3(0,0,.040*dir),bb+Vector3(0,0,.040*dir),.044,"ochre" if not back else "iron",8)
		for sign_x in [-1.,1.]:
			var x: float = sign_x
			_rod(parent,Vector3(x*.15,y,-.166),Vector3(x*.31,y,-.047),.046,"ochre" if not back else "iron",8)
			_box(parent,Vector3(x*.372,y,-.032),Vector3(.268,.132,.072),"ochre" if not back else "iron")
	for sign_x in [-1.,1.]:
		var x: float = sign_x*.465
		_box(parent,Vector3(x,0,-.031),Vector3(.075,.615,.066),"ochre" if not back else "iron")
	if not back:
		# Raised lifting handle is accessible even with the front shell canted on its sling.
		for sy in [-.185,.185]:
			_rod(parent,Vector3(0,sy,.02),Vector3(0,sy,.135),.031,"steel")
		_rod(parent,Vector3(0,-.185,.135),Vector3(0,.185,.135),.042,"ochre")
		for side in [-1.,1.]:
			_rod(parent,Vector3(side*.39,0,-.03),Vector3(side*.30,0,.039),.040,"steel",8)
			_box(parent,Vector3(side*.335,0,.052),Vector3(.080,.020,.010),"white")

func _build_equipment() -> void:
	_line = _pivot(_content,Vector3.ZERO)
	_rod(_line,Vector3(0,-7,.024),Vector3(0,7,.024),.123,"boot",18)
	for s in LEVELS.size():
		var mount := _pivot(_content,Vector3.ZERO)
		_stations.append(mount)
		for y in [-.235,.235]:
			_rod(mount,Vector3(0,y-.055,-1.1),Vector3(0,y+.055,-1.1),.77,"iron",16)
			_box(mount,Vector3(0,y,-.35),Vector3(.99,.105,.63),"iron")
		var rear := _pivot(mount,Vector3(0,0,.126))
		_body(rear,true)
		# The two saddle pads carry threaded inserts and witness lines at their shoulders.
		for side in [-1.,1.]:
			_box(mount,Vector3(side*BRUSH_X,0,.103),Vector3(.245,.64,.060),"iron")
			_box(mount,Vector3(side*EDGE,0,_rear_face(s,side)-.0225),Vector3(.037,.64,.045),"steel")
			for sy in [-.295,.295]:
				_box(mount,Vector3(side*EDGE,sy,.139),Vector3(.100,.017,.007),"white")
		for xy: Vector2 in BOLTS:
			_face_disc(mount,Vector3(xy.x,xy.y,.135),.073,.018,"steel",12)
			_face_disc(mount,Vector3(xy.x,xy.y,.147),.044,.009,"rubber",10)
		_box(mount,Vector3(-.405,.475,.11),Vector3(.54,.118,.064),"rubber")
		_label(mount,"B4 / %02d" % (s+1),Vector3(-.405,.475,.15),.067,Color("#e7d8bb"))
		_rod(mount,Vector3(.23,.46,-.07),Vector3(.23,.56,.18),.025,"steel",8)
		_face_disc(mount,Vector3(.23,.56,.186),.035,.026,"brass",10)
		var installed := _pivot(mount,Vector3(0,0,FACE))
		_installed.append(installed)
		_body(installed,false)
		for xy: Vector2 in BOLTS:
			_face_disc(installed,Vector3(xy.x,xy.y,.029),.067,.037,"brass",6)
	_carrier = _pivot(_content,Vector3.ZERO)
	_body(_carrier,false)
	for xy: Vector2 in BOLTS:
		_face_disc(_carrier,Vector3(xy.x,xy.y,.008),.079,.021,"steel",16)
		var cap := _pivot(_carrier,Vector3(xy.x,xy.y,.06))
		_caps.append(cap)
		_face_disc(cap,Vector3(0,0,-.041),.041,.085,"steel",12)
		_face_disc(cap,Vector3.ZERO,.069,.040,"brass",6)
		_box(cap,Vector3(.025,0,.022),Vector3(.047,.012,.006),"white")
	_surface("limpet","aa9879")
	var shell := CylinderMesh.new()
	shell.height = 1.
	shell.bottom_radius = .5
	shell.top_radius = .17
	shell.radial_segments = 7
	shell.rings = 0
	_shapes["shell"] = shell
	for i in 6:
		var crust := _pivot(_content,_patch(i))
		_growth.append(crust)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4430+i
		for chip in 26:
			var loc := Vector3(rng.randf_range(-.1,.1),rng.randf_range(-.085,.085),rng.randf_range(0,.023))
			var size := rng.randf_range(.032,.073)
			var normal := Vector3(rng.randf_range(-.24,.24),rng.randf_range(-.28,.28),1).normalized()
			var basis := Basis(Quaternion(Vector3.UP,normal)).scaled_local(Vector3(size,size*.40,size*.8))
			_part(crust,"shell","limpet" if chip%3 else "iron",basis,loc)
			_face_disc(crust,loc+normal*size*.203,size*.107,.002,"rubber",7)
	_brush = _pivot(_content,Vector3.ZERO)
	_box(_brush,Vector3(0,0,.022),Vector3(.16,.105,.043),"brass")
	for i in 6:
		_box(_brush,Vector3((i-2.5)*.025,0,0),Vector3(.013,.11,.032),"steel")
	_rod(_brush,Vector3(0,0,.065),Vector3(-.17,-.12,.115),.036,"ochre")
	_wrench = _pivot(_content,Vector3.ZERO)
	_face_disc(_wrench,Vector3.ZERO,.079,.095,"rubber",10)
	_face_disc(_wrench,Vector3(0,0,.049),.070,.055,"steel",12)
	_rod(_wrench,Vector3(0,0,.067),Vector3(ARM-.065,0,.067),.024,"steel",8)
	_rod(_wrench,Vector3(ARM-.101,0,.067),Vector3(ARM+.019,0,.067),.034,"red",10)
	_label(_wrench,"24",Vector3(.174,0,.094),.029,Color("#e5e0c7"))
	_blade = _pivot(_content,BLADE_REST)
	# The leading edge has the thinnest section. Each division reads directly in mm.
	for i in 14:
		var width := .009
		var x := (i+.5)*width
		var thick := (TAPER_START+TAPER_SLOPE*x)*.001
		_box(_blade,Vector3(x,0,0),Vector3(width,.041,thick),"steel")
	for value in range(2,8):
		var x := (value-TAPER_START)/TAPER_SLOPE
		_box(_blade,Vector3(x,.008,.0045),Vector3(.003,.024,.003),"rubber")
	_box(_blade,Vector3(.171,0,.012),Vector3(.099,.075,.031),"ochre")
	_label(_blade,"mm",Vector3(.17,0,.031),.031,Color("#453b31"))
	_plate = _label(_content,"",Vector3(0,-.468,.14),.045,Color("#e0d7b8"))
	_sling = MeshInstance3D.new()
	_sling.mesh = _primitive("8")
	_sling.material_override = _surfaces["rubber"]
	_content.add_child(_sling)
	_click = AudioStreamPlayer3D.new()
	_click.stream = _click_sound()
	_click.volume_db = -11
	_click.unit_size = 2.
	_content.add_child(_click)

func _click_sound() -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.mix_rate = 22050
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	var samples := PackedByteArray()
	samples.resize(2646)
	for i in samples.size()/2:
		var t := float(i)/sound.mix_rate
		var rebound := maxf(0.,t-.012)
		var vibration := sin(t*TAU*740.)*exp(-t*230.) + .38*sin(rebound*TAU*420.)*exp(-rebound*175.)
		samples.encode_s16(i*2,roundi(vibration*21000.))
	sound.data = samples
	return sound

func _refresh(_instant := false) -> void:
	if _plate==null:
		return
	_line.position.y = -float(LEVELS[station])
	for i in LEVELS.size():
		_stations[i].position.y = float(LEVELS[i])-float(LEVELS[station])
		_installed[i].visible = i<station
	for i in 6:
		var remaining := clampf(1.-float(_wear[i])/_scale_thickness(i),0.,1.)
		_growth[i].visible = phase==Phase.BRUSH and remaining>.002
		_growth[i].scale = Vector3(.38+.62*remaining,.32+.68*remaining,maxf(.03,remaining))
	_carrier.visible = phase!=Phase.BRUSH
	_carrier.position = Vector3(_shell_offset.x,_shell_offset.y,_shell_z())
	var tilt_x := (_fraction(0)+_fraction(2)-_fraction(1)-_fraction(3))*.045
	var tilt_y := (_fraction(2)+_fraction(1)-_fraction(0)-_fraction(3))*.032
	_carrier.rotation = Vector3(tilt_x,tilt_y,_shell_roll)
	_sling.visible = phase in [Phase.FIT,Phase.START]
	if _sling.visible:
		_sling.transform = _shaft_frame(Vector3(.23,.56,.186),to_local(_carrier.to_global(Vector3(0,.185,.135))),.010)
	for i in 4:
		_caps[i].position.z = .03+.077*(1.-float(_threads[i])/_thread_turn(i))
		_caps[i].rotation.z = -.25*i-float(_threads[i])-float(_draw[i])
	_brush.visible = _working and phase==Phase.BRUSH
	_brush.position = _last_local if _drag=="brush" else Vector3(-.07,-.31,.225)
	_wrench.visible = phase==Phase.TIGHTEN
	_wrench.position = _bolt_pos(_socket) if _socket>=0 else (_last_local if _drag=="socket" else _tool_rest)
	_wrench.rotation.z = _arm_dir(_socket,_angle).angle() if _socket>=0 else -.17
	_blade.visible = phase==Phase.INSPECT
	_blade.position = _last_local if _drag=="blade" else BLADE_REST
	_blade.rotation.y = PI if _drag=="blade" and _gauge_side<0. else 0.
	_plate.text = "24 N·m PRESET    /    4 mm GAP"
	if not _working:
		_glove.stow()
		return
	match _drag:
		"brush":
			var handle := Vector3(-.17,-.12,.05)
			_hold_tool(_brush.transform*(Vector3(0,0,.065)+handle*.67),_brush.basis*(-handle.normalized()),.034)
		"move":
			_hold_tool(_carrier.transform*Vector3(0,0,.135),_carrier.basis.y,.042)
		"rotate":
			var side := signf(_carrier.to_local(to_global(_last_local)).x)
			_hold_tool(_carrier.transform*Vector3(side*.32,0,.039),_carrier.basis.y,.036)
		"thread":
			_hold_tool(_bolt_pos(_bolt)+Vector3.BACK*.027,Vector3.BACK,.045,-.38*sin(_threads[_bolt]))
		"socket","wrench":
			_hold_tool(_wrench.transform*Vector3(ARM-.046,0,.067),_wrench.basis.x,.034)
		"blade":
			_hold_tool(_blade.transform*Vector3(.171,0,.012),_blade.basis.x,.024)
		_: _glove.stow()

func _hit(camera: Camera3D, at: Vector2, point: Vector3, radius: Vector2) -> bool:
	return _within(_plane_point(camera,at,point.z),point,radius)

func _pick_work(camera: Camera3D, at: Vector2) -> String:
	match phase:
		Phase.BRUSH:
			var p := _plane_point(camera,at,_patch(0).z)
			if absf(absf(p.x)-BRUSH_X)<.215 and absf(p.y)<.405:
				_last_local = p
				return "brush"
			if _hit(camera,at,_brush.position,Vector2(.15,.12)):
				_last_local = _brush.position
				return "brush"
		Phase.FIT:
			var center := to_local(control_point("shell"))
			if _hit(camera,at,center,Vector2(.138,.218)):
				_last_local = _plane_point(camera,at,center.z)
				_grab_xy = _xy(_last_local)-_shell_offset
				return "move"
			var p := _plane_point(camera,at,_shell_z()+.04)
			if p.is_finite():
				var r := _xy(p)-_shell_offset
				var lug := r.rotated(-_shell_roll)
				if absf(lug.x)>.14 and absf(lug.x)<.56 and absf(lug.y)<.34:
					_last_local = p
					_bias = r.angle()-_shell_roll
					return "rotate"
		Phase.START:
			for i in 4:
				var center := _bolt_pos(i)
				if _threads[i]<_thread_turn(i) and _hit(camera,at,center,Vector2(.134,.132)):
					_bolt = i
					_last_local = _plane_point(camera,at,center.z)
					_turn_ref = _xy(_last_local-center)
					return "thread"
		Phase.TIGHTEN:
			var head := _wrench.position
			if _socket>=0 and _hit(camera,at,_grip_point(_angle),Vector2(.119,.115)):
				_last_local = _grip_point(_angle)
				return "wrench"
			var tip := head+_wrench.basis*Vector3(ARM,0,.067)
			if _hit(camera,at,head,Vector2(.124,.124)) or (_socket<0 and _hit(camera,at,tip,Vector2(.112,.108))):
				_socket = -1
				_last_local = head
				_grab_xy = _xy(_plane_point(camera,at,FACE+.08)-head)
				return "socket"
		Phase.INSPECT:
			if _hit(camera,at,_blade.position+Vector3(.092,0,0),Vector2(.192,.107)):
				_last_local = _blade.position
				_grab_xy = _xy(_plane_point(camera,at,GAUGE_Z)-_last_local)
				_approach = -1
				_reading_bolt = -1
				_gauge_side = 1.
				return "blade"
	return ""

func _xy(p: Vector3) -> Vector2:
	return Vector2(p.x,p.y)

func _press_at(camera: Camera3D, at: Vector2, finger: int) -> bool:
	if _finger!=-2:
		return false
	var part := _pick_work(camera,at)
	if part.is_empty():
		return false
	_drag = part
	_finger = finger
	_press = at
	_last_pointer = at
	_emit_hint()
	_refresh()
	return true

func _scrub(p: Vector3) -> void:
	var travel := _last_local.distance_to(p)
	var samples := clampi(ceili(travel/.035),1,48)
	var step := minf(travel/float(samples),.035)
	for n in samples:
		var here := _last_local.lerp(p,(n+.5)/samples)
		for i in 6:
			if _within(here,_patch(i),Vector2(.14,.123)):
				_wear[i] = minf(_scale_thickness(i),float(_wear[i])+step)
	_last_local = p
	_dirty = true
	for i in 6:
		if _wear[i]<_scale_thickness(i):
			return
	_phase_done(Phase.FIT)

func _phase_done(next: Phase) -> void:
	phase = next
	_drag = "finished" if _finger!=-2 else ""
	_checkpoint()
	_emit_hint()

func _drag_to(camera: Camera3D, at: Vector2, finger: int) -> bool:
	if finger!=_finger:
		return false
	_last_pointer = at
	match _drag:
		"brush":
			var point := _plane_point(camera,at,_patch(0).z)
			if point.is_finite():
				_scrub(point)
		"move","rotate":
			var p := _plane_point(camera,at,_shell_z()+(.14 if _drag=="move" else .04))
			if p.is_finite():
				if _drag=="move":
					_shell_offset = (_xy(p)-_grab_xy).clamp(Vector2(-.5,-.32),Vector2(.5,.32))
				elif _xy(p).distance_to(_shell_offset)>.085:
					_shell_roll = clampf(wrapf((_xy(p)-_shell_offset).angle()-_bias,-PI,PI),-.68,.68)
				_last_local = p
				_dirty = true
		"thread":
			var center := _bolt_pos(_bolt)
			var p := _plane_point(camera,at,center.z)
			if p.is_finite():
				var r := _xy(p-center)
				if r.length()>.03 and r.length()<.22:
					if _turn_ref.length()>.03:
						_threads[_bolt] = clampf(float(_threads[_bolt])-_turn_ref.angle_to(r),0.,_thread_turn(_bolt))
						_dirty = true
					_turn_ref = r
				else:
					_turn_ref = Vector2.ZERO
				_last_local = p
				if _threads[_bolt]>=_thread_turn(_bolt):
					_finish_thread()
		"socket","blade":
			var p := _plane_point(camera,at,FACE+.08 if _drag=="socket" else GAUGE_Z)
			if p.is_finite():
				p.x -= _grab_xy.x
				p.y -= _grab_xy.y
				if _drag=="blade":
					_last_local = _inspect(p)
				else:
					_last_local = p
		"wrench":
			var p := _plane_point(camera,at,_grip_point(_angle).z)
			if p.is_finite():
				var r := _xy(p-_bolt_pos(_socket))
				if r.length()>.077:
					_angle_goal = clampf(wrapf(_arm_dir(_socket,0.).angle()-r.angle(),-PI,PI),0.,SWEEP)
	_refresh()
	return true

func _finish_thread() -> void:
	for i in 4:
		if _threads[i]<_thread_turn(i):
			_drag = "finished"
			_checkpoint()
			_emit_hint("Washer seated. Finger-start the remaining raised heads.")
			return
	_phase_done(Phase.TIGHTEN)

func _inspect(point: Vector3) -> Vector3:
	# A reading needs a blade inserted from outside. Dragging across the front of the
	# guide leaves the tip above the cover. A contact stays readable until withdrawal.
	if absf(point.x)>EDGE+.012:
		_approach = -1
		_reading_bolt = -1
		_gauge_side = signf(point.x)
		for i in 4:
			if signf(BOLTS[i].x)==_gauge_side and absf(point.y-BOLTS[i].y)<.092:
				_approach = i
				break
		return point
	if _approach<0:
		return point
	if absf(point.y-BOLTS[_approach].y)>.105:
		_approach = -1
		_reading_bolt = -1
		return point
	var gap := _gap_at(_approach)
	var penetration := maxf(0.,(gap-TAPER_START)/TAPER_SLOPE)
	var stop_x := _gauge_side*(EDGE-penetration)
	if point.x*_gauge_side > stop_x*_gauge_side:
		return point
	point.x = stop_x
	if _reading_bolt!=_approach:
		_reading_bolt = _approach
		_clearances[_approach] = gap
		_dirty = true
		var position_words := "%s %s" % ["Upper" if BOLTS[_approach].y>0. else "Lower","left" if _gauge_side<0. else "right"]
		var read_count := 0
		for value in _clearances:
			if value>=0.:
				read_count += 1
		_emit_hint("%s reads %.1f mm. %s" % [position_words,gap,"Withdraw the gauge to finish." if read_count==4 else "Withdraw and measure the other corners (%d/4)." % read_count])
	return point

func _release_at(camera: Camera3D, at: Vector2, finger: int) -> bool:
	if finger!=_finger:
		return false
	if at.distance_to(_last_pointer)>1.:
		_drag_to(camera,at,finger)
	var part := _drag
	_drag = ""
	_finger = -2
	_angle_goal = _angle
	if part=="blade" and not _clearances.has(-1.):
		_finish_guide()
	elif part in ["move","rotate"]:
		var aligned := true
		for xy: Vector2 in BOLTS:
			if (_shell_offset+xy.rotated(_shell_roll)).distance_to(xy)>.062:
				aligned = false
		if aligned:
			_shell_roll = 0.
			_shell_offset = Vector2.ZERO
			_phase_done(Phase.START)
		elif _shell_offset.length()<.07:
			_emit_hint("The lifting handle is centered. Turn a side lug to bring the holes over the inserts.")
	elif part=="socket":
		for i in 4:
			if _hit(camera,at,_bolt_pos(i)+Vector3(_grab_xy.x,_grab_xy.y,0),Vector2(.114,.114)):
				_socket = i
				_angle = 0.
				_angle_goal = 0.
				_tool_rest = _bolt_pos(i)
				_dirty = true
				_emit_hint()
				break
		if _socket<0:
			_tool_rest = WRENCH_REST
			_dirty = true
			_emit_hint("The socket is clear. Place the ring squarely over a hex head.")
	if _dirty:
		_checkpoint()
	_refresh()
	return true

func _process(dt: float) -> void:
	if not _working or _drag!="wrench" or _socket<0:
		return
	var before := _angle
	var speed := lerpf(1.85,.93,_fraction(_socket)) if _angle_goal>_angle else 2.35
	_angle = move_toward(_angle,_angle_goal,dt*speed)
	if _angle==before:
		return
	if _angle>before:
		# The unsupported corner cants into its guide pins. The relieved corner
		# travels again as the other ears catch up; any order and partial arc work.
		var even_limit := minf(1.,_min_draw()+.54)*_draw_turn(_socket)
		var travel := minf(_angle-before,maxf(0.,even_limit-float(_draw[_socket])))
		_angle = before+travel
		if travel<=.000001:
			var message := "The wrench has clicked on this head." if _fraction(_socket)>=1. else "This corner is bearing hard. Bring the open corners down before pulling here again."
			if _feedback!=message:
				_emit_hint(message)
			return
		_draw[_socket] = minf(_draw_turn(_socket),float(_draw[_socket])+travel)
		_dirty = true
		if is_equal_approx(_draw[_socket],_draw_turn(_socket)):
			_draw[_socket] = _draw_turn(_socket)
			_click.position = _bolt_pos(_socket)
			_click.play()
			if _min_draw()>=.99999:
				_socket = -1
				_phase_done(Phase.INSPECT)
			else:
				_emit_hint("Click. This head has reached the 24 N·m preset.")
	_refresh()

func _finish_guide() -> void:
	var left := (float(_clearances[0])+float(_clearances[3]))*.5
	var right := (float(_clearances[1])+float(_clearances[2]))*.5
	_records.append({"location":station_name(),"fasteners":4,"torque_nm":24,
		"left_gap_mm":snappedf(left,.1),"right_gap_mm":snappedf(right,.1),
		"corner_gaps_mm":_clearances.duplicate(),"fit":"Liner seated; both mating edges even"})
	if station==LEVELS.size()-1:
		phase = Phase.COMPLETE
		_accepted = true
		_drag = "finished"
		_checkpoint()
		submitted.emit(true,"B4  /  Four service-line guides fitted. All bolts torqued, gaps even.")
		return
	var previous := station_name()
	station += 1
	var rise: float = LEVELS[station]-float(LEVELS[station-1])
	_reset_guide()
	_drag = "finished"
	position = _anchor()
	_checkpoint()
	station_changed.emit("%s inspected. Follow the service line %s %.1f m to %s." % [previous,"up" if rise>0 else "down",absf(rise),station_name()])

func handle_input(event: InputEvent, camera: Camera3D) -> bool:
	if event is InputEventKey:
		return false
	return super.handle_input(event,camera)
