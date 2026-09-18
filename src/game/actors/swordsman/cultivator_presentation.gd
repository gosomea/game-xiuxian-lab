class_name CultivatorPresentation
extends Node3D

## 纯表现层：分件步态、摆臂、袍摆与御剑平衡姿态。
##
## 只读 actor.motion() 的 actual_velocity / on_floor / flight_active；不写任何 Component 字段、
## 不新增 Capability、不移动物理根与胶囊。删除本节点后角色行为与碰撞完全不变。
## 导出的分件对象原点都在角色原点，直接旋转会绕脚底转，因此 _ready() 按实测包围盒给每组
## 建枢轴（髋 / 肩 / 腰）并把网格 reparent 进去；枢轴仍建在模型根内，既有子树查询不受影响。
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

var _actor: Node3D
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _robe: Node3D
var _phase := 0.0
var _clock := 0.0
var _gait := 0.0
var _flight := 0.0


func _ready() -> void:
	_actor = get_node_or_null(actor_path)
	assert(_actor != null, "CultivatorPresentation: actor_path 未指向角色根（%s）" % actor_path)
	assert(_actor.has_method("motion"), "CultivatorPresentation: 角色根缺少 motion() 读取接口")
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


func _process(delta: float) -> void:
	if _actor == null:
		return
	var motion: Object = _actor.call("motion")
	if motion == null:
		return
	var velocity: Vector3 = motion.get("actual_velocity")
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded: bool = motion.get("on_floor")
	var flying: bool = motion.get("flight_active")
	_clock += delta
	_flight = move_toward(_flight, 1.0 if flying else 0.0, delta * 4.0)
	# 相位只在着地且真的在走时推进：停下就停在当前步态，不原地踏步。
	_gait = move_toward(_gait, 1.0 if grounded and speed > 0.2 else 0.0, delta * 6.0)
	if grounded:
		_phase = fmod(_phase + delta * TAU * speed / maxf(stride_meters, 0.01), TAU)
	var airborne := 0.0 if (grounded or flying) else 1.0
	if _legs.size() >= 2:
		var swing := sin(_phase) * leg_swing * _gait
		_legs[0].rotation.x = swing - airborne * 0.22 + _flight * 0.10
		_legs[1].rotation.x = -swing - airborne * 0.16 + _flight * 0.14
	if _arms.size() >= 2:
		var arm := -sin(_phase) * arm_swing * _gait
		_arms[0].rotation.x = arm
		_arms[1].rotation.x = -arm
		# 御剑与腾空时双臂略向外张，形成平衡姿态。
		_arms[0].rotation.z = _flight * 0.22 + airborne * 0.10
		_arms[1].rotation.z = -_flight * 0.22 - airborne * 0.10
	if _robe != null:
		# 进行与御剑时袍摆向后（+Z 为身后）轻拖，幅度刻意保守。
		_robe.rotation.x = -(clampf(speed * 0.020, 0.0, 0.10) + _flight * 0.10)
		_robe.rotation.z = sin(_phase) * 0.03 * _gait
	if _body != null:
		# 整体前倾与厘米级起伏；脚底基准仍由 actor 的物理结果决定。
		_body.rotation.x = -(_gait * 0.05 + _flight * flight_lean)
		_body.rotation.z = sin(_phase) * 0.015 * _gait
		_body.position.y = _flight * 0.035 * sin(_clock * 1.8) + _gait * 0.006 * (1.0 - cos(_phase * 2.0))


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
