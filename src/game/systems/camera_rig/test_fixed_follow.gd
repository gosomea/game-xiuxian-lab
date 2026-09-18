extends RefCounted
## test_fixed_follow：fixed_follow（镜头模式 A）配对测试。
## 覆盖：模式互斥激活、四种预设的焦点策略（硬 / 平滑 / 死区 / 前视）、
## 前视只在 lookahead 产生、缩放与限幅、键盘偏航乘帧时长、失活只清自己写的字段、
## 缺组件不崩溃。本能力不写 Camera3D，断言只读 CameraRigComponent。

const HARD := "hard"
const SMOOTH := "smooth"
const DEADZONE := "deadzone"
const LOOKAHEAD := "lookahead"


static func run(t) -> void:
	_test_mode_gate(t)
	_test_hard_preset_focus_tracks_target(t)
	_test_smooth_preset_lags_then_converges(t)
	_test_deadzone_holds_inside_and_pushes_outside(t)
	_test_lookahead_only_in_lookahead_preset(t)
	_test_zoom_applies_and_clamps(t)
	_test_keyboard_yaw_scales_with_delta(t)
	_test_deactivation_only_clears_own_fields(t)
	_test_missing_component_is_inert(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var rig := CameraRigComponent.new()
	host.add_child(rig)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var mode := FixedFollow.new()
	manager.add_child(mode)
	rig.mode_id = "fixed_follow"
	return {"host": host, "rig": rig, "manager": manager, "mode": mode}


static func _test_mode_gate(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as FixedFollow
	rig.mode_id = "orbit"
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_false(mode.active, "mode_id 不是 fixed_follow 时不得激活")

	rig.mode_id = "fixed_follow"
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_true(mode.active, "mode_id 为 fixed_follow 时激活")


static func _test_hard_preset_focus_tracks_target(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.follow_preset = HARD
	rig.target_position = Vector3(3.0, 0.5, -2.0)
	manager.tick(0.016)
	t.assert_eq(rig.focus, Vector3(3.0, 0.5, -2.0), "硬跟随：焦点立即等于目标位置")
	t.assert_eq(rig.lookahead, Vector3.ZERO, "硬跟随：无前视")


static func _test_smooth_preset_lags_then_converges(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.follow_preset = SMOOTH
	rig.smooth_time = 0.35
	rig.target_position = Vector3(10.0, 0.0, 0.0)
	manager.tick(0.016)
	var lag := rig.focus.distance_to(rig.target_position)
	t.assert_true(lag > 0.05, "平滑跟随：首帧焦点落后（%.3f m）" % lag)
	for _index in range(240):
		manager.tick(0.016)
	t.assert_true(rig.focus.distance_to(rig.target_position) < 0.05, "平滑跟随：足够帧数后收敛")


static func _test_deadzone_holds_inside_and_pushes_outside(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.follow_preset = DEADZONE
	rig.focus = Vector3.ZERO
	rig.target_position = Vector3(1.0, 0.0, 0.5)
	manager.tick(0.016)
	t.assert_eq(rig.focus, Vector3.ZERO, "死区：目标在区内焦点不动")

	rig.target_position = Vector3(20.0, 0.0, 0.0)
	manager.tick(0.016)
	t.assert_true(rig.focus.distance_to(Vector3.ZERO) > 1.0, "死区：目标越界后焦点被拖动")
	t.assert_true(rig.focus.x < 20.0, "死区：焦点只拖到边界，不直接跳到目标")


static func _test_lookahead_only_in_lookahead_preset(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.follow_preset = HARD
	rig.target_velocity = Vector3(4.0, 0.0, 0.0)
	manager.tick(0.016)
	t.assert_eq(rig.lookahead, Vector3.ZERO, "硬跟随：速度非零也不产生前视")

	rig.follow_preset = LOOKAHEAD
	rig.target_position = Vector3(5.0, 0.0, 0.0)
	for _index in range(60):
		manager.tick(0.016)
	var lead := rig.lookahead
	t.assert_true(lead.length() > 0.5, "前视预设：按目标速度产生前视（%.3f m）" % lead.length())
	t.assert_true(lead.x > 0.0, "前视方向与目标速度同向")
	t.assert_true(lead.length() <= rig.lookahead_max + 0.001, "前视不超过限幅")

	rig.follow_preset = DEADZONE
	manager.tick(0.016)
	t.assert_eq(rig.lookahead, Vector3.ZERO, "切回死区：前视归零")


static func _test_zoom_applies_and_clamps(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.size = 24.0
	rig.zoom_step = 2.0
	rig.size_min = 8.0
	rig.size_max = 44.0
	rig.zoom_steps = 2.0
	manager.tick(0.016)
	t.assert_true(absf(rig.size - 20.0) < 0.001, "正值缩放步拉近 size（%.1f）" % rig.size)
	t.assert_true(is_zero_approx(rig.zoom_steps), "缩放请求被消费并清零")

	for _index in range(40):
		rig.zoom_steps = 2.0
		manager.tick(0.016)
	t.assert_true(absf(rig.size - rig.size_min) < 0.001, "连续拉近被限幅在 size_min")


static func _test_keyboard_yaw_scales_with_delta(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.yaw_degrees = 0.0
	rig.yaw_speed_degrees = 90.0
	rig.yaw_input = 1.0
	manager.tick(0.5)
	t.assert_true(absf(rig.yaw_degrees - 45.0) < 0.001, "键盘偏航是角速度，乘帧时长（%.2f°）" % rig.yaw_degrees)
	rig.yaw_input = -1.0
	manager.tick(0.5)
	t.assert_true(absf(rig.yaw_degrees) < 0.001, "反向输入可回退")


static func _test_deactivation_only_clears_own_fields(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as FixedFollow
	var manager := scene["manager"] as CapabilityManager
	rig.follow_preset = LOOKAHEAD
	rig.target_position = Vector3(4.0, 0.0, 0.0)
	rig.target_velocity = Vector3(4.0, 0.0, 0.0)
	for _index in range(30):
		manager.tick(0.016)
	t.assert_true(mode.active and rig.lookahead.length() > 0.0, "前置：前视已产生")

	# 模拟交接给 orbit：模式互斥由 mode_id 决定，旧模式失活不得覆盖新模式的焦点/偏航。
	rig.focus = Vector3(99.0, 0.0, 0.0)
	rig.yaw_degrees = 123.0
	rig.mode_id = "orbit"
	manager.tick(0.016)
	t.assert_false(mode.active, "mode_id 改变后旧模式失活")
	t.assert_eq(rig.lookahead, Vector3.ZERO, "失活只清本能力写过的前视")
	t.assert_true(absf(rig.focus.x - 99.0) < 0.001, "失活不得覆盖接管模式写的焦点")
	t.assert_true(absf(rig.yaw_degrees - 123.0) < 0.001, "失活不得覆盖接管模式写的偏航")


static func _test_missing_component_is_inert(t) -> void:
	t.begin_case()
	var host := Node3D.new()
	t.track(host)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var mode := FixedFollow.new()
	manager.add_child(mode)
	manager.tick(0.016)
	t.assert_false(mode.active, "缺少 CameraRigComponent 时不激活")
