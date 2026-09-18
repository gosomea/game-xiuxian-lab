class_name Orbit
extends Capability

## 受限 RMB 环绕（镜头模式 C，长期语义名 orbit）。
##
## RMB 按住期间消费 executor 写入的 look_delta（鼠标像素位移，不乘帧时长），
## 累加偏航并受限俯角；滚轮缩放沿用组件 zoom_steps。只写期望姿态字段，
## 由 CameraRig 唯一写 Camera3D。本能力不读键鼠、不设 mouse_mode、不认识 Camera3D。

## 拖动灵敏度（度 / 像素）；executor 只负责把像素位移写进组件。
@export var drag_sensitivity: float = 0.18


func _init() -> void:
	priority = 0


func _should_activate() -> bool:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return false
	return rig.mode_id == "orbit"


func _tick_active(delta: float) -> void:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return
	if rig.drag_active and rig.look_delta != Vector2.ZERO:
		rig.yaw_degrees += rig.look_delta.x * drag_sensitivity
		rig.pitch_degrees = clampf(
			rig.pitch_degrees + rig.look_delta.y * drag_sensitivity,
			rig.pitch_min_degrees,
			rig.pitch_max_degrees
		)
	rig.look_delta = Vector2.ZERO
	rig.yaw_degrees += rig.yaw_input * rig.yaw_speed_degrees * delta
	_apply_zoom(rig)
	# 环绕模式仍软跟随目标，保证角色不离开取景；焦点不写死区。
	rig.focus = rig.clamped_focus(rig.target_position)
	rig.lookahead = Vector3.ZERO


## 投影区分的缩放（与其余三个模式同一契约）：正交调 size，透视调 distance。
func _apply_zoom(rig: CameraRigComponent) -> void:
	if rig.projection == Camera3D.PROJECTION_ORTHOGONAL:
		rig.size = rig.size_after_zoom(rig.zoom_steps)
	else:
		rig.distance = rig.distance_after_zoom(rig.zoom_steps)
	rig.zoom_steps = 0.0


## mode_id 互斥：当前模式不是 orbit 时必须立即失活。
func _should_deactivate() -> bool:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return true
	return rig.mode_id != "orbit"


func _on_deactivated() -> void:
	# 交接时只丢弃未消费的鼠标位移，保留 yaw/pitch 供下一模式继续使用。
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig != null:
		rig.look_delta = Vector2.ZERO
		rig.drag_active = false