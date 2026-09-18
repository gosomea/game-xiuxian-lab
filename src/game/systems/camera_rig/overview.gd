class_name Overview
extends Capability

## 总览平移 + 回中（镜头模式 D，长期语义名 overview）。
##
## MMB 拖拽把焦点沿实际相机地面基平移（executor 已把像素位移换算成世界位移，
## 因此平移方向与实际渲染一致）；Home 键或可视按钮请求回中，回中按时间常数收敛。
## 偏航 / 俯角保持不动，只移动焦点，不抢 1-4 模式键。只写期望姿态字段。

var _offset := Vector3.ZERO


func _init() -> void:
	priority = 0


func _should_activate() -> bool:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return false
	return rig.mode_id == "overview"


func _tick_active(delta: float) -> void:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return
	# 平移：executor 写入的世界位移直接叠加，并按 pan_distance_max 限幅在目标周围。
	if rig.pan_active and rig.pan_world_delta != Vector3.ZERO:
		_offset += rig.pan_world_delta
		if _offset.length() > rig.pan_distance_max:
			_offset = _offset.normalized() * rig.pan_distance_max
	rig.pan_world_delta = Vector3.ZERO
	# 回中：请求或已经离开目标时收敛回目标（时间常数与帧长无关）。
	if rig.recenter_request:
		_offset = _offset.lerp(Vector3.ZERO, _exp_weight(rig.recenter_time, delta))
		if _offset.length() < 0.02:
			_offset = Vector3.ZERO
			rig.recenter_request = false
	elif rig.pan_active and _offset != Vector3.ZERO:
		# 拖动中不回中，保持玩家意图。
		pass
	_apply_zoom(rig)
	rig.focus = rig.clamped_focus(rig.target_position + _offset)
	rig.lookahead = Vector3.ZERO


func _apply_zoom(rig: CameraRigComponent) -> void:
	if rig.projection == Camera3D.PROJECTION_ORTHOGONAL:
		rig.size = rig.size_after_zoom(rig.zoom_steps)
	else:
		rig.distance = rig.distance_after_zoom(rig.zoom_steps)
	rig.zoom_steps = 0.0


## 只读：离目标的当前平移量（HUD / 测试读回，不暴露可变状态）。
func offset() -> Vector3:
	return _offset


func _exp_weight(time_constant: float, delta: float) -> float:
	if time_constant <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / time_constant)


## mode_id 互斥：当前模式不是 overview 时必须立即失活。
func _should_deactivate() -> bool:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return true
	return rig.mode_id != "overview"


func _on_deactivated() -> void:
	# 离开模式时清平移与未消费位移，避免下次进入时突然跳。
	_offset = Vector3.ZERO
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig != null:
		rig.pan_world_delta = Vector3.ZERO
		rig.pan_active = false
		rig.recenter_request = false
