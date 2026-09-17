class_name CapabilityManager
extends Node

## Capability 调度器：作为 GameObject 的子节点，轮询自己的 Capability 子节点。
##
## 轮询而非事件驱动是有意选择：并行激活语义天然，代价是每帧固定开销。
## 参考量级：Split Fiction 每玩家约 250 个能力轮询约 0.5ms/帧。

## 逻辑时间：随每次 tick 累加。能力的冷却与持续时长读这里，不读墙钟时间，
## 因此无头测试可用手动 tick 精确推进时序。
var elapsed: float = 0.0


## 推进一帧调度。激活当帧即执行 _tick_active——五函数轴是同帧连续的。
func tick(delta: float) -> void:
	elapsed += delta
	for capability in sorted_capabilities():
		if not capability.active:
			if capability._should_activate():
				capability.active = true
				capability._on_activated()
				capability._tick_active(delta)
		elif capability._should_deactivate():
			capability.active = false
			capability._on_deactivated()
		else:
			capability._tick_active(delta)


func sorted_capabilities() -> Array[Capability]:
	var result: Array[Capability] = []
	for child in get_children():
		if child is Capability:
			result.append(child)
	result.sort_custom(func(a: Capability, b: Capability) -> bool: return a.priority > b.priority)
	return result


func _process(delta: float) -> void:
	tick(delta)
