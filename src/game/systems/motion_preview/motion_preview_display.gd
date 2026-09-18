class_name MotionPreviewDisplay
extends Node3D

## 动作预览展示实例（S2 P0）：真实模型的独立 Visual 装配 + 局部预览时钟 + 显式 state provider。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md
## 「真预览：同 Visual 子场景 + 局部预览时钟 + 显式 preview state provider；
##  不操纵全局 TimeKeeper、不写真实 actor 意图」。
##
## 边界（硬约束）：
## - 本节点不是 actor：没有 CharacterBody3D、没有 CollisionShape3D、没有 CapabilityManager、
##   没有第二个 move_and_slide()。删除本节点后正式角色行为与物理完全不变。
## - 模型与表现系统与正式角色同源：CULTIVATOR_VISUAL（同一 GLB + 同一 cultivator_presentation.gd），
##   不存在第二套姿态实现，也不新建/覆盖任何模型资产。
## - 飞剑读取共享御剑表现资源（sword_flight 包内的 flying_sword.glb），显隐由预览状态决定，
##   不冒充真实 SwordFlight 能力，也不消费任何组件。
##
## 时间契约（与 MotionPreviewState 对齐，测试直接断言）：
## - `advance(frame_delta)` 由工作台每渲染帧传入**真实帧 delta**；播放时推进
##   frame_delta * rate，因此 30/60 fps 下同一墙钟时长的推进总量相同。
## - 暂停时 state 的 consumed_delta = 0，本节点**完全不推进表现层**（不调 advance_state，
##   不写姿态），clock / phase / 各增益保持逐位不变。
## - `step_once()` 固定推进 STEP_SECONDS * rate 一次，与播放状态无关，单步后可完全复算。
## - 姿态复位只在「循环回卷」与「显式 reset」发生；**动作切换不复位姿态**，A-B 从当前
##   实际姿态继续（transition_from_* 由 state.note_effective 采样）。
## - rotation.y（朝向）归本节点所有；回卷与 reset 时一并归零，因此转身类动作不会跨循环累积。

const CULTIVATOR_VISUAL: PackedScene = preload("res://game/actors/swordsman/cultivator_visual.tscn")
## 共享御剑表现资源：与 sword_flight 能力包使用的是同一个 GLB，不复制、不覆盖。
const FLYING_SWORD_SCENE: PackedScene = preload("res://game/abilities/sword_flight/models/flying_sword.glb")

## 动作速度的参考值（米/秒）：由工作台从 SwordsmanMotionComponent.move_speed 注入，
## 使「行走 = 0.5 倍、跑动 = 1.0 倍」与正式角色的真实速度同尺度。
## 默认 4.0 只是该契约默认值的兜底，仅供独立单测；工作台必须显式注入。
@export var speed_reference: float = 4.0
## 展示实例的初始世界朝向（水平向量）。由调用场景注入，**本包不硬编码任何场景方向**：
## 动作工作台注入角色的 SPAWN_AIM，使「预览的正面」与「实时角色的正面」指向同一方向，
## 于是 FRONT / SIDE / 三机位标签对两种模式都成立（否则预览朝 −Z、角色朝 +X，标签会颠倒）。
## 默认 Vector3.FORWARD(−Z) = 零朝向，独立单测与无宿主用法保持原有语义。
@export var initial_aim: Vector3 = Vector3.FORWARD

var _visual: Node3D
var _presentation: Node3D
var _sword: Node3D
var _state := MotionPreviewState.new()
## 起始站位高度：局部竖直位移以此为基准（reset 时回到它）。
var _base_y := 0.0
## 预览实例的朝向（弧度），含义与角色一致（模型局部 −Z 为正面）。
## 初值由 initial_aim 推导；回卷 / reset 复位到该初值（不是固定 0，否则会转回 −Z）。
var _heading := 0.0
## 初始朝向（弧度）：由 initial_aim 推导，reset 与循环回卷都回到它。
var _initial_heading := 0.0
## 预览局部竖直位移（米）：由剖面竖直速度积分得到，**只影响展示实例自己的位置**，
## 不写任何 actor / Component / 物理。起跳与御剑升降因此能被肉眼读出；
## 循环回卷与 reset 时归零，避免跨循环累积。
var _offset_y := 0.0
## 本帧是否真的推进了（consumed_delta > 0）。暂停时为 false。
var _advanced_last_frame := false


func _ready() -> void:
	# 实例化共享 Visual 装配，并在入树前把表现层切到预览驱动：
	# 它没有任何 actor 路径可读，必须只由 advance() 显式推进。
	var visual := CULTIVATOR_VISUAL.instantiate() as Node3D
	assert(visual != null, "MotionPreviewDisplay: cultivator_visual.tscn 根必须是 Node3D")
	visual.name = "CultivatorVisual"
	var presentation := visual.get_node_or_null("CultivatorPresentation")
	assert(presentation != null, "MotionPreviewDisplay: 共享 Visual 缺少 CultivatorPresentation")
	presentation.set("auto_read_actor", false)
	presentation.set("actor_path", NodePath(""))
	add_child(visual)
	_visual = visual
	_presentation = presentation
	# 初始朝向来自注入的 aim：与 actor 的 _face_aim() 同一约定（局部 −Z 为正面）。
	_initial_heading = heading_for_aim(initial_aim)
	_heading = _initial_heading
	_base_y = position.y
	_bind_sword()
	# 初始即落一帧中性姿态，避免首帧读取空快照。
	_presentation.call("reset_pose")
	_sync_visual()


## 飞剑：读取共享御剑表现资源并挂到 Visual 下，显隐由预览状态同步。
func _bind_sword() -> void:
	var instance := FLYING_SWORD_SCENE.instantiate()
	assert(instance is Node3D, "MotionPreviewDisplay: flying_sword.glb 根必须是 Node3D")
	var sword := instance as Node3D
	sword.name = "PreviewSword"
	_visual.add_child(sword)
	sword.visible = false
	_sword = sword


## aim（世界水平方向）→ 节点 rotation.y：与 actor 的 _face_aim() 同一公式（局部 −Z 为正面）。
static func heading_for_aim(aim: Vector3) -> float:
	var flat := Vector3(aim.x, 0.0, aim.z)
	if flat.length_squared() <= 0.000001:
		return 0.0
	flat = flat.normalized()
	return atan2(-flat.x, -flat.z)


# --- 预览状态 API（供工作台与测试读取/驱动） --------------------------------


func state() -> MotionPreviewState:
	return _state


## 注入剖面物理参数（工作台从 SwordsmanMotionComponent 一次性注入）。
## 不注入时状态机使用 MotionPreviewParams 的契约默认值，独立单测因此可完全离线。
func apply_params(params: MotionPreviewParams) -> void:
	if params == null:
		return
	_state.params = params
	speed_reference = params.move_speed
	_apply(0.0)


## 推进一个渲染帧。frame_delta 必须是调用方采集的真实帧时长。
## 返回本帧是否推进了表现层（false = 暂停或零长帧，姿态逐位未变）。
func advance(frame_delta: float) -> bool:
	_state.tick(frame_delta)
	return _consume_tick()


## 单步：固定 STEP_SECONDS * rate，一次一步，与播放状态无关。
func step_once() -> bool:
	_state.step_once()
	return _consume_tick()


## 切换动作。切换**不复位姿态**：表现层从当前姿态继续过渡，A 端由 state 采样。
func select_action(action_id: String) -> bool:
	# 先记录切换前这一刻「实际生效」的状态，select() 会把它作为过渡 A 端；
	# 再应用一帧（delta=0，不推进姿态），因此切换本身不产生跳变。
	_state.note_effective(_state.effective_state())
	var changed := _state.select(action_id)
	if changed:
		_apply(0.0)
	return changed


## 显式复位：局部时钟、朝向、姿态全部回到中性。只有用户显式重置 / 循环回卷才调用。
func reset_preview() -> void:
	_state.rewind()
	_state.playing = false
	_heading = _initial_heading
	_offset_y = 0.0
	position.y = _base_y
	if _presentation != null:
		_presentation.call("reset_pose")
	_sync_visual()
	_advanced_last_frame = false


## 只读快照：工作台 HUD 与验收脚本读这个，不访问任何私有节点。
func preview_snapshot() -> Dictionary:
	var effective := _state.effective_state()
	var pose := pose_snapshot()
	return {
		"action_id": _state.current_id(),
		"action_title": _state.current.title,
		"source": _state.current.source,
		"previous_id": _state.previous.id,
		"note": _state.current.note,
		# 用户可读的一行摘要（面板常显）；note 保留完整技术说明进 tooltip。
		"summary": _state.current.summary(),
		"playing": _state.playing,
		"looping": _state.looping,
		"rate": _state.rate,
		"local_time": _state.local_time,
		"duration": _state.action_duration(),
		"progress": _state.progress(),
		"transition": _state.transition,
		"transitioning": _state.is_transitioning(),
		"step_seconds": MotionPreviewState.STEP_SECONDS,
		"consumed_delta": _state.consumed_delta,
		"advanced_last_frame": _advanced_last_frame,
		"effective": effective,
		"sword_visible": _sword != null and _sword.visible,
		"heading": _heading,
		"initial_heading": _initial_heading,
		# 预览正面朝向（世界水平单位向量）：测试据此断言机位标签真的对应。
		"forward": Vector3(-sin(_heading), 0.0, -cos(_heading)),
		"offset_y": _offset_y,
		"pose": pose,
		"clock": pose.get("clock", 0.0),
	}


func pose_snapshot() -> Dictionary:
	if _presentation != null and _presentation.has_method("pose_state"):
		return _presentation.call("pose_state") as Dictionary
	return {}


func presentation() -> Node3D:
	return _presentation


func sword_visual() -> Node3D:
	return _sword


# --- 内部 -------------------------------------------------------------------


## 消耗本 tick：consumed_delta = 0 时**完全不碰姿态**（暂停 / 零长帧 / 已到末尾）。
## 只有真的推进了才调用表现层的 advance_state，且 delta 就是 consumed_delta，
## 因此 local_time 与 clock / phase 同源、不分叉。
func _consume_tick() -> bool:
	if _state.consumed_delta <= 0.0:
		_advanced_last_frame = false
		_sync_visual()
		return false
	if _state.wrapped_last_tick:
		# 循环回卷：先复位姿态与朝向（避免关节变换跨循环累积），
		# 再只推进本帧落到新一圈的**余量**，因此边界相位与帧率无关。
		_heading = _initial_heading
		_offset_y = 0.0
		if _presentation != null:
			_presentation.call("reset_pose")
	_apply(_state.pose_delta())
	_advanced_last_frame = true
	return true


## 把预览状态推给共享表现系统。用的是与正式角色完全相同的 advance_state()
## （rotation.y 由本节点写，表现层不碰朝向）。
func _apply(delta: float = 0.0) -> void:
	if _presentation == null:
		return
	var effective := _state.effective_state()
	var speed := _state.speed_at(effective, speed_reference)
	var vertical: float = effective.get("vertical", 0.0)
	# 预览实例原地播放：速度方向按本地 heading 给出，因此步态相位由真实"速度大小"驱动。
	var forward := Vector3(-sin(_heading), 0.0, -cos(_heading))
	var velocity := forward * speed
	velocity.y = vertical
	var blend := {
		"velocity": velocity,
		"grounded": effective.get("grounded", true),
		"flying": effective.get("flying", false),
		"aim": forward,
	}
	if delta > 0.0:
		_presentation.call("advance_state", blend, delta)
		# 预览局部竖直位移：把剖面的竖直速度积分成展示实例的高度（纯展示，不写物理）。
		# 不在地面时积分；落地后贴回基准高度，因此 jump 的起跳→下落→落地与 flight 的
		# 升→悬→降在画面上都能直接读出来。
		if bool(effective.get("grounded", true)):
			_offset_y = 0.0
		else:
			_offset_y = maxf(_offset_y + vertical * delta, 0.0)
		position.y = _base_y + _offset_y
	# 过渡起点采样的是「实际生效」的这一状态。
	_state.note_effective(effective)
	_sync_visual()


## 视觉同步：朝向与飞剑显隐（不参与表现层姿态计算）。
func _sync_visual() -> void:
	if _visual != null:
		_visual.rotation.y = _heading
	if _sword != null:
		_sword.visible = _state.effective_state().get("sword", false)
