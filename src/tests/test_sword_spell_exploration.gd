extends RefCounted
## 六招组合回归：真实地面、释放后切招、蓄势取消、重置、飞行与生命周期。
## 依据 notes/implemented/gameplay/2026-10-10-sword-spell-exploration.md。
const SCENE := "res://levels/experiments/sword_combat/sword_workbench.tscn"
const NEW_FORMS := [SwordCastComponent.FORM_WHEEL, SwordCastComponent.FORM_GIANT, SwordCastComponent.FORM_RAIN]

static func run(t) -> void:
	t.begin_case()
	# 接近并跨过竖直方向：剑尖跟随，而剑身不因切换参考上轴突然翻滚。
	var previous := SwordSpellVisual.sword_transform(Vector3.ZERO, Vector3(0.0, -0.95, -0.312)).basis
	for degrees in range(-18, 19):
		var direction := Vector3(0.0, -cos(deg_to_rad(float(degrees))), sin(deg_to_rad(float(degrees))))
		var rendered := SwordSpellVisual.continuous_sword_transform(Vector3.ZERO, direction, Vector3.ONE, previous)
		t.assert_true((-rendered.basis.z).dot(direction) > 0.99999, "连续剑身保持真实剑尖朝向")
		t.assert_true(absf(previous.get_rotation_quaternion().dot(rendered.basis.get_rotation_quaternion())) > 0.999, "跨竖直方向不突然滚转")
		previous = rendered.basis
	var scene := (load(SCENE) as PackedScene).instantiate()
	t.track(scene)
	await _frames(scene, 5)
	var actor: Swordsman = scene.call("actor")
	var cast: SwordCastComponent = scene.call("cast_component")
	t.assert_eq((scene.get_node("BoundaryCollision") as StaticBody3D).collision_layer, 1, "边墙不进入地面查询层")
	t.assert_eq(SwordCastComponent.FORMS.size(), 6, "工作台六招可选择")
	for form in NEW_FORMS:
		t.assert_true(scene.call("spell_component", form) != null, "%s 独立数据已装配" % form)
	# 木桩顶面不能成为选点；高台顶面应被识别。
	_aim(scene, Vector3(0, 0, -4))
	await _frames(scene, 3)
	t.assert_true(cast.aim_surface_valid and absf(cast.aim_surface_point.y) < 0.03, "落点筛选地面排除木桩顶面")
	_aim(scene, Vector3(10, 1.5, -5))
	await _frames(scene, 3)
	t.assert_true(cast.aim_surface_valid and absf(cast.aim_surface_point.y - 1.5) < 0.03, "射线识别1.5米高台")
	for _i in range(6):
		_aim(scene, Vector3(10, 0.5, -3))
		await _frames(scene, 1)
	if cast.aim_surface_valid:
		print("SIDE_PROBE ", cast.aim_surface_point, " normal=", cast.aim_surface_normal)
	t.assert_false(cast.aim_surface_valid, "高台竖直侧面不是可镇落地面")
	for form in NEW_FORMS:
		scene.call("reset_experiment")
		await _frames(scene, 3)
		scene.call("select_form", form)
		_aim(scene, Vector3(0, 0, -4))
		await _frames(scene, 2)
		_press(scene, true)
		for _i in range(85):
			_aim(scene, Vector3(0, 0, -4))
			await _frames(scene, 1)
		var data: Component = scene.call("spell_component", form)
		t.assert_eq(str(data.get("phase")), "gather", "%s 持续按住维持聚剑" % form)
		t.assert_true(cast.pose_weight > 0.5, "%s 聚剑发出角色姿势请求" % form)
		_press(scene, false)
		# 释放与换招在同一物理帧，能力尚未消费松开边沿。
		scene.call("select_form", SwordCastComponent.FORM_QI)
		for _i in range(280):
			await _frames(scene, 1)
			if str(data.get("phase")) == "idle":
				break
		t.assert_eq(str(data.get("phase")), "idle", "%s 释放后切招仍完成并清空" % form)
		t.assert_true(int(scene.call("total_hits")) > 0, "%s 三维轨迹命中木桩" % form)
		t.assert_true(cast.pose_weight < 0.05, "%s 后台释放不覆盖前台姿势" % form)
		t.assert_eq(TagRegistry.block_count(actor, &"sword_away_block"), 0, "%s 不泄漏本命剑阻塞" % form)
		# 蓄势切招取消，随后再次蓄势与 R 取消。
		scene.call("select_form", form)
		await _frames(scene, 40)
		_press(scene, true)
		await _frames(scene, 15)
		scene.call("select_form", SwordCastComponent.FORM_STRIKE)
		await _frames(scene, 3)
		t.assert_eq(str(data.get("phase")), "idle", "%s 蓄势切招取消" % form)
		scene.call("select_form", form)
		await _frames(scene, 40)
		_press(scene, true)
		await _frames(scene, 15)
		scene.call("reset_experiment")
		await _frames(scene, 3)
		t.assert_eq(str(data.get("phase")), "idle", "%s R 重置清理所有阶段" % form)
		t.assert_eq(int(scene.call("total_hits")), 0, "%s R 清空命中记录" % form)
	# 同一帧 A 松手→切 B→按住 B，旧释放边沿不得令 B 提前发射。
	scene.call("select_form", SwordCastComponent.FORM_WHEEL)
	await _frames(scene, 45)
	_aim(scene, Vector3(0,0,-4))
	_press(scene, true)
	await _frames(scene, 85)
	_press(scene, false)
	scene.call("select_form", SwordCastComponent.FORM_RAIN)
	_press(scene, true)
	await _frames(scene, 65)
	var rain: Component = scene.call("spell_component", SwordCastComponent.FORM_RAIN)
	t.assert_eq(str(rain.get("phase")), "gather", "旧招松开边沿不会提前释放新招")
	t.assert_false(bool(rain.get("released")), "新招持续按住仍未锁区")
	t.assert_false(str((scene.call("spell_component", SwordCastComponent.FORM_WHEEL) as Component).get("phase")) == "gather", "旧招仍继续释放")
	scene.call("reset_experiment")
	await _frames(scene, 5)
	# 御剑时天空法术仍可开始；失焦清输入与取消正在运行法术。
	scene.call("select_form", SwordCastComponent.FORM_GIANT)
	actor.press_flight_toggle()
	await _frames(scene, 15)
	t.assert_true(actor.motion().flight_active, "新增三招保留御剑组合")
	_press(scene, true)
	await _frames(scene, 10)
	var giant: Component = scene.call("spell_component", SwordCastComponent.FORM_GIANT)
	t.assert_eq(str(giant.get("phase")), "gather", "御剑中巨剑可以凝形")
	scene.call("_notification", Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await _frames(scene, 3)
	t.assert_eq(str(giant.get("phase")), "idle", "失焦清理凝剑")
	t.assert_false(cast.cast_held, "失焦不残留左键按住")
	t.assert_eq(TimeKeeper.request_count(), 0, "组合测试无时间缩放泄漏")

static func _frames(scene: Node, count: int) -> void:
	for _i in range(count):
		await scene.get_tree().physics_frame

static func _aim(scene: Node, point: Vector3) -> void:
	var event := InputEventMouseMotion.new()
	event.position = scene.get_viewport().get_camera_3d().unproject_position(point)
	scene.call("_input", event)

static func _press(scene: Node, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	scene.call("_unhandled_input", event)
