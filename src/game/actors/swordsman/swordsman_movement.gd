class_name SwordsmanMovement
extends Capability

## 修士水平移动：把屏幕相对输入映射到相机地面基，按 move_speed 只写水平速度意图。
##
## 输入来自 SwordsmanMotionComponent，本能力不读取键鼠、不认识实验场景，
## 也不执行物理——唯一 move_and_slide() 在 Swordsman 根节点。
## 御剑期间被 sword_flight_block 阻塞；地面与非御剑空中同一套规则。
## 无输入时失活；意图字段由 actor 每帧清理，本能力不回写宿主速度。

func _init() -> void:
	priority = 0


func _should_activate() -> bool:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	if motion == null or motion.move_input == Vector2.ZERO:
		return false
	var host := game_object()
	return host != null and not TagRegistry.is_blocked(host, &"sword_flight_block")


func _tick_active(_delta: float) -> void:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	if motion == null:
		return
	# 屏幕上方（y 为负）对应相机前方，屏幕下方对应相机后方。
	var direction := motion.camera_right * motion.move_input.x - motion.camera_forward * motion.move_input.y
	direction.y = 0.0
	# 斜向输入先归一化再乘速度，避免两键同时按下时加速。
	if direction.length() > 1.0:
		direction = direction.normalized()
	motion.desired_horizontal = direction * motion.move_speed


func _should_deactivate() -> bool:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	if motion == null or motion.move_input == Vector2.ZERO:
		return true
	var host := game_object()
	return host != null and TagRegistry.is_blocked(host, &"sword_flight_block")


func _on_deactivated() -> void:
	pass
