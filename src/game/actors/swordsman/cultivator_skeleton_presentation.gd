class_name CultivatorSkeletonPresentation
extends Node3D

## 骨骼动画表现层（纯表现）：读 motion() 快照驱动 AnimationPlayer 的动作混合。
##
## 与 CultivatorPresentation（分件刚体版）同 API 形状，便于互换与预览驱动：
##   auto_read_actor / actor_path / advance_state(state, delta) / sample_state()
##   / pose_state() / reset_pose()
##
## 职责边界（与刚体版一致）：
## - 只读 motion() 的 actual_velocity / on_floor / flight_active；不写 Component、
##   不新增 Capability、不移动物理根。删除本节点后角色行为与碰撞完全不变。
##
## 动作映射（速度同步防滑步）：
##   御剑  → idle @0.6 倍速 + 前倾 FLIGHT_LEAN
##   空中  → jump（单次，播完保持末帧）
##   着地  → speed > RUN_SPEED_MPS → run；> WALK_SPEED_MPS → walk；否则 idle
##   播放速率 = 实际水平速度 / 动作自然速度（walk 1.6 / run 3.2 m/s，实测 Mixamo 步幅近似值）
## 切换统一走 play(clip, BLEND) 交叉淡化。

## 角色根（Swordsman）；本节点挂在 Visual 下，默认向上两层。
@export var actor_path: NodePath = ^"../.."
## true = 每帧读宿主 motion()（正式角色）；false = 外部用 advance_state() 显式驱动（预览）。
@export var auto_read_actor: bool = true
## 一个 walk 步周期覆盖的距离（米）：播放速率 = 速度 / 该值。
@export var walk_stride_meters: float = 1.6
## 一个 run 步周期覆盖的距离（米）。
@export var run_stride_meters: float = 3.2
## 御剑前倾（弧度）。
@export var flight_lean: float = 0.21

const WALK_SPEED_MPS := 0.3
const RUN_SPEED_MPS := 5.5
const BLEND := 0.15
const IDLE_FLIGHT_RATE := 0.6

## 循环动作：持续状态必须线性循环，否则一个周期后停在末帧而快照仍报当前 gait。
const LOOPING_CLIPS: Array[String] = ["idle", "walk", "run"]
## 单次动作：jump 播完保持末帧（空中状态）。
const ONESHOT_CLIPS: Array[String] = ["jump"]

var _actor: Node3D
var _player: AnimationPlayer
var _model: Node3D
var _current := ""
var _clock := 0.0
## true = 预览式外部驱动：AnimationPlayer 走 MANUAL，由 advance_state() 的 delta 推进。
var _manual_advance := false

## 最近一次只读快照：预览 HUD 与验收脚本读取，不参与物理。
var _pose: Dictionary = {}


func _ready() -> void:
	_actor = get_node_or_null(actor_path) if not actor_path.is_empty() else null
	if auto_read_actor:
		assert(_actor != null, "CultivatorSkeletonPresentation: actor_path 未指向角色根（%s）" % actor_path)
		assert(_actor.has_method("motion"), "CultivatorSkeletonPresentation: 角色根缺少 motion() 读取接口")
	_model = get_parent() as Node3D
	assert(_model != null, "CultivatorSkeletonPresentation: 必须挂在模型节点下")
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	assert(players.size() == 1,
		"CultivatorSkeletonPresentation: 应恰好 1 个 AnimationPlayer，实际 %d" % players.size())
	_player = players[0] as AnimationPlayer
	for clip in ["idle", "walk", "run", "jump"]:
		assert(_player.has_animation(clip),
			"CultivatorSkeletonPresentation: 缺少动作 %s（GLB 导出 clips=%s）"
			% [clip, _player.get_animation_list()])
	_configure_looping()
	# 预览路径（auto_read_actor=false）不接受引擎帧驱动：调用方在任意时刻用任意 delta 调
	# advance_state()，包括同一帧内连续多次。若让 AnimationPlayer 仍按渲染帧自走，同一帧里
	# 推进 20 次只有 1 次有效，phase 几乎不动，HUD 与验收读到的播放位置就是假的。
	# 因此手动路径把 mixer 切到 MANUAL，改为由 advance_state() 按传入 delta 显式推进。
	if not auto_read_actor:
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_manual_advance = true
	_player.play("idle")


## glTF 导入的 clip 默认是 LOOP_NONE（实测 v9 GLB 四个 clip 全为 0）。若不显式修正，
## idle/walk/run 播放一个周期后停在末帧，但状态快照仍会报当前 gait，形成「不动却报走动」。
## jump 必须保持单次，播完停在末帧供空中状态使用。
func _configure_looping() -> void:
	for clip in LOOPING_CLIPS:
		var animation := _player.get_animation(clip)
		assert(animation != null, "CultivatorSkeletonPresentation: 无法读取动作 %s" % clip)
		animation.loop_mode = Animation.LOOP_LINEAR
	for clip in ONESHOT_CLIPS:
		var animation := _player.get_animation(clip)
		assert(animation != null, "CultivatorSkeletonPresentation: 无法读取动作 %s" % clip)
		animation.loop_mode = Animation.LOOP_NONE


func _process(delta: float) -> void:
	if not auto_read_actor:
		return
	advance_state(sample_state(), delta)


## 只读采样：宿主 motion() 的物理真值，形状与刚体版一致。
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


## 共享推进：actor 路径（渲染帧 delta）与预览路径（显式 delta）共用。
## 只写表现层自身状态与 AnimationPlayer，不碰任何 Component。
func advance_state(state: Dictionary, delta: float) -> void:
	if state.is_empty():
		return
	_clock += delta
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var grounded: bool = state.get("grounded", true)
	var flying: bool = state.get("flying", false)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()

	var target := ""
	var rate := 1.0
	if flying:
		target = "idle"
		rate = IDLE_FLIGHT_RATE
	elif not grounded:
		target = "jump"
	elif speed > RUN_SPEED_MPS:
		target = "run"
		rate = speed / maxf(run_stride_meters, 0.01)
	elif speed > WALK_SPEED_MPS:
		target = "walk"
		rate = speed / maxf(walk_stride_meters, 0.01)
	else:
		target = "idle"

	if target != _current:
		_current = target
		_player.play(target, BLEND)
	# 切换动作的第一帧也必须同步播放速率；否则每次 idle -> walk/run 都会以旧速率播放一帧，
	# 在低帧率或反复起停时形成可见脚步脉冲。
	if target == "walk" or target == "run":
		_player.speed_scale = clampf(rate, 0.5, 2.5)
	else:
		_player.speed_scale = rate

	# 手动模式：AnimationPlayer 不自走，由本次调用的 delta 显式推进（见 _ready 注释）。
	# 放在 speed_scale 之后，使本次推进就用上刚设定的速率。
	if _manual_advance:
		_player.advance(delta)

	# 御剑前倾：只倾斜模型节点（表现层），与刚体版的 body 前倾同语义。
	if _model != null:
		var lean := flight_lean if flying else 0.0
		_model.rotation.x = lerpf(_model.rotation.x, -lean, minf(delta * 6.0, 1.0))

	_record_pose(velocity, speed, grounded, flying)


## 回到中性姿态（预览循环起点用）。
func reset_pose() -> void:
	_clock = 0.0
	_current = "idle"
	_player.speed_scale = 1.0
	_player.play("idle", BLEND)
	if _model != null:
		_model.rotation.x = 0.0
	_record_pose(Vector3.ZERO, 0.0, true, false)


## 只读快照：键与刚体版兼容（clock/gait/phase/speed/grounded/flying/current_clip）。
func pose_state() -> Dictionary:
	return _pose.duplicate()


func _record_pose(velocity: Vector3, speed: float, grounded: bool, flying: bool) -> void:
	_pose = {
		"clock": _clock,
		"gait": 1.0 if _current == "walk" or _current == "run" else 0.0,
		"phase": _player.current_animation_position if _player != null else 0.0,
		"current_clip": _current,
		"speed": speed,
		"vertical_speed": velocity.y,
		"grounded": grounded,
		"flying": flying,
	}
