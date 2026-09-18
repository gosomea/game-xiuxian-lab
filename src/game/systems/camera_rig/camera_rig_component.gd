class_name CameraRigComponent
extends Component

## 镜头装配的共享数据（纯数据，见 design 契约）。
##
## 四个模式 Capability 只写"期望位姿"字段；CameraRig（普通节点，唯一 executor）读这些
## 字段并独占写 Camera3D；executor 还在每帧把输入层请求、目标 snapshot 与 modifier 结果写进来。
## 本组件不读键鼠、不认识节点树，也不做决策。
## 字段契约登记在 res://data/vocabulary/camera_rig.json。

## 模式：当前持有效的镜头模式；executor 每帧由 mode_request 同步。
## 用普通 String 存模式名：它是组件字段值，不是 TagRegistry 词汇（字段本身已登记）。
var mode_id: String = "fixed_follow"
## 模式：外部请求的模式；executor 在 tick 前写入 mode_id 并清空。
var mode_request: String = ""
## fixed_follow 的参数预设（hard / smooth / deadzone / lookahead）——同一模式的比较参数。
var follow_preset: String = "hard"

## 取景偏移（米，世界坐标）：executor 把它加到目标 snapshot 上（例如对准人物胸部）；
## 只影响取景，速度差分仍用目标真实 global_position。
var focus_offset: Vector3 = Vector3.ZERO

## 期望跟随焦点（世界坐标，y 为地面高度）；由模式 Capability 写入。
var focus: Vector3 = Vector3.ZERO
## 期望瞄准点相对焦点的偏移；executor 用它平移整个取景（相机与瞄准点同步前移）。
var lookahead: Vector3 = Vector3.ZERO

## 期望偏航角（度）；相机地面基随之旋转。
var yaw_degrees: float = -35.0
## 期望俯角（度）；orbit 模式下受限幅。
var pitch_degrees: float = 42.0
## 相机到焦点的球面距离（米）；透视模式下滚轮缩放改这里。
var distance: float = 16.0

## 投影（Resource 配置播种；executor 唯一写 Camera3D）。
var projection: Camera3D.ProjectionType = Camera3D.PROJECTION_ORTHOGONAL
var near: float = 0.1
var far: float = 220.0
## 透视模式的视场角（度）；正交模式忽略。由配置播种，executor 统一写。
var fov: float = 60.0

## 正交投影参数。
var size: float = 24.0
var size_min: float = 8.0
var size_max: float = 44.0
var zoom_step: float = 2.0
## 透视模式的缩放范围与步进：调 distance，不改正交 size（否则镜头看上去没变）。
var distance_min: float = 6.0
var distance_max: float = 60.0
var distance_step: float = 1.5

## modifier 数据（executor 每帧写入并由 executor 叠加；不是第 5 个 Capability）。
var target_altitude: float = 0.0
var target_speed: float = 0.0
var distance_bias: float = 0.0
var height_reference_y: float = 0.0
var height_distance_bias: float = 0.0
var height_bias_max: float = 6.0
var speed_distance_bias: float = 0.0
var speed_bias_max: float = 4.0

## 固定跟随调参（由 CameraRigConfig 播种；模式只读，场景可显式覆盖）。
var smooth_time: float = 0.35
var deadzone_half_width: float = 4.0
var deadzone_half_height: float = 2.5
var lookahead_time: float = 0.45
var lookahead_max: float = 5.0
var lookahead_smooth_time: float = 0.3

## 连续偏航角速度（度/秒）；只有连续旋转模式（orbit）消费，且乘帧时长。
var yaw_speed_degrees: float = 90.0
## quarter_turn 单次离散转向角度（度）。
var turn_step_degrees: float = 90.0
## orbit 的俯角限幅（度）；受限视角，不做全球自由旋转。
var pitch_min_degrees: float = 12.0
var pitch_max_degrees: float = 78.0

## overview 平移：像素 → 米的换算乘数、离目标的最大范围与回中时间常数。
var pan_speed: float = 1.0
var pan_distance_max: float = 18.0
var recenter_time: float = 0.35

## 本帧输入层请求（executor 写入，模式消费，executor 帧末兜底清零）。
var zoom_steps: float = 0.0
var yaw_input: float = 0.0
var yaw_step_request: float = 0.0
var look_delta: Vector2 = Vector2.ZERO
var pan_delta: Vector2 = Vector2.ZERO
var pan_world_delta: Vector3 = Vector3.ZERO
var drag_active: bool = false
var pan_active: bool = false
var recenter_request: bool = false

## 焦点收缩：启用后焦点被限制在 min/max 之间。
## x/z 始终夹取；y 只有显式打开 focus_clamp_y_enabled 时才夹取
## （否则保留 value.y，使高空御剑的镜头不会被压回地面）。
var focus_clamp_enabled: bool = false
var focus_clamp_y_enabled: bool = false
var focus_clamp_min: Vector3 = Vector3.ZERO
var focus_clamp_max: Vector3 = Vector3.ZERO

## 目标 snapshot（executor 桥接写入；能力只读，不抓场景节点）。
var target_position: Vector3 = Vector3.ZERO
var target_velocity: Vector3 = Vector3.ZERO
var target_on_floor: bool = false
var target_flight_active: bool = false

## 只读观察项：本 rig 拥有的捕获态与相机到目标的遮挡读数。
var capture_active: bool = false
var occlusion: bool = false


## 派生值：正交 size 应用缩放请求后并限幅。
func size_after_zoom(steps: float) -> float:
	return clampf(size - steps * zoom_step, size_min, size_max)


## 派生值：透视 distance 应用缩放请求后并限幅（透视下滚轮必须改距离才看得见变化）。
func distance_after_zoom(steps: float) -> float:
	return clampf(distance - steps * distance_step, distance_min, distance_max)


## 派生值：modifier 的距离偏移（高度 + 速度，各自限幅后相加）。
func modifier_distance_bias() -> float:
	var height_part := clampf(
		(target_altitude - height_reference_y) * height_distance_bias,
		0.0,
		height_bias_max
	)
	var speed_part := clampf(target_speed * speed_distance_bias, 0.0, speed_bias_max)
	return height_part + speed_part


## 派生值：叠加 modifier 后的有效距离（已限幅）。
func effective_distance(base_distance: float) -> float:
	var biased := base_distance + modifier_distance_bias()
	return clampf(biased, distance_min, distance_max)


## 派生值：焦点是否在收缩范围内（越界时需要 executor 拉回）。
func focus_within_clamp() -> bool:
	if not focus_clamp_enabled:
		return true
	if focus.x < focus_clamp_min.x or focus.x > focus_clamp_max.x:
		return false
	if focus.z < focus_clamp_min.z or focus.z > focus_clamp_max.z:
		return false
	if focus_clamp_y_enabled and (focus.y < focus_clamp_min.y or focus.y > focus_clamp_max.y):
		return false
	return true


## 派生值：把焦点收缩到场地范围；未启用时原样返回。
## y 只在 focus_clamp_y_enabled 时按 min.y / max.y 夹取，否则保留原高度
## （2.5D 有界场地用 y 夹取保持地平构图；开放空域保留高度）。
func clamped_focus(value: Vector3) -> Vector3:
	if not focus_clamp_enabled:
		return value
	var clamped_y := value.y
	if focus_clamp_y_enabled:
		clamped_y = clampf(value.y, focus_clamp_min.y, focus_clamp_max.y)
	return Vector3(
		clampf(value.x, focus_clamp_min.x, focus_clamp_max.x),
		clamped_y,
		clampf(value.z, focus_clamp_min.z, focus_clamp_max.z)
	)