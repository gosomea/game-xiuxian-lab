extends RefCounted
## test_flying_sword_strike：飞剑出击能力配对测试。
## 覆盖：按下边沿出击并登记 sword_away_block、御剑期间与招式不符不激活、
## 去程命中、飞回悬浮位后失活清账、剑在外不重复出击、退出场景树清账、优先级。

const DT := 1.0 / 60.0
const TAG := &"sword_away_block"


static func run(t) -> void:
	_test_press_launches_and_blocks(t)
	_test_blocked_while_flying(t)
	_test_requires_matching_form(t)
	_test_hits_target_and_returns(t)
	_test_no_second_strike_while_away(t)
	_test_exit_tree_clears_block(t)
	_test_priority(t)


static func _build(t) -> Dictionary:
	var host := Node3D.new()
	t.track(host)
	var cast := SwordCastComponent.new()
	host.add_child(cast)
	var manager := CapabilityManager.new()
	manager.set_process(false)
	host.add_child(manager)
	var strike := FlyingSwordStrike.new()
	manager.add_child(strike)
	cast.form = SwordCastComponent.FORM_STRIKE
	cast.aim_point = Vector3(0.0, 0.0, -8.0)
	return {"host": host, "cast": cast, "manager": manager, "strike": strike}


static func _press(scene: Dictionary) -> void:
	var cast := scene["cast"] as SwordCastComponent
	cast.cast_pressed = true
	(scene["manager"] as CapabilityManager).tick(DT)
	cast.cast_pressed = false


static func _run_until_idle(scene: Dictionary, limit: int = 600) -> int:
	var strike := scene["strike"] as FlyingSwordStrike
	for i in range(limit):
		(scene["manager"] as CapabilityManager).tick(DT)
		if not strike.active:
			return i
	return limit


static func _test_press_launches_and_blocks(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press(scene)
	t.assert_true((scene["strike"] as FlyingSwordStrike).active, "按下边沿激活")
	t.assert_true(cast.sword_away, "本命剑离开悬浮位")
	t.assert_eq(TagRegistry.block_count(scene["host"], TAG), 1, "剑在外期间登记 sword_away_block")
	t.assert_eq(cast.casts_total, 1, "登记一次出招")
	var start := cast.rest_position((scene["host"] as Node3D).global_position, Vector3.FORWARD)
	t.assert_true(cast.sword_position.distance_to(start) < 0.6, "从悬浮位附近起飞")


static func _test_blocked_while_flying(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var blocker := Node.new()
	t.track(blocker)
	TagRegistry.add_block(scene["host"], &"sword_flight_block", blocker)
	_press(scene)
	t.assert_false((scene["strike"] as FlyingSwordStrike).active, "御剑期间不能飞剑出击")
	t.assert_false((scene["cast"] as SwordCastComponent).sword_away, "本命剑仍在悬浮位")
	TagRegistry.remove_block(scene["host"], &"sword_flight_block", blocker)


static func _test_requires_matching_form(t) -> void:
	t.begin_case()
	var scene := _build(t)
	(scene["cast"] as SwordCastComponent).form = SwordCastComponent.FORM_QI
	_press(scene)
	t.assert_false((scene["strike"] as FlyingSwordStrike).active, "招式不是飞剑时不激活")


static func _test_hits_target_and_returns(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	var dummy := Node3D.new()
	var target := SwordTargetComponent.new()
	dummy.add_child(target)
	dummy.add_to_group(&"sword_target")
	t.track(dummy)
	dummy.global_position = Vector3(0.0, 0.0, -8.0)
	_press(scene)
	var ticks := _run_until_idle(scene)
	t.assert_true(ticks < 600, "飞剑在有限时间内飞回（%d tick）" % ticks)
	t.assert_true(target.hit_count >= 1, "飞剑命中指向点处的木桩（%d 次）" % target.hit_count)
	t.assert_true(target.hit_count <= 2, "去程与回程各至多命中一次（%d 次）" % target.hit_count)
	t.assert_false(cast.sword_away, "飞回后本命剑回到悬浮位")
	t.assert_eq(TagRegistry.block_count(scene["host"], TAG), 0, "飞回后撤销 sword_away_block")
	var home := cast.rest_position((scene["host"] as Node3D).global_position, Vector3.FORWARD)
	t.assert_true(cast.sword_position.distance_to(home) < 0.01, "最后位置就是悬浮位")


static func _test_no_second_strike_while_away(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press(scene)
	_press(scene)
	t.assert_eq(cast.casts_total, 1, "剑在外时再次按下不重复出击")
	_run_until_idle(scene)
	_press(scene)
	t.assert_eq(cast.casts_total, 2, "剑飞回后可再次出击")


static func _test_exit_tree_clears_block(t) -> void:
	t.begin_case()
	var scene := _build(t)
	var cast := scene["cast"] as SwordCastComponent
	_press(scene)
	var strike := scene["strike"] as FlyingSwordStrike
	strike.get_parent().remove_child(strike)
	strike.free()
	t.assert_eq(TagRegistry.block_count(scene["host"], TAG), 0, "能力退出场景树时撤销阻塞")
	t.assert_false(cast.sword_away, "能力退出场景树时本命剑回到悬浮状态")


static func _test_priority(t) -> void:
	t.begin_case()
	var strike := FlyingSwordStrike.new()
	t.track(strike)
	t.assert_eq(strike.priority, 45, "飞剑出击优先级低于跳跃、高于剑气与剑阵")
