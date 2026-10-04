extends RefCounted

## 所有真实移动场景的完整操作链路，输入只经按键事件进入。
const CATALOG := "res://data/content/character_movement_subexperiments.json"
const FLIGHT_TAG := &"sword_flight_block"


static func run(t) -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	for entry: Dictionary in catalog["subexperiments"]:
		t.begin_case()
		var label: String = entry["id"]
		var scene := (load(str(entry["scene"])) as PackedScene).instantiate()
		t.track(scene)
		await _frames(scene, 30)
		var actor := scene.find_child("Swordsman", true, false) as Swordsman
		t.assert_true(actor != null, "%s 装配共享修士" % label)
		if actor == null:
			continue
		var motion := actor.motion()
		var presentation := actor.get_node("Visual/CultivatorSkeletonPresentation")
		var rig := scene.find_child("CameraRig", true, false) as CameraRig
		var assembly := actor.get_node("ActorAssembly") as ActorAssembly
		var names := assembly.capability_names()
		names.sort()
		t.assert_eq(names, PackedStringArray(["Jump", "SwordFlight", "SwordsmanMovement"]),
			"%s 只装配同一套三能力" % label)

		_key(KEY_SPACE, true)
		await _frames(scene, 2)
		t.assert_true(not motion.on_floor and motion.actual_velocity.y > 0.0, "%s Space 正常起跳" % label)
		t.assert_eq(_clip(presentation), "jump", "%s 跳跃动画" % label)
		var jump_velocity := motion.actual_velocity.y
		_key(KEY_SPACE, true, true)
		await _frames(scene, 3)
		t.assert_true(motion.actual_velocity.y < jump_velocity, "%s 按住 Space 不重复起跳" % label)
		_key(KEY_SPACE, false)
		t.assert_true(await _land(actor), "%s 跳跃后落地" % label)

		var ground_y := actor.global_position.y
		_key(KEY_F, true)
		_key(KEY_F, false)
		await _frames(scene, 22)
		t.assert_true(motion.flight_active, "%s F 开启御剑" % label)
		t.assert_eq(TagRegistry.block_count(actor, FLIGHT_TAG), 1, "%s 御剑统一阻塞地面移动与跳跃" % label)
		t.assert_true(actor.flight_visual_node().visible, "%s 御剑显示飞剑" % label)
		t.assert_eq(_clip(presentation), "sword_ride", "%s 御剑统一动画" % label)
		_key(KEY_F, true, true)
		await _frames(scene, 2)
		t.assert_true(motion.flight_active, "%s F echo 不重复开关御剑" % label)
		_key(KEY_F, false)

		_key(KEY_W, true)
		await _frames(scene, 4)
		var flight_speed := _speed(motion)
		t.assert_true(absf(flight_speed - motion.flight_speed) < 0.02, "%s 共享御剑速度 %.2f" % [label, flight_speed])
		_key(KEY_SHIFT, true)
		await _frames(scene, 3)
		t.assert_true(absf(_speed(motion) - flight_speed) < 0.02, "%s 飞行由御剑能力控制速度" % label)
		_key(KEY_W, false)
		_key(KEY_SHIFT, false)

		_key(KEY_SPACE, true)
		await _frames(scene, 4)
		var lift := motion.actual_velocity.y
		t.assert_true(absf(lift - motion.flight_lift_speed) < 0.02, "%s Space 上升 %.2f" % [label, lift])
		var focus: Vector3 = rig.snapshot()["focus"]
		t.assert_true(focus.y > ground_y + 0.1, "%s 镜头跟随御剑高度" % label)
		_key(KEY_CTRL, true)
		await _frames(scene, 3)
		t.assert_true(absf(motion.actual_velocity.y) < 0.01, "%s 上下同按悬停" % label)
		_key(KEY_SPACE, false)
		await _frames(scene, 4)
		var sink := motion.actual_velocity.y
		t.assert_true(absf(sink + motion.flight_sink_speed) < 0.02, "%s Ctrl 下降 %.2f" % [label, sink])
		_key(KEY_CTRL, false)
		await _frames(scene, 3)
		t.assert_true(motion.actual_velocity.length() < 0.01, "%s 松开按键悬停" % label)

		_key(KEY_W, true)
		_key(KEY_SPACE, true)
		await _frames(scene, 2)
		scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _frames(scene, 3)
		t.assert_true(motion.flight_active, "%s 失焦保留御剑" % label)
		t.assert_true(motion.actual_velocity.length() < 0.01, "%s 失焦清移动与升降，保持悬停" % label)
		_key(KEY_W, false)
		_key(KEY_SPACE, false)
		_key(KEY_F, true)
		_key(KEY_F, false)
		await _frames(scene, 2)
		t.assert_false(motion.flight_active, "%s F 收剑" % label)
		t.assert_eq(TagRegistry.block_count(actor, FLIGHT_TAG), 0, "%s 收剑解除阻塞" % label)
		t.assert_false(actor.flight_visual_node().visible, "%s 收剑隐藏飞剑" % label)
		t.assert_true(await _land(actor), "%s 收剑后重力落地" % label)
		_key(KEY_W, true)
		_key(KEY_SHIFT, true)
		await _frames(scene, 3)
		t.assert_true(absf(_speed(motion) - motion.sprint_speed) < 0.02, "%s 落地恢复疾跑能力" % label)
		_key(KEY_W, false)
		_key(KEY_SHIFT, false)

		_key(KEY_F, true)
		_key(KEY_F, false)
		await _frames(scene, 3)
		t.assert_true(motion.flight_active, "%s 重置前处于御剑" % label)
		_key(KEY_W, true)
		_key(KEY_SPACE, true)
		_key(KEY_R, true)
		_key(KEY_R, false)
		await _frames(scene, 30)
		t.assert_false(motion.flight_active, "%s R 重置关闭御剑" % label)
		t.assert_eq(TagRegistry.block_count(actor, FLIGHT_TAG), 0, "%s R 重置解除御剑阻塞" % label)
		t.assert_true(motion.actual_velocity.length() < 0.01, "%s R 清理按住输入及尚未消费的动作" % label)
		t.assert_true(motion.on_floor, "%s R 回出生点落地" % label)
		_key(KEY_W, false)
		_key(KEY_SPACE, false)

		if label == "motion_stage":
			_key(KEY_M, true)
			_key(KEY_M, false)
			await _frames(scene, 2)
			_key(KEY_F, true)
			_key(KEY_SPACE, true)
			_key(KEY_W, true)
			await _frames(scene, 5)
			t.assert_false(motion.flight_active, "工作台预览不操作真实御剑")
			t.assert_true(motion.on_floor and motion.actual_velocity.length() < 0.01, "工作台预览不操作真实移动和跳跃")
			for code in [KEY_F, KEY_SPACE, KEY_W]:
				_key(code, false)
			_key(KEY_M, true)
			_key(KEY_M, false)
			await _frames(scene, 3)
			t.assert_false(motion.flight_active, "切回实时模式没有积攒的御剑边沿")

		_key(KEY_F, true)
		_key(KEY_F, false)
		await _frames(scene, 3)
		t.assert_true(motion.flight_active, "%s 退场前开启御剑作为清理对照" % label)
		t.root().remove_child(scene)
		t.assert_eq(TagRegistry.block_count(actor, FLIGHT_TAG), 0, "%s 退场清御剑阻塞" % label)
		t.assert_false(motion.flight_active, "%s 退场清御剑状态" % label)
		scene.queue_free()
		await t.root().get_tree().process_frame
		print("TRAVERSAL_SCENE %s flight=%.2f lift=%.2f sink=%.2f" % [label, flight_speed, lift, sink])


static func _frames(node: Node, count: int) -> void:
	for _frame in range(count):
		await node.get_tree().physics_frame
		await node.get_tree().process_frame


static func _land(actor: Swordsman) -> bool:
	for _frame in range(90):
		if actor.motion().on_floor:
			return true
		await _frames(actor, 1)
	return false


static func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


static func _speed(motion: SwordsmanMotionComponent) -> float:
	return Vector2(motion.actual_velocity.x, motion.actual_velocity.z).length()


static func _clip(presentation: Node) -> String:
	var pose: Dictionary = presentation.call("pose_state")
	return str(pose.get("current_clip", ""))
