class_name QuarterTurn
extends Capability

## 固定俯角四向切换（镜头模式 B，长期语义名 quarter_turn）。
##
## 与 fixed_follow 的区别：偏航不再自由，Q / E 每次 key-down 让偏航一次转 90°，
## 按住不连续旋转（离散 step 由 executor 把 yaw_step_request 写进组件）。
## 只写期望姿态字段，由 CameraRig 唯一写 Camera3D；不读键鼠、不引用其他 Capability。

## 转向动画的时间常数（秒）：0 表示瞬转。让 90° 切换看起来是转而不是跳。
@export var turn_smooth_time: float = 0.18

var _pending_degrees := 0.0


func _init() -> void:
	priority = 0


func _should_activate() -> bool:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return false
	return rig.mode_id == "quarter_turn"


func _tick_active(delta: float) -> void:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return
	# 离散请求：每个 key-down 记一步（executor 已按 turn_step_degrees 换算成度）。
	_pending_degrees += rig.yaw_step_request
	rig.yaw_step_request = 0.0
	if not is_zero_approx(_pending_degrees) and turn_smooth_time <= 0.0:
		rig.yaw_degrees += _pending_degrees
		_pending_degrees = 0.0
	elif not is_zero_approx(_pending_degrees):
		var step := _pending_degrees * clampf(delta / turn_smooth_time, 0.0, 1.0)
		rig.yaw_degrees += step
		_pending_degrees -= step
		if absf(_pending_degrees) < 0.01:
			_pending_degrees = 0.0
	_apply_zoom(rig)
	# 焦点跟随目标：四向切换下仍保持"目标在画面里"，与 fixed_follow 的软区区分。
	rig.focus = rig.clamped_focus(rig.target_position)
	rig.lookahead = Vector3.ZERO


func _apply_zoom(rig: CameraRigComponent) -> void:
	if rig.projection == Camera3D.PROJECTION_ORTHOGONAL:
		rig.size = rig.size_after_zoom(rig.zoom_steps)
	else:
		rig.distance = rig.distance_after_zoom(rig.zoom_steps)
	rig.zoom_steps = 0.0


## mode_id 互斥：当前模式不是 quarter_turn 时必须立即失活。
func _should_deactivate() -> bool:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return true
	return rig.mode_id != "quarter_turn"


func _on_deactivated() -> void:
	# 未完成的步进丢弃，避免退出模式后突然补转。
	_pending_degrees = 0.0
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig != null:
		rig.yaw_step_request = 0.0
