class_name VitalsRegeneration
extends Capability

## 生命再生：脱离战斗一段时间后，按秒恢复生命值；被 regen_block 阻塞时停止。
##
## 通用示例能力之一。它演示三件事：
## 1. 激活条件读取 Tag 阻塞（regen_block）——不认识是谁阻塞的，也不需要认识；
## 2. 用调度器逻辑时间（manager_time）做延迟判断，而非墙钟时间，使无头测试可精确推进；
## 3. 满值即自行失活，不占用调度开销。

## 每秒恢复量
@export var rate_per_second: float = 5.0
## 触发再生所需的「安静」时长（秒，逻辑时间）
@export var idle_delay: float = 3.0

## 最近一次被打断的时刻（由外部通过 interrupt() 通知，或由阻塞状态推断）
var _last_interrupt_time: float = -INF


## 供其他系统调用的打断入口（例如受伤能力在造成伤害后调用）。
## 注意这是「数据通知」而非「能力互调」：调用方不需要知道本能力存在，
## 通常由 VitalsComponent 的 signal 连到这里，或由宿主统一转发。
func interrupt() -> void:
	_last_interrupt_time = manager_time()


func _should_activate() -> bool:
	var vitals := component(&"VitalsComponent") as VitalsComponent
	if vitals == null or vitals.is_depleted():
		return false
	if vitals.current >= vitals.maximum:
		return false
	var host := game_object()
	if host == null or TagRegistry.is_blocked(host, &"regen_block"):
		return false
	return manager_time() - _last_interrupt_time >= idle_delay


func _tick_active(delta: float) -> void:
	var vitals := component(&"VitalsComponent") as VitalsComponent
	if vitals == null:
		return
	vitals.restore(rate_per_second * delta)


func _should_deactivate() -> bool:
	var vitals := component(&"VitalsComponent") as VitalsComponent
	if vitals == null or vitals.is_depleted():
		return true
	if vitals.current >= vitals.maximum:
		return true
	var host := game_object()
	if host != null and TagRegistry.is_blocked(host, &"regen_block"):
		return true
	return manager_time() - _last_interrupt_time < idle_delay
