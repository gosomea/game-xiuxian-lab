class_name CameraLabRig
extends Node3D

## 镜头实验室专用的跟随台架（组合节点，纯实验资产）。
##
## 只属于 res://levels/experiments/character_movement/，不抽 core、不做通用镜头系统；
## 不引用任何 Capability / Component 字段，不写角色状态，只读目标 Node3D 的全局变换。
## 场景每物理帧调用 update()，由策略决定跟随焦点，再按偏航角摆放相机。
##
## 四种策略（本实验室唯一比较对象）：
## - HARD       固定偏移硬跟随：焦点严格等于目标位置，无任何缓动。
## - SMOOTH     平滑跟随：焦点按指数衰减逼近目标（与帧率无关）。
## - DEADZONE   死区跟随：屏幕轴向上的死区矩形，目标越界才拖动焦点，无前视。
## - LOOKAHEAD  死区 + 前视：在死区基础上按目标水平速度沿屏幕轴加限幅前视偏移。
## 四者的偏航、俯角、距离与缩放完全一致，比较时只变跟随策略；
## DEADZONE 与 LOOKAHEAD 成对存在，用来单独读出"前视"这一项的贡献。

enum Mode {
	HARD = 0,
	SMOOTH = 1,
	DEADZONE = 2,
	LOOKAHEAD = 3,
}

const MODE_ORDER: Array[Mode] = [Mode.HARD, Mode.SMOOTH, Mode.DEADZONE, Mode.LOOKAHEAD]
const MODE_NAMES: Dictionary = {
	Mode.HARD: "固定偏移硬跟随",
	Mode.SMOOTH: "平滑跟随",
	Mode.DEADZONE: "死区跟随",
	Mode.LOOKAHEAD: "死区 + 前视",
}
const MODE_KEYS: Dictionary = {
	Mode.HARD: "hard",
	Mode.SMOOTH: "smooth",
	Mode.DEADZONE: "deadzone",
	Mode.LOOKAHEAD: "lookahead",
}
## 带死区的策略集合（焦点由目标越界推动而不是直接赋值）。
const DEADZONE_MODES: Array[Mode] = [Mode.DEADZONE, Mode.LOOKAHEAD]

## 相机相对焦点的球面参数：偏航角决定水平朝向，俯角与距离固定（高度由二者导出）。
@export var distance: float = 16.0
@export var pitch_degrees: float = 42.0
@export var yaw_degrees: float = -35.0

## 缩放：正交 size，越小越近。步进为滚轮一格的量。
@export var zoom_step: float = 2.0
@export var zoom_min: float = 8.0
@export var zoom_max: float = 44.0

## 平滑策略的时间常数（秒）；越大越"拖"。
@export var smooth_time: float = 0.35

## 死区半宽 / 半高（米）：目标在焦点周围的这个矩形内移动时相机不动。
@export var deadzone_half_width: float = 4.0
@export var deadzone_half_height: float = 2.5
## 前视：按目标水平速度提前量的秒数，限幅后平滑加入焦点。
@export var lookahead_time: float = 0.45
@export var lookahead_max: float = 5.0
@export var lookahead_smooth_time: float = 0.3

var _mode: Mode = Mode.HARD
var _camera: Camera3D = null
var _target: Node3D = null
var _focus: Vector3 = Vector3.ZERO
var _lookahead: Vector3 = Vector3.ZERO
var _previous_target_position: Vector3 = Vector3.ZERO
var _has_previous := false
var _marker: MeshInstance3D = null


func setup(camera: Camera3D, target: Node3D) -> void:
	_camera = camera
	_target = target
	_has_previous = false
	_focus = target.global_position if target != null else Vector3.ZERO
	_previous_target_position = _focus
	_build_focus_marker()
	_place_camera()


func mode() -> Mode:
	return _mode


func mode_key() -> String:
	return MODE_KEYS[_mode]


func mode_label() -> String:
	return MODE_NAMES[_mode]


func set_mode(value: Mode) -> void:
	if value == _mode:
		return
	_mode = value
	# 切换策略不改物理：只重置本台架内部状态，硬跟随立刻贴住目标。
	# 切走再切回会重新收敛，这是策略自身的瞬态，不是角色物理变化。
	_lookahead = Vector3.ZERO
	_has_previous = false
	if value not in DEADZONE_MODES and _target != null:
		_focus = _target.global_position


func cycle_mode() -> Mode:
	var index := MODE_ORDER.find(_mode)
	set_mode(MODE_ORDER[(index + 1) % MODE_ORDER.size()])
	return _mode


## 绕焦点的偏航角（度）。相机地面基随它旋转，屏幕相对移动因此改变。
func set_yaw_degrees(value: float) -> void:
	yaw_degrees = value


func add_yaw_degrees(delta: float) -> void:
	yaw_degrees += delta


## 缩放：index 越大越近（HUD 与测试都按索引读回）。
func zoom_levels() -> int:
	return int(round((zoom_max - zoom_min) / zoom_step)) + 1


func zoom_index() -> int:
	if _camera == null:
		return 1
	return int(round((zoom_max - _camera.size) / zoom_step)) + 1


func zoom_size() -> float:
	return _camera.size if _camera != null else zoom_min


func adjust_zoom(steps: float) -> float:
	if _camera == null:
		return zoom_min
	_camera.size = clampf(_camera.size - steps * zoom_step, zoom_min, zoom_max)
	return _camera.size


func reset_state() -> void:
	_lookahead = Vector3.ZERO
	_has_previous = false
	if _target != null:
		_focus = _target.global_position
		_previous_target_position = _focus
	_place_camera()


## 供场景每物理帧调用：先按策略求焦点，再摆放相机。delta 为物理帧时长。
func update(delta: float) -> void:
	if _camera == null or _target == null:
		return
	var target_position := _target.global_position
	match _mode:
		Mode.HARD:
			_focus = target_position
			_lookahead = Vector3.ZERO
		Mode.SMOOTH:
			var weight := _exp_weight(smooth_time, delta)
			_focus = _focus.lerp(target_position, weight)
			_lookahead = Vector3.ZERO
		Mode.DEADZONE:
			_update_deadzone(target_position, delta, false)
		Mode.LOOKAHEAD:
			_update_deadzone(target_position, delta, true)
	_previous_target_position = target_position
	_has_previous = true
	_place_camera()
	if _marker != null:
		_marker.global_position = Vector3(_focus.x, 0.04, _focus.z)


## 死区：把目标位置换算到屏幕轴（右 / 前）上，越界才推动焦点；再叠加限幅前视。
func _update_deadzone(target_position: Vector3, delta: float, use_lookahead: bool) -> void:
	var right := right_axis()
	var forward := forward_axis()
	var delta_xz := target_position - _focus
	delta_xz.y = 0.0
	var along_right := delta_xz.dot(right)
	var along_forward := delta_xz.dot(forward)
	var pushed := Vector3.ZERO
	if absf(along_right) > deadzone_half_width:
		pushed += right * (along_right - signf(along_right) * deadzone_half_width)
	if absf(along_forward) > deadzone_half_height:
		pushed += forward * (along_forward - signf(along_forward) * deadzone_half_height)
	_focus += pushed
	# 竖直方向不设死区：保持地面高度稳定，避免高台被死区拖成错觉。
	_focus.y = target_position.y
	if not use_lookahead:
		_lookahead = Vector3.ZERO
		return
	# 目标水平速度由位移差分得到，只用于计算前视量，不写回任何对象。
	var travel_rate := Vector3.ZERO
	if _has_previous and delta > 0.0:
		travel_rate = (target_position - _previous_target_position) / delta
	travel_rate.y = 0.0
	var wanted := travel_rate * lookahead_time
	if wanted.length() > lookahead_max:
		wanted = wanted.normalized() * lookahead_max
	_lookahead = _lookahead.lerp(wanted, _exp_weight(lookahead_smooth_time, delta))
	if _lookahead.length() < 0.01:
		_lookahead = Vector3.ZERO


func _place_camera() -> void:
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var horizontal := distance * cos(pitch)
	var focus := camera_focus()
	# 相机绕焦点的水平偏移由偏航角决定；俯角唯一，抬头/低头不参与本实验。
	var offset := Vector3(sin(yaw) * horizontal, distance * sin(pitch), cos(yaw) * horizontal)
	_camera.global_position = focus + offset
	_camera.look_at(focus, Vector3.UP)


## 相机地面基：右方向与前方向（水平单位向量），场景用它驱动屏幕相对移动。
## 与 Camera3D 实际基一致：right = basis.x 的水平投影，forward = -basis.z 的水平投影。
func right_axis() -> Vector3:
	var yaw := deg_to_rad(yaw_degrees)
	return Vector3(cos(yaw), 0.0, -sin(yaw)).normalized()


func forward_axis() -> Vector3:
	var yaw := deg_to_rad(yaw_degrees)
	return Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()


## 相机实际瞄准的水平点：带前视策略时 = 焦点 + 前视；其余策略等于焦点。
## 比较"跟随落后多少"必须读这个值，而不是只读死区焦点。
func camera_focus() -> Vector3:
	if _mode == Mode.LOOKAHEAD:
		return _focus + _lookahead
	return _focus


## 只读快照：模式、焦点、前视、偏航与相机变换，供 HUD 与运行时读回。
func snapshot() -> Dictionary:
	return {
		"mode": mode_key(),
		"mode_label": mode_label(),
		"focus": _focus,
		"camera_focus": camera_focus(),
		"lookahead": _lookahead,
		"yaw_degrees": yaw_degrees,
		"zoom_size": zoom_size(),
		"zoom_index": zoom_index(),
		"camera_transform": _camera.global_transform if _camera != null else Transform3D.IDENTITY,
		"right": right_axis(),
		"forward": forward_axis(),
	}


## 焦点标记：地面上的细圆盘，用来在截图里对照焦点与实际角色位置。
func _build_focus_marker() -> void:
	if _marker != null:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.55
	mesh.height = 0.03
	mesh.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.867, 0.373, 0.235, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	_marker = MeshInstance3D.new()
	_marker.name = "FocusMarker"
	_marker.mesh = mesh
	_marker.position = Vector3(_focus.x, 0.04, _focus.z)
	add_child(_marker)


## 与帧率无关的指数衰减权重：delta 越大权重越高，但永不超过 1。
static func _exp_weight(time_constant: float, delta: float) -> float:
	if time_constant <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / time_constant)
