extends RefCounted
## test_sword_qi：剑气能力配对测试。
## 覆盖：招式不符不激活、按下边沿出剑并登记出招、飞行穿透各命中一次、冷却、
## 飞满射程失活、退出场景树清渲染数据、优先级。

const DT := 1.0 / 60.0


static func run(t) -> void:
	_test_requires_matching_form(t)
	_test_press_spawns_and_records(t)
	_test_pierces_each_target_once(t)
	_test_cooldown(t)
	_test_deactivates_after_range(t)
	_test_exit_tree_clears_shots(t)
	_test_priority(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var cast := SwordCastComponent.new()
	host.add_child(cast)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var qi := SwordQi.new()
	manager.add_child(qi)
	cast.form = SwordCastComponent.FORM_QI
	cast.aim_point = Vector3(0.0, 0.0, -10.0)
	return {"host": host, "cast": cast, "manager": manager, "qi": qi}


static func _target(t, position: Vector3) -> SwordTargetComponent:
	var host := Node3D.new()
	var target := SwordTargetComponent.new()
	host.add_child(target)
	host.add_to_group(&"sword_target")
	t.track(host)
	host.global_position = position
	return target


static func _press(scene: Dictionary) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_pressed = true
	(scene["manager"] as CapabilityManager).tick(DT)
	cast.cast_pressed = false


static func _test_requires_matching_form(t) -> void:
	t.begin_case()
	var scene := _build(t)
	(scene["cast"] as SwordCastComponent).form = SwordCastComponent.FORM_ARRAY
	_press(scene)
	t.assert_false((scene["qi"] as SwordQi).active, "招式不是剑气时按下左键不激活")
	t.assert_true((scene["cast"] as SwordCastComponent).qi_shots.is_empty(), "不生成剑气")


static func _test_press_spawns_and_records(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press(scene)
	t.assert_true((scene["qi"] as SwordQi).active, "按下边沿激活")
	t.assert_eq(cast.qi_shots.size(), 1, "生成一道剑气")
	t.assert_eq(cast.casts_total, 1, "登记一次出招")
	t.assert_eq(cast.last_cast_form, SwordCastComponent.FORM_QI, "最近招式为剑气")
	t.assert_eq(cast.pose_kind, SwordCastComponent.POSE_THRUST, "剑气请求前指姿势")
	var shot: Dictionary = cast.qi_shots[0]
	t.assert_true((shot["direction"] as Vector3).distance_to(Vector3(0, 0, -1)) < 0.001, "剑气朝指向点水平飞行")
	t.assert_true(absf((shot["position"] as Vector3).y - cast.qi_height) < 0.001, "剑气离地高度取参数")
	t.assert_true(cast.facing_requested((scene["manager"] as CapabilityManager).elapsed), "出招后请求面向")


static func _test_pierces_each_target_once(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var near := _target(t, Vector3(0.0, 0.0, -4.0))
	var far := _target(t, Vector3(0.3, 0.0, -8.0))
	var aside := _target(t, Vector3(4.0, 0.0, -6.0))
	_press(scene)
	for i in range(60):
		(scene["manager"] as CapabilityManager).tick(DT)
	t.assert_eq(near.hit_count, 1, "近处木桩命中一次（不因多帧重叠重复计数）")
	t.assert_eq(far.hit_count, 1, "剑气穿透后命中远处木桩")
	t.assert_eq(aside.hit_count, 0, "偏离剑路的木桩不被命中")
	t.assert_eq(near.last_hit_form, SwordCastComponent.FORM_QI, "命中记录招式")


static func _test_cooldown(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press(scene)
	_press(scene)
	t.assert_eq(cast.casts_total, 1, "冷却内再次按下不出剑")
	var ticks := int(ceil(cast.qi_cooldown / DT)) + 1
	for i in range(ticks):
		(scene["manager"] as CapabilityManager).tick(DT)
	_press(scene)
	t.assert_eq(cast.casts_total, 2, "冷却结束后可再次出剑")


static func _test_deactivates_after_range(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press(scene)
	var ticks := int(ceil(cast.qi_range / cast.qi_speed / DT)) + 2
	for i in range(ticks):
		(scene["manager"] as CapabilityManager).tick(DT)
	t.assert_true(cast.qi_shots.is_empty(), "飞满射程后剑气消散")
	t.assert_false((scene["qi"] as SwordQi).active, "没有剑气在飞时失活")


static func _test_exit_tree_clears_shots(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press(scene)
	var qi := scene["qi"] as SwordQi
	qi.get_parent().remove_child(qi)
	qi.free()
	t.assert_true(cast.qi_shots.is_empty(), "能力退出场景树时清空剑气渲染数据")


static func _test_priority(t) -> void:
	t.begin_case()
	var qi := SwordQi.new()
	t.track(qi)
	t.assert_eq(qi.priority, 40, "剑气优先级低于御剑与跳跃")
