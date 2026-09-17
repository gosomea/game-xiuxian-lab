class_name VitalsGuard
extends Capability

## 生命护盾：危急时自动提供伤害减免，并阻塞再生（表达「护盾与再生互斥」）。
##
## 通用示例能力之二。它演示本架构的核心解耦：
## **本能力完全不认识 VitalsRegeneration**，只做两件事——往 VitalsComponent 写减免记录、
## 往 TagRegistry 写 regen_block 阻塞。再生能力现算自己该不该激活，于是互斥自动成立。
##
## 阻塞带 instigator（self），解除时只移除自己那一条——
## 若同时有其他系统也阻塞了再生，不会被本能力误删。

## 伤害减免比例（0.0–1.0）
@export var damage_reduction: float = 0.5
## 护盾持续时长（秒，逻辑时间）；<= 0 表示只要危急就一直生效
@export var duration: float = 5.0

var _activated_at: float = 0.0


func _should_activate() -> bool:
	var vitals := component(&"VitalsComponent") as VitalsComponent
	if vitals == null or vitals.is_depleted():
		return false
	return vitals.is_critical()


func _on_activated() -> void:
	_activated_at = manager_time()
	var vitals := component(&"VitalsComponent") as VitalsComponent
	if vitals != null:
		vitals.add_mitigation(get_instance_id(), damage_reduction)
	var host := game_object()
	if host != null:
		TagRegistry.add_block(host, &"regen_block", self)


func _should_deactivate() -> bool:
	var vitals := component(&"VitalsComponent") as VitalsComponent
	if vitals == null or vitals.is_depleted():
		return true
	if duration > 0.0 and manager_time() - _activated_at >= duration:
		return true
	return not vitals.is_critical()


func _on_deactivated() -> void:
	_release()


func _exit_tree() -> void:
	_release()
	TagRegistry.remove_all_from(self)


func _release() -> void:
	var vitals := component(&"VitalsComponent") as VitalsComponent
	if vitals != null:
		vitals.remove_mitigation(get_instance_id())
	var host := game_object()
	if host != null:
		TagRegistry.remove_block(host, &"regen_block", self)
