extends Node3D

## 御剑飞行训练场：起飞 / 升降 / 悬停 / 穿越 / 转向 / 落点选择是否可控。
##
## 依据 [character-movement-subexperiments](../../../../notes/proposed/gameplay/2026-09-18-character-movement-subexperiments.md)
## 「御剑飞行训练场」行：立体路线场，覆盖多层落点、升降、悬停、通道与低天花。
##
## 边界：
## - 角色只用既有 Swordsman + SwordsmanMovement / Jump / SwordFlight 三能力；
##   本场景只调用公开输入 API（set_move_input / set_vertical_input / press_jump /
##   press_flight_toggle / set_camera_ground_basis / set_aim_direction / reset_motion /
##   clear_input），绝不写 velocity、组件字段或能力内部状态，也不传送角色伪造通关。
## - 唯一 move_and_slide() 在 actor 根节点。
## - 输入映射、按住状态与失焦清账走 MovementLabInput（WASD/方向键，Space/Ctrl，F）。
## - 路线判定读取角色真实轨迹与真实 on_floor / flight_active，不靠按钮标记成功。
## - 场景数据与状态机保持局部，不提炼成核心系统。
##
## 本地路线数据（sword_flight_course_collision.json）与视觉 GLB 同源生成：
## tools/art/generate_sword_flight_course.py 同时产出几何与碰撞盒坐标。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const COURSE_VISUAL: PackedScene = preload("res://levels/experiments/character_movement/sword_flight_course.glb")
const ROUTE_PATH := "res://levels/experiments/character_movement/sword_flight_course_collision.json"
const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")

const COLLISION_LAYER := 1
const CAMERA_FAR := 400.0
const CAMERA_SIZE := 34.0
const CAMERA_SIZE_MIN := 12.0
const CAMERA_SIZE_MAX := 90.0
const CAMERA_ZOOM_STEP := 3.0
const CAMERA_FOLLOW_SPEED := 4.5
const CAMERA_OFFSET := Vector3(17.0, 21.0, 18.0)

## 穿越判定：角色中心到环心的轴向距离（穿过环平面）与径向距离（在环口内）。
## 角色原点在脚底；碰撞胶囊中心相对原点高 0.8 m（与 swordsman.tscn 一致）。
## 门 / 悬停区判定用身体中心，落点判定用脚底（脚踩台面）。
const BODY_CENTER_OFFSET := 0.8

const GATE_AXIAL_TOLERANCE := 0.75
const GATE_RADIAL_MARGIN := 0.25
## 悬停判据：竖直速度绝对值不得超过此值才算"稳定悬停"（米/秒）。
## 这是悬停判据的唯一来源——不要在别处再写字面量，否则调参只改一半。
const HOVER_TICK_TOLERANCE := 0.12
const LANDING_RADIUS_MARGIN := 0.35

## 掉出回收：低于此高度即视为掉出航路（起飞坪台面 0.6 m，航线最低落点 0.8 m，
## 因此 -12 m 远低于任何可玩高度，不会误伤正常飞行与降落）。
const FALL_OUT_Y := -12.0

## 物理键 → 屏幕输入由 MovementLabInput 提供；本场景只编排语义边沿。

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _input := MovementLabInput.new()
var _visual_root: Node3D

## 路线数据（从 JSON 读入，与 Blender 生成的几何同源）。
var _takeoff_top_y := 0.6
var _gates: Array = []
var _hover: Dictionary = {}
var _landings: Array = []
var _bounds_min := Vector3.ZERO
var _bounds_max := Vector3.ZERO

## 状态机（局部）：起飞 -> 依次穿门（含悬停段）-> 落点。
var _phase := "takeoff"
var _gate_index := 0
var _hover_accumulated := 0.0
var _hover_done := false
var _landing_result := ""
var _landing_checked := false
var _previous_position := Vector3.ZERO
var _trail: Array[Vector3] = []
var _follow_target := Vector3.ZERO
var _reset_count := 0
## 掉出回收次数（与手动 R 重置分开计数，便于区分"玩家重置"与"飞丢了"）。
var _fall_out_count := 0

## HUD。
var _status: Label
var _phase_label: Label
var _gates_label: Label
var _flight_label: Label
var _landing_label: Label


# ---------------------------------------------------------------- 生命周期


func _ready() -> void:
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "sword_flight_course: 场景必须提供 Camera3D")
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.near = 0.1
	_camera.far = CAMERA_FAR
	_read_route()
	_build_visual()
	_build_collision()
	_spawn_player()
	_build_hud()
	_reset_experiment()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	# 失焦只清输入（含升降键）：已开启的御剑保留悬停，不自动关飞、不坠落。
	# 是否把边沿状态清掉由本场景决定，helper 只负责按住状态。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()


## 读取与 GLB 同源生成的路线数据；缺文件即硬失败，不静默降级。
func _read_route() -> void:
	var file := FileAccess.open(ROUTE_PATH, FileAccess.READ)
	assert(file != null, "sword_flight_course: 缺少路线数据 %s" % ROUTE_PATH)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "sword_flight_course: 路线数据不是 JSON 对象")
	var route: Dictionary = parsed
	assert(route.get("schema") == "sword_flight_course_collision/1",
		"sword_flight_course: 路线数据 schema 不匹配")
	_takeoff_top_y = float(route["takeoff"]["top_y"])
	_gates = route["gates"]
	_hover = route["hover"]
	_landings = route["landings"]
	_bounds_min = _vector(route["bounds"]["min"])
	_bounds_max = _vector(route["bounds"]["max"])
	assert(_gates.size() >= 5, "sword_flight_course: 玉环门至少 5 道")
	assert(_landings.size() >= 2, "sword_flight_course: 至少两个有取舍的落点")


func _build_visual() -> void:
	var visual := COURSE_VISUAL.instantiate() as Node3D
	assert(visual != null, "sword_flight_course: GLB 根节点必须是 Node3D")
	visual.name = "CourseVisual"
	add_child(visual)
	_visual_root = visual


## 按路线 JSON 精确装配静态碰撞：与 GLB 视觉同源（同一份数值），不做隐形墙。
func _build_collision() -> void:
	var root := Node3D.new()
	root.name = "CourseCollision"
	add_child(root)
	for entry in _colliders():
		var body := StaticBody3D.new()
		body.name = str(entry["name"])
		body.position = _vector(entry["center"])
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = COLLISION_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = _vector(entry["size"])
		shape.shape = box
		body.add_child(shape)
		root.add_child(body)


func _colliders() -> Array:
	var file := FileAccess.open(ROUTE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary)["colliders"]


func _spawn_player() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "sword_flight_course: swordsman.tscn 根节点必须是 Swordsman")
	actor.name = "Swordsman"
	add_child(actor)
	_player = actor
	_motion = actor.motion()
	assert(_motion != null, "sword_flight_course: 角色缺少 SwordsmanMotionComponent")
	assert(actor.capability_manager() != null, "sword_flight_course: 角色缺少唯一 CapabilityManager")
	actor.global_position = _spawn_position()


func _spawn_position() -> Vector3:
	return Vector3(0.0, _takeoff_top_y + 0.75, 11.0)


static func _vector(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2]))



# ---------------------------------------------------------------- 输入


func _unhandled_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code := MovementLabInput.key_code(key_event)
		# 移动键 / 升降键由 helper 记按住状态；本场景决定语义边沿。
		if _input.track_key(key_event, MovementLabInput.VERTICAL_KEYS):
			if MovementLabInput.is_key_down_edge(key_event):
				if code == MovementLabInput.KEY_VERTICAL_UP:
					_player.press_jump()
			viewport.set_input_as_handled()
			return
		if MovementLabInput.is_key_down_edge(key_event):
			match code:
				KEY_F:
					# echo 不算新边沿：按住 F 只切换一次。
					_player.press_flight_toggle()
				KEY_R:
					_reset_experiment()
				KEY_Z:
					_camera.size = clampf(_camera.size - CAMERA_ZOOM_STEP, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
				KEY_X:
					_camera.size = clampf(_camera.size + CAMERA_ZOOM_STEP, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
				_:
					if event.is_action_pressed("ui_cancel"):
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
			_camera.size = clampf(_camera.size - CAMERA_ZOOM_STEP, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
			viewport.set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + CAMERA_ZOOM_STEP, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
			viewport.set_input_as_handled()


## 场景先写输入、actor 子节点随后 tick（父节点 _physics_process 先于子节点）。
func _physics_process(delta: float) -> void:
	if _player == null or _motion == null:
		return
	var right := _ground(_camera.global_transform.basis.x, Vector3.RIGHT)
	var forward := _ground(-_camera.global_transform.basis.z, Vector3.FORWARD)
	_player.set_camera_ground_basis(right, forward)
	var move := _input.move_input()
	_player.set_move_input(move)
	_player.set_vertical_input(_input.vertical_input())
	if move != Vector2.ZERO:
		var direction := right * move.x - forward * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())
	_check_fall_out()
	_update_route(delta)
	_follow_camera(delta)


func _process(_delta: float) -> void:
	_update_hud()


static func _ground(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


func _follow_camera(delta: float) -> void:
	var target := _player.global_position
	target.x = clampf(target.x, _bounds_min.x, _bounds_max.x)
	target.y = clampf(target.y, _bounds_min.y, _bounds_max.y)
	target.z = clampf(target.z, _bounds_min.z, _bounds_max.z)
	_follow_target = _follow_target.lerp(target, clampf(delta * CAMERA_FOLLOW_SPEED, 0.0, 1.0))
	_camera.position = _follow_target + CAMERA_OFFSET
	_camera.look_at(_follow_target, Vector3.UP)


func _clear_pressed() -> void:
	_input.clear()
	if _player != null:
		_player.clear_input()


## 掉出回收：关飞后若飞出航路而没有可落脚的台面，角色会一直下坠。
## 低于 FALL_OUT_Y 即回收：复用既有公开清账路径（clear_input / reset_motion /
## 回起飞坪 / 复位朝向 / 路线状态归零），不写组件或能力内部状态。
## 御剑状态与 sword_flight_block 由 reset_motion + SwordFlight 的失活路径清账。
func _check_fall_out() -> void:
	if _player == null:
		return
	var altitude := _player.global_position.y
	if altitude >= FALL_OUT_Y:
		return
	_fall_out_count += 1
	push_warning("sword_flight_course: 角色掉出航路（y=%.2f < %.2f），回收至起飞坪（第 %d 次）" % [
		altitude, FALL_OUT_Y, _fall_out_count])
	_reset_experiment()


func _reset_experiment() -> void:
	_clear_pressed()
	_player.global_position = _spawn_position()
	_player.reset_motion()
	_player.set_aim_direction(Vector3.FORWARD)
	_reset_count += 1
	_phase = "takeoff"
	_gate_index = 0
	_hover_accumulated = 0.0
	_hover_done = false
	_landing_result = ""
	_landing_checked = false
	_trail.clear()
	_previous_position = _player.global_position
	_follow_target = _player.global_position
	_camera.size = CAMERA_SIZE
	_camera.position = _follow_target + CAMERA_OFFSET
	_camera.look_at(_follow_target, Vector3.UP)


func _return_to_hub() -> void:
	_clear_pressed()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	if result != OK:
		push_error("sword_flight_course: 返回移动子实验目录失败，错误码 %d" % result)



# ---------------------------------------------------------------- 路线判定
# 全部判据来自角色真实轨迹与真实 on_floor / flight_active，不由按钮或时间直接标记成功。
# 穿门：读取上一帧到当前帧的位移线段；线段跨过环平面、且跨点落在环口内才算穿越。
# 未御剑时不算空中门（地面步行穿过环口不记进度）。


func _update_route(delta: float) -> void:
	var position := _player.global_position
	_trail.append(position)
	if _trail.size() > 600:
		_trail.pop_front()
	if _landing_checked:
		_previous_position = position
		return
	if _phase == "takeoff":
		# 离开起飞坪并真实进入御剑，才算起飞成功。
		if _motion.flight_active and not _motion.on_floor:
			_phase = "gates"
	elif _phase == "gates":
		_update_gate_progress(position)
		_update_hover(delta, position)
		# 落点判定与门序 / 悬停相互独立：起飞后的任何真实落地都记录落点。
		_check_landing(position)
	elif _phase == "landing":
		_check_landing(position)
	_previous_position = position


## 逐门推进：必须按门序，且必须处于御剑状态才算空中门。
func _update_gate_progress(position: Vector3) -> void:
	if _gate_index >= _gates.size():
		if not _hover_done:
			return
		_phase = "landing"
		return
	var gate: Dictionary = _gates[_gate_index]
	if not _motion.flight_active:
		return
	var center := _vector(gate["center"])
	var yaw := deg_to_rad(float(gate["yaw"]))
	var axis := Vector3(sin(yaw), 0.0, -cos(yaw))
	var radius := float(gate["radius"])
	if _segment_crosses_gate(_previous_body_center(), _body_center(), center, axis, radius):
		_gate_index += 1
		if _gate_index >= _gates.size() and _hover_done:
			_phase = "landing"


## 位移线段是否在同一帧内跨过环平面，且跨点在环口半径 − 余量以内。
func _segment_crosses_gate(from: Vector3, to: Vector3, center: Vector3,
		axis: Vector3, radius: float) -> bool:
	var from_axial := (from - center).dot(axis)
	var to_axial := (to - center).dot(axis)
	if from_axial == to_axial:
		return false
	# 必须真的从一侧穿到另一侧（同侧移动不算）。
	if signf(from_axial) == signf(to_axial):
		return false
	# 跨点是否落在环口内：按两侧轴向距离插值出跨点。
	if absf(from_axial) <= GATE_AXIAL_TOLERANCE or absf(to_axial) <= GATE_AXIAL_TOLERANCE:
		var t := absf(from_axial) / (absf(from_axial) + absf(to_axial))
		var crossing := from.lerp(to, t)
		# 径向距离要剔除轴向残差：跨点近似在环平面内，但插值仍有分量。
		var offset := crossing - center
		var radial := offset - axis * offset.dot(axis)
		return radial.length() <= radius - GATE_RADIAL_MARGIN
	return false


## 悬停计时：在悬停区内、御剑中、竖直速度接近 0 时累计；离开或非悬停则清零。
func _update_hover(delta: float, position: Vector3) -> void:
	if _hover_done or _phase != "gates":
		return
	if _gate_index < _gates.size():
		return
	var center := _vector(_hover["center"])
	var radius := float(_hover["radius"])
	var body := _body_center()
	var horizontal := Vector2(body.x - center.x, body.z - center.z).length()
	var vertical := absf(body.y - center.y)
	var hovering := horizontal <= radius and vertical <= radius
	# 悬停必须真的御剑且竖直速度接近 0（按升降键不算悬停）。
	# 判据唯一来源：HOVER_TICK_TOLERANCE。
	var steady := _motion.flight_active and absf(_motion.actual_velocity.y) <= HOVER_TICK_TOLERANCE
	if hovering and steady:
		_hover_accumulated += delta
		if _hover_accumulated >= float(_hover["seconds"]):
			_hover_done = true
			_phase = "landing"
	else:
		_hover_accumulated = 0.0


## 落点判定：真实 on_floor 且落在某个落点台面范围内；两个落点取先满足者。
func _check_landing(position: Vector3) -> void:
	if not _motion.on_floor:
		return
	for landing in _landings:
		var center := _vector(landing["center"])
		var radius := float(landing["radius"])
		var horizontal := Vector2(position.x - center.x, position.z - center.z).length()
		var on_top := absf(position.y - float(landing["top_y"])) <= 1.2
		if horizontal <= radius + LANDING_RADIUS_MARGIN and on_top:
			_landing_result = str(landing["id"])
			_landing_checked = true
			return


# ---------------------------------------------------------------- HUD


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
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _backdrop())
	header.add_child(panel)

	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(titles)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.theme_type_variation = "AccentLabel"
	kicker.add_theme_font_size_override("font_size", 13)
	kicker.text = "EXPERIMENT    /    CHARACTER MOVEMENT · SWORD FLIGHT"
	titles.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 28)
	title.text = "角色移动 · 御剑飞行训练场"
	titles.add_child(title)

	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override("font_size", 18)
	titles.add_child(_phase_label)

	_gates_label = Label.new()
	_gates_label.name = "GatesLabel"
	_gates_label.theme_type_variation = "MutedLabel"
	_gates_label.add_theme_font_size_override("font_size", 14)
	titles.add_child(_gates_label)

	_flight_label = Label.new()
	_flight_label.name = "FlightLabel"
	_flight_label.theme_type_variation = "MutedLabel"
	_flight_label.add_theme_font_size_override("font_size", 14)
	titles.add_child(_flight_label)

	_landing_label = Label.new()
	_landing_label.name = "LandingLabel"
	_landing_label.theme_type_variation = "MutedLabel"
	_landing_label.add_theme_font_size_override("font_size", 14)
	titles.add_child(_landing_label)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = "MutedLabel"
	_status.add_theme_font_size_override("font_size", 13)
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
	controls_panel.add_theme_stylebox_override("panel", _backdrop())
	footer.add_child(controls_panel)

	var controls := Label.new()
	controls.name = "Controls"
	controls.theme_type_variation = "MutedLabel"
	controls.add_theme_font_size_override("font_size", 14)
	controls.text = "WASD / 方向键 飞行  ·  Space / Ctrl 升降  ·  F 御剑  ·  滚轮或 Z / X 缩放  ·  R 重置  ·  Esc 返回"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_panel.add_child(controls)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.custom_minimum_size = Vector2(96, 44)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_experiment)
	footer.add_child(reset_button)


func _backdrop() -> StyleBoxFlat:
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


## HUD 只读回读：航段、真实高度 / 竖直速度 / flight_active、门序、悬停计时、落点结果。
func _update_hud() -> void:
	if _phase_label == null or _player == null or _motion == null:
		return
	var position := _player.global_position
	_phase_label.text = "当前航段：%s" % _phase_title()
	_gates_label.text = "门序进度：%d / %d%s" % [
		_gate_index, _gates.size(),
		"（已穿完）" if _gate_index >= _gates.size() else "",
	]
	_flight_label.text = "高度 %.2f m  ·  竖直速度 %+.2f m/s  ·  御剑 %s  ·  着地 %s  ·  水平速度 %.2f" % [
		position.y, _motion.actual_velocity.y,
		"是" if _motion.flight_active else "否",
		"是" if _motion.on_floor else "否",
		Vector2(_motion.actual_velocity.x, _motion.actual_velocity.z).length(),
	]
	var hover_text := "未开始"
	if _hover_done:
		hover_text = "已完成"
	elif _gate_index >= _gates.size():
		hover_text = "%.2f / %.2f s" % [_hover_accumulated, float(_hover["seconds"])]
	_landing_label.text = "悬停计时 %s  ·  落点 %s  ·  重置 %d 次  ·  掉出回收 %d 次（低于 %.0f m）" % [
		hover_text,
		"未落地" if _landing_result.is_empty() else "已落 %s" % _landing_title(_landing_result),
		_reset_count,
		_fall_out_count,
		FALL_OUT_Y,
	]
	_status.text = "起飞坪起飞 → 按序穿 5 道玉环门 → 悬停计时 → 选择近 / 远落点"


func _phase_title() -> String:
	match _phase:
		"takeoff":
			return "起飞（需真实御剑离地）"
		"gates":
			if _gate_index >= _gates.size():
				return "悬停计时区"
			return "穿门 %d / %d" % [_gate_index + 1, _gates.size()]
		"landing":
			return "选择落点"
	return _phase


func _landing_title(id: String) -> String:
	for landing in _landings:
		if str(landing["id"]) == id:
			return str(landing["title"])
	return id


# ---------------------------------------------------------------- 只读回读


## 路线状态只读快照：供 HUD 与验收脚本读取，不暴露写入口。
func route_state() -> Dictionary:
	return {
		"phase": _phase,
		"gate_index": _gate_index,
		"gate_total": _gates.size(),
		"hover_accumulated": _hover_accumulated,
		"hover_done": _hover_done,
		"landing_result": _landing_result,
		"landing_checked": _landing_checked,
		"reset_count": _reset_count,
		"fall_out_count": _fall_out_count,
		"fall_out_y": FALL_OUT_Y,
		"trail_points": _trail.size(),
		"gates": _gates,
		"landings": _landings,
		"hover": _hover,
	}


## 当前身体中心（脚底原点 + 胶囊中心偏移）。
func _body_center() -> Vector3:
	return _player.global_position + Vector3(0.0, BODY_CENTER_OFFSET, 0.0)


## 上一帧身体中心（穿门线段起点）。
func _previous_body_center() -> Vector3:
	return _previous_position + Vector3(0.0, BODY_CENTER_OFFSET, 0.0)


## 只读：胶囊中心相对脚底原点的偏移，供验收脚本换算瞄准点。
func body_center_offset() -> float:
	return BODY_CENTER_OFFSET


func actor() -> Swordsman:
	return _player


func motion() -> SwordsmanMotionComponent:
	return _motion


func camera() -> Camera3D:
	return _camera

