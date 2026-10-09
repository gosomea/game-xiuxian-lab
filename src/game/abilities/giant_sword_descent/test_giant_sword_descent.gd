extends RefCounted
## 巨剑配对测试：输入/连续阶段、锁点、高台、运动、去重、反馈与取消/卸载。

const DT := 1.0 / 60.0


static func run(t) -> void:
	_test_activation_contract(t)
	_test_quick_click_has_complete_flow(t)
	_test_preview_follows_without_teleport(t)
	_test_lock_and_acceleration(t)
	_test_raised_ground_contact(t)
	_test_shared_hit_ledger(t)
	_test_one_feedback_per_impact(t)
	_test_release_then_switch_continues(t)
	_test_gather_switch_cancels(t)
	_test_cancel_and_reuse(t)
	_test_exit_and_component_unload(t)
	_test_cooldown(t)
	_test_view_geometry(t)


static func _build(t, point: Vector3 = Vector3(0.0, 0.0, -6.0)) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var cast := SwordCastComponent.new()
	var data := GiantSwordDescentComponent.new()
	host.add_child(cast)
	host.add_child(data)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var giant := GiantSwordDescent.new()
	manager.add_child(giant)
	cast.form = SwordCastComponent.FORM_GIANT
	cast.aim_surface_valid = true
	cast.aim_surface_point = point
	cast.aim_surface_normal = Vector3.UP
	cast.aim_point = Vector3(point.x, 0.0, point.z)
	return {"host": host, "cast": cast, "data": data, "manager": manager, "giant": giant}


static func _hold(scene: Dictionary, ticks: int = 0) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_pressed = true
	cast.cast_held = true
	(scene["manager"] as CapabilityManager).tick(DT)
	cast.cast_pressed = false
	_step(scene, ticks)


static func _release(scene: Dictionary) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_released = true
	cast.cast_held = false
	_step(scene, 1)
	cast.cast_released = false


static func _step(scene: Dictionary, ticks: int = 1) -> void:
	for index in range(ticks):
		(scene["manager"] as CapabilityManager).tick(DT)


static func _until_phase(scene: Dictionary, phase: String, limit: int = 600) -> bool:
	for index in range(limit):
		if (scene["data"] as GiantSwordDescentComponent).phase == phase:
			return true
		_step(scene)
	return false


static func _finish(scene: Dictionary, limit: int = 600) -> int:
	for index in range(limit):
		_step(scene)
		if not (scene["giant"] as GiantSwordDescent).active:
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
	_hold(scene)
	t.assert_false((scene["giant"] as GiantSwordDescent).active, "非巨剑招式不激活")
	cast.form = SwordCastComponent.FORM_GIANT
	cast.aim_surface_valid = false
	_hold(scene)
	t.assert_false((scene["giant"] as GiantSwordDescent).active, "无有效地面选点不激活")
	cast.aim_surface_valid = true
	cast.cast_pressed = false
	_step(scene)
	t.assert_false((scene["giant"] as GiantSwordDescent).active, "只有按住没有按下边沿不激活")
	_hold(scene)
	t.assert_true((scene["giant"] as GiantSwordDescent).active, "招式、选点与按下边沿成立时激活")
	t.assert_eq((scene["giant"] as GiantSwordDescent).priority, 40, "巨剑与其它剑术使用相同优先级")


static func _test_quick_click_has_complete_flow(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as GiantSwordDescentComponent
	_hold(scene)
	_release(scene)
	t.assert_true(data.locked, "快速松开立即锁点")
	t.assert_eq(data.phase, "gather", "快速点击先补足最小凝聚")
	var observed: Array[String] = [data.phase]
	for index in range(300):
		_step(scene)
		if not observed.has(data.phase):
			observed.append(data.phase)
		if not (scene["giant"] as GiantSwordDescent).active:
			break
	for phase in ["gather", "hover", "descent", "impact", "fade", "idle"]:
		t.assert_true(observed.has(phase), "快速点击完整经过 %s" % phase)
	t.assert_eq((scene["cast"] as SwordCastComponent).casts_total, 1, "快速点击只登记一次出招")
	t.assert_eq(data.impact_serial, 1, "快速点击完成一次镇落")


static func _test_preview_follows_without_teleport(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var data := scene["data"] as GiantSwordDescentComponent
	_hold(scene, 45)
	var old := data.rune_point
	cast.aim_surface_point += Vector3(5.0, 0.0, 0.0)
	_step(scene)
	t.assert_true(data.rune_point.x > old.x, "预览开始朝新选点移动")
	t.assert_true(data.rune_point.x < cast.aim_surface_point.x, "预览一帧不瞬移到新选点")
	t.assert_true(data.sword_tip.distance_to(old + Vector3.UP * data.hover_tip_height) < 1.0,
		"主剑跟随平滑预览而非鼠标突变")
	_step(scene, 60)
	t.assert_true(data.rune_point.distance_to(cast.aim_surface_point) < 0.002, "持续指向后预览准确收敛")
	t.assert_true(data.sword_length <= data.sword_length_m + 0.001, "凝形剑长不越过完整长度")
	var before_lock := data.sword_tip
	cast.aim_surface_point += Vector3(2.0, 4.0, 0.0)
	_release(scene)
	t.assert_true(data.sword_tip.distance_to(before_lock) < 1.0, "鼠标急移后松开不传送主剑")
	t.assert_eq(data.target_point, cast.aim_surface_point, "锁定实际地面点而非落后的平滑点")
	t.assert_true(_until_phase(scene, "descent"), "锁点后进入镇落")
	t.assert_true(data.rune_point.distance_to(data.target_point) < 0.001, "悬停阶段法阵归位准确落点")


static func _test_lock_and_acceleration(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var data := scene["data"] as GiantSwordDescentComponent
	_hold(scene, 60)
	_release(scene)
	var locked := data.target_point
	cast.aim_surface_point = Vector3(8.0, 3.0, -8.0)
	t.assert_true(_until_phase(scene, "descent"), "完整凝剑后进入加速阶段")
	var last_tip := data.sword_tip
	var previous_step := 0.0
	var accelerated := 0
	var down_ticks := 0
	for index in range(100):
		_step(scene)
		if data.phase != "descent":
			break
		var step := last_tip.y - data.sword_tip.y
		t.assert_true(step >= -0.00001, "镇落逐帧高度单调下降 %d" % index)
		t.assert_true(data.sword_forward.distance_to(Vector3.DOWN) < 0.0001, "剑尖跟随竖直镇落方向 %d" % index)
		t.assert_true(data.sword_tip.y >= locked.y - 0.0001, "剑尖不穿过锁定地面 %d" % index)
		if step > previous_step:
			accelerated += 1
		previous_step = step
		last_tip = data.sword_tip
		down_ticks += 1
	t.assert_true(accelerated >= down_ticks - 2, "镇落绝大多数帧持续加速而非匀速")
	t.assert_true(data.sword_tip.distance_to(locked) < 0.001, "落地剑尖精确到锁点")
	t.assert_eq(data.target_point, locked, "释放后鼠标移动不改变落点")
	t.assert_eq(data.phase, "impact", "接地进入冲击阶段")


static func _test_raised_ground_contact(t) -> void:
	t.begin_case()
	var ground := Vector3(0.0, 4.0, -6.0)
	var scene := _build(t, ground)
	var data := scene["data"] as GiantSwordDescentComponent
	_hold(scene, 30)
	_release(scene)
	t.assert_true(_until_phase(scene, "impact"), "高台地面能够完成镇落")
	t.assert_true(data.sword_tip.distance_to(ground) < 0.001, "高台剑尖在真实4m地面停下")
	t.assert_eq(data.target_point.y, 4.0, "地面高度独立于角色根高度")


static func _test_shared_hit_ledger(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var point := (scene["cast"] as SwordCastComponent).aim_surface_point
	var center := _dummy(t, point)
	var nearby := _dummy(t, point + Vector3(2.0, 0.0, 0.0))
	var remote := _dummy(t, point + Vector3(8.0, 0.0, 0.0))
	var elevated := _dummy(t, point + Vector3(2.0, 5.0, 0.0))
	_hold(scene)
	_release(scene)
	_finish(scene)
	t.assert_eq(center.hit_count, 1, "贯穿与落地冲击共用账本，中心木桩仅命中一次")
	t.assert_eq(nearby.hit_count, 1, "落地冲击覆盖附近木桩")
	t.assert_eq(remote.hit_count, 0, "冲击不命中范围外木桩")
	t.assert_eq(elevated.hit_count, 0, "落地冲击不命中高度范围外木桩")
	t.assert_eq(center.last_hit_form, SwordCastComponent.FORM_GIANT, "木桩登记本次巨剑招式")


static func _test_one_feedback_per_impact(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_hold(scene, 90)
	t.assert_eq(cast.feedback_serial, 0, "蓄势不触发重击反馈")
	_release(scene)
	t.assert_true(_until_phase(scene, "impact"), "反馈检查能够进入冲击")
	t.assert_eq(cast.feedback_serial, 1, "落地同帧只请求一次反馈")
	t.assert_eq(cast.feedback_strength, 1.0, "巨剑请求最大层级反馈")
	t.assert_eq(cast.feedback_point, (scene["data"] as GiantSwordDescentComponent).target_point,
		"反馈位置为实际接地点")
	_finish(scene)
	t.assert_eq(cast.feedback_serial, 1, "停留与消散不重复触发重击")


static func _test_release_then_switch_continues(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var data := scene["data"] as GiantSwordDescentComponent
	_hold(scene)
	_release(scene)
	cast.form = SwordCastComponent.FORM_QI
	cast.pose_kind = SwordCastComponent.POSE_THRUST
	cast.pose_weight = 0.27
	_finish(scene)
	t.assert_eq(data.impact_serial, 1, "快速点击释放后换招仍完成巨剑")
	t.assert_eq(cast.pose_kind, SwordCastComponent.POSE_THRUST, "后台巨剑不抢新招式姿态")
	t.assert_eq(cast.pose_weight, 0.27, "后台巨剑不改其它招的姿势权重")


static func _test_gather_switch_cancels(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var data := scene["data"] as GiantSwordDescentComponent
	_hold(scene, 60)
	cast.form = SwordCastComponent.FORM_RAIN
	_step(scene, 2)
	t.assert_false((scene["giant"] as GiantSwordDescent).active, "蓄势换招取消巨剑")
	t.assert_eq(data.phase, "idle", "取消清空表现阶段")
	t.assert_eq(data.sword_alpha, 0.0, "取消清空剑形")
	t.assert_eq(data.impact_serial, 0, "取消不偷偷镇落")


static func _test_cancel_and_reuse(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var data := scene["data"] as GiantSwordDescentComponent
	_hold(scene, 60)
	_release(scene)
	_until_phase(scene, "descent")
	cast.request_cancel()
	_step(scene, 2)
	t.assert_false((scene["giant"] as GiantSwordDescent).active, "取消序号能撤销释放中的巨剑")
	t.assert_true(data.tip_history.is_empty(), "取消撤销轨迹历史")
	t.assert_eq(data.rune_alpha, 0.0, "取消撤销符环")
	t.assert_eq(cast.feedback_serial, 0, "落地前取消不请求反馈")
	_step(scene, 60)
	_hold(scene)
	_release(scene)
	_finish(scene)
	t.assert_eq(data.impact_serial, 1, "取消后能够再次施法且账本独立")
	t.assert_eq(TimeKeeper.request_count(), 0, "能力自身不留下时停请求")


static func _test_exit_and_component_unload(t) -> void:
	t.begin_case()
	var scene := _build(t)
	_hold(scene, 45)
	var giant := scene["giant"] as GiantSwordDescent
	giant.get_parent().remove_child(giant)
	giant.free()
	var data := scene["data"] as GiantSwordDescentComponent
	t.assert_eq(data.phase, "idle", "能力退出树清空表现")
	t.assert_eq(data.sword_alpha, 0.0, "能力退出树撤销剑体")
	scene = _build(t)
	_hold(scene, 45)
	data = scene["data"] as GiantSwordDescentComponent
	data.get_parent().remove_child(data)
	_step(scene)
	t.assert_false((scene["giant"] as GiantSwordDescent).active, "独立组件卸载使能力失活")
	t.assert_eq(data.phase, "idle", "组件卸载也清残留快照")
	data.free()


static func _test_cooldown(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_hold(scene)
	_release(scene)
	_finish(scene)
	_hold(scene)
	t.assert_eq(cast.casts_total, 1, "流程刚结束不绕过冷却")
	_release(scene)
	_step(scene, 60)
	_hold(scene)
	t.assert_eq(cast.casts_total, 2, "冷却后能够重复施法")


static func _test_view_geometry(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var data := scene["data"] as GiantSwordDescentComponent
	var view := GiantSwordDescentView.new()
	view.bind(data)
	t.track(view)
	view.set_process(false)
	_hold(scene, 60)
	_release(scene)
	_until_phase(scene, "impact")
	view.render_snapshot()
	var blade := view.get_node("GiantBlade") as MeshInstance3D
	var actual_tip := blade.global_transform * Vector3(0.0, 0.0, -SwordSpellVisual.TIP_LENGTH)
	t.assert_true(actual_tip.distance_to(data.sword_tip) < 0.001, "可见几何剑尖与命中剑尖完全一致")
	t.assert_true(blade.mesh != null and blade.material_override is ShaderMaterial, "完整主剑使用共享网格与独立暗刃材质")
	t.assert_true(view.get_node("CrownGlyphs") is MeshInstance3D, "冠环符纹表现存在")
	t.assert_true(view.get_node("ShockOuter") is MeshInstance3D, "落地扩散环表现存在")
	_finish(scene)
	view.render_snapshot()
	t.assert_false(view.visible, "完成后视图自隐藏，不残留剑体")
