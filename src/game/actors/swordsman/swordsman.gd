class_name Swordsman
extends CharacterBody3D

## 修士角色根：物理 tick 的唯一提交点。
##
## 每帧顺序（契约 docs/experiments/traversal-contract.md）：
## 着地同步 -> 意图归零 -> manager.tick -> 重力/飞行合成 -> 一次 move_and_slide
## -> 回写状态 -> 清边沿与意图 -> 表现同步。
## 重力是基础物理，统一在本节点施加；能力只写意图字段。
## 本脚本不读键鼠、不认识实验场景、不引用任何 Capability 类名。

@onready var _motion: SwordsmanMotionComponent = $SwordsmanMotionComponent
@onready var _manager: CapabilityManager = $CapabilityManager
@onready var _visual: Node3D = $Visual

## 御剑视觉由场景实例化后经 bind_flight_visual() 注入；
## actor 不引用能力包的资源路径，也不硬依赖模型是否已落盘。
var _flight_visual: Node3D = null
var _lab_assembly_defaults: Dictionary = {}


func _ready() -> void:
	# CapabilityManager 自带 _process 自动 tick；这里禁用，改由本根节点的物理 tick 驱动，
	# 避免同一帧被推进两次。
	_manager.set_process(false)
	# 装配：能力由 ActorAssembly 按显式配置注册到本 manager 的直系子。
	# 配置缺失与装配失败一律断言暴露，不静默降级；没有装配节点的裸 actor/测试夹具不走本路径。
	var assembly := get_node_or_null("ActorAssembly") as ActorAssembly
	if assembly == null:
		return
	var assembly_error := assembly.install_configured()
	assert(assembly_error == "", "Swordsman: 角色装配失败：%s" % assembly_error)
	var initial := assembly.installed_config()
	_lab_assembly_defaults = {"move": initial.move_enabled, "jump": initial.jump_enabled,
		"flight": initial.flight_enabled}
	LabDefaults.subscribe(self)
	var settings_error := apply_lab_defaults()
	assert(settings_error.is_empty(), "Swordsman: 全局默认应用失败：%s" % settings_error)


## 参数由设置设施提供；生命周期操作由装配所有者执行。
func apply_lab_defaults() -> String:
	LabDefaults.apply_component(_motion)
	var assembly := get_node_or_null("ActorAssembly") as ActorAssembly
	if assembly == null or not assembly.is_installed():
		return ""
	for kind in _lab_assembly_defaults:
		var error := assembly.set_capability_enabled(kind,
			LabDefaults.ability_enabled(kind, _lab_assembly_defaults[kind]))
		if not error.is_empty():
			return error
	return ""


func _physics_process(delta: float) -> void:
	var motion := _motion
	# 1. 着地同步：能力在 tick 中读到的是上一帧的物理结果。
	motion.on_floor = is_on_floor()
	# 2. 意图归零：能力不负责清理，避免失活踩掉高优先级能力同帧写入的意图。
	clear_intents(motion)
	# 3. 调度：SwordFlight(100) -> Jump(50) -> SwordsmanMovement(0)。
	_manager.tick(delta)
	# 4. 合成速度：飞行不吃重力、忽略冲量；非飞行时重力由 actor 统一施加。
	if motion.flight_active:
		velocity.x = motion.desired_horizontal.x
		velocity.z = motion.desired_horizontal.z
		velocity.y = motion.desired_vertical
	else:
		velocity.x = motion.desired_horizontal.x
		velocity.z = motion.desired_horizontal.z
		if motion.on_floor:
			velocity.y = 0.0
		else:
			velocity.y -= motion.gravity * delta
		if not is_zero_approx(motion.vertical_impulse):
			velocity.y = motion.vertical_impulse
	# 5. 全帧唯一一次物理提交。
	move_and_slide()
	# 6. 回写状态。
	motion.actual_velocity = velocity
	motion.on_floor = is_on_floor()
	# 7. 边沿与意图清理：同一边沿不会被两帧消费，也不会补触发。
	motion.jump_pressed = false
	motion.flight_toggle_pressed = false
	clear_intents(motion)
	# 8. 表现同步。
	_face_aim()
	if _flight_visual != null and is_instance_valid(_flight_visual):
		_flight_visual.visible = motion.flight_active


## 完整移动输入的统一场景入口。数据已由输入层解码，不包含设备按键。
## 契约字段：move(Vector2)、sprint(bool)、vertical(float)、jump(bool)、flight(bool)。
## 场景每个物理帧调用一次；动作边沿由输入层消费一次，能力仍只读取共享组件。
func apply_motion_input(input: Dictionary) -> void:
	set_move_input(input["move"])
	set_sprint_input(input["sprint"])
	set_vertical_input(input["vertical"])
	if input["jump"]:
		press_jump()
	if input["flight"]:
		press_flight_toggle()
	if _motion.move_input != Vector2.ZERO:
		var direction := _motion.camera_right * _motion.move_input.x \
			- _motion.camera_forward * _motion.move_input.y
		set_aim_direction(direction)


## 场景装配 API：屏幕相对移动输入（x = 右，y = 下），长度收敛到 1。
func set_move_input(input: Vector2) -> void:
	_motion.move_input = input.limit_length(1.0)


## 场景装配 API：升降输入（+1 升 / -1 降 / 0 悬停）。
func set_vertical_input(value: float) -> void:
	_motion.vertical_input = clampf(value, -1.0, 1.0)


## 场景装配 API：空格 key-down 边沿，仅按下当帧调用一次。
func press_jump() -> void:
	_motion.jump_pressed = true


## 场景装配 API：F key-down 边沿，仅按下当帧调用一次。
func press_flight_toggle() -> void:
	_motion.flight_toggle_pressed = true


## 场景装配 API：疾行开关（按住加速键期间为 true）。与 move_input 同为输入，非状态。
func set_sprint_input(active: bool) -> void:
	_motion.sprint_input = active


## 场景装配 API：失焦清理全部输入，不改变飞行状态（已开启的御剑保留悬停）。
func clear_input() -> void:
	_motion.move_input = Vector2.ZERO
	_motion.vertical_input = 0.0
	_motion.jump_pressed = false
	_motion.flight_toggle_pressed = false
	_motion.sprint_input = false


## 场景装配 API：相机在地面的右/前基向量（水平单位向量）。
func set_camera_ground_basis(right: Vector3, forward: Vector3) -> void:
	_motion.camera_right = Vector3(right.x, 0.0, right.z).normalized()
	_motion.camera_forward = Vector3(forward.x, 0.0, forward.z).normalized()


## 场景装配 API：外部提供的世界地面朝向（水平单位向量）；零向量会被忽略。
func set_aim_direction(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() <= 0.000001:
		return
	_motion.aim_direction = flat.normalized()


## 场景装配 API：R 重置：清输入、意图、速度与飞行状态。
## 飞行阻塞由 SwordFlight 下一 physics tick 的失活路径清账。
func reset_motion() -> void:
	clear_input()
	clear_intents(_motion)
	_motion.actual_velocity = Vector3.ZERO
	_motion.flight_active = false
	velocity = Vector3.ZERO


## 场景装配 API：注入御剑视觉节点；可见性由本节点按 flight_active 同步。
## 同一 actor 只应绑定一个御剑视觉：装配方（FlightBundle 或场景）负责保证唯一性。
func bind_flight_visual(node: Node3D) -> void:
	_flight_visual = node
	if _flight_visual != null:
		_flight_visual.visible = _motion.flight_active


## 场景装配 API：解除御剑视觉绑定。只解除当前绑定的那个节点，避免误伤其它装配方的绑定；
## 节点本身由它的所有者释放，本节点不销毁未知节点。
func unbind_flight_visual(node: Node3D) -> void:
	if _flight_visual == node or not is_instance_valid(_flight_visual):
		_flight_visual = null


## 只读：当前绑定的御剑视觉节点（未绑定返回 null）。
func flight_visual_node() -> Node3D:
	return _flight_visual if is_instance_valid(_flight_visual) else null


func motion() -> SwordsmanMotionComponent:
	return _motion


func capability_manager() -> CapabilityManager:
	return _manager


## 世界水平朝向 → 角色视觉 yaw。现役角色资产统一以局部 +Z 为正面；
## 因此旋转后的 local +Z 必须与 aim 同向，而不是旧约定的 local -Z。
static func visual_yaw_for_aim(direction: Vector3) -> float:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() <= 0.000001:
		return 0.0
	flat = flat.normalized()
	return atan2(flat.x, flat.z)


## 意图字段归零；tick 前与帧末各调用一次。
static func clear_intents(motion: SwordsmanMotionComponent) -> void:
	motion.desired_horizontal = Vector3.ZERO
	motion.desired_vertical = 0.0
	motion.vertical_impulse = 0.0


## 运动 inactive 时也更新朝向表现：只读组件数据，属于纯表现同步。
func _face_aim() -> void:
	var aim := _motion.aim_direction
	if aim.length_squared() <= 0.000001:
		return
	# 模型局部 +Z 为正面：统一由共享换算保证正面与 aim / 实际行进方向同向。
	_visual.rotation.y = visual_yaw_for_aim(aim)
