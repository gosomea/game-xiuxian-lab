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
const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")

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

## 相机固定偏移，做轻柔跟随；正交俯视保证尺度可读。
const CAMERA_OFFSET := Vector3(14.0, 17.0, 15.0)
const CAMERA_SIZE := 24.0
const CAMERA_SIZE_MIN := 14.0
const CAMERA_SIZE_MAX := 34.0
## 跟随目标在场地内收缩，避免边界处构图漂移；0 表示硬跟随。
const FOLLOW_MARGIN := Vector3(3.0, 0.0, 2.5)
const FOLLOW_SPEED := 3.5

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _follow_target := Vector3.ZERO
var _pressed: Dictionary = {}
var _status: Label


func _ready() -> void:
	# 细碎锯齿来自兼容渲染器的边缘走样：进入本场景时开 4x MSAA，离开时恢复进入前的值，
	# 不把状态泄漏给实验目录等其他场景。
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "movement_garden: 场景必须提供 Camera3D")
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_build_garden()
	_build_ground_collision()
	_build_boundaries()
	_build_obstacles()
	_spawn_player()
	_build_hud()
	_reset_camera()
	_update_status()


func _exit_tree() -> void:
	# 恢复共享根视口的 MSAA，避免切换场景后残留（_viewport 引用在节点离树后仍有效）。
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()


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
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = clampf(_camera.size - 1.5, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + 1.5, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	# 屏幕相对：相机右方/前方投影到 y=0 平面后规范化，退化时回退世界轴。
	_player.set_camera_ground_basis(
		_ground_vector(_camera.global_transform.basis.x, Vector3.RIGHT),
		_ground_vector(-_camera.global_transform.basis.z, Vector3.FORWARD)
	)
	_player.set_move_input(_read_move_input())
	# 角色朝运动方向；停下时不写朝向，由角色保留最后一次朝向。
	if _motion.move_input != Vector2.ZERO:
		var direction := _motion.camera_right * _motion.move_input.x - _motion.camera_forward * _motion.move_input.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())
	_follow_camera(delta)


func _process(_delta: float) -> void:
	_update_status()


func _read_move_input() -> Vector2:
	var input_vector := Vector2.ZERO
	for code in MOVE_KEYS:
		if _pressed.get(code, false):
			input_vector += MOVE_KEYS[code] as Vector2
	return input_vector.limit_length(1.0)


func _ground_vector(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


func _follow_camera(delta: float) -> void:
	var target := _player.global_position
	target.x = clampf(target.x, -ARENA_HALF_X + FOLLOW_MARGIN.x, ARENA_HALF_X - FOLLOW_MARGIN.x)
	target.z = clampf(target.z, -ARENA_HALF_Z + FOLLOW_MARGIN.z, ARENA_HALF_Z - FOLLOW_MARGIN.z)
	target.y = 0.0
	_follow_target = _follow_target.lerp(target, clampf(delta * FOLLOW_SPEED, 0.0, 1.0))
	_camera.position = _follow_target + CAMERA_OFFSET
	_camera.look_at(_follow_target, Vector3.UP)


func _reset_camera() -> void:
	_follow_target = Vector3.ZERO
	_camera.size = CAMERA_SIZE
	_camera.position = CAMERA_OFFSET
	_camera.look_at(Vector3.ZERO, Vector3.UP)


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
	_reset_camera()


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


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	add_child(layer)

	var interface := Control.new()
	interface.name = "Interface"
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interface.theme = LAB_THEME
	layer.add_child(interface)
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 20)
	interface.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(header)

	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(titles)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.theme_type_variation = "AccentLabel"
	kicker.add_theme_font_size_override("font_size", 13)
	kicker.text = "EXPERIMENT    /    CHARACTER MOVEMENT"
	titles.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 28)
	title.text = "角色移动 · 庭院"
	titles.add_child(title)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = "MutedLabel"
	_status.add_theme_font_size_override("font_size", 14)
	titles.add_child(_status)

	var return_button := Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回子实验目录"
	return_button.custom_minimum_size = Vector2(140, 44)
	return_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 按钮不抢键盘焦点：移动键事件始终抵达场景的 _unhandled_input。
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.pressed.connect(_return_to_hub)
	header.add_child(return_button)

	var spacer := Control.new()
	spacer.name = "Space"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(footer)

	var controls := Label.new()
	controls.name = "Controls"
	controls.theme_type_variation = "MutedLabel"
	controls.add_theme_font_size_override("font_size", 14)
	controls.text = "WASD 屏幕相对移动（角色朝运动方向）  ·  滚轮缩放  ·  R 重置  ·  Esc 返回子实验目录"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(controls)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.custom_minimum_size = Vector2(96, 44)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_experiment)
	footer.add_child(reset_button)


func _update_status() -> void:
	if _status == null:
		return
	_status.text = "观察移动、转向与空间尺度"