extends "res://game/field_tool.gd"
## Diver-held single-echo UT on bare steel. Positions are indexed on the survey plan.

signal station_changed(detail: String)

const SKIN := preload("res://game/survey_strip.gdshader")
const BAND_HEIGHTS := [0.0, 3.4, 6.1, -3.35]
const BAND_NAMES := ["collar", "upper", "crown", "lower"]
const SPOTS := 8
const MASK_WIDTH := 5
const MASK_SIZE := MASK_WIDTH * MASK_WIDTH
const FOOTPRINT := .25
const RADIUS := 2.97
const BRUSH_CLIP := Vector3(-.59,-.40,.09)
const PROBE_CLIP := Vector3(.055,-.40,.13)
const BLOCK := Vector3(.71,-.475,.185)
const TAIL := .20
const NO_POINT := -1
const REFERENCE := -2
const FORMAT := 3
const RECHECK_BELOW := 100 # Tenths of a millimetre, specified by this fictional work order.

var band := 0
var gate := 3
var _mask := PackedFloat32Array()
var _first := PackedInt32Array()
var _repeat := PackedInt32Array()
var _opening_check := false
var _closing_check := false

var _rack: Node3D
var _skins: Array[ShaderMaterial] = []
var _brush: Node3D
var _brush_in_clip: Node3D
var _parked_probe: Node3D
var _legend: Label3D
var _brush_held := true
var _tip := Vector3.ZERO
var _seated := NO_POINT
var _tilt := Vector2.ZERO
var _settled := 0.0
var _live := 0
var _dirty := false
var _checkpoint_age := 0.0
var _lifted := true
var _scrubbing := NO_POINT
var _press_ray_hit := Vector3.ZERO
var _last_ray_hit := Vector3.ZERO
var _dial_start := Vector3.ZERO
var _carried := false
var _hand_displacement := Vector2.ZERO

func _band_offset(index: int) -> Vector3:
	return Vector3(.035,1.0,-.051) * float(BAND_HEIGHTS[index])

func _face_z(x: float) -> float:
	return -.26 + sqrt(RADIUS*RADIUS-x*x) - RADIUS

func _normal(x: float) -> Vector3:
	return Vector3(x/RADIUS,0.,sqrt(1.0-pow(x/RADIUS,2)))

func _spot_local(i: int) -> Vector3:
	var x := -.69 + float(i % 4)*.279
	var y := .205 if i < 4 else -.145
	return Vector3(x,y,_face_z(x))

func spot_point(i: int) -> Vector3:
	return to_global(_spot_local(i))

func reference_point() -> Vector3:
	return to_global(BLOCK)

func _index(i: int) -> int:
	return band*SPOTS+i

func _id(b: int, i: int) -> String:
	return "%s P%02d" % [BAND_NAMES[b],i+1]

func _mm(tenths: int) -> String:
	return "%.1f" % (tenths*.1)

func configure(_index_unused: int, watch_number: int, settings: Array) -> void:
	_job = 0
	_watch = watch_number
	band = 0
	gate = 3
	_opening_check = false
	_closing_check = false
	_accepted = false
	_mask.resize(SPOTS * BAND_HEIGHTS.size() * MASK_SIZE)
	_first.resize(SPOTS * BAND_HEIGHTS.size())
	_repeat.resize(_first.size())
	_mask.fill(0.)
	_first.fill(0)
	_repeat.fill(0)
	if settings.size() == 2 and settings[0] is int and int(settings[0]) >= 0:
		gate = clampi(int(settings[0]),0,24)
	elif settings.size()==8 and settings[0]==FORMAT:
		band = clampi(int(settings[1]),0,BAND_HEIGHTS.size()-1)
		gate = clampi(int(settings[2]),0,24)
		if settings[3] is PackedFloat32Array and settings[3].size()==_mask.size():
			_mask = settings[3].duplicate()
		if settings[4] is PackedInt32Array and settings[4].size()==_first.size():
			_first = settings[4].duplicate()
		if settings[5] is PackedInt32Array and settings[5].size()==_repeat.size():
			_repeat = settings[5].duplicate()
		_opening_check = bool(settings[6])
		_closing_check = bool(settings[7])
	if _content == null:
		_build()
		_build_stations()
	_feedback = ""
	_reset_hand()
	_place_meter()
	for i in _skins.size():
		_update_skin(i)
	_refresh(true)

func snapshot() -> Array:
	return [FORMAT,band,gate,_mask.duplicate(),_first.duplicate(),_repeat.duplicate(),_opening_check,_closing_check]

func inspection_record() -> Array:
	var values: Array = []
	for index in _first.size():
		if _first[index] > 0:
			@warning_ignore("integer_division")
			var b := index / SPOTS
			values.append({"band":BAND_NAMES[b], "point":"P%02d" % (index%SPOTS+1),
				"thickness_mm":_first[index]*.1, "repeat_mm":_repeat[index]*.1 if _repeat[index]>0 else null})
	return values

func _reset_hand() -> void:
	_brush_held = true
	_tip = BRUSH_CLIP
	_seated = NO_POINT
	_scrubbing = NO_POINT
	_settled = 0.
	_live = 0
	_tilt = Vector2.ZERO
	_hand_displacement = Vector2.ZERO
	_lifted = true

func _save_progress() -> void:
	_dirty = false
	_checkpoint_age = 0.
	adjusted.emit(snapshot())

func set_working(active: bool) -> void:
	if _working and not active:
		_save_progress()
		_reset_hand()
	super.set_working(active)

func _place_meter() -> void:
	position = ANCHORS[0]+_band_offset(band)
	_rack.position = -_band_offset(band)

func swim_target() -> Vector3:
	return stance()

func station_name() -> String:
	return "A2 · %s band" % BAND_NAMES[band]

func stance() -> Vector3:
	return to_global(Vector3(.12,.04,1.65))

func focus_point() -> Vector3:
	return to_global(Vector3(.12,-.02,-.085))

func _brush_head(parent: Node3D) -> void:
	_box(parent,Vector3(-.005,.005,.039),Vector3(.124,.066,.034),"ochre",-.08)
	for i in 9:
		_rod(parent,Vector3(-.062+i*.015,-.018,.031),Vector3(-.057+i*.015,.012,.0005),.005,"steel",6)
	_rod(parent,Vector3(.005,0,.041),Vector3(-.16,-.046,.12),.024,"ochre")

func _build_stations() -> void:
	_rack = _pivot(self,Vector3.ZERO)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * FOOTPRINT
	for b in BAND_HEIGHTS.size():
		var wall := _pivot(_rack,_band_offset(b))
		# Six broad facets form the welded reinforcement on the cylindrical sleeve.
		for f in 6:
			var x := -.91 + (f+.5)*.221
			var plate := _pivot(wall,Vector3(x,-.015,_face_z(x)-.049))
			plate.rotation.y = asin(x/RADIUS)
			_box(plate,Vector3.ZERO,Vector3(.231,.86,.089),"iron")
			for y in [-.428,.428]:
				_rod(plate,Vector3(-.115,y,.044),Vector3(.115,y,.044),.012,"steel",8)
		_label(wall,"A2   /   "+str(BAND_NAMES[b]).to_upper(),Vector3(-.29,.36,_face_z(-.29)+.014),.056,Color("c4b99c"))
		for i in SPOTS:
			var at := _spot_local(i)
			var pad := _pivot(wall,at)
			pad.rotation.y = asin(at.x/RADIUS)
			var face := MeshInstance3D.new()
			var skin := ShaderMaterial.new()
			skin.shader = SKIN
			skin.set_shader_parameter("wear",STEEL)
			skin.set_shader_parameter("seed",b*SPOTS+i+1.6)
			face.mesh = quad
			face.material_override = skin
			face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pad.add_child(face)
			_skins.append(skin)
			_label(pad,"P%02d" % (i+1),Vector3(-.033,-.126,.005),.044,Color("bdb7a1"),-.025)
			_rod(pad,Vector3(-.113,-.085,.007),Vector3(-.080,-.085,.007),.0034,"white",6)
	_brush = _pivot(_content,BRUSH_CLIP)
	_brush_head(_brush)
	_brush_in_clip = _pivot(_content,BRUSH_CLIP)
	_brush_head(_brush_in_clip)
	_parked_probe = _pivot(_content,PROBE_CLIP)
	_face_disc(_parked_probe,Vector3(0,0,.055),.054,.09,"steel")
	_face_disc(_parked_probe,Vector3(0,0,.13),.063,.086,"ochre")
	_face_disc(_parked_probe,Vector3(0,0,.20),.051,.063,"rubber")
	_rod(_content,BRUSH_CLIP+Vector3(-.082,.05,-.04),PROBE_CLIP+Vector3(.101,.05,-.04),.019,"iron")
	_label(_content,"BRUSH",BRUSH_CLIP+Vector3(0,-.088,.024),.047,Color("d1c6ab"))
	_label(_content,"PROBE",PROBE_CLIP+Vector3(0,-.088,.024),.047,Color("d1c6ab"))
	_box(_content,BLOCK-Vector3(0.,0.,.042),Vector3(.38,.17,.078),"steel")
	_face_disc(_content,BLOCK-Vector3(0.,0.,.006),.073,.012,"steel")
	_label(_content,"12.0 mm REF",BLOCK+Vector3(0.,-.126,.005),.048,Color("d0c5a9"))
	_box(_content,METER+Vector3(0,.382,-.025),Vector3(.71,.104,.044),"iron")
	_legend = _label(_content,"",METER+Vector3(0,.379,.001),.044,Color("d2cfbc"))
	_reading.pixel_size *= .73
	_flush()

func _update_skin(index: int) -> void:
	var offset := index*MASK_SIZE
	_skins[index].set_shader_parameter("clean",_mask.slice(offset,offset+MASK_SIZE))

func _near_spot(pointer: Vector3) -> int:
	for i in SPOTS:
		if Vector2(pointer.x-_spot_local(i).x,pointer.y-_spot_local(i).y).length() < FOOTPRINT*.50:
			return i
	return NO_POINT

func _steel_hit(camera: Camera3D,screen: Vector2) -> Vector3:
	var hit := _plane_point(camera,screen,_face_z(-.3))
	if hit.is_finite() and absf(hit.x)<1.45:
		hit = _plane_point(camera,screen,_face_z(hit.x))
	return hit

func _pick_spot(camera: Camera3D,screen: Vector2) -> int:
	var ref := _plane_point(camera,screen,BLOCK.z)
	if _within(ref,BLOCK,Vector2(.089,.075)):
		return REFERENCE
	return _near_spot(_steel_hit(camera,screen))

func _mask_at(i: int, x: int, y: int) -> int:
	return _index(i)*MASK_SIZE + x + MASK_WIDTH*y

func _cell_xy(i: int,x: int,y: int) -> Vector2:
	var center := _spot_local(i)
	return Vector2(center.x,center.y) + Vector2(x-2,y-2)*FOOTPRINT/MASK_WIDTH

func _scrub(i: int, a: Vector3, b: Vector3) -> void:
	var from := Vector2(a.x,a.y)
	var to := Vector2(b.x,b.y)
	var distance := from.distance_to(to)
	if distance < .00005:
		return
	var segments := clampi(ceili(distance/.022),1,36)
	var toughness := .49 + .12*sin(float(_index(i))*.97 + _watch*.41)
	for step in segments:
		var bristles := from.lerp(to,(step+.5)/segments)
		for y in MASK_WIDTH:
			for x in MASK_WIDTH:
				var d := (bristles-_cell_xy(i,x,y))*Vector2(.88,1.18)
				var pressure := 1.-smoothstep(.018,.078,d.length())
				if pressure>0.:
					var idx := _mask_at(i,x,y)
					_mask[idx] = minf(1.,_mask[idx] + pressure*distance/(toughness*segments))
					_dirty = true
	_update_skin(_index(i))

func _bare_fraction(i: int, tip: Vector3) -> float:
	if i==REFERENCE:
		return 1.
	if i < 0:
		return 0.
	var p := Vector2(tip.x,tip.y)
	var center := _spot_local(i)
	if p.distance_to(Vector2(center.x,center.y)) > .068:
		return 0.
	var bare := 0.
	var total := 0.
	for y in MASK_WIDTH:
		for x in MASK_WIDTH:
			var w := 1.-smoothstep(.022,.083,_cell_xy(i,x,y).distance_to(p))
			bare += w * _mask[_mask_at(i,x,y)]
			total += w
	return bare/total if total>.1 else 0.

func _metal_contact(i: int, tip: Vector3) -> bool:
	return _bare_fraction(i,tip)>=.80

func _measurement(i: int) -> int:
	if i==REFERENCE:
		return 120
	# The same stamped position still measures the same piece of steel next watch.
	var base := 117 + posmod(5+band*7+i*13,26)
	if i==posmod(1+band*3,SPOTS):
		base = 87 + posmod(band*4+1,10)
	var offset := _tip - _spot_local(i)
	return base + roundi(1.4*sin(offset.x*20.+offset.y*13.))

func _lowest() -> int:
	var lowest := 0
	for i in SPOTS:
		if _first[_index(i)]==0:
			return NO_POINT
		if _first[_index(i)] < _first[_index(lowest)]:
			lowest=i
	return lowest

func _needs_repeat(i: int) -> bool:
	var idx := _index(i)
	return _first[idx]>0 and _repeat[idx]==0 and (_first[idx]<RECHECK_BELOW or i==_lowest())

func _next_point() -> int:
	for i in SPOTS:
		if _needs_repeat(i):
			return i
	for i in SPOTS:
		if _first[_index(i)]==0:
			return i
	return NO_POINT

func _axis() -> Vector3:
	return _normal(_tip.x) if _seated>=0 else Vector3.BACK

func _square_tail() -> Vector3:
	return _tip+_axis()*TAIL

func _tail() -> Vector3:
	return _square_tail()+Vector3(_tilt.x,_tilt.y,0)

func control_point(id: String) -> Vector3:
	match id:
		"brush": return to_global(_tip if _brush_held else BRUSH_CLIP)
		"probe": return to_global(PROBE_CLIP if _brush_held else _tip)
		"tail": return to_global(_tail())
		"square": return to_global(_square_tail())
	return super.control_point(id)

func _refresh(_instant := false) -> void:
	if _rack==null:
		return
	_brush.visible = _working and _brush_held and not _accepted
	_probe.visible = _working and not _brush_held and not _accepted
	_parked_probe.visible = not _probe.visible
	_brush_in_clip.visible = not _brush.visible
	if _brush.visible:
		_brush.position = _tip
		if _drag=="brush" or not _tip.is_equal_approx(BRUSH_CLIP):
			_hold_tool(_brush.transform*Vector3(-.098,-.028,.09),_brush.basis*Vector3(-.165,-.046,.079).normalized(),.022)
		else:
			_glove.stow()
	elif _probe.visible:
		var axis := (_tail()-_tip).normalized()
		_probe.basis = Basis.looking_at(-axis,Vector3.UP)
		_probe.position = _tip
		_update_lead()
		_hold_tool(_probe.transform*Vector3(0,0,.14),_probe.basis.z,.061)
	else:
		_glove.stow()
	_lead.visible_instance_count = CABLE_SEGMENTS if _probe.visible else 0
	_glass.set_shader_parameter("gate",float(gate))
	_dial.rotation.z = -gate/24.*TAU*.83
	var signal_strength := _bare_fraction(_seated,_tip) * (1.-smoothstep(.025,.110,_tilt.length()))
	_glass.set_shader_parameter("contact",_seated!=NO_POINT)
	_glass.set_shader_parameter("coupling",signal_strength)
	if _seated!=NO_POINT:
		_glass.set_shader_parameter("wall",_measurement(_seated)*.1)
	_reading.text = _mm(_live) if _live>0 else "—"
	_reading.modulate = Color("d9e0ad") if _live>0 else Color("bba486")
	var i := _next_point()
	var location := "REF 12.0 mm" if not _opening_check or i<0 else _id(band,i)
	if _seated >= 0:
		location = _id(band,_seated)
	_legend.text = "SE   /   "+location.to_upper()

func instruction(touch: bool) -> String:
	_touch=touch
	if not _feedback.is_empty():
		return _feedback
	if _accepted:
		return "UT log complete. Carry the thickness record back to Ellis."
	var next := _next_point()
	if _seated!=NO_POINT:
		if _seated>=0 and not _metal_contact(_seated,_tip):
			return "Poor coupling. Take the wire brush and clear enough bare steel for the probe face."
		if _tilt.length()>=.031:
			var dirs := PackedStringArray()
			if absf(_tilt.x)>.018:
				dirs.append("left" if _tilt.x>0 else "right")
			if absf(_tilt.y)>.018:
				dirs.append("down" if _tilt.y>0 else "up")
			return "One edge is lifted. Rock the back of the probe %s until the face lies flat." % " and ".join(dirs)
		if _live>0:
			return "%s mm · stable back-wall echo. Press MARK to record." % _mm(_live)
		return "Hold the probe steady and read the back-wall echo."
	if not _opening_check or next<0:
		return "Check the gauge against its stamped 12.0 mm block. Drag the probe from its clip to the block, then square the barrel."
	var point := _id(band,next)
	if _needs_repeat(next):
		return "%s needs an independent repeat. Lift the probe clear and seat it again on that patch." % point
	if _brush_held:
		return "%s · scrub the marked spot to bare steel. Drag the parked probe onto the cleaned patch." % point
	return "%s · place the probe on bare steel. Pick up the brush below the markings to clear another spot." % point

func _meter_part(camera: Camera3D,p: Vector2) -> String:
	if _within(_plane_point(camera,p,STAMP.z),STAMP,Vector2(.091,.09)):
		return "stamp"
	if _within(_plane_point(camera,p,DIAL.z),DIAL,Vector2(.09,.09)):
		return "dial"
	if _within(_plane_point(camera,p,GLASS_C.z),GLASS_C,Vector2(GLASS_WIDTH*.51,GLASS_HEIGHT*.51)):
		return "gate"
	return ""

func _over(camera: Camera3D, p: Vector2, local: Vector3, reach: float) -> bool:
	var hit := _plane_point(camera,p,local.z)
	return _within(hit,local,Vector2.ONE*reach)

func _press_at(camera: Camera3D, p: Vector2, finger: int) -> bool:
	if _finger!=-2:
		return false
	var part := _meter_part(camera,p)
	var site := _pick_spot(camera,p)
	if part=="":
		if _over(camera,p,BRUSH_CLIP,.087):
			_brush_held=true
			_reset_hand()
			part="brush"
		elif _seated!=NO_POINT and _over(camera,p,_tail(),.091):
			part="rock"
		elif (_brush_held and _over(camera,p,PROBE_CLIP,.086)) or (not _brush_held and _over(camera,p,_tip,.101)):
			_brush_held=false
			_tip=PROBE_CLIP if _seated==NO_POINT and _brush.visible else _tip
			part="place"
		elif site>=0 and _brush_held:
			_tip=_steel_hit(camera,p)
			part="brush"
		else:
			return false
	_drag=part
	_finger=finger
	_press_ray_hit=_plane_point(camera,p,.10)
	_last_ray_hit=_press_ray_hit
	_carried=false
	_hand_displacement=Vector2.ZERO
	_feedback=""
	_scrubbing = site if part=="brush" else NO_POINT
	if part=="gate":
		_gate_under(camera,p)
	elif part=="dial":
		_start_detent=gate
		_dial_start=_plane_point(camera,p,DIAL.z)
	_refresh()
	_emit_hint()
	return true

func _drag_to(camera: Camera3D,p: Vector2,finger: int) -> bool:
	if finger!=_finger:
		return false
	_last_ray_hit=_plane_point(camera,p,.10)
	if _last_ray_hit.is_finite() and _press_ray_hit.is_finite() and _last_ray_hit.distance_to(_press_ray_hit)>.014:
		_carried=true
	match _drag:
		"brush":
			var loc := _steel_hit(camera,p)
			if not loc.is_finite() or absf(loc.x)>1.4 or absf(loc.y)>.8:
				return true
			var site := _near_spot(loc)
			if site>=0 and site==_scrubbing:
				_scrub(site,_tip,loc)
			_scrubbing=site
			_tip=loc
		"rock":
			var loc := _plane_point(camera,p,_square_tail().z)
			if not loc.is_finite():
				return true
			var error := loc-_square_tail()
			if Vector2(error.x,error.y).length()>.15:
				_seated=NO_POINT
				_lifted=true
				_live=0
				_settled=0.
				_tilt=Vector2.ZERO
				_drag="place"
			else:
				_tilt=Vector2(error.x,error.y)
				if _tilt.length()>.031:
					_settled=0.
					_live=0
				_refresh()
				_emit_hint()
				return true
		"gate": _gate_under(camera,p)
		"dial":
			var b := _plane_point(camera,p,DIAL.z)
			if b.is_finite() and _dial_start.is_finite():
				_set_value(0,_start_detent+roundi((b.x-_dial_start.x+b.y-_dial_start.y)/.036))
	if _drag=="place" and _carried:
		var loc := _plane_point(camera,p,.10)
		if loc.is_finite():
			if _seated!=NO_POINT and _tip.distance_to(loc)>.13:
				_lifted=true
			_seated=NO_POINT
			_live=0
			_settled=0.
			var next := Vector3(clampf(loc.x,-1.13,1.25),clampf(loc.y,-.65,.62),.10)
			_hand_displacement+=Vector2(next.x-_tip.x,next.y-_tip.y)
			_tip=next
	_refresh()
	return true

func _release_at(camera: Camera3D,p: Vector2,finger: int) -> bool:
	if finger!=_finger:
		return false
	var hit := _plane_point(camera,p,.10)
	if hit.is_finite() and not hit.is_equal_approx(_last_ray_hit):
		_drag_to(camera,p,finger)
	var part:=_drag
	_finger=-2
	_drag=""
	if part=="stamp" and _meter_part(camera,p)=="stamp":
		_submit()
		return true
	if part=="place" and _carried:
		_seated=_pick_spot(camera,p)
		if _seated!=NO_POINT:
			_tip=_plane_point(camera,p,BLOCK.z) if _seated==REFERENCE else _steel_hit(camera,p)
			# Preserve the carried barrel angle as its foot meets the local surface.
			# A gentle, square approach can couple on first contact.
			_tilt.x-=_axis().x*TAIL
		else:
			_lifted=true
		_settled=0.
		_live=0
	_refresh()
	_emit_hint()
	if _dirty or part in ["dial","gate"]:
		_save_progress()
	return true

func _gate_under(camera: Camera3D, position_on_screen: Vector2) -> void:
	var point := _plane_point(camera, position_on_screen, GLASS_C.z)
	if point.is_finite():
		_set_value(0, roundi((.5 + (point.x-GLASS_C.x)/GLASS_WIDTH) * 24.0))

func _set_value(_side: int,value: int) -> void:
	gate=clampi(value,0,24)
	_glass.set_shader_parameter("gate",float(gate))
	_dial.rotation.z=-gate/24.*TAU*.83

func handle_input(event: InputEvent,camera: Camera3D) -> bool:
	if event is InputEventKey:
		return false
	return super.handle_input(event,camera)

func _process(delta: float) -> void:
	if not _working or _accepted:
		return
	if _drag=="place" and _carried and delta>.0001:
		var lateral_velocity := _hand_displacement/delta
		_hand_displacement=Vector2.ZERO
		var load := (-lateral_velocity*.14).limit_length(.088)
		_tilt=_tilt.lerp(load,1.-exp(-delta*8.))
		_refresh()
	if _dirty:
		_checkpoint_age+=delta
		if _checkpoint_age>=1.5:
			_save_progress()
	if _seated!=NO_POINT and _live==0 and _tilt.length()<.031 and _metal_contact(_seated,_tip):
		_settled+=delta
		# Several agreeing pulse returns establish the digital readout.
		if _settled>=.65:
			_live=_measurement(_seated)
			_refresh()
			_emit_hint()
	if _stamp_travel>0.:
		_stamp_travel=maxf(0.,_stamp_travel-delta*4.5)
		_stamp.position.z=STAMP.z-METER.z-.041*minf(1.,_stamp_travel*2.)

func _submit() -> void:
	_stamp_travel=1.
	if _live<=0:
		_emit_hint("No stable thickness to store. Seat the probe on clean steel and square it to the surface.")
		return
	if _seated==REFERENCE:
		if not _opening_check:
			_opening_check=true
			_reset_hand()
			_refresh()
			_save_progress()
			_emit_hint("Reference check 12.0 mm. Brush the numbered spots on the sleeve, then probe the bare patches.")
		elif _next_point()<0 and band==BAND_HEIGHTS.size()-1:
			_closing_check=true
			_accepted=true
			_refresh()
			_save_progress()
			var min_index := 0
			var minimum := _first[0]
			var repeats := 0
			for i in _first.size():
				if _repeat[i]>0:
					repeats+=1
				var measured := mini(_first[i],_repeat[i]) if _repeat[i]>0 else _first[i]
				if measured<minimum:
					minimum=measured
					min_index=i
			@warning_ignore("integer_division")
			var min_id := _id(min_index/SPOTS,min_index%SPOTS)
			submitted.emit(true,"A2 / %d UT spots · %d repeats. Minimum %s mm at %s. Ref 12.0 mm before/after." % [_first.size(),repeats,_mm(minimum),min_id])
		else:
			_emit_hint("Reference reads 12.0 mm. Continue the spot survey on the sleeve.")
		return
	if not _opening_check:
		_emit_hint("Check the stamped 12.0 mm reference block before recording the first steel reading.")
		return
	var i := _seated
	var index := _index(i)
	if _first[index]==0:
		_first[index]=_live
	elif _needs_repeat(i) and _lifted:
		if absi(_live-_first[index])>3:
			_emit_hint("Repeat disagrees by more than 0.3 mm. Clean around the depression and re-seat.")
			return
		_repeat[index]=_live
	else:
		_emit_hint("Reading already stored. Lift the probe clear before making an independent repeat." if _needs_repeat(i) else "Reading already stored for "+_id(band,i)+".")
		return
	_lifted=false
	var record := "%s · %s mm stored." % [_id(band,i),_mm(_live)]
	var next := _next_point()
	if next==NO_POINT and band<BAND_HEIGHTS.size()-1:
		band+=1
		_reset_hand()
		_place_meter()
		_refresh(true)
		_save_progress()
		station_changed.emit("%s Follow the sleeve to the %s band." % [record,BAND_NAMES[band]])
	else:
		_refresh()
		_save_progress()
		if next==NO_POINT:
			_emit_hint(record+" Finish with a 12.0 mm reference check.")
		elif _needs_repeat(next):
			_emit_hint(record+" Recheck %s. Drag the barrel clear, then re-seat it." % _id(band,next))
		else:
			_emit_hint(record+" Next is %s. Take the brush from its clip." % _id(band,next))
