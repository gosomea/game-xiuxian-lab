extends RefCounted
## 测试夹具：快速搭建符合架构约定的 GameObject。


## 通用行动者：Node2D + VitalsComponent + CapabilityManager，加入 actor 组。
static func make_actor(t, current: float, maximum: float) -> Dictionary:
	var node := Node2D.new()
	node.add_to_group(&"actor")
	t.track(node)

	var vitals := VitalsComponent.new()
	vitals.maximum = maximum
	vitals.current = current
	node.add_child(vitals)

	var manager := CapabilityManager.new()
	manager.set_process(false)
	node.add_child(manager)

	return {"node": node, "vitals": vitals, "manager": manager}
