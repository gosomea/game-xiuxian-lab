class_name FixedFollow
extends Capability

## 固定正交跟随（镜头模式 A，长期语义名 fixed_follow）。
##
## 只写 CameraRigComponent 的期望姿态（焦点 / 前视 / 偏航 / 缩放），由 CameraRig（普通节点）
## 唯一消费并写 Camera3D。本能力不读键鼠、不认识 Camera3D 与场景节点，也不引用其他 Capability。
## follow_preset 是同一模式下的参数比较（hard / smooth / deadzone / lookahead），不是独立模式。
## 失活只清本能力写过的字段（前视），不触碰焦点/偏航，避免覆盖接管的模式输出。

## 预设名以普通 String 存在组件里（纯数据）；本能力只解释预设语义。
const PRESET_HARD := "hard"
const PRESET_SMOOTH := "smooth"
const PRESET_DEADZONE := "deadzone"
const PRESET_LOOKAHEAD := "lookahead"

func _init() -> void:
	priority = 0


func _should_activate() -> bool:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return false
	return rig.mode_id == "fixed_follow"


func _tick_active(delta: float) -> void:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return
	_follow_focus(rig, delta)
	_apply_zoom(rig)
	_apply_yaw(rig, delta)
	rig.lookahead = _lookahead_of(rig, delta)


## 焦点策略：与旧 CameraLabRig 的四种预设一一对应，竖直方向不做死区（地面高度稳定）。
func _follow_focus(rig: CameraRigComponent, delta: float) -> void:
	match rig.follow_preset:
		PRESET_HARD:
			rig.focus = rig.target_position
		PRESET_SMOOTH:
			rig.focus = rig.focus.lerp(rig.target_position, _exp_weight(rig, delta))
		PRESET_DEADZONE:
			_follow_deadzone(rig, delta)
		_:
			_follow_deadzone(rig, delta)


## 死区：焦点只在目标越过屏幕轴死区矩形后被拖动；竖直方向直接跟随。
func _follow_deadzone(rig: CameraRigComponent, delta: float) -> void:
	var right := _right_axis(rig)
	var forward := _forward_axis(rig)
	var delta_xz := rig.target_position - rig.focus
	delta_xz.y = 0.0
	var along_right := delta_xz.dot(right)
	var along_forward := delta_xz.dot(forward)
	var pushed := Vector3.ZERO
	if absf(along_right) > rig.deadzone_half_width:
		pushed += right * (along_right - signf(along_right) * rig.deadzone_half_width)
	if absf(along_forward) > rig.deadzone_half_height:
		pushed += forward * (along_forward - signf(along_forward) * rig.deadzone_half_height)
	rig.focus += pushed
	rig.focus.y = rig.target_position.y
	rig.focus = rig.clamped_focus(rig.focus)


## 前视：仅 lookahead 预设产生；死区与硬跟随为 0，便于单独读出前视贡献。
func _lookahead_of(rig: CameraRigComponent, delta: float) -> Vector3:
	if rig.follow_preset != PRESET_LOOKAHEAD:
		return Vector3.ZERO
	var speed := rig.target_velocity
	speed.y = 0.0
	var wanted := speed * rig.lookahead_time
	if wanted.length() > rig.lookahead_max:
		wanted = wanted.normalized() * rig.lookahead_max
	var blended := rig.lookahead.lerp(wanted, 1.0 - exp(-delta / maxf(rig.lookahead_smooth_time, 0.0001)))
	if blended.length() < 0.01:
		return Vector3.ZERO
	return blended


func _apply_zoom(rig: CameraRigComponent) -> void:
	# 投影方式与控制行为分开：正交调 size，透视调 distance（透视下改 size 画面不变）。
	if rig.projection == Camera3D.PROJECTION_ORTHOGONAL:
		rig.size = rig.size_after_zoom(rig.zoom_steps)
	else:
		rig.distance = rig.distance_after_zoom(rig.zoom_steps)
	rig.zoom_steps = 0.0


## 键盘偏航是角速度（度/秒），必须乘帧时长；鼠标像素位移不在这里处理。
func _apply_yaw(rig: CameraRigComponent, delta: float) -> void:
	rig.yaw_degrees += rig.yaw_input * rig.yaw_speed_degrees * delta


func _exp_weight(rig: CameraRigComponent, delta: float) -> float:
	if rig.smooth_time <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / rig.smooth_time)


func _right_axis(rig: CameraRigComponent) -> Vector3:
	var yaw := deg_to_rad(rig.yaw_degrees)
	return Vector3(cos(yaw), 0.0, -sin(yaw)).normalized()


func _forward_axis(rig: CameraRigComponent) -> Vector3:
	var yaw := deg_to_rad(rig.yaw_degrees)
	return Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()


## mode_id 互斥：当前模式不是 fixed_follow 时必须立即失活，把姿态交给接管的模式。
func _should_deactivate() -> bool:
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig == null:
		return true
	return rig.mode_id != "fixed_follow"


func _on_deactivated() -> void:
	# 只清本能力写过的前视；焦点 / 偏航留给下一模式接管，避免旧模式覆盖新输出。
	var rig := component(&"CameraRigComponent") as CameraRigComponent
	if rig != null:
		rig.lookahead = Vector3.ZERO