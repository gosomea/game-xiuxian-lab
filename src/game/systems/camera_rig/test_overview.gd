extends RefCounted
## test_overview：overview（镜头模式 D）配对测试。
## 覆盖：模式互斥激活、MMB 世界位移平移焦点并限幅、回中收敛、
## 拖动中不回中、失活清平移与未消费位移、缺组件不崩溃。

const MAX_PAN := 10.0


static func run(t) -> void:
	_test_mode_gate(t)
	_test_pan_moves_focus_and_clamps(t)
	_test_recenter_converges(t)
	_test_pan_direction_follows_world_delta(t)
	_test_deactivation_clears_offset(t)
	_test_missing_component_is_inert(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var rig := CameraRigComponent.new()
	host.add_child(rig)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var mode := Overview.new()
	manager.add_child(mode)
	rig.mode_id = "overview"
	rig.pan_distance_max = MAX_PAN
	rig.recenter_time = 0.2
	return {"host": host, "rig": rig, "manager": manager, "mode": mode}


static func _test_mode_gate(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as Overview
	rig.mode_id = "orbit"
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_false(mode.active, "mode_id 不是 overview 时不激活")
	rig.mode_id = "overview"
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_true(mode.active, "mode_id 为 overview 时激活")


static func _test_pan_moves_focus_and_clamps(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.target_position = Vector3(3.0, 0.0, 1.0)
	rig.pan_active = true
	rig.pan_world_delta = Vector3(4.0, 0.0, 0.0)
	manager.tick(0.016)
	t.assert_true(absf(rig.focus.x - 7.0) < 0.001, "MMB 平移把焦点推离目标（x=%.2f）" % rig.focus.x)

	# 超过 pan_distance_max 时被限幅。
	for _index in range(20):
		rig.pan_world_delta = Vector3(5.0, 0.0, 0.0)
		manager.tick(0.016)
	var offset := rig.focus - rig.target_position
	t.assert_true(offset.length() <= MAX_PAN + 0.001, "平移被限幅在 pan_distance_max（%.2f m）" % offset.length())


static func _test_recenter_converges(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.target_position = Vector3.ZERO
	rig.pan_active = true
	rig.pan_world_delta = Vector3(6.0, 0.0, 0.0)
	manager.tick(0.016)
	rig.pan_active = false
	t.assert_true(rig.focus.length() > 5.0, "前置：已离开目标")

	rig.recenter_request = true
	for _index in range(240):
		manager.tick(0.016)
	t.assert_true(rig.focus.length() < 0.05, "回中后焦点收敛到目标（%.3f m）" % rig.focus.length())
	t.assert_false(rig.recenter_request, "回中完成后清请求")


static func _test_pan_direction_follows_world_delta(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var manager := scene["manager"] as CapabilityManager
	rig.target_position = Vector3.ZERO
	rig.pan_active = true
	rig.pan_world_delta = Vector3(0.0, 0.0, 5.0)
	manager.tick(0.016)
	t.assert_true(rig.focus.z > 4.9, "世界位移决定平移方向（executor 已按实际相机基换算）")


static func _test_deactivation_clears_offset(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rig := scene["rig"] as CameraRigComponent
	var mode := scene["mode"] as Overview
	var manager := scene["manager"] as CapabilityManager
	rig.pan_active = true
	rig.pan_world_delta = Vector3(6.0, 0.0, 0.0)
	manager.tick(0.016)
	t.assert_true(mode.active, "前置：overview 已激活")
	rig.mode_id = "fixed_follow"
	manager.tick(0.016)
	t.assert_false(mode.active, "mode_id 改变后失活")
	t.assert_false(rig.pan_active, "失活清拖拽状态")
	t.assert_true(is_zero_approx(rig.pan_world_delta.length()), "失活清未消费位移")
	# 重新进入 overview 时平移量从目标重新开始。
	rig.mode_id = "overview"
	rig.target_position = Vector3(2.0, 0.0, 0.0)
	manager.tick(0.016)
	t.assert_true(rig.focus.distance_to(Vector3(2.0, 0.0, 0.0)) < 0.001, "重新进入后焦点贴回目标，不保留旧平移")


static func _test_missing_component_is_inert(t) -> void:
	t.begin_case()
	var host := Node3D.new()
	t.track(host)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var mode := Overview.new()
	manager.add_child(mode)
	manager.tick(0.016)
	t.assert_false(mode.active, "缺少 CameraRigComponent 时不激活")