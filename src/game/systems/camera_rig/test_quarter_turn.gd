extends RefCounted
## test_quarter_turn：quarter_turn（镜头模式 B）配对测试。
## 覆盖：模式互斥激活、Q/E 一步 ±90° 且按住不连续、转向平滑收敛、
## 投影区分的缩放、失活丢弃未完成步进、缺组件不崩溃。

const STEP := 90.0


static func run(t) -> void:
	_test_mode_gate(t)
	_test_single_step_is_half_turn(t)
	_test_held_input_does_not_repeat(t)
	_test_turn_is_distinct_from_continuous_yaw(t)
	_test_zoom_by_projection(t)
	_test_deactivation_drops_pending_step(t)
	_test_missing_component_is_inert(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var rig := CameraRigComponent.new()
	host.add_child(rig)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var mode := QuarterTurn.new()
	mode.turn_smooth_time = 0.0
	manager.add_child(mode)
	rig.mode_id = "quarter_turn"
	rig.turn_step_degrees = STEP
	return {"host": host, "rig": rig, "manager": manager, "mode": mode}


static func _test_mode_gate(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as QuarterTurn
	rig.mode_id = "fixed_follow"
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_false(mode.active, "mode_id 不是 quarter_turn 时不激活")
	rig.mode_id = "quarter_turn"
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_true(mode.active, "mode_id 为 quarter_turn 时激活")


static func _test_single_step_is_half_turn(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.yaw_degrees = 0.0
	rig.yaw_step_request = STEP
	manager.tick(0.016)
	t.assert_true(absf(rig.yaw_degrees - STEP) < 0.001, "一次请求转 %.0f°（实际 %.2f°）" % [STEP, rig.yaw_degrees])
	t.assert_true(is_zero_approx(rig.yaw_step_request), "步进请求被消费")


static func _test_held_input_does_not_repeat(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.yaw_degrees = 0.0
	# 按住不产生新请求：连续多帧没有 yaw_step_request 时角度不继续增长。
	for _index in range(30):
		manager.tick(0.016)
	t.assert_true(is_zero_approx(rig.yaw_degrees), "按住期间无新请求则不持续旋转（不会被连续轴驱动）")


static func _test_turn_is_distinct_from_continuous_yaw(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	# 同一帧：continuous yaw_input 对 quarter_turn 无效，只有离散步进生效。
	rig.yaw_degrees = 0.0
	rig.yaw_input = 1.0
	rig.yaw_speed_degrees = 90.0
	manager.tick(1.0)
	t.assert_true(is_zero_approx(rig.yaw_degrees), "quarter_turn 不消费连续偏航输入（与 orbit 区分）")


static func _test_zoom_by_projection(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.projection = Camera3D.PROJECTION_ORTHOGONAL
	rig.size = 20.0
	rig.zoom_step = 2.0
	rig.zoom_steps = 1.0
	manager.tick(0.016)
	t.assert_true(absf(rig.size - 18.0) < 0.001, "正交：缩放改 size（%.1f）" % rig.size)

	rig.projection = Camera3D.PROJECTION_PERSPECTIVE
	rig.distance = 20.0
	rig.distance_min = 6.0
	rig.distance_max = 60.0
	rig.distance_step = 1.5
	rig.zoom_steps = 2.0
	manager.tick(0.016)
	t.assert_true(absf(rig.distance - 17.0) < 0.001, "透视：缩放改 distance（%.2f）" % rig.distance)


static func _test_deactivation_drops_pending_step(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as QuarterTurn
	var manager := scene["manager"] as CapabilityManager
	mode.turn_smooth_time = 1.0
	manager.tick(0.016)
	t.assert_true(mode.active, "前置：quarter_turn 已激活")
	rig.yaw_step_request = STEP
	rig.mode_id = "orbit"
	manager.tick(0.016)
	t.assert_false(mode.active, "mode_id 改变后失活")
	t.assert_true(is_zero_approx(rig.yaw_step_request), "失活清掉未消费的步进请求")

	# 回到 quarter_turn 后不得补转旧步进。
	rig.mode_id = "quarter_turn"
	var yaw_before := rig.yaw_degrees
	manager.tick(0.016)
	t.assert_true(absf(rig.yaw_degrees - yaw_before) < 0.001, "重新进入后不补转退出前的步进")


static func _test_missing_component_is_inert(t) -> void:
	t.begin_case()
	var host := Node3D.new()
	t.track(host)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var mode := QuarterTurn.new()
	manager.add_child(mode)
	manager.tick(0.016)
	t.assert_false(mode.active, "缺少 CameraRigComponent 时不激活")