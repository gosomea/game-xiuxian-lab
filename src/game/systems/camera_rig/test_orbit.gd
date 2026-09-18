extends RefCounted
## test_orbit：orbit（镜头模式 C）配对测试。
## 覆盖：模式互斥激活、RMB 拖拽改偏航与受限俯角、鼠标像素位移不乘帧时长、
## 键盘偏航乘帧时长、滚轮缩放、失活丢弃未消费位移但不改 yaw/pitch、缺组件不崩溃。

const SENSITIVITY := 0.18


static func run(t) -> void:
	_test_mode_gate(t)
	_test_drag_changes_yaw_and_clamped_pitch(t)
	_test_pixel_delta_not_scaled_by_delta(t)
	_test_keyboard_yaw_scales_with_delta(t)
	_test_zoom_and_soft_follow(t)
	_test_perspective_zoom_changes_distance(t)
	_test_deactivation_keeps_orientation(t)
	_test_no_look_delta_leak_between_modes(t)
	_test_missing_component_is_inert(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var rig := CameraRigComponent.new()
	host.add_child(rig)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var mode := Orbit.new()
	manager.add_child(mode)
	rig.mode_id = "orbit"
	return {"host": host, "rig": rig, "manager": manager, "mode": mode}


static func _test_mode_gate(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as Orbit
	rig.mode_id = "fixed_follow"
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_false(mode.active, "mode_id 不是 orbit 时不激活")
	rig.mode_id = "orbit"
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_true(mode.active, "mode_id 为 orbit 时激活")


static func _test_drag_changes_yaw_and_clamped_pitch(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.yaw_degrees = 0.0
	rig.pitch_degrees = 40.0
	rig.pitch_min_degrees = 12.0
	rig.pitch_max_degrees = 78.0
	rig.drag_active = true
	rig.look_delta = Vector2(100.0, 0.0)
	manager.tick(0.016)
	t.assert_true(absf(rig.yaw_degrees - 100.0 * SENSITIVITY) < 0.001, "横向拖拽按灵敏度改偏航（%.2f°）" % rig.yaw_degrees)
	t.assert_true(is_zero_approx(rig.look_delta.x), "位移被消费")

	rig.look_delta = Vector2(0.0, 10000.0)
	manager.tick(0.016)
	t.assert_true(absf(rig.pitch_degrees - rig.pitch_max_degrees) < 0.001, "俯角被限幅在 pitch_max")
	rig.look_delta = Vector2(0.0, -10000.0)
	manager.tick(0.016)
	t.assert_true(absf(rig.pitch_degrees - rig.pitch_min_degrees) < 0.001, "俯角被限幅在 pitch_min")


static func _test_pixel_delta_not_scaled_by_delta(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.drag_active = true
	rig.yaw_degrees = 0.0
	rig.look_delta = Vector2(50.0, 0.0)
	manager.tick(1.0 / 60.0)
	var slow_frame_yaw := rig.yaw_degrees
	rig.yaw_degrees = 0.0
	rig.look_delta = Vector2(50.0, 0.0)
	manager.tick(0.5)
	t.assert_true(absf(rig.yaw_degrees - slow_frame_yaw) < 0.001,
		"相同像素位移在不同帧长下产生相同旋转（%.3f° vs %.3f°）" % [slow_frame_yaw, rig.yaw_degrees])


static func _test_keyboard_yaw_scales_with_delta(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.yaw_degrees = 0.0
	rig.yaw_speed_degrees = 90.0
	rig.yaw_input = 1.0
	manager.tick(0.25)
	t.assert_true(absf(rig.yaw_degrees - 22.5) < 0.001, "键盘偏航乘帧时长（%.2f°）" % rig.yaw_degrees)


static func _test_zoom_and_soft_follow(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.size = 24.0
	rig.zoom_step = 2.0
	rig.zoom_steps = 1.0
	rig.target_position = Vector3(7.0, 0.0, -3.0)
	manager.tick(0.016)
	t.assert_true(absf(rig.size - 22.0) < 0.001, "滚轮缩放被消费（size %.1f）" % rig.size)
	t.assert_eq(rig.focus, Vector3(7.0, 0.0, -3.0), "环绕模式仍软跟随目标（焦点贴目标）")
	t.assert_eq(rig.lookahead, Vector3.ZERO, "环绕模式不产生前视")


## 透视投影下 orbit 的滚轮必须改 distance（与本包其它模式同契约），不动正交 size。
static func _test_perspective_zoom_changes_distance(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.projection = Camera3D.PROJECTION_PERSPECTIVE
	rig.distance = 20.0
	rig.distance_min = 6.0
	rig.distance_max = 60.0
	rig.distance_step = 1.5
	rig.size = 24.0
	rig.zoom_steps = 1.0
	manager.tick(0.016)
	t.assert_true(absf(rig.distance - 18.5) < 0.001, "透视：orbit 滚轮改 distance（%.2f）" % rig.distance)
	t.assert_true(absf(rig.size - 24.0) < 0.001, "透视：orbit 不动正交 size（%.2f）" % rig.size)

	# 上下限：连续拉近 / 拉远都停在声明范围。
	for _index in range(40):
		rig.zoom_steps = 1.0
		manager.tick(0.016)
	t.assert_true(rig.distance >= rig.distance_min - 0.001, "透视：连续拉近限幅在 distance_min（%.2f）" % rig.distance)
	for _index in range(80):
		rig.zoom_steps = -1.0
		manager.tick(0.016)
	t.assert_true(rig.distance <= rig.distance_max + 0.001, "透视：连续拉远限幅在 distance_max（%.2f）" % rig.distance)

	# 正交分支不受影响（回归：不能让透视改动破坏 size 缩放）。
	rig.projection = Camera3D.PROJECTION_ORTHOGONAL
	rig.size = 24.0
	rig.zoom_steps = 2.0
	manager.tick(0.016)
	t.assert_true(absf(rig.size - 20.0) < 0.001, "切回正交：仍改 size（%.2f）" % rig.size)


static func _test_deactivation_keeps_orientation(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as Orbit
	var manager := scene["manager"] as CapabilityManager
	rig.drag_active = true
	manager.tick(0.016)
	t.assert_true(mode.active, "前置：orbit 在自身模式下已激活")

	# 模拟交接给 fixed_follow：先留下未消费的位移与拖拽状态，再切换 mode_id。
	rig.yaw_degrees = 33.0
	rig.pitch_degrees = 55.0
	rig.look_delta = Vector2(20.0, 20.0)
	rig.drag_active = true
	rig.mode_id = "fixed_follow"
	manager.tick(0.016)
	t.assert_false(mode.active, "mode_id 改变后 orbit 失活")
	t.assert_eq(rig.look_delta, Vector2.ZERO, "失活丢弃未消费的鼠标位移")
	t.assert_false(rig.drag_active, "失活清拖拽状态")
	t.assert_true(absf(rig.yaw_degrees - 33.0) < 0.001 and absf(rig.pitch_degrees - 55.0) < 0.001,
		"失活保留 yaw / pitch 供接管模式继续使用")


## 模式切换不得把旧模式未消费的鼠标位移带到新模式（避免"切换后突然转一大下"）。
static func _test_no_look_delta_leak_between_modes(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as Orbit
	var manager := scene["manager"] as CapabilityManager
	# orbit 激活并留下未消费位移，然后切到 fixed_follow。
	manager.tick(0.016)
	t.assert_true(mode.active, "前置：orbit 已激活")
	rig.drag_active = true
	rig.look_delta = Vector2(200.0, 0.0)
	rig.mode_id = "fixed_follow"
	var yaw_before := rig.yaw_degrees
	manager.tick(0.016)
	t.assert_true(is_zero_approx(rig.look_delta.x) and is_zero_approx(rig.look_delta.y),
		"orbit 失活丢弃未消费位移")
	t.assert_true(absf(rig.yaw_degrees - yaw_before) < 0.001, "切换当帧不把旧位移应用成旋转")


static func _test_missing_component_is_inert(t) -> void:
	t.begin_case()
	var host := Node3D.new()
	t.track(host)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var mode := Orbit.new()
	manager.add_child(mode)
	manager.tick(0.016)
	t.assert_false(mode.active, "缺少 CameraRigComponent 时不激活")