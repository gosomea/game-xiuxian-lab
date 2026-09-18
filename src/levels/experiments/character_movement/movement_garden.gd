extends Node3D

## 纯移动实验：角色移动 × 庭院观察（见 notes/implemented/gameplay/2026-09-18-character-movement-garden.md）。
##
## 职责边界：
## - 角色与移动行为归 res://game/actors/swordsman/（SwordsmanMotionComponent + SwordsmanMovement）
## - 庭院美术归同目录 movement_garden.glb（由 Blender 资产生成代理维护，本脚本不改 GLB）
## 本场景只做实验编排：屏幕相对输入、转向表现、地面/边界/障碍代理、相机与精简 HUD。
## 无鼠标瞄准、无左键攻击、无战斗 UI。关键依赖全部 preload：缺失即解析失败。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const GARDEN_SCENE: PackedScene = preload("res://levels/experiments/character_movement/movement_garden.glb")
const RIG_SHEET: PackedScene = preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")

## 庭院尺寸 18 x 14 米，地面 y = 0，中央为空地。
const ARENA_HALF_X := 9.0
const ARENA_HALF_Z := 7.0
const GROUND_THICKNESS := 0.5
const WALL_HEIGHT := 2.0
const WALL_THICKNESS := 1.0
const PLAYER_START := Vector3(0.0, 0.02, 3.0)
const PLAYER_NODE := "SwordsmanMotionComponent"

## 两个障碍代理：仅碰撞，视觉由庭院 GLB 提供。
const OBSTACLE_SIZE := Vector2(2.0, 2.0)
const OBSTACLE_HEIGHT := 1.0
const OBSTACLE_POSITIONS: Array[Vector3] = [
	Vector3(-4.0, 0.0, 0.0),
	Vector3(4.0, 0.0, -1.0),
]

## 物理键 → 屏幕输入（x = 右，y = 下）。用物理键码维护 pressed 字典，不看键盘布局。
const MOVE_KEYS := {
	KEY_W: Vector2(0.0, -1.0),
	KEY_S: Vector2(0.0, 1.0),
	KEY_A: Vector2(-1.0, 0.0),
	KEY_D: Vector2(1.0, 0.0),
}

## 相机：正交俯视 + 软区跟随。数值由旧固定偏移 (14, 17, 15) 换算而来
## （yaw≈43.0°、pitch≈39.6°、distance≈26.65），保持既有庭院构图不变。
const CAMERA_YAW_DEGREES := 43.0
const CAMERA_PITCH_DEGREES := 39.6
const CAMERA_DISTANCE := 26.65
const CAMERA_SIZE := 24.0
const CAMERA_SIZE_MIN := 14.0
const CAMERA_SIZE_MAX := 34.0
## 跟随目标在场地内收缩，避免边界处构图漂移；对应旧的 FOLLOW_MARGIN。
const FOLLOW_MARGIN := Vector3(3.0, 0.0, 2.5)
## 旧 lerp 速度 3.5 等价的时间常数 ≈ 1/3.5。
const FOLLOW_SMOOTH_TIME := 0.29
const CAMERA_FAR := 120.0

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _rig: CameraRig
var _pressed: Dictionary = {}
var _hud: LabHud
var _mode_button: Button


func _ready() -> void:
	# 细碎锯齿来自兼容渲染器的边缘走样：进入本场景时开 4x MSAA，离开时恢复进入前的值，
	# 不把状态泄漏给实验目录等其他场景。
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "movement_garden: 场景必须提供 Camera3D")
	_build_garden()
	_build_ground_collision()
	_build_boundaries()
	_build_obstacles()
	_spawn_player()
	_build_rig()
	_build_hud()
	_update_status()


func _exit_tree() -> void:
	# 恢复共享根视口的 MSAA，避免切换场景后残留（_viewport 引用在节点离树后仍有效）。
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()
		if _rig != null:
			_rig.release_capture()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		# 物理键码优先（不看键盘布局）；个别平台 Ctrl 等只填逻辑键码时回退。
		var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if MOVE_KEYS.has(code):
			_pressed[code] = key_event.pressed
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo:
			if code == KEY_R:
				get_viewport().set_input_as_handled()
				_reset_experiment()
				return
			if event.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				_return_to_hub()
				return


func _physics_process(_delta: float) -> void:
	# 相机地面基由 CameraRig 桥接写入角色（同帧一致）；本场景只做屏幕相对输入与朝向。
	_player.set_move_input(_read_move_input())
	# 角色朝运动方向；停下时不写朝向，由角色保留最后一次朝向。
	if _motion.move_input != Vector2.ZERO:
		var direction := _motion.camera_right * _motion.move_input.x - _motion.camera_forward * _motion.move_input.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())


func _process(_delta: float) -> void:
	_update_status()


func _read_move_input() -> Vector2:
	var input_vector := Vector2.ZERO
	for code in MOVE_KEYS:
		if _pressed.get(code, false):
			input_vector += MOVE_KEYS[code] as Vector2
	return input_vector.limit_length(1.0)


func _clear_pressed() -> void:
	_pressed.clear()
	if _player != null:
		# 只清输入：本场景不装配御剑操作，行为与旧版一致。
		_player.clear_input()


func _reset_experiment() -> void:
	_clear_pressed()
	_player.global_position = PLAYER_START
	_player.reset_motion()
	_player.set_aim_direction(Vector3.FORWARD)
	_rig.reset_state()


func _return_to_hub() -> void:
	_clear_pressed()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	if result != OK:
		push_error("movement_garden: 返回子实验目录失败，错误码 %d" % result)


func _build_garden() -> void:
	var garden := GARDEN_SCENE.instantiate() as Node3D
	assert(garden != null, "movement_garden: movement_garden.glb 根节点必须是 Node3D")
	garden.name = "Garden"
	add_child(garden)


func _build_ground_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = Vector3(0.0, -GROUND_THICKNESS * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ARENA_HALF_X * 2.0, GROUND_THICKNESS, ARENA_HALF_Z * 2.0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _build_boundaries() -> void:
	var root := Node3D.new()
	root.name = "Boundaries"
	add_child(root)
	var span_x := ARENA_HALF_X + WALL_THICKNESS * 0.5
	var span_z := ARENA_HALF_Z + WALL_THICKNESS * 0.5
	var length_x := ARENA_HALF_X * 2.0 + WALL_THICKNESS * 2.0
	var length_z := ARENA_HALF_Z * 2.0 + WALL_THICKNESS * 2.0
	_make_block(root, "North", Vector3(0.0, WALL_HEIGHT * 0.5, -span_z), Vector3(length_x, WALL_HEIGHT, WALL_THICKNESS))
	_make_block(root, "South", Vector3(0.0, WALL_HEIGHT * 0.5, span_z), Vector3(length_x, WALL_HEIGHT, WALL_THICKNESS))
	_make_block(root, "West", Vector3(-span_x, WALL_HEIGHT * 0.5, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, length_z))
	_make_block(root, "East", Vector3(span_x, WALL_HEIGHT * 0.5, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, length_z))


func _build_obstacles() -> void:
	var root := Node3D.new()
	root.name = "Obstacles"
	add_child(root)
	for index in range(OBSTACLE_POSITIONS.size()):
		var center := OBSTACLE_POSITIONS[index]
		var size := Vector3(OBSTACLE_SIZE.x, OBSTACLE_HEIGHT, OBSTACLE_SIZE.y)
		_make_block(root, "Obstacle%d" % (index + 1), center + Vector3(0.0, OBSTACLE_HEIGHT * 0.5, 0.0), size)


func _make_block(parent: Node, block_name: String, block_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = block_position
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


func _spawn_player() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "movement_garden: swordsman.tscn 根节点必须是 Swordsman")
	actor.name = "Swordsman"
	actor.position = PLAYER_START
	add_child(actor)
	_player = actor
	_motion = actor.get_node_or_null(PLAYER_NODE) as SwordsmanMotionComponent
	assert(_motion != null, "movement_garden: 角色缺少 %s" % PLAYER_NODE)
	assert(actor.get_node_or_null("CapabilityManager") != null, "movement_garden: 角色缺少唯一 CapabilityManager")


## 装配共享 CameraRig：正交 + 软区跟随，参数换算自旧的固定偏移相机，构图保持不变。
func _build_rig() -> void:
	var rig := RIG_SHEET.instantiate() as CameraRig
	assert(rig != null, "movement_garden: camera_rig_sheet.tscn 根节点必须是 CameraRig")
	rig.name = "CameraRig"
	add_child(rig)
	_rig = rig
	var config := CameraRigConfig.new()
	config.start_mode = "fixed_follow"
	config.follow_preset = "smooth"
	config.yaw_degrees = CAMERA_YAW_DEGREES
	config.pitch_degrees = CAMERA_PITCH_DEGREES
	config.distance = CAMERA_DISTANCE
	config.size = CAMERA_SIZE
	config.size_min = CAMERA_SIZE_MIN
	config.size_max = CAMERA_SIZE_MAX
	config.smooth_time = FOLLOW_SMOOTH_TIME
	config.near = 0.1
	config.far = CAMERA_FAR
	# 庭院是地面小场景：显式打开 y 夹取并把 min/max y 设为 0，保持旧地平构图。
	config.focus_clamp_enabled = true
	config.focus_clamp_y_enabled = true
	config.focus_clamp_min = Vector3(-ARENA_HALF_X + FOLLOW_MARGIN.x, 0.0, -ARENA_HALF_Z + FOLLOW_MARGIN.z)
	config.focus_clamp_max = Vector3(ARENA_HALF_X - FOLLOW_MARGIN.x, 0.0, ARENA_HALF_Z - FOLLOW_MARGIN.z)
	# 庭院默认仍是旧构图（fixed_follow + smooth），但允许切到 orbit 作为第二消费者验证；
	# 不占数字键（模式切换只走可视按钮），Q/E 只在 orbit 内被消费。
	config.mode_choices = PackedStringArray(["fixed_follow", "orbit"])
	config.enable_mode_selection_keys = false
	config.enable_preset_key = false
	config.enable_zoom_keys = false
	config.enable_yaw_keys = true
	_rig.bind(_camera, _player, config)



## 只读：本场的镜头 rig（测试与外部观察用）。
func rig() -> CameraRig:
	return _rig


## 紧凑镜头模式切换：不占数字键，点击在 fixed_follow 与 orbit 之间切换。
## 默认进入 fixed_follow，因此初始构图与旧庭院完全一致。
func _on_mode_toggle() -> void:
	var next := "orbit" if _rig.mode_id() == "fixed_follow" else "fixed_follow"
	_rig.request_mode(next)
	_update_status()


func _build_hud() -> void:
	_hud = LabHud.new()
	add_child(_hud)
	_hud.configure("移动庭院", "角色移动 · 庭院", "WASD 移动 · 滚轮缩放 · 镜头按钮切换环绕 · H 详情")
	_hud.set_controls("WASD 屏幕相对移动（角色朝运动方向）· 滚轮缩放 · 镜头按钮在固定跟随与 RMB 环绕间切换 · R 重置 · Esc 返回子实验目录")
	_hud.set_question("小范围地面移动和既有庭院美术与构图是否仍然成立？")
	_hud.return_pressed.connect(_return_to_hub)
	_hud.set_return_text("返回子实验目录")
	var mode_button := Button.new()
	mode_button.name = "ModeToggleButton"
	mode_button.text = "镜头：固定跟随"
	mode_button.focus_mode = Control.FOCUS_NONE
	mode_button.tooltip_text = "在固定跟随与 RMB 环绕之间切换（不占用数字键）"
	mode_button.pressed.connect(_on_mode_toggle)
	_hud.add_button(mode_button)
	_mode_button = mode_button
	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_experiment)
	_hud.add_button(reset_button)


func _update_status() -> void:
	if _hud == null or _rig == null or _player == null:
		return
	var snapshot := _rig.snapshot()
	var focus: Vector3 = snapshot["focus"]
	var focus_offset := Vector2(focus.x - _player.global_position.x, focus.z - _player.global_position.z).length()
	if _mode_button != null:
		_mode_button.text = "镜头：固定跟随" if _rig.mode_id() == "fixed_follow" else "镜头：RMB 环绕"
	var mode_name := "固定跟随" if _rig.mode_id() == "fixed_follow" else "RMB 环绕"
	_hud.set_status("%s · 偏航 %d° · 缩放 %.1f · 焦点偏移 %.2f m · 速度 %.2f m/s" % [
		mode_name,
		int(round(float(snapshot["yaw_degrees"]))),
		float(snapshot["zoom_size"]),
		focus_offset,
		_motion.actual_velocity.length(),
	])
	_hud.set_debug_lines(PackedStringArray([
		"相机由共享 CameraRig 独占写；本场景不写 Camera3D 姿态",
		"相机位置 (%.2f, %.2f, %.2f)" % [
			_camera.global_position.x, _camera.global_position.y, _camera.global_position.z],
		"角色位置 (%.2f, %.2f, %.2f)" % [
			_player.global_position.x, _player.global_position.y, _player.global_position.z],
	]))