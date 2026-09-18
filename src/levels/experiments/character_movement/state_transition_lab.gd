extends Node3D

## 状态切换压力场（心境 / 身法试炼阵）：回答「能力切换、失焦、重置、碰撞与边缘时机是否正确清账」。
##
## 职责边界（依据 notes/proposed/gameplay/2026-09-18-character-movement-subexperiments.md）：
## - 只有三项既有 Capability；本场景不新增能力、不实现战斗、不实现通用状态机。
## - 场景只调用角色公开输入 API（set_move_input / set_vertical_input / press_jump /
##   press_flight_toggle / clear_input / set_camera_ground_basis / set_aim_direction /
##   reset_motion / bind_flight_visual）。绝不写 Component / Capability / velocity / TagRegistry。
## - 唯一 move_and_slide() 在 Swordsman 根节点；本场景不提交物理、不 tick 能力管理器。
## - 账本只记录本场景**实际观察到**的读数（组件公共字段只读 + TagRegistry.block_count 只读），
##   不把推测显示成事实；不向任何能力注入测试钩子。
## - 返回：Esc 与「返回子实验目录」按钮都回 movement_lab_hub.tscn；R 重置。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const TRIAL_SCENE: PackedScene = preload("res://levels/experiments/character_movement/state_transition_lab.glb")
const FLYING_SWORD_SCENE: PackedScene = preload("res://game/abilities/sword_flight/models/flying_sword.glb")
const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")
const Ledger := preload("res://levels/experiments/character_movement/state_transition_lab_ledger.gd")
const InputHelper := preload("res://levels/experiments/character_movement/movement_lab_input.gd")

## 世界碰撞统一层（与群山/庭院同一约定，不引入额外碰撞层）。
const COLLISION_LAYER := 1

## 阵盘几何（与 tools/art/generate_state_transition_lab.py 的导出契约一致）：
## 玉盘半径 9 m、顶面 y = 0；石门北墙内面 z = WALL_Z；断桥沿 +X、缺口 x ∈ [GAP_MIN_X, GAP_MAX_X]。
## 下列常量是唯一真源：碰撞段的位置与长度都由它们推导，不再手写第二份数值；
## GLB 的断桥残端（Blender 脚本中 x=9.35 与 11.75）正好落在缺口两侧，两侧对得上。
const DISC_RADIUS := 9.0
const WALL_Z := -5.5
## 主石门墙宽度：墙段自门洞边缘向外延伸，门洞留 x ∈ [-1.5, 1.5]。
const GATE_OPENING_HALF_X := 1.5
const WALL_HALF_X := 5.0
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 1.1
const BRIDGE_Z_HALF := 1.3
const BRIDGE_Y := -0.44
## 断桥缺口：取两段桥面**内侧边缘**（与 GLB 的 Bridge near/far span 逐值对齐），
## 碰撞段由缺口 + 各自跨度推导，改缺口或跨度只改这里，不再手写第二份数值。
const GAP_MIN_X := 9.1
const GAP_MAX_X := 11.5
const BRIDGE_NEAR_SPAN := 3.0
const BRIDGE_FAR_SPAN := 3.2
const SPAWN := Vector3(0.0, 0.05, 2.6)

const CAMERA_OFFSET := Vector3(13.0, 16.0, 13.5)
const CAMERA_SIZE := 27.0
const CAMERA_FAR := 300.0
const CAMERA_FOLLOW_SPEED := 4.0

## 掉出回收（阵盘之外的虚空）：由场景承担，不依赖角色能力。
const FALL_OUT_Y := -8.0

var _actor: Swordsman
var _motion: SwordsmanMotionComponent
var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _input_helper: MovementLabInput
var _ledger: StateTransitionLedger
var _follow_target := Vector3.ZERO
var _relative_frame := 0
var _fall_out_count := 0
var _reset_count := 0
## 本帧待观察的输入边沿：在 deferred 阶段读取 actor tick 后的真实状态再入账。
var _pending_jump := false
var _pending_flight := false

var _ledger_view: RichTextLabel
var _timeline: Control
var _hud_input: Label
var _hud_state: Label
var _hud_ledger: Label


func _ready() -> void:
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	assert(ResourceLoader.exists(HUB_SCENE), "state_transition_lab: 缺少返回目录 %s" % HUB_SCENE)
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "state_transition_lab: 场景必须提供 Camera3D")
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.near = 0.1
	_camera.far = CAMERA_FAR
	_input_helper = InputHelper.new()
	_ledger = Ledger.new()
	_build_trial_visual()
	_build_collision()
	_spawn_actor()
	_build_hud()
	_reset_experiment("场景就绪")
	_ledger.record(0, "prepare", "场景装配完成", _snapshot(), "三能力 + 唯一提交点")


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	# 失焦：清场景输入缓存并调用公开 clear_input()；已开启的御剑按既有契约保留悬停。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_apply_focus_out()


# --- 输入（真实键 → 公开 API 的唯一映射点）-----------------------------------


func _unhandled_input(event: InputEvent) -> void:
	# 场景切换（Esc 返回目录）后仍可能有排队事件抵达已离树的节点：没有视口就不处理。
	var viewport := get_viewport()
	if viewport == null:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code := InputHelper.key_code(key_event)
		if _input_helper.track_key(key_event, InputHelper.VERTICAL_KEYS):
			# 空格既是升降输入也是跳跃边沿：按住状态进 helper，起跳语义仍由本场景调用公开 API。
			if code == InputHelper.KEY_VERTICAL_UP and InputHelper.is_key_down_edge(key_event) and _actor != null:
				_actor.press_jump()
				_pending_jump = true
			viewport.set_input_as_handled()
			return
		if InputHelper.is_key_down_edge(key_event):
			match code:
				KEY_F:
					if _actor != null:
						_actor.press_flight_toggle()
						_pending_flight = true
					viewport.set_input_as_handled()
				KEY_R:
					viewport.set_input_as_handled()
					_reset_experiment("R 键")
				_:
					if event.is_action_pressed("ui_cancel"):
						# 切场景会立即把本节点移出树：先标记已处理，再执行返回，避免用到失效视口。
						viewport.set_input_as_handled()
						_return_to_hub()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed or _camera == null:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = clampf(_camera.size - 2.0, 12.0, 60.0)
			viewport.set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + 2.0, 12.0, 60.0)
			viewport.set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _actor == null or _motion == null:
		return
	_relative_frame += 1
	# 场景先写输入、actor 子节点随后 tick（父节点先于子节点）。
	_actor.set_move_input(_input_helper.move_input())
	_actor.set_vertical_input(_input_helper.vertical_input())
	var right := _ground_vector(_camera.global_transform.basis.x, Vector3.RIGHT)
	var forward := _ground_vector(-_camera.global_transform.basis.z, Vector3.FORWARD)
	_actor.set_camera_ground_basis(right, forward)
	var move := _input_helper.move_input()
	if move != Vector2.ZERO:
		var direction := right * move.x - forward * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_actor.set_aim_direction(direction.normalized())
	_check_fall_out()
	_follow_camera(delta)
	# 边沿事件延迟到本帧 actor tick 之后记录：那时读到的能力激活态与阻塞计数才是同帧事实。
	if _pending_jump or _pending_flight:
		call_deferred("_flush_observed_edges")
	_ledger.observe(_relative_frame, _snapshot())
	_timeline.queue_redraw()


## 记录本帧被 actor 消费掉的输入边沿（在 deferred 阶段读取 tick 后的真实状态）。
func _flush_observed_edges() -> void:
	if _pending_jump:
		_pending_jump = false
		_ledger.record(_relative_frame, "jump_edge", "Space 边沿", _snapshot(), "actor 已消费边沿")
	if _pending_flight:
		_pending_flight = false
		_ledger.record(_relative_frame, "flight_edge", "F 边沿", _snapshot(), "actor 已消费边沿")


func _process(_delta: float) -> void:
	_update_hud()


func _apply_focus_out() -> void:
	_input_helper.clear()
	if _actor != null:
		# 公开 API：只清四种输入，不改变飞行状态（御剑保留悬停）。
		_actor.clear_input()
	_ledger.record(_relative_frame, "focus_out", "窗口失焦",
		_snapshot(), "公开 clear_input()")


func _check_fall_out() -> void:
	if _actor.global_position.y < FALL_OUT_Y:
		_fall_out_count += 1
		_ledger.record(_relative_frame, "fall_out",
			"越出下沿 y=%.2f" % _actor.global_position.y, _snapshot(), "回收至起点")
		_reset_experiment("掉出回收")


func _reset_experiment(reason: String) -> void:
	_reset_count += 1
	_input_helper.clear()
	# 公开 API：reset_motion() 清输入、边沿、速度、意图与 flight_active；
	# 御剑阻塞由 SwordFlight 下一 physics tick 的失活路径清账（契约已记录）。
	_actor.reset_motion()
	_actor.global_position = SPAWN
	_actor.set_aim_direction(Vector3.FORWARD)
	_follow_target = SPAWN
	_camera.position = _follow_target + CAMERA_OFFSET
	_camera.look_at(_follow_target, Vector3.UP)
	_ledger.record(_relative_frame, "reset", "重置（%s）" % reason, _snapshot(),
		"reset_motion() + 回起点")


func _return_to_hub() -> void:
	_input_helper.clear()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	assert(result == OK, "state_transition_lab: 返回子实验目录失败（%s，错误码 %d）" % [HUB_SCENE, result])


# --- 只读快照（账本唯一数据来源）---------------------------------------------


## 快照全部来自公开只读面：组件公共字段 + TagRegistry.block_count。
## 能力激活态按节点名读取（与既有回归一致的诊断读法，无类引用）；缺失时记 -1，不猜测。
func _snapshot() -> Dictionary:
	if _actor == null or _motion == null:
		return {}
	var manager := _actor.capability_manager()
	return {
		"pos": _actor.global_position,
		"on_floor": _motion.on_floor,
		"flight": _motion.flight_active,
		"block": TagRegistry.block_count(_actor, LEDGER_TAG),
		"velocity": _motion.actual_velocity,
		"move_input": _motion.move_input,
		"vertical_input": _motion.vertical_input,
		"jump_edge": _motion.jump_pressed,
		"flight_edge": _motion.flight_toggle_pressed,
		"jump_active": _node_active(manager, "Jump"),
		"move_active": _node_active(manager, "SwordsmanMovement"),
		"flight_cap_active": _node_active(manager, "SwordFlight"),
	}


const LEDGER_TAG := &"sword_flight_block"


func _node_active(manager: CapabilityManager, node_name: String) -> int:
	if manager == null:
		return -1
	var node := manager.get_node_or_null(node_name)
	if node == null:
		return -1
	return 1 if (node as Capability).active else 0


# --- 装配（碰撞与装饰分离：GLB 只做视觉，物理由本场景精确装配）----------------


func _build_trial_visual() -> void:
	var visual := TRIAL_SCENE.instantiate() as Node3D
	assert(visual != null, "state_transition_lab: state_transition_lab.glb 根节点必须是 Node3D")
	visual.name = "TrialFormation"
	add_child(visual)


## 碰撞按设计契约本地精确装配：不用 GLB 网格生成 trimesh，保证数值可控可测。
## 断桥缺口必须真的留空：两段碰撞的内侧边缘由 GAP_* 推导，若被手改会在这里立刻失败。
func _build_collision() -> void:
	assert(is_equal_approx(GAP_MIN_X - BRIDGE_NEAR_SPAN, 6.1),
		"state_transition_lab: 断桥近段外侧边缘必须对齐 GLB（6.1），实际 %.2f" % (GAP_MIN_X - BRIDGE_NEAR_SPAN))
	assert(is_equal_approx(GAP_MAX_X + BRIDGE_FAR_SPAN, 14.7),
		"state_transition_lab: 断桥远段外侧边缘必须对齐 GLB（14.7），实际 %.2f" % (GAP_MAX_X + BRIDGE_FAR_SPAN))
	var world := Node3D.new()
	world.name = "TrialCollision"
	add_child(world)
	# 主阵盘：实体圆盘，顶面 y = 0（角色站立面）。
	_make_block(world, "DiscFloor", Vector3(0.0, -0.25, 0.0), Vector3(DISC_RADIUS * 2.0, 0.5, DISC_RADIUS * 2.0))
	# 石门北墙（z = WALL_Z）：门洞 x ∈ [-GATE_OPENING_HALF_X, +GATE_OPENING_HALF_X]，两侧墙段按 WALL_HALF_X 推导。
	var wall_span := WALL_HALF_X - GATE_OPENING_HALF_X
	var wall_center_x := GATE_OPENING_HALF_X + wall_span * 0.5
	_make_block(world, "GateWallWest", Vector3(-wall_center_x, WALL_HEIGHT * 0.5, WALL_Z),
		Vector3(wall_span, WALL_HEIGHT, WALL_THICKNESS))
	_make_block(world, "GateWallEast", Vector3(wall_center_x, WALL_HEIGHT * 0.5, WALL_Z),
		Vector3(wall_span, WALL_HEIGHT, WALL_THICKNESS))
	# 断桥两段：近段以 GAP_MIN_X 为内侧端点，远段以 GAP_MAX_X 为内侧端点，跨度各自匹配 GLB。
	_make_block(world, "BridgeNear", Vector3(GAP_MIN_X - BRIDGE_NEAR_SPAN * 0.5, BRIDGE_Y * 0.5, 0.0),
		Vector3(BRIDGE_NEAR_SPAN, 0.44, BRIDGE_Z_HALF * 2.0))
	_make_block(world, "BridgeFar", Vector3(GAP_MAX_X + BRIDGE_FAR_SPAN * 0.5, BRIDGE_Y * 0.5, 0.0),
		Vector3(BRIDGE_FAR_SPAN, 0.44, BRIDGE_Z_HALF * 2.0))
	# 边缘低台（供「边缘离地」用例）：2×2 m、高 0.5 m，西南侧。
	_make_block(world, "EdgeLedge", Vector3(-6.0, 0.25, 5.0), Vector3(2.0, 0.5, 2.0))


func _make_block(parent: Node, block_name: String, block_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = block_position
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = COLLISION_LAYER
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	return body


func _spawn_actor() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "state_transition_lab: swordsman.tscn 根节点必须是 Swordsman")
	actor.name = "Swordsman"
	add_child(actor)
	_actor = actor
	_motion = actor.motion()
	assert(_motion != null, "state_transition_lab: 角色缺少 SwordsmanMotionComponent")
	assert(actor.capability_manager() != null, "state_transition_lab: 角色缺少唯一 CapabilityManager")
	actor.reset_motion()
	actor.global_position = SPAWN
	actor.set_aim_direction(Vector3.FORWARD)
	_bind_flight_visual(actor)


## 御剑视觉由场景绑定：作为角色 Visual 子节点，可见性由 actor 按 flight_active 同步。
func _bind_flight_visual(actor: Swordsman) -> void:
	var sword := FLYING_SWORD_SCENE.instantiate() as Node3D
	assert(sword != null, "state_transition_lab: 御剑视觉根节点必须是 Node3D")
	sword.name = "FlyingSword"
	var visual := actor.get_node_or_null("Visual") as Node3D
	assert(visual != null, "state_transition_lab: 角色缺少 Visual 节点")
	visual.add_child(sword)
	actor.bind_flight_visual(sword)


func _ground_vector(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


func _follow_camera(delta: float) -> void:
	var target := _actor.global_position
	target.x = clampf(target.x, -DISC_RADIUS + 3.0, DISC_RADIUS + 6.0)
	target.z = clampf(target.z, -DISC_RADIUS + 3.0, DISC_RADIUS - 3.0)
	target.y = clampf(target.y, 0.0, 12.0)
	_follow_target = _follow_target.lerp(target, clampf(delta * CAMERA_FOLLOW_SPEED, 0.0, 1.0))
	_camera.position = _follow_target + CAMERA_OFFSET
	_camera.look_at(_follow_target, Vector3.UP)


# --- HUD：账本 + 时间线 + 状态读数 -------------------------------------------


## HUD 用锚点定位的固定面板，而不是会互相拉伸的容器：
## 场景中心留空（看得见阵盘与角色），账本固定在左下、时间线固定在右上。
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

	# 左上：标题与三能力状态、输入读数、账本摘要、按键提示。
	var header_panel := PanelContainer.new()
	header_panel.name = "HeaderPanel"
	header_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_panel.anchor_left = 0.0
	header_panel.anchor_top = 0.0
	header_panel.anchor_right = 0.0
	header_panel.anchor_bottom = 0.0
	header_panel.offset_left = 18.0
	header_panel.offset_top = 16.0
	header_panel.offset_right = 470.0
	header_panel.offset_bottom = 16.0
	header_panel.grow_vertical = Control.GROW_DIRECTION_END
	interface.add_child(header_panel)

	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_theme_constant_override("separation", 5)
	header_panel.add_child(titles)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.theme_type_variation = "AccentLabel"
	kicker.add_theme_font_size_override("font_size", 12)
	kicker.text = "EXPERIMENT    /    CHARACTER MOVEMENT · STATE TRANSITION"
	kicker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 24)
	title.text = "状态切换压力场"
	titles.add_child(title)

	_hud_state = Label.new()
	_hud_state.name = "StateReadout"
	_hud_state.add_theme_font_size_override("font_size", 14)
	_hud_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_hud_state)

	_hud_input = Label.new()
	_hud_input.name = "InputReadout"
	_hud_input.theme_type_variation = "MutedLabel"
	_hud_input.add_theme_font_size_override("font_size", 13)
	_hud_input.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_hud_input)

	_hud_ledger = Label.new()
	_hud_ledger.name = "LedgerSummary"
	_hud_ledger.add_theme_font_size_override("font_size", 13)
	_hud_ledger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_hud_ledger)

	var hint := Label.new()
	hint.name = "Controls"
	hint.theme_type_variation = "MutedLabel"
	hint.add_theme_font_size_override("font_size", 12)
	hint.text = "WASD / 方向键 移动  ·  Space 跳跃 / 上升  ·  Ctrl 下降  ·  F 御剑  ·  滚轮缩放  ·  R 重置  ·  Esc 返回子实验目录"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(hint)

	# 右上：返回按钮与时间线。
	var right := VBoxContainer.new()
	right.name = "Right"
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.anchor_left = 1.0
	right.anchor_top = 0.0
	right.anchor_right = 1.0
	right.anchor_bottom = 0.0
	right.offset_left = -560.0
	right.offset_top = 16.0
	right.offset_right = -18.0
	right.offset_bottom = 16.0
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.grow_vertical = Control.GROW_DIRECTION_END
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	right.add_theme_constant_override("separation", 8)
	interface.add_child(right)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	right.add_child(buttons)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.custom_minimum_size = Vector2(88, 40)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset_button)

	var return_button := Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回子实验目录"
	return_button.custom_minimum_size = Vector2(150, 40)
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.pressed.connect(_return_to_hub)
	buttons.add_child(return_button)

	var timeline_panel := PanelContainer.new()
	timeline_panel.name = "TimelinePanel"
	timeline_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline_panel.custom_minimum_size = Vector2(0, 150)
	right.add_child(timeline_panel)

	_timeline = LedgerTimeline.new()
	_timeline.name = "Timeline"
	_timeline.ledger = _ledger
	_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline_panel.add_child(_timeline)

	# 左下：事件账本（固定尺寸，内部滚动；不遮住场景中心）。
	var ledger_panel := PanelContainer.new()
	ledger_panel.name = "LedgerPanel"
	ledger_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ledger_panel.anchor_left = 0.0
	ledger_panel.anchor_top = 1.0
	ledger_panel.anchor_right = 0.0
	ledger_panel.anchor_bottom = 1.0
	ledger_panel.offset_left = 18.0
	ledger_panel.offset_top = -246.0
	ledger_panel.offset_right = 18.0 + 470.0
	ledger_panel.offset_bottom = -16.0
	ledger_panel.grow_horizontal = Control.GROW_DIRECTION_END
	ledger_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	interface.add_child(ledger_panel)

	var ledger_margin := MarginContainer.new()
	ledger_margin.name = "LedgerMargin"
	ledger_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ledger_margin.add_theme_constant_override("margin_left", 10)
	ledger_margin.add_theme_constant_override("margin_right", 10)
	ledger_margin.add_theme_constant_override("margin_top", 8)
	ledger_margin.add_theme_constant_override("margin_bottom", 8)
	ledger_panel.add_child(ledger_margin)

	_ledger_view = RichTextLabel.new()
	_ledger_view.name = "Ledger"
	_ledger_view.bbcode_enabled = true
	_ledger_view.scroll_following = true
	_ledger_view.scroll_active = true
	_ledger_view.fit_content = false
	_ledger_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# RichTextLabel 不继承 Label 的字体色：显式指定墨色，避免白底白字。
	_ledger_view.add_theme_color_override("default_color", Color(0.145098, 0.239216, 0.211765, 1.0))
	_ledger_view.add_theme_font_size_override("normal_font_size", 12)
	_ledger_view.add_theme_font_size_override("bold_font_size", 12)
	ledger_margin.add_child(_ledger_view)


## 公开只读访问器：验收脚本经此读取账本与输入状态，不再触碰私有字段。
## 只返回对象引用 / 快照副本，不暴露可变内部集合。
func ledger() -> StateTransitionLedger:
	return _ledger


## 当前「按住键数」快照：仅用于验证失焦 / 重置后输入确实清零。
func input_held_count() -> int:
	return _input_helper.held_count()


## 输入状态只读快照（值拷贝，测试可断言但不持有内部结构）。
func input_state() -> Dictionary:
	return {
		"move_input": _input_helper.move_input(),
		"vertical_input": _input_helper.vertical_input(),
		"held_count": _input_helper.held_count(),
	}


func _on_reset_pressed() -> void:
	_reset_experiment("按钮")


## HUD 每秒重算一次读数；账本只在内容变化时重建文本（脏标记，不逐帧格式化）。
func _update_hud() -> void:
	if _hud_state == null or _motion == null:
		return
	var snapshot := _snapshot()
	if snapshot.is_empty():
		return
	_hud_state.text = "状态  着地=%s  御剑=%s  高度=%.2f m  block=%d  相对帧=%d" % [
		"是" if snapshot["on_floor"] else "否",
		"是" if snapshot["flight"] else "否",
		(_actor.global_position.y),
		snapshot["block"],
		_relative_frame,
	]
	_hud_input.text = "输入  move=(%+.2f, %+.2f)  升降=%+.0f  起跳边沿=%d  御剑边沿=%d  按住键数=%d" % [
		_motion.move_input.x, _motion.move_input.y, _motion.vertical_input,
		1 if _motion.jump_pressed else 0, 1 if _motion.flight_toggle_pressed else 0,
		_input_helper.held_count(),
	]
	_hud_ledger.text = "账本  事件 %d 条  ·  %s  ·  重置 %d 次  ·  回收 %d 次" % [
		_ledger.event_count(), _ledger.summary_text(), _reset_count, _fall_out_count,
	]
	_ledger_view.text = _ledger.ledger_text()


## 时间线自绘：状态色带 + block/能力 lane + 事件标记 + 播放头。
class LedgerTimeline extends Control:
	var ledger: RefCounted

	func _draw() -> void:
		if ledger == null:
			return
		var size := get_rect().size
		var pad := 8.0
		var band := 14.0
		var lane_h := 12.0
		var width := size.x - pad * 2.0
		var events: Array = ledger.events()
		if events.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(pad, pad + 12.0), "时间线：等待事件",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.40, 0.36))
			return
		var last_frame := maxi(1, int(ledger.last_frame()))
		var first_frame := int((events[0] as Dictionary).get("frame", 0))
		var span := maxi(1, last_frame - first_frame)
		var state_color := Color(0.75, 0.80, 0.74)
		# 状态色带：按事件间的实际读数绘制（着地 / 空中 / 御剑）。
		var band_y := pad
		for index in range(events.size()):
			var event: Dictionary = events[index]
			var next_frame := last_frame if index + 1 >= events.size() else int((events[index + 1] as Dictionary)["frame"])
			var x0 := pad + width * float(int(event["frame"]) - first_frame) / float(span + 1)
			var x1 := pad + width * float(next_frame - first_frame + 1) / float(span + 1)
			var state := str(event.get("flight", "?"))
			if state == "true":
				state_color = Color(0.24, 0.55, 0.45)
			elif state == "false" and str(event.get("on_floor", "")) == "true":
				state_color = Color(0.72, 0.76, 0.66)
			else:
				state_color = Color(0.55, 0.62, 0.66)
			draw_rect(Rect2(Vector2(x0, band_y), Vector2(maxf(1.0, x1 - x0), band)), state_color)
		# block lane。
		var lane_y := band_y + band + 6.0
		draw_line(Vector2(pad, lane_y), Vector2(pad + width, lane_y), Color(0.62, 0.66, 0.60), 1.0)
		var blocked := false
		for index in range(events.size()):
			var event: Dictionary = events[index]
			var next_frame := last_frame if index + 1 >= events.size() else int((events[index + 1] as Dictionary)["frame"])
			var is_blocked := str(event.get("block", "0")) != "0"
			if is_blocked != blocked:
				blocked = is_blocked
			if not is_blocked:
				continue
			var x0 := pad + width * float(int(event["frame"]) - first_frame) / float(span + 1)
			var x1 := pad + width * float(next_frame - first_frame + 1) / float(span + 1)
			draw_rect(Rect2(Vector2(x0, lane_y - lane_h * 0.5), Vector2(maxf(2.0, x1 - x0), lane_h)),
				Color(0.55, 0.34, 0.24))
		# 能力 lane（诊断读数；缺失画灰）。
		var cap_y := lane_y + lane_h + 10.0
		for pair in [["flight_cap", "SwordFlight"], ["jump_cap", "Jump"]]:
			var key := str(pair[0])
			for index in range(events.size()):
				var event: Dictionary = events[index]
				var value := int(event.get(key, -1))
				var x := pad + width * float(int(event["frame"]) - first_frame) / float(span + 1)
				var color := Color(0.45, 0.48, 0.44)
				if value == 1:
					color = Color(0.36, 0.66, 0.42)
				elif value == -1:
					color = Color(0.30, 0.30, 0.30)
				draw_rect(Rect2(Vector2(x, cap_y), Vector2(3.0, lane_h)), color)
			cap_y += lane_h + 4.0
		# 事件标记 + 播放头。
		var marker_y := cap_y + 6.0
		var marker_colors := {
			"jump_edge": Color(0.30, 0.55, 0.85), "flight_edge": Color(0.20, 0.70, 0.60),
			"hold": Color(0.60, 0.58, 0.40), "reset": Color(0.80, 0.45, 0.20),
			"focus_out": Color(0.70, 0.35, 0.55), "collision": Color(0.75, 0.30, 0.25),
			"fall_out": Color(0.85, 0.25, 0.20), "edge": Color(0.85, 0.65, 0.20),
		}
		for event in events:
			var tag := str((event as Dictionary).get("tag", ""))
			if not marker_colors.has(tag):
				continue
			var x := pad + width * float(int((event as Dictionary)["frame"]) - first_frame) / float(span + 1)
			draw_line(Vector2(x, marker_y), Vector2(x, marker_y + 10.0), marker_colors[tag], 1.5)
		var head_x := pad + width * float(_relative(int(ledger.last_frame()), first_frame, span))
		draw_line(Vector2(head_x, pad), Vector2(head_x, marker_y + 10.0), Color(0.15, 0.20, 0.17), 1.0)

	func _relative(value: int, first: int, span: int) -> int:
		return clampi(value - first, 0, span)
