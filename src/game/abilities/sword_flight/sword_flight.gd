class_name SwordFlight
extends Capability

## 御剑飞行：F key-down 边沿切换；飞行期间写水平与竖直速度意图并阻塞普通移动与跳跃。
##
## 只写意图，不执行物理；唯一 move_and_slide() 在 Swordsman 根节点。
## 参数来自 SwordsmanMotionComponent，本能力不内联数值。
## 阻塞清账三条路径：再按 F 失活 / 外部把 flight_active 置 false 后下一 tick 失活 /
## 节点退出场景树（_exit_tree）。任何一条都不得让宿主继续处于御剑状态。

## 御剑期间封锁普通移动与跳跃的 tag；只登记 instigator 为自身，不影响其他 instigator。
const BLOCK_TAG := &"sword_flight_block"

## 升起窗口结束的逻辑时刻（manager_time），仅地面启动时有意义。
var _launch_until: float = 0.0
## 是否处于地面启动的升起窗口。
var _launching: bool = false
## 激活后的第一个 tick：非地面启动时保留上一帧竖直动量。
var _first_tick: bool = false
## 激活时缓存宿主与组件，供 _exit_tree 清账（此时可能已取不到父节点）。
var _host_ref: Node = null
var _motion_ref: SwordsmanMotionComponent = null


func _init() -> void:
	priority = 100


func _should_activate() -> bool:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	return motion != null and motion.flight_toggle_pressed and not motion.flight_active


func _on_activated() -> void:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	var host := game_object()
	if motion == null or host == null:
		return
	_host_ref = host
	_motion_ref = motion
	motion.flight_active = true
	TagRegistry.add_block(host, BLOCK_TAG, self)
	_first_tick = true
	_launching = motion.on_floor
	if _launching:
		_launch_until = manager_time() + motion.flight_launch_time


func _tick_active(_delta: float) -> void:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	var host := game_object() as CharacterBody3D
	if motion == null or host == null:
		return
	var direction := motion.camera_right * motion.move_input.x - motion.camera_forward * motion.move_input.y
	direction.y = 0.0
	if direction.length() > 1.0:
		direction = direction.normalized()
	motion.desired_horizontal = direction * motion.flight_speed
	if _launching and manager_time() <= _launch_until:
		motion.desired_vertical = motion.flight_launch_speed
	elif _first_tick:
		motion.desired_vertical = clampf(host.velocity.y, -motion.flight_sink_speed, motion.flight_lift_speed)
	elif motion.vertical_input > 0.0:
		motion.desired_vertical = motion.flight_lift_speed
	elif motion.vertical_input < 0.0:
		motion.desired_vertical = -motion.flight_sink_speed
	else:
		motion.desired_vertical = 0.0
	_first_tick = false


func _should_deactivate() -> bool:
	var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	return motion == null or not motion.flight_active or motion.flight_toggle_pressed


func _on_deactivated() -> void:
	_clear_flight_state()
	_host_ref = null
	_motion_ref = null


## 节点退出场景树：装配被移除时也必须清 flight_active 与自己的阻塞。
func _exit_tree() -> void:
	_clear_flight_state()


func _clear_flight_state() -> void:
	var motion := _motion_ref
	if motion == null or not is_instance_valid(motion):
		motion = component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
	if motion != null:
		motion.flight_active = false
	var host := _host_ref
	if host == null or not is_instance_valid(host):
		host = game_object()
	if host != null and is_instance_valid(host):
		TagRegistry.remove_block(host, BLOCK_TAG, self)
	_launching = false
	_launch_until = 0.0
	_first_tick = false

