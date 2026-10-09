extends RefCounted
## 天降剑雨配对测试：真实逻辑 tick 与场景树分组，不以表现时间触发规则。

const DT := 1.0 / 60.0


static func run(t) -> void:
	_test_activation_contract(t)
	_test_quick_click_complete_batches(t)
	_test_locked_target_and_background_pose(t)
	_test_release_pose_is_monotonic(t)
	_test_gather_switch_and_cancel(t)
	_test_acceleration_ground_tip_and_hit_once(t)
	_test_elevated_sloped_surface(t)
	await _test_ground_layer_sampling(t)
	_test_cooldown_and_exit(t)
	_test_view_uses_exact_tip_geometry(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var cast := SwordCastComponent.new()
	var rain := HeavenlySwordRainComponent.new()
	host.add_child(cast)
	host.add_child(rain)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var ability := HeavenlySwordRain.new()
	manager.add_child(ability)
	cast.form = SwordCastComponent.FORM_RAIN
	cast.aim_point = Vector3(0.0, 0.0, -6.0)
	cast.aim_surface_point = cast.aim_point
	cast.aim_surface_valid = true
	return {"host": host, "cast": cast, "rain": rain, "manager": manager, "ability": ability}


static func _press(scene: Dictionary) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_pressed = true
	cast.cast_held = true
	(scene["manager"] as CapabilityManager).tick(DT)
	cast.cast_pressed = false


static func _release(scene: Dictionary) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_held = false
	cast.cast_released = true
	(scene["manager"] as CapabilityManager).tick(DT)
	cast.cast_released = false


static func _advance(scene: Dictionary, ticks: int) -> void:
	for index in range(ticks):
		(scene["manager"] as CapabilityManager).tick(DT)


static func _until_idle(scene: Dictionary, limit: int = 500) -> int:
	for index in range(limit):
		(scene["manager"] as CapabilityManager).tick(DT)
		if not (scene["ability"] as HeavenlySwordRain).active:
			return index
	return limit


static func _dummy(t, point: Vector3) -> SwordTargetComponent:
	var host := Node3D.new()
	var target := SwordTargetComponent.new()
	host.add_child(target)
	host.add_to_group(&"sword_target")
	t.track(host)
	host.global_position = point
	return target


static func _test_activation_contract(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	cast.form = SwordCastComponent.FORM_QI
	_press(scene)
	t.assert_false((scene["ability"] as HeavenlySwordRain).active, "非剑雨招式不激活")
	cast.form = SwordCastComponent.FORM_RAIN
	cast.aim_surface_valid = false
	_press(scene)
	t.assert_false((scene["ability"] as HeavenlySwordRain).active, "没有真实地面选点不激活")
	cast.aim_surface_valid = true
	_press(scene)
	t.assert_true((scene["ability"] as HeavenlySwordRain).active, "选中剑雨并按下且有效地面时激活")
	t.assert_eq(cast.pose_kind, SwordCastComponent.POSE_RAIN, "聚剑请求独立剑雨姿势")
	t.assert_eq((scene["ability"] as HeavenlySwordRain).priority, 40, "与其他主动剑法同优先级")


static func _test_quick_click_complete_batches(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rain := scene["rain"] as HeavenlySwordRainComponent
	_press(scene)
	_release(scene)
	t.assert_true(rain.released, "快速松开立即锁区")
	t.assert_eq(rain.phase, "gather", "快速点击仍保持最短聚剑段")
	var phases: Dictionary = {}
	var batches: Dictionary = {}
	var first_batch_time: Dictionary = {}
	for index in range(500):
		(scene["manager"] as CapabilityManager).tick(DT)
		phases[rain.phase] = true
		for sword in rain.swords:
			if sword["state"] == "fall":
				var batch := int(sword["batch"])
				batches[batch] = true
				if not first_batch_time.has(batch):
					first_batch_time[batch] = (scene["manager"] as CapabilityManager).elapsed
		if not (scene["ability"] as HeavenlySwordRain).active:
			break
	t.assert_true(phases.has("hover") and phases.has("rain") and phases.has("dissipate"), "快速点击经历完整悬停、降剑与散阵")
	t.assert_eq(batches.size(), 3, "默认剑雨确实分三批下落")
	t.assert_eq(rain.batches_launched, 3, "统计保留已开始的三批")
	t.assert_eq(rain.swords_landed, rain.sword_count, "全部剑实际接地")
	t.assert_true(absf(float(first_batch_time[1]) - float(first_batch_time[0]) - rain.batch_interval) <= DT * 1.1,
		"第一与第二批间隔符合设定，不同帧可辨")
	t.assert_true(absf(float(first_batch_time[2]) - float(first_batch_time[1]) - rain.batch_interval) <= DT * 1.1,
		"第二与第三批间隔符合设定")
	t.assert_true(rain.swords.is_empty() and rain.impacts.is_empty(), "散阵结束清空所有表现数据")
	t.assert_eq(rain.ring_alpha, 0.0, "散阵结束法环完全消散")


static func _test_locked_target_and_background_pose(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var rain := scene["rain"] as HeavenlySwordRainComponent
	_press(scene)
	_advance(scene, 20)
	_release(scene)
	var center := rain.ground_center
	cast.aim_surface_point = Vector3(15.0, 8.0, 12.0)
	cast.form = SwordCastComponent.FORM_QI
	cast.pose_kind = SwordCastComponent.POSE_THRUST
	cast.pose_weight = 0.24
	cast.pose_phase = "external"
	_advance(scene, 60)
	t.assert_eq(rain.ground_center, center, "释放后移动鼠标不会移动落区")
	t.assert_true((scene["ability"] as HeavenlySwordRain).active, "释放后换招仍继续法术")
	t.assert_eq(cast.pose_kind, SwordCastComponent.POSE_THRUST, "后台法术不改当前招式姿势")
	t.assert_eq(cast.pose_weight, 0.24, "后台法术不改当前招式姿势权重")
	t.assert_eq(cast.pose_phase, "external", "后台法术不改姿势流程")
	t.assert_true(_until_idle(scene) < 500, "后台剑雨完整结束")


static func _test_gather_switch_and_cancel(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var rain := scene["rain"] as HeavenlySwordRainComponent
	_press(scene)
	cast.form = SwordCastComponent.FORM_WHEEL
	_advance(scene, 2)
	t.assert_false((scene["ability"] as HeavenlySwordRain).active, "尚未释放时换招取消")
	t.assert_true(rain.swords.is_empty(), "取消蓄势清剑")
	t.assert_eq(rain.ring_alpha, 0.0, "取消蓄势清法环")
	cast.form = SwordCastComponent.FORM_RAIN
	_advance(scene, 60)
	_press(scene)
	_release(scene)
	_advance(scene, 80)
	cast.request_cancel()
	_advance(scene, 2)
	t.assert_false((scene["ability"] as HeavenlySwordRain).active, "取消序号终止释放后的剑雨")
	t.assert_true(rain.swords.is_empty() and rain.impacts.is_empty(), "取消序号清理降剑、冲击")
	t.assert_eq(rain.ring_alpha, 0.0, "取消序号清法环")
	t.assert_eq(cast.pose_weight, 0.0, "取消序号释放本招姿势请求")


static func _test_release_pose_is_monotonic(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var rain := scene["rain"] as HeavenlySwordRainComponent
	_press(scene)
	_release(scene)
	var previous := 0.0
	var monotonic := true
	var suspended_pose := true
	var last_weight := 1.0
	var fading := true
	for index in range(300):
		(scene["manager"] as CapabilityManager).tick(DT)
		if rain.phase == "hover":
			suspended_pose = suspended_pose and cast.pose_phase == "gather"
		if rain.phase in ["rain", "dissipate"]:
			monotonic = monotonic and cast.pose_progress + 0.00001 >= previous
			previous = cast.pose_progress
		if rain.phase == "dissipate":
			fading = fading and cast.pose_weight <= last_weight + 0.00001
			last_weight = cast.pose_weight
		if rain.phase == "idle":
			break
	t.assert_true(suspended_pose, "成阵停悬保持高举姿势，未提前下压")
	t.assert_true(monotonic, "释放与收势的动作进度连续，不因换阶段重新举手")
	t.assert_true(fading and last_weight < 0.1, "收势姿势权重逐渐回落到自然待命")


static func _test_acceleration_ground_tip_and_hit_once(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rain := scene["rain"] as HeavenlySwordRainComponent
	rain.region_radius = 4.2
	var target := _dummy(t, Vector3(0.0, 0.0, -6.0))
	_press(scene)
	_release(scene)
	var previous := Vector3.ZERO
	var early_speed := 0.0
	var late_speed := 0.0
	var previous_fall := false
	var landing_seen := false
	var all_tips_above := true
	var tangent_matches := true
	var landing_hit_count := -1
	for index in range(400):
		(scene["manager"] as CapabilityManager).tick(DT)
		for sword in rain.swords:
			var tip: Vector3 = sword["tip"]
			var ground: Vector3 = sword["target"]
			all_tips_above = all_tips_above and tip.y >= ground.y - 0.00001
			if int(sword["slot"]) != 0:
				continue
			if sword["state"] == "fall":
				if previous_fall:
					var velocity := (tip - previous) / DT
					if early_speed == 0.0 and velocity.length() > 0.1:
						early_speed = velocity.length()
					late_speed = velocity.length()
					if velocity.length() > 0.001:
						tangent_matches = tangent_matches and velocity.normalized().dot(sword["forward"]) > 0.99
				previous = tip
				previous_fall = true
			elif sword["state"] == "landed":
				landing_seen = true
				t.assert_true(tip.distance_to(ground) < 0.00001, "接地后剑尖精确停在落点")
				if landing_hit_count < 0:
					landing_hit_count = target.hit_count
		if rain.phase == "idle":
			break
	t.assert_true(landing_seen, "观察到真实接地阶段")
	t.assert_true(all_tips_above, "逐帧所有剑尖都没有穿过地面")
	t.assert_true(tangent_matches, "剑尖方向与真实位移切线一致")
	t.assert_true(early_speed > 0.0 and late_speed > early_speed * 3.0, "剑雨从停悬自然加速，下落后段速度明显更快")
	t.assert_eq(target.hit_count, 1, "中心木桩只被中心剑命中一次，接地不重复计数")
	t.assert_eq(landing_hit_count, 1, "命中发生于真实下降，落地之前已登记")
	t.assert_eq(TimeKeeper.request_count(), 0, "轻剑雨没有任何逐剑顿帧请求")


static func _test_elevated_sloped_surface(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var rain := scene["rain"] as HeavenlySwordRainComponent
	cast.aim_surface_point = Vector3(0.0, 4.0, -6.0)
	cast.aim_surface_normal = Vector3(0.2, 1.0, 0.0).normalized()
	_press(scene)
	_release(scene)
	var conforms := true
	for sword in rain.swords:
		var offset: Vector3 = sword["target"] - rain.ground_center
		conforms = conforms and absf(offset.dot(rain.ground_normal)) < 0.0001
	t.assert_true(conforms, "无物理碰撞体时每剑落点投影到选中斜面")
	t.assert_eq(rain.ground_center.y, 4.0, "地面选点使用高台高度，不用人物高度")
	t.assert_true(_until_idle(scene) < 500, "高台斜面剑雨可完整结束")


static func _test_cooldown_and_exit(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var rain := scene["rain"] as HeavenlySwordRainComponent
	_press(scene)
	_release(scene)
	_until_idle(scene)
	var count := cast.casts_total
	_press(scene)
	t.assert_eq(cast.casts_total, count, "刚散阵完成处于冷却")
	_advance(scene, int(ceil(rain.cooldown / DT)) + 1)
	_press(scene)
	t.assert_eq(cast.casts_total, count + 1, "冷却结束可再次聚剑")
	var ability := scene["ability"] as HeavenlySwordRain
	ability.get_parent().remove_child(ability)
	ability.free()
	t.assert_true(rain.swords.is_empty() and rain.impacts.is_empty(), "卸载能力清理全部表现")
	t.assert_eq(rain.ring_alpha, 0.0, "卸载能力清理空中法阵")


static func _test_ground_layer_sampling(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var rain := scene["rain"] as HeavenlySwordRainComponent
	for index in range(2):
		var body := StaticBody3D.new()
		body.collision_layer = 3 if index == 0 else 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8.0, 1.0, 8.0) if index == 0 else Vector3(0.6, 1.0, 0.6)
		shape.shape = box
		body.add_child(shape)
		t.track(body)
		body.global_position = Vector3(0.0, 3.5 if index == 0 else 5.5, -6.0)
	await t.root().get_tree().physics_frame
	await t.root().get_tree().physics_frame
	cast.aim_surface_point = Vector3(0.0, 4.0, -6.0)
	_press(scene)
	_release(scene)
	var first: Dictionary = rain.swords[0]
	t.assert_true(absf((first["target"] as Vector3).y - 4.0) < 0.0001,
		"真实落点采样命中含 bit2 的高台表面")
	t.assert_true(absf((first["target"] as Vector3).y - 6.0) > 1.0,
		"落点采样忽略只有 bit1 的木桩顶面")


static func _test_view_uses_exact_tip_geometry(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var rain := scene["rain"] as HeavenlySwordRainComponent
	var view := HeavenlySwordRainView.new()
	(scene["host"] as Node3D).add_child(view)
	view.set_process(false)
	view.bind(rain)
	_press(scene)
	_release(scene)
	_advance(scene, 110)
	view._process(DT)
	var swords := view.get_node("RainSwords") as MultiMeshInstance3D
	t.assert_eq(swords.multimesh.visible_instance_count, rain.swords.size(), "视图绘制与逻辑剑数相同")
	var tips_match := true
	for index in range(rain.swords.size()):
		var transform := HeavenlySwordRainView.transform_for_sword(rain.swords[index])
		var geometry_tip := transform * Vector3(0.0, 0.0, -SwordSpellVisual.TIP_LENGTH)
		tips_match = tips_match and geometry_tip.distance_to(rain.swords[index]["tip"]) < 0.0001
	t.assert_true(tips_match, "所有放大后的模型剑尖精确对应连续命中轨迹")
	t.assert_true((view.get_node("RainTrails") as MeshInstance3D).mesh.get_surface_count() > 0,
		"落剑阶段生成真实轨迹尾迹网格")
