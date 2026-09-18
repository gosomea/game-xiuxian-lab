extends Node3D

## 人物动作工作台（motion_stage）：用真实 Swordsman 与公开输入 API 观察动作表现。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md（子实验「人物动作工作台」）。
##
## 职责边界：
## - 角色、三能力与运动数据归 res://game/actors/swordsman/ 与 res://game/abilities/；
##   本场景只做输入编排、场地标记、固定观察视角与 HUD。
## - 只调用角色公开输入 API（set_move_input / set_vertical_input / press_jump /
##   press_flight_toggle / set_camera_ground_basis / set_aim_direction / reset_motion /
##   clear_input）；不写 velocity、不写意图、不碰任何 Capability 内部状态。
## - HUD 只读组件公共字段（actual_velocity / on_floor / flight_active / aim_direction）
##   与表现层只读快照 pose_state()；表现层不参与物理裁决。
## - 场地标记全部程序化生成（无新二进制资产）；跳跃标尺刻度由组件参数推导，不是硬编码文案。
## - Esc / 返回按钮固定回到移动子实验目录；该依赖在 _ready 断言，缺失时启动即失败而非静默改道。

## 移动子实验目录是本工作台的固定返回目标（同提交依赖）；
## 不做「存在才用、否则静默回退顶层目录」的兜底——那会掩盖装配缺陷。
const MOVEMENT_HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")
## 御剑视觉复用 sword_flight 叶子包既有资产；不新增、不覆盖任何资产。
## 只作为角色 Visual 子节点装配，可见性由 actor 按 flight_active 统一同步。
const FLYING_SWORD_SCENE: PackedScene = preload("res://game/abilities/sword_flight/models/flying_sword.glb")

## 世界碰撞统一层：地面 / 边界 / 角色同层，契约不引入额外碰撞层。
const COLLISION_LAYER := 1

## 舞台尺寸：x 向为长边（跑道方向），z 向为进深。
const STAGE_HALF_X := 18.5
const STAGE_HALF_Z := 8.5
const GROUND_THICKNESS := 0.6
const WALL_THICKNESS := 1.0
const WALL_HEIGHT := 8.0
## 高度上限：给御剑起降留 12 m 净空，同时兜住失控上升。
const CEILING_Y := 12.0

## 出生点：跑道西端视线内，初始朝 +X（沿跑道方向，侧面机位因此能读到跑动侧影）。
const SPAWN_POSITION := Vector3(-6.0, 0.05, 0.0)
const SPAWN_AIM := Vector3.RIGHT

## 直跑道：z ∈ [-RUNWAY_HALF_Z, RUNWAY_HALF_Z]，每 RUNWAY_STRIPE_STEP 米一条刻度线。
const RUNWAY_MIN_X := -16.0
const RUNWAY_MAX_X := 16.0
const RUNWAY_HALF_Z := 1.5
const RUNWAY_STRIPE_STEP := 2.0

## 八方向 / 急转区：圆心与半径。
const TURN_PAD_CENTER := Vector3(-11.5, 0.0, 5.0)
const TURN_PAD_RADIUS := 3.2

## 跳跃标尺：立柱位于跑道北侧边缘外，不参与碰撞（纯量具）。
const RULER_X := 9.0
const RULER_Z := -3.8
## 标尺刻度相对理论顶点的倍率；1.0 刻度即 jump_speed^2 / (2 * gravity)。
const RULER_BAND_FACTORS: Array[float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5]
const RULER_BAND_WIDTH := 1.6

## 御剑起降区：圆盘与高度环。
const FLIGHT_PAD_CENTER := Vector3(11.5, 0.0, 5.0)
const FLIGHT_PAD_RADIUS := 3.2
const FLIGHT_RING_HEIGHTS: Array[float] = [2.0, 4.0, 6.0, 8.0]
const FLIGHT_RING_RADIUS := 3.2

## 固定观察视角：只切换机位偏移，不改变角色或能力；跟随只做位移，不旋转。
## 角色沿 +X 跑道跑动且初始朝 +X，因此：
## - 正面 = 相机在 +X，看到角色正脸与跑道尽头；
## - 侧面 = 相机在 -Z，看到跑动侧影与横贯画面的跑道（读步态用这个）；
## - 斜侧 = 两者之间，兼顾步态与场地标记。
## 三个机位都抬高到 3 m 以上，让地面刻度不再是近乎正切的窄带。
enum StageView { FRONT, SIDE, THREE_QUARTER }
const VIEW_NAMES: Array[String] = ["正面", "侧面", "斜侧"]
const VIEW_HINT: Array[String] = [
	"相机在跑道尽头（读角色正面与转身）",
	"相机在跑道侧面（横贯画面，读步态）",
	"斜侧俯视（同时读步态与场地标记）",
]
const VIEW_OFFSETS: Array[Vector3] = [
	Vector3(14.0, 4.6, 0.0),
	Vector3(0.0, 4.6, -14.0),
	Vector3(10.5, 5.6, -10.5),
]
const CAMERA_TARGET_HEIGHT := 0.9
const CAMERA_SIZE := 11.0
const CAMERA_SIZE_MIN := 5.0
const CAMERA_SIZE_MAX := 34.0
const CAMERA_ZOOM_STEP := 1.5
const CAMERA_FOLLOW_SPEED := 6.0

## 场地配色（不依赖主题，标记本身即说明）。
const COLOR_FLOOR := Color(0.847059, 0.839216, 0.811765, 1.0)
const COLOR_RUNWAY := Color(0.941176, 0.929412, 0.898039, 0.9)
const COLOR_STRIPE := Color(0.243137, 0.278431, 0.309804, 0.85)
const COLOR_RUNWAY_CENTER := Color(0.454902, 0.549020, 0.478431, 0.75)
const COLOR_TURN_PAD := Color(0.647059, 0.356863, 0.243137, 0.35)
const COLOR_TURN_SPOKE := Color(0.815686, 0.482353, 0.321569, 0.9)
const COLOR_FLIGHT_PAD := Color(0.223529, 0.482353, 0.529412, 0.35)
const COLOR_FLIGHT_RING := Color(0.352941, 0.760784, 0.788235, 0.75)
const COLOR_RULER_POLE := Color(0.913725, 0.905882, 0.878431, 1.0)
const COLOR_RULER_BAND := Color(0.317647, 0.337255, 0.360784, 1.0)
const COLOR_RULER_APEX := Color(0.847059, 0.309804, 0.243137, 1.0)

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _presentation: Node3D
var _input := MovementLabInput.new()
var _view: int = StageView.THREE_QUARTER
var _follow_target := Vector3.ZERO
var _jump_edges := 0
var _flight_edges := 0
var _physics_ticks := 0

var _hud_panel: PanelContainer
var _hud_input: Label
var _hud_velocity: Label
var _hud_state: Label
var _hud_pose: Label
var _hud_view: Label


func _ready() -> void:
	# 固定返回目标必须先存在：缺它属于装配缺陷，启动即断言，不留给运行时静默兜底。
	assert(ResourceLoader.exists(MOVEMENT_HUB_SCENE, "PackedScene"),
		"motion_stage: 缺少移动子实验目录 %s（本工作台的固定返回目标）" % MOVEMENT_HUB_SCENE)
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "motion_stage: 场景必须提供 Camera3D")
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.near = 0.1
	_camera.far = 200.0
	_build_floor()
	_build_boundaries()
	_build_runway()
	_build_turn_pad()
	_build_flight_pad()
	_spawn_player()
	_build_ruler()
	_build_hud()
	_apply_view(_view, true)
	_update_hud()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	# 失焦只清输入：已开启的御剑保留悬停，不自动关飞、不坠落（traversal-contract）。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code := MovementLabInput.key_code(key_event)
		# 移动键与升降键的按住状态交给 helper（升降键由本场景显式声明）；
		# 跳跃语义仍是本场景决定并调用角色 API。
		if _input.track_key(key_event, MovementLabInput.VERTICAL_KEYS):
			if code == MovementLabInput.KEY_VERTICAL_UP and MovementLabInput.is_key_down_edge(key_event) and _player != null:
				# 跳跃是 key-down 边沿（echo 不算）；actor 在帧末自行清零。
				_player.press_jump()
				_jump_edges += 1
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo:
			match code:
				KEY_F:
					if _player != null:
						_player.press_flight_toggle()
						_flight_edges += 1
					get_viewport().set_input_as_handled()
				KEY_1:
					_apply_view(StageView.FRONT, false)
					get_viewport().set_input_as_handled()
				KEY_2:
					_apply_view(StageView.SIDE, false)
					get_viewport().set_input_as_handled()
				KEY_3:
					_apply_view(StageView.THREE_QUARTER, false)
					get_viewport().set_input_as_handled()
				KEY_TAB:
					_apply_view((_view + 1) % VIEW_NAMES.size(), false)
					get_viewport().set_input_as_handled()
				KEY_R:
					get_viewport().set_input_as_handled()
					_reset_experiment()
				_:
					if event.is_action_pressed("ui_cancel"):
						get_viewport().set_input_as_handled()
						_return_to_hub()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = clampf(_camera.size - CAMERA_ZOOM_STEP, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + CAMERA_ZOOM_STEP, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
			get_viewport().set_input_as_handled()


## 场景先写输入、actor 子节点随后 tick（父节点 _physics_process 先于子节点）。
func _physics_process(delta: float) -> void:
	if _player == null or _motion == null:
		return
	_physics_ticks += 1
	var right := _ground_vector(_camera.global_transform.basis.x, Vector3.RIGHT)
	var forward := _ground_vector(-_camera.global_transform.basis.z, Vector3.FORWARD)
	_player.set_camera_ground_basis(right, forward)
	var move := _input.move_input()
	_player.set_move_input(move)
	_player.set_vertical_input(_input.vertical_input())
	# 角色朝运动方向；停下时保留最后一次朝向，因此不停地在原地打转。
	if move != Vector2.ZERO:
		var direction := right * move.x - forward * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())
	_follow_camera(delta)


func _process(_delta: float) -> void:
	_update_hud()


func _ground_vector(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


# --- 观察视角 ---------------------------------------------------------------


## 切换固定机位：只改相机偏移，不动角色、不动能力，也不改输入语义。
func _apply_view(index: int, snap: bool) -> void:
	_view = clampi(index, 0, VIEW_NAMES.size() - 1)
	_camera.size = CAMERA_SIZE if snap else _camera.size
	var target := _camera_target()
	_follow_target = target if snap else _follow_target
	_camera.position = _follow_target + VIEW_OFFSETS[_view]
	_camera.look_at(_follow_target, Vector3.UP)


func _camera_target() -> Vector3:
	var target := _player.global_position if _player != null else Vector3.ZERO
	target.y += CAMERA_TARGET_HEIGHT
	return target


func _follow_camera(delta: float) -> void:
	var target := _camera_target()
	# 断线或首次跟随时直接贴合，避免相机从原点飞过去。
	if _follow_target.distance_squared_to(target) > 400.0:
		_follow_target = target
	else:
		_follow_target = _follow_target.lerp(target, clampf(delta * CAMERA_FOLLOW_SPEED, 0.0, 1.0))
	_camera.position = _follow_target + VIEW_OFFSETS[_view]
	_camera.look_at(_follow_target, Vector3.UP)


func _reset_camera() -> void:
	_follow_target = _camera_target()
	_camera.size = CAMERA_SIZE
	_camera.position = _follow_target + VIEW_OFFSETS[_view]
	_camera.look_at(_follow_target, Vector3.UP)


# --- 场地装配 ---------------------------------------------------------------


## 纯物理地面：顶面严格 y = 0，与作品其它场景一致。
func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.position = Vector3(0.0, -GROUND_THICKNESS * 0.5, 0.0)
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = COLLISION_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(STAGE_HALF_X * 2.0, GROUND_THICKNESS, STAGE_HALF_Z * 2.0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	_add_mark("FloorPlate", Vector3(0.0, -0.02, 0.0), Vector3(STAGE_HALF_X * 2.0, 0.04, STAGE_HALF_Z * 2.0), COLOR_FLOOR)


func _build_boundaries() -> void:
	var root := Node3D.new()
	root.name = "Boundaries"
	add_child(root)
	var span_x := STAGE_HALF_X + WALL_THICKNESS * 0.5
	var span_z := STAGE_HALF_Z + WALL_THICKNESS * 0.5
	var length_x := STAGE_HALF_X * 2.0 + WALL_THICKNESS * 2.0
	var length_z := STAGE_HALF_Z * 2.0 + WALL_THICKNESS * 2.0
	_make_block(root, "West", Vector3(-span_x, WALL_HEIGHT * 0.5, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, length_z))
	_make_block(root, "East", Vector3(span_x, WALL_HEIGHT * 0.5, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, length_z))
	_make_block(root, "North", Vector3(0.0, WALL_HEIGHT * 0.5, -span_z), Vector3(length_x, WALL_HEIGHT, WALL_THICKNESS))
	_make_block(root, "South", Vector3(0.0, WALL_HEIGHT * 0.5, span_z), Vector3(length_x, WALL_HEIGHT, WALL_THICKNESS))
	# 边界只有碰撞体、没有网格：StaticBody3D 本身不渲染，墙体不会遮住跑道与角色。
	_make_block(root, "Ceiling", Vector3(0.0, CEILING_Y + WALL_THICKNESS * 0.5, 0.0),
		Vector3(length_x, WALL_THICKNESS, length_z))


## 直跑道：铺底 + 每 2 m 一条横刻度 + 起止端线；刻度线是量具，不参与碰撞。
func _build_runway() -> void:
	var root := Node3D.new()
	root.name = "Runway"
	add_child(root)
	var length := RUNWAY_MAX_X - RUNWAY_MIN_X
	var center_x := (RUNWAY_MIN_X + RUNWAY_MAX_X) * 0.5
	_add_mark_to(root, "RunwayBed", Vector3(center_x, 0.006, 0.0), Vector3(length, 0.012, RUNWAY_HALF_Z * 2.0), COLOR_RUNWAY)
	# 中线：让跑道方向一眼可读，也作为八方向区之外的直行参照。
	_add_mark_to(root, "RunwayCenterLine", Vector3(center_x, 0.010, 0.0),
		Vector3(length, 0.010, 0.10), COLOR_RUNWAY_CENTER)
	var index := 0
	var x := RUNWAY_MIN_X
	while x <= RUNWAY_MAX_X + 0.001:
		var metre := int(round(x))
		var is_end := index == 0 or x >= RUNWAY_MAX_X - 0.001
		var width := RUNWAY_HALF_Z * 2.0 if is_end else (0.16 if metre % 10 == 0 else 0.08)
		var colour := COLOR_STRIPE
		_add_mark_to(root, "Stripe%02d" % index, Vector3(x, 0.014, 0.0), Vector3(width, 0.012, RUNWAY_HALF_Z * 2.0), colour)
		# 每 8 m 才落一个数字：刻度线保持每 2 m，文字稀疏到不互相遮挡。
		if metre % 8 == 0:
			_add_label_to(root, "StripeLabel%02d" % index, Vector3(x, 0.18, RUNWAY_HALF_Z + 0.62),
				"%d m" % metre, 0.24, Color(0.243137, 0.258824, 0.278431, 1.0))
		x += RUNWAY_STRIPE_STEP
		index += 1


## 八方向 / 急转区：八条辐条 + 中心环，供急转与方向反转观察。
func _build_turn_pad() -> void:
	var root := Node3D.new()
	root.name = "TurnPad"
	add_child(root)
	_add_disc_to(root, "TurnPadDisc", TURN_PAD_CENTER, TURN_PAD_RADIUS, COLOR_TURN_PAD)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		var centre := TURN_PAD_CENTER + direction * (TURN_PAD_RADIUS * 0.5)
		var spoke := _add_mark_to(root, "Spoke%d" % index, centre + Vector3(0.0, 0.016, 0.0),
			Vector3(0.14, 0.012, TURN_PAD_RADIUS), COLOR_TURN_SPOKE)
		spoke.rotation.y = angle
	_add_ring_to(root, "TurnPadRing", TURN_PAD_CENTER, TURN_PAD_RADIUS, 0.10, 0.014, COLOR_TURN_SPOKE)
	_add_label_to(root, "TurnPadLabel", TURN_PAD_CENTER + Vector3(0.0, 0.22, -TURN_PAD_RADIUS - 0.8),
		"八方向 / 急转区", 0.28, Color(0.360784, 0.219608, 0.160784, 1.0))


## 御剑起降区：起降盘 + 高度环；环高度是绝对高度参照，不是 Hardcode 的手感结论。
func _build_flight_pad() -> void:
	var root := Node3D.new()
	root.name = "FlightPad"
	add_child(root)
	_add_disc_to(root, "FlightPadDisc", FLIGHT_PAD_CENTER, FLIGHT_PAD_RADIUS, COLOR_FLIGHT_PAD)
	_add_ring_to(root, "FlightPadRing", FLIGHT_PAD_CENTER, FLIGHT_PAD_RADIUS, 0.12, 0.016, COLOR_FLIGHT_RING)
	for index in range(FLIGHT_RING_HEIGHTS.size()):
		var height := FLIGHT_RING_HEIGHTS[index] as float
		_add_torus_to(root, "HeightRing%d" % index, FLIGHT_PAD_CENTER + Vector3(0.0, height, 0.0),
			FLIGHT_RING_RADIUS, 0.035, COLOR_FLIGHT_RING)
		_add_label_to(root, "HeightLabel%d" % index,
			FLIGHT_PAD_CENTER + Vector3(FLIGHT_RING_RADIUS + 0.45, height, 0.0),
			"%d m" % int(height), 0.24, Color(0.164706, 0.372549, 0.396078, 1.0))
	_add_label_to(root, "FlightPadLabel", FLIGHT_PAD_CENTER + Vector3(0.0, 0.22, -FLIGHT_PAD_RADIUS - 0.8),
		"御剑起降区", 0.28, Color(0.113725, 0.278431, 0.309804, 1.0))


## 跳跃标尺：立柱 + 刻度带；刻度由组件的 jump_speed / gravity 推导，标尺读数即物理真值。
func _build_ruler() -> void:
	var apex := _jump_apex()
	var root := Node3D.new()
	root.name = "JumpRuler"
	add_child(root)
	_add_mark_to(root, "RulerBase", Vector3(RULER_X, 0.016, RULER_Z), Vector3(RULER_BAND_WIDTH + 0.5, 0.02, 0.5),
		Color(0.733333, 0.725490, 0.701961, 1.0))
	_add_mark_to(root, "RulerPole", Vector3(RULER_X, apex * 0.85, RULER_Z), Vector3(0.10, apex * 1.7 + 0.4, 0.10), COLOR_RULER_POLE)
	for index in range(RULER_BAND_FACTORS.size()):
		var factor := RULER_BAND_FACTORS[index] as float
		var height := apex * factor
		var is_apex := is_equal_approx(factor, 1.0)
		var colour := COLOR_RULER_APEX if is_apex else COLOR_RULER_BAND
		_add_mark_to(root, "Band%d" % index, Vector3(RULER_X, height, RULER_Z),
			Vector3(RULER_BAND_WIDTH, 0.045 if is_apex else 0.03, 0.16), colour)
		_add_label_to(root, "BandLabel%d" % index, Vector3(RULER_X + RULER_BAND_WIDTH * 0.5 + 0.50, height, RULER_Z),
			"%.2f m" % height, 0.24, Color(0.203922, 0.219608, 0.239216, 1.0))
	_add_label_to(root, "RulerLabel", Vector3(RULER_X, 0.50, RULER_Z + 0.85),
		"跳跃标尺（顶点 %.2f m）" % apex, 0.28, Color(0.203922, 0.219608, 0.239216, 1.0))


## 理论跳跃顶点 = v0^2 / (2g)，直接读组件导出参数；组件缺失时用契约默认值并保持标尺可见。
func _jump_apex() -> float:
	var jump_speed := 6.0
	var gravity := 18.0
	if _motion != null:
		jump_speed = _motion.jump_speed
		gravity = _motion.gravity
	return jump_speed * jump_speed / (2.0 * maxf(gravity, 0.001))


func _spawn_player() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "motion_stage: swordsman.tscn 根节点必须是 Swordsman")
	actor.name = "Swordsman"
	add_child(actor)
	_player = actor
	_motion = actor.motion()
	assert(_motion != null, "motion_stage: 角色缺少 SwordsmanMotionComponent")
	_presentation = actor.get_node_or_null("Visual/CultivatorPresentation") as Node3D
	assert(_presentation != null, "motion_stage: 角色缺少表现节点 Visual/CultivatorPresentation")
	# 场景不认识 CapabilityManager 与任何具体能力：能力装配由 swordsman.tscn 负责（铁律 2）。
	_bind_flight_visual(actor)
	# reset_motion 会清输入与御剑状态，因此先重置、再写落点与朝向。
	actor.reset_motion()
	actor.global_position = SPAWN_POSITION
	actor.set_aim_direction(SPAWN_AIM)


## 御剑视觉由场景装配并经 actor.bind_flight_visual() 注入：剑作为 Visual 子节点随角色转身，
## 显隐由 actor 按 flight_active 统一处理，表现层不参与御剑状态判定。
func _bind_flight_visual(actor: Swordsman) -> void:
	var instance := FLYING_SWORD_SCENE.instantiate()
	assert(instance is Node3D, "motion_stage: flying_sword.glb 根节点必须是 Node3D")
	var sword := instance as Node3D
	sword.name = "FlyingSword"
	var visual := actor.get_node_or_null("Visual") as Node3D
	assert(visual != null, "motion_stage: 角色缺少 Visual 节点")
	visual.add_child(sword)
	actor.bind_flight_visual(sword)


## 只读：御剑视觉节点（供验收脚本断言飞行状态与视觉一致）。
func flight_visual() -> Node3D:
	var visual := _player.get_node_or_null("Visual/FlyingSword") if _player != null else null
	return visual as Node3D


# --- 输入清理与重置 ---------------------------------------------------------


func _clear_pressed() -> void:
	_input.clear()
	if _player != null:
		# 只清输入：已开启的御剑保留悬停，不自动关飞。
		_player.clear_input()


func _reset_experiment() -> void:
	_clear_pressed()
	_player.global_position = SPAWN_POSITION
	_player.reset_motion()
	_player.set_aim_direction(SPAWN_AIM)
	_jump_edges = 0
	_flight_edges = 0
	_physics_ticks = 0
	_reset_camera()
	_update_hud()


## 返回移动子实验目录。目标固定，切换失败即显式报错，不静默改道。
func _return_to_hub() -> void:
	_clear_pressed()
	var result := get_tree().change_scene_to_file(MOVEMENT_HUB_SCENE)
	assert(result == OK, "motion_stage: 返回移动子实验目录失败（%s，错误码 %d）" % [MOVEMENT_HUB_SCENE, result])


# --- 公开只读接口（供 HUD 与验收脚本读取，不写任何状态） ---------------------


func player() -> Swordsman:
	return _player


func motion() -> SwordsmanMotionComponent:
	return _motion


func presentation() -> Node3D:
	return _presentation


func view_index() -> int:
	return _view


func view_name() -> String:
	return VIEW_NAMES[_view]


## 表现层只读快照；表现节点被移除时返回空字典（三能力不受影响）。
func presentation_state() -> Dictionary:
	if _presentation == null or not _presentation.has_method("pose_state"):
		return {}
	return _presentation.call("pose_state") as Dictionary


## 工作台当前可观察量汇总：输入意图、实际速度、物理状态、表现姿态与视角。
func stage_state() -> Dictionary:
	if _player == null or _motion == null:
		return {}
	return {
		"position": _player.global_position,
		"move_input": _motion.move_input,
		"vertical_input": _motion.vertical_input,
		"aim_direction": _motion.aim_direction,
		"actual_velocity": _motion.actual_velocity,
		"horizontal_speed": Vector2(_motion.actual_velocity.x, _motion.actual_velocity.z).length(),
		"on_floor": _motion.on_floor,
		"flight_active": _motion.flight_active,
		"jump_edges": _jump_edges,
		"flight_edges": _flight_edges,
		"physics_ticks": _physics_ticks,
		"view": view_name(),
		"pose": presentation_state(),
	}


# --- HUD --------------------------------------------------------------------


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
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 14)
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

	_hud_panel = PanelContainer.new()
	_hud_panel.name = "ReadoutPanel"
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel.add_theme_stylebox_override("panel", _backdrop())
	header.add_child(_hud_panel)

	var readout := VBoxContainer.new()
	readout.name = "Readout"
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.add_theme_constant_override("separation", 2)
	_hud_panel.add_child(readout)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.theme_type_variation = "AccentLabel"
	kicker.add_theme_font_size_override("font_size", 12)
	kicker.text = "EXPERIMENT    /    CHARACTER MOVEMENT · MOTION STAGE"
	readout.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 22)
	title.text = "人物动作工作台"
	readout.add_child(title)

	_hud_input = _make_readout_label(readout, "Input")
	_hud_velocity = _make_readout_label(readout, "Velocity")
	_hud_state = _make_readout_label(readout, "State")
	_hud_pose = _make_readout_label(readout, "Pose")
	_hud_view = _make_readout_label(readout, "View")

	var buttons := VBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 8)
	header.add_child(buttons)

	var return_button := Button.new()
	return_button.name = "ReturnButton"
	# 目标固定为移动子实验目录（movement_lab_hub），不是顶层实验目录；按钮文案必须如实。
	return_button.text = "返回子实验目录"
	return_button.custom_minimum_size = Vector2(132, 40)
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.pressed.connect(_return_to_hub)
	buttons.add_child(return_button)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置 (R)"
	reset_button.custom_minimum_size = Vector2(132, 40)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_experiment)
	buttons.add_child(reset_button)

	var view_row := HBoxContainer.new()
	view_row.name = "ViewRow"
	view_row.add_theme_constant_override("separation", 4)
	buttons.add_child(view_row)
	for index in range(VIEW_NAMES.size()):
		var view_button := Button.new()
		view_button.name = "View%d" % index
		view_button.text = VIEW_NAMES[index]
		view_button.custom_minimum_size = Vector2(40, 34)
		view_button.focus_mode = Control.FOCUS_NONE
		view_button.pressed.connect(_apply_view.bind(index, false))
		view_row.add_child(view_button)

	var spacer := Control.new()
	spacer.name = "Space"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	controls.add_theme_font_size_override("font_size", 13)
	controls.text = "WASD / 方向键 移动  ·  Space 跳跃 / 上升  ·  Ctrl 下降  ·  F 开关御剑  ·  1/2/3 切换固定视角  ·  滚轮缩放  ·  R 重置  ·  Esc 返回子实验目录"
	# 中文没有词间空格，WORD_SMART 会把整句当成一个长词并撑出最小宽度；
	# 小窗 960×640 下这会顶穿右边界，因此用任意位置换行。
	controls.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_panel.add_child(controls)


func _make_readout_label(parent: Node, tag: String) -> Label:
	var label := Label.new()
	label.name = tag
	label.theme_type_variation = "MutedLabel"
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.custom_minimum_size = Vector2(0, 0)
	parent.add_child(label)
	return label


func _backdrop() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.980392, 0.972549, 0.949020, 0.86)
	style.border_color = Color(0.505882, 0.611765, 0.533333, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


## 只读组件与表现快照，不写任何运动状态。
func _update_hud() -> void:
	if _hud_input == null or _motion == null or _player == null:
		return
	var move := _motion.move_input
	var velocity := _motion.actual_velocity
	var horizontal := Vector2(velocity.x, velocity.z).length()
	_hud_input.text = "输入  move=(%+.2f, %+.2f)  升降=%+.0f  跳跃边沿=%d  御剑边沿=%d" % [
		move.x, move.y, _motion.vertical_input, _jump_edges, _flight_edges,
	]
	_hud_velocity.text = "实际速度  v=(%+.2f, %+.2f, %+.2f)  水平 %.2f m/s" % [
		velocity.x, velocity.y, velocity.z, horizontal,
	]
	_hud_state.text = "状态  着地=%s  御剑=%s  高度=%.2f m  朝向=(%+.2f, %+.2f)  物理帧=%d" % [
		"是" if _motion.on_floor else "否",
		"是" if _motion.flight_active else "否",
		_player.global_position.y,
		_motion.aim_direction.x, _motion.aim_direction.z,
		_physics_ticks,
	]
	_hud_pose.text = "表现  " + _pose_text()
	_hud_view.text = "视角  %s（%s）" % [view_name(), VIEW_HINT[_view]]


## 表现摘要：gait / phase / 四肢枢轴角 / 躯干俯仰与起伏；表现节点缺失时如实标注。
func _pose_text() -> String:
	var pose := presentation_state()
	if pose.is_empty():
		return "表现节点缺失（三能力不受影响）"
	return "gait=%.2f  phase=%.2f  flight=%.2f  左腿=%+.2f  右腿=%+.2f  左臂=%+.2f  躯干俯仰=%+.3f  起伏=%+.3f" % [
		float(pose.get("gait", 0.0)),
		float(pose.get("phase", 0.0)),
		float(pose.get("flight", 0.0)),
		float(pose.get("leg_left", 0.0)),
		float(pose.get("leg_right", 0.0)),
		float(pose.get("arm_left", 0.0)),
		float(pose.get("body_pitch", 0.0)),
		float(pose.get("body_lift", 0.0)),
	]


# --- 程序化标记工具 ---------------------------------------------------------


## 标记材质：不受光、关闭高光与背面剔除，保证量具在任何光照下清晰。
func _mark_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _add_mark(mark_name: String, centre: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	return _add_mark_to(self, mark_name, centre, size, color)


func _add_mark_to(parent: Node, mark_name: String, centre: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = mark_name
	instance.mesh = mesh
	instance.material_override = _mark_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = centre
	parent.add_child(instance)
	return instance


func _add_disc_to(parent: Node, disc_name: String, centre: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 48
	mesh.rings = 0
	var instance := MeshInstance3D.new()
	instance.name = disc_name
	instance.mesh = mesh
	instance.material_override = _mark_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = centre + Vector3(0.0, 0.012, 0.0)
	parent.add_child(instance)
	return instance


## 平放的圆环：用 TorusMesh 转 90° 使其落在水平面。
func _add_ring_to(parent: Node, ring_name: String, centre: Vector3, radius: float, thickness: float, lift: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(radius - thickness, 0.01)
	mesh.outer_radius = radius + thickness
	mesh.rings = 48
	mesh.ring_segments = 6
	var instance := MeshInstance3D.new()
	instance.name = ring_name
	instance.mesh = mesh
	instance.material_override = _mark_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = centre + Vector3(0.0, lift, 0.0)
	parent.add_child(instance)
	return instance


## 竖直圆环：高度环保持竖直方向，从正面 / 斜侧可读。
func _add_torus_to(parent: Node, torus_name: String, centre: Vector3, radius: float, thickness: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(radius - thickness, 0.01)
	mesh.outer_radius = radius + thickness
	mesh.rings = 48
	mesh.ring_segments = 6
	var instance := MeshInstance3D.new()
	instance.name = torus_name
	instance.mesh = mesh
	instance.material_override = _mark_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = centre
	instance.rotation.x = PI * 0.5
	parent.add_child(instance)
	return instance


func _add_label_to(parent: Node, label_name: String, position: Vector3, text: String, height: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = label_name
	label.text = text
	label.font_size = 48
	label.pixel_size = height / 48.0
	label.modulate = color
	label.shaded = false
	# Label3D 的正面朝 +Z，固定机位会从 +X / -Z 看，直接摆放会读到镜像或侧棱。
	# 量具文字对齐相机（billboard）并关闭深度测试，三个观察视角都能正读。
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.double_sided = true
	label.no_depth_test = true
	label.position = position
	parent.add_child(label)
	return label


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
