extends SceneTree

## 状态切换压力场验收：真实场景 + 真实 Swordsman + 真实输入事件 + 账本读回。
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md 的验收标准。
##
## 用法（分批，单进程 <45s）：
##   Godot --headless --path src --script res://tests/state_transition_lab_playtest.gd -- --batch=assembly,runjump,flight,collision,edge,focus,reset,ledger,repeat,hub
## 窗口截图（真实输入，非传送摆拍）：
##   Godot --path src --script res://tests/state_transition_lab_playtest.gd -- --capture-prefix=/abs/prefix --shot=overview,jump,flight,collision,focus,ledger,small
##
## 断言纪律：只经角色公开输入 API 驱动（真实 InputEventKey → 场景 _unhandled_input → 公开 API）；
## 读回组件公共字段与 TagRegistry.block_count 只读摘要；不调用私有能力方法、不写内部状态；
## 失败即退出码 1，不吞错、不放宽阈值。

const SCENE := "res://levels/experiments/character_movement/state_transition_lab.tscn"
const SCENE_SOURCE := "res://levels/experiments/character_movement/state_transition_lab.gd"
const LEDGER_SOURCE := "res://levels/experiments/character_movement/state_transition_lab_ledger.gd"
const ACTOR_SOURCE := "res://game/actors/swordsman/swordsman.gd"
const MOVEMENT_HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const MOVEMENT_HUB_NODE := "MovementLabHub"
const FLIGHT_TAG := &"sword_flight_block"
const CAPABILITY_SCRIPTS := [
	"res://game/actors/swordsman/swordsman_movement.gd",
	"res://game/abilities/jump/jump.gd",
	"res://game/abilities/sword_flight/sword_flight.gd",
]
## CapabilityManager.sorted_capabilities() 按 priority 降序返回：SwordFlight(100) → Jump(50) → SwordsmanMovement(0)。
const EXPECTED_CAPABILITIES := ["SwordFlight", "Jump", "SwordsmanMovement"]
const COMBAT_KEYWORDS := ["slash", "attack", "hitbox", "hurtbox", "damage", "projectile"]
const CAPTURE_TIMEOUT_MSEC := 15000
const POS_TOL := 0.08
const VERT_TOL := 0.06
const GRAVITY := 18.0
const MOVE_SPEED := 4.0
const FLIGHT_SPEED := 12.0

var _failed := 0
var _prefix := ""
var _only: PackedStringArray = []
var _shots: PackedStringArray = []
var _stage: Node3D
var _actor: Swordsman
var _motion: SwordsmanMotionComponent
var _manager: CapabilityManager
var _camera: Camera3D
var _frame_drawn := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
		elif argument.begins_with("--batch="):
			_only = argument.trim_prefix("--batch=").split(",", false)
		elif argument.begins_with("--shot="):
			_shots = argument.trim_prefix("--shot=").split(",", false)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var error := change_scene_to_file(SCENE)
	if error != OK:
		print("FAIL 无法加载压力场场景：%s（错误 %d）" % [SCENE, error])
		quit(1)
		return
	await scene_changed
	await _frames(8)
	_bind()
	if _actor == null:
		_check(false, "场景缺少 Swordsman 角色根")
		_finish()
		return
	if not _prefix.is_empty():
		await _run_capture()
		return
	await _run_batches()
	_finish()


func _run_batches() -> void:
	if _has("assembly"):
		print("--- batch assembly ---")
		await _batch_assembly()
	if _has("runjump"):
		print("--- batch runjump ---")
		await _batch_runjump()
	if _has("flight"):
		print("--- batch flight ---")
		await _batch_flight()
	if _has("collision"):
		print("--- batch collision ---")
		await _batch_collision()
	if _has("edge"):
		print("--- batch edge ---")
		await _batch_edge()
	if _has("focus"):
		print("--- batch focus ---")
		await _batch_focus()
	if _has("reset"):
		print("--- batch reset ---")
		await _batch_reset()
	if _has("ledger"):
		print("--- batch ledger ---")
		await _batch_ledger()
	if _has("repeat"):
		print("--- batch repeat ---")
		await _batch_repeat()
	if _has("hub"):
		print("--- batch hub ---")
		await _batch_hub()


func _has(batch: String) -> bool:
	return _only.is_empty() or _only.has(batch)


# --- 装配 -------------------------------------------------------------------


func _batch_assembly() -> void:
	await _reset_via_r()
	_check(_camera != null and _manager != null and _motion != null, "角色 / 能力管理器 / 组件 / 相机齐备")
	if _manager == null:
		return
	var caps := _manager.sorted_capabilities()
	var names: Array[String] = []
	for cap in caps:
		names.append(str(cap.get_script().get_global_name()))
	_check(names == EXPECTED_CAPABILITIES, "三能力按调度顺序装配：%s" % str(names))
	_check(caps.size() == 3, "恰有三项能力，未新增第四项（实际 %d）" % caps.size())
	_check(not _has_combat_rig(), "角色子树无战斗语义节点")

	# 场景静态边界：只调公开 API，不写组件 / capability / velocity / TagRegistry，不提交物理。
	# 只扫描去注释后的代码：文档注释里说明「唯一 move_and_slide 在 actor 根」不算违规。
	var scene_source := _strip_comments(FileAccess.get_file_as_string(SCENE_SOURCE))
	for forbidden in ["desired_horizontal", "desired_vertical", "vertical_impulse",
			"flight_active =", "on_floor =", "add_block", "remove_block", "clear_all",
			"move_and_slide", "velocity =", "velocity.x =", "velocity.y =", "velocity.z =",
			".tick("]:
		_check(not scene_source.contains(forbidden), "场景源码不出现「%s」" % forbidden)
	for capability_class in ["SwordsmanMovement", "SwordFlight"]:
		_check(not scene_source.contains(capability_class + ".") and not scene_source.contains("new() as " + capability_class),
			"场景不实例化能力类：%s" % capability_class)
	_check(scene_source.contains("movement_lab_input.gd"), "场景使用 MovementLabInput helper")
	_check(scene_source.contains("reset_motion()"), "重置走公开 reset_motion()")
	_check(scene_source.contains("clear_input()"), "失焦走公开 clear_input()")

	# 账本只格式化调用方传入的只读快照：不得认识运行时对象，也不得写任何运动量。
	var ledger_source := _strip_comments(FileAccess.get_file_as_string(LEDGER_SOURCE))
	for forbidden in ["TagRegistry", "Swordsman", "Capability", "Component", "get_node",
			"velocity =", "actual_velocity =", "flight_active =", "on_floor ="]:
		_check(not ledger_source.contains(forbidden), "账本模块不引用 / 不写「%s」" % forbidden)

	_check(_check_single_commit_point(), "actor 根是唯一物理提交点，能力不提交物理")
	_check(_has_return_link(), "场景声明返回子实验目录")

	# 起点落在阵盘内、着地、无阻塞残留。
	_check(await _wait_floor(120), "初始着地")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "初始无御剑阻塞残留")
	_check(absf(_actor.global_position.y) < 0.2, "起点在阵盘顶面（y=%.3f）" % _actor.global_position.y)


func _check_single_commit_point() -> bool:
	var actor_source := FileAccess.get_file_as_string(ACTOR_SOURCE)
	var ok := _call_count(actor_source, "move_and_slide") == 1
	for path in CAPABILITY_SCRIPTS:
		ok = ok and _call_count(FileAccess.get_file_as_string(path), "move_and_slide") == 0
	ok = ok and _call_count(FileAccess.get_file_as_string(SCENE_SOURCE), "move_and_slide") == 0
	return ok


func _has_return_link() -> bool:
	var source := FileAccess.get_file_as_string(SCENE_SOURCE)
	return source.contains(MOVEMENT_HUB_SCENE)


func _has_combat_rig() -> bool:
	for node in _actor.find_children("*", "", true, false):
		var lower := node.name.to_lower()
		for keyword in COMBAT_KEYWORDS:
			if lower.contains(keyword):
				return true
	return false


# --- 跑动 → 跳跃 → 落地 -------------------------------------------------------


func _batch_runjump() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120), "跑跳用例着地")
	var ledger := _ledger_ref()
	var start_events: int = ledger.event_count()
	var start := _actor.global_position

	# 跑动：按住 D 到出现真实水平速度。
	_key(KEY_D, true)
	await _frames(14)
	var running_speed := Vector2(_actor.velocity.x, _actor.velocity.z).length()
	_check(running_speed > MOVE_SPEED * 0.8, "真实按键跑动建立水平速度（%.2f m/s）" % running_speed)
	_check(_motion.move_input != Vector2.ZERO, "移动意图由公开 API 写入")

	# 跳跃：空格边沿，起跳当帧竖直冲量被 actor 消费。
	var floor_y := _actor.global_position.y
	_key(KEY_SPACE, true)
	# 起跳当帧即离地；取弧线内首帧离地，避免恰好读到落地帧造成假失败。
	var left_floor := false
	var apex := floor_y
	for _index in range(12):
		await physics_frame
		left_floor = left_floor or not _motion.on_floor
		apex = maxf(apex, _actor.global_position.y)
		if _index == 0:
			_key(KEY_SPACE, false)
	var _sanity := floor_y
	var landed := false
	for _index in range(200):
		await physics_frame
		apex = maxf(apex, _actor.global_position.y)
		if _index > 8 and _motion.on_floor and _actor.global_position.y <= floor_y + POS_TOL:
			landed = true
			break
	_key(KEY_D, false)
	await _frames(3)
	_check(left_floor, "空格边沿后离开地面")
	_check(apex - floor_y > 0.7 and apex - floor_y < 1.3, "跳跃顶点约 1.0 m（实际 %.2f）" % (apex - floor_y))
	_check(landed, "跳跃后真实落回地面（y=%.2f）" % _actor.global_position.y)
	_check(Vector2(_actor.velocity.x, _actor.velocity.z).length() < 0.01, "松开移动键后水平速度归零")

	# 账本必须记录到这次转换，且内容来自实际读数。
	var events: Array[Dictionary] = ledger.events()
	_check(ledger.event_count() > start_events, "账本记录了跑跳转换（+%d 条）" % (ledger.event_count() - start_events))
	var jump_rows := _rows_with_tag(events, "jump_edge")
	_check(not jump_rows.is_empty(), "账本含起跳边沿事件")
	if not jump_rows.is_empty():
		var row: Dictionary = jump_rows[0]
		# 账本记录的是 actor 消费边沿之后的同帧事实：冲量已施加，因此此刻已离地、竖直速度为正。
		_check(str(row["jump_cap"]) == "1", "起跳边沿事件记录 Jump 能力当帧激活")
		_check(str(row["block"]) == "0", "起跳边沿事件记录无阻塞")
		_check(str(row["flight"]) == "false", "起跳边沿事件记录御剑为 false")
		_check(str(row["on_floor"]) == "false", "起跳边沿事件记录起跳后已离地（同帧事实）")
		_check(str(row["velocity"]).begins_with("(") and not str(row["velocity"]).begins_with("(0.00, 0.00, 0.00"),
			"起跳边沿事件记录了非零速度读数：%s" % row["velocity"])


# --- 地面 → 御剑 → 升降 → 关飞 → 恢复重力 / 落地 --------------------------------


func _batch_flight() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120), "御剑用例着地")
	var floor_y := _actor.global_position.y
	var ledger := _ledger_ref()

	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	await _frames(2)
	_check(_motion.flight_active, "F 边沿开启御剑")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "御剑登记恰好一条阻塞")
	_check(_actor.velocity.y > 2.0, "地面开启产生升起速度（vy=%.2f）" % _actor.velocity.y)

	# 上升：空格。
	_key(KEY_SPACE, true)
	await _frames(16)
	var lifted_y := _actor.global_position.y
	_check(_actor.velocity.y > 4.0, "空格上升（vy=%.2f）" % _actor.velocity.y)
	_key(KEY_SPACE, false)
	await _frames(14)
	var hover_y := _actor.global_position.y
	await _frames(20)
	_check(absf(_actor.velocity.y) < VERT_TOL and absf(_actor.global_position.y - hover_y) < 0.12,
		"松键悬停：竖直速度 ≈ 0 且高度稳定")

	# 下降：Ctrl。先爬升到离地足够高：贴地时 move_and_slide 会把向下速度归零（落地修正），
	# 那属于「撞地」而不是「下降失败」，测试必须先把角色放到真正悬空的位置。
	_key(KEY_SPACE, true)
	await _frames(45)
	_key(KEY_SPACE, false)
	await _frames(10)
	var high_y := _actor.global_position.y
	_check(high_y > 2.0, "Ctrl 用例前已升到离地 %.2f m" % (high_y - floor_y))
	_key(KEY_CTRL, true)
	await _frames(16)
	_check(_actor.velocity.y < -4.0, "Ctrl 下降（vy=%.2f）" % _actor.velocity.y)
	_check(_actor.global_position.y < high_y - 0.5, "Ctrl 期间真实下降（%.2f → %.2f）" % [high_y, _actor.global_position.y])
	_key(KEY_CTRL, false)
	await _frames(4)

	# 关飞：同帧恢复重力（tick 后读 flight_active=false 合成速度，不是下一帧）。
	_key(KEY_SPACE, true)
	await _frames(40)
	_key(KEY_SPACE, false)
	await _frames(8)
	_check(_actor.global_position.y > 1.5, "关飞用例前处于空中（y=%.2f）" % _actor.global_position.y)
	var before_off := _actor.velocity.y
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	await _frames(1)
	_check(not _motion.flight_active, "F 边沿关闭御剑")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "关飞后阻塞清账")
	var after_off := _actor.velocity.y
	_check(after_off < before_off, "关飞当帧起竖直速度下降（%.2f → %.2f）" % [before_off, after_off])

	# 恢复重力并真实落地。
	var landed := false
	for _index in range(300):
		await physics_frame
		if _index > 6 and _motion.on_floor and _actor.global_position.y <= floor_y + POS_TOL:
			landed = true
			break
	_check(landed, "关飞后恢复重力并落地（y=%.2f）" % _actor.global_position.y)
	_check(absf(_actor.velocity.y) < VERT_TOL, "落地后竖直速度归零（vy=%.3f）" % _actor.velocity.y)

	# 账本记录了升降与关飞，且飞行读数一致。
	# 账本记录 actor 消费边沿之后的同帧事实：开启行 flight=true/block=1，关闭行 flight=false/block=0。
	var flight_rows := _rows_with_tag(ledger.events(), "flight_edge")
	_check(flight_rows.size() >= 2, "账本含开启与关闭两条御剑边沿（实际 %d）" % flight_rows.size())
	if flight_rows.size() >= 2:
		var open_row: Dictionary = flight_rows[0]
		var close_row: Dictionary = flight_rows[flight_rows.size() - 1]
		_check(str(open_row["flight"]) == "true" and str(open_row["block"]) == "1",
			"开启行记录同帧事实 flight=true / block=1（实际 %s / %s）" % [open_row["flight"], open_row["block"]])
		_check(str(open_row["flight_cap"]) == "1", "开启行记录 SwordFlight 当帧激活")
		_check(str(close_row["flight"]) == "false" and str(close_row["block"]) == "0",
			"关闭行记录同帧事实 flight=false / block=0（实际 %s / %s）" % [close_row["flight"], close_row["block"]])
	_check(lifted_y > floor_y + 0.4, "御剑真实升离地面（%.2f → %.2f）" % [floor_y, lifted_y])


# --- 撞墙期间切御剑 -----------------------------------------------------------


func _batch_collision() -> void:
	var wall := _stage.get_node_or_null("TrialCollision/GateWallEast")
	_check(wall != null, "石门北墙碰撞体存在")
	if wall == null:
		return
	var wall_z := (wall as StaticBody3D).position.z
	var wall_face := wall_z + 0.55
	await _reset_via_r()
	# 传送到墙前（物理摆位属场景权限，不算写组件状态）；不用 reset 以免清掉后续输入。
	_actor.global_position = Vector3(3.25, 0.05, wall_face + 2.0)
	await _frames(6)
	_check(await _wait_floor(120), "撞墙用例着地")

	# 真实按键向墙推进：接触 + 不穿透。相机是斜俯视，W 不等于世界 -Z——
	# 因此按相机地面基换算按键（与群山回归同一做法），否则会斜穿门洞而测不到墙。
	var push_target := Vector3(3.25, 0.0, wall_face - 4.0)
	var contact_frames := 0
	var violations := 0
	var deepest := 0.0
	for _index in range(200):
		if _index % 4 == 0:
			_drive_toward(push_target)
		await physics_frame
		if _slide_contacts(wall):
			contact_frames += 1
		var z := _actor.global_position.z
		if z < wall_face - 0.05:
			violations += 1
			deepest = maxf(deepest, wall_face - 0.05 - z)
	_release_move_keys()
	await _frames(3)
	_check(contact_frames > 0, "真实按键与 GateWallEast 发生滑动接触（%d 帧）" % contact_frames)
	_check(violations == 0, "接触期间不穿透墙面（违规帧 %d，最深 %.3f m）" % [violations, deepest])
	_check(absf(_actor.global_position.x - 3.25) < 1.6,
		"推进过程保持在东墙段范围内（x=%.2f）" % _actor.global_position.x)

	# 撞墙期间切御剑：水平推进被墙截断，但状态与阻塞登记正确，且仍可垂直升起。
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	_key(KEY_SPACE, true)
	for _index in range(30):
		if _index % 4 == 0:
			_drive_toward(push_target)
		await physics_frame
	_key(KEY_SPACE, false)
	await _frames(4)
	_check(_motion.flight_active, "撞墙期间开启御剑成功")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "撞墙期间阻塞恰好一条")
	_check(_actor.global_position.z > wall_face - 0.05,
		"御剑水平推进被墙挡住（z=%.2f，墙面 %.2f）" % [_actor.global_position.z, wall_face])
	_check(_actor.global_position.y > 0.5, "撞墙期间御剑仍可垂直升起（y=%.2f）" % _actor.global_position.y)

	# 关飞后清账且仍不穿墙。
	_release_move_keys()
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	await _frames(10)
	_check(not _motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "撞墙用例关飞后清账")
	_check(_actor.global_position.z > wall_face - 0.05, "关飞后仍在墙外侧")
	await _reset_via_r()


# --- 边缘离地时的跳跃 / 御剑优先级 ----------------------------------------------


func _batch_edge() -> void:
	var ledge := _stage.get_node_or_null("TrialCollision/EdgeLedge")
	_check(ledge != null, "边缘低台碰撞体存在")
	await _reset_via_r()
	# 站在低台边缘（顶面 y=0.5），朝外走出边缘。
	_actor.global_position = Vector3(-6.0, 0.55, 5.9)
	await _frames(8)
	_check(await _wait_floor(120, 0.45), "边缘用例先站上低台（y=%.2f）" % _actor.global_position.y)
	var ledge_y := _actor.global_position.y

	# ① 边缘离地当帧按空格：on_floor 为 false 时 Jump 不得激活。
	_key(KEY_S, true)
	var left := false
	var jumped_on_leave := false
	for _index in range(90):
		await physics_frame
		if not _motion.on_floor:
			left = true
		if left and not _motion.on_floor:
			# 离地后立刻按一次空格：应无效。
			_key(KEY_SPACE, true)
			await physics_frame
			_key(KEY_SPACE, false)
			if _actor.velocity.y > 1.0:
				jumped_on_leave = true
			break
	_check(left, "走出低台后离地（y=%.2f）" % _actor.global_position.y)
	_check(not jumped_on_leave, "空中按下空格不产生起跳冲量（vy=%.2f）" % _actor.velocity.y)

	# ② 空中同帧 F+Space：SwordFlight(100) 先接管，Jump(50) 被阻塞，无补跳。
	_key(KEY_F, true)
	_key(KEY_SPACE, true)
	await _frames(1)
	_key(KEY_F, false)
	_key(KEY_SPACE, false)
	await _frames(3)
	_check(_motion.flight_active, "空中同帧 F+Space：御剑开启")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "空中同帧 F+Space：阻塞恰好一条")
	var jump_cap := _manager.get_node_or_null("Jump")
	_check(jump_cap != null and not (jump_cap as Capability).active, "空中同帧 F+Space：Jump 未激活")
	_check(_actor.velocity.y <= 7.0 + 0.01, "空中接管首帧竖直速度被限幅（vy=%.2f）" % _actor.velocity.y)

	# ③ 落地清账：关飞后回到地面，阻塞为零。
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	_key(KEY_S, false)
	var landed := false
	for _index in range(300):
		await physics_frame
		if _index > 6 and _motion.on_floor and absf(_actor.global_position.y - ledge_y + 0.5) < 0.6:
			landed = true
			break
	_check(landed or _motion.on_floor, "边缘用例最终着地（y=%.2f）" % _actor.global_position.y)
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "边缘用例结束后无阻塞残留")
	await _reset_via_r()


# --- 按住 + 失焦 → 输入清零但飞行保留悬停 ---------------------------------------


func _batch_focus() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120), "失焦用例着地")
	# 先开御剑并上升。
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	await _frames(25)
	_key(KEY_W, true)
	_key(KEY_SPACE, true)
	await _frames(14)
	var hover_y := _actor.global_position.y
	_check(_motion.flight_active, "失焦前御剑已开启")

	# 真实失焦通知：场景公开 clear_input()，飞行状态按契约保留。
	current_scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(3)
	_check(_motion.flight_active, "失焦不关闭已开启的御剑（按既有契约保留）")
	_check(_motion.move_input == Vector2.ZERO and _motion.vertical_input == 0.0,
		"失焦清水平与升降输入")
	_check(_helper_held_count() == 0, "失焦清空场景输入缓存（按住键数 0）")
	var input_state: Dictionary = current_scene.call("input_state")
	_check(input_state["held_count"] == 0 and input_state["move_input"] == Vector2.ZERO
		and input_state["vertical_input"] == 0.0, "输入快照与清零一致：%s" % str(input_state))
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "失焦后阻塞仍在（御剑未退出）")
	# 场景输入缓存也必须清空：真实按键释放不再产生输入（键已松但 helper 也清了）。
	_key(KEY_W, false)
	_key(KEY_SPACE, false)
	await _frames(18)
	_check(absf(_actor.velocity.y) < VERT_TOL, "失焦后竖直速度 ≈ 0（悬停，vy=%.3f）" % _actor.velocity.y)
	_check(absf(_actor.global_position.y - hover_y) < 0.8, "失焦后高度稳定（Δ%.2f m）" % (_actor.global_position.y - hover_y))

	# 失焦期间再按键应重新生效（显示读回：按住计数 > 0 且速度变化）。
	_key(KEY_SPACE, true)
	await _frames(10)
	_check(_actor.velocity.y > 4.0, "失焦后重新按键仍生效（vy=%.2f）" % _actor.velocity.y)
	_key(KEY_SPACE, false)

	# R 才关闭御剑并清账。
	await _reset_via_r()
	_check(not _motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "R 关闭御剑并清账")


# --- R → 位置 / 运动 / 阻塞统一清账 -------------------------------------------


func _batch_reset() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120), "重置用例着地")
	# 造出「脏状态」：御剑 + 移动 + 上升 + 阻塞。
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	_key(KEY_D, true)
	_key(KEY_SPACE, true)
	await _frames(20)
	_check(_motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "重置前处于御剑 + 阻塞")
	_check(_actor.global_position.distance_to(Vector3(0.0, 0.05, 2.6)) > 0.5, "重置前已偏离起点")

	await _reset_via_r()
	_check(_actor.global_position.distance_to(Vector3(0.0, 0.05, 2.6)) < 0.3,
		"R 后位置回起点（%s）" % str(_actor.global_position))
	_check(not _motion.flight_active, "R 后 flight_active 为 false")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "R 后阻塞清账")
	_check(_actor.velocity.length() < 0.01, "R 后速度归零")
	_check(_motion.move_input == Vector2.ZERO and _motion.vertical_input == 0.0, "R 后输入归零")
	_check(_helper_held_count() == 0, "R 后场景输入缓存清空（按住键数 0）")

	# 下一 tick 仍然清账（阻塞不得被重新登记）。
	await _frames(5)
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "R 后 5 帧仍无阻塞（未重新登记）")
	# 松开真实按键，避免影响后续批次。
	_key(KEY_D, false)
	_key(KEY_SPACE, false)
	await _frames(2)


# --- 账本来自实际读数 ---------------------------------------------------------


func _batch_ledger() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120), "账本用例着地")
	var ledger := _ledger_ref()
	_check(ledger != null, "场景提供账本对象")
	if ledger == null:
		return
	var before: int = ledger.event_count()
	# 一次完整转换：起跳 → 落地。
	_key(KEY_SPACE, true)
	await _frames(1)
	_key(KEY_SPACE, false)
	_check(await _wait_floor(240), "账本用例完成一次跳跃落地")
	_check(ledger.event_count() > before, "账本随真实转换增长（+%d）" % (ledger.event_count() - before))

	# 逐条核对：每条事件的字段必须是合法读数（不是占位或推测）。
	var events: Array[Dictionary] = ledger.events()
	var invalid := 0
	for event in events:
		var tag := str(event["tag"])
		if tag == "prepare" or tag == "state":
			continue
		if str(event["on_floor"]) not in ["true", "false"]:
			invalid += 1
		if str(event["flight"]) not in ["true", "false"]:
			invalid += 1
		if str(event["block"]) not in ["0", "1", "2"]:
			invalid += 1
	_check(invalid == 0, "账本所有事件字段都是真实布尔 / 计数读数（非法 %d）" % invalid)

	# 账本中记录的 block 与当时的 flight 必须语义一致：
	# 凡记录 flight=true 的事件，block 必须 ≥ 1（御剑期间必登记阻塞）。
	var inconsistent := 0
	for event in events:
		if str(event["flight"]) == "true" and int(str(event["block"])) < 1:
			inconsistent += 1
	_check(inconsistent == 0, "账本中飞行事件必然带阻塞登记（不一致 %d）" % inconsistent)

	# 账本摘要与事件数一致。
	_check(ledger.summary_text().contains(str(ledger.event_count())), "摘要文本包含真实事件数：%s" % ledger.summary_text())
	# 账本绝不显示未观察到的能力态：能力列取值为 -1 / 0 / 1。
	var bad_cap := 0
	for event in events:
		for key in ["jump_cap", "flight_cap", "move_cap"]:
			if int(event[key]) not in [-1, 0, 1]:
				bad_cap += 1
	_check(bad_cap == 0, "能力诊断列只有 -1/0/1（非法 %d）" % bad_cap)

	# 账本的时间线读数与当前实际状态一致（同一帧内交叉核对）。
	var live_block := TagRegistry.block_count(_actor, FLIGHT_TAG)
	_check(live_block == 0, "交叉核对：当前无阻塞，与账本最后一条一致（%d）" % live_block)


# --- 可重复性 ---------------------------------------------------------------


func _batch_repeat() -> void:
	# 同一序列跑两遍，逐项读数必须一致（证明转换可重复、无残留状态）。
	var first := await _measure_jump_apex()
	var second := await _measure_jump_apex()
	_check(first["apex"] > 0.7, "第一遍跳跃顶点有效（%.2f）" % first["apex"])
	_check(absf(first["apex"] - second["apex"]) < 0.12,
		"两遍序列顶点一致（%.2f / %.2f）" % [first["apex"], second["apex"]])
	_check(first["takeoffs"] == 1 and second["takeoffs"] == 1,
		"两遍各只起跳一次（%d / %d）" % [first["takeoffs"], second["takeoffs"]])
	_check(second["block_after"] == 0, "第二遍结束后无阻塞残留")

	# 御剑开关两遍：状态序列必须一致。
	var on1 := await _measure_flight_cycle()
	var on2 := await _measure_flight_cycle()
	_check(on1["opened"] and on2["opened"], "两遍御剑都能开启")
	_check(on1["cleared_after_off"] and on2["cleared_after_off"], "两遍关飞都清账")
	_check(on1["block_while_flying"] == 1 and on2["block_while_flying"] == 1, "两遍御剑期间都恰好一条阻塞")


func _measure_jump_apex() -> Dictionary:
	await _reset_via_r()
	await _wait_floor(120)
	var floor_y := _actor.global_position.y
	var takeoffs := 0
	var was_floor := true
	var apex := floor_y
	_key(KEY_SPACE, true)
	for _index in range(200):
		_key_echo(KEY_SPACE)
		await physics_frame
		apex = maxf(apex, _actor.global_position.y)
		if was_floor and not _motion.on_floor:
			takeoffs += 1
		was_floor = _motion.on_floor
		if _index > 10 and _motion.on_floor and _actor.global_position.y <= floor_y + POS_TOL:
			break
	_key(KEY_SPACE, false)
	await _frames(3)
	return {
		"apex": apex - floor_y,
		"takeoffs": takeoffs,
		"block_after": TagRegistry.block_count(_actor, FLIGHT_TAG),
	}


func _measure_flight_cycle() -> Dictionary:
	await _reset_via_r()
	await _wait_floor(120)
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	await _frames(8)
	var opened := _motion.flight_active
	var block_while := TagRegistry.block_count(_actor, FLIGHT_TAG)
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	await _frames(4)
	var cleared := not _motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 0
	await _reset_via_r()
	await _wait_floor(180)
	return {"opened": opened, "block_while_flying": block_while, "cleared_after_off": cleared}


# --- hub 返回 ---------------------------------------------------------------


func _batch_hub() -> void:
	await _reset_via_r()
	await _frames(5)
	# 返回按钮文本与目标一致（层级语义防漂移）。
	var return_button := current_scene.find_child("ReturnButton", true, false) as Button
	_check(return_button != null and return_button.text == "返回子实验目录",
		"返回按钮文本指向子实验目录：%s" % (return_button.text if return_button != null else "<缺失>"))
	var controls := current_scene.find_child("Controls", true, false) as Label
	_check(controls != null and controls.text.contains("返回子实验目录"), "控制提示指向子实验目录")

	_key(KEY_ESCAPE, true)
	await _frames(2)
	_key(KEY_ESCAPE, false)
	await _frames(10)
	_check(current_scene != null and current_scene.name == MOVEMENT_HUB_NODE,
		"Esc 返回角色移动子实验目录（%s）" % (current_scene.name if current_scene != null else "<null>"))
	_check(TagRegistry._blocks.is_empty(), "切换场景后无阻塞残留")


# --- 截图（窗口模式；转换必须由真实输入产生） -----------------------------------


func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "无头渲染器无法截图，请用窗口模式运行")
		_finish()
		return
	await _wait_render_frames(48)
	root.get_texture().get_image()
	await _frames(4)
	if _should_shot("overview"):
		await _capture("overview")
	if _should_shot("jump"):
		await _reset_via_r()
		await _wait_floor(120)
		_key(KEY_D, true)
		await _frames(12)
		# 在跳跃弧线顶点附近（起跳后约 18 帧）取图，让「离地」这一转换在画面里真实可见。
		_key(KEY_SPACE, true)
		await _frames(1)
		_key(KEY_SPACE, false)
		await _frames(18)
		print("SNAPJUMP on_floor=%s y=%.2f" % [str(_motion.on_floor), _actor.global_position.y])
		await _capture("jump-transition")
		_key(KEY_D, false)
		await _frames(3)
	if _should_shot("flight"):
		await _reset_via_r()
		await _wait_floor(120)
		_key(KEY_F, true)
		await _frames(1)
		_key(KEY_F, false)
		await _frames(30)
		_key(KEY_SPACE, true)
		await _frames(14)
		_key(KEY_SPACE, false)
		await _capture("flight-transition")
		await _reset_via_r()
	if _should_shot("collision"):
		# 边缘离地：站上低台后朝南走出边缘（按相机地面基驱动，斜俯视下 S 不等于世界 +Z）。
		_actor.global_position = Vector3(-6.0, 0.55, 5.9)
		await _frames(8)
		await _wait_floor(120, 0.45)
		# 目标点仍在阵盘内：离台后立即松开按键，避免角色继续走出盘沿触发掉出回收，
		# 让截图真实呈现「边缘离地」那一刻而不是回收之后。
		var walk_target := Vector3(-6.0, 0.0, 6.4)
		for _index in range(60):
			if _index % 4 == 0:
				_drive_toward(walk_target)
			await physics_frame
			if not _motion.on_floor:
				break
		_release_move_keys()
		await _capture("edge-leave")
		# 边缘离地当帧同按 F+Space：验证御剑优先接管、Jump 不激活，再截图。
		_key_now(KEY_SPACE, true)
		_key(KEY_F, true)
		await _frames(1)
		_key(KEY_F, false)
		_key_now(KEY_SPACE, false)
		await _frames(18)
		await _capture("edge-flight-priority")
		_release_move_keys()
		await _reset_via_r()
		# 撞墙：按相机地面基推进到石门东墙，接触期间截图。
		var wall := _stage.get_node_or_null("TrialCollision/GateWallEast") as StaticBody3D
		if wall != null:
			_actor.global_position = Vector3(3.25, 0.05, wall.position.z + 0.55 + 2.5)
			await _frames(8)
			await _wait_floor(120)
			var push_target := Vector3(3.25, 0.0, wall.position.z - 3.0)
			for _index in range(120):
				if _index % 4 == 0:
					_drive_toward(push_target)
				await physics_frame
				if _slide_contacts(wall):
					break
			await _capture("wall-contact")
			_release_move_keys()
			await _reset_via_r()
	if _should_shot("focus"):
		await _reset_via_r()
		await _wait_floor(120)
		_key(KEY_F, true)
		await _frames(1)
		_key(KEY_F, false)
		await _frames(25)
		_key(KEY_W, true)
		_key(KEY_SPACE, true)
		await _frames(12)
		_key(KEY_W, false)
		_key(KEY_SPACE, false)
		current_scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await _frames(30)
		await _capture("focus-hover")
		await _reset_via_r()
	if _should_shot("reset"):
		_key(KEY_F, true)
		await _frames(1)
		_key(KEY_F, false)
		_key(KEY_D, true)
		_key(KEY_SPACE, true)
		await _frames(20)
		_key(KEY_D, false)
		_key(KEY_SPACE, false)
		await _capture("before-reset")
		await _reset_via_r()
		await _frames(4)
		await _capture("after-reset")
	if _should_shot("ledger"):
		# 跑一段代表序列让账本出现多样事件，再截图。
		await _run_ledger_fill()
		await _capture("ledger-timeline")
	if _should_shot("small"):
		root.size = Vector2i(960, 640)
		await _frames(8)
		await _capture("small")
	_finish()


func _run_ledger_fill() -> void:
	await _reset_via_r()
	await _wait_floor(120)
	_key(KEY_D, true)
	await _frames(10)
	_key(KEY_SPACE, true)
	await _frames(1)
	_key(KEY_SPACE, false)
	await _wait_floor(240)
	_key(KEY_D, false)
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	await _frames(20)
	current_scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(6)
	await _reset_via_r()
	await _wait_floor(120)


func _should_shot(name: String) -> bool:
	return _shots.is_empty() or _shots.has(name)


func _capture(suffix: String) -> void:
	if _prefix.is_empty():
		return
	var deadline := Time.get_ticks_msec() + CAPTURE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _frame_drawn:
			break
	var path := "%s-%s.png" % [_prefix, suffix]
	var image := root.get_texture().get_image()
	if image == null:
		_check(false, "截图读回为空：" + suffix)
		return
	_check(image.save_png(path) == OK, "截图保存：" + suffix)
	print("SNAPSHOT %s flight=%s block=%d pos=%s ledger=%s" % [
		suffix, str(_motion.flight_active), TagRegistry.block_count(_actor, FLIGHT_TAG),
		str(_actor.global_position.round()), _ledger_ref().summary_text(),
	])


# --- 工具 -------------------------------------------------------------------


func _bind() -> void:
	_stage = current_scene as Node3D
	_actor = current_scene.get_node_or_null("Swordsman") as Swordsman
	if _actor != null:
		_motion = _actor.motion()
		_manager = _actor.capability_manager()
	_camera = current_scene.get_node_or_null("%Camera3D") as Camera3D


## 经场景公开只读访问器读取输入按住计数（验证失焦 / 重置清账）。
func _helper_held_count() -> int:
	if current_scene == null:
		return -1
	return int(current_scene.call("input_held_count"))


## 经场景公开只读访问器读取账本（不触碰私有字段）。
func _ledger_ref() -> StateTransitionLedger:
	if current_scene == null:
		return null
	return current_scene.call("ledger") as StateTransitionLedger


func _rows_with_tag(events: Array[Dictionary], tag: String) -> Array:
	var rows: Array = []
	for event in events:
		if str((event as Dictionary)["tag"]) == tag:
			rows.append(event)
	return rows


func _reset_via_r() -> void:
	_key(KEY_R, true)
	await _frames(1)
	_key(KEY_R, false)
	await _frames(4)


func _wait_floor(max_frames: int, expected_y: float = INF) -> bool:
	for _index in range(max_frames):
		await physics_frame
		if _motion.on_floor:
			if expected_y == INF or absf(_actor.global_position.y - expected_y) < 0.12:
				return true
	return false


## 按相机地面基把世界方向换算成 WASD 按住状态（相机斜俯视时 W 不等于世界 -Z）。
func _drive_toward(target: Vector3) -> void:
	var flat := Vector3(target.x - _actor.global_position.x, 0.0, target.z - _actor.global_position.z)
	var x_axis := 0.0
	var y_axis := 0.0
	if flat.length_squared() > 0.01:
		var desired := flat.normalized()
		x_axis = desired.dot(_motion.camera_right)
		y_axis = -desired.dot(_motion.camera_forward)
	for pair in [[KEY_D, x_axis > 0.38], [KEY_A, x_axis < -0.38], [KEY_S, y_axis > 0.38], [KEY_W, y_axis < -0.38]]:
		_key_now(pair[0], pair[1])


func _release_move_keys() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key_now(code, false)


## 同步发出按住事件（不等待帧）：供逐帧推进的移动用例使用。
func _key_now(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _slide_contacts(node: Node) -> bool:
	if node == null or _actor == null:
		return false
	for index in range(_actor.get_slide_collision_count()):
		if _actor.get_slide_collision(index).get_collider() == node:
			return true
	return false


## 发出真实按键事件：当帧解析，下一帧才推进物理——与既有回归一致，保证边沿在真实 tick 内可见。
func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame


func _key_echo(code: Key) -> void:
	_key(code, true, true)


func _frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _wait_render_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


## 去行注释后的代码（与既有回归的静态检查同一口径，避免文档注释造成误判）。
func _strip_comments(source: String) -> String:
	var kept := PackedStringArray()
	for line in source.split("\n"):
		var text: String = line
		var cut := text.find("#")
		if cut >= 0:
			text = text.substr(0, cut)
		var trimmed := text.strip_edges()
		if not trimmed.is_empty():
			kept.append(trimmed)
	return "\n".join(kept)


func _call_count(source: String, call: String) -> int:
	var count := 0
	for line in source.split("
"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		count += stripped.count(call)
	return count


func _check(ok: bool, message: String) -> bool:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failed += 1
	return ok


func _finish() -> void:
	print("STATE_TRANSITION_LAB_PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)
