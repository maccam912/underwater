extends RefCounted
## Exercise the physical strokes at all four elevations through projected touch.

var world_cursor := Vector3.INF

func _travel(driver, game, target: Vector3, dragging: bool, pixels_per_second: float) -> void:
	if not world_cursor.is_finite():
		world_cursor = game.camera.project_position(game.get_viewport().get_visible_rect().get_center(),1.5)
	var start := world_cursor
	var span: float = game.camera.unproject_position(start).distance_to(game.camera.unproject_position(target))
	var frames := maxi(1,ceili(span/pixels_per_second*Engine.physics_ticks_per_second))
	for i in frames:
		var previous := world_cursor
		world_cursor = start.lerp(target,(i+1.0)/frames)
		if dragging:
			driver._drag_at(game,world_cursor,previous)
		await driver.physics_frame

func _press(driver, game, point: Vector3) -> void:
	await _travel(driver,game,point,false,500.0)
	driver._touch_at(game,point,true)

func _release(driver, game) -> void:
	driver._touch_at(game,world_cursor,false)

func _drag(driver, game, start: Vector3, finish: Vector3) -> void:
	await _press(driver,game,start)
	await _travel(driver,game,finish,true,270.0)
	_release(driver,game)

func _clean(driver, game, work) -> void:
	for side in 2:
		var top: Vector3 = work.control_point("patch%d" % (side*3)) + Vector3.UP*.09
		var bottom: Vector3 = work.control_point("patch%d" % (side*3+2)) + Vector3.DOWN*.09
		await _press(driver,game,top)
		for stroke in 12:
			await _travel(driver,game,bottom,true,205.0)
			var clean := true
			for patch in range(side*3,side*3+3):
				if work._wear[patch]<work._scale_thickness(patch):
					clean = false
			if clean:
				break
			await _travel(driver,game,top,true,205.0)
		_release(driver,game)
	driver.check(work.phase==work.Phase.FIT,"bare saddle accepts guide shell")

func _fit(driver, game, work) -> void:
	await _drag(driver,game,work.control_point("shell"),work.control_point("seat"))
	driver.check(work.phase==work.Phase.FIT,"centered shell still has to be square to its inserts")
	await _drag(driver,game,work.control_point("ear"),work.control_point("square"))
	driver.check(work.phase==work.Phase.START,"squared shell seats over the service line")

func _thread(driver,game,work,i: int) -> void:
	var center: Vector3 = work.control_point("bolt%d" % i)
	var start := center+Vector3.RIGHT*.085
	await _press(driver,game,start)
	for step in 52:
		if work._threads[i]>=work._thread_turn(i):
			break
		var r := Vector2.from_angle(-float(step+1)*TAU/20.)*.085
		center = work.control_point("bolt%d" % i)
		await _travel(driver,game,center+Vector3(r.x,r.y,0),true,170.)
	_release(driver,game)
	driver.check(work._threads[i]>=work._thread_turn(i),"finger-started screw lands on its washer")

func _sweep(driver,game,work,angle: float) -> void:
	var opening: float = work._angle
	# The hand follows the arc rather than jumping the wrench through the pipe.
	for step in 5:
		if work._socket<0:
			return
		var midway := lerpf(opening,angle,float(step+1)/5.)
		await _travel(driver,game,work.to_global(work._grip_point(midway)),true,235. if angle>opening else 355.)
		var last: float = work._angle
		for frame in 65:
			await driver.physics_frame
			if work._socket<0 or absf(work._angle-work._angle_goal)<.001 or is_equal_approx(work._angle,last):
				break
			last = work._angle

func _draw_down(driver,game,work,i: int,target_fraction: float) -> void:
	await _drag(driver,game,work.control_point("wrench"),work.control_point("bolt%d" % i))
	driver.check(work._socket==i,"socket fits whichever bolt the diver chooses")
	if work._socket!=i:
		return
	await _press(driver,game,work.control_point("handle"))
	for stroke in 8:
		if work._fraction(i)>=target_fraction-.003 or work.phase!=work.Phase.TIGHTEN:
			break
		var remain: float = (target_fraction-work._fraction(i))*work._draw_turn(i)
		await _sweep(driver,game,work,minf(work.SWEEP,work._angle+remain+.012))
		if work.phase==work.Phase.TIGHTEN and work._fraction(i)<target_fraction-.003:
			await _sweep(driver,game,work,0.)
	_release(driver,game)
	driver.check(work._fraction(i)>=target_fraction-.003,"partial strokes remain on the chosen bolt")

func _check_uneven_load(driver,game,work) -> void:
	await _drag(driver,game,work.control_point("wrench"),work.control_point("bolt2"))
	await _press(driver,game,work.control_point("handle"))
	for pull in 4:
		await _sweep(driver,game,work,work.SWEEP)
		driver.check_grip(work,work._wrench.to_global(Vector3(work.ARM-.046,0,.067)))
		await _sweep(driver,game,work,0.)
	_release(driver,game)
	driver.check(absf(work._fraction(2)-.54)<.003 and work._min_draw()==0.,
		"a leading lug binds against its pins while the other corners remain open")

func _inspect(driver,game,work,i: int) -> void:
	var side := signf(work.BOLTS[i].x)
	var y: float = work.BOLTS[i].y
	var outside := Vector3(side*(work.EDGE+.105),y,work.GAUGE_Z)
	var inside := Vector3(side*(work.EDGE-.098),y,work.GAUGE_Z)
	await _press(driver,game,work.control_point("blade"))
	await _travel(driver,game,work.to_global(outside),true,235.)
	await _travel(driver,game,work.to_global(inside),true,130.)
	driver.check(work._clearances[i]>3.5 and work._clearances[i]<4.5,"taper physically contacts both mating faces")
	await _travel(driver,game,work.to_global(outside),true,190.)
	_release(driver,game)

func exercise(driver, game) -> void:
	var first_frame := Engine.get_physics_frames()
	for idx in 4:
		var work = game.instrument
		driver.check(work!=null and work.station==idx,"dive along B4 to the current guide")
		if work==null or work.station!=idx:
			return
		await _clean(driver,game,work)
		if work.phase!=work.Phase.FIT:
			return
		await _fit(driver,game,work)
		if work.phase!=work.Phase.START:
			return
		for step in 4:
			await _thread(driver,game,work,(step+idx+2)%4)
		driver.check(work.phase==work.Phase.TIGHTEN,"four hand-started screws support the shell")
		if work.phase!=work.Phase.TIGHTEN:
			return
		if idx==0:
			await _check_uneven_load(driver,game,work)
		for step in 4:
			await _draw_down(driver,game,work,(step+idx)%4,.50)
		for step in 4:
			await _draw_down(driver,game,work,(step+idx+2)%4,1.)
		driver.check(work.phase==work.Phase.INSPECT,"preset clicks on all heads release the inspection blade")
		if work.phase!=work.Phase.INSPECT:
			return
		for step in 4:
			await _inspect(driver,game,work,(step+idx)%4)
			if step==0:
				driver.check(work.phase==work.Phase.INSPECT,"one clearance alone cannot establish an even fit")
		driver.check(work.inspection_record().size()==idx+1,"the measured guide enters the report")
		if idx<3:
			driver.check(game.sample.is_empty(),"each guide remains a separate field location")
			await driver._swim(game)
			await driver._settle()
	driver.check(not game.sample.is_empty(),"four inspected service guides yield the as-fitted record")
	var seconds := float(Engine.get_physics_frames()-first_frame)/Engine.physics_ticks_per_second
	print("B4 scripted work and inter-guide travel: %.1f simulation seconds" % seconds)
