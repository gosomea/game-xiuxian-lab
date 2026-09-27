class_name CultivatorSkeletonPresentation
extends Node3D

## 骨骼动画表现层（纯表现）：读 motion() 快照驱动 AnimationPlayer 的动作混合。
##
## 由正式角色或动作预览调用的表现层接口：
##   auto_read_actor / actor_path / advance_state(state, delta) / sample_state()
##   / pose_state() / reset_pose()
##
## 职责边界：
## - 只读 motion() 的 actual_velocity / on_floor / flight_active；不写 Component、
##   不新增 Capability、不移动物理根。删除本节点后角色行为与碰撞完全不变。
##
## 动作映射（速度同步防滑步）：
##   御剑  → sword_ride（独立的平衡站姿）@1.0；资产没有该 clip 时
##           退回 idle @0.6 倍速 + 前倾 FLIGHT_LEAN
##   空中  → jump（单次，播完保持末帧）
##   着地  → speed >= RUN_SPEED_MPS → run；>= WALK_SPEED_MPS → walk；否则 idle
##   播放速率 = 实际水平速度 / 该动作的原速参考（现役场景逐档覆盖）
## 切换统一走 play(clip, BLEND) 交叉淡化。
##
## 动作参考速度由所用资产的脚趾水平行程和周期估算，由视觉场景显式覆盖。
## 换动作后应重新测量，避免走跑滑步。

## 角色根（Swordsman）；本节点挂在 Visual 下，默认向上两层。
@export var actor_path: NodePath = ^"../.."
## true = 每帧读宿主 motion()（正式角色）；false = 外部用 advance_state() 显式驱动（预览）。
@export var auto_read_actor: bool = true
## walk 动作以**原速**（播放速率 1.0）播放时对应的移动速度（米/秒）。
## 契约：播放速率 = 实际速度 / 该值；当前视觉场景覆盖本默认值。
@export var walk_reference_mps: float = 1.3424
## run 动作以原速播放时对应的移动速度（米/秒）。
## 当前视觉场景覆盖本默认值；旧 v9 的参考值保留在历史资产台账。
@export var run_reference_mps: float = 2.3845
## 御剑前倾（弧度）。**仅用于退回路径**：资产没有 sword_ride 时，御剑以 idle 抬速呈现，
## 由本参数补出前倾。有 sword_ride 时前倾由该姿态自带，本参数不参与。
@export var flight_lean: float = 0.21

## 动作切换阈值（米/秒）：取在两档实际速度之间，使按住/松开加速键时真的切换 clip。
## 走 1.25 m/s、疾行 2.25 m/s（见 SwordsmanMotionComponent）。1.9 落在两档之间，避免
## 因一点点速度偏差就跳档。
const WALK_SPEED_MPS := 0.3
const RUN_SPEED_MPS := 1.9
const BLEND := 0.15
const IDLE_FLIGHT_RATE := 0.6

## 循环动作：持续状态必须线性循环，否则一个周期后停在末帧而快照仍报当前 gait。
const LOOPING_CLIPS: Array[String] = ["idle", "walk", "run", "idle_guarded", "meditate",
	"sword_ride"]
## 单次动作：jump 播完保持末帧（空中状态）。
const ONESHOT_CLIPS: Array[String] = ["jump"]

## 额外的手作状态。表现层保留缺失时退化为 idle 的兼容行为；
## 现役资产的七段 clip 由视觉契约测试完整校验。
const OPTIONAL_GUARDED_IDLE := "idle_guarded"
## true = 静止时用额外待命姿态代替普通 idle；资产没有该 clip 时自动退回 idle。
## 默认关闭：现役人物静止与预览重置使用双臂自然放松的普通站姿。
@export var prefer_guarded_idle: bool = false
const OPTIONAL_MEDITATE := "meditate"
const OPTIONAL_SWORD_RIDE := "sword_ride"

var _actor: Node3D
var _player: AnimationPlayer
var _model: Node3D
var _current := ""
var _clock := 0.0
## 非空 = 显式状态覆盖（见 play_state）；此时不按速度自动选 clip。
var _override := ""
## true = 预览式外部驱动：AnimationPlayer 走 MANUAL，由 advance_state() 的 delta 推进。
var _manual_advance := false

## 最近一次只读快照：预览 HUD 与验收脚本读取，不参与物理。
var _pose: Dictionary = {}


func _ready() -> void:
	_actor = (get_node_or_null(actor_path) as Node3D) if not actor_path.is_empty() else null
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
	_current = _default_idle_clip()
	_player.play(_current)
	_player.advance(0.0)


## glTF 导入的 clip 默认是 LOOP_NONE（实测 v9 GLB 四个 clip 全为 0）。若不显式修正，
## idle/walk/run 播放一个周期后停在末帧，但状态快照仍会报当前 gait，形成「不动却报走动」。
## jump 必须保持单次，播完停在末帧供空中状态使用。
func _configure_looping() -> void:
	# 四段核心动作必须存在（_ready 已断言过）；手作额外状态是可选的，缺失就跳过，
	# 这样四段旧资产与新七段资产都能跑。
	for clip in LOOPING_CLIPS:
		var animation := _player.get_animation(clip)
		if animation == null:
			continue
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
	if not _override.is_empty():
		# 显式覆盖期间只推进时间与快照，不改 clip：覆盖是玩法层的决定，不被速度推翻。
		if _manual_advance:
			_player.advance(delta)
		var ov_velocity: Vector3 = state.get("velocity", Vector3.ZERO)
		_record_pose(ov_velocity,
			Vector3(ov_velocity.x, 0.0, ov_velocity.z).length(),
			bool(state.get("grounded", true)), bool(state.get("flying", false)))
		return
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var grounded: bool = state.get("grounded", true)
	var flying: bool = state.get("flying", false)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()

	var target := ""
	var rate := 1.0
	if flying:
		# 御剑优先用专门手作的「御剑而立」姿态；它自带前倾，因此不再叠加节点前倾
		# （叠加会变成弯腰）。旧的四段资产没有该 clip，退回原来的 idle@0.6 + 前倾。
		if has_state(OPTIONAL_SWORD_RIDE):
			target = OPTIONAL_SWORD_RIDE
			rate = 1.0
		else:
			target = "idle"
			rate = IDLE_FLIGHT_RATE
	elif not grounded:
		target = "jump"
	elif speed > RUN_SPEED_MPS:
		target = "run"
		rate = speed / maxf(run_reference_mps, 0.01)
	elif speed > WALK_SPEED_MPS:
		target = "walk"
		rate = speed / maxf(walk_reference_mps, 0.01)
	elif prefer_guarded_idle and has_state(OPTIONAL_GUARDED_IDLE):
		# 静止：优先用手作的「负手而立」。它自带端正站姿，不需要按速度调整速率。
		target = OPTIONAL_GUARDED_IDLE
		rate = 1.0
	else:
		target = "idle"

	if target != _current:
		_current = target
		_player.play(target, BLEND)
	# 切换动作的第一帧也必须同步播放速率；否则每次 idle -> walk/run 都会以旧速率播放一帧，
	# 在低帧率或反复起停时形成可见脚步脉冲。
	if target == "walk" or target == "run":
		# 实测步幅已让 rate 在正常速度下 ≈1.0，因此夹取带收窄：过大的上限只会在极端速度下
		# 把动作拉成「快放」，反而更假。0.6–1.8 覆盖走跑全速域且不破坏节奏。
		_player.speed_scale = clampf(rate, 0.6, 1.8)
	else:
		_player.speed_scale = rate

	# 手动模式：AnimationPlayer 不自走，由本次调用的 delta 显式推进（见 _ready 注释）。
	# 放在 speed_scale 之后，使本次推进就用上刚设定的速率。
	if _manual_advance:
		_player.advance(delta)

	# 御剑前倾：只倾斜模型节点（表现层），与刚体版的 body 前倾同语义。
	#
	# 用 sword_ride 姿态时不再叠加节点前倾：那套姿态的脊柱本身已经前倾（髋 +9°、脊柱
	# 逐节累加），再叠 flight_lean 会变成弯腰。节点前倾因此只服务于退回路径（idle 抬速），
	# 那条路径没有自带前倾，正需要它。
	if _model != null:
		var authored_ride := flying and has_state(OPTIONAL_SWORD_RIDE)
		var lean := 0.0 if authored_ride else (flight_lean if flying else 0.0)
		_model.rotation.x = lerpf(_model.rotation.x, -lean, minf(delta * 6.0, 1.0))

	_record_pose(velocity, speed, grounded, flying)


## 静止默认 clip：普通 idle；仅显式启用负手偏好时改用 idle_guarded。
##
## 起手与 reset 都走这里，保证「进场景看到的站姿」与「停下后的站姿」一致——
## 两处各写一次会让静止姿态在 reset 后悄悄变回 idle。
func _default_idle_clip() -> String:
	if prefer_guarded_idle and has_state(OPTIONAL_GUARDED_IDLE):
		return OPTIONAL_GUARDED_IDLE
	return "idle"


## 是否有某个额外手作状态（资产可能是四段旧版，此时为 false）。
func has_state(clip: String) -> bool:
	return _player != null and _player.has_animation(clip)


## 手动切到某个额外状态（打坐 / 负手而立 / 御剑而立）。用于实验场景演示与截图取证。
##
## 这是**显式覆盖**：调用后表现层不再按速度自动选 clip，直到 `release_state()`。
## 不做成自动判定，是因为「这个角色现在是在打坐还是在待机」是玩法层的问题，
## 表现层没有依据替它决定。
func play_state(clip: String) -> bool:
	if not has_state(clip):
		return false
	_override = clip
	_current = clip
	_player.play(clip, BLEND)
	_player.speed_scale = 1.0
	_record_pose(Vector3.ZERO, 0.0, true, false)
	return true


## 解除显式状态覆盖，回到按速度自动选 clip。
func release_state() -> void:
	_override = ""
	reset_pose()


## 回到中性姿态（预览循环起点用）。
func reset_pose() -> void:
	_clock = 0.0
	_current = _default_idle_clip()
	_player.speed_scale = 1.0
	# 显式复位应立刻写入骨架。预览默认暂停时没有后续 advance，若仍
	# crossfade 或只调用 play()，展示实例会一直停在 GLB 的绑定 T 姿态。
	_player.play(_current)
	_player.advance(0.0)
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
		"overridden": not _override.is_empty(),
		"speed": speed,
		"vertical_speed": velocity.y,
		"grounded": grounded,
		"flying": flying,
	}
