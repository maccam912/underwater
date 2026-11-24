extends RefCounted
## Projects hand trajectories through the actual game camera onto the same touch surface as a player.

func _move(driver,game,a: Vector3,b: Vector3,seconds: float) -> void:
	var frames := maxi(1,roundi(seconds*Engine.physics_ticks_per_second))
	var last := a
	for frame in frames:
		var t := (frame+1.)/frames
		var point := a.lerp(b,t)
		driver._drag_at(game,point,last)
		last=point
		await driver.physics_frame

func _carry(driver,game,a: Vector3,b: Vector3,speed: float) -> void:
	driver._touch_at(game,a,true)
	await _move(driver,game,a,b,clampf(a.distance_to(b)/speed,.35,2.4))
	driver._touch_at(game,b,false)
	await driver.physics_frame

func _clean(driver,game,work,i: int) -> void:
	driver._tap(game,work.to_global(work.BRUSH_CLIP))
	var center: Vector3=work.spot_point(i)
	var a:=center+Vector3(-.092,0,0)
	driver._touch_at(game,a,true)
	for pass_index in 16:
		var y:=.024*sin(float(pass_index)*2.1)
		var b:=center+Vector3(.092 if pass_index%2==0 else -.092,y,0)
		await _move(driver,game,a,b,a.distance_to(b)/.24)
		if pass_index == 0:
			driver.check_grip(work,work._brush.to_global(Vector3(-.098,-.028,.09)))
		a=b
		if work._metal_contact(i,work.to_local(center)):
			break
	driver._touch_at(game,a,false)
	driver.check(work._metal_contact(i,work.to_local(center)),"wire strokes expose steel at the actual probe footprint")

func _read(driver,game,work,at: Vector3,repeat: bool=false) -> void:
	var grip: Vector3=work.control_point("probe")
	if repeat:
		# Lift beyond the edge and come back from a fresh approach.
		grip=work.control_point("tail")
		var clear:=grip+Vector3(-.19,.12,.14)
		await _carry(driver,game,grip,clear,.46)
		grip=work.control_point("probe")
	await _carry(driver,game,grip,at,.49)
	driver.check(work._seated!=work.NO_POINT,"probe is resting on the work surface")
	if driver.failed:
		return
	driver.check(work._live==0,"the readout waits for agreeing back-wall pulses")
	await _carry(driver,game,work.control_point("tail"),work.control_point("square"),.105)
	for frame in 75:
		if work._live>0:
			break
		await driver.physics_frame
	driver.check(work._live>0,"flat, clean contact produces a numeric back-wall echo")
	if driver.failed:
		return
	driver.check_grip(work,work._probe.to_global(Vector3(0,0,.14)))
	driver._tap(game,work.control_point("stamp"))

func exercise(driver,game) -> void:
	var work=game.instrument
	var first_frame:=Engine.get_physics_frames()
	driver._tap(game,work.control_point("stamp"))
	driver.check(work.inspection_record().is_empty(),"gauging in water cannot create a thickness record")
	await _read(driver,game,work,work.reference_point())
	driver.check(work._opening_check,"opening reference check stored")
	await _carry(driver,game,work.control_point("probe"),work.spot_point(2),.49)
	await _carry(driver,game,work.control_point("tail"),work.control_point("square"),.105)
	for frame in 55:
		await driver.physics_frame
	driver._tap(game,work.control_point("stamp"))
	driver.check(work._live==0 and work.inspection_record().is_empty(),"square contact on an unprepared spot cannot produce a valid single-echo reading")
	for b in work.BAND_HEIGHTS.size():
		# The location tags allow the diver to visit spots in any order.
		for i in [2,0,4,1,3,5,7,6]:
			if driver.failed:
				return
			await _clean(driver,game,work,i)
			await _read(driver,game,work,work.spot_point(i))
			if driver.failed:
				return
			if work.band==b and work._needs_repeat(i):
				driver._tap(game,work.control_point("stamp"))
				driver.check(work._needs_repeat(i),"a second press cannot substitute for an independent reading")
				await _read(driver,game,work,work.spot_point(i)+Vector3(.007,.003,0),true)
		if b<work.BAND_HEIGHTS.size()-1:
			driver.check(game.mode=="dive","next inspection band requires swimming")
			await driver._swim(game)
			driver.check(game.mode=="tool","next band is within working reach")
			if game.mode!="tool":
				return
			await driver._settle()
	if driver.failed:
		return
	# A quick exchange at the tool clip lifts the probe before the closing check.
	driver._tap(game,work.to_global(work.BRUSH_CLIP))
	await _read(driver,game,work,work.reference_point())
	var logbook: Array=work.inspection_record()
	driver.check(logbook.size()==32 and work._closing_check,"32 registered thicknesses and closing reference check")
	var repeats:=0
	for entry in logbook:
		driver.check(entry.thickness_mm>0. and entry.point.begins_with("P") and entry.band in work.BAND_NAMES,"every measurement carries a location and positive thickness")
		if entry.repeat_mm!=null:
			repeats+=1
			driver.check(absf(entry.thickness_mm-entry.repeat_mm)<=.3,"independent thicknesses agree")
	driver.check(repeats>=4,"each band has an independently verified minimum")
	var seconds:=float(Engine.get_physics_frames()-first_frame)/Engine.physics_ticks_per_second
	print("A2 survey and inter-band travel: %.1f simulation seconds" % seconds)
