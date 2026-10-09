extends RefCounted
## 剑法工作台集成测试：场景装配、表现挂载、左键边沿交付、真实物理帧下三招都能命中木桩、
## 飞剑在外时御剑被拒、重置清账、目录登记。
## 依据 notes/implemented/gameplay/2026-10-09-sword-workbench.md。

const SCENE := "res://levels/experiments/sword_combat/sword_workbench.tscn"


static func run(t) -> void:
	t.begin_case()
	var packed := load(SCENE) as PackedScene
	t.assert_true(packed != null, "剑法工作台场景可加载")
	if packed == null:
		return
	var scene := packed.instantiate()
	t.track(scene)
	await scene.get_tree().physics_frame
	var actor: Swordsman = scene.call("actor")
	var cast: SwordCastComponent = scene.call("cast_component")
	t.assert_true(actor != null and cast != null, "场景装好修士与剑法组件")
	var names := PackedStringArray()
	for child in actor.capability_manager().get_children():
		names.append(str(child.name))
	for expected in ["SwordsmanMovement", "Jump", "SwordFlight", "SwordQi", "FlyingSwordStrike", "SwordArray"]:
		t.assert_true(expected in names, "宿主管理器装有 %s（%s）" % [expected, names])
	t.assert_eq(scene.get_tree().get_nodes_in_group(&"sword_target").size(), 5, "五根木桩进入 sword_target 分组")
	var presentation := actor.get_node_or_null("SwordCastPresentation") as SwordCastPresentation
	t.assert_true(presentation != null and presentation.sword_node() != null, "悬浮本命剑已挂载")
	t.assert_eq(actor.find_children("SwordCastPoseModifier", "SkeletonModifier3D", true, false).size(), 1,
		"出招姿势修饰器挂在角色骨架下")
	var rest := cast.rest_position(actor.global_position, actor.motion().aim_direction)
	t.assert_true(presentation.sword_node().global_position.distance_to(rest) < 0.2,
		"本命剑悬在右肩后上方")

	# 左键边沿：场景把按下交付为一帧 cast_pressed，并朝鼠标地面投影出剑。
	scene.call("select_form", SwordCastComponent.FORM_QI)
	scene.call("_unhandled_input", _mouse(true))
	await scene.get_tree().physics_frame
	await scene.get_tree().physics_frame
	t.assert_eq(cast.casts_total, 1, "左键按下交付为一次出招")
	t.assert_false(cast.cast_pressed, "按下边沿只交付一帧")
	scene.call("_unhandled_input", _mouse(false))
	await scene.get_tree().physics_frame

	var dummies: Array = scene.call("dummies")
	var first: TrainingDummy = dummies[0]
	for form in [SwordCastComponent.FORM_QI, SwordCastComponent.FORM_STRIKE, SwordCastComponent.FORM_ARRAY]:
		scene.call("reset_experiment")
		await scene.get_tree().physics_frame
		scene.call("select_form", form)
		# 重置取消此前出招；按真实冷却推进后再开始本次独立命中用例。
		for _frame in range(24):
			await scene.get_tree().physics_frame
		var before := int(scene.call("total_hits"))
		await _cast_at(scene, first.global_position, form == SwordCastComponent.FORM_ARRAY)
		t.assert_true(int(scene.call("total_hits")) > before, "%s 在真实物理帧下命中木桩" % form)

	scene.call("reset_experiment")
	await scene.get_tree().physics_frame
	scene.call("select_form", SwordCastComponent.FORM_STRIKE)
	_aim_at(scene, first.global_position)
	scene.call("_unhandled_input", _mouse(true))
	await scene.get_tree().physics_frame
	await scene.get_tree().physics_frame
	t.assert_true(cast.sword_away, "飞剑出击后本命剑在外")
	actor.press_flight_toggle()
	await scene.get_tree().physics_frame
	t.assert_false(actor.motion().flight_active, "本命剑在外时按 F 不起飞")
	scene.call("_unhandled_input", _mouse(false))
	for i in range(240):
		await scene.get_tree().physics_frame
		if not cast.sword_away:
			break
	t.assert_false(cast.sword_away, "飞剑飞回悬浮位")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_away_block"), 0, "飞回后撤销剑在外阻塞")

	scene.call("reset_experiment")
	t.assert_eq(int(scene.call("total_hits")), 0, "重置清空木桩命中记录")
	t.assert_true(TimeKeeper.request_count() <= 1, "顿帧请求不累积")

	var entry := {}
	for module in LabCatalog.read()["modules"]:
		if str(module["id"]) == "sword_combat":
			entry = module
	t.assert_eq(str(entry.get("scene", "")), SCENE, "顶层清单登记剑法工作台")
	t.assert_true(LabCatalog.can_open(entry), "剑法战斗可从顶层进入")


static func _mouse(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


## 无头环境没有真实鼠标：按当前镜头把世界点换算成视口坐标，送一次鼠标移动事件。
static func _aim_at(scene: Node, point: Vector3) -> void:
	var camera := scene.get_viewport().get_camera_3d()
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(Vector3(point.x, 0.0, point.z))
	scene.call("_input", motion)


static func _cast_at(scene: Node, point: Vector3, hold: bool) -> void:
	_aim_at(scene, point)
	await scene.get_tree().physics_frame
	scene.call("_unhandled_input", _mouse(true))
	for i in range(40 if hold else 2):
		_aim_at(scene, point)
		await scene.get_tree().physics_frame
	scene.call("_unhandled_input", _mouse(false))
	for i in range(150):
		_aim_at(scene, point)
		await scene.get_tree().physics_frame
