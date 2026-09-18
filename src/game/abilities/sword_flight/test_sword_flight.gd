extends RefCounted
## test_sword_flight：御剑飞行能力配对测试。
## 覆盖：开关边沿、地面升起窗口、空中首帧动量、升降/悬停、水平速度、
## sword_flight_block 的 add/remove 与 instigator 隔离、_exit_tree 清账、
## 外部 reset 后下一 tick 清账、缺组件不崩溃。
##
## 本能力只写意图；重力与 move_and_slide 由 Swordsman 根节点负责。

const TAG := &"sword_flight_block"


static func run(t) -> void:
	_test_toggle_on_from_ground(t)
	_test_launch_window_ends(t)
	_test_airborne_first_tick_keeps_momentum(t)
	_test_lift_sink_hover(t)
	_test_horizontal_uses_flight_speed(t)
	_test_toggle_off_clears_block(t)
	_test_external_flight_active_false_clears_block(t)
	_test_exit_tree_clears_block_and_state(t)
	_test_instigator_isolation(t)
	_test_missing_component_is_inert(t)
	_test_priority(t)


static func _build(t) -> Dictionary:
	var host := CharacterBody3D.new()
	t.track(host)
	var motion := SwordsmanMotionComponent.new()
	host.add_child(motion)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var flight := SwordFlight.new()
	manager.add_child(flight)
	return {"host": host, "motion": motion, "manager": manager, "flight": flight}


static func _test_toggle_on_from_ground(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var flight := scene["flight"] as SwordFlight
	var host := scene["host"] as CharacterBody3D

	motion.on_floor = true
	motion.flight_toggle_pressed = true
	motion.vertical_input = 0.0
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_true(flight.active, "F 边沿应开启御剑")
	t.assert_true(motion.flight_active, "开启后组件 flight_active 为真")
	t.assert_true(TagRegistry.is_blocked(host, TAG), "御剑期间应阻塞普通移动与跳跃")
	t.assert_eq(motion.desired_vertical, 3.0, "地面启动当帧取 flight_launch_speed")


static func _test_launch_window_ends(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = true
	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	motion.flight_toggle_pressed = false
	motion.vertical_input = 0.0
	manager.tick(0.5)
	t.assert_eq(motion.desired_vertical, 0.0, "升起窗口结束后松键应悬停")

	motion.vertical_input = 1.0
	manager.tick(0.016)
	t.assert_eq(motion.desired_vertical, 7.0, "按住空格应上升")
	t.assert_true(motion.flight_active, "升降输入不影响御剑状态")


static func _test_airborne_first_tick_keeps_momentum(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var flight := scene["flight"] as SwordFlight
	var host := scene["host"] as CharacterBody3D
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = false
	motion.flight_toggle_pressed = true
	host.velocity = Vector3(0.0, 4.0, 0.0)
	manager.tick(0.016)
	t.assert_eq(motion.desired_vertical, 4.0, "空中首帧应保留上升动量")

	motion.flight_toggle_pressed = false
	motion.move_input = Vector2.ZERO
	manager.tick(0.016)
	t.assert_eq(motion.desired_vertical, 0.0, "第二帧起由升降输入接管（松键悬停）")

	# 外部复位（R）当帧只做失活清账，同一 tick 的 F 边沿会被消耗；重新开启需下一 tick。
	host.velocity = Vector3(0.0, -50.0, 0.0)
	motion.flight_active = false
	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	t.assert_false(flight.active, "外部复位当帧先失活清账")

	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	t.assert_true(flight.active, "下一 tick 可重新开启御剑")
	t.assert_eq(motion.desired_vertical, -7.0, "极端下坠动量限幅到 flight_sink_speed")


static func _test_lift_sink_hover(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = false
	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	motion.flight_toggle_pressed = false

	motion.vertical_input = 1.0
	manager.tick(0.016)
	t.assert_eq(motion.desired_vertical, 7.0, "vertical_input=+1 应上升")

	motion.vertical_input = -1.0
	manager.tick(0.016)
	t.assert_eq(motion.desired_vertical, -7.0, "vertical_input=-1 应下降")

	motion.vertical_input = 0.0
	manager.tick(0.016)
	t.assert_eq(motion.desired_vertical, 0.0, "松键应悬停")


static func _test_horizontal_uses_flight_speed(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = false
	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	motion.flight_toggle_pressed = false
	motion.camera_right = Vector3.RIGHT
	motion.camera_forward = Vector3.FORWARD
	motion.move_input = Vector2(1.0, 0.0)
	manager.tick(0.016)
	t.assert_eq(motion.desired_horizontal, Vector3(12.0, 0.0, 0.0), "御剑水平速度应为 flight_speed 且沿相机基")


static func _test_toggle_off_clears_block(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var flight := scene["flight"] as SwordFlight
	var host := scene["host"] as CharacterBody3D
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = true
	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	t.assert_true(TagRegistry.is_blocked(host, TAG), "开启后应有阻塞")

	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	t.assert_false(flight.active, "再按 F 应失活")
	t.assert_false(motion.flight_active, "失活必须清 flight_active")
	t.assert_false(TagRegistry.is_blocked(host, TAG), "失活必须解除自己的阻塞")


static func _test_external_flight_active_false_clears_block(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var flight := scene["flight"] as SwordFlight
	var host := scene["host"] as CharacterBody3D
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = true
	motion.flight_toggle_pressed = true
	manager.tick(0.016)

	# 模拟 reset_motion()：外部把 flight_active 置 false，下一 tick 能力自行清账。
	motion.flight_active = false
	manager.tick(0.016)
	t.assert_false(flight.active, "外部复位后应失活")
	t.assert_false(TagRegistry.is_blocked(host, TAG), "外部复位后阻塞须在下一 tick 清账")


static func _test_exit_tree_clears_block_and_state(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var host := scene["host"] as CharacterBody3D
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = true
	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	t.assert_true(TagRegistry.is_blocked(host, TAG), "开启后应有阻塞")

	# 模拟装配中直接删除御剑能力：移除后不得残留飞行状态与阻塞。
	# remove_child 只摘出场景树、不销毁对象；必须显式 free，否则本测试会遗留孤儿节点。
	var removed := scene["flight"] as SwordFlight
	manager.remove_child(removed)
	removed.free()
	t.assert_false(motion.flight_active, "_exit_tree 必须把 flight_active 置 false")
	t.assert_false(TagRegistry.is_blocked(host, TAG), "_exit_tree 必须移除自己的阻塞")


static func _test_instigator_isolation(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var host := scene["host"] as CharacterBody3D
	var manager := scene["manager"] as CapabilityManager
	var other := Node.new()
	t.track(other)

	TagRegistry.add_block(host, TAG, other)
	motion.on_floor = true
	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	motion.flight_toggle_pressed = true
	manager.tick(0.016)
	t.assert_true(TagRegistry.is_blocked(host, TAG), "解除飞行时不得移除其他 instigator 的阻塞")
	t.assert_eq(TagRegistry.block_count(host, TAG), 1, "只应剩其他 instigator 的 1 条阻塞")


static func _test_missing_component_is_inert(t) -> void:
	t.begin_case()
	var host := CharacterBody3D.new()
	t.track(host)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var flight := SwordFlight.new()
	manager.add_child(flight)

	manager.tick(0.016)
	t.assert_false(flight.active, "缺少组件时不应激活")


static func _test_priority(t) -> void:
	t.begin_case()
	var flight := SwordFlight.new()
	t.track(flight)
	t.assert_eq(flight.priority, 100, "SwordFlight 必须最先调度");
