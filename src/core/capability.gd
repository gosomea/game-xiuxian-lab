class_name Capability
extends Node

## 行为单元基类（五函数触发轴）。
##
## 通信纪律：Capability 之间禁止直接引用；只读写 Component 共享数据、用 TagRegistry 表达互斥。
## 多个 Capability 可并行激活——这不是状态机，没有状态转移线。
##
## 生命周期由 CapabilityManager 每帧轮询驱动：
## _should_activate -> _on_activated -> _tick_active -> _should_deactivate -> _on_deactivated

var active: bool = false

## 数值越大越先被评估。兜底类能力用极低值（例如「应急坠落」设为 -100）。
@export var priority: int = 0


## 宿主 GameObject（本能力的 CapabilityManager 的父节点）。
func game_object() -> Node:
	var manager := get_parent()
	if manager is CapabilityManager:
		return manager.get_parent()
	return null


## 调度器的逻辑时间（秒）。冷却与持续时长判断读这里，不读墙钟时间。
func manager_time() -> float:
	var manager := get_parent()
	if manager is CapabilityManager:
		return (manager as CapabilityManager).elapsed
	return 0.0


## 按脚本类名取宿主身上的 Component。取不到返回 null，调用方负责降级。
func component(component_class: StringName) -> Component:
	var host := game_object()
	if host == null:
		return null
	for child in host.get_children():
		if child is Component:
			var script: Script = child.get_script()
			if script != null and script.get_global_name() == component_class:
				return child
	return null


func _should_activate() -> bool:
	return false


func _on_activated() -> void:
	pass


func _tick_active(_delta: float) -> void:
	pass


func _should_deactivate() -> bool:
	return false


func _on_deactivated() -> void:
	pass
