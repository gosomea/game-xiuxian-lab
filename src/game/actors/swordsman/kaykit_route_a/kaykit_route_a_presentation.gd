class_name KaykitRouteAPresentation
extends Node3D

## 路线 A 骨骼动画表现层（纯表现）：直接用 KayKit 原生 GLB 骨架与 76 clips，不经重定向。
##
## 公开 API（与 CultivatorSkeletonPresentation 同形状 + 路线 A 专用入口）：
##   set_motion_state(motion_mode, speed, is_grounded)  ← 本轮要求的公共 API
##   advance_state(state, delta) / sample_state()      ← 接入宿主 motion() 的自动路径
##   pose_state() / reset_pose()                        ← 只读快照与归零
##
## 职责边界（与既有骨骼表现层一致）：
## - 只读 motion() 的 actual_velocity / on_floor / flight_active；不写 Component、
##   不新增 Capability、不移动物理根。删除本节点后角色行为与碰撞完全不变。
##
## 动作映射（A/B 受控：阈值与步幅与 CultivatorSkeletonPresentation 完全相同）：
##   idle     = Unarmed_Idle
##   walk     = Walking_A      （阈值 > WALK_SPEED_MPS 0.3）
##   run      = Running_A      （阈值 > RUN_SPEED_MPS 5.5）
##   airborne = Jump_Idle 循环
##   flight   = 优先 Jump_Idle，缺失时回退 idle；恒定 FLIGHT_RATE 0.6 + FLIGHT_LEAN 前倾
##   播放速率 = 实际水平速度 / 动作自然速度（walk 1.6 / run 3.2 m/s）
##   切换统一走 play(clip, BLEND 0.15) 交叉淡化。
##
## 武器处理：KayKit 免费 GLB 自带 5 件展示用武器挂件（挂在 handslot 骨上），
## 它们会随攻击动作摆动、干扰 A/B 观感与 draw call 对照，因此在 _ready 里隐藏。
## 披风 Rogue_Cape（84 tris，刚体挂 chest）保留可见——它正是路线 B 要复现的袍片对照物。

## 角色根（Swordsman）；本节点挂在 Visual 下，默认向上两层。
@export var actor_path: NodePath = ^"../.."
## KayKit 模型实例；动画、武器与披风查找只允许在这个子树内，避免误碰同层道具。
@export var model_root_path: NodePath = ^"../KaykitRogueHooded"
## true = 每帧读宿主 motion()（正式角色）；false = 外部用 set_motion_state()/advance_state() 显式驱动。
@export var auto_read_actor: bool = true
## 一个 walk 步周期覆盖的距离（米）：播放速率 = 速度 / 该值。
@export var walk_stride_meters: float = 1.6
## 一个 run 步周期覆盖的距离（米）。
@export var run_stride_meters: float = 3.2
## 御剑前倾（弧度，21 度）。
@export_range(0.0, 1.0, 0.001) var flight_lean: float = deg_to_rad(21.0)

## 与既有骨骼表现层逐字相同的常量——A/B 对照不得只为其中一条路线调阈值。
const WALK_SPEED_MPS := 0.3
const RUN_SPEED_MPS := 5.5
const BLEND := 0.15
const FLIGHT_RATE := 0.6

## motion_mode 取值。
const MODE_GROUND := "ground"
const MODE_AIR := "air"
const MODE_FLIGHT := "flight"

## 路线 A 的 clip 映射（KayKit 原生命名，非 Mixamo 的 idle/walk/run/jump）。
const CLIP_IDLE := "Unarmed_Idle"
const CLIP_WALK := "Walking_A"
const CLIP_RUN := "Running_A"
const CLIP_AIRBORNE := "Jump_Idle"

## 上游 GLB 自带的 5 件展示用武器挂件：隐藏，但不删除资源。
const HIDDEN_WEAPON_PARTS: Array[String] = [
	"Knife",
	"Knife_Offhand",
	"1H_Crossbow",
	"2H_Crossbow",
	"Throwable",
]
## 必须保持可见的袍片（路线 B 的对照物）。
const KEPT_CAPE_PART := "Rogue_Cape"

## 宿主用 Node 而非 Node3D：表现层可被挂在任意容器下独立实例化（演示台/测试夹具），
## 只要 auto_read_actor=false 就不要求宿主是 Node3D。
var _actor: Node
var _player: AnimationPlayer
var _model: Node3D
var _model_instance: Node3D
var _current := ""
var _clock := 0.0
var _mode := MODE_GROUND
var _lean_target := 0.0
var _hidden: Array[String] = []

## 最近一次只读快照：预览 HUD 与验收脚本读取，不参与物理。
var _pose: Dictionary = {}


func _ready() -> void:
	_actor = get_node_or_null(actor_path) if not actor_path.is_empty() else null
	if auto_read_actor:
		assert(_actor != null, "KaykitRouteAPresentation: actor_path 未指向角色根（%s）" % actor_path)
		assert(_actor.has_method("motion"), "KaykitRouteAPresentation: 角色根缺少 motion() 读取接口")
	_model = get_parent() as Node3D
	assert(_model != null, "KaykitRouteAPresentation: 必须挂在模型节点下")
	_model_instance = get_node_or_null(model_root_path) as Node3D
	assert(_model_instance != null,
		"KaykitRouteAPresentation: model_root_path 未指向 KayKit 模型实例（%s）" % model_root_path)
	var players := _model_instance.find_children("*", "AnimationPlayer", true, false)
	assert(players.size() == 1,
		"KaykitRouteAPresentation: 应恰好 1 个 AnimationPlayer，实际 %d" % players.size())
	_player = players[0] as AnimationPlayer
	# 断言映射所需的 4 条 clip 真实可达（原生 76 clips，不做任何重命名/重定向）。
	for clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_AIRBORNE]:
		assert(_player.has_animation(clip),
			"KaykitRouteAPresentation: 缺少动作 %s（GLB 导出 clips=%s）"
			% [clip, _player.get_animation_list()])
	_configure_looping()
	_hide_weapons()
	_assert_cape_kept()
	reset_pose()


func _process(delta: float) -> void:
	if auto_read_actor:
		advance_state(sample_state(), delta)
	update_visuals(delta)


## 隐藏上游自带的 5 件武器挂件（资源本身保留，仅不可见）。
func _hide_weapons() -> void:
	_hidden.clear()
	for part_name in HIDDEN_WEAPON_PARTS:
		var found := _model_instance.find_children(part_name, "MeshInstance3D", true, false)
		for node in found:
			var mesh_instance := node as MeshInstance3D
			mesh_instance.visible = false
			_hidden.append(part_name)
	assert(_hidden.size() == HIDDEN_WEAPON_PARTS.size(),
		"KaykitRouteAPresentation: 应隐藏 %d 件武器，实际匹配 %d 件（%s）"
		% [HIDDEN_WEAPON_PARTS.size(), _hidden.size(), str(_hidden)])


## 披风必须保留可见：它是路线 B 袍片对照的锚点。
func _assert_cape_kept() -> void:
	var capes := _model_instance.find_children(KEPT_CAPE_PART, "MeshInstance3D", true, false)
	assert(capes.size() == 1,
		"KaykitRouteAPresentation: 应恰好保留 1 片披风 %s，实际 %d" % [KEPT_CAPE_PART, capes.size()])
	assert((capes[0] as MeshInstance3D).visible,
		"KaykitRouteAPresentation: 披风 %s 必须保持可见" % KEPT_CAPE_PART)


## glTF 导入的 KayKit clips 默认是 LOOP_NONE；若不显式修正，走跑约一个周期后会停住，
## 但状态快照仍会误报当前 gait。四个持续状态动作必须在运行时线性循环。
func _configure_looping() -> void:
	for clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_AIRBORNE]:
		var animation := _player.get_animation(clip)
		assert(animation != null, "KaykitRouteAPresentation: 无法读取动作 %s" % clip)
		animation.loop_mode = Animation.LOOP_LINEAR


## 只读采样：宿主 motion() 的物理真值，形状与 CultivatorSkeletonPresentation 一致。
func sample_state() -> Dictionary:
	if _actor == null:
		return {}
	var motion: Object = _actor.call("motion")
	if motion == null:
		return {}
	return {
		"velocity": motion.get("actual_velocity") as Vector3,
		"grounded": bool(motion.get("on_floor")),
		"flying": bool(motion.get("flight_active")),
		"aim": motion.get("aim_direction") as Vector3,
	}


## 共享推进：actor 路径与显式驱动路径共用。只写表现层自身状态与 AnimationPlayer。
func advance_state(state: Dictionary, delta: float) -> void:
	if state.is_empty():
		return
	_clock += delta
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var grounded: bool = state.get("grounded", true)
	var flying: bool = state.get("flying", false)
	var mode := MODE_GROUND
	if flying:
		mode = MODE_FLIGHT
	elif not grounded:
		mode = MODE_AIR
	set_motion_state(mode, flat.length(), grounded)


## 路线 A 的公共 API：一次调用完成「模式 + 速度 + 着地」到 clip 的解析。
## motion_mode ∈ {MODE_GROUND, MODE_AIR, MODE_FLIGHT}；未知值按 MODE_GROUND 处理。
func set_motion_state(motion_mode: String, speed: float, is_grounded: bool) -> void:
	var mode := motion_mode if motion_mode in [MODE_GROUND, MODE_AIR, MODE_FLIGHT] else MODE_GROUND
	_mode = mode
	var safe_speed := maxf(speed, 0.0)

	var target := ""
	var rate := 1.0
	var lean := 0.0
	if mode == MODE_FLIGHT:
		# 御剑：优先 Jump_Idle；缺失时回退 idle。前倾 21 度。
		target = CLIP_AIRBORNE if _player.has_animation(CLIP_AIRBORNE) else CLIP_IDLE
		rate = FLIGHT_RATE
		lean = flight_lean
	elif mode == MODE_AIR or not is_grounded:
		# 腾空：Jump_Idle 循环（不播 Jump_Start，避免落回地面时残留单次尾帧）。
		target = CLIP_AIRBORNE
	elif safe_speed > RUN_SPEED_MPS:
		target = CLIP_RUN
		rate = safe_speed / maxf(run_stride_meters, 0.01)
	elif safe_speed > WALK_SPEED_MPS:
		target = CLIP_WALK
		rate = safe_speed / maxf(walk_stride_meters, 0.01)
	else:
		target = CLIP_IDLE

	if target != _current:
		_current = target
		_player.play(target, BLEND)
	# 切换动作的第一帧也必须同步播放速率；否则每次切换都会以旧速率播放一帧，
	# 在低帧率或反复起停时形成可见脚步脉冲。
	if target == CLIP_WALK or target == CLIP_RUN:
		_player.speed_scale = clampf(rate, 0.5, 2.5)
	else:
		_player.speed_scale = rate
	_lean_target = lean
	_record_pose(safe_speed, is_grounded)


## 只倾斜模型节点（表现层），与既有刚体版/骨骼版的 body 前倾同语义。
func update_visuals(delta: float) -> void:
	if _model == null:
		return
	_model.rotation.x = lerpf(_model.rotation.x, -_lean_target, minf(delta * 6.0, 1.0))


## 回到中性姿态（预览循环起点用）。
func reset_pose() -> void:
	_clock = 0.0
	_current = CLIP_IDLE
	_mode = MODE_GROUND
	_lean_target = 0.0
	if _player != null:
		_player.speed_scale = 1.0
		_player.play(CLIP_IDLE, BLEND)
	if _model != null:
		_model.rotation.x = 0.0
	_record_pose(0.0, true)


## 只读快照：键与既有骨骼表现层兼容，另加路线 A 的 mode/lean/hidden 诊断键。
func pose_state() -> Dictionary:
	return _pose.duplicate()


## 已隐藏的武器件名（只读，供验收核对）。
func hidden_parts() -> Array[String]:
	return _hidden.duplicate()


func _record_pose(speed: float, grounded: bool) -> void:
	_pose = {
		"clock": _clock,
		"gait": 1.0 if _current == CLIP_WALK or _current == CLIP_RUN else 0.0,
		"phase": _player.current_animation_position if _player != null else 0.0,
		"current_clip": _current,
		"speed": speed,
		"grounded": grounded,
		"flying": _mode == MODE_FLIGHT,
		"motion_mode": _mode,
		"lean_target": _lean_target,
		"play_rate": _player.speed_scale if _player != null else 1.0,
		"hidden_parts": _hidden.duplicate(),
	}
