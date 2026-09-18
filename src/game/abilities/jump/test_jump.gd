extends RefCounted
## test_jump：跳跃能力配对测试。
## 覆盖：边沿+着地才激活、单帧冲量、按住不连跳、空中不激活、被御剑阻塞、缺组件不崩溃。
##
## 本能力只写 vertical_impulse 意图；重力与 move_and_slide 由 Swordsman 根节点负责。

const JUMP_SPEED := 6.0


static func run(t) -> void:
	_test_edge_and_floor_activates(t)
	_test_single_frame_impulse(t)
	_test_requires_floor(t)
	_test_requires_edge(t)
	_test_blocked_while_sword_flight(t)
	_test_missing_component_is_inert(t)
	_test_priority(t)


static func _build(t) -> Dictionary:
	var host := CharacterBody3D.new()
	t.track(host)
	var motion := SwordsmanMotionComponent.new()
	motion.jump_speed = JUMP_SPEED
	host.add_child(motion)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var jump := Jump.new()
	manager.add_child(jump)
	return {"host": host, "motion": motion, "manager": manager, "jump": jump}


static func _test_edge_and_floor_activates(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var jump := scene["jump"] as Jump

	motion.on_floor = true
	motion.jump_pressed = true
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_true(jump.active, "着地且按下空格时应激活")
	t.assert_eq(motion.vertical_impulse, JUMP_SPEED, "应写入 jump_speed 冲量")


static func _test_single_frame_impulse(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var jump := scene["jump"] as Jump
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = true
	motion.jump_pressed = true
	manager.tick(0.016)
	t.assert_true(jump.active, "第一帧应激活")
	manager.tick(0.016)
	t.assert_false(jump.active, "冲量发出后下一 tick 应失活（单帧发射器）")


static func _test_requires_floor(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var jump := scene["jump"] as Jump

	motion.on_floor = false
	motion.jump_pressed = true
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_false(jump.active, "空中不得起跳")
	t.assert_eq(motion.vertical_impulse, 0.0, "空中不写冲量")


static func _test_requires_edge(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var jump := scene["jump"] as Jump
	var manager := scene["manager"] as CapabilityManager

	motion.on_floor = true
	motion.jump_pressed = true
	manager.tick(0.016)
	# 模拟 actor 帧末清零后仍按住空格：不产生第二个冲量。
	motion.vertical_impulse = 0.0
	motion.jump_pressed = false
	manager.tick(0.016)
	t.assert_false(jump.active, "按住空格不得连跳（只认按下边沿）")
	t.assert_eq(motion.vertical_impulse, 0.0, "无新边沿时不写冲量")


static func _test_blocked_while_sword_flight(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var jump := scene["jump"] as Jump
	var host := scene["host"] as CharacterBody3D
	var blocker := Node.new()
	t.track(blocker)

	TagRegistry.add_block(host, &"sword_flight_block", blocker)
	motion.on_floor = true
	motion.jump_pressed = true
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_false(jump.active, "御剑期间不得起跳")
	t.assert_eq(motion.vertical_impulse, 0.0, "御剑期间不写冲量")


static func _test_missing_component_is_inert(t) -> void:
	t.begin_case()
	var host := CharacterBody3D.new()
	t.track(host)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var jump := Jump.new()
	manager.add_child(jump)

	manager.tick(0.016)
	t.assert_false(jump.active, "缺少组件时不应激活")


static func _test_priority(t) -> void:
	t.begin_case()
	var jump := Jump.new()
	t.track(jump)
	t.assert_eq(jump.priority, 50, "Jump 优先级必须低于 SwordFlight、高于 Movement")
