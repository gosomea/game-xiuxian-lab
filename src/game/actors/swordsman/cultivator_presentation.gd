class_name CultivatorPresentation
extends Node3D

## 纯表现层：分件步态、摆臂、袍摆、腾空与御剑姿态，以及落地压缩过渡。
##
## 只读 actor.motion() 的 actual_velocity / on_floor / flight_active；不写任何 Component 字段、
## 不新增 Capability、不移动物理根与胶囊。删除本节点后角色行为与碰撞完全不变。
## 导出的分件对象原点都在角色原点，直接旋转会绕脚底转，因此 _ready() 按实测包围盒给每组
## 建枢轴（髋 / 肩 / 腰）并把网格 reparent 进去；枢轴仍建在模型根内，既有子树查询不受影响。
##
## 过渡全部由物理状态驱动，不依赖动画帧：
## - 着地/腾空来自 on_floor 边沿（跳起、落地各一次），不做「动画播放完毕」判定；
## - 落地压缩是 on_floor 上升沿触发的衰减脉冲，脚底基准始终由 actor 的物理结果决定；
## - 方向反转来自实际速度方向与上一帧方向点积，不是按键边沿；
## - 御剑起降看 flight_active 与实际竖直速度，升降/悬停分别是升速、降速与近零。
##
## 双驱动路径（动作工作台 P0，依据 composable-labs S2 动作工作台）：
## - **actor 路径（默认）**：auto_read_actor=true，_process 用渲染帧 delta 调用 advance_state()。
##   注意口径：_process 拿到的是 render / idle frame delta，**不是**物理帧时长，因此本条路径的
##   推进量是表现时钟，不等于物理时钟；它读取的快照是物理真值（actual_velocity / on_floor /
##   flight_active），但那些值来自物理 tick，两者不是同一个时间基准。
## - **预览路径**：auto_read_actor=false，由 preview state provider 用显式状态调用
##   advance_state(state, delta)，delta 来自局部预览时钟。两条路径共用同一 _apply_pose /
##   _record_pose，不存在第二套姿态实现；预览不读也不写任何 Component、不动物理。
##
## 已知边界：GLB 无骨骼，这是分件刚体摆动而非骨骼动画；脚掌无 IK 锁定，竖直起伏仅厘米级。
## 轴（导出实测）：Godot -Z 为正面、+Y 向上、足底 y=0；髋 y≈0.70、肩 y≈1.42、腰 y≈0.97。

## 角色根（Swordsman）；Presentation 挂在 Visual 下，默认向上两层。
@export var actor_path: NodePath = ^"../.."
## 一个完整步周期前进的距离（米）：步频 = 水平速度 / 该值。
## 默认 1.8 m：步行 4 m/s 时约 2.2 周期/秒（小跑感）；调小会更急促。
@export var stride_meters: float = 1.8
## 髋部前后摆动最大角度（弧度）。
@export var leg_swing: float = 0.34
## 肩部前后摆动最大角度（弧度），与腿反相。
@export var arm_swing: float = 0.22
## 御剑时身体前倾（弧度）。
@export var flight_lean: float = 0.16
## 步态增益上升 / 下降速率（每秒）：起步要快、停下稍缓，读起来才像有质量。
@export var gait_attack: float = 6.0
@export var gait_release: float = 4.5
## 腾空姿态增益速率（每秒）。
@export var airborne_rate: float = 5.5
## 落地压缩脉冲的初始强度与衰减速率（每秒）。
@export var landing_impulse: float = 1.0
@export var landing_decay: float = 5.0
## 方向反转响应的强度与衰减速率（每秒）。
@export var turn_response: float = 0.55
@export var turn_decay: float = 3.0
## 下落时屈膝伸展的最大角度（弧度）与达到该角度的下落速度（米/秒）。
@export var fall_leg_extend: float = 0.30
@export var fall_speed_reference: float = 6.0
## 御剑升降时机身俯仰的附加角（弧度）。
@export var flight_climb_pitch: float = 0.10
@export var flight_dive_pitch: float = 0.12
## 驱动来源：true = 每帧读宿主 actor 的物理结果（正式角色）；
## false = 由外部 state provider 显式调用 advance_state()（动作预览展示实例）。
@export var auto_read_actor: bool = true

var _actor: Node3D
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _robe: Node3D
var _phase := 0.0
var _clock := 0.0
var _gait := 0.0
var _flight := 0.0
var _airborne := 0.0
var _landing := 0.0
var _turn := 0.0
var _was_grounded := true
var _last_direction := Vector3.ZERO
## 最近一次读到的只读快照：供工作台 HUD 与验收脚本读取，不参与物理。
var _pose: Dictionary = {}


func _ready() -> void:
	# 空 NodePath 表示「本实例没有宿主」：它只在 auto_read_actor=false 的预览展示实例上合法。
	_actor = get_node_or_null(actor_path) if not actor_path.is_empty() else null
	# actor 路径必须真的能读物理结果；预览宿主（auto_read_actor=false）允许没有 actor，
	# 但它必须显式声明，不能靠「取不到就静默降级」。
	if auto_read_actor:
		assert(_actor != null, "CultivatorPresentation: actor_path 未指向角色根（%s）" % actor_path)
		assert(_actor.has_method("motion"), "CultivatorPresentation: 角色根缺少 motion() 读取接口")
	else:
		assert(_actor == null or _actor.has_method("motion"),
			"CultivatorPresentation: auto_read_actor=false 时 actor_path 必须为空或仍指向有 motion() 的根")
	_body = get_parent() as Node3D
	assert(_body != null, "CultivatorPresentation: 必须挂在角色模型节点下")
	var model := _model_root()
	assert(model != null, "CultivatorPresentation: 未找到模型根，无法建立表现枢轴")
	# 枢轴由调用方显式收集：_pivot 只负责建树与 reparent，不判断目标数组是否为空
	# （此前 _pivot 内部用 target.is_empty() 守卫 append，导致空数组永远收不到枢轴、
	# 四肢动画静默失效）。
	_legs.append(_require_pivot(model, ["Leg_L", "Foot_L"]))
	_legs.append(_require_pivot(model, ["Leg_R", "Foot_R"]))
	_arms.append(_require_pivot(model, ["Arm_Sleeve_L", "Cuff_L", "Hand_L"]))
	_arms.append(_require_pivot(model, ["Arm_Sleeve_R", "Cuff_R", "Hand_R"]))
	_robe = _require_pivot(model, ["Robe_Skirt", "Robe_HemBand", "Robe_Panel"])
	_assert_rig(model)
	if _actor is CharacterBody3D:
		_was_grounded = true


func _process(delta: float) -> void:
	# 预览展示实例关掉自动读取：它必须只由显式 state provider 推进。
	if not auto_read_actor:
		return
	advance_state(sample_state(), delta)


## 只读采样：从宿主 actor 的 motion 组件取本帧物理真值。
## 纯读，不写任何字段、不接触 Capability；这是 actor 路径与预览路径的唯一状态形状。
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


## 共享推进：actor 路径与预览路径共用。state 形状见 sample_state()；
## delta 由调用方给出（正式路径是 _process 的渲染帧 delta，预览路径是局部预览时钟的 tick 量）。
## 本函数只写表现层自身增益与枢轴，不写任何 Component、不碰 Engine.time_scale。
## 朝向（rotation.y）不在此处设置：yaw 归驱动方所有（actor 的 _face_aim() / provider 的 heading）。
func advance_state(state: Dictionary, delta: float) -> void:
	if state.is_empty():
		return
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var grounded: bool = state.get("grounded", true)
	var flying: bool = state.get("flying", false)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()
	_clock += delta
	# 御剑 / 腾空增益：都是物理状态驱动，不依赖动画播放进度。
	_flight = move_toward(_flight, 1.0 if flying else 0.0, delta * 4.0)
	_airborne = move_toward(_airborne, 0.0 if (grounded or flying) else 1.0, delta * airborne_rate)
	# 落地脉冲：着地上升沿触发一次，随后按 landing_decay 衰减，不做「落地动画播放完毕」判定。
	if grounded and not _was_grounded:
		_landing = landing_impulse
	_was_grounded = grounded
	_landing = move_toward(_landing, 0.0, delta * landing_decay)
	# 方向反转：实际速度方向与上一帧方向接近反向时给一次转身响应。
	if speed > 0.6:
		var direction := flat / speed
		if _last_direction.length_squared() > 0.25 and direction.dot(_last_direction) < -0.35:
			_turn = turn_response
		_last_direction = direction
	_turn = move_toward(_turn, 0.0, delta * turn_decay)
	# 相位只在着地且真的在走时推进：停下就停在当前步态，不原地踏步。
	_gait = move_toward(_gait, 1.0 if grounded and speed > 0.2 else 0.0,
		delta * (gait_attack if speed > 0.2 else gait_release))
	if grounded:
		_phase = fmod(_phase + delta * TAU * speed / maxf(stride_meters, 0.01), TAU)
	_apply_pose(velocity, speed)
	_record_pose(velocity, speed, grounded, flying)


## 清空全部姿态增益与相位并立即回到中性姿态。
## 预览动作循环回到起点时必须调用：否则上一轮的 landing / airborne / turn 脉冲会跨循环累积，
## 表现为「第二轮起点的姿态继承上一轮末尾」。actor 路径不在循环中使用。
##
## 刻意不碰 rotation.y：yaw 归驱动方所有。若预览 provider 用 rotation.y 表达 90°/180° 朝向，
## 它必须在自己的循环/动作重置里把 heading 一起复位，否则会一轮轮累积成 90°/180°/270°…。
## 本函数只负责姿态增益与相位，不替 provider 复位朝向。
func reset_pose() -> void:
	_phase = 0.0
	_clock = 0.0
	_gait = 0.0
	_flight = 0.0
	_airborne = 0.0
	_landing = 0.0
	_turn = 0.0
	_last_direction = Vector3.ZERO
	# 复位后视作已着地：随后第一帧若仍是着地状态，不得触发一次虚假落地脉冲。
	_was_grounded = true
	_apply_pose(Vector3.ZERO, 0.0)
	_record_pose(Vector3.ZERO, 0.0, true, false)


## 姿态合成：步态摆动 + 腾空收腿 + 下落伸腿 + 落地屈膝 + 转向侧倾 + 御剑平衡。
func _apply_pose(velocity: Vector3, speed: float) -> void:
	var vertical := velocity.y
	# 下落速度归一化：下落越快，腿越向前下方伸出准备触地。
	var fall := clampf(-vertical / maxf(fall_speed_reference, 0.01), 0.0, 1.0) * _airborne
	# 起跳 / 上升：收腿。
	var rise := clampf(vertical / maxf(fall_speed_reference, 0.01), 0.0, 1.0) * _airborne
	var tuck := rise * 0.30 - fall * fall_leg_extend
	var squash := _landing * 0.26
	if _legs.size() >= 2:
		var swing := sin(_phase) * leg_swing * _gait
		_legs[0].rotation.x = swing + tuck + squash - _flight * 0.06
		_legs[1].rotation.x = -swing + tuck * 0.85 + squash - _flight * 0.02
	if _arms.size() >= 2:
		var arm := -sin(_phase) * arm_swing * _gait
		_arms[0].rotation.x = arm + rise * 0.22 - fall * 0.10 + _turn * 0.10
		_arms[1].rotation.x = -arm + rise * 0.22 - fall * 0.10 - _turn * 0.10
		# 御剑与腾空时双臂略向外张，形成平衡姿态；落地时略收。
		var spread := _flight * 0.22 + _airborne * 0.10 - _landing * 0.06
		_arms[0].rotation.z = spread + _turn * 0.18
		_arms[1].rotation.z = -spread - _turn * 0.18
	if _robe != null:
		# 进行与御剑时袍摆向后（+Z 为身后）轻拖，下落与落地时再向前兜一下；幅度刻意保守。
		_robe.rotation.x = -(clampf(speed * 0.020, 0.0, 0.10) + _flight * 0.10 + _airborne * 0.05)
		_robe.rotation.z = sin(_phase) * 0.03 * _gait + _turn * 0.06
	if _body != null:
		# 整体前倾与厘米级起伏；脚底基准仍由 actor 的物理结果决定，压缩只在身体局部。
		var climb := clampf(vertical / maxf(fall_speed_reference, 0.01), -1.0, 1.0) * _flight
		_body.rotation.x = -(_gait * 0.05 + _flight * flight_lean + _airborne * 0.06
			+ climb * (flight_climb_pitch if vertical > 0.0 else flight_dive_pitch))
		_body.rotation.z = sin(_phase) * 0.015 * _gait + _turn * 0.08
		_body.position.y = (_flight * 0.035 * sin(_clock * 1.8)
			+ _gait * 0.006 * (1.0 - cos(_phase * 2.0))
			- _landing * 0.05)


## 只读快照：工作台 HUD 与验收脚本据此读回姿态参数，不参与任何物理裁决。
## clock 是表现层自己的推进量（actor 路径 = 渲染帧 delta 累计；预览路径 = 局部预览时钟累计），
## 暂停预览时它必须原地不动，因此它由调用方给出的 delta 累加，而不是读全局时间。
func _record_pose(velocity: Vector3, speed: float, grounded: bool, flying: bool) -> void:
	var left_leg := _legs[0].rotation.x if _legs.size() >= 2 else 0.0
	var right_leg := _legs[1].rotation.x if _legs.size() >= 2 else 0.0
	var left_arm := _arms[0].rotation.x if _arms.size() >= 2 else 0.0
	_pose = {
		# 表现层自己的推进量（秒）：actor 路径 = 渲染帧 delta 累计；预览路径 = 局部预览时钟累计。
		# 暂停预览时它不得前进，step 时按固定量前进——测试据此区分「真暂停」与「仍在跑」。
		# 注意：它是表现时钟，不是物理时钟；两者只在稳态下近似同步。
		"clock": _clock,
		"gait": _gait,
		"phase": _phase,
		"flight": _flight,
		"airborne": _airborne,
		"landing": _landing,
		"turn": _turn,
		"leg_left": left_leg,
		"leg_right": right_leg,
		"arm_left": left_arm,
		"body_pitch": _body.rotation.x if _body != null else 0.0,
		"body_lift": _body.position.y if _body != null else 0.0,
		"robe_pitch": _robe.rotation.x if _robe != null else 0.0,
		"speed": speed,
		"vertical_speed": velocity.y,
		"grounded": grounded,
		"flying": flying,
	}


## 表现层只读快照访问器；无快照时返回空字典，不制造默认姿态。
func pose_state() -> Dictionary:
	return _pose.duplicate()


## 模型根 = 首个网格节点的父节点（GLB 根）；枢轴建在它内部。
func _model_root() -> Node3D:
	for found in get_parent().find_children("*", "MeshInstance3D", true, false):
		return found.get_parent() as Node3D
	return null


## 按组 AABB 顶面中心建枢轴并把成员网格 reparent 进去；缺件返回 null，由调用方处理。
func _pivot(model: Node3D, members: Array) -> Node3D:
	var meshes: Array[Node3D] = []
	var bounds := AABB()
	for member in members:
		var node := model.find_child(member, true, false) as Node3D
		if node == null:
			continue
		var box := _node_aabb(node)
		bounds = box if meshes.is_empty() else bounds.merge(box)
		meshes.append(node)
	if meshes.is_empty():
		return null
	var pivot := Node3D.new()
	pivot.name = "Pivot_" + str(members[0])
	model.add_child(pivot)
	# AABB 在本节点局部空间，枢轴挂在 model 下：必须转成全局位置再赋值，
	# 否则 GLB 根带任何变换（缩放/旋转）时枢轴都会偏到角色体外。
	pivot.global_position = to_global(Vector3((bounds.position.x + bounds.end.x) * 0.5, bounds.end.y,
		(bounds.position.z + bounds.end.z) * 0.5))
	for mesh in meshes:
		mesh.reparent(pivot, true)
	return pivot


## 取枢轴；分件缺失是装配缺陷而不是可降级状态，取不到立即断言并指出缺哪个分件。
func _require_pivot(model: Node3D, members: Array) -> Node3D:
	for member in members:
		assert(model.find_child(member, true, false) != null,
			"CultivatorPresentation: 模型缺少分件 %s（表现层不做静默降级）" % member)
	return _pivot(model, members)


## 启动断言：腿/臂各 2 个枢轴，名字与父节点正确，且每个枢轴确实接管了成员网格。
func _assert_rig(model: Node3D) -> void:
	assert(_legs.size() == 2 and _arms.size() == 2,
		"CultivatorPresentation: 四肢枢轴数量错误（腿 %d / 臂 %d，期望各 2）" % [_legs.size(), _arms.size()])
	var named := {
		"Pivot_Leg_L": _legs[0], "Pivot_Leg_R": _legs[1],
		"Pivot_Arm_Sleeve_L": _arms[0], "Pivot_Arm_Sleeve_R": _arms[1],
	}
	for pivot_name in named:
		var pivot: Node3D = named[pivot_name]
		assert(pivot != null and pivot.name == pivot_name,
			"CultivatorPresentation: 枢轴名不符（期望 %s，实际 %s）" % [pivot_name, pivot.name])
		assert(pivot.get_parent() == model,
			"CultivatorPresentation: 枢轴 %s 必须挂在模型根 %s 下" % [pivot.name, model.name])
		assert(pivot.get_child_count() > 0, "CultivatorPresentation: 枢轴 %s 未接管任何分件" % pivot.name)
	assert(_robe != null and _robe.get_parent() == model,
		"CultivatorPresentation: 袍摆枢轴缺失或父节点错误")


## 分件相对本节点的包围盒：变换在世界空间统一，与枢轴是否已建立无关。
func _node_aabb(node: Node3D) -> AABB:
	var instance := node as MeshInstance3D
	if instance == null or instance.mesh == null:
		return AABB()
	return (global_transform.affine_inverse() * instance.global_transform) * instance.mesh.get_aabb()
