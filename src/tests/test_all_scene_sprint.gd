extends RefCounted

## 从真实子实验清单加载场景，走事件派发、物理能力和动画完整链路。
## 不直接写角色输入或手工 tick 能力，避免漏接场景仍被测试判为通过。
const CATALOG := "res://data/content/character_movement_subexperiments.json"


static func run(t) -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	for entry: Dictionary in catalog["subexperiments"]:
		t.begin_case()
		var label: String = entry["id"]
		var packed := load(str(entry["scene"])) as PackedScene
		var scene := packed.instantiate()
		t.track(scene)
		await _frames(t.root(), 30)
		var actor := scene.find_child("Swordsman", true, false) as Swordsman
		t.assert_true(actor != null, "%s 装配共享修士" % label)
		if actor == null:
			continue
		var motion := actor.motion()
		var presentation := actor.get_node("Visual/CultivatorSkeletonPresentation")
		t.assert_true(motion.on_floor, "%s 出生点落地" % label)

		_push_key(KEY_W, true)
		await _frames(scene, 10)
		var walk := _speed(motion)
		t.assert_true(absf(walk - motion.move_speed) < 0.02,
			"%s 步行实测 %.2f m/s" % [label, walk])
		t.assert_eq(_clip(presentation), "walk", "%s 步行动画" % label)

		_push_key(KEY_SHIFT, true)
		await _frames(scene, 10)
		var sprint := _speed(motion)
		t.assert_true(motion.sprint_input, "%s Shift 通过场景传入共享组件" % label)
		t.assert_true(absf(sprint - motion.sprint_speed) < 0.02,
			"%s 疾跑实测 %.2f m/s" % [label, sprint])
		t.assert_eq(_clip(presentation), "run", "%s 疾跑动画" % label)

		_push_key(KEY_SHIFT, false)
		await _frames(scene, 5)
		var released := _speed(motion)
		t.assert_false(motion.sprint_input, "%s 松开 Shift 清疾跑意图" % label)
		t.assert_true(absf(released - motion.move_speed) < 0.02,
			"%s 松开 Shift 恢复步行速度" % label)
		t.assert_eq(_clip(presentation), "walk", "%s 松开 Shift 恢复步行动画" % label)

		_push_key(KEY_W, false)
		_push_key(KEY_SHIFT, true)
		await _frames(scene, 5)
		t.assert_false(motion.sprint_input, "%s 仅按 Shift 无疾跑意图" % label)
		t.assert_true(_speed(motion) < 0.01, "%s 仅按 Shift 不移动" % label)
		t.assert_eq(_clip(presentation), "idle", "%s 仅按 Shift 保持普通站立" % label)

		_push_key(KEY_W, true)
		await _frames(scene, 3)
		scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _frames(scene, 3)
		var unfocused := _speed(motion)
		t.assert_false(motion.sprint_input, "%s 失焦清疾跑意图" % label)
		t.assert_true(unfocused < 0.01, "%s 失焦停止移动" % label)
		_push_key(KEY_W, false)
		_push_key(KEY_SHIFT, false)
		await _frames(scene, 2)
		print("SPRINT_SCENE %s walk=%.2f run=%.2f released=%.2f unfocused=%.2f" %
			[label, walk, sprint, released, unfocused])
		# 离树前清全局键状态；下一项不会继承按住状态。
		t.root().remove_child(scene)
		scene.queue_free()
		await t.root().get_tree().process_frame


static func _frames(node: Node, count: int) -> void:
	for _frame in range(count):
		await node.get_tree().physics_frame
		await node.get_tree().process_frame


static func _push_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


static func _speed(motion: SwordsmanMotionComponent) -> float:
	return Vector2(motion.actual_velocity.x, motion.actual_velocity.z).length()


static func _clip(presentation: Node) -> String:
	var pose: Dictionary = presentation.call("pose_state")
	return str(pose.get("current_clip", ""))
