extends Node3D

## 镜头实验室（character_movement 子实验，见 notes/proposed/gameplay/2026-09-18-character-movement-subexperiments.md）。
##
## 唯一目标：在同一灰盒里比较跟随策略（固定偏移硬跟随 / 平滑跟随 / 死区 + 前视）
## 与手动缩放、镜头旋转对屏幕相对移动的影响。不修改角色与三项 Capability。
##
## 边界：
## - 角色只经公开输入 API 驱动（set_move_input / set_camera_ground_basis /
##   set_aim_direction / clear_input / reset_motion），本场景不写 velocity、意图字段
##   或能力内部状态。
## - 镜头策略只属于本实验：跟随逻辑在 CameraLabRig（同目录组合节点），不抽 core。
## - 灰盒几何在 CameraLabGraybox（同目录），不做完整地图与美术资产。
## - Esc 返回角色移动子实验目录 movement_lab_hub.tscn。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const RIG_SCRIPT: GDScript = preload("res://levels/experiments/character_movement/camera_lab_rig.gd")
const GRAYBOX_SCRIPT: GDScript = preload("res://levels/experiments/character_movement/camera_lab_graybox.gd")
const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")

const SPAWN_POSITION := Vector3(0.0, 0.1, -10.0)
const SPAWN_AIM := Vector3.FORWARD
const CAMERA_FAR := 220.0

## Q / E 按住时的偏航角速度（度/秒）。
const YAW_SPEED := 90.0

## 本场景专有的"按住生效"键：Q / E 转镜头。
## 本场景只跟踪移动键（WASD / 方向键）与这里的 YAW_KEYS，不消费空格 / Ctrl——
## 镜头实验室没有跳跃与升降语义；升降键由需要它的场景自行声明 VERTICAL_KEYS。
## 移动键映射、按住状态与失焦清账统一由 MovementLabInput 承担
## （两个消费者验证后抽取；见同目录 movement_lab_input.gd）。
const YAW_KEYS: Array[Key] = [KEY_Q, KEY_E]

## 直接切换策略的数字键（1/2/3/4 依次对应 HARD / SMOOTH / DEADZONE / LOOKAHEAD），Tab 循环。
const MODE_KEYS := {
	KEY_1: 0,
	KEY_2: 1,
	KEY_3: 2,
	KEY_4: 3,
}

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _rig: CameraLabRig
var _input := MovementLabInput.new()
var _status: Label
var _mode_label: Label
var _occluded := false


func _ready() -> void:
	# 与其他实验场景一致：进入开 4x MSAA，离开恢复，不把状态泄漏给目录。
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "camera_lab: 场景必须提供 Camera3D")
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = CAMERA_FAR
	_build_graybox()
	_spawn_player()
	_build_rig()
	_build_hud()
	_update_status()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	# 失焦只清输入；不改变镜头策略、不改变角色能力状态。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_input.clear()
		if _player != null:
			_player.clear_input()


func _unhandled_input(event: InputEvent) -> void:
	# 场景切换（Esc 返回目录）后仍可能有排队事件抵达已离树的节点：没有视口就不处理。
	var viewport := get_viewport()
	if viewport == null:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		# 物理键码优先（不看键盘布局）；个别平台修饰键只填逻辑键码时回退。
		var code := MovementLabInput.key_code(key_event)
		# 移动键与 Q / E 都只是"按住状态"；语义（移动 vs 转镜头）留在本场景。
		if _input.track_key(key_event, YAW_KEYS):
			viewport.set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo:
			if MODE_KEYS.has(code):
				_rig.set_mode(MODE_KEYS[code] as CameraLabRig.Mode)
				viewport.set_input_as_handled()
				return
			match code:
				KEY_TAB:
					_rig.cycle_mode()
				KEY_Z:
					_rig.adjust_zoom(1.0)
				KEY_X:
					_rig.adjust_zoom(-1.0)
				KEY_R:
					_reset_experiment()
				_:
					if event.is_action_pressed("ui_cancel"):
						# 先标记已处理再切场景：切完节点已离树，view 无法再访问。
						viewport.set_input_as_handled()
						_return_to_hub()
						return
					return
			viewport.set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_rig.adjust_zoom(1.0)
			viewport.set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_rig.adjust_zoom(-1.0)
			viewport.set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _player == null or _motion == null or _rig == null:
		return
	if _input.is_down(KEY_Q):
		_rig.add_yaw_degrees(-YAW_SPEED * delta)
	if _input.is_down(KEY_E):
		_rig.add_yaw_degrees(YAW_SPEED * delta)
	# 镜头旋转后，屏幕相对移动仍由相机地面基解释（与相机实际 basis 同源）。
	_player.set_camera_ground_basis(_rig.right_axis(), _rig.forward_axis())
	var move := _input.move_input()
	_player.set_move_input(move)
	# 角色朝运动方向；停下时不写朝向，由角色保留最后一次朝向。
	if move != Vector2.ZERO:
		var direction := _rig.right_axis() * move.x - _rig.forward_axis() * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())
	_rig.update(delta)


func _process(_delta: float) -> void:
	_update_occlusion()
	_update_status()


## 相机 → 角色之间的遮挡读数：纯观察项，不改变镜头行为。
func _update_occlusion() -> void:
	_occluded = false
	if _camera == null or _player == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(_camera.global_position, _player.global_position + Vector3(0.0, 0.9, 0.0))
	query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	_occluded = not hit.is_empty()


func _reset_experiment() -> void:
	_input.clear()
	_player.global_position = SPAWN_POSITION
	_player.reset_motion()
	_player.set_aim_direction(SPAWN_AIM)
	_rig.yaw_degrees = -35.0
	_rig.reset_state()


func _return_to_hub() -> void:
	_input.clear()
	if _player != null:
		_player.clear_input()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	if result != OK:
		push_error("camera_lab: 返回角色移动子实验目录失败，错误码 %d" % result)


# --- 装配 ---------------------------------------------------------------


func _build_graybox() -> void:
	GRAYBOX_SCRIPT.build(self)


func _spawn_player() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "camera_lab: swordsman.tscn 根节点必须是 Swordsman")
	actor.name = "Swordsman"
	actor.position = SPAWN_POSITION
	add_child(actor)
	_player = actor
	_motion = actor.motion()
	assert(_motion != null, "camera_lab: 角色缺少 SwordsmanMotionComponent")
	assert(actor.capability_manager() != null, "camera_lab: 角色缺少唯一 CapabilityManager")


func _build_rig() -> void:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(RIG_SCRIPT)
	add_child(rig)
	_rig = rig as CameraLabRig
	assert(_rig != null, "camera_lab: CameraLabRig 装配失败")
	_rig.setup(_camera, _player)


# --- HUD ----------------------------------------------------------------


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

	var panel := PanelContainer.new()
	panel.name = "TitlesPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_text_backdrop())
	header.add_child(panel)

	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(titles)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.theme_type_variation = "AccentLabel"
	kicker.add_theme_font_size_override("font_size", 13)
	kicker.text = "EXPERIMENT    /    CHARACTER MOVEMENT · CAMERA LAB"
	titles.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 28)
	title.text = "角色移动 · 镜头实验室"
	titles.add_child(title)

	# 当前模式单独一行、字号更大：切换策略时是唯一需要立刻读到的信息。
	_mode_label = Label.new()
	_mode_label.name = "ModeLabel"
	_mode_label.add_theme_font_size_override("font_size", 18)
	_mode_label.text = "跟随策略：—"
	titles.add_child(_mode_label)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = "MutedLabel"
	_status.add_theme_font_size_override("font_size", 14)
	titles.add_child(_status)

	var return_button := Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回子实验目录"
	return_button.custom_minimum_size = Vector2(150, 44)
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

	var controls_panel := PanelContainer.new()
	controls_panel.name = "ControlsPanel"
	controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_panel.add_theme_stylebox_override("panel", _make_text_backdrop())
	footer.add_child(controls_panel)

	var controls := Label.new()
	controls.name = "Controls"
	controls.theme_type_variation = "MutedLabel"
	controls.add_theme_font_size_override("font_size", 14)
	controls.text = "WASD / 方向键 屏幕相对移动  ·  Q / E 转镜头  ·  Tab 或 1/2/3/4 切换跟随策略  ·  滚轮或 Z / X 缩放  ·  R 复位  ·  Esc 返回"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_panel.add_child(controls)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.custom_minimum_size = Vector2(96, 44)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_experiment)
	footer.add_child(reset_button)


func _make_text_backdrop() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.980392, 0.972549, 0.949020, 0.86)
	style.border_color = Color(0.839216, 0.850980, 0.796078, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


## HUD 只读回读：模式、焦点与角色偏移、偏航、缩放与遮挡。不写任何角色状态。
func _update_status() -> void:
	if _status == null or _mode_label == null or _rig == null or _player == null:
		return
	var snapshot := _rig.snapshot()
	var focus: Vector3 = snapshot["focus"]
	var camera_focus: Vector3 = snapshot["camera_focus"]
	var lookahead: Vector3 = snapshot["lookahead"]
	# 两个偏移分开显示：焦点偏移 = 死区/缓动落后；相机偏移 = 含前视后相机实际瞄准点的落后。
	var focus_offset := Vector2(focus.x - _player.global_position.x, focus.z - _player.global_position.z).length()
	var camera_offset := Vector2(camera_focus.x - _player.global_position.x, camera_focus.z - _player.global_position.z).length()
	_mode_label.text = "跟随策略：%s" % str(snapshot["mode_label"])
	_status.text = "偏航 %d°  ·  缩放 %d/%d（size %.1f）  ·  焦点偏移 %.2f m  ·  相机偏移 %.2f m  ·  前视 %.2f m  ·  遮挡 %s" % [
		int(round(float(snapshot["yaw_degrees"]))),
		int(snapshot["zoom_index"]), _rig.zoom_levels(), float(snapshot["zoom_size"]),
		focus_offset, camera_offset, Vector2(lookahead.x, lookahead.z).length(),
		"是" if _occluded else "否",
	]


# --- 只读访问（测试与外部观察用；不暴露写入口） --------------------------


func rig() -> CameraLabRig:
	return _rig


func actor() -> Swordsman:
	return _player


func camera() -> Camera3D:
	return _camera


## 相机 → 角色视线是否被灰盒几何挡住（只读观察项）。
func is_occluded() -> bool:
	return _occluded


## 只读：本场景的输入 helper 是否登记了该键（用于验证"不吞与本场景无关的键"）。
## 不写任何状态，仅供验收脚本读回。
func input_held(code: Key) -> bool:
	return _input.is_down(code)
