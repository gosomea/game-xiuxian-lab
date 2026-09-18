extends Node3D

## 人物动作工作台（motion_stage）：用真实 Swordsman 与公开输入 API 观察动作表现。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md（子实验「人物动作工作台」）
## 与 notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md（S2 动作工作台 P0）。
##
## 两种模式（界面上必须显式区分，不靠用户猜）：
## - **实时运动**（realtime）：真实 Swordsman + 真实输入 + 唯一物理提交点，读数来自物理真值。
## - **程序动作预览**（preview）：独立展示实例（MotionPreviewDisplay，同共享 Visual 装配，
##   无 CharacterBody3D / 无碰撞 / 无 CapabilityManager），由局部预览时钟与显式 state provider
##   驱动。预览不写正式 actor 的 motion 组件、不写 Engine.time_scale、不暂停场景树。
##
## 职责边界：
## - 角色、三能力与运动数据归 res://game/actors/swordsman/ 与 res://game/abilities/；
##   本场景只做输入编排、场地标记、固定观察视角与 HUD/控件装配。
## - 只调用角色公开输入 API（set_move_input / set_vertical_input / press_jump /
##   press_flight_toggle / set_camera_ground_basis / set_aim_direction / reset_motion /
##   clear_input）；不写 velocity、不写意图、不碰任何 Capability 内部状态。
## - 预览模式下保留真实 actor（它在场景里照常存在、可继续被物理推进），但**禁用其输入路由**：
##   场景不再向它写输入，且失焦/切模式时调用 clear_input() 清掉已按住的键。
## - HUD 只读组件公共字段（actual_velocity / on_floor / flight_active / aim_direction）
##   与表现层只读快照 pose_state() / stage_state() / preview_snapshot()；
##   验收脚本不得访问 _legs / _arms 等私有字段。
## - 镜头归 res://game/systems/camera_rig/ 的 CameraRig（唯一 executor）；本场景不再手写跟随，
##   只做「视角配置 + 模式切换时换目标」。CameraRig 以 process_physics_priority=-10 先写相机并
##   把最终地面基发布给 target，因此本场景的物理帧不再自行计算相机基。
## - 场地标记全部程序化生成（无新二进制资产）；跳跃标尺刻度由组件参数推导，不是硬编码文案。
## - Esc / 返回按钮固定回到移动子实验目录；该依赖在 _ready 断言，缺失时启动即失败而非静默改道。
##
## 空间键（空格）裁决：实时模式下空格 = 跳跃；控件获得焦点时空格属于控件（按钮激活），
## 不再触发角色跳跃；预览模式下空格永远不触发跳跃。

## 移动子实验目录是本工作台的固定返回目标（同提交依赖）；
## 不做「存在才用、否则静默回退顶层目录」的兜底——那会掩盖装配缺陷。
const MOVEMENT_HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")

## 动作预览专用包（S2 P0）：展示实例与控件面板都在 res://game/systems/motion_preview/，
## 本场景只做装配与编排，不复制姿态系统、不实现第二个动作播放器。
## 该包由本场景作者维护，因此用 class_name 静态类型；运行时参数仍走预览快照。
## 共享 HUD 由整合方维护并迭代中，故只按约定方法名动态调用，不钉死其类签名。
const LAB_HUD_SCRIPT: GDScript = preload("res://ui/lab_hud.gd")
## 镜头装配 sheet（camera_rig 包唯一 executor）：场景只实例化 + bind + 配置，不复制跟随逻辑。
const CAMERA_RIG_SHEET: PackedScene = preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")

## 预览展示实例站位：跑道北侧、观察机位可见处，不参与任何碰撞。
const PREVIEW_POSITION := Vector3(6.5, 0.05, 3.6)

## 观察模式：实时运动（真实 actor 物理真值）/ 程序动作预览（独立展示实例）。
enum StageMode { REALTIME, PREVIEW }
const MODE_NAMES: Array[String] = ["实时运动", "程序动作预览"]

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

## 地面标记分层：物理地面碰撞盒顶严格 y = 0，可见标记整体抬到地面之上，不靠下沉可见面回避共面。
## 抬升约定沿用 mountain_realm / peak_courtyards 的 2 cm；相邻可见层净空 ≥ MARK_LAYER_CLEARANCE。
const GROUND_MARK_BASE := 0.02
const MARK_LAYER_CLEARANCE := 0.004

## 各层只写「底面 + 顶面」，中心由两端推出，杜绝「承托面 + 自身半高」的零间隙写法。
const RUNWAY_BED_BOTTOM := GROUND_MARK_BASE
const RUNWAY_BED_TOP := RUNWAY_BED_BOTTOM + 0.006
const RUNWAY_CENTER_BOTTOM := RUNWAY_BED_TOP + MARK_LAYER_CLEARANCE
const RUNWAY_CENTER_TOP := RUNWAY_CENTER_BOTTOM + 0.004
const STRIPE_BOTTOM := RUNWAY_CENTER_TOP + MARK_LAYER_CLEARANCE
const STRIPE_TOP := STRIPE_BOTTOM + 0.006
const PAD_DISC_BOTTOM := GROUND_MARK_BASE
const PAD_DISC_TOP := PAD_DISC_BOTTOM + 0.006
const SPOKE_BOTTOM := PAD_DISC_TOP + MARK_LAYER_CLEARANCE
const SPOKE_TOP := SPOKE_BOTTOM + 0.005
const PAD_RING_BOTTOM := SPOKE_TOP + MARK_LAYER_CLEARANCE
const PAD_RING_TOP := PAD_RING_BOTTOM + 0.006
const RULER_BASE_BOTTOM := GROUND_MARK_BASE
const RULER_BASE_TOP := RULER_BASE_BOTTOM + 0.004

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
## 7 个地面量具颜色由半透明改为等效不透明（原 alpha 合成到最近承托面），避免透明排序参与地面绘制；
## 合成口径见 notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md 的「第五场」。
const COLOR_FLOOR := Color(0.847059, 0.839216, 0.811765, 1.0)
const COLOR_RUNWAY := Color(0.932, 0.920, 0.889, 1.0)
const COLOR_STRIPE := Color(0.346, 0.375, 0.397, 1.0)
const COLOR_RUNWAY_CENTER := Color(0.574, 0.642, 0.581, 1.0)
const COLOR_TURN_PAD := Color(0.777, 0.670, 0.613, 1.0)
const COLOR_TURN_SPOKE := Color(0.812, 0.501, 0.351, 1.0)
const COLOR_FLIGHT_PAD := Color(0.629, 0.714, 0.713, 1.0)
const COLOR_FLIGHT_RING := Color(0.445, 0.764, 0.786, 1.0)
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
## 镜头装配（camera_rig 包）：本场景只持有引用用于视角配置与目标切换，不写 Camera3D。
var _rig: CameraRig
var _jump_edges := 0
var _flight_edges := 0
var _physics_ticks := 0

## 共享 HUD 与预览面板都用无类型变量持有：它们来自别的包/别的 agent 维护的脚本，
## 这里只按约定方法名动态调用，避免把对方的类签名钉死在本场景的静态类型上。
var _hud
var _mode: int = StageMode.REALTIME
var _preview
var _panel
var _mode_button: Button
var _action_ids: Array[StringName] = []


func _ready() -> void:
	# 固定返回目标必须先存在：缺它属于装配缺陷，启动即断言，不留给运行时静默兜底。
	assert(ResourceLoader.exists(MOVEMENT_HUB_SCENE, "PackedScene"),
		"motion_stage: 缺少移动子实验目录 %s（本工作台的固定返回目标）" % MOVEMENT_HUB_SCENE)
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "motion_stage: 场景必须提供 Camera3D")
	# 相机的投影 / size / near / far 由 CameraRig（唯一 executor）按配置写，本场景不直接写。
	_build_floor()
	_build_boundaries()
	_build_runway()
	_build_turn_pad()
	_build_flight_pad()
	_spawn_player()
	_build_ruler()
	_build_preview()
	_build_camera_rig()
	_build_hud()
	_apply_view(_view, true)
	_apply_mode(StageMode.REALTIME, true)
	_update_hud()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	# 失焦只清输入：已开启的御剑保留悬停，不自动关飞、不坠落（traversal-contract）。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()


## 表单控件占用键盘焦点：空格/回车归控件，不能再当成角色跳跃或能力键。
## 这是「播放 GUI 获得 focus 时空格不能同时 jump」的机械判据。
func _ui_has_keyboard_focus() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and focus.is_visible_in_tree()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code := MovementLabInput.key_code(key_event)
		# 预览模式：空格归预览播放/暂停，与角色跳跃无关。
		# 控件持有键盘焦点时 GUI 会先消费该事件（按钮被激活），根本不会走到这里；
		# 走到这里说明没有控件在响应，语义明确归预览。
		if _mode == StageMode.PREVIEW and code == MovementLabInput.KEY_VERTICAL_UP \
				and MovementLabInput.is_key_down_edge(key_event):
			_toggle_preview_playing()
			get_viewport().set_input_as_handled()
			return
		# 预览模式下角色输入路由被禁用：所有输入只服务预览控件与观察，不写真实 actor。
		var actor_input_enabled := _mode == StageMode.REALTIME and not _ui_has_keyboard_focus()
		# 移动键与升降键的按住状态交给 helper（升降键由本场景显式声明）；
		# 跳跃语义仍是本场景决定并调用角色 API。
		if _input.track_key(key_event, MovementLabInput.VERTICAL_KEYS):
			var jump_edge := MovementLabInput.is_key_down_edge(key_event) and _player != null
			if code == MovementLabInput.KEY_VERTICAL_UP and actor_input_enabled and jump_edge:
				# 跳跃是 key-down 边沿（echo 不算）；actor 在帧末自行清零。
				_player.press_jump()
				_jump_edges += 1
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo:
			match code:
				KEY_M:
					# 模式开关：实时运动 <-> 程序动作预览（与界面顶部按钮同源）。
					_apply_mode(StageMode.PREVIEW if _mode == StageMode.REALTIME else StageMode.REALTIME, false)
					get_viewport().set_input_as_handled()
				KEY_F:
					if actor_input_enabled and _player != null:
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
			# 缩放走 CameraRig（唯一写 Camera3D 的节点）；GUI 已消费的滚轮不会到达这里。
			if _rig != null:
				_rig.adjust_zoom(1.0)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _rig != null:
				_rig.adjust_zoom(-1.0)
			get_viewport().set_input_as_handled()


## 场景先写输入、actor 子节点随后 tick（父节点 _physics_process 先于子节点）。
func _physics_process(_delta: float) -> void:
	if _player == null or _motion == null:
		return
	_physics_ticks += 1
	# 相机地面基由 CameraRig 在写相机后直接发布给目标（桥接层），本场景不重复转交、不写 Camera3D。
	# 执行次序由 process_physics_priority 保证：CameraRig(-10) 先写相机并发布基，本节点(0) 再读。
	if _mode != StageMode.REALTIME:
		# 预览模式：真实 actor 保留在场景中，但输入路由完全关闭——每帧写零，
		# 不依赖「谁记得清干净」，因此它不可能因本场景输入产生位移。
		_player.set_move_input(Vector2.ZERO)
		_player.set_vertical_input(0.0)
		return
	var move := _input.move_input()
	_player.set_move_input(move)
	_player.set_vertical_input(_input.vertical_input())
	# 角色朝运动方向；停下时保留最后一次朝向，因此不停地在原地打转。
	# 地面基与最终渲染一致（含混合期），因此移动方向不会与画面脱节。
	if move != Vector2.ZERO and _rig != null:
		var right := _rig.right_axis()
		var forward := _rig.forward_axis()
		var direction := right * move.x - forward * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())


func _process(delta: float) -> void:
	# 预览局部时钟使用真实渲染帧 delta：预览播放推进 delta * 倍率，
	# 因此 30/60 fps 同一墙钟时长推进总量一致；暂停时 advance 内部 consumed_delta=0，
	# 表现层连姿态都不会被推进（见 MotionPreviewDisplay._consume_tick）。
	if _preview != null and _mode == StageMode.PREVIEW:
		_preview.call("advance", delta)
		if _panel != null:
			_panel.call("refresh", preview_snapshot())
	_update_hud()


# --- 镜头装配与观察视角 -----------------------------------------------------


## 实例化镜头 sheet 并绑定：默认跟随真实 actor（实时运动模式的物理真值来源）。
## 本场景不写 Camera3D、不做跟随插值、不发布地面基——全部由 CameraRig(-10) 完成。
func _build_camera_rig() -> void:
	var rig := CAMERA_RIG_SHEET.instantiate() as CameraRig
	assert(rig != null, "motion_stage: camera_rig_sheet.tscn 根节点必须是 CameraRig")
	rig.name = "CameraRig"
	add_child(rig)
	_rig = rig
	# 数字键 1/2/3 属于本场景的观察视角（正面 / 侧面 / 斜侧），因此不开启镜头包的模式选择键，
	# 也不开启 Tab 预设键：镜头包只提供 fixed_follow 跟随，不抢实验按键。
	rig.mode_cycle = PackedStringArray(["fixed_follow"])
	rig.bind(_camera, _player, _view_config(_view))
	rig.bind_motion_source(_player)


## 观察视角 = 一组 CameraRigConfig：用同一 fixed_follow executor，只换构图参数。
## VIEW_OFFSETS 是「相机相对焦点的偏移」，这里换算成 CameraRig 的 yaw / pitch / distance，
## 保持与迁移前完全相同的机位（换算而非重调参）。
func _view_config(index: int) -> CameraRigConfig:
	var offset := VIEW_OFFSETS[clampi(index, 0, VIEW_OFFSETS.size() - 1)]
	var horizontal := Vector2(offset.x, offset.z).length()
	var config := CameraRigConfig.new()
	config.start_mode = "fixed_follow"
	config.follow_preset = "hard"
	config.projection = Camera3D.PROJECTION_ORTHOGONAL
	config.size = CAMERA_SIZE
	config.size_min = CAMERA_SIZE_MIN
	config.size_max = CAMERA_SIZE_MAX
	config.zoom_step = CAMERA_ZOOM_STEP
	# 输入归属显式声明（config 默认值即此，仍写出来让本场景的意图可读）：
	# 只有 fixed_follow 跟随；数字键 1/2/3 归本场景的三个观察机位，Q/E 偏航也归场景。
	config.mode_choices = PackedStringArray(["fixed_follow"])
	config.enable_mode_selection_keys = false
	config.enable_preset_key = false
	config.enable_zoom_keys = false
	config.enable_zoom_wheel = true
	config.enable_yaw_keys = false
	config.near = 0.1
	config.far = 200.0
	# 焦点抬到胸口高度（迁移前 _camera_target() 的 +0.9 m）。
	config.focus_offset = Vector3(0.0, CAMERA_TARGET_HEIGHT, 0.0)
	# VIEW_OFFSETS 是**相机相对焦点**的偏移（迁移前 camera = follow_target + VIEW_OFFSETS，
	# 而 follow_target 已经抬到胸口），因此这里换算成以焦点为原点的球面参数，不再二次减去
	# 焦点高度——否则相机会整体下沉 0.9 m。
	config.pitch_degrees = rad_to_deg(atan2(offset.y, maxf(horizontal, 0.0001)))
	config.yaw_degrees = rad_to_deg(atan2(offset.x, offset.z))
	config.distance = offset.length()
	config.transition_time = 0.0
	# 实时运动中角色会跑动，焦点跟紧（与迁移前的 6 m/s 跟随相当）。
	config.smooth_time = 0.12
	config.deadzone_half_width = 0.0
	config.deadzone_half_height = 0.0
	return config


## 切换观察视角：只换镜头配置与目标，不动角色、不动能力、不改输入语义。
## snap=true 时立即生效（不做混合），用于启动与重置；false 时由 CameraRig 混合过渡。
func _apply_view(index: int, snap: bool) -> void:
	_view = clampi(index, 0, VIEW_NAMES.size() - 1)
	if _rig == null:
		return
	var config := _view_config(_view)
	# 只换构图参数：CameraRig 的 bind() 会按新配置播种并在需要时从**当前真实渲染状态**开始混合，
	# 因此视角切换不跳变。snap=true 用于启动 / 重置，额外把镜头状态一并复位。
	_rig.bind(_camera, _camera_target_node(), config)
	if snap:
		_rig.reset_state()
		_rig.bind(_camera, _camera_target_node(), config)


## 当前模式跟随的目标节点：实时运动跟真实 actor，程序预览跟独立展示实例。
## 两者都是普通 Node3D，CameraRig 只读它们的 global_position（速度由位移差分得到）。
func _camera_target_node() -> Node3D:
	if _mode == StageMode.PREVIEW and _preview != null:
		return _preview as Node3D
	return _player


## 切模式时把镜头目标换到对应对象：预览跟展示实例，实时跟真实 actor。
func _retarget_camera() -> void:
	if _rig == null:
		return
	_rig.bind(_camera, _camera_target_node(), _view_config(_view))


## 重置镜头：回当前视角配置的初值（相机由 executor 写）。
func _reset_camera() -> void:
	if _rig != null:
		_rig.reset_state()


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
	_add_mark_layer_to(root, "RunwayBed", Vector2(center_x, 0.0), Vector2(length, RUNWAY_HALF_Z * 2.0),
		RUNWAY_BED_BOTTOM, RUNWAY_BED_TOP, COLOR_RUNWAY)
	# 中线：让跑道方向一眼可读，也作为八方向区之外的直行参照。
	_add_mark_layer_to(root, "RunwayCenterLine", Vector2(center_x, 0.0), Vector2(length, 0.10),
		RUNWAY_CENTER_BOTTOM, RUNWAY_CENTER_TOP, COLOR_RUNWAY_CENTER)
	var index := 0
	var x := RUNWAY_MIN_X
	while x <= RUNWAY_MAX_X + 0.001:
		var metre := int(round(x))
		var is_end := index == 0 or x >= RUNWAY_MAX_X - 0.001
		var width := RUNWAY_HALF_Z * 2.0 if is_end else (0.16 if metre % 10 == 0 else 0.08)
		var colour := COLOR_STRIPE
		_add_mark_layer_to(root, "Stripe%02d" % index, Vector2(x, 0.0), Vector2(width, RUNWAY_HALF_Z * 2.0),
			STRIPE_BOTTOM, STRIPE_TOP, colour)
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
	_add_disc_to(root, "TurnPadDisc", TURN_PAD_CENTER, TURN_PAD_RADIUS, PAD_DISC_BOTTOM, PAD_DISC_TOP, COLOR_TURN_PAD)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		var centre := TURN_PAD_CENTER + direction * (TURN_PAD_RADIUS * 0.5)
		var spoke := _add_mark_layer_to(root, "Spoke%d" % index, Vector2(centre.x, centre.z),
			Vector2(0.14, TURN_PAD_RADIUS), SPOKE_BOTTOM, SPOKE_TOP, COLOR_TURN_SPOKE)
		spoke.rotation.y = angle
	_add_ring_to(root, "TurnPadRing", TURN_PAD_CENTER, TURN_PAD_RADIUS - 0.10, TURN_PAD_RADIUS + 0.10,
		PAD_RING_BOTTOM, PAD_RING_TOP, COLOR_TURN_SPOKE)
	_add_label_to(root, "TurnPadLabel", TURN_PAD_CENTER + Vector3(0.0, 0.22, -TURN_PAD_RADIUS - 0.8),
		"八方向 / 急转区", 0.28, Color(0.360784, 0.219608, 0.160784, 1.0))


## 御剑起降区：起降盘 + 高度环；环高度是绝对高度参照，不是 Hardcode 的手感结论。
func _build_flight_pad() -> void:
	var root := Node3D.new()
	root.name = "FlightPad"
	add_child(root)
	_add_disc_to(root, "FlightPadDisc", FLIGHT_PAD_CENTER, FLIGHT_PAD_RADIUS, PAD_DISC_BOTTOM, PAD_DISC_TOP, COLOR_FLIGHT_PAD)
	_add_ring_to(root, "FlightPadRing", FLIGHT_PAD_CENTER, FLIGHT_PAD_RADIUS - 0.12, FLIGHT_PAD_RADIUS + 0.12,
		PAD_RING_BOTTOM, PAD_RING_TOP, COLOR_FLIGHT_RING)
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
	_add_mark_layer_to(root, "RulerBase", Vector2(RULER_X, RULER_Z), Vector2(RULER_BAND_WIDTH + 0.5, 0.5),
		RULER_BASE_BOTTOM, RULER_BASE_TOP, Color(0.733333, 0.725490, 0.701961, 1.0))
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
	# 场景不认识 CapabilityManager 与任何具体能力：能力与御剑视觉的装配由 swordsman.tscn /
	# ActorAssembly / FlightBundle 负责（铁律 2）。本场景只**只读**读取已绑定结果：
	# 正式角色缺剑是装配缺陷，必须启动即断言，不做场景侧兜底新建（那会违反 owner 契约）。
	assert(actor.flight_visual_node() != null,
		"motion_stage: 角色缺少御剑视觉绑定（FlightBundle 应由装配负责装配飞剑）")
	# reset_motion 会清输入与御剑状态，因此先重置、再写落点与朝向。
	actor.reset_motion()
	actor.global_position = SPAWN_POSITION
	actor.set_aim_direction(SPAWN_AIM)


## 只读：御剑视觉节点（供验收脚本断言飞行状态与视觉一致）。
## 只读 actor 的公开绑定结果，不扫描节点树、不认领别人的视觉。
func flight_visual() -> Node3D:
	return _player.flight_visual_node() if _player != null else null


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
	if _preview != null:
		# 预览复位只动它自己的局部时钟与姿态；不 pause 场景树、不改 Engine.time_scale。
		_preview.call("reset_preview")
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
		# S2 P0：模式与预览读数并入同一只读聚合，测试不需要访问私有成员。
		"mode": _mode,
		"mode_name": mode_name(),
		"preview": preview_snapshot(),
		"realtime": realtime_snapshot(),
		"foot_sliding": foot_sliding_status(),
	}


# --- HUD --------------------------------------------------------------------


func _build_hud() -> void:
	# 共享 HUD（S0 变体）承担标题 / 状态 / 返回与通用按钮行；本场景不自建面板与字号 override。
	var hud = LAB_HUD_SCRIPT.new()
	_hud = hud
	add_child(_hud)
	# 短 kicker + 短 hint：LabHud 的 Label 不自动换行，长文案会在 960×640 下撑宽面板。
	# 完整操作说明与实验问题放折叠详情（H / F1）与 tooltip，不常显。
	_hud.configure("", "人物动作工作台", "程序预览 · M 实时 · H 详情")
	_hud.set_controls("WASD 移动 · Space 跳跃/预览播放 · Ctrl 下降 · F 御剑 · M 实时/预览模式 · "
		+ "1/2/3 正面/侧面/斜侧机位 · 滚轮缩放 · R 重置 · H 详情 · Esc 返回子实验目录")
	_hud.set_question("待机、起步、跑动、跳跃、御剑及其过渡是否清楚？")
	_hud.return_pressed.connect(_return_to_hub)
	# 返回文案必须如实指向移动子实验目录（不是顶层实验目录）。
	_hud.set_return_text("返回子实验目录")

	# 模式开关：界面上必须能一眼看出当前是「实时运动」还是「程序动作预览」。
	_mode_button = Button.new()
	_mode_button.name = "ModeButton"
	# 按钮文案必须自解释：它是「切到另一个模式」的动作，不是当前状态标签。
	# 空文案会留下一个 150×34 的空白按钮（可见验收缺陷），因此文案在 _update_mode_button() 里统一写。
	_mode_button.custom_minimum_size = Vector2(150, 34)
	_mode_button.focus_mode = Control.FOCUS_ALL
	_mode_button.pressed.connect(func() -> void:
		_apply_mode(StageMode.PREVIEW if _mode == StageMode.REALTIME else StageMode.REALTIME, false))
	_hud.add_button(_mode_button)
	_update_mode_button()

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置 (R)"
	reset_button.custom_minimum_size = Vector2(96, 34)
	reset_button.pressed.connect(_reset_experiment)
	_hud.add_button(reset_button)

	for index in range(VIEW_NAMES.size()):
		var view_button := Button.new()
		view_button.name = "View%d" % index
		view_button.text = VIEW_NAMES[index]
		view_button.custom_minimum_size = Vector2(56, 34)
		view_button.pressed.connect(_apply_view.bind(index, false))
		_hud.add_button(view_button)

	_build_preview_panel()


## 动作选择 / 播放专用紧凑面板：挂在独立的右侧中列，不塞进 LabHud 按钮行。
## 面板自带 HFlowContainer 包裹，窄窗自动换行；整合者后续统一排版时只需调整本函数。
func _build_preview_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewOverlay"
	layer.layer = 2
	add_child(layer)

	var margin := MarginContainer.new()
	margin.name = "PreviewMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	layer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 面板靠右下：人物在画面中心，面板若居中偏右会在 960×640 下压住模型
	#（实测 960×640 时人物 x≈460、面板从 x≈440 起）。底部对齐后 1280×720 与
	# 1920×1080 同样不遮人物，构图不随分辨率变化。
	var column := VBoxContainer.new()
	column.name = "PreviewColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	margin.add_child(column)

	var row := HBoxContainer.new()
	row.name = "PreviewRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)

	var panel := MotionPreviewPanel.new()
	panel.name = "PreviewPanel"
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(268, 0)
	row.add_child(panel)
	_panel = panel

	# 动作按钮由本场景按动作注册表构建（面板不硬编码动作列表）。
	for action in MotionPreviewAction.library():
		panel.add_action_button(action.title, action.id)
		_action_ids.append(action.id)
	panel.action_selected.connect(_on_action_selected)
	panel.play_toggled.connect(_toggle_preview_playing)
	panel.step_requested.connect(_step_preview)
	panel.loop_toggled.connect(_set_preview_loop)
	panel.rate_selected.connect(_set_preview_rate)
	panel.ab_requested.connect(_ab_preview)


## 预览展示实例：与正式角色同共享 Visual 装配，但没有任何物理与能力。
func _build_preview() -> void:
	var display := MotionPreviewDisplay.new()
	assert(display != null, "motion_stage: 预览展示实例创建失败")
	display.name = "MotionPreview"
	display.position = PREVIEW_POSITION
	# 预览朝向必须与实时角色一致：机位标签（正面 / 侧面 / 斜侧）是按 SPAWN_AIM = +X 定义的，
	# 预览若停在默认 −Z，同一按钮在两种模式下拍到的是不同的面（标签颠倒）。
	# 必须在 add_child 之前注入：_ready() 会据此推导初始 heading。
	display.initial_aim = SPAWN_AIM
	add_child(display)
	# 剖面物理参数一次性从真实运动组件注入：组件调 jump_speed / gravity / lift / sink / move_speed
	# 之后，预览剖面跟着变，不会与真实手感分叉（预览包自身不写死这些常量）。
	if _motion != null:
		display.apply_params(MotionPreviewParams.from_motion(_motion))
	_preview = display


# --- 模式与预览编排 ---------------------------------------------------------


## 切模式：实时运动（真实 actor 物理真值）/ 程序动作预览（独立展示实例）。
## 进入预览先把真实 actor 的输入清干净并停止预览播放；回到实时则停止预览时钟。
## 两模式都不改 Engine.time_scale、不 pause 场景树、不禁用 actor 的物理推进。
func _apply_mode(mode: int, force: bool) -> void:
	var next := clampi(mode, StageMode.REALTIME, StageMode.PREVIEW)
	if not force and next == _mode:
		return
	_mode = next
	_update_mode_button()
	if _preview != null:
		var state: MotionPreviewState = _preview.state()
		state.playing = false
		if _mode == StageMode.REALTIME:
			_preview.reset_preview()
	_clear_pressed()
	# 真实输入模式下才允许按键驱动角色；切走时清掉已按住的输入，且每帧继续写零。
	if _player != null:
		_player.clear_input()
	# 镜头目标随模式切换：预览跟展示实例，实时跟真实 actor。
	_retarget_camera()
	if _panel != null:
		_panel.visible = _mode == StageMode.PREVIEW
	_update_hud()


## 只读：镜头装配（唯一 executor）。验收据此断言镜头所有权与模式，不直接摸 Camera3D。
func rig() -> CameraRig:
	return _rig


## 模式按钮文案：说明点下去会切到哪个模式（不是当前模式标签）。
func _update_mode_button() -> void:
	if _mode_button == null:
		return
	if _mode == StageMode.REALTIME:
		_mode_button.text = "切到预览 (M)"
		_mode_button.tooltip_text = "切到程序动作预览（独立展示实例，无骨骼 clip）"
	else:
		_mode_button.text = "切到实时 (M)"
		_mode_button.tooltip_text = "切回实时运动（真实 actor 物理真值）"


func mode() -> int:
	return _mode


func mode_name() -> String:
	return MODE_NAMES[_mode]


func preview() -> Node3D:
	return _preview


func preview_panel() -> PanelContainer:
	return _panel


## 预览只读快照（含动作、时钟、过渡、表现姿态）；无预览实例时返回空字典。
func preview_snapshot() -> Dictionary:
	if _preview == null or not _preview.has_method("preview_snapshot"):
		return {}
	return _preview.call("preview_snapshot") as Dictionary


## 实时模式只读快照：物理真值全部来自 actor（预览不参与）。
func realtime_snapshot() -> Dictionary:
	if _player == null or _motion == null:
		return {}
	return {
		"position": _player.global_position,
		"velocity": _motion.actual_velocity,
		"horizontal_speed": Vector2(_motion.actual_velocity.x, _motion.actual_velocity.z).length(),
		"on_floor": _motion.on_floor,
		"flight_active": _motion.flight_active,
		"aim_direction": _motion.aim_direction,
		"move_input": _motion.move_input,
		"vertical_input": _motion.vertical_input,
		"physics_ticks": _physics_ticks,
		"jump_edges": _jump_edges,
		"flight_edges": _flight_edges,
	}


## 足滑度量状态：socket 尚未建立，当前一律标注「待建立」。
## 步幅匹配（速度 / stride_meters）不是足滑度量，不得用它冒充。
func foot_sliding_status() -> String:
	return "待建立（需 Visual/Sockets/Foot_* 世界位置；当前无 socket）"


func _toggle_preview_playing() -> void:
	if _preview == null:
		return
	var state: MotionPreviewState = _preview.state()
	state.playing = not state.playing
	_update_hud()


func _step_preview() -> void:
	if _preview == null:
		return
	_preview.call("step_once")
	_update_hud()


func _on_action_selected(action_id: StringName) -> void:
	if _preview == null:
		return
	_preview.call("select_action", action_id)
	_update_hud()


func _set_preview_loop(enabled: bool) -> void:
	if _preview == null:
		return
	var state: MotionPreviewState = _preview.state()
	state.looping = enabled
	_update_hud()


func _set_preview_rate(value: float) -> void:
	if _preview == null:
		return
	var state: MotionPreviewState = _preview.state()
	state.rate = maxf(value, 0.01)
	_update_hud()


## A-B 过渡：在「当前动作」与「上一动作」之间再做一次 A→B 插值。
func _ab_preview() -> void:
	if _preview == null:
		return
	var state: MotionPreviewState = _preview.state()
	var straight := state.current
	var blend := state.previous
	if straight == null or blend == null or blend == straight:
		_update_hud()
		return
	state.select(blend.id)
	state.select(straight.id)
	_update_hud()


# --- 读数刷新 ---------------------------------------------------------------


## 只读组件与表现快照，不写任何运动状态。
## 两种模式分开读数：实时运动读 actor 物理真值；程序动作预览读独立展示实例的预览快照。
## 任何模式都不读 _legs / _arms 私有字段。
func _update_hud() -> void:
	if _hud == null or _motion == null or _player == null:
		return
	var realtime := realtime_snapshot()
	var velocity: Vector3 = realtime.get("velocity", Vector3.ZERO)
	var move: Vector2 = realtime.get("move_input", Vector2.ZERO)
	# 状态行必须与当前模式一致：预览模式不能显示正式 actor 的着地 / 御剑（那会误导读数）。
	if _mode == StageMode.REALTIME:
		_hud.set_status("实时运动  ·  着地=%s  御剑=%s  水平 %.2f m/s" % [
			"是" if realtime.get("on_floor", false) else "否",
			"是" if realtime.get("flight_active", false) else "否",
			float(realtime.get("horizontal_speed", 0.0)),
		])
	else:
		var preview_status := preview_snapshot()
		if preview_status.is_empty():
			_hud.set_status("程序动作预览  ·  展示实例缺失")
		else:
			# 状态行只说「在看哪个动作、是否在播」；时间 / 倍率读数归核心摘要，避免两行重复同一内容。
			_hud.set_status("程序动作预览  ·  %s  ·  %s" % [
				str(preview_status.get("action_title", "")),
				"播放中" if preview_status.get("playing", false) else "已暂停",
			])
	_hud.set_core_summary(_core_summary_text())
	var lines := PackedStringArray()
	lines.append("模式  %s（M 或右上按钮切换）" % mode_name())
	lines.append("实时输入  move=(%+.2f, %+.2f)  升降=%+.0f  跳跃边沿=%d  御剑边沿=%d  物理帧=%d" % [
		move.x, move.y,
		float(realtime.get("vertical_input", 0.0)),
		int(realtime.get("jump_edges", 0)),
		int(realtime.get("flight_edges", 0)),
		int(realtime.get("physics_ticks", 0)),
	])
	lines.append("实时速度  v=(%+.2f, %+.2f, %+.2f)  水平 %.2f m/s" % [
		velocity.x, velocity.y, velocity.z, float(realtime.get("horizontal_speed", 0.0)),
	])
	lines.append("实时状态  着地=%s  御剑=%s  高度=%.2f m  朝向=(%+.2f, %+.2f)" % [
		"是" if realtime.get("on_floor", false) else "否",
		"是" if realtime.get("flight_active", false) else "否",
		_player.global_position.y,
		float(realtime.get("aim_direction", Vector3.ZERO).x),
		float(realtime.get("aim_direction", Vector3.ZERO).z),
	])
	lines.append("实时表现  " + _pose_text(presentation_state()))
	var preview := preview_snapshot()
	if preview.is_empty():
		lines.append("预览  展示实例缺失")
	else:
		lines.append("预览  动作=%s  来源=%s  播放=%s  循环=%s  倍率=%s" % [
			str(preview.get("action_title", "")),
			"程序近似（无骨骼 clip）" if str(preview.get("source", "")) == "program" else str(preview.get("source", "")),
			"是" if preview.get("playing", false) else "否",
			"是" if preview.get("looping", true) else "否",
			str(preview.get("rate", 1.0)),
		])
		lines.append("预览时钟  局部 t=%.3f / %.2f s  进度=%.2f  过渡=%.2f%s  单步=%.4f s×倍率" % [
			float(preview.get("local_time", 0.0)),
			float(preview.get("duration", 0.0)),
			float(preview.get("progress", 0.0)),
			float(preview.get("transition", 1.0)),
			"（进行中）" if preview.get("transitioning", false) else "",
			float(preview.get("step_seconds", 0.0)),
		])
		lines.append("预览表现  " + _pose_text(preview.get("pose", {})))
		lines.append("预览飞剑  显隐=%s" % ("是" if preview.get("sword_visible", false) else "否"))
	lines.append("足滑度量  %s" % foot_sliding_status())
	lines.append("步幅匹配  stride_meters=%.2f m（与足滑是两件事，不互相替代）" % _stride_meters())
	lines.append("视角  %s（%s）" % [view_name(), VIEW_HINT[_view]])
	_hud.set_debug_lines(lines)


## 顶部核心摘要：模式 + 被观察对象 + 当前时间读数，一行读完「现在在看什么」。
func _core_summary_text() -> String:
	if _mode == StageMode.PREVIEW:
		var preview := preview_snapshot()
		if preview.is_empty():
			return "程序动作预览 · 展示实例缺失"
		# 核心摘要 = 预览时钟读数：局部时间 / 进度 / 倍率 / 过渡；不重复状态行已有的动作名与播放态。
		return "局部时钟 t=%.2f/%.2fs（%.0f%%） · 倍率 %.2fx%s · 不写全局时间" % [
			float(preview.get("local_time", 0.0)),
			float(preview.get("duration", 0.0)),
			float(preview.get("progress", 0.0)) * 100.0,
			float(preview.get("rate", 1.0)),
			" · A-B 过渡中" if preview.get("transitioning", false) else "",
		]
	var velocity: Vector3 = _motion.actual_velocity if _motion != null else Vector3.ZERO
	return "实时运动（物理真值） · 水平 %.2f m/s · 着地=%s" % [
		Vector2(velocity.x, velocity.z).length(),
		"是" if _motion != null and _motion.on_floor else "否",
	]


## 步幅参数：从表现层导出参数读取（正式角色与预览实例同源）。
func _stride_meters() -> float:
	if _presentation != null:
		var value: Variant = _presentation.get("stride_meters")
		if value != null:
			return float(value)
	return 1.8


## 表现摘要：只读 pose_state() 快照字段（clock / gait / phase / 增益 / 躯干），不碰私有枢轴。
func _pose_text(pose: Dictionary) -> String:
	if pose.is_empty():
		return "表现节点缺失（三能力不受影响）"
	return "t=%.2f  gait=%.2f  phase=%.2f  flight=%.2f  左腿=%+.2f  右腿=%+.2f  左臂=%+.2f  躯干俯仰=%+.3f  起伏=%+.3f" % [
		float(pose.get("clock", 0.0)),
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
## 一律不透明：transparency 强制关闭、alpha 归一为 1.0，透明排序不参与地面绘制。
func _mark_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
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


## 水平量具：底面 / 顶面显式给定，中心由两端推出，结构上不可能出现零间隙或体积交叠。
func _add_mark_layer_to(parent: Node, mark_name: String, centre_xz: Vector2, footprint: Vector2,
		bottom: float, top: float, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(footprint.x, top - bottom, footprint.y)
	var instance := MeshInstance3D.new()
	instance.name = mark_name
	instance.mesh = mesh
	instance.material_override = _mark_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(centre_xz.x, (bottom + top) * 0.5, centre_xz.y)
	parent.add_child(instance)
	return instance


## 圆盘：同样只接受底面 / 顶面，中心由两端推出。
func _add_disc_to(parent: Node, disc_name: String, centre: Vector3, radius: float,
		bottom: float, top: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = top - bottom
	mesh.radial_segments = 48
	mesh.rings = 0
	var instance := MeshInstance3D.new()
	instance.name = disc_name
	instance.mesh = mesh
	instance.material_override = _mark_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = centre + Vector3(0.0, (bottom + top) * 0.5, 0.0)
	parent.add_child(instance)
	return instance


## 平放的圆环：真实矩形截面环带（内 / 外半径 + 厚度），替代原先管半径 0.10 的 Torus。
## 顶面 / 底面严格落在给定高度，不再穿地或切进盘体。
func _add_ring_to(parent: Node, ring_name: String, centre: Vector3, inner_radius: float, outer_radius: float,
		bottom: float, top: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = ring_name
	instance.mesh = _flat_ring_mesh(inner_radius, outer_radius, top - bottom)
	instance.material_override = _mark_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = centre + Vector3(0.0, (bottom + top) * 0.5, 0.0)
	parent.add_child(instance)
	return instance


## SurfaceTool 程序生成矩形截面水平环带：外壁 / 内壁 / 顶面 / 底面四个环面。
## 网格以原点为中心、厚度沿 ±Y 各占一半；节点位置负责把顶 / 底面落到目标高度。
func _flat_ring_mesh(inner_radius: float, outer_radius: float, thickness: float) -> ArrayMesh:
	var segments := 64
	var half := thickness * 0.5
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(segments):
		var angle0 := TAU * float(index) / float(segments)
		var angle1 := TAU * float(index + 1) / float(segments)
		var inner0 := Vector3(cos(angle0) * inner_radius, 0.0, sin(angle0) * inner_radius)
		var inner1 := Vector3(cos(angle1) * inner_radius, 0.0, sin(angle1) * inner_radius)
		var outer0 := Vector3(cos(angle0) * outer_radius, 0.0, sin(angle0) * outer_radius)
		var outer1 := Vector3(cos(angle1) * outer_radius, 0.0, sin(angle1) * outer_radius)
		var up := Vector3(0.0, half, 0.0)
		var down := Vector3(0.0, -half, 0.0)
		var outward := Vector3(cos(angle0), 0.0, sin(angle0))
		_ring_quad(tool, inner0 + up, outer0 + up, outer1 + up, inner1 + up, Vector3.UP)
		_ring_quad(tool, inner1 + down, outer1 + down, outer0 + down, inner0 + down, Vector3.DOWN)
		_ring_quad(tool, outer0 + up, outer0 + down, outer1 + down, outer1 + up, outward)
		_ring_quad(tool, inner0 + down, inner0 + up, inner1 + up, inner1 + down, -outward)
	return tool.commit() as ArrayMesh


## 把四边形拆成两个三角形；法线显式给定，不依赖 generate_normals 的绕序推断。
func _ring_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
	tool.add_vertex(a)
	tool.add_vertex(c)
	tool.add_vertex(d)


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
