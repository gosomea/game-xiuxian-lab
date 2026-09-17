extends RefCounted
## test_vitals_regeneration：再生能力测试。
## 覆盖：延迟未到不激活、延迟到达后恢复、满值失活、被阻塞时停止、耗尽时不再生。

const Harness := preload("res://tests/harness.gd")


static func run(t) -> void:
	_test_waits_for_idle_delay(t)
	_test_restores_after_delay(t)
	_test_deactivates_when_full(t)
	_test_blocked_stops_regen(t)
	_test_depleted_never_regens(t)


static func _build(t, current: float) -> Dictionary:
	var actor := Harness.make_actor(t, current, 100.0)
	var regen := VitalsRegeneration.new()
	regen.rate_per_second = 10.0
	regen.idle_delay = 3.0
	(actor["manager"] as CapabilityManager).add_child(regen)
	return {"actor": actor, "regen": regen}


static func _test_waits_for_idle_delay(t) -> void:
	t.begin_case()
	var scene := _build(t, 50.0)
	var regen := scene["regen"] as VitalsRegeneration
	regen.interrupt()

	(scene["actor"]["manager"] as CapabilityManager).tick(1.0)
	t.assert_false(regen.active, "打断后延迟未满不应激活")


static func _test_restores_after_delay(t) -> void:
	t.begin_case()
	var scene := _build(t, 50.0)
	var manager := scene["actor"]["manager"] as CapabilityManager
	var vitals := scene["actor"]["vitals"] as VitalsComponent

	manager.tick(3.5)
	t.assert_true((scene["regen"] as VitalsRegeneration).active, "延迟满足后应激活")
	t.assert_true(vitals.current > 50.0, "激活当帧即应开始恢复")


static func _test_deactivates_when_full(t) -> void:
	t.begin_case()
	var scene := _build(t, 95.0)
	var manager := scene["actor"]["manager"] as CapabilityManager
	var vitals := scene["actor"]["vitals"] as VitalsComponent

	manager.tick(3.5)
	manager.tick(1.0)
	manager.tick(0.1)
	t.assert_eq(vitals.current, 100.0, "恢复不应超过上限")
	t.assert_false((scene["regen"] as VitalsRegeneration).active, "满值后应自行失活")


static func _test_blocked_stops_regen(t) -> void:
	t.begin_case()
	var scene := _build(t, 50.0)
	var blocker: Node = t.track(Node.new())
	TagRegistry.add_block(scene["actor"]["node"], &"regen_block", blocker)

	(scene["actor"]["manager"] as CapabilityManager).tick(3.5)
	t.assert_false((scene["regen"] as VitalsRegeneration).active, "被 regen_block 阻塞时不应激活")


static func _test_depleted_never_regens(t) -> void:
	t.begin_case()
	var scene := _build(t, 0.0)
	(scene["actor"]["manager"] as CapabilityManager).tick(3.5)
	t.assert_false((scene["regen"] as VitalsRegeneration).active, "数值耗尽后不应自行再生")
