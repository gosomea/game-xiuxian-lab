extends RefCounted
## test_swordsman_movement：水平移动能力配对测试。
## 覆盖：idle 不激活、输入映射到相机地面基、斜向不加速、相机旋转后的映射、
## 失活不触碰宿主速度、被 sword_flight_block 阻塞、缺组件不崩溃。
##
## 本能力只写 desired_horizontal 意图，物理提交与重力合成由 Swordsman 根节点负责，
## 因此这里只断言意图，不断言位移（位移留给组合场景验收）。

const SPEED := 4.0


static func run(t) -> void:
	_test_idle_stays_inactive(t)
	_test_input_maps_to_camera_axes(t)
	_test_diagonal_not_faster(t)
	_test_rotated_camera_basis(t)
	_test_deactivation_leaves_host_velocity_alone(t)
	_test_blocked_while_sword_flight(t)
	_test_missing_component_is_inert(t)


static func _build(t) -> Dictionary:
	var host := CharacterBody3D.new()
	t.track(host)
	var motion := SwordsmanMotionComponent.new()
	motion.move_speed = SPEED
	host.add_child(motion)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var movement := SwordsmanMovement.new()
	manager.add_child(movement)
	return {"host": host, "motion": motion, "manager": manager, "movement": movement}


static func _test_idle_stays_inactive(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	(scene["manager"] as CapabilityManager).tick(0.016)
	t.assert_false((scene["movement"] as SwordsmanMovement).active, "无输入时移动能力不应激活")
	t.assert_eq(motion.desired_horizontal, Vector3.ZERO, "无输入时不写水平意图")


static func _test_input_maps_to_camera_axes(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var movement := scene["movement"] as SwordsmanMovement
	var manager := scene["manager"] as CapabilityManager

	motion.camera_right = Vector3.RIGHT
	motion.camera_forward = Vector3.FORWARD
	motion.move_input = Vector2(1.0, 0.0)
	manager.tick(0.016)
	t.assert_true(movement.active, "有输入时应激活")
	t.assert_eq(motion.desired_horizontal, Vector3(SPEED, 0.0, 0.0), "屏幕右应对应相机右方向")

	motion.move_input = Vector2(0.0, -1.0)
	manager.tick(0.016)
	t.assert_eq(motion.desired_horizontal, Vector3(0.0, 0.0, -SPEED), "屏幕上方应对应相机前方")

	motion.move_input = Vector2(0.0, 1.0)
	manager.tick(0.016)
	t.assert_eq(motion.desired_horizontal, Vector3(0.0, 0.0, SPEED), "屏幕下方应对应相机后方")


static func _test_diagonal_not_faster(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent

	motion.camera_right = Vector3.RIGHT
	motion.camera_forward = Vector3.FORWARD
	motion.move_input = Vector2(1.0, 1.0)
	(scene["manager"] as CapabilityManager).tick(0.016)

	t.assert_true(absf(motion.desired_horizontal.length() - SPEED) <= 0.001, "斜向意图不得高于 move_speed（实际 %f）" % motion.desired_horizontal.length())
	t.assert_true(is_zero_approx(motion.desired_horizontal.y), "水平意图的 y 必须为 0")


static func _test_rotated_camera_basis(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var manager := scene["manager"] as CapabilityManager

	# 相机绕 Y 轴旋转 90 度：前方指向 +X，右方指向 -Z。
	motion.camera_forward = Vector3.RIGHT
	motion.camera_right = Vector3.FORWARD
	motion.move_input = Vector2(0.0, -1.0)
	manager.tick(0.016)
	t.assert_eq(motion.desired_horizontal, Vector3(SPEED, 0.0, 0.0), "相机旋转后，屏幕上方跟随相机前方")

	motion.move_input = Vector2(1.0, 0.0)
	manager.tick(0.016)
	t.assert_eq(motion.desired_horizontal, Vector3(0.0, 0.0, -SPEED), "相机旋转后，屏幕右方跟随相机右方")


static func _test_deactivation_leaves_host_velocity_alone(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var host := scene["host"] as CharacterBody3D
	var manager := scene["manager"] as CapabilityManager

	motion.move_input = Vector2(1.0, 0.0)
	manager.tick(0.016)
	t.assert_true((scene["movement"] as SwordsmanMovement).active, "移动中应处于激活状态")

	# 宿主速度由 actor 维护；能力失活不得回写，避免踩掉同帧其他能力的合成结果。
	host.velocity = Vector3(9.0, 3.0, 0.0)
	motion.move_input = Vector2.ZERO
	manager.tick(0.016)
	t.assert_false((scene["movement"] as SwordsmanMovement).active, "输入归零后应失活")
	t.assert_eq(host.velocity, Vector3(9.0, 3.0, 0.0), "能力不得改写宿主速度")


static func _test_blocked_while_sword_flight(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var motion := scene["motion"] as SwordsmanMotionComponent
	var movement := scene["movement"] as SwordsmanMovement
	var manager := scene["manager"] as CapabilityManager
	var host := scene["host"] as CharacterBody3D
	var blocker := Node.new()
	t.track(blocker)

	motion.move_input = Vector2(1.0, 0.0)
	TagRegistry.add_block(host, &"sword_flight_block", blocker)
	manager.tick(0.016)
	t.assert_false(movement.active, "被御剑阻塞时不应激活")
	t.assert_eq(motion.desired_horizontal, Vector3.ZERO, "被阻塞时不写水平意图")

	TagRegistry.remove_block(host, &"sword_flight_block", blocker)
	manager.tick(0.016)
	t.assert_true(movement.active, "阻塞解除后应恢复激活")
	t.assert_eq(motion.desired_horizontal, Vector3(SPEED, 0.0, 0.0), "阻塞解除后按相机地面基写意图")


static func _test_missing_component_is_inert(t) -> void:
	t.begin_case()
	var host := CharacterBody3D.new()
	t.track(host)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var movement := SwordsmanMovement.new()
	manager.add_child(movement)

	manager.tick(0.016)
	t.assert_false(movement.active, "缺少组件时不应激活")
