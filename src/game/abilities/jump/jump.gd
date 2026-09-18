class_name Jump
extends Capability

## 跳跃：空格 key-down 边沿且上一帧着地时，写一帧竖直冲量。
##
## 只写意图，不执行物理、不碰宿主速度；下一次调度即失活，天然单帧冲量。
## 空中或御剑（sword_flight_block）时不可激活；按住空格不会连跳（边沿由场景产生）。
## 参数来自 SwordsmanMotionComponent，本能力不内联数值。

func _init() -> void:
	priority = 50


func _should_activate() -> bool:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	if motion == null or not motion.jump_pressed or not motion.on_floor:
		return false
	var host := game_object()
	return host != null and not TagRegistry.is_blocked(host, &"sword_flight_block")


func _tick_active(_delta: float) -> void:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	if motion == null:
		return
	motion.vertical_impulse = motion.jump_speed


func _should_deactivate() -> bool:
	# 一帧冲量发射器：写完即收回，由 manager 下一 tick 失活。
	return true


func _on_deactivated() -> void:
	pass
