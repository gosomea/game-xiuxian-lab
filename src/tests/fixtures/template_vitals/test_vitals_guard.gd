extends RefCounted
## test_vitals_guard：护盾能力测试。
## 覆盖：危急时激活并写减免、伤害真实降低、失活清账、持续时间到期、instigator 隔离、
## 以及与再生能力的零耦合互斥（本文件的重点）。

const Harness := preload("res://tests/harness.gd")


static func run(t) -> void:
	_test_activates_when_critical(t)
	_test_reduces_actual_damage(t)
	_test_cleans_up_on_deactivate(t)
	_test_duration_expires(t)
	_test_instigator_isolation(t)
	_test_guard_suppresses_regen_without_coupling(t)


static func _build(t, current: float) -> Dictionary:
	var actor := Harness.make_actor(t, current, 100.0)
	var guard := VitalsGuard.new()
	guard.damage_reduction = 0.5
	guard.duration = 5.0
	(actor["manager"] as CapabilityManager).add_child(guard)
	return {"actor": actor, "guard": guard}


static func _test_activates_when_critical(t) -> void:
	t.begin_case()
	var scene := _build(t, 20.0)
	(scene["actor"]["manager"] as CapabilityManager).tick(0.1)

	t.assert_true((scene["guard"] as VitalsGuard).active, "危急比例以下应激活")
	t.assert_eq((scene["actor"]["vitals"] as VitalsComponent).mitigation_count(), 1, "应写入一条减免记录")


static func _test_reduces_actual_damage(t) -> void:
	t.begin_case()
	var scene := _build(t, 20.0)
	var vitals := scene["actor"]["vitals"] as VitalsComponent

	(scene["actor"]["manager"] as CapabilityManager).tick(0.1)
	var actual := vitals.apply_damage(10.0)
	t.assert_eq(actual, 5.0, "50% 减免下 10 点伤害应只造成 5 点")


static func _test_cleans_up_on_deactivate(t) -> void:
	t.begin_case()
	var scene := _build(t, 20.0)
	var manager := scene["actor"]["manager"] as CapabilityManager
	var vitals := scene["actor"]["vitals"] as VitalsComponent

	manager.tick(0.1)
	vitals.restore(60.0)
	manager.tick(0.1)

	t.assert_false((scene["guard"] as VitalsGuard).active, "脱离危急后应失活")
	t.assert_eq(vitals.mitigation_count(), 0, "失活后减免记录必须清空")
	t.assert_false(TagRegistry.is_blocked(scene["actor"]["node"], &"regen_block"), "失活后阻塞必须撤销")


static func _test_duration_expires(t) -> void:
	t.begin_case()
	var scene := _build(t, 20.0)
	var manager := scene["actor"]["manager"] as CapabilityManager

	manager.tick(0.1)
	t.assert_true((scene["guard"] as VitalsGuard).active, "应先激活")
	manager.tick(6.0)
	t.assert_false((scene["guard"] as VitalsGuard).active, "持续时间到期后应失活，即使仍处危急")


static func _test_instigator_isolation(t) -> void:
	t.begin_case()
	var scene := _build(t, 20.0)
	var manager := scene["actor"]["manager"] as CapabilityManager
	var node := scene["actor"]["node"] as Node

	manager.tick(0.1)
	var other: Node = t.track(Node.new())
	TagRegistry.add_block(node, &"regen_block", other)
	t.assert_eq(TagRegistry.block_count(node, &"regen_block"), 2, "两个发起者应各占一条")

	(scene["actor"]["vitals"] as VitalsComponent).restore(60.0)
	manager.tick(0.1)
	t.assert_true(
		TagRegistry.is_blocked(node, &"regen_block"),
		"护盾撤销自己的阻塞时，不得误删其他发起者的阻塞"
	)


## 本架构的核心验证：两个能力之间没有任何一行互相调用，
## 互斥完全通过 TagRegistry 这个共享词汇达成。
static func _test_guard_suppresses_regen_without_coupling(t) -> void:
	t.begin_case()
	var actor := Harness.make_actor(t, 20.0, 100.0)
	var manager := actor["manager"] as CapabilityManager

	var guard := VitalsGuard.new()
	guard.damage_reduction = 0.5
	guard.duration = 0.0
	manager.add_child(guard)

	var regen := VitalsRegeneration.new()
	regen.rate_per_second = 10.0
	regen.idle_delay = 0.0
	manager.add_child(regen)

	manager.tick(0.1)
	t.assert_true(guard.active, "危急时护盾应激活")
	t.assert_false(regen.active, "护盾激活期间再生应被阻塞（零代码互调）")

	var vitals := actor["vitals"] as VitalsComponent
	vitals.restore(60.0)
	manager.tick(0.1)
	manager.tick(0.1)
	t.assert_false(guard.active, "脱离危急后护盾失活")
	t.assert_true(regen.active, "护盾失活后再生自动恢复")
