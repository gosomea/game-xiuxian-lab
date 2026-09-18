class_name CameraRig
extends Node3D

## 镜头装配宿主（唯一 executor）。
##
## 形状（notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md）：
## CameraRig 的直系子节点是 CameraRigComponent（唯一）与 CapabilityManager（唯一），
## 模式 Capability 是 manager 的直系子。本脚本不引用任何 Capability 类名。
##
## 挂载即可用：场景实例化 camera_rig_sheet.tscn 后填 camera_path / target_path / config 即可，
## 不必在场景脚本里抄输入映射、写物理顺序或转交相机地面基——本节点在写相机后直接把
## 最终地面基写入目标（target 支持 set_camera_ground_basis 时），角色物理与渲染同帧一致。
## 同一目标多个 rig 时只有 active 的那个消费输入、写 Camera3D 与发布地面基。
##
## 独占写：位置 / look_at / projection / size / near / far 只在本节点写。
## 地面基来源：最终 Camera3D.global_transform.basis 的水平投影（不是期望 yaw），
## 因此平滑混合期间移动方向与实际渲染一致。
##
## 输入分相：
## - RMB 归属走 _input 早期路径：世界区域的 RMB press 在同一事件内捕获（orbit 且
##   enable_yaw_keys）或按 consume_unowned_rmb 消费（其余模式），避免未消费的右键泄漏为
##   编辑器嵌入 Game 视图的上下文操作；交互 GUI 上方的右键归 GUI。捕获态的 RMB 释放与
##   Esc 也走 _input，即使 GUI 消费了事件也能退出捕获。
## - 数字键选模式、Q/E 偏航、滚轮缩放、MMB 平移走 _unhandled_input：GUI 已消费的事件
##   （面板上的滚轮、按钮点击）不会到这里，GUI 滚轮不缩放、点按钮不捕获。

signal mode_changed(mode_id: String)

## 早于角色（0）执行：角色物理使用本帧已确定的相机地面基。
const PHYSICS_PRIORITY_BEFORE_ACTOR := -10

const MODE_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4]
const YAW_KEYS: Dictionary = {KEY_Q: -1.0, KEY_E: 1.0}

@export var camera_path: NodePath
@export var target_path: NodePath
@export var config: CameraRigConfig
## 同一目标可能有多个 rig；只有 active 的 rig 消费输入并写 Camera3D。
@export var active: bool = true
## 数字键 1..4 依次选择的模式；只列当前包内真实存在的模式（避免空壳按键）。
@export var mode_cycle: PackedStringArray = PackedStringArray(["fixed_follow", "orbit"])
## fixed_follow 的参数预设循环顺序（同一模式内的比较参数，不是独立模式）。
@export var preset_cycle: PackedStringArray = PackedStringArray(["hard", "smooth", "deadzone", "lookahead"])

var _camera: Camera3D = null
var _target: Node3D = null
var _rig: CameraRigComponent = null
var _manager: CapabilityManager = null
var _held: Dictionary = {}
var _target_last_position: Vector3 = Vector3.ZERO
var _target_has_previous := false
## 可选的物理目标（读取着地 / 御剑状态）；不参与相机写入。
var _motion_source: CharacterBody3D = null

## 上一次真正提交到 Camera3D 的状态：混合起点与 pan 换算读这里，
## 不从 transform 互推（互推会形成循环依赖，也没有唯一解）。
var _applied_focus := Vector3.ZERO
var _applied_lookahead := Vector3.ZERO
var _applied_distance := 0.0
var _occluded := false
## 绑定时播种的配置：reset_state 用它恢复初值（偏航 / 俯角 / 距离 / 缩放等）。
var _seed_config: CameraRigConfig = null

## 捕获归属：只释放本 rig 自己设过的捕获，并恢复进入前的 mouse_mode。
var _capture_owned := false
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

## 模式切换混合：起点是切换瞬间的"真实渲染状态"（实际 transform / 位置 / 投影），
## 不是当时组件里的期望值——否则 deadzone 焦点离目标时切 orbit 会位置跳。
## 混合期焦点同样插值迁移；切换中再次切换会以当前实际状态重启混合，因此连续不跳。
var _blend_active := false
var _blend_from_focus := Vector3.ZERO
var _blend_from_lookahead := Vector3.ZERO
var _blend_from_yaw := 0.0
var _blend_from_pitch := 0.0
var _blend_from_distance := 0.0
var _blend_from_size := 0.0
var _blend_left := 0.0
var _blend_duration := 0.0
var _blend_from_fov := 60.0


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY_BEFORE_ACTOR
	for child in get_children():
		if child is CameraRigComponent:
			_rig = child as CameraRigComponent
		elif child is CapabilityManager:
			_manager = child as CapabilityManager
	assert(_rig != null, "CameraRig: 根节点下必须有 CameraRigComponent")
	assert(_manager != null, "CameraRig: 根节点下必须有 CapabilityManager")
	# manager 自带 _process 自动 tick；改由本节点的物理帧驱动，避免同帧推进两次。
	_manager.set_process(false)
	if not camera_path.is_empty() or not target_path.is_empty():
		bind(
			get_node_or_null(camera_path) as Camera3D,
			get_node_or_null(target_path) as Node3D,
			config
		)


func _exit_tree() -> void:
	release_capture()


func _notification(what: int) -> void:
	# 失焦：释放本 rig 的捕获并清按住状态；不改变模式与目标。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_capture()


# --- 装配 API ---------------------------------------------------------------


## 绑定本 rig 独占写的相机与只读跟随目标；可选的配置播种投影与参数。
## 相机为空是装配错误：显式报错并停用，不做隐式回退到 viewport 的当前相机。
func bind(camera: Camera3D, target: Node3D, rig_config: CameraRigConfig = null) -> void:
	assert(_rig != null, "CameraRig.bind: 组件尚未就绪（_ready 之后调用）")
	if camera == null:
		push_error("CameraRig.bind: 必须显式提供要独占写的 Camera3D；本节点已停用")
		active = false
		return
	_camera = camera
	_target = target
	_target_has_previous = target != null
	_target_last_position = target.global_position if target != null else Vector3.ZERO
	if target != null:
		_rig.target_position = target.global_position
		_rig.focus = target.global_position
		_rig.mode_id = _default_mode()
	var resolved := rig_config if rig_config != null else config
	if resolved != null:
		_seed_config = resolved
		_apply_config(resolved)
		_rig.mode_id = resolved.start_mode
		_blend_duration = resolved.transition_time
	# 绑定后还没有提交过：applied 状态以种子配置为准，保证首次混合有真实起点。
	_applied_focus = _rig.focus
	_applied_lookahead = _rig.lookahead
	_applied_distance = _rig.effective_distance(_rig.distance)
	if resolved != null:
		begin_blend()


func _apply_config(rig_config: CameraRigConfig) -> void:
	_rig.projection = rig_config.projection
	_rig.near = rig_config.near
	_rig.far = rig_config.far
	_rig.size = rig_config.size
	_rig.size_min = rig_config.size_min
	_rig.size_max = rig_config.size_max
	_rig.zoom_step = rig_config.zoom_step
	_rig.yaw_degrees = rig_config.yaw_degrees
	_rig.yaw_speed_degrees = rig_config.yaw_speed_degrees
	_rig.pitch_degrees = rig_config.pitch_degrees
	_rig.pitch_min_degrees = rig_config.pitch_min_degrees
	_rig.pitch_max_degrees = rig_config.pitch_max_degrees
	_rig.distance = rig_config.distance
	_rig.smooth_time = rig_config.smooth_time
	_rig.deadzone_half_width = rig_config.deadzone_half_width
	_rig.deadzone_half_height = rig_config.deadzone_half_height
	_rig.lookahead_time = rig_config.lookahead_time
	_rig.lookahead_max = rig_config.lookahead_max
	_rig.lookahead_smooth_time = rig_config.lookahead_smooth_time
	_rig.focus_clamp_enabled = rig_config.focus_clamp_enabled
	_rig.focus_clamp_y_enabled = rig_config.focus_clamp_y_enabled
	_rig.focus_offset = rig_config.focus_offset
	_rig.focus_clamp_min = rig_config.focus_clamp_min
	_rig.focus_clamp_max = rig_config.focus_clamp_max
	_rig.follow_preset = rig_config.follow_preset
	# 模式子集来自配置：非 lab 场景默认只有 fixed_follow，不抢场景自己的数字键。
	if not rig_config.mode_choices.is_empty():
		mode_cycle = rig_config.mode_choices
	_rig.turn_step_degrees = rig_config.turn_step_degrees
	_rig.pan_speed = rig_config.pan_speed
	_rig.pan_distance_max = rig_config.pan_distance_max
	_rig.recenter_time = rig_config.recenter_time
	_rig.distance_min = rig_config.distance_min
	_rig.distance_max = rig_config.distance_max
	_rig.distance_step = rig_config.distance_step
	_rig.fov = rig_config.fov
	_rig.height_reference_y = rig_config.height_reference_y
	_rig.height_distance_bias = rig_config.height_distance_bias
	_rig.height_bias_max = rig_config.height_bias_max
	_rig.speed_distance_bias = rig_config.speed_distance_bias
	_rig.speed_bias_max = rig_config.speed_bias_max
	if _camera != null:
		_camera.projection = _rig.projection
		_camera.fov = rig_config.fov
		_camera.size = _rig.size


# --- 输入开关（默认全关：独立场景不被镜头包抢按键） -------------------------


func _mode_selection_enabled() -> bool:
	return _seed_config != null and _seed_config.enable_mode_selection_keys


func _preset_key_enabled() -> bool:
	return _seed_config != null and _seed_config.enable_preset_key


func _zoom_keys_enabled() -> bool:
	return _seed_config != null and _seed_config.enable_zoom_keys


func _zoom_wheel_enabled() -> bool:
	return _seed_config == null or _seed_config.enable_zoom_wheel


func _yaw_keys_enabled() -> bool:
	return _seed_config == null or _seed_config.enable_yaw_keys


func _consume_unowned_rmb() -> bool:
	return _seed_config != null and _seed_config.consume_unowned_rmb


# --- 只读访问（HUD / 测试） --------------------------------------------------


func component() -> CameraRigComponent:
	return _rig


func camera() -> Camera3D:
	return _camera


func target() -> Node3D:
	return _target


func is_active() -> bool:
	return active


func is_bound() -> bool:
	return _camera != null


func mode_id() -> String:
	return _rig.mode_id if _rig != null else ""


func preset() -> String:
	return _rig.follow_preset if _rig != null else ""


func zoom_size() -> float:
	return _rig.size if _rig != null else 0.0


func is_occluded() -> bool:
	return _occluded


func is_captured() -> bool:
	return _capture_owned


## 只读：本 rig 是否正在跟踪某个按住键（验收读回用，Q/E 由 rig 而非场景跟踪）。
func is_key_held(code: Key) -> bool:
	return bool(_held.get(code, false))


## 只读快照：模式 / 预设 / 焦点 / 前视 / 地面基 / 捕获 / 遮挡 / 相机变换。
func snapshot() -> Dictionary:
	return {
		"mode": _rig.mode_id,
		"preset": _rig.follow_preset,
		"focus": _rig.focus,
		"camera_focus": _rig.focus + _rig.lookahead,
		"lookahead": _rig.lookahead,
		"yaw_degrees": yaw_degrees(),
		"pitch_degrees": _rig.pitch_degrees,
		"zoom_size": _rig.size,
		"capture_active": _capture_owned,
		"drag_active": _rig.drag_active,
		"occlusion": _occluded,
		"blending": _blend_left > 0.0,
		"camera_transform": _camera.global_transform if _camera != null else Transform3D.IDENTITY,
		"right": right_axis(),
		"forward": forward_axis(),
		"target_position": _rig.target_position,
		"target_velocity": _rig.target_velocity,
		"focus_offset": _rig.focus_offset,
		"distance_bias": _rig.distance_bias,
		"effective_distance": _rig.effective_distance(_rig.distance),
		"pan_offset": _pan_offset(),
		"recenter_request": _rig.recenter_request,
		"projection": _rig.projection,
		"fov": _rig.fov,
	}


## 只读：overview 当前的平移量（焦点实际相对目标的偏移）。
func _pan_offset() -> Vector3:
	return _rig.focus - _rig.target_position


## 实际渲染偏航（最终相机基）；未绑定时退回期望值，仅用于读数与 HUD。
func yaw_degrees() -> float:
	if _camera == null:
		return _rig.yaw_degrees
	var forward := -_camera.global_transform.basis.z
	return rad_to_deg(atan2(-forward.x, -forward.z))


## 实际渲染俯角（度）：直接从相机基算出（offset 方向已知，pitch = asin(-forward.y)），
## 不做任何焦点 / 距离互推，因此不存在循环依赖。
func _actual_pitch_degrees() -> float:
	if _camera == null:
		return _rig.pitch_degrees
	var forward := -_camera.global_transform.basis.z
	return rad_to_deg(asin(clampf(-forward.y, -1.0, 1.0)))


## 实际渲染距离（米）：上一帧提交时保存的 applied 值（真实生效值，不是互推近似）。
func _actual_distance() -> float:
	return _applied_distance


## 实际渲染焦点：上一帧提交时保存的 applied 值。
func _actual_focus() -> Vector3:
	return _applied_focus


## 实际前视偏移：上一帧提交时保存的 applied 值。
func _actual_lookahead() -> Vector3:
	return _applied_lookahead


# --- 装配控制 ---------------------------------------------------------------


## 让位 / 接管：同一目标下只有一个 rig 处于 active；让位时只释放自己的捕获。
func set_active(value: bool) -> void:
	active = value
	if not active:
		release_capture()


## 请求切换模式：下一物理帧生效并开始混合；未列在 mode_cycle 的模式不被接受。
func request_mode(value: String) -> bool:
	if _rig == null or not mode_cycle.has(value):
		return false
	if value == _rig.mode_id and _rig.mode_request.is_empty():
		return false
	_rig.mode_request = value
	return true


func request_preset(value: String) -> bool:
	if _rig == null or not preset_cycle.has(value):
		return false
	_rig.follow_preset = value
	return true


func cycle_preset() -> String:
	if _rig == null or preset_cycle.is_empty():
		return ""
	var index := preset_cycle.find(_rig.follow_preset)
	_rig.follow_preset = preset_cycle[(index + 1) % preset_cycle.size()]
	return _rig.follow_preset


## overview 回中请求：由可视按钮或 Home 键触发，模式回中完成后自行清除。
func request_recenter() -> void:
	if _rig != null:
		_rig.recenter_request = true


## 直接设定偏航（重置 / 验收与外部编排用；正常操作路径是输入）。
func set_yaw_degrees(value: float) -> void:
	if _rig != null:
		_rig.yaw_degrees = value


## 直接设定缩放（验收用）。
func set_zoom_size(value: float) -> void:
	if _rig != null:
		_rig.size = clampf(value, _rig.size_min, _rig.size_max)


func adjust_zoom(steps: float) -> void:
	if _rig != null:
		_rig.zoom_steps += steps


## 相机地面基：与最终渲染一致（平滑混合期间也读实际相机），场景可直接用它驱动移动。
func right_axis() -> Vector3:
	if _camera == null:
		var yaw := deg_to_rad(_rig.yaw_degrees)
		return Vector3(cos(yaw), 0.0, -sin(yaw)).normalized()
	return _ground_axis(_camera.global_transform.basis.x, Vector3.RIGHT)


func forward_axis() -> Vector3:
	if _camera == null:
		var yaw := deg_to_rad(_rig.yaw_degrees)
		return Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()
	return _ground_axis(-_camera.global_transform.basis.z, Vector3.FORWARD)


func _ground_axis(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


## 复位：回 mode_cycle[0] 与初值、清输入与捕获、焦点贴回目标、姿态立即生效（不做混合）。
## 场景的默认模式可与 mode_cycle[0] 不同（如默认组合环绕、1 号键仍是 fixed_follow），
## 这类场景在 reset_state() 之后自行 request_mode 回默认模式。
func reset_state() -> void:
	if _rig == null:
		return
	release_capture()
	_held.clear()
	_rig.mode_request = ""
	if _seed_config != null:
		_apply_config(_seed_config)
	_rig.mode_id = _default_mode()
	if _target != null:
		_rig.target_position = _target.global_position
		_rig.focus = _target.global_position
	_rig.lookahead = Vector3.ZERO
	_rig.look_delta = Vector2.ZERO
	_rig.zoom_steps = 0.0
	_rig.yaw_input = 0.0
	_rig.recenter_request = false
	_end_pan()
	_target_has_previous = _target != null
	_target_last_position = _target.global_position if _target != null else Vector3.ZERO
	_blend_left = 0.0
	if _camera != null and _rig.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_camera.size = _rig.size


## 释放本 rig 拥有的捕获并恢复进入前的 mouse_mode；未拥有时是幂等空操作。
func release_capture() -> void:
	_held.clear()
	if _rig != null:
		_rig.capture_active = false
		_rig.drag_active = false
		_rig.look_delta = Vector2.ZERO
		_rig.yaw_input = 0.0
		# 平移（MMB）不捕获鼠标，但同样由本节点拥有：失焦 / 退场 / reset / 切模式都要结束，
		# 否则回到 overview 时鼠标没按下也会继续平移。
		_end_pan()
	if not _capture_owned:
		return
	_capture_owned = false
	Input.set_mouse_mode(_previous_mouse_mode)


## 结束平移并丢弃累积位移（幂等）；MMB 抬起、失焦、退场、切模式共用。
func _end_pan() -> void:
	if _rig == null:
		return
	_rig.pan_active = false
	_rig.pan_delta = Vector2.ZERO
	_rig.pan_world_delta = Vector3.ZERO


## 只读：平移是否处于进行中（HUD / 测试）。
func is_panning() -> bool:
	return _rig != null and _rig.pan_active


## 开始姿态混合：起点取当前真实渲染状态（实际相机 transform / 位置 / 投影参数）。
## 释放捕获并清未消费输入，避免旧模式的 delta 被新模式应用（不积累旧 delta）。
func begin_blend() -> void:
	release_capture()
	_rig.pan_world_delta = Vector3.ZERO
	_rig.yaw_step_request = 0.0
	if _blend_duration <= 0.0:
		_blend_active = false
		_blend_left = 0.0
		return
	_blend_from_focus = _actual_focus()
	_blend_from_lookahead = _actual_lookahead()
	_blend_from_yaw = yaw_degrees()
	_blend_from_pitch = _actual_pitch_degrees()
	_blend_from_distance = _actual_distance()
	_blend_from_size = _camera.size if _camera != null else _rig.size
	_blend_from_fov = _camera.fov if _camera != null else _rig.fov
	_blend_active = true
	_blend_left = _blend_duration


# --- 输入 -------------------------------------------------------------------


## 拖拽结束：MMB 抬起走 _input；平移不捕获鼠标，但释放事件可能被 GUI 消费。
## 只在本节点确实处于平移中时消费，避免影响其它 UI 的拖拽。
func handle_drag_end_input(event: InputEvent) -> bool:
	if not active or _rig == null or not _rig.pan_active:
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE and not button.pressed:
			_end_pan()
			get_viewport().set_input_as_handled()
			return true
	return false


## 捕获态兜底：只处理 RMB 释放与 Esc，处理即消费；非捕获态返回 false 交给场景返回。
func handle_captured_input(event: InputEvent) -> bool:
	if not active or _rig == null or not _capture_owned:
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and not button.pressed:
			release_capture()
			get_viewport().set_input_as_handled()
			return true
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if key_event.pressed and not key_event.echo and code == KEY_ESCAPE:
			release_capture()
			get_viewport().set_input_as_handled()
			return true
	return false


## 未被视图消费的事件：数字键选模式、Q/E 偏航、MMB 平移、滚轮 / Z / X 缩放。
## RMB 走 _input 早期路径（见 handle_rmb_input），保证嵌入 Game 视图不先看到世界区域右键。
func handle_input(event: InputEvent) -> bool:
	if not active or _rig == null:
		return false
	if event is InputEventKey:
		return _handle_key(event as InputEventKey)
	if event is InputEventMouseButton:
		return _handle_button(event as InputEventMouseButton)
	if event is InputEventMouseMotion:
		return _handle_motion(event as InputEventMouseMotion)
	return false


## 交互 GUI 上方：控件可见且非 mouse_filter=IGNORE 时右键归 GUI，镜头包不劫持。
## 无控件或悬停控件不接收鼠标（如 LabHud 的 IGNORE 根 / 标签）时按世界区域处理。
func _gui_wants_mouse() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.visible and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


## RMB 早期路径（_input，早于 GUI / 嵌入 Game 视图的视图输入）：
## - orbit 且 enable_yaw_keys：UI 未占用时同一事件内捕获（按下）/ 释放（抬起）；
## - 其余模式且 consume_unowned_rmb：消费世界区域 press / release，但不捕获、
##   不写 mouse_mode、不写 look_delta；默认关闭时原样放行。
## 返回 true 表示事件已被本 rig 处理。
func handle_rmb_input(event: InputEvent) -> bool:
	if not active or _rig == null or not (event is InputEventMouseButton):
		return false
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_RIGHT:
		return false
	# 捕获态下的释放由 handle_captured_input 兜底（即使 GUI 消费也不丢）；此处不重复处理。
	if not button.pressed and _capture_owned:
		return false
	if _gui_wants_mouse():
		return false
	if _rig.mode_id == "orbit" and _yaw_keys_enabled():
		# 组合环绕：同一输入事件内进入 / 退出捕获，不延迟到物理帧。
		if button.pressed:
			_rig.drag_active = true
			_begin_capture()
		else:
			release_capture()
		return true
	if _consume_unowned_rmb():
		# 未归属 RMB 策略：只消费事件，不捕获、不改 mouse_mode、不写 look_delta。
		return true
	return false


func _input(event: InputEvent) -> void:
	# 早期 RMB：世界区域 press 先于嵌入 Game 视图的上下文操作被本 rig 处理。
	if handle_rmb_input(event):
		get_viewport().set_input_as_handled()
		return
	if handle_drag_end_input(event):
		return
	handle_captured_input(event)


func _unhandled_input(event: InputEvent) -> void:
	# 平移结束已在 _input 兜底；这里只负责开始与其余未消费输入。
	if handle_input(event):
		get_viewport().set_input_as_handled()


func _handle_key(key_event: InputEventKey) -> bool:
	var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	# Q / E 只被两个偏航模式消费；其他模式放行，场景可另作实验快捷键。
	if YAW_KEYS.has(code):
		if not _yaw_keys_enabled():
			return false
		if _rig.mode_id == "quarter_turn":
			# 离散：只在 key-down 记一步，按住不连续重复。
			if key_event.pressed and not key_event.echo:
				_rig.yaw_step_request += YAW_KEYS[code] as float * _rig.turn_step_degrees
			return true
		if _rig.mode_id == "orbit":
			_held[code] = key_event.pressed
			return true
		return false
	if not key_event.pressed or key_event.echo:
		return false
	if _mode_selection_enabled():
		var mode_index := MODE_KEYS.find(code)
		if mode_index >= 0 and mode_index < mode_cycle.size():
			request_mode(mode_cycle[mode_index])
			return true
	if code == KEY_HOME:
		# overview 回中：只在 overview 下消费。
		if _rig.mode_id == "overview":
			_rig.recenter_request = true
			return true
		return false
	if code == KEY_TAB and _preset_key_enabled():
		cycle_preset()
		return true
	if code == KEY_Z and _zoom_keys_enabled():
		adjust_zoom(1.0)
		return true
	if code == KEY_X and _zoom_keys_enabled():
		adjust_zoom(-1.0)
		return true
	return false


func _handle_button(button: InputEventMouseButton) -> bool:
	if button.button_index == MOUSE_BUTTON_RIGHT:
		# RMB 的唯一归属路径：orbit + enable_yaw_keys 捕获 / 拖动；其余模式由
		# consume_unowned_rmb 决定是否只消费事件。默认关闭时返回 false 放行给场景。
		# 世界区域的早期处理（含 GUI 优先）在 _input 的 handle_rmb_input。
		if _rig.mode_id == "orbit" and _yaw_keys_enabled():
			if button.pressed:
				_rig.drag_active = true
				_begin_capture()
			else:
				release_capture()
			return true
		return _consume_unowned_rmb()
	if button.button_index == MOUSE_BUTTON_MIDDLE:
		# MMB 只属于 overview：按住拖拽平移焦点，抬起结束。
		if _rig.mode_id != "overview":
			return false
		_rig.pan_active = button.pressed
		if not button.pressed:
			_rig.pan_world_delta = Vector3.ZERO
		return true
	if not button.pressed:
		return false
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		return _handle_wheel(1.0)
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		return _handle_wheel(-1.0)
	return false


## 滚轮缩放：受配置开关控制；GUI 已消费的滚轮不会到达这里。
func _handle_wheel(steps: float) -> bool:
	if not _zoom_wheel_enabled():
		return false
	adjust_zoom(steps)
	return true


func _handle_motion(motion: InputEventMouseMotion) -> bool:
	# 捕获态用 screen_relative：不受 stretch 缩放影响；像素位移不乘帧时长。
	if _rig.mode_id == "orbit" and _rig.drag_active:
		_rig.look_delta += motion.screen_relative
		return true
	if _rig.mode_id == "overview" and _rig.pan_active:
		_rig.pan_delta += motion.screen_relative
		return true
	return false


## 记录进入前的 mouse_mode，只标记本 rig 自己的捕获归属。
func _begin_capture() -> void:
	if not _capture_owned:
		_previous_mouse_mode = Input.get_mouse_mode()
		_capture_owned = true
	_rig.capture_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# --- 物理帧：唯一写 Camera3D -------------------------------------------------


func _physics_process(delta: float) -> void:
	advance(delta)


## 推进一个 executor 帧：采样输入与目标 snapshot → 调度模式 → 写相机 → 发布地面基。
## 由 _physics_process 每物理帧调用；无头验收也可直接调用它做确定性推进。
func advance(delta: float) -> void:
	if not active or _rig == null or _manager == null or _camera == null:
		return
	_begin_frame(delta)
	_manager.tick(delta)
	_apply_camera(delta)
	_publish_ground_basis()
	_end_frame()


func _begin_frame(delta: float) -> void:
	if not _rig.mode_request.is_empty():
		# 模式交接：释放旧模式的捕获并结束平移，避免旧模式的输入留给新模式。
		release_capture()
		_rig.mode_id = _rig.mode_request
		_rig.mode_request = ""
		begin_blend()
		mode_changed.emit(_rig.mode_id)
	var axis := 0.0
	for code in YAW_KEYS:
		if _held.get(code, false):
			axis += YAW_KEYS[code] as float
	_rig.yaw_input = clampf(axis, -1.0, 1.0)
	# 捕获态以本 rig 的归属为准，不从全局 mouse_mode 反推（避免认领别人的捕获）。
	_rig.capture_active = _capture_owned
	_bridge_target(delta)
	_update_modifier(delta)
	_update_pan_delta()
	_update_occlusion()


## overview 平移：把像素位移按实际相机基与投影换算成世界位移（离开目标后仍与实际画面一致）。
func _update_pan_delta() -> void:
	_rig.pan_world_delta = Vector3.ZERO
	if _camera == null or not _rig.pan_active or _rig.pan_delta == Vector2.ZERO:
		_rig.pan_delta = Vector2.ZERO
		return
	var right := right_axis()
	var forward := forward_axis()
	# 像素 → 米：正交为 size / 视口高度；透视为当前距离处的视锥高度 / 视口高度。
	# pan_speed 是倍率（1.0 = 与画面 1:1），只在这里用一次。
	var viewport_height := maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	var meters_per_pixel := 0.0
	if _rig.projection == Camera3D.PROJECTION_ORTHOGONAL:
		meters_per_pixel = _rig.size / viewport_height
	else:
		var frustum_height := 2.0 * _actual_distance() * tan(deg_to_rad(_camera.fov * 0.5))
		meters_per_pixel = frustum_height / viewport_height
	var scale := meters_per_pixel * maxf(_rig.pan_speed, 0.0)
	# 向右拖 → 画面内容向右走 → 焦点向左移；向下拖 → 焦点向相机前方移。
	_rig.pan_world_delta = right * (-_rig.pan_delta.x * scale) + forward * (_rig.pan_delta.y * scale)
	_rig.pan_delta = Vector2.ZERO


## 目标 snapshot 桥接：只读 Node3D 全局位置，速度由位移差分得到。
func _bridge_target(delta: float) -> void:
	if _target == null:
		_rig.target_velocity = Vector3.ZERO
		return
	var position := _target.global_position
	# 速度差分必须用目标的真实 global_position（不受 focus_offset 影响）。
	if _target_has_previous and delta > 0.0:
		_rig.target_velocity = (position - _target_last_position) / delta
	else:
		_rig.target_velocity = Vector3.ZERO
	_target_last_position = position
	_target_has_previous = true
	# 取景用目标位置加 focus_offset（胸部 / 其它场景偏移），模式读 target_position。
	_rig.target_position = position + _rig.focus_offset


## modifier 数据：把目标高度与水平速度写进组件，由组件派生距离偏移（非 Capability）。
func _update_modifier(delta: float) -> void:
	_rig.target_altitude = _rig.target_position.y
	_rig.target_speed = Vector2(_rig.target_velocity.x, _rig.target_velocity.z).length()
	if _motion_source != null and is_instance_valid(_motion_source):
		_rig.target_on_floor = _motion_source.is_on_floor()
		_rig.target_flight_active = bool(_motion_source.motion().flight_active)
	_rig.distance_bias = _rig.modifier_distance_bias()


## 可选：桥接一个物理目标（actor）以读取着地 / 御剑状态；不传则不读。
func bind_motion_source(body: CharacterBody3D) -> void:
	_motion_source = body


## 遮挡读数：只读观察项，不改变镜头行为。目标不是碰撞体时仅不排除自身。
func _update_occlusion() -> void:
	_occluded = false
	if _camera == null or _target == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		_camera.global_position,
		_target.global_position + Vector3(0.0, 0.9, 0.0)
	)
	var body := _target as CollisionObject3D
	if body != null:
		query.exclude = [body.get_rid()]
	_occluded = not space.intersect_ray(query).is_empty()


func _apply_camera(delta: float) -> void:
	if _rig.focus_clamp_enabled:
		_rig.focus = _rig.clamped_focus(_rig.focus)
	# 期望姿态来自模式 Capability；切换后在过渡时间内插值到它。
	var desired_focus := _rig.focus
	var desired_lookahead := _rig.lookahead
	var desired_yaw := _rig.yaw_degrees
	var desired_pitch := _rig.pitch_degrees
	var desired_distance := _rig.effective_distance(_rig.distance)
	var desired_size := _rig.size
	var desired_fov := _rig.fov
	if _blend_active and _blend_left > 0.0 and _blend_duration > 0.0:
		_blend_left = maxf(_blend_left - delta, 0.0)
		var alpha := 1.0 - _blend_left / _blend_duration
		if _blend_left <= 0.0:
			_blend_active = false
		# 焦点与前视一起迁移：deadzone 焦点偏离目标时切 orbit 不会位置跳。
		desired_focus = _blend_from_focus.lerp(_rig.focus, alpha)
		desired_lookahead = _blend_from_lookahead.lerp(_rig.lookahead, alpha)
		var blended_yaw := lerp_angle(deg_to_rad(_blend_from_yaw), deg_to_rad(_rig.yaw_degrees), alpha)
		desired_yaw = rad_to_deg(blended_yaw)
		desired_pitch = lerpf(_blend_from_pitch, _rig.pitch_degrees, alpha)
		desired_distance = lerpf(_blend_from_distance, _rig.effective_distance(_rig.distance), alpha)
		desired_size = lerpf(_blend_from_size, _rig.size, alpha)
		desired_fov = lerpf(_blend_from_fov, _rig.fov, alpha)
	var yaw := deg_to_rad(desired_yaw)
	var pitch := deg_to_rad(desired_pitch)
	var horizontal := desired_distance * cos(pitch)
	var offset := Vector3(sin(yaw) * horizontal, desired_distance * sin(pitch), cos(yaw) * horizontal)
	# 前视平移整个取景（相机位与瞄准点同步前移），角色因此退到画面后侧。
	var focus := desired_focus + desired_lookahead
	_camera.global_position = focus + offset
	_camera.look_at(focus, Vector3.UP)
	_camera.projection = _rig.projection
	if _rig.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_camera.size = desired_size
	else:
		_camera.fov = desired_fov
	_camera.near = _rig.near
	_camera.far = _rig.far
	# 提交后保存真实生效状态：下一帧的混合起点与 pan 换算读它，不从 transform 反推。
	_applied_focus = desired_focus
	_applied_lookahead = desired_lookahead
	_applied_distance = desired_distance


## 桥接层把最终相机地面基写给目标（目标支持该公开 API 时）。
## 只有本节点调用；模式 Capability 不接触 actor。
func _publish_ground_basis() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if not _target.has_method("set_camera_ground_basis"):
		return
	_target.call("set_camera_ground_basis", right_axis(), forward_axis())


func _end_frame() -> void:
	# 输入请求只在消费帧有效；未消费的模式由这里兜底清零，避免跨帧累积后突然应用。
	_rig.yaw_input = 0.0
	_rig.zoom_steps = 0.0
	_rig.look_delta = Vector2.ZERO


func _default_mode() -> String:
	return mode_cycle[0] if not mode_cycle.is_empty() else ""


## 取直系子节点中第一个指定类型的节点（Component / Manager 各唯一）。
func _first_child_of_type(type: Variant) -> Node:
	for child in get_children():
		if type is Script:
			if child.get_script() == type:
				return child
		elif child.is_class(str(type)):
			return child
	return null