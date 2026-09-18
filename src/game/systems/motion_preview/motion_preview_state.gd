class_name MotionPreviewState
extends RefCounted

## 预览状态机（纯数据 + 纯函数，无节点）。
##
## 依据 notes/implemented/.../2026-09-18-character-movement-composable-labs.md「真预览」：
## **局部预览时钟 + 显式 preview state provider**；不操纵全局 TimeKeeper、不写真实 actor 意图。
##
## 时钟口径（测试据此判定，不含糊）：
## - `tick(frame_delta)`：**由调用方传入真实帧 delta**，内部乘 rate；播放推进量 = frame_delta * rate。
##   渲染帧率不同（30 / 60 fps）只改变每帧步长，同一墙钟时长推进总量相同。
## - `step_once()`：与播放状态无关，固定推进 `STEP_SECONDS * rate` 一次。
## - `consumed_delta`：本 tick **实际**推进了多少秒（0 表示什么都没动）。暂停时恒为 0；
##   非循环动作到达结尾时按剩余时间 clamp，不越过末尾。
## - 姿态推进必须使用 consumed_delta，因此 local_time 与表现层 clock / phase 不会分叉。
## - 循环回卷时姿态推进量取**余量**（`pose_delta()` = 新一圈的 local_time），
##   而不是整帧 delta，因此循环边界处的相位与帧率无关：30fps 与 60fps 走过同一墙钟时长后
##   落在同一相位，而不是各自断在帧边界上。
##
## 本类不引用任何节点/组件/物理，可独立单测。

const MotionPreviewAction := preload("res://game/systems/motion_preview/motion_preview_action.gd")
const MotionPreviewParams := preload("res://game/systems/motion_preview/motion_preview_params.gd")

## 单步固定基步长（秒）。step 一次推进 STEP_SECONDS * rate，是本工作台的公开常量。
const STEP_SECONDS := 1.0 / 30.0

## 动作切换的过渡时长（秒）；A-B 过渡的 A/B 即「当前动作 / 目标动作」。
const TRANSITION_SECONDS := 0.35

var actions: Array[MotionPreviewAction] = []
## 剖面物理参数：由工作台从 SwordsmanMotionComponent 注入；未注入时用契约默认值。
var params: MotionPreviewParams = MotionPreviewParams.new()
var current: MotionPreviewAction
var previous: MotionPreviewAction
var local_time := 0.0
var playing := false
var looping := true
var rate := 1.0
## 0..1 的过渡进度：1 = 完全在 current，未处于过渡时恒为 1。
var transition := 1.0

## 过渡起点：切换时**采样当时的实际预览状态**（由 display 通过 note_effective 回写），
## 不是默认值 0。这样 A→B 从当前姿态继续，而不是先跳到静止再走。
var transition_from_speed := 0.0
var transition_from_vertical := 0.0
var transition_from_grounded := true
var transition_from_flying := false
var transition_from_sword := false

## display 最近一次实际生效的预览状态（用于过渡起点采样与读数）。
var last_speed := 0.0
var last_vertical := 0.0
var last_grounded := true
var last_flying := false
var last_sword := false

## 本 tick 实际推进量（秒）。0 = 完全没推进（暂停 / 零长帧 / 已到非循环末尾）。
var consumed_delta := 0.0

## 上一次 tick 是否发生了循环回卷（display 据此复位姿态，避免跨循环累积）。
var wrapped_last_tick := false
## 上一次 tick 是否发生了动作切换（信息性标记；切换不复位姿态）。
var switched_last_tick := false


func _init() -> void:
	actions = MotionPreviewAction.library()
	current = MotionPreviewAction.find(actions, "idle")
	assert(current != null, "MotionPreviewState: 默认动作 idle 必须在库中")
	previous = current
	# 初始「实际状态」= 默认动作在相位 0 的采样，首个动作切换才有正确的 A 端起点。
	var initial := current.sample(0.0, params)
	last_speed = float(initial.get("speed_factor", 0.0))
	last_vertical = float(initial.get("vertical", 0.0))
	last_grounded = bool(initial.get("grounded", true))
	last_flying = bool(initial.get("flying", false))
	last_sword = bool(initial.get("sword", false))


func action_ids() -> Array[String]:
	var ids: Array[String] = []
	for action in actions:
		ids.append(action.id)
	return ids


func current_id() -> String:
	return current.id if current != null else ""


func is_transitioning() -> bool:
	return transition < 1.0


## display 每次实际生效后回写：过渡起点与读数都以它为准。
func note_effective(effective: Dictionary) -> void:
	last_speed = float(effective.get("speed", 0.0))
	last_vertical = float(effective.get("vertical", 0.0))
	last_grounded = bool(effective.get("grounded", true))
	last_flying = bool(effective.get("flying", false))
	last_sword = bool(effective.get("sword", false))


## 切到目标动作：A-B 过渡的 B 端。起点从 note_effective() 记录的**当前实际状态**采样，
## 因此切换瞬间不会跳到静止；**不清姿态**（只有循环回卷与显式 reset 才复位姿态）。
## 同一动作重复切换幂等（不重置过渡）。
func select(action_id: String) -> bool:
	var target := MotionPreviewAction.find(actions, action_id)
	assert(target != null, "MotionPreviewState: 未登记的动作 id %s" % action_id)
	if target == null or target == current:
		return false
	previous = current
	# A 端 = 切换前这一刻实际生效的状态（含相位采样结果），不是动作的静态常量。
	var outgoing := effective_state()
	transition_from_speed = float(outgoing.get("speed", 0.0))
	transition_from_vertical = float(outgoing.get("vertical", 0.0))
	transition_from_grounded = bool(outgoing.get("grounded", true))
	transition_from_flying = bool(outgoing.get("flying", false))
	transition_from_sword = bool(outgoing.get("sword", false))
	current = target
	local_time = 0.0
	transition = 0.0
	wrapped_last_tick = false
	switched_last_tick = true
	return true


## 播放推进：frame_delta 是调用方采到的真实帧时长（秒），乘 rate 后生效。
## 暂停 / 零长帧 / 已到末尾时 consumed_delta = 0，调用方必须据此完全不推进姿态。
func tick(frame_delta: float) -> void:
	_reset_tick_flags()
	if not playing:
		return
	_advance(maxf(frame_delta, 0.0) * rate)


## 单步：与播放状态无关，恰好推进 STEP_SECONDS * rate 一次；不改变 playing。
func step_once() -> void:
	_reset_tick_flags()
	_advance(STEP_SECONDS * rate)


## 显式复位时钟（reset / 循环回卷），不改动作选择。
func rewind() -> void:
	local_time = 0.0
	transition = 1.0
	consumed_delta = 0.0


## 0..1 播放进度（用于进度条）；一次性动作停帧后为 1。
func progress() -> float:
	return phase()


## 当前动作在注入参数下的有效时长（秒）：局部时钟、进度、相位共用这一条时间轴。
## 跳跃由 jump_speed / gravity 决定，其余动作等于登记时长。
func action_duration() -> float:
	if current == null:
		return 0.0
	return current.effective_duration(params)


## 当前相位（0..1）：profile 采样的时间参数。
func phase() -> float:
	var span := action_duration()
	if current == null or span <= 0.0:
		return 0.0
	return clampf(local_time / span, 0.0, 1.0)


## 目标状态 = 当前动作按**当前相位**采样。这是「动作真的随相位变化」的唯一出口：
## 起步 / 停下速度先升后归零、跳跃竖速 正→0→负→着地、御剑 升/悬/降，都来自这里。
## 物理常量走注入参数，组件调参后预览不会与真实运动分叉。
func target_state() -> Dictionary:
	return current.sample(phase(), params)


## 中间状态：A 端（切换前实际状态）与 B 端（当前相位采样）按过渡进度混合。
## 过渡完成（transition>=1）时等价于 target_state()。
##
## 各分量按物理性质分别处理（都有实测依据，不是随手选择）：
## - **竖直速度直接取剖面目标值，不参与过渡混合**。竖直速度是这个动作自己的物理时间轴
##   （跳跃抛物线 / 御剑升降），把它与来源动作插值会削掉起跳初速：实测 idle→jump 时
##   首帧竖速只有 0.27 m/s（应为 6.0），跳跃峰值因此从理论 1.00 m 掉到 0.32 m。
## - **水平速度参与过渡混合**：它是步态幅度，从当前实际速度平滑过渡不会破坏动作时间轴。
## - **着地立刻取目标值**（不混合）：离地 / 落地是离散物理事件。
## - **御剑 / 飞剑在过渡中点切换**：避免剑在过渡刚开始就突兀出现 / 消失。
func effective_state() -> Dictionary:
	var target := target_state()
	var to_speed := float(target.get("speed_factor", 0.0))
	var to_vertical := float(target.get("vertical", 0.0))
	var to_grounded := bool(target.get("grounded", true))
	var to_flying := bool(target.get("flying", false))
	var to_sword := bool(target.get("sword", false))
	var blend := transition
	if blend >= 1.0:
		return _pack(to_speed, to_vertical, to_grounded, to_flying, to_sword)
	return _pack(
		lerpf(transition_from_speed, to_speed, blend),
		to_vertical,
		to_grounded,
		to_flying if blend >= 0.5 else transition_from_flying,
		to_sword if blend >= 0.5 else transition_from_sword)


## 速度系数 → 世界速度：display 才知道朝向，因此这里只返回大小。
func speed_at(effective: Dictionary, move_speed: float) -> float:
	return float(effective.get("speed", 0.0)) * move_speed


## 姿态推进量：决定表现层该前进多少秒。
## - 未回卷：等于 consumed_delta（正常推进 / 非循环末尾 clamp）。
## - 回卷：姿态必须先用 reset_pose() 回到圈首，再只推进**余量**（= 新一圈的 local_time），
##   而不是把整帧都算在新圈起点上。否则同一墙钟时长在不同帧率下会落到不同相位。
func pose_delta() -> float:
	if wrapped_last_tick:
		return local_time
	return consumed_delta


func _reset_tick_flags() -> void:
	consumed_delta = 0.0
	wrapped_last_tick = false
	switched_last_tick = false


## 实际推进量计算。
## - 非循环：到达末尾时 clamp 到剩余时间，不越界，随后 playing=false。
## - 循环：本帧跨过末尾时，把**余量**留在新一圈的 local_time 里，姿态按 pose_delta() 推进，
##   因此边界相位只由时间决定、与帧率无关；同时置 wrapped_last_tick 供 display 复位姿态。
func _advance(step: float) -> void:
	if step <= 0.0:
		return
	var duration := maxf(action_duration(), 0.01)
	if not looping and local_time + step >= duration:
		step = maxf(duration - local_time, 0.0)
		playing = false
		if step <= 0.0:
			return
		consumed_delta = step
		local_time += step
		transition = minf(transition + step / TRANSITION_SECONDS, 1.0)
		return
	consumed_delta = step
	local_time += step
	while local_time >= duration:
		local_time -= duration
		wrapped_last_tick = true
	transition = minf(transition + step / TRANSITION_SECONDS, 1.0)


func _pack(speed: float, vertical: float, grounded: bool, flying: bool, sword: bool) -> Dictionary:
	return {
		"speed": speed,
		"vertical": vertical,
		"grounded": grounded,
		"flying": flying,
		"sword": sword,
	}
