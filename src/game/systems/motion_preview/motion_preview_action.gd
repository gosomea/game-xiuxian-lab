class_name MotionPreviewAction
extends RefCounted

## 剖面参数由 MotionPreviewParams 提供（工作台从组件注入），本文件不写死物理常量。
const MotionPreviewParams := preload("res://game/systems/motion_preview/motion_preview_params.gd")

## 动作工作台 P0 的动作定义（纯数据 + 纯函数，无节点、无生命周期）。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md「动作工作台与动作库（S2）」。
##
## 现实口径（不得冒充）：当前 GLB 0 skin / 0 animation，全部动作都是**程序近似**，
## 没有任何骨骼 clip。source 字段如实标注 program，UI 必须显示「程序动作预览」。
##
## 动作是**随循环相位变化的程序剖面**，不是一个静态常量：sample(phase) 按 phase（0..1）
## 给出该时刻的水平速度系数、竖直速度、着地、御剑与飞剑显隐。display 每帧用当前相位采样，
## 因此「起跳 → 顶点 → 下落 → 落地」「升 → 悬 → 降」必须能在读数上看出来，
## 而不是只换了一个动作名。note 文案必须与采样结果一致，不得描述样本里没有的行为。
##
## 动作 id / 播放模式 / 来源 / 剖面名都是**本包内的数据标识**，不是跨包公共词汇，
## 因此刻意使用普通 String 而非 StringName（&"..."），不进 src/data/vocabulary/。

## 循环播放：到达末尾后回卷并复位姿态。
const LOOP := "loop"
## 单次播放：到达末尾后停在末帧（除非勾选循环）。
const ONCE := "once"

## 动作来源：当前只有程序近似。
const SOURCE_PROGRAM := "program"

## 剖面：常量姿态（待机 / 行走 / 跑动）。
const PROFILE_STATIC := "static"
## 剖面：速度 0 → 巡航 → 0 的分段线性（起步 / 停下）。
const PROFILE_START_STOP := "start_stop"
## 剖面：v = jump_speed − gravity·t 的抛物线；落地后着地且竖速归零。
const PROFILE_JUMP := "jump"
## 剖面：升 → 悬 → 降 → 悬的周期。
const PROFILE_FLIGHT := "flight"

## 起步 / 停下剖面的分段点：前 30% 起步、后 30% 停下、中段巡航。
const START_STOP_RISE_END := 0.30
const START_STOP_FALL_START := 0.70
## 御剑剖面分段点。
const FLIGHT_LIFT_END := 0.20
const FLIGHT_HOVER_END := 0.50
const FLIGHT_SINK_END := 0.70

## 跳跃落地后的停留时长（秒）：让「落地」在预览里可读，而不是刚好停在触地那一帧。
## 有效时长 = max(登记时长, 2·jump_speed/gravity + 本常量)；默认参数下
## 2·6/18 + 0.4333 = 1.10 s，恰好等于登记时长，默认体验不变；
## 调大 jump_speed 或调小 gravity 时有效时长随之变长，飞行段不会被截断。
const JUMP_LANDING_HOLD := 0.4333

var id: String
var title: String
var source: String
var loop_mode: String
## 动作一个完整循环的时长（秒）；同时是剖面采样的时间轴长度。
var duration: float
var note: String
## 剖面类型：决定 sample(phase) 如何随时间变化（不是常量）。
var profile: String
## 剖面基础参数：水平速度系数（相对 move_speed）；static 剖面的竖直速度为 vertical_speed。
var speed_factor: float
var vertical_speed: float
var grounded: bool
var flying: bool
## 该动作是否要求显示飞剑视觉。
var shows_sword: bool


func _init(action_id: String, action_title: String, action_duration: float, action_note: String,
		action_profile: String, action_speed_factor: float, action_vertical: float,
		action_grounded: bool, action_flying: bool, action_loop: String) -> void:
	id = action_id
	title = action_title
	source = SOURCE_PROGRAM
	loop_mode = action_loop
	duration = maxf(action_duration, 0.05)
	note = action_note
	profile = action_profile
	speed_factor = action_speed_factor
	vertical_speed = action_vertical
	grounded = action_grounded
	flying = action_flying
	shows_sword = action_flying


## 默认动作库。note 必须与实际剖面一致：描述里出现的每个阶段都要能被 sample(phase) 采到。
static func library() -> Array[MotionPreviewAction]:
	var actions: Array[MotionPreviewAction] = []
	actions.append(MotionPreviewAction.new("idle", "待机", 2.4,
		"常量姿态：水平与竖向速度恒为 0，保持着地", PROFILE_STATIC, 0.0, 0.0, true, false, LOOP))
	actions.append(MotionPreviewAction.new("walk", "行走", 2.0,
		"常量步态：水平速度 0.5×move_speed；步频 = 速度 / stride_meters", PROFILE_STATIC, 0.5, 0.0, true, false, LOOP))
	actions.append(MotionPreviewAction.new("run", "跑动", 1.2,
		"常量步态：水平速度 1.0×move_speed；与行走共用同一套摆动，只提高步频", PROFILE_STATIC, 1.0, 0.0, true, false, LOOP))
	actions.append(MotionPreviewAction.new("start_stop", "起步 / 停下", 2.0,
		"随相位变化：速度 0 → 巡航 → 0（前 30% 起步、中段保持、后 30% 停下）",
		PROFILE_START_STOP, 0.5, 0.0, true, false, LOOP))
	actions.append(MotionPreviewAction.new("jump", "跳跃", 1.1,
		"随相位变化：起跳 +jump_speed → 顶点 0 → 下落 −jump_speed → 落地着地（v = jump_speed − gravity·t，参数由组件注入）",
		PROFILE_JUMP, 0.35, 0.0, false, false, ONCE))
	actions.append(MotionPreviewAction.new("flight", "御剑", 3.0,
		"随相位变化：升 +flight_lift_speed → 悬停 0 → 降 −flight_sink_speed → 悬停 0；全程御剑且飞剑可见",
		PROFILE_FLIGHT, 0.6, 0.0, false, true, LOOP))
	return actions


## 按 id 取动作；找不到返回 null（调用方必须显式处理，不做静默回退）。
static func find(actions: Array[MotionPreviewAction], action_id: String) -> MotionPreviewAction:
	for action in actions:
		if action.id == action_id:
			return action
	return null


## 本动作在给定参数下的**有效时长（秒）**：UI 进度、局部时钟、相位采样三者共用的唯一时间轴。
##
## 为什么不能直接用登记时长：跳跃的飞行时长由物理参数决定（2·jump_speed/gravity）。若时长写死为
## 1.1 s 而注入参数要求 1.5 s 飞行，动作会在仍在空中时结束——预览停在半空、而 summary 说"落地"。
## 这里让参数同时决定时长，因此时间轴与物理剖面始终自洽，不靠改倍率假装匹配。
func effective_duration(params: MotionPreviewParams = null) -> float:
	if profile != PROFILE_JUMP:
		return duration
	var resolved := params if params != null else MotionPreviewParams.new()
	return maxf(duration, resolved.jump_flight_seconds() + JUMP_LANDING_HOLD)


## 按循环相位采样本动作在该时刻的状态。phase 会被 clamp 到 [0, 1]。
## params 提供物理常量（由工作台从组件注入）；为 null 时用 MotionPreviewParams 的契约默认值。
## 返回 {speed_factor, vertical, grounded, flying, sword}，是 display 唯一消费的数据形状。
func sample(phase: float, params: MotionPreviewParams = null) -> Dictionary:
	var resolved := params if params != null else MotionPreviewParams.new()
	var p := clampf(phase, 0.0, 1.0)
	match profile:
		PROFILE_START_STOP:
			return _pack(_start_stop_speed(p), 0.0, true, false)
		PROFILE_JUMP:
			return _jump_state(p, resolved)
		PROFILE_FLIGHT:
			return _pack(speed_factor, _flight_vertical(p, resolved), false, true)
		_:
			return _pack(speed_factor, vertical_speed, grounded, flying)


## 起步 / 停下剖面：0 → 巡航 → 0 的分段线性；相位 0 与 1 处严格为 0。
func _start_stop_speed(phase: float) -> float:
	if phase < START_STOP_RISE_END:
		return speed_factor * (phase / START_STOP_RISE_END)
	if phase < START_STOP_FALL_START:
		return speed_factor
	return speed_factor * maxf(1.0 - (phase - START_STOP_FALL_START) / (1.0 - START_STOP_FALL_START), 0.0)


## 跳跃剖面：v = jump_speed − gravity·t；落地（v <= −jump_speed）之后着地且竖速归零。
## jump_speed / gravity 来自注入参数，因此组件调参后预览剖面同步变化。
func _jump_state(phase: float, params: MotionPreviewParams) -> Dictionary:
	# t 必须走 effective_duration：它与 phase 的分母同源，因此「相位 1.0」永远是「落地并停留结束」。
	var vertical := params.jump_speed - params.gravity * phase * effective_duration(params)
	if vertical <= -params.jump_speed:
		return _pack(speed_factor, 0.0, true, false)
	return _pack(speed_factor, vertical, false, false)


## 御剑剖面：升 → 悬停 → 降 → 悬停；全程 flying=true（表现层 flight 增益与飞剑显隐都由它驱动）。
## lift / sink 来自注入参数，与组件 flight_lift_speed / flight_sink_speed 同源。
func _flight_vertical(phase: float, params: MotionPreviewParams) -> float:
	if phase < FLIGHT_LIFT_END:
		return params.lift_speed
	if phase < FLIGHT_HOVER_END:
		return 0.0
	if phase < FLIGHT_SINK_END:
		return -params.sink_speed
	return 0.0


## 用户可读的一行摘要（面板常显）；带参数名的技术说明留在 note（tooltip / 详情）。
func summary() -> String:
	match profile:
		PROFILE_START_STOP:
			return "速度：起步 → 巡航 → 停下"
		PROFILE_JUMP:
			return "起跳 → 顶点 → 下落 → 落地"
		PROFILE_FLIGHT:
			return "上升 → 悬停 → 下降 → 悬停"
		_:
			if is_zero_approx(speed_factor):
				return "站立不动"
			return "匀速行走 %.0f%% 速度" % (speed_factor * 100.0)


func _pack(speed: float, vertical: float, is_grounded: bool, is_flying: bool) -> Dictionary:
	return {
		"speed_factor": speed,
		"vertical": vertical,
		"grounded": is_grounded,
		"flying": is_flying,
		"sword": is_flying,
	}
