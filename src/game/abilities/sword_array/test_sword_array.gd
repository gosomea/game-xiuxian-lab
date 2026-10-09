extends RefCounted
## test_sword_array：剑阵能力配对测试。
## 覆盖：招式不符不激活、按住逐把蓄剑、上限、松开逐把射出、落点木桩命中、
## 全部消散后失活与冷却、退出场景树清渲染数据、优先级。

const DT := 1.0 / 60.0


static func run(t) -> void:
	_test_requires_matching_form(t)
	_test_hold_gathers_over_time(t)
	_test_gather_respects_max(t)
	_test_release_fires_and_hits(t)
	_test_cooldown_after_volley(t)
	_test_exit_tree_clears_swords(t)
	_test_priority(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var cast := SwordCastComponent.new()
	host.add_child(cast)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var array := SwordArray.new()
	manager.add_child(array)
	cast.form = SwordCastComponent.FORM_ARRAY
	cast.aim_point = Vector3(0.0, 0.0, -6.0)
	return {"host": host, "cast": cast, "manager": manager, "array": array}


static func _press_and_hold(scene: Dictionary, ticks: int) -> void:
	var cast := scene["cast"] as SwordCastComponent
	var manager := scene["manager"] as CapabilityManager
	cast.cast_held = true
	cast.cast_pressed = true
	manager.tick(DT)
	cast.cast_pressed = false
	for i in range(ticks):
		manager.tick(DT)


static func _release(scene: Dictionary) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_held = false
	cast.cast_released = true
	(scene["manager"] as CapabilityManager).tick(DT)
	cast.cast_released = false


static func _run_until_idle(scene: Dictionary, limit: int = 900) -> int:
	var array := scene["array"] as SwordArray
	for i in range(limit):
		(scene["manager"] as CapabilityManager).tick(DT)
		if not array.active:
			return i
	return limit


static func _test_requires_matching_form(t) -> void:
	t.begin_case()
	var scene := _build(t)
	(scene["cast"] as SwordCastComponent).form = SwordCastComponent.FORM_QI
	_press_and_hold(scene, 3)
	t.assert_false((scene["array"] as SwordArray).active, "招式不是剑阵时不激活")


static func _test_hold_gathers_over_time(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press_and_hold(scene, 0)
	t.assert_eq(cast.array_swords.size(), 1, "按下当帧出现第一把剑")
	t.assert_eq(cast.pose_kind, SwordCastComponent.POSE_RAISE, "蓄势请求斜上举姿势")
	_press_and_hold(scene, 0)
	for i in range(30):
		(scene["manager"] as CapabilityManager).tick(DT)
	var expected := 1 + int(floor((31.0 * DT) / cast.array_spawn_interval + 0.0001))
	t.assert_true(absi(cast.array_swords.size() - expected) <= 1,
		"按住约 0.5 秒逐把蓄剑（%d 把，预期约 %d）" % [cast.array_swords.size(), expected])
	var host := scene["host"] as Node3D
	var behind := 0
	for sword in cast.array_swords:
		if ((sword["position"] as Vector3) - host.global_position).dot(Vector3.FORWARD) < 0.0:
			behind += 1
	t.assert_eq(behind, cast.array_swords.size(), "蓄势的剑全部悬在身后（面向 -Z）")


static func _test_gather_respects_max(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	cast.array_max = 5
	_press_and_hold(scene, 120)
	t.assert_eq(cast.array_swords.size(), 5, "蓄剑数不超过上限")


static func _test_release_fires_and_hits(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	cast.array_max = 12
	var dummy := Node3D.new()
	var target := SwordTargetComponent.new()
	dummy.add_child(target)
	dummy.add_to_group(&"sword_target")
	t.track(dummy)
	dummy.global_position = Vector3(0.0, 0.0, -6.0)
	_press_and_hold(scene, 60)
	_release(scene)
	var ticks := _run_until_idle(scene)
	t.assert_true(ticks < 900, "齐射在有限时间内结束（%d tick）" % ticks)
	t.assert_true(target.hit_count >= 1, "落点处木桩被剑阵命中（%d 次）" % target.hit_count)
	t.assert_true(target.hit_count <= 12, "每把剑至多命中一次（%d 次）" % target.hit_count)
	t.assert_true(cast.array_swords.is_empty(), "全部剑消散后清空渲染数据")


static func _test_cooldown_after_volley(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	cast.array_max = 3
	_press_and_hold(scene, 10)
	_release(scene)
	_run_until_idle(scene)
	var casts := cast.casts_total
	_press_and_hold(scene, 0)
	t.assert_eq(cast.casts_total, casts, "齐射刚结束时处于冷却")
	_release(scene)
	for i in range(int(ceil(cast.array_cooldown / DT)) + 1):
		(scene["manager"] as CapabilityManager).tick(DT)
	_press_and_hold(scene, 0)
	t.assert_eq(cast.casts_total, casts + 1, "冷却结束后可再次结阵")


static func _test_exit_tree_clears_swords(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press_and_hold(scene, 10)
	var array := scene["array"] as SwordArray
	array.get_parent().remove_child(array)
	array.free()
	t.assert_true(cast.array_swords.is_empty(), "能力退出场景树时清空剑阵渲染数据")


static func _test_priority(t) -> void:
	t.begin_case()
	var array := SwordArray.new()
	t.track(array)
	t.assert_eq(array.priority, 40, "剑阵优先级与剑气相同")
