extends RefCounted

## 天轮配对测试：独立数据、完整施法、双环、连续运动、扫掠去重和退场清理。
const DT := 1.0 / 60.0


static func run(t) -> void:
	_test_form_and_component(t)
	_test_double_ring(t)
	_test_configurable_slots(t)
	_test_quick_release(t)
	_test_entry_and_turn_continuity(t)
	_test_flight_tangent_acceleration_and_contact(t)
	_test_elevated_contact(t)
	_test_close_point_motion(t)
	_test_hits_and_dedup(t)
	_test_switch_before_release(t)
	_test_switch_after_release(t)
	_test_generation_cancel(t)
	_test_exit_cleanup(t)
	_test_cooldown(t)
	_test_repeat_and_clock(t)
	_test_view_reads_data(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var cast := SwordCastComponent.new()
	var data := HeavenlySwordWheelComponent.new()
	host.add_child(cast)
	host.add_child(data)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var wheel := HeavenlySwordWheel.new()
	manager.add_child(wheel)
	cast.form = SwordCastComponent.FORM_WHEEL
	cast.aim_point = Vector3(0.0, 0.0, -8.0)
	cast.aim_surface_point = cast.aim_point
	cast.aim_surface_normal = Vector3.UP
	cast.aim_surface_valid = true
	return {"host": host, "cast": cast, "data": data, "manager": manager, "wheel": wheel}


static func _hold(scene: Dictionary, ticks: int) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_pressed = true
	cast.cast_held = true
	(scene["manager"] as CapabilityManager).tick(DT)
	cast.cast_pressed = false
	for index in range(ticks):
		(scene["manager"] as CapabilityManager).tick(DT)


static func _release(scene: Dictionary) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_held = false
	cast.cast_released = true
	(scene["manager"] as CapabilityManager).tick(DT)
	cast.cast_released = false


static func _wait_phase(scene: Dictionary, phase: String, limit: int = 600) -> bool:
	for index in range(limit):
		if (scene["data"] as HeavenlySwordWheelComponent).phase == phase:
			return true
		(scene["manager"] as CapabilityManager).tick(DT)
	return false


static func _idle(scene: Dictionary, limit: int = 600) -> bool:
	for index in range(limit):
		(scene["manager"] as CapabilityManager).tick(DT)
		if not (scene["wheel"] as HeavenlySwordWheel).active:
			return true
	return false


static func _test_form_and_component(t) -> void:
	t.begin_case()
	var scene := _build(t)
	(scene["cast"] as SwordCastComponent).form = SwordCastComponent.FORM_ARRAY
	_hold(scene, 2)
	t.assert_false((scene["wheel"] as HeavenlySwordWheel).active, "其它招式不激活天轮")
	(scene["cast"] as SwordCastComponent).form = SwordCastComponent.FORM_WHEEL
	var data := scene["data"] as HeavenlySwordWheelComponent
	(scene["host"] as Node3D).remove_child(data)
	_hold(scene, 2)
	t.assert_false((scene["wheel"] as HeavenlySwordWheel).active, "未装独立组件不激活")
	data.free()


static func _test_double_ring(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as HeavenlySwordWheelComponent
	_hold(scene, 120)
	t.assert_eq(data.swords.size(), data.max_swords, "长按成完整三十六剑双轮")
	var inner := 0
	var outer := 0
	var slots: Dictionary = {}
	for sword in data.swords:
		var radius := (sword["position"] as Vector3).distance_to(data.center)
		var expected := data.inner_radius if int(sword["ring"]) == 0 else data.outer_radius
		t.assert_true(absf(radius - expected) < 0.0001, "悬剑在对应圆轮上")
		t.assert_true(absf(((sword["position"] as Vector3) - data.center).dot(data.direction)) < 0.0001,
			"剑阵为完整竖直轮面")
		t.assert_true((sword["forward"] as Vector3).dot(((sword["position"] as Vector3) - data.center).normalized()) > 0.999,
			"悬剑剑尖指向轮缘外侧")
		var key := "%d/%.4f" % [int(sword["ring"]), float(sword["angle"])]
		t.assert_false(slots.has(key), "每把剑有唯一圆轮槽位")
		slots[key] = true
		if int(sword["ring"]) == 0:
			inner += 1
		else:
			outer += 1
	t.assert_eq(inner, data.inner_swords, "内轮十二剑")
	t.assert_eq(outer, data.max_swords - data.inner_swords, "外轮二十四剑")
	var cast := scene["cast"] as SwordCastComponent
	t.assert_eq(cast.pose_kind, SwordCastComponent.POSE_WHEEL, "结阵请求天轮双臂姿势")
	t.assert_true(data.ring_alpha > 0.99, "完整成阵法环可见")


static func _test_quick_release(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as HeavenlySwordWheelComponent
	_hold(scene, 0)
	_release(scene)
	t.assert_eq(data.swords.size(), data.min_swords, "快点至少六把灵剑")
	t.assert_true(data.release_requested, "松开捕获释放请求")
	t.assert_eq(data.phase, "gather", "快速松开仍先完成入阵")
	t.assert_true(_wait_phase(scene, "turn"), "短招有可观察的转向阶段")
	t.assert_eq(data.swords.size(), data.min_swords, "松开后不继续无限补剑")
	var angles: Array[float] = []
	for sword in data.swords:
		angles.append(float(sword["angle"]))
	angles.sort()
	for index in range(angles.size()):
		var step := angles[(index + 1) % angles.size()] - angles[index]
		if step < 0.0:
			step += TAU
		t.assert_true(absf(step - TAU / data.min_swords) < 0.0001, "快速六剑也均匀绕完整圆")
	t.assert_true(_idle(scene), "快点完整释放并结束")
	t.assert_eq(data.launched_total, data.min_swords, "快速六剑全部发射")
	t.assert_eq(data.completed_total, data.min_swords, "快速六剑全部接地消散")


static func _test_configurable_slots(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as HeavenlySwordWheelComponent
	data.inner_swords = 13
	data.max_swords = 38
	_hold(scene, 140)
	var slots: Dictionary = {}
	for sword in data.swords:
		var key := "%d/%.4f" % [int(sword["ring"]), float(sword["angle"])]
		t.assert_false(slots.has(key), "奇数层剑数也不重叠槽位")
		slots[key] = true
	t.assert_eq(slots.size(), data.max_swords, "调整剑数后所有槽位仍独立")


static func _test_entry_and_turn_continuity(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as HeavenlySwordWheelComponent
	_hold(scene, 0)
	var last_position: Vector3 = data.swords[0]["position"]
	var last_forward: Vector3 = data.swords[0]["forward"]
	var max_step := 0.0
	var minimum_dot := 1.0
	for index in range(40):
		(scene["manager"] as CapabilityManager).tick(DT)
		var sword: Dictionary = data.swords[0]
		max_step = maxf(max_step, last_position.distance_to(sword["position"]))
		minimum_dot = minf(minimum_dot, last_forward.dot(sword["forward"]))
		last_position = sword["position"]
		last_forward = sword["forward"]
	t.assert_true(max_step < 0.16, "入阵逐 tick 连续，无传送（最大 %.4fm）" % max_step)
	t.assert_true(minimum_dot > 0.94, "入阵剑尖连续转动")
	_release(scene)
	t.assert_true(_wait_phase(scene, "turn"), "完整成阵进入转剑阶段")
	var from: Vector3 = data.swords[0]["position"]
	last_forward = data.swords[0]["forward"]
	minimum_dot = 1.0
	for index in range(int(ceil(data.turn_time / DT))):
		(scene["manager"] as CapabilityManager).tick(DT)
		var sword: Dictionary = data.swords[0]
		t.assert_true(from.distance_to(sword["position"]) < 0.0001, "转向时剑格稳定悬停")
		minimum_dot = minf(minimum_dot, last_forward.dot(sword["forward"]))
		last_forward = sword["forward"]
	t.assert_true(minimum_dot > 0.92, "释放转向没有突然翻剑")


static func _test_flight_tangent_acceleration_and_contact(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as HeavenlySwordWheelComponent
	_hold(scene, 80)
	_release(scene)
	t.assert_true(_wait_phase(scene, "volley"), "转向结束后进入齐射")
	var early_speed := 0.0
	var middle_speed := 0.0
	var tangent_min := 1.0
	var last_position: Vector3 = data.swords[0]["position"]
	var tested_contact := false
	for index in range(120):
		(scene["manager"] as CapabilityManager).tick(DT)
		if data.swords.is_empty():
			break
		var sword: Dictionary = data.swords[0]
		if sword["state"] == "fly":
			var progress := (data.logic_time - float(sword["launched_at"])) / float(sword["flight_time"])
			var movement := (sword["position"] as Vector3) - last_position
			if movement.length_squared() > 0.000001:
				tangent_min = minf(tangent_min, movement.normalized().dot(sword["forward"]))
			if progress > 0.04 and progress < 0.12:
				early_speed = maxf(early_speed, movement.length() / DT)
			if progress > 0.4 and progress < 0.6:
				middle_speed = maxf(middle_speed, movement.length() / DT)
		elif sword["state"] == "settle":
			var tip := (sword["position"] as Vector3) + (sword["forward"] as Vector3) \
				* SwordSpellVisual.TIP_LENGTH * (sword["scale"] as Vector3).z
			t.assert_true(tip.distance_to(sword["target"]) < 0.0001, "剑尖终点准确接地")
			t.assert_true(absf(tip.y) < 0.0001, "地平落点不穿入地下")
			tested_contact = true
			break
		last_position = sword["position"]
	t.assert_true(tangent_min > 0.94, "剑尖沿运动切线，没有反飞（最小点积 %.4f）" % tangent_min)
	t.assert_true(early_speed > 0.0 and middle_speed > early_speed * 1.2,
		"离阵慢、中段加速（%.3f → %.3f m/s）" % [early_speed, middle_speed])
	t.assert_true(tested_contact, "观察到接地阶段")
	t.assert_true(data.launched_total > data.group_size, "齐射按组推进而非一次全发")


static func _test_hits_and_dedup(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as HeavenlySwordWheelComponent
	var host := Node3D.new()
	var target := SwordTargetComponent.new()
	target.radius = 1.2
	host.add_child(target)
	host.add_to_group(&"sword_target")
	t.track(host)
	host.global_position = Vector3(0.0, 0.0, -8.0)
	_hold(scene, 100)
	_release(scene)
	t.assert_true(_idle(scene), "长招在有限逻辑时间内结束")
	t.assert_eq(target.hit_count, data.max_swords, "每剑沿途命中一次，接地不重复命中")
	t.assert_eq(target.last_hit_form, SwordCastComponent.FORM_WHEEL, "命中登记独立招式标识")
	t.assert_true((scene["cast"] as SwordCastComponent).feedback_serial > 0, "命中发出轻反馈数据请求")
	t.assert_true(data.swords.is_empty() and data.impacts.is_empty(), "结束无残留剑或冲击")


static func _test_elevated_contact(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	cast.aim_surface_point = Vector3(0.0, 3.0, -8.0)
	_hold(scene, 80)
	_release(scene)
	t.assert_true(_wait_phase(scene, "volley"), "高台指向进入齐射")
	var data := scene["data"] as HeavenlySwordWheelComponent
	var downwards := true
	var on_surface := true
	for sword in data.swords:
		var end_direction := ((sword["curve_to"] as Vector3) - (sword["control_b"] as Vector3)).normalized()
		downwards = downwards and end_direction.dot(sword["normal"]) < -0.5
		var tip := (sword["curve_to"] as Vector3) + end_direction * SwordSpellVisual.TIP_LENGTH * data.display_scale
		on_surface = on_surface and absf(tip.y - 3.0) < 0.0001
	t.assert_true(downwards, "所有高台落剑末段从上方接地")
	t.assert_true(on_surface, "每把剑保持真实高台高度")
	t.assert_true(_idle(scene), "高台施法完整结束")


static func _test_close_point_motion(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	cast.aim_point = Vector3(0.0, 0.0, -0.15)
	cast.aim_surface_point = cast.aim_point
	_hold(scene, 80)
	_release(scene)
	t.assert_true(_wait_phase(scene, "volley"), "近距离指向进入齐射")
	var data := scene["data"] as HeavenlySwordWheelComponent
	var non_reversing := true
	for sword in data.swords:
		var start: Vector3 = sword["curve_from"]
		var endpoint: Vector3 = sword["curve_to"]
		var flat := endpoint - start
		flat.y = 0.0
		var direction := flat.normalized()
		var last := 0.0
		for index in range(101):
			var point := HeavenlySwordWheel._curve(sword, float(index) / 100.0)
			var forward_distance := (point - start).dot(direction)
			non_reversing = non_reversing and forward_distance + 0.0001 >= last
			last = forward_distance
	t.assert_true(non_reversing, "近点曲线不越过落点再反飞")
	t.assert_true(_idle(scene), "近距离全部剑接地消散")


static func _test_switch_before_release(t) -> void:
	t.begin_case()
	var scene := _build(t)
	_hold(scene, 15)
	(scene["cast"] as SwordCastComponent).form = SwordCastComponent.FORM_GIANT
	(scene["manager"] as CapabilityManager).tick(DT)
	t.assert_false((scene["wheel"] as HeavenlySwordWheel).active, "蓄势时换招取消")
	t.assert_true((scene["data"] as HeavenlySwordWheelComponent).swords.is_empty(), "取消清空未发射剑群")


static func _test_switch_after_release(t) -> void:
	t.begin_case()
	var scene := _build(t)
	_hold(scene, 60)
	_release(scene)
	var cast := scene["cast"] as SwordCastComponent
	cast.form = SwordCastComponent.FORM_RAIN
	cast.pose_kind = SwordCastComponent.POSE_RAIN
	cast.face_direction = Vector3.RIGHT
	t.assert_true(_idle(scene), "松开后换招仍完成天轮齐射")
	t.assert_eq((scene["data"] as HeavenlySwordWheelComponent).completed_total,
		(scene["data"] as HeavenlySwordWheelComponent).max_swords, "后台全部剑自然消散")
	t.assert_eq(cast.pose_kind, SwordCastComponent.POSE_RAIN, "后台天轮不抢另一招姿势")
	t.assert_eq(cast.face_direction, Vector3.RIGHT, "后台天轮不抢另一招朝向")


static func _test_generation_cancel(t) -> void:
	t.begin_case()
	var scene := _build(t)
	_hold(scene, 70)
	_release(scene)
	_wait_phase(scene, "volley")
	(scene["cast"] as SwordCastComponent).request_cancel()
	(scene["manager"] as CapabilityManager).tick(DT)
	var data := scene["data"] as HeavenlySwordWheelComponent
	t.assert_false((scene["wheel"] as HeavenlySwordWheel).active, "取消序号变化当 tick 失活")
	t.assert_true(data.swords.is_empty() and data.impacts.is_empty() and data.ring_alpha == 0.0,
		"重置/失焦清剑、尾迹和法环")


static func _test_exit_cleanup(t) -> void:
	t.begin_case()
	var scene := _build(t)
	_hold(scene, 30)
	var wheel := scene["wheel"] as HeavenlySwordWheel
	wheel.get_parent().remove_child(wheel)
	wheel.free()
	var data := scene["data"] as HeavenlySwordWheelComponent
	t.assert_true(data.swords.is_empty() and data.impacts.is_empty() and data.phase == "idle",
		"卸载/退出树立即清理本包数据")


static func _test_cooldown(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as HeavenlySwordWheelComponent
	_hold(scene, 0)
	_release(scene)
	_idle(scene)
	var before := data.casts_total
	_hold(scene, 0)
	t.assert_eq(data.casts_total, before, "消散后冷却拒绝再施法")
	_release(scene)
	for index in range(int(ceil(data.cooldown / DT)) + 1):
		(scene["manager"] as CapabilityManager).tick(DT)
	_hold(scene, 0)
	t.assert_eq(data.casts_total, before + 1, "冷却后允许下一次结阵")


static func _test_repeat_and_clock(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as HeavenlySwordWheelComponent
	for repeat in range(3):
		_hold(scene, 0)
		_release(scene)
		t.assert_true(_idle(scene), "重复短招都有有限结束")
		for index in range(int(ceil(data.cooldown / DT)) + 2):
			(scene["manager"] as CapabilityManager).tick(DT)
	t.assert_eq(data.casts_total, 3, "三次完整结阵统计正确")
	t.assert_true(data.swords.is_empty() and data.impacts.is_empty(), "重复施法没有遗留叠加")
	t.assert_true(absf(data.logic_time - (scene["manager"] as CapabilityManager).elapsed) <= data.cooldown + DT * 4.0,
		"时序来自 manager 逻辑时钟")


static func _test_view_reads_data(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var view := HeavenlySwordWheelView.new()
	(scene["host"] as Node3D).add_child(view)
	view.bind(scene["data"])
	view.set_process(false)
	_hold(scene, 80)
	var data := scene["data"] as HeavenlySwordWheelComponent
	var before := data.swords.duplicate(true)
	view._process(DT)
	t.assert_eq(data.swords, before, "表现只读天轮组件")
	var mm := view.get_node("WheelSwords") as MultiMeshInstance3D
	t.assert_eq(mm.multimesh.visible_instance_count, data.swords.size(), "批量绘制所有悬剑")
	(scene["cast"] as SwordCastComponent).request_cancel()
	(scene["manager"] as CapabilityManager).tick(DT)
	view._process(DT)
	t.assert_eq(mm.multimesh.visible_instance_count, 0, "取消后视图同帧隐藏所有剑")
