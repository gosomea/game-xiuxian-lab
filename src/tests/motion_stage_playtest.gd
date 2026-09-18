extends SceneTree

## 人物动作工作台验收：真实场景 + 真实 Swordsman + 真实输入事件 + 表现层读回。
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md 的验收标准。
##
## 用法（分批，单进程 <45s）：
##   Godot --headless --path src --script res://tests/motion_stage_playtest.gd -- --batch=assembly,idle,run,turn,jump,flight,landing,removal,hud,exit
## 窗口截图（真实输入，非传送摆拍）：
##   Godot --path src --script res://tests/motion_stage_playtest.gd -- --capture-prefix=/abs/prefix --shot=run,flight,landing,small
##
## 断言纪律：只经角色公开输入 API 驱动；读回 components 公共字段与表现层 pose_state()；
## 失败即退出码 1，不吞错、不放宽阈值。

const SCENE := "res://levels/experiments/character_movement/motion_stage.tscn"
const SWORDSMAN_SCENE := "res://game/actors/swordsman/swordsman.tscn"
const ACTOR_SOURCE := "res://game/actors/swordsman/swordsman.gd"
const PRESENTATION_SOURCE := "res://game/actors/swordsman/cultivator_presentation.gd"
## 工作台的固定返回目标（同提交依赖，不设顶层目录回退）。
const MOVEMENT_HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
## 三份能力脚本本体；actor 根是唯一物理提交点，不在其中。
const CAPABILITY_SCRIPTS := [
	"res://game/actors/swordsman/swordsman_movement.gd",
	"res://game/abilities/jump/jump.gd",
	"res://game/abilities/sword_flight/sword_flight.gd",
]
const EXPECTED_CAPABILITIES := ["SwordsmanMovement", "Jump", "SwordFlight"]
const CAPTURE_TIMEOUT_MSEC := 15000
const POS_TOL := 0.08
const VERT_TOL := 0.06

var _failed := 0
var _prefix := ""
var _only: PackedStringArray = []
var _shots: PackedStringArray = []
var _stage: Node3D
var _actor: Swordsman
var _motion: SwordsmanMotionComponent
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
		print("FAIL 无法加载工作台场景：%s（错误 %d）" % [SCENE, error])
		quit(1)
		return
	await scene_changed
	await _frames(6)
	_bind()
	if _actor == null:
		_check(false, "工作台缺少 Swordsman 角色根")
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
	if _has("idle"):
		print("--- batch idle ---")
		await _batch_idle()
	if _has("run"):
		print("--- batch run ---")
		await _batch_run()
	if _has("turn"):
		print("--- batch turn ---")
		await _batch_turn()
	if _has("jump"):
		print("--- batch jump ---")
		await _batch_jump()
	if _has("flight"):
		print("--- batch flight ---")
		await _batch_flight()
	if _has("landing"):
		print("--- batch landing ---")
		await _batch_landing()
	if _has("removal"):
		print("--- batch removal ---")
		await _batch_removal()
	if _has("hud"):
		print("--- batch hud ---")
		await _batch_hud()
	if _has("exit"):
		print("--- batch exit ---")
		await _batch_exit()


# --- 批次：装配 -------------------------------------------------------------


func _batch_assembly() -> void:
	var manager := _actor.get_node("CapabilityManager")
	var names := PackedStringArray()
	for child in manager.get_children():
		var capability_script: Script = child.get_script() as Script
		names.append(str(capability_script.get_global_name()) if capability_script != null else str(child.name))
	_check(names.size() == 3, "工作台角色恰好装配 3 个能力（实际 %s）" % str(names))
	for expected in EXPECTED_CAPABILITIES:
		_check(names.has(expected), "能力装配包含 %s（实际 %s）" % [expected, str(names)])
	_check(_actor.get_node_or_null("SwordsmanMotionComponent") != null, "角色挂载 SwordsmanMotionComponent")
	_check(_actor.get_node_or_null("Visual/CultivatorPresentation") != null, "角色挂载表现节点 CultivatorPresentation")

	# 唯一物理提交点：只有 actor 根调用 move_and_slide，工作台脚本与能力都不提交物理。
	# 注释与字符串里的说明文字不算调用，只统计真实代码行。
	var stage_source := _code_only(FileAccess.get_file_as_string("res://levels/experiments/character_movement/motion_stage.gd"))
	var actor_source := _code_only(FileAccess.get_file_as_string(ACTOR_SOURCE))
	_check(_call_count(stage_source, "move_and_slide") == 0, "工作台脚本不调用 move_and_slide")
	_check(_call_count(actor_source, "move_and_slide") == 1,
		"actor 根只有一处 move_and_slide（唯一物理提交点）")
	for path in CAPABILITY_SCRIPTS:
		_check(_call_count(_code_only(FileAccess.get_file_as_string(path)), "move_and_slide") == 0,
			"能力不自行提交物理：%s" % path.get_file())

	# 场景不引用具体 Capability 类名 / 脚本路径（节点名 "JumpRuler" 之类不算引用类名）。
	for capability in EXPECTED_CAPABILITIES:
		var pattern := "\b%s\b" % capability
		var regex := RegEx.new()
		regex.compile(pattern)
		_check(regex.search(stage_source) == null, "工作台不引用具体 Capability 类名：%s" % capability)

	# 场景只调用角色公开输入 API；不写 velocity、不写意图、不碰能力内部状态。
	for forbidden in [".velocity =", ".velocity.x =", ".velocity.z =", ".velocity.y =",
			"desired_horizontal =", "desired_vertical =", "vertical_impulse =",
			"flight_active =", "on_floor =", "camera_right =", "camera_forward ="]:
		_check(not stage_source.contains(forbidden), "工作台不写速度 / 意图 / 状态：%s" % forbidden)
	for axis in ["_should_activate", "_tick_active", "_on_activated", "_should_deactivate", "_on_deactivated"]:
		_check(not stage_source.contains(axis), "工作台不触碰能力五函数轴：%s" % axis)
	_check(not stage_source.contains("CapabilityManager"), "工作台不直接访问 CapabilityManager")
	for api in ["set_move_input(", "set_vertical_input(", "press_jump(", "press_flight_toggle(",
			"set_camera_ground_basis(", "set_aim_direction(", "reset_motion(", "clear_input("]:
		_check(stage_source.contains(api), "工作台经公开输入 API 驱动角色：%s" % api)

	# 场地标记：直跑道 / 八方向区 / 跳跃标尺 / 御剑起降区。
	_check(_stage.get_node_or_null("Runway") != null, "工作台含直跑道标记")
	_check(_stage.get_node_or_null("Runway").get_child_count() >= 12, "跑道刻度线按米生成")
	_check(_stage.get_node_or_null("TurnPad") != null and _stage.get_node("TurnPad").get_child_count() >= 9,
		"工作台含八方向 / 急转区（八条辐条 + 中心环）")
	_check(_stage.get_node_or_null("JumpRuler") != null, "工作台含跳跃标尺")
	_check(_stage.get_node_or_null("FlightPad") != null, "工作台含御剑起降区")

	# 标尺刻度由组件参数推导，不是硬编码读数。
	var apex: float = _motion.jump_speed * _motion.jump_speed / (2.0 * _motion.gravity)
	var labels := PackedStringArray()
	for node in _stage.get_node("JumpRuler").find_children("*", "Label3D", true, false):
		labels.append((node as Label3D).text)
	_check(labels.has("%.2f m" % apex), "跳跃标尺满分刻度等于组件推导顶点 %.2f m（实际 %s）" % [apex, str(labels)])

	# 场地物理：地面顶面 y=0，角色站立其上。
	_check(_actor.is_on_floor(), "出生后角色站在地面上")
	_check(absf(_actor.global_position.y) < 0.2, "出生高度贴地（y=%.2f）" % _actor.global_position.y)
	_check(_camera.projection == Camera3D.PROJECTION_ORTHOGONAL and _camera.current, "固定正交观察相机已激活")


# --- 批次：待机 -------------------------------------------------------------


func _batch_idle() -> void:
	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(20)
	var pose := _pose()
	_check(_motion.actual_velocity.length() < 0.05, "无输入时实际速度为零（%.3f）" % _motion.actual_velocity.length())
	_check(_motion.on_floor, "无输入时保持着地")
	_check(float(pose.get("gait", 1.0)) < 0.05, "待机时步态增益归零（%.3f）" % float(pose.get("gait", 1.0)))
	_check(absf(float(pose.get("leg_left", 1.0))) < 0.03, "待机时腿部枢轴回到静止位（%.3f）" % float(pose.get("leg_left", 1.0)))
	var first_phase := float(pose.get("phase", 0.0))
	await _frames(10)
	var second_phase := float(_pose().get("phase", 0.0))
	_check(is_equal_approx(first_phase, second_phase), "待机时相位不推进（%.3f -> %.3f）" % [first_phase, second_phase])


# --- 批次：跑动与停下归零 ---------------------------------------------------


func _batch_run() -> void:
	_place(Vector3(13.0, 0.05, 0.0))
	await _frames(4)
	var run_start := _actor.global_position
	_key(KEY_D, true)
	await _frames(14)
	var pose_a := _pose()
	var pos_a := _actor.global_position
	await _frames(6)
	var pose_b := _pose()
	var pos_b := _actor.global_position
	_key(KEY_D, false)

	_check(_motion.actual_velocity.length() >= _motion.move_speed - 0.05,
		"D 输入达到步行速度 %.2f（%.2f）" % [_motion.move_speed, _motion.actual_velocity.length()])
	# 屏幕相对：D 必须沿相机右方产生真实位移，不是只看世界 +X。
	var travelled := pos_b - run_start
	_check(travelled.length() > 0.5, "跑动产生真实位移（%.3f m）" % travelled.length())
	_check(travelled.normalized().dot(_motion.camera_right) > 0.9,
		"D 位移沿相机右方（dot=%.3f）" % travelled.normalized().dot(_motion.camera_right))
	_check(float(pose_a.get("gait", 0.0)) > 0.6, "跑动时步态增益升到高位（%.3f）" % float(pose_a.get("gait", 0.0)))
	var phase_delta := absf(float(pose_b.get("phase", 0.0)) - float(pose_a.get("phase", 0.0)))
	_check(phase_delta > 0.05 or absf(phase_delta - TAU) < 0.05,
		"两个时间点的步态相位不同（Δ=%.3f）证明动作在变化" % phase_delta)
	var leg_delta := absf(float(pose_b.get("leg_left", 0.0)) - float(pose_a.get("leg_left", 0.0)))
	_check(leg_delta > 0.005, "两个时间点左腿枢轴角度不同（Δ=%.4f）" % leg_delta)

	# 停下归零：速度、步态与枢轴角都回到静止。
	await _frames(30)
	var resting := _pose()
	_check(_motion.actual_velocity.length() < 0.05, "松开按键后速度归零（%.3f）" % _motion.actual_velocity.length())
	_check(float(resting.get("gait", 1.0)) < 0.05, "停下后步态增益归零（%.3f）" % float(resting.get("gait", 1.0)))
	_check(absf(float(resting.get("leg_left", 1.0))) < 0.03,
		"停下后腿部枢轴回到静止位（%.3f）" % float(resting.get("leg_left", 1.0)))
	_check(_motion.on_floor, "跑动停止后仍着地")

	# 斜向输入不超过组件速度上限（屏幕相对输入归一化）。
	_place(Vector3(-14.0, 0.05, 0.0))
	_key(KEY_D, true)
	_key(KEY_S, true)
	await _frames(10)
	_check(_motion.actual_velocity.length() <= _motion.move_speed + 0.05,
		"斜向输入不超过 move_speed（%.2f）" % _motion.actual_velocity.length())
	_key(KEY_D, false)
	_key(KEY_S, false)
	await _frames(10)


# --- 批次：方向反转 ---------------------------------------------------------


func _batch_turn() -> void:
	_place(Vector3(-6.0, 0.05, 0.0))
	_key(KEY_D, true)
	await _frames(18)
	_key(KEY_D, false)
	_key(KEY_A, true)
	var peak := 0.0
	for index in range(12):
		await _frames(1)
		peak = maxf(peak, float(_pose().get("turn", 0.0)))
	_key(KEY_A, false)
	_check(peak > 0.05, "方向反转触发转身响应（峰值 %.3f）" % peak)
	await _frames(24)
	var settled := _pose()
	_check(float(settled.get("turn", 1.0)) < 0.02, "转身响应衰减回零（%.3f）" % float(settled.get("turn", 1.0)))
	_check(float(settled.get("gait", 1.0)) < 0.05, "停下后步态归零（%.3f）" % float(settled.get("gait", 1.0)))

	# 八方向区：八个方向都能驱动角色（真实输入，逐向验证位移）。
	var directions := {
		"W": KEY_W, "S": KEY_S, "A": KEY_A, "D": KEY_D,
		"WA": KEY_W, "WD": KEY_W, "SA": KEY_S, "SD": KEY_S,
	}
	var pad_origin := Vector3(-11.5, 0.05, 5.0)
	for name in directions:
		_place(pad_origin)
		await _frames(3)
		var start := _actor.global_position
		_key(directions[name] as Key, true)
		if name.length() == 2:
			_key((directions["A"] if name.ends_with("A") else directions["D"]) as Key, true)
		await _frames(9)
		_key(directions[name] as Key, false)
		if name.length() == 2:
			_key((directions["A"] if name.ends_with("A") else directions["D"]) as Key, false)
		await _frames(2)
		_check(start.distance_to(_actor.global_position) > 0.2, "八方向区 %s 方向产生位移" % name)
	await _frames(6)


# --- 批次：跳跃 -------------------------------------------------------------


func _batch_jump() -> void:
	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(6)
	var ground_y := _actor.global_position.y
	_key(KEY_SPACE, true)
	await _frames(1)
	_key(KEY_SPACE, false)
	var airborne_peak := 0.0
	var apex := ground_y
	var rise_tuck := 0.0
	var landing_peak := 0.0
	var land_frames := 0
	for index in range(90):
		await _frames(1)
		var pose := _pose()
		airborne_peak = maxf(airborne_peak, float(pose.get("airborne", 0.0)))
		apex = maxf(apex, _actor.global_position.y)
		if float(pose.get("airborne", 0.0)) > 0.5:
			rise_tuck = maxf(rise_tuck, float(pose.get("leg_right", 0.0)) - float(pose.get("leg_left", 0.0)))
		landing_peak = maxf(landing_peak, float(pose.get("landing", 0.0)))
		if _motion.on_floor:
			land_frames += 1
			if land_frames >= 3:
				break
		else:
			land_frames = 0
	_check(airborne_peak > 0.5, "跳起后表现层进入腾空姿态（峰值 %.3f）" % airborne_peak)
	_check(apex - ground_y > 0.6, "跳跃产生真实高度（Δy=%.2f）" % (apex - ground_y))
	_check(landing_peak > 0.3, "落地触发压缩脉冲（峰值 %.3f）" % landing_peak)
	_check(_motion.on_floor, "跳跃后重新着地")
	var resting := _pose()
	await _frames(20)
	resting = _pose()
	_check(float(resting.get("airborne", 1.0)) < 0.05, "落地后腾空增益归零（%.3f）" % float(resting.get("airborne", 1.0)))
	_check(float(resting.get("landing", 1.0)) < 0.05, "落地脉冲衰减归零（%.3f）" % float(resting.get("landing", 1.0)))

	# 按住空格不连跳：起跳边沿只产生一次高度峰值。
	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(6)
	_key(KEY_SPACE, true)
	var peaks := 0
	var climbing := false
	for index in range(70):
		await _frames(1)
		var vy := _motion.actual_velocity.y
		if vy > 0.5 and not climbing:
			climbing = true
			peaks += 1
		elif vy < -0.5:
			climbing = false
	_key(KEY_SPACE, false)
	_check(peaks == 1, "按住空格只起跳一次（上升段 %d 次）" % peaks)
	await _frames(20)


# --- 批次：御剑 -------------------------------------------------------------


func _batch_flight() -> void:
	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(6)
	# 御剑视觉：剑是角色 Visual 子节点，显隐严格跟随 flight_active（actor 统一同步）。
	var sword: Node3D = _stage.flight_visual()
	_check(sword != null, "工作台装配御剑视觉节点 Visual/FlyingSword")
	_check(sword != null and not sword.visible, "未御剑时剑不可见")
	_toggle_flight()
	await _frames(8)
	_check(_motion.flight_active, "F 开启御剑")
	_check(sword != null and sword.visible, "御剑时剑可见")
	_check(float(_pose().get("flight", 0.0)) > 0.3, "表现层进入御剑姿态（%.3f）" % float(_pose().get("flight", 0.0)))

	# 地面启动后进入爬升：按 Space 持续上升。
	_key(KEY_SPACE, true)
	await _frames(20)
	var climbing := _pose()
	_check(_motion.actual_velocity.y > 1.0, "御剑按 Space 上升（vy=%.2f）" % _motion.actual_velocity.y)
	_check(float(climbing.get("flight", 0.0)) > 0.8, "上升时御剑增益饱和（%.3f）" % float(climbing.get("flight", 0.0)))
	var high_y := _actor.global_position.y
	_key(KEY_SPACE, false)
	# 悬停：松开升降键且没有水平输入时竖直速度为零。
	await _frames(20)
	_check(absf(_motion.actual_velocity.y) < 0.05, "松开升降键后悬停（vy=%.2f）" % _motion.actual_velocity.y)
	var hover_y := _actor.global_position.y
	await _frames(20)
	_check(absf(_actor.global_position.y - hover_y) < 0.12, "悬停期间高度稳定（Δy=%.3f）" % (_actor.global_position.y - hover_y))
	# 下降。
	_key(KEY_CTRL, true)
	await _frames(16)
	_check(_motion.actual_velocity.y < -1.0, "御剑按 Ctrl 下降（vy=%.2f）" % _motion.actual_velocity.y)
	_key(KEY_CTRL, false)
	await _frames(4)
	_check(_actor.global_position.y < high_y, "下降产生真实高度损失（%.2f -> %.2f）" % [high_y, _actor.global_position.y])

	# 水平飞行快于步行。
	_key(KEY_D, true)
	await _frames(16)
	_check(_motion.actual_velocity.length() >= _motion.flight_speed - 0.05,
		"御剑水平速度 %.2f（%.2f）" % [_motion.flight_speed, _motion.actual_velocity.length()])
	_key(KEY_D, false)
	await _frames(6)
	# 移动中开飞：从移动状态直接进入御剑并保持速度。
	_check(_motion.flight_active, "水平飞行期间御剑保持开启")

	# 悬停时表现层仍在读物理状态（不依赖动画帧）。
	var pose_a := _pose()
	await _frames(6)
	var pose_b := _pose()
	_check(float(pose_a.get("flight", 0.0)) > 0.9 and float(pose_b.get("flight", 0.0)) > 0.9,
		"悬停期间御剑增益保持饱和")
	_check(absf(float(pose_b.get("body_pitch", 0.0))) > 0.02,
		"御剑前倾体现在躯干俯仰（%.4f）" % float(pose_b.get("body_pitch", 0.0)))

	# 关飞：同帧恢复重力，落地并触发落地过渡。
	# 先升到有降落过程的高度，再关飞；落地脉冲在着地后才产生，
	# 因此检测到着地后必须继续采样若干帧，不能在第一帧就跳出。
	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(4)
	_toggle_flight()
	await _frames(4)
	_key(KEY_SPACE, true)
	await _frames(30)
	_key(KEY_SPACE, false)
	await _frames(4)
	var flight_height := _actor.global_position.y
	_check(flight_height > 2.0, "关飞前悬停在 %.2f m" % flight_height)
	_toggle_flight()
	await _frames(4)
	_check(not _motion.flight_active, "再按 F 关闭御剑")
	var landing_peak := 0.0
	var grounded := false
	for index in range(200):
		await _frames(1)
		landing_peak = maxf(landing_peak, float(_pose().get("landing", 0.0)))
		if _motion.on_floor:
			grounded = true
			break
	for index in range(12):
		await _frames(1)
		landing_peak = maxf(landing_peak, float(_pose().get("landing", 0.0)))
	_check(grounded, "关闭御剑后角色落回地面（从 %.2f m）" % flight_height)
	_check(landing_peak > 0.3, "关飞落地触发压缩脉冲（峰值 %.3f）" % landing_peak)
	await _frames(20)
	_check(float(_pose().get("flight", 1.0)) < 0.05, "落地后御剑增益归零（%.3f）" % float(_pose().get("flight", 1.0)))

	# 站立 → 御剑 → 关飞 的完整过渡在表现快照里可读。
	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(6)
	var before := _pose()
	_toggle_flight()
	await _frames(10)
	var during := _pose()
	_check(float(during.get("flight", 0.0)) > float(before.get("flight", 0.0)),
		"站立→御剑的增益在表现快照上单调上升（%.3f -> %.3f）" % [float(before.get("flight", 0.0)), float(during.get("flight", 0.0))])
	_toggle_flight()
	await _frames(4)
	_check(not _motion.flight_active, "关飞状态在组件上立即为假")
	await _frames(70)


# --- 批次：落地过渡与拆装 ---------------------------------------------------


func _batch_landing() -> void:
	# 空中关飞落地：从高处下降时关闭御剑，落地必须有一个压缩脉冲而不是硬着陆。
	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(4)
	_toggle_flight()
	await _frames(4)
	_key(KEY_SPACE, true)
	await _frames(45)
	_key(KEY_SPACE, false)
	await _frames(6)
	var high := _actor.global_position.y
	_check(high > 3.0, "御剑升至 %.2f m 用于落地过渡观察" % high)
	_toggle_flight()
	var landing_peak := 0.0
	var airborne_seen := 0.0
	var grounded := false
	for index in range(200):
		await _frames(1)
		var pose := _pose()
		airborne_seen = maxf(airborne_seen, float(pose.get("airborne", 0.0)))
		landing_peak = maxf(landing_peak, float(pose.get("landing", 0.0)))
		if _motion.on_floor:
			grounded = true
			break
	for index in range(12):
		await _frames(1)
		landing_peak = maxf(landing_peak, float(_pose().get("landing", 0.0)))
	_check(grounded, "空中关飞后落回地面（从 %.2f m）" % high)
	_check(airborne_seen > 0.5, "落地前经历腾空姿态（峰值 %.3f）" % airborne_seen)
	_check(landing_peak > 0.3, "空中落地触发压缩脉冲（峰值 %.3f）" % landing_peak)
	await _frames(24)
	_check(float(_pose().get("landing", 1.0)) < 0.05, "落地脉冲衰减归零")
	_check(_motion.on_floor and not _motion.flight_active, "落地后状态为着地且未御剑")


func _batch_removal() -> void:
	# 删除表现节点后三能力仍正确：移动、跳跃、御剑全部照常，且无脚本错误。
	var presentation := _actor.get_node_or_null("Visual/CultivatorPresentation")
	_check(presentation != null, "移除前表现节点存在")
	presentation.queue_free()
	await _frames(4)
	_check(_actor.get_node_or_null("Visual/CultivatorPresentation") == null, "表现节点已从角色子树移除")

	_place(Vector3(-14.0, 0.05, 0.0))
	await _frames(4)
	_key(KEY_D, true)
	await _frames(12)
	_check(_motion.actual_velocity.length() >= _motion.move_speed - 0.05, "删除表现节点后移动仍达到步行速度")
	_key(KEY_D, false)
	await _frames(10)

	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(6)
	_key(KEY_SPACE, true)
	await _frames(1)
	_key(KEY_SPACE, false)
	var apex := _actor.global_position.y
	for index in range(40):
		await _frames(1)
		apex = maxf(apex, _actor.global_position.y)
	_check(apex > 0.6, "删除表现节点后跳跃仍有真实高度（%.2f）" % apex)
	await _frames(40)
	_check(_motion.on_floor, "删除表现节点后跳跃仍能落地")

	_toggle_flight()
	await _frames(6)
	_check(_motion.flight_active, "删除表现节点后御剑仍可开启")
	_key(KEY_SPACE, true)
	await _frames(14)
	_check(_motion.actual_velocity.y > 1.0, "删除表现节点后御剑仍能上升")
	_key(KEY_SPACE, false)
	_check(_stage.flight_visual() != null and _stage.flight_visual().visible, "删除表现节点后御剑视觉仍随状态显示")
	_toggle_flight()
	await _frames(6)
	_check(not _motion.flight_active, "删除表现节点后御剑仍可关闭")
	_check(_stage.flight_visual() != null and not _stage.flight_visual().visible, "关飞后剑随状态隐藏")

	# 工作台在缺表现节点时 HUD 不崩，如实标注缺失。
	var hud_pose := _stage.get_node_or_null("Overlay/Interface/Margin/Layout/Header/ReadoutPanel/Readout/Pose")
	_check(hud_pose != null and "缺失" in (hud_pose as Label).text,
		"表现节点缺失时 HUD 如实标注（%s）" % ("" if hud_pose == null else (hud_pose as Label).text))
	_check(_stage.presentation_state().is_empty(), "缺表现节点时 pose_state() 返回空快照")


# --- 批次：HUD 与小窗 -------------------------------------------------------


func _batch_hud() -> void:
	var input := _hud_label("Input")
	var velocity := _hud_label("Velocity")
	var state := _hud_label("State")
	var view := _hud_label("View")
	_check(input != null and "move=" in input.text, "HUD 显示输入意图（%s）" % ("" if input == null else input.text))
	_check(velocity != null and "v=" in velocity.text, "HUD 显示 actual_velocity（%s）" % ("" if velocity == null else velocity.text))
	_check(state != null and "着地=" in state.text and "御剑=" in state.text,
		"HUD 显示 on_floor 与 flight_active（%s）" % ("" if state == null else state.text))
	_check(view != null and "视角" in view.text, "HUD 显示当前观察视角（%s）" % ("" if view == null else view.text))

	# 返回按钮与底部提示的文案必须与真实返回目标一致（子实验目录，不是顶层实验目录）。
	var return_text := _control_text("Overlay/Interface/Margin/Layout/Header/Buttons/ReturnButton")
	_check(return_text == "返回子实验目录",
		"返回按钮文案为「返回子实验目录」（实际「%s」）" % return_text)
	_check(not return_text.contains("返回实验目录"),
		"返回按钮不写「返回实验目录」（会与实际目标不符）")
	var controls_text := _control_text("Overlay/Interface/Margin/Layout/Footer/ControlsPanel/Controls")
	_check(controls_text.contains("Esc 返回子实验目录"),
		"底部提示写明 Esc 返回子实验目录（实际「%s」）" % controls_text)

	# 小窗不溢出：工程用 canvas_items 拉伸，改窗口尺寸只会等比缩放画布、不会重排 Control，
	# 因此这里临时把内容画布改成 960×640 做真实重排，断言 HUD 仍落在画布内。
	_check(_hud_fits_canvas(), "1280x800 画布下 HUD 全部不溢出")
	var previous_canvas := root.content_scale_size
	root.content_scale_size = Vector2i(960, 640)
	await _frames(8)
	_check(_canvas_size() == Vector2(960, 640), "小窗画布已切到 960x640（实际 %s）" % str(_canvas_size()))
	_check(_hud_fits_canvas(), "960x640 画布下 HUD 全部不溢出")
	var footer := _stage.get_node("Overlay/Interface/Margin/Layout/Footer/ControlsPanel") as Control
	_check(_rect_fits(footer), "960x640 画布下底部说明不溢出（%s）" % _rect_text(footer))
	# 读数区不遮住舞台中心：HUD 面板宽度不超过画布七成，底部说明不高于画布三成。
	var readout_panel := _stage.get_node("Overlay/Interface/Margin/Layout/Header/ReadoutPanel") as Control
	_check(readout_panel.get_global_rect().size.x <= _canvas_size().x * 0.7,
		"小窗下读数面板不遮住舞台中心（宽 %.0f / 画布 %.0f）" % [readout_panel.get_global_rect().size.x, _canvas_size().x])
	root.content_scale_size = previous_canvas
	await _frames(6)
	_check(_canvas_size() == Vector2(previous_canvas), "画布尺寸已恢复为 %s" % str(previous_canvas))

	# 视角切换：只改相机，不改角色与能力状态。先把角色放回稳定着地状态，
	# 否则自由落体造成的位移会被误判成「切换视角移动了角色」。
	_place(Vector3(-6.0, 0.05, 0.0))
	await _frames(12)
	_check(_motion.on_floor, "视角切换检查前角色已稳定着地")
	var before_position := _actor.global_position
	var before_flight := _motion.flight_active
	_press(KEY_2)
	await _frames(6)
	_check(_stage.view_index() == 1, "数字键 2 切到侧面视角（实际 %d）" % _stage.view_index())
	_press(KEY_3)
	await _frames(6)
	_check(_stage.view_index() == 2, "数字键 3 切到斜侧视角（实际 %d）" % _stage.view_index())
	_press(KEY_1)
	await _frames(6)
	_check(_stage.view_index() == 0, "数字键 1 切回正面视角（实际 %d）" % _stage.view_index())
	_check(_actor.global_position.distance_to(before_position) < POS_TOL, "切换视角不移动角色")
	_check(_motion.flight_active == before_flight, "切换视角不改变御剑状态")


# --- 批次：退出 -------------------------------------------------------------


func _batch_exit() -> void:
	_key(KEY_R, true)
	await _frames(1)
	_key(KEY_R, false)
	await _frames(8)
	_check(_actor.global_position.distance_to(Vector3(-6.0, 0.05, 0.0)) < 0.3, "R 重置角色到出生点")
	_check(not _motion.flight_active, "R 重置关闭御剑并清账")
	_check(TagRegistry.is_blocked(_actor, &"sword_flight_block") == false, "R 重置后御剑阻塞已清账")

	# 退出批次同样读回返回文案：按钮与底部提示都必须指向子实验目录，与实际目标一致。
	var return_text := _control_text("Overlay/Interface/Margin/Layout/Header/Buttons/ReturnButton")
	_check(return_text == "返回子实验目录",
		"退出批次读回返回按钮文案（实际「%s」）" % return_text)
	var controls_text := _control_text("Overlay/Interface/Margin/Layout/Footer/ControlsPanel/Controls")
	_check(controls_text.contains("Esc 返回子实验目录"),
		"退出批次读回底部提示含「Esc 返回子实验目录」（实际「%s」）" % controls_text)
	# 文案要与真实目标相符：场景里不得再有旧文案，返回常量必须指向子实验目录。
	var stage_text := FileAccess.get_file_as_string(
		"res://levels/experiments/character_movement/motion_stage.gd")
	_check(not stage_text.contains('"返回实验目录"'),
		"场景源码不再残留旧按钮文案「返回实验目录」")
	_check(stage_text.contains('change_scene_to_file(MOVEMENT_HUB_SCENE)'),
		"返回常量与按钮文案指向同一目标（MOVEMENT_HUB_SCENE）")
	var return_button := _stage.get_node_or_null(
		"Overlay/Interface/Margin/Layout/Header/Buttons/ReturnButton") as Button
	_check(return_button != null and not return_button.pressed.get_connections().is_empty(),
		"返回按钮已接线到返回处理（点击不会静默失效）")

	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(10)
	_check(current_scene != null and current_scene.scene_file_path == MOVEMENT_HUB_SCENE,
		"Esc 返回移动子实验目录（期望 %s，实际 %s）" % [MOVEMENT_HUB_SCENE, "" if current_scene == null else current_scene.scene_file_path])
	# 返回目标必须固定：不得出现「存在才用 / 否则改道」的条件分支，也不得有第二个候选目录。
	# 注意两条探针都要够精确：
	# - 子串 "lab_hub.tscn" 会命中 "movement_lab_hub.tscn" 的尾部，必须比完整路径；
	# - ResourceLoader.exists 允许出现在启动断言里（缺失即报错），只禁止它出现在返回路径的条件分支中。
	var stage_source := _code_only(FileAccess.get_file_as_string(
		"res://levels/experiments/character_movement/motion_stage.gd"))
	_check(not stage_source.contains("res://levels/lab_hub.tscn"),
		"工作台代码不引用顶层实验目录作备用目标")
	var fallback := RegEx.new()
	fallback.compile("if\\s+ResourceLoader\\.exists|else\\s+\\w*HUB")
	_check(fallback.search(stage_source) == null, "工作台不对返回目标做运行时存在性回退")
	var return_body := _function_body(stage_source, "_return_to_hub")
	_check(return_body.contains("change_scene_to_file(MOVEMENT_HUB_SCENE)"),
		"返回路径直接使用固定的移动子实验目录常量")
	_check(not return_body.contains(" if ") and not return_body.contains(" else "),
		"返回路径不含条件改道分支（实际：%s）" % return_body.strip_edges().replace("\n", " ⏎ "))


# --- 截图路径 ---------------------------------------------------------------


func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "无头渲染器无法截图，请用窗口模式运行截图")
		_finish()
		return
	await _wait_render_frames(48)
	root.get_texture().get_image()
	await _frames(4)
	if _shots.is_empty() or _shots.has("idle"):
		await _capture("idle")
	if _shots.is_empty() or _shots.has("run"):
		# 侧面机位横贯跑道，最能读出步态与手臂反相。
		# 只经真实按键切换视角：截图路径与玩家走同一条输入链路，不直接调私有方法。
		await _switch_view(KEY_2, 1)
		_place(Vector3(12.0, 0.05, 0.0))
		await _frames(6)
		_key(KEY_D, true)
		await _frames(26)
		await _capture("run")
		_key(KEY_D, false)
		await _frames(12)
	if _shots.is_empty() or _shots.has("turn"):
		_place(Vector3(-11.5, 0.05, 5.0))
		_key(KEY_D, true)
		await _frames(16)
		_key(KEY_D, false)
		_key(KEY_A, true)
		await _frames(6)
		await _capture("turn")
		_key(KEY_A, false)
		await _frames(10)
	if _shots.is_empty() or _shots.has("jump"):
		# 斜侧机位同时带到跳跃标尺与角色顶点高度。
		await _switch_view(KEY_3, 2)
		_place(Vector3(9.0, 0.05, 0.0))
		await _frames(8)
		_key(KEY_SPACE, true)
		await _frames(1)
		_key(KEY_SPACE, false)
		await _frames(14)
		await _capture("jump")
		await _frames(40)
	if _shots.is_empty() or _shots.has("flight"):
		await _switch_view(KEY_3, 2)
		_place(Vector3(11.5, 0.05, 5.0))
		await _frames(6)
		_toggle_flight()
		await _frames(4)
		_key(KEY_SPACE, true)
		await _frames(40)
		_key(KEY_SPACE, false)
		await _frames(8)
		await _capture("flight")
		_key(KEY_D, false)
		await _frames(4)
	if _shots.is_empty() or _shots.has("landing"):
		_toggle_flight()
		for index in range(150):
			await _frames(1)
			if _motion.on_floor:
				break
		await _capture("landing")
		await _frames(10)
	if _shots.is_empty() or _shots.has("small"):
		# 改内容画布而不是 OS 窗口：窗口尺寸变化在 macOS 上会触发遮挡节流，导致截帧超时。
		var previous_canvas := root.content_scale_size
		root.content_scale_size = Vector2i(960, 640)
		await _frames(10)
		await _capture("small")
		root.content_scale_size = previous_canvas
		await _frames(6)
	_finish()


# --- 工具 -------------------------------------------------------------------


func _bind() -> void:
	_stage = current_scene as Node3D
	for child in current_scene.find_children("*", "CharacterBody3D", true, false):
		_actor = child as Swordsman
		break
	if _actor == null:
		return
	_motion = _actor.motion()
	_camera = root.get_camera_3d()


func _pose() -> Dictionary:
	return _stage.presentation_state()


func _place(position: Vector3) -> void:
	_actor.global_position = position
	_actor.reset_motion()
	_actor.set_aim_direction(Vector3.RIGHT)


func _toggle_flight() -> void:
	_actor.press_flight_toggle()
	await _frames(1)


## 用真实数字键切换固定观察视角，并通过公开只读接口回读确认生效。
## 不调用场景私有方法：截图路径必须与玩家输入走同一条链路，否则会掩盖键位绑定缺陷。
func _switch_view(code: Key, expected: int) -> void:
	_press(code)
	await _frames(6)
	_check(_stage.view_index() == expected,
		"按键切换视角到 %d（实际 %d）" % [expected, _stage.view_index()])


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _press(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	_key(code, false)


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame


func _hud_label(tag: String) -> Label:
	var panel := _stage.get_node_or_null("Overlay/Interface/Margin/Layout/Header/ReadoutPanel/Readout/%s" % tag)
	return panel as Label


## 读回任意 Button / Label 的文案；节点缺失或类型不符返回空串，由断言判失败。
func _control_text(path: String) -> String:
	var node := _stage.get_node_or_null(path)
	if node is Button:
		return (node as Button).text
	if node is Label:
		return (node as Label).text
	return ""


## HUD 当前排版所在的画布尺寸（canvas_items 拉伸下等于 content_scale_size）。
func _canvas_size() -> Vector2:
	return root.get_visible_rect().size


func _rect_fits(control: Control) -> bool:
	if control == null:
		return false
	var canvas := _canvas_size()
	var rect := control.get_global_rect()
	return rect.position.x >= -0.5 and rect.position.y >= -0.5 \
		and rect.end.x <= canvas.x + 0.5 and rect.end.y <= canvas.y + 0.5


## 整块 HUD（读数面板 / 按钮列 / 底部说明）都必须落在画布内。
func _hud_fits_canvas() -> bool:
	for path in [
		"Overlay/Interface/Margin/Layout/Header/ReadoutPanel",
		"Overlay/Interface/Margin/Layout/Header/Buttons",
		"Overlay/Interface/Margin/Layout/Footer/ControlsPanel",
		"Overlay/Interface/Margin/Layout/Footer",
	]:
		if not _rect_fits(_stage.get_node_or_null(path) as Control):
			return false
	return true


## 失败诊断用：读出控件矩形与文本，失败时能直接定位是尺寸还是内容问题。
func _rect_text(control: Control) -> String:
	if control == null:
		return "<null>"
	var rect := control.get_global_rect()
	var text := ""
	if control is Label:
		text = (control as Label).text
	elif control is PanelContainer and control.get_child_count() > 0 and control.get_child(0) is Label:
		text = (control.get_child(0) as Label).text
	return "rect=(%.0f,%.0f)-(%.0f,%.0f) 视口=%s 文本=%s" % [
		rect.position.x, rect.position.y, rect.end.x, rect.end.y, str(root.size), text,
	]


func _has(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _call_count(source: String, symbol: String) -> int:
	var count := 0
	var start := 0
	while true:
		var index := source.find(symbol, start)
		if index < 0:
			break
		count += 1
		start = index + symbol.length()
	return count


## 取出某个顶层函数的函数体（从 func 行到下一个顶层 func 之前），用于精确探针。
func _function_body(source: String, function_name: String) -> String:
	var marker := "func %s(" % function_name
	var start := source.find(marker)
	if start < 0:
		return ""
	var rest := source.substr(start + marker.length())
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


## 去掉行注释与字符串字面量：注释里的说明文字不构成调用或写入。
func _code_only(source: String) -> String:
	var lines := PackedStringArray()
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var comment := line.find("#")
		lines.append(line if comment < 0 else line.substr(0, comment))
	return "\n".join(lines)


func _capture(suffix: String) -> void:
	_frame_drawn = false
	RenderingServer.frame_post_draw.connect(_on_frame_drawn, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + CAPTURE_TIMEOUT_MSEC
	while not _frame_drawn and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _frame_drawn:
		_check(false, "等待渲染帧超时，未能截图：" + suffix)
		return
	var path := "%s-%s.png" % [_prefix, suffix]
	var error := root.get_texture().get_image().save_png(path)
	_check(error == OK, "渲染截图保存：%s（错误 %d）" % [path, error])


func _wait_render_frames(count: int) -> void:
	var drawn: Array[int] = [0]
	var on_draw := func() -> void: drawn[0] += 1
	RenderingServer.frame_post_draw.connect(on_draw)
	var start := Time.get_ticks_msec()
	var deadline := start + CAPTURE_TIMEOUT_MSEC
	while (drawn[0] < count or Time.get_ticks_msec() - start < 2000) and Time.get_ticks_msec() < deadline:
		await process_frame
	RenderingServer.frame_post_draw.disconnect(on_draw)
	_check(drawn[0] >= count, "字体预热完成，真实绘制帧 %d/%d" % [drawn[0], count])


func _on_frame_drawn() -> void:
	_frame_drawn = true


func _check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failed += 1


func _finish() -> void:
	print("MOTION_STAGE_PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)
