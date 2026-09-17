extends RefCounted
## test_core：核心设施测试（TagRegistry instigator 语义、TimeKeeper 叠加、调度器、Sheet 装配）。

const Harness := preload("res://tests/harness.gd")


static func run(t) -> void:
	_test_tag_instigator_isolation(t)
	_test_tag_remove_all_from(t)
	_test_time_keeper_min_scale(t)
	_test_capability_manager_priority(t)
	_test_capability_manager_logical_time(t)
	_test_sheet_attach_detach(t)


static func _test_tag_instigator_isolation(t) -> void:
	t.begin_case()
	var target: Node = t.track(Node.new())
	var first: Node = t.track(Node.new())
	var second: Node = t.track(Node.new())

	TagRegistry.add_block(target, &"regen_block", first)
	TagRegistry.add_block(target, &"regen_block", second)
	t.assert_eq(TagRegistry.block_count(target, &"regen_block"), 2, "两个发起者各占一条记录")

	TagRegistry.remove_block(target, &"regen_block", first)
	t.assert_true(TagRegistry.is_blocked(target, &"regen_block"), "移除第一个发起者后第二个的阻塞仍在")

	TagRegistry.remove_block(target, &"regen_block", second)
	t.assert_false(TagRegistry.is_blocked(target, &"regen_block"), "全部发起者移除后阻塞解除")


static func _test_tag_remove_all_from(t) -> void:
	t.begin_case()
	var alpha: Node = t.track(Node.new())
	var beta: Node = t.track(Node.new())
	var instigator: Node = t.track(Node.new())

	TagRegistry.add_block(alpha, &"regen_block", instigator)
	TagRegistry.add_block(beta, &"regen_block", instigator)
	TagRegistry.remove_all_from(instigator)

	t.assert_false(TagRegistry.is_blocked(alpha, &"regen_block"), "退场清账应清理第一个目标")
	t.assert_false(TagRegistry.is_blocked(beta, &"regen_block"), "退场清账应清理第二个目标")


static func _test_time_keeper_min_scale(t) -> void:
	t.begin_case()
	var slow: Node = t.track(Node.new())
	var stop: Node = t.track(Node.new())

	TimeKeeper.request(slow, 0.5)
	t.assert_eq(TimeKeeper.current_scale(), 0.5, "单个减速请求生效")

	TimeKeeper.request(stop, 0.0)
	t.assert_eq(TimeKeeper.current_scale(), 0.0, "最强减速胜出")

	TimeKeeper.release(stop)
	t.assert_eq(TimeKeeper.current_scale(), 0.5, "释放时停后回到减速档")

	TimeKeeper.release(slow)
	t.assert_eq(TimeKeeper.current_scale(), 1.0, "全部释放后恢复正常速度")


static func _test_capability_manager_priority(t) -> void:
	t.begin_case()
	var actor := Harness.make_actor(t, 100.0, 100.0)
	var manager := actor["manager"] as CapabilityManager

	var guard := VitalsGuard.new()
	guard.priority = 10
	manager.add_child(guard)
	var regen := VitalsRegeneration.new()
	regen.priority = 5
	manager.add_child(regen)

	var order := manager.sorted_capabilities()
	t.assert_eq(order.size(), 2, "调度器应收集全部 Capability 子节点")
	t.assert_eq(order[0], guard, "priority 高的能力先被评估")


static func _test_capability_manager_logical_time(t) -> void:
	t.begin_case()
	var actor := Harness.make_actor(t, 100.0, 100.0)
	var manager := actor["manager"] as CapabilityManager

	t.assert_eq(manager.elapsed, 0.0, "逻辑时间初始为 0")
	manager.tick(0.5)
	manager.tick(0.25)
	t.assert_eq(manager.elapsed, 0.75, "逻辑时间应累加每次 tick 的 delta")


static func _test_sheet_attach_detach(t) -> void:
	t.begin_case()
	var host: Node = t.track(Node2D.new())
	host.add_to_group(&"actor")

	var sheet := SheetLoader.attach(host, "res://tests/fixtures/template_vitals/vitals_sheet.tscn")
	t.assert_true(sheet != null, "Sheet 应装配成功")
	if sheet == null:
		return

	var has_component := false
	for child in sheet.get_children():
		if child is VitalsComponent:
			has_component = true
	t.assert_true(has_component, "Sheet 应带来 VitalsComponent")

	SheetLoader.detach(sheet)
	t.assert_eq(host.get_child_count(), 0, "卸载后宿主不应残留 Sheet 节点")
