extends SceneTree

## 地形接触训练场验收：真实场景 + 真实角色 + 真实键盘事件 + 真实碰撞。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md 的验收标准。
##
## 用法（分批，单进程 <45s）：
##   Godot --headless --path src --script res://tests/ground_contact_course_playtest.gd -- --batch=assembly,flat,ramp,step,corner,narrow,edge,recovery,hud,exit
## 窗口截图：
##   Godot --path src --script res://tests/ground_contact_course_playtest.gd -- --capture-prefix=<abs>
##
## 断言纪律：允许把角色摆到装置起点（staging），但「走上去 / 走过去 / 掉下去」的过程
## 必须是真实按键 + 真实物理位移；禁止把角色直接放到终点冒充通过。失败即退出码 1。

const SCENE := "res://levels/experiments/character_movement/ground_contact_course.tscn"
const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SCENE_SCRIPT := "res://levels/experiments/character_movement/ground_contact_course.gd"
const LAYOUT_PATH := "res://levels/experiments/character_movement/ground_contact_course_layout.json"
const ACTOR_SOURCE := "res://game/actors/swordsman/swordsman.gd"
const HELPER_SOURCE := "res://levels/experiments/character_movement/movement_lab_input.gd"
const CAPABILITY_SCRIPTS := [
	"res://game/actors/swordsman/swordsman_movement.gd",
	"res://game/abilities/jump/jump.gd",
	"res://game/abilities/sword_flight/sword_flight.gd",
]
const EXPECTED_CAPABILITIES := ["SwordsmanMovement", "Jump", "SwordFlight"]
const CAPTURE_TIMEOUT_MSEC := 15000
const POS_TOL := 0.12
const SPEED_TOL := 0.12
## 实测地面倾角容差（度）：碰撞面法线与声明角度的差。
const ANGLE_TOL := 1.0

var _failed := 0
var _prefix := ""
var _only: PackedStringArray = []
var _stage: Node3D
var _actor: Swordsman
var _motion: SwordsmanMotionComponent
var _camera: Camera3D
var _layout: Dictionary = {}
var _frame_drawn := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
		elif argument.begins_with("--batch="):
			_only = argument.trim_prefix("--batch=").split(",", false)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var error := change_scene_to_file(SCENE)
	if error != OK:
		print("FAIL 无法加载训练场场景：%s（错误 %d）" % [SCENE, error])
		quit(1)
		return
	await scene_changed
	await _frames(6)
	_bind()
	if _actor == null:
		_check(false, "训练场缺少 Swordsman 角色根")
		_finish()
		return
	if not _prefix.is_empty():
		await _run_capture()
		return
	await _run_batches()
	_finish()


func _run_batches() -> void:
	for name in ["assembly", "flat", "ramp", "step", "corner", "narrow", "edge", "recovery", "hud", "exit"]:
		if not _has(name):
			continue
		print("--- batch %s ---" % name)
		await call("_batch_" + name)


# --- 批次：装配与契约 -------------------------------------------------------


func _batch_assembly() -> void:
	var manager := _actor.get_node("CapabilityManager")
	var names := PackedStringArray()
	for child in manager.get_children():
		var capability_script: Script = child.get_script() as Script
		names.append(str(capability_script.get_global_name()) if capability_script != null else str(child.name))
	_check(names.size() == 3, "训练场角色恰好装配 3 个能力（实际 %s）" % str(names))
	for expected in EXPECTED_CAPABILITIES:
		_check(names.has(expected), "能力装配包含 %s" % expected)

	var stage_source := _code_only(FileAccess.get_file_as_string(SCENE_SCRIPT))
	_check(_call_count(stage_source, "move_and_slide") == 0, "训练场脚本不调用 move_and_slide")
	for path in CAPABILITY_SCRIPTS:
		_check(_call_count(_code_only(FileAccess.get_file_as_string(path)), "move_and_slide") == 0,
			"能力不自行提交物理：%s" % path.get_file())
	_check(_call_count(_code_only(FileAccess.get_file_as_string(ACTOR_SOURCE)), "move_and_slide") == 1,
		"actor 根只有一处 move_and_slide（唯一物理提交点）")

	# 场景不写速度 / 意图 / 能力内部状态，也不碰能力五函数轴。
	for forbidden in [".velocity =", ".velocity.x =", ".velocity.z =", ".velocity.y =",
			"desired_horizontal =", "desired_vertical =", "vertical_impulse =",
			"flight_active =", "on_floor =", "camera_right =", "camera_forward ="]:
		_check(not stage_source.contains(forbidden), "训练场不写速度 / 意图 / 状态：%s" % forbidden)
	for axis in ["_should_activate", "_tick_active", "_on_activated", "_should_deactivate", "_on_deactivated"]:
		_check(not stage_source.contains(axis), "训练场不触碰能力五函数轴：%s" % axis)
	_check(not stage_source.contains("CapabilityManager"), "训练场不直接访问 CapabilityManager")
	for capability in EXPECTED_CAPABILITIES:
		var regex := RegEx.new()
		regex.compile("\\b%s\\b" % capability)
		_check(regex.search(stage_source) == null, "训练场不引用具体 Capability 类名：%s" % capability)

	# 场景不改 actor 的物理属性（斜坡/台阶行为必须来自引擎默认契约，而不是场景偷调参数）。
	for forbidden_property in ["floor_max_angle", "floor_snap_length", "floor_stop_on_slope",
			"floor_block_on_wall", "wall_min_slide_angle", "up_direction", "max_slides", "safe_margin"]:
		_check(not stage_source.contains(forbidden_property),
			"训练场不改 actor 物理属性：%s" % forbidden_property)

	# 使用 MovementLabInput 组合输入。
	_check(stage_source.contains("MovementLabInput"), "训练场使用 MovementLabInput 组合输入")
	var helper_source := FileAccess.get_file_as_string(HELPER_SOURCE)
	for forbidden in ["Swordsman", "Capability", "Component", "TagRegistry", "Camera3D", "move_and_slide"]:
		_check(not _code_only(helper_source).contains(forbidden),
			"input helper 不依赖角色 / 能力 / 相机：%s" % forbidden)
	for api in ["set_move_input(", "set_vertical_input(", "press_jump(", "set_camera_ground_basis(",
			"set_aim_direction(", "reset_motion(", "clear_input("]:
		_check(stage_source.contains(api), "训练场经公开输入 API 驱动角色：%s" % api)

	# 布局 → 碰撞：每个 device 都有碰撞体，数量一致，且命名可寻址。
	var devices: Array = _stage.devices()
	var colliders: Dictionary = _stage.device_colliders()
	_check(devices.size() == colliders.size(),
		"布局装置数与碰撞体数一致（%d / %d）" % [devices.size(), colliders.size()])
	_check(devices.size() >= 25, "训练场装置数量覆盖五类（%d）" % devices.size())
	var missing := PackedStringArray()
	for device in devices:
		if _stage.device_collider(str(device["id"])) == null:
			missing.append(str(device["id"]))
	_check(missing.is_empty(), "每个装置都有按 id 可寻址的碰撞体（缺：%s）" % str(missing))
	var zones := {}
	for device in devices:
		zones[str(device["zone"])] = true
	for expected_zone in ["平地", "坡道", "台阶", "墙角", "窄路", "边缘"]:
		_check(zones.has(expected_zone), "训练场覆盖分区：%s" % expected_zone)

	# 视觉与碰撞对齐：撞击盒顶面必须等于布局声明高度（可见几何由同一份 JSON 推导）。
	for id in ["step_025", "step_050", "step_075"]:
		var device := _device(id)
		var body: StaticBody3D = _stage.device_collider(id)
		var declared := float(device["rise"])
		var top: float = body.position.y + _box_size(body).y * 0.5
		_check(absf(top - declared) <= 0.005,
			"%s 碰撞顶面 %.4f 对齐声明抬升 %.4f" % [id, top, declared])
	for id in ["ramp_gentle", "ramp_critical", "ramp_steep"]:
		var device := _device(id)
		var body: StaticBody3D = _stage.device_collider(id)
		var shape: BoxShape3D = (body.get_child(0) as CollisionShape3D).shape as BoxShape3D
		var declared_angle := float(device["angle_deg"])
		_check(absf(rad_to_deg(body.rotation.z) - declared_angle) <= 0.05,
			"%s 碰撞体倾角 %.3f° 对齐声明 %.3f°" % [id, rad_to_deg(body.rotation.z), declared_angle])
		_check(absf(shape.size.z - float(device["width"])) <= 0.005,
			"%s 碰撞体宽度 %.3f 对齐声明 %.3f" % [id, shape.size.z, float(device["width"])])
	var terrace: StaticBody3D = _stage.device_collider("terrace")
	var terrace_device := _device("terrace")
	var terrace_top: float = terrace.position.y + _box_size(terrace).y * 0.5
	_check(absf(terrace_top - float(terrace_device["top_y"])) <= 0.005,
		"边缘台碰撞顶面 %.3f 对齐声明 %.3f" % [terrace_top, float(terrace_device["top_y"])])

	# 可见几何确实加载，且数量与 GLB 规模相符。
	var visual := _stage.get_node_or_null("World/CourseVisual")
	_check(visual != null, "训练场加载可见几何 CourseVisual")
	if visual != null:
		_check(visual.find_children("*", "MeshInstance3D", true, false).size() >= 60,
			"可见几何网格数充足（%d）" % visual.find_children("*", "MeshInstance3D", true, false).size())
		# 可视 vs 碰撞对齐：逐个装置比较「GLB 里同名网格的世界 AABB」与「碰撞盒的世界 AABB」。
		# 这是「看得见的装置就是走得上去的装置」的机械证据，不靠人工看图。
		await _check_visual_collision_alignment(visual)

	_check(_actor.is_on_floor(), "出生后角色站在地面上")
	_check(absf(_actor.global_position.y) < 0.4, "出生高度贴地（y=%.3f）" % _actor.global_position.y)


# --- 批次：平地基线 ---------------------------------------------------------


func _batch_flat() -> void:
	await _go_to("flat_pad", Vector3(-18.0, 0.05, 0.0))
	var device: Dictionary = _stage.current_device()
	_check(str(device.get("id", "")) == "flat_pad", "站上平地基线（实际 %s）" % str(device.get("id", "")))
	_check(_motion.on_floor, "平地着地")

	# 停下归零与无漂移。
	await _frames(20)
	_check(_motion.actual_velocity.length() < 0.05, "平地静止时速度为零（%.3f）" % _motion.actual_velocity.length())
	var resting := _actor.global_position
	await _frames(20)
	_check(_actor.global_position.distance_to(resting) < 0.02, "平地静止无漂移")

	# 真实输入跑动达到组件速度上限，并沿相机右方位移。
	var start := _actor.global_position
	_key(KEY_D, true)
	await _frames(14)
	_check(_motion.actual_velocity.length() >= _motion.move_speed - SPEED_TOL,
		"平地达到步行速度 %.2f（%.2f）" % [_motion.move_speed, _motion.actual_velocity.length()])
	_key(KEY_D, false)
	await _frames(4)
	var travelled := _actor.global_position - start
	_check(travelled.length() > 0.5, "平地产生真实位移（%.3f m）" % travelled.length())
	_check(travelled.normalized().dot(_motion.camera_right) > 0.9,
		"D 位移沿相机右方（dot=%.3f）" % travelled.normalized().dot(_motion.camera_right))
	_check(absf(_stage.stage_state()["floor_angle_deg"]) <= ANGLE_TOL,
		"平地实测地面倾角 ≈ 0°（%.2f°）" % float(_stage.stage_state()["floor_angle_deg"]))


# --- 批次：坡道 -------------------------------------------------------------


func _batch_ramp() -> void:
	# 每个坡：摆到坡脚，真实按键走上坡顶，再核对抬升与实测倾角。
	for id in ["ramp_gentle", "ramp_critical"]:
		var device := _device(id)
		var expected := float(device["angle_deg"])
		var base := Vector3(float(device["base"][0]), 0.0, float(device["base"][2]))
		var shape: Dictionary = _stage.ramp_shape(device)
		var top_y: float = shape["top_y"]
		var top_x: float = shape["top_x"]
		await _go_to(id, base - Vector3(1.6, 0.0, 0.0))
		var floor_before := _actor.global_position.y
		_key(KEY_D, true)
		# 斜面上水平推进被 cosθ 折减（42° 约 0.74×），给足帧数再判「是否真的上到坡顶」。
		var climbed := false
		var peak := floor_before
		var on_floor_throughout := true
		for index in range(110):
			await _frames(1)
			peak = maxf(peak, _actor.global_position.y)
			if not _motion.on_floor:
				on_floor_throughout = false
			# 成功判据 = 站上坡顶高度（顶面平台），而不是「x 走到某处」。
			if _actor.global_position.y >= top_y - 0.12 and _motion.on_floor:
				climbed = true
				break
		var angle := float(_stage.stage_state()["floor_angle_deg"])
		_key(KEY_D, false)
		await _frames(10)
		_check(peak - floor_before > 0.35, "%s 走上缓坡产生真实抬升（Δy=%.2f）" % [id, peak - floor_before])
		_check(climbed, "%s 真实按键走上坡顶（y=%.2f，坡顶 %.2f）" % [id, peak, top_y])
		_check(on_floor_throughout, "%s 上坡途中保持贴地" % id)
		_check(angle >= 0.0 and absf(angle - expected) <= ANGLE_TOL,
			"%s 实测地面倾角 %.2f° 对齐声明 %.2f°" % [id, angle, expected])
		_check(_actor.global_position.x >= top_x - 1.0,
			"%s 到达坡顶水平位置（x=%.2f，顶沿 %.2f）" % [id, _actor.global_position.x, top_x])

	# 陡坡：真实按键顶不上去，净上行位移接近 0 且被挡。
	var steep := _device("ramp_steep")
	await _go_to("ramp_steep", Vector3(float(steep["base"][0]) - 1.6, 0.05, float(steep["base"][2])))
	var steep_before := _actor.global_position.y
	_key(KEY_D, true)
	for index in range(60):
		await _frames(1)
	var steep_after := _actor.global_position.y
	var steep_blocked := _actor.global_position.x
	_key(KEY_D, false)
	await _frames(10)
	_check(steep_after - steep_before < 0.45,
		"陡坡 52° 顶不上去（Δy=%.2f，应远小于坡高）" % (steep_after - steep_before))
	_check(steep_blocked < float(steep["base"][0]) + float(steep["slope_length"]),
		"陡坡上被真实挡在半途（x=%.2f）" % steep_blocked)

	# 坡上停住：默认贴地不滑（floor_stop_on_slope 行为），且不抖动。
	var gentle := _device("ramp_gentle")
	await _go_to("ramp_gentle", Vector3(float(gentle["base"][0]) + 1.2, 0.05, float(gentle["base"][2])))
	_key(KEY_D, true)
	await _frames(10)
	_key(KEY_D, false)
	await _frames(22)
	var slope_rest := _actor.global_position
	await _frames(20)
	_check(_actor.global_position.distance_to(slope_rest) < 0.12,
		"缓坡上松键后停住不滑（Δ=%.3f m）" % _actor.global_position.distance_to(slope_rest))
	_check(_motion.on_floor, "缓坡上停住时仍贴地")


# --- 批次：台阶 -------------------------------------------------------------


## 台阶行为（实测结论，非预期假设）：
## 角色是胶囊体、没有台阶辅助（本项目未实现 step-up，也不允许本场景加），
## 因此 0.25 / 0.50 / 0.75 m 三级**都不能靠走上去**——碰撞面是竖直面，
## 法线水平，move_and_slide 只会沿面滑动，不会抬升。三级都需要起跳。
## 这里如实断言这个结果，并把「走→被挡」与「跳→站上去」分成两组。
func _batch_step() -> void:
	const STEP_IDS := ["step_025", "step_050", "step_075"]

	# 第一组：真实走上去 —— 全部被挡（不抬升、停在踏面前）。
	for id in STEP_IDS:
		var device := _device(id)
		var rise := float(device["rise"])
		var center := Vector3(float(device["center"][0]), 0.0, float(device["center"][2]))
		var size := Vector3(float(device["size"][0]), 0.0, float(device["size"][2]))
		var face_x: float = center.x - size.x * 0.5
		await _go_to(id, Vector3(face_x - 3.0, 0.05, center.z))
		var before := _actor.global_position.y
		_key(KEY_D, true)
		for index in range(45):
			await _frames(1)
		var after := _actor.global_position.y
		var stopped_x := _actor.global_position.x
		_key(KEY_D, false)
		await _frames(10)
		_check(after - before < 0.12,
			"%s（抬升 %.2f m）步行被挡不抬升（Δy=%.2f）" % [id, rise, after - before])
		# 停在踏面前：中心到踏面的距离 ≈ 胶囊半径（0.35），不穿透。
		_check(absf(stopped_x - (face_x - 0.35)) < 0.15,
			"%s 停在踏面前、不穿透（x=%.2f，期望 %.2f）" % [id, stopped_x, face_x - 0.35])
		_check(_motion.on_floor, "%s 被挡时仍着地" % id)

	# 第二组：真实起跳 —— 三级都能上，落地后站在台面上，且高度等于声明抬升。
	for id in STEP_IDS:
		var device := _device(id)
		var rise := float(device["rise"])
		var center := Vector3(float(device["center"][0]), 0.0, float(device["center"][2]))
		var size := Vector3(float(device["size"][0]), 0.0, float(device["size"][2]))
		var face_x: float = center.x - size.x * 0.5
		# 贴着踏面起跳：竖直方向够了再水平推进，落点落在台面内。
		await _go_to(id, Vector3(face_x - 0.6, 0.05, center.z))
		var jump_before := _actor.global_position.y
		_key(KEY_D, true)
		await _frames(4)
		_key(KEY_SPACE, true)
		await _frames(1)
		_key(KEY_SPACE, false)
		var peak := jump_before
		var landed := false
		var landed_y := jump_before
		for index in range(80):
			await _frames(1)
			peak = maxf(peak, _actor.global_position.y)
			if _motion.on_floor and _actor.global_position.y > jump_before + rise - 0.06 \
					and _actor.global_position.x > face_x + 0.3:
				landed = true
				landed_y = _actor.global_position.y
				break
		_key(KEY_D, false)
		await _frames(12)
		_check(peak > jump_before + rise, "%s 起跳高度越过台阶（峰值 Δy=%.2f > %.2f）" % [id, peak - jump_before, rise])
		_check(landed, "%s 起跳后站上台面（y=%.2f，期望 ≈%.2f）" % [id, landed_y, rise])
		_check(absf(landed_y - rise) < 0.08, "%s 台面高度等于声明抬升（%.3f / %.3f）" % [id, landed_y, rise])
		_check(_motion.on_floor, "%s 跳上台面后着地" % id)

	# 台面承重：站上后停下不下沉。
	await _frames(20)
	var resting := _actor.global_position
	await _frames(20)
	_check(_actor.global_position.distance_to(resting) < 0.05, "站上台面后停稳不下沉")


# --- 批次：墙角 -------------------------------------------------------------


## 墙角行为：内角是两面墙的凹角（x=6.2 的竖墙 + z=-8.2 的横墙），
## 角色顶住后必须停稳且不穿透；外墙角是凸角，贴墙推进应能滑过而不是卡死。
## 断言按「到墙面的距离 ≈ 胶囊半径」判穿透，而不是只判「撞到了什么东西」。
func _batch_corner() -> void:
	var inner_x: StaticBody3D = _stage.device_collider("corner_inner_x")
	var inner_z: StaticBody3D = _stage.device_collider("corner_inner_z")
	var capsule_radius := 0.35
	var inner_device := _device("corner_inner_x")
	var inner_size := Vector3(float(inner_device["size"][0]), 0.0, float(inner_device["size"][2]))
	var face_x: float = inner_x.position.x - inner_size.x * 0.5

	# 正面顶住内角竖墙：必须停在墙面外一个半径处，停稳不抖。
	await _go_to("corner_inner_x", Vector3(face_x - 3.0, 0.05, inner_x.position.z + 1.0))
	_key(KEY_D, true)
	# 接触对象必须在**持续推进中**采样：一旦松键，角色不再挤墙，
	# 本帧 move_and_slide 只会报地面——这是读法差异，不是行为差异。
	var contact_seen := PackedStringArray()
	for index in range(45):
		await _frames(1)
		for name in _stage.stage_state()["contacts"] as PackedStringArray:
			if not contact_seen.has(name):
				contact_seen.append(name)
	var stopped := _actor.global_position
	var wall_flag := bool(_stage.stage_state()["is_on_wall"])
	await _frames(20)
	var drift := _actor.global_position.distance_to(stopped)
	_key(KEY_D, false)
	await _frames(8)
	_check(absf(stopped.x - (face_x - capsule_radius)) < 0.15,
		"内角墙挡住真实角色形状（x=%.2f，墙面 %.2f，半径 %.2f）" % [stopped.x, face_x, capsule_radius])
	_check(drift < 0.05, "顶住内角墙后停稳不抖（Δ=%.3f）" % drift)
	_check(_motion.on_floor, "顶墙时仍着地")
	_check(wall_flag, "顶墙时 is_on_wall 为真")
	_check(contact_seen.has("corner_inner_x"),
		"推进过程中接触对象含被顶住的墙本体（采样到 %s）" % str(contact_seen))

	# 两面墙的凹角：同时被两面墙限制，两个方向的推进都被挡住。
	var corner_point := Vector3(face_x - capsule_radius - 0.02, 0.05,
		inner_z.position.z + float(inner_device["size"][2]) * 0.5 + capsule_radius + 0.02)
	await _go_to("corner_inner_x", corner_point)
	_key(KEY_D, true)
	_key(KEY_S, true)
	for index in range(45):
		await _frames(1)
	var corner_rest := _actor.global_position
	_key(KEY_D, false)
	_key(KEY_S, false)
	var corner_drift := 0.0
	for index in range(20):
		await _frames(1)
		corner_drift = maxf(corner_drift, _actor.global_position.distance_to(corner_rest))
	_check(corner_rest.x < inner_x.position.x - capsule_radius + 0.15,
		"凹角处 x 方向被墙挡住（x=%.2f）" % corner_rest.x)
	_check(corner_drift < 0.08, "凹角处停稳不穿透（最大漂移 %.3f）" % corner_drift)

	# 斜向顶墙：真实按键下应沿墙滑（切向位移显著、法向被挡住），而不是卡死。
	await _go_to("corner_inner_x", Vector3(face_x - 2.0, 0.05, inner_x.position.z - 2.4))
	var slide_start := _actor.global_position
	_key(KEY_D, true)
	_key(KEY_W, true)
	for index in range(45):
		await _frames(1)
	var slide_end := _actor.global_position
	_key(KEY_D, false)
	_key(KEY_W, false)
	await _frames(8)
	var slide_along := absf(slide_end.z - slide_start.z)
	var slide_into := slide_end.x - slide_start.x
	# 起点离墙 2 m，因此「法向被挡住」的判据是「最终没有越过墙面」，
	# 而不是「法向位移很小」——斜向推进本来就该先走完那段自由行程再贴墙。
	_check(slide_along > 0.5, "斜向顶墙沿墙滑出真实位移（Δz=%.2f）" % slide_along)
	_check(slide_into > 0.5, "斜向推进先走完自由行程（Δx=%.2f）" % slide_into)
	_check(slide_end.x < face_x, "斜向顶墙未穿透墙面（x=%.2f < 墙面 %.2f）" % [slide_end.x, face_x])
	_check(absf(slide_end.x - (face_x - capsule_radius)) < 0.3,
		"斜滑后仍贴在墙面外一个半径处（x=%.2f）" % slide_end.x)

	# 外墙角：凸角不卡死。贴墙推进时切向分量把它带过角点。
	var outer: StaticBody3D = _stage.device_collider("wall_outer")
	var outer_device := _device("wall_outer")
	var outer_size := Vector3(float(outer_device["size"][0]), 0.0, float(outer_device["size"][2]))
	var outer_face_x: float = outer.position.x - outer_size.x * 0.5
	var outer_north_z: float = outer.position.z - outer_size.z * 0.5
	await _go_to("wall_outer", Vector3(outer_face_x - 1.6, 0.05, outer_north_z - 0.4))
	_key(KEY_D, true)
	var passed := false
	for index in range(70):
		await _frames(1)
		if _actor.global_position.x > outer.position.x + 0.9:
			passed = true
			break
	_key(KEY_D, false)
	await _frames(8)
	_check(passed, "外墙角可绕行通过（x=%.2f，墙角 x=%.2f）" % [_actor.global_position.x, outer.position.x])
	_check(_motion.on_floor, "绕行外墙角时始终着地")


# --- 批次：窄路 -------------------------------------------------------------


func _batch_narrow() -> void:
	# 1.2 / 0.9 m 通道：从西侧真实走过整条通道。
	for id in ["narrow_12_s", "narrow_09_s"]:
		var wall: StaticBody3D = _stage.device_collider(id)
		var device := _device(id)
		var lane_z := float(device["lane_z"])
		await _go_to(id, Vector3(7.0, 0.05, lane_z))
		var start := _actor.global_position
		_key(KEY_D, true)
		for index in range(70):
			await _frames(1)
		var end := _actor.global_position
		_key(KEY_D, false)
		await _frames(8)
		_check(end.x - start.x > 3.5,
			"%s（净宽 %.2f m）真实走过通道（Δx=%.2f）" % [id, float(device["gap_m"]), end.x - start.x])
		_check(absf(end.z - lane_z) < 0.5, "%s 通过时未偏出通道（Δz=%.2f）" % [id, end.z - lane_z])
		_check(_motion.on_floor, "%s 通过时始终着地" % id)
		_check(wall != null, "%s 碰撞体存在" % id)

	# 0.6 m 通道（窄于角色直径 0.70 m）：真实按键无法穿过。
	var tight := _device("narrow_06_s")
	var tight_z := float(tight["lane_z"])
	await _go_to("narrow_06_s", Vector3(7.0, 0.05, tight_z))
	var tight_start := _actor.global_position
	_key(KEY_D, true)
	for index in range(70):
		await _frames(1)
	var tight_end := _actor.global_position
	_key(KEY_D, false)
	await _frames(8)
	_check(tight_end.x - tight_start.x < 1.6,
		"0.6 m 通道窄于角色直径，真实按键无法穿过（Δx=%.2f）" % (tight_end.x - tight_start.x))
	_check(_motion.on_floor, "被窄路挡住时仍着地")


# --- 批次：边缘与回收 -------------------------------------------------------


func _batch_edge() -> void:
	# 登上边缘台（走登台坡），再从东侧无栏处真实走出并落到下层。
	var terrace: StaticBody3D = _stage.device_collider("terrace")
	await _go_to("terrace_ramp", Vector3(12.2, 0.05, -3.0))
	_key(KEY_D, true)
	var on_terrace := false
	for index in range(70):
		await _frames(1)
		if _actor.global_position.y > 0.75 and _actor.global_position.x > 15.6:
			on_terrace = true
			break
	_key(KEY_D, false)
	await _frames(10)
	_check(on_terrace, "经登台坡走上边缘台（y=%.2f）" % _actor.global_position.y)
	var device: Dictionary = _stage.current_device()
	_check(str(device.get("id", "")) == "terrace", "站上边缘台（实际 %s）" % str(device.get("id", "")))

	var edge_x: float = terrace.position.x + _box_size(terrace).x * 0.5
	_key(KEY_D, true)
	var left_floor := false
	var landed := false
	var landed_y := 1.0
	for index in range(110):
		await _frames(1)
		if not _motion.on_floor:
			left_floor = true
		# 判据是「离地后重新着地」，不假设必须在某个固定帧内掉到 y<0.2：
		# 台面 0.90 m、重力 18 m/s²，自由落体本就很短，但帧数取决于推进节奏。
		if left_floor and _motion.on_floor:
			landed = true
			landed_y = _actor.global_position.y
			break
	_key(KEY_D, false)
	await _frames(20)
	_check(left_floor, "走出无栏边缘后离地")
	_check(landed, "离地后落回下层并重新着地")
	_check(landed_y < 0.3, "落回下层地面而非台阶（y=%.3f）" % landed_y)
	_check(_motion.on_floor, "落地后重新着地")
	_check(_actor.global_position.x > edge_x, "确实走出台缘（x=%.2f > %.2f）" % [_actor.global_position.x, edge_x])

	# 边缘停住：在台面上靠近边缘处停下不应掉落。
	await _go_to("terrace", Vector3(edge_x - 1.4, 1.0, -3.0))
	await _frames(20)
	_check(_motion.on_floor, "边缘附近着地")
	var ledge_rest := _actor.global_position
	await _frames(30)
	_check(_actor.global_position.distance_to(ledge_rest) < 0.05,
		"边缘附近停住不下落（Δ=%.3f）" % _actor.global_position.distance_to(ledge_rest))
	_check(_actor.global_position.y > 0.7, "停住时仍在台面上（y=%.2f）" % _actor.global_position.y)


func _batch_recovery() -> void:
	# 掉落回收：走入场东侧的 void 缺口，掉出 fall_out_y 后回到 spawn 并计数。
	var void_gap: Dictionary = _layout["void_gap"]
	var gap_center := Vector3(float(void_gap["center"][0]), 0.0, float(void_gap["center"][1]))
	var before := int(_stage.stage_state()["recoveries"])
	await _go_to("void", Vector3(22.0, 0.05, 0.5))
	_check(_motion.on_floor, "回收区起点着地")
	_key(KEY_D, true)
	var recovered := false
	for index in range(120):
		await _frames(1)
		if int(_stage.stage_state()["recoveries"]) > before:
			recovered = true
			break
	_key(KEY_D, false)
	await _frames(10)
	_check(recovered, "走入落下回收区触发回收（计数 %d → %d）" % [before, int(_stage.stage_state()["recoveries"])])
	_check(_actor.global_position.distance_to(Vector3(-18.0, 0.05, 0.0)) < 1.0,
		"回收回到出生点（x=%.2f, z=%.2f）" % [_actor.global_position.x, _actor.global_position.z])
	_check(not _motion.flight_active, "回收后未处于御剑状态")
	_check(not TagRegistry.is_blocked(_actor, &"sword_flight_block"), "回收后无御剑阻塞残留")
	_check(absf(_actor.global_position.y) < 0.4, "回收后落在地面上（y=%.2f）" % _actor.global_position.y)
	_check(void_gap.has("note"), "布局登记了落下回收区说明")


# --- 批次：HUD 与契约 -------------------------------------------------------


func _batch_hud() -> void:
	var zone := _hud_label("Zone")
	var declared := _hud_label("Declared")
	var motion := _hud_label("Motion")
	var contact := _hud_label("Contact")
	var recovery := _hud_label("Recovery")
	_check(zone != null and "区域" in zone.text, "HUD 显示当前区域与装置（%s）" % ("" if zone == null else zone.text))
	_check(declared != null and "装置声明" in declared.text,
		"HUD 显示装置声明尺寸（%s）" % ("" if declared == null else declared.text))
	_check(motion != null and "实测" in motion.text and "地面倾角" in motion.text,
		"HUD 显示实测速度与地面倾角（%s）" % ("" if motion == null else motion.text))
	_check(contact != null and "接触" in contact.text, "HUD 显示接触对象（%s）" % ("" if contact == null else contact.text))
	_check(recovery != null and "回收" in recovery.text, "HUD 显示回收计数（%s）" % ("" if recovery == null else recovery.text))

	# 区域读数随位置真实变化（站上台阶 vs 平地）。
	await _go_to("step_050", Vector3(-0.6, 0.05, 0.0))
	var flat_zone := _hud_label("Zone").text
	await _go_to("step_050", Vector3(1.5, 0.6, 0.0))
	await _frames(10)
	var step_zone := _hud_label("Zone").text
	_check(flat_zone != step_zone, "HUD 区域随所在装置变化（%s → %s）" % [flat_zone, step_zone])
	_check("台阶" in step_zone, "站上台面时区域读数含装置名（%s）" % step_zone)

	# 小窗：改内容画布触发真实重排，HUD 不溢出。
	_check(_hud_fits_canvas(), "1280x800 画布下 HUD 不溢出")
	var previous := root.content_scale_size
	root.content_scale_size = Vector2i(960, 640)
	await _frames(8)
	_check(_hud_fits_canvas(), "960x640 画布下 HUD 不溢出")
	root.content_scale_size = previous
	await _frames(6)
	_check(_hud_fits_canvas(), "画布恢复后 HUD 仍不溢出")

	# 返回文案与实际目标一致。
	var return_text := _control_text("Overlay/Interface/Margin/Layout/Header/Buttons/ReturnButton")
	_check(return_text == "返回子实验目录", "返回按钮文案为「返回子实验目录」（实际「%s」）" % return_text)
	var controls := _control_text("Overlay/Interface/Margin/Layout/Footer/ControlsPanel/Controls")
	_check(controls.contains("Esc 返回子实验目录"), "底部提示写明 Esc 返回子实验目录（实际「%s」）" % controls)
	var stage_text := FileAccess.get_file_as_string(SCENE_SCRIPT)
	_check(not stage_text.contains('"返回实验目录"'), "场景源码无旧返回文案")


# --- 批次：退出 -------------------------------------------------------------


func _batch_exit() -> void:
	# 御剑状态也要能被 R 清账（地面场景仍装配三能力，重置必须关飞）。
	_actor.press_flight_toggle()
	await _frames(6)
	_check(_motion.flight_active, "F 可开启御剑（训练场仍装配三能力）")
	_place(Vector3(-18.0, 0.05, 0.0))
	_key(KEY_R, true)
	await _frames(1)
	_key(KEY_R, false)
	await _frames(10)
	_check(not _motion.flight_active, "R 重置关闭御剑")
	_check(not TagRegistry.is_blocked(_actor, &"sword_flight_block"), "R 重置后御剑阻塞清账")
	_check(_actor.global_position.distance_to(Vector3(-18.0, 0.05, 0.0)) < 0.6, "R 重置回到出生点")
	_check(_stage.input_state().held_count() == 0, "R 重置清空输入按住状态")

	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(10)
	_check(current_scene != null and current_scene.scene_file_path == HUB_SCENE,
		"Esc 返回子实验目录（实际 %s）" % ("" if current_scene == null else current_scene.scene_file_path))


# --- 截图 -------------------------------------------------------------------


func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "无头渲染器无法截图，请用窗口模式运行截图")
		_finish()
		return
	await _wait_render_frames(48)
	root.get_texture().get_image()
	await _frames(4)

	# 全景：拉远看整个训练场分区。只为构图，不声称任何物理结论。
	_place(Vector3(5.0, 0.05, 0.0))
	_camera.size = 50.0
	await _frames(24)
	await _capture("overview")

	# 坡道：真实按键走上 42° 临界坡。
	_camera.size = 17.0
	var critical := _device("ramp_critical")
	await _go_to("ramp_critical", Vector3(float(critical["base"][0]) - 1.4, 0.05, float(critical["base"][2])))
	_key(KEY_D, true)
	await _frames(34)
	await _capture("ramp")
	_key(KEY_D, false)
	await _frames(10)

	# 台阶：站上 0.50 m 台面。
	await _go_to("step_050", Vector3(-0.4, 0.05, 0.0))
	_key(KEY_D, true)
	await _frames(30)
	await _capture("step")
	_key(KEY_D, false)
	await _frames(10)

	# 墙角 / 窄路：真实按键顶住内角墙。
	var inner: StaticBody3D = _stage.device_collider("corner_inner_x")
	await _go_to("corner_inner_x", Vector3(inner.position.x - 3.0, 0.05, inner.position.z))
	_key(KEY_D, true)
	await _frames(40)
	await _capture("corner")
	_key(KEY_D, false)
	await _frames(10)

	# 边缘 / 回收：站上边缘台临边处。
	await _go_to("terrace", Vector3(18.6, 1.0, -3.0))
	await _frames(24)
	await _capture("edge")

	# 落下回收区。
	_camera.size = 26.0
	await _go_to("void", Vector3(24.6, 0.05, 0.4))
	_key(KEY_D, true)
	await _frames(24)
	await _capture("recovery")
	_key(KEY_D, false)

	# 小窗。
	var previous := root.content_scale_size
	root.content_scale_size = Vector2i(960, 640)
	await _frames(10)
	await _capture("small")
	root.content_scale_size = previous
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
	_layout = _stage.layout()


## 取碰撞体的 BoxShape3D 尺寸：Shape3D 基类没有 size，必须显式下转，否则推断失败。
## 装置可视几何与碰撞盒的对齐：两侧 AABB 逐项比较。
##
## 允许的差异只来自「碰撞盒按设计比可见几何略窄/略厚」（例如台阶碰撞不含装饰底座、
## 斜坡碰撞不含木栏），因此这里比对的是**关键尺寸**：顶面高度、占地范围与倾角，
## 而不是要求两个 AABB 完全相等——完全相等会把装饰也算成物理误差。
func _check_visual_collision_alignment(visual: Node3D) -> void:
	var checked := 0
	var mismatched := PackedStringArray()
	for device in _stage.devices():
		var id := str(device["id"])
		var body: StaticBody3D = _stage.device_collider(id)
		if body == null:
			continue
		var mesh := visual.find_child(id, true, false)
		if mesh == null:
			mismatched.append("%s(无可见几何)" % id)
			continue
		var visual_aabb := (mesh as Node3D).global_transform * _node_aabb(mesh as Node3D)
		var collision_aabb := _body_aabb(body)
		var visual_top := visual_aabb.position.y + visual_aabb.size.y
		var collision_top := collision_aabb.position.y + collision_aabb.size.y
		var kind := str(device["kind"])
		var ok := true
		if kind == "step" or kind == "terrace" or kind == "pad":
			# 承重装置：碰撞顶面必须与可见顶面一致（容差 0.12 m，含压顶/装饰边）。
			ok = absf(visual_top - collision_top) <= 0.12
			if not ok:
				mismatched.append("%s(顶面 可视%.2f / 碰撞%.2f)" % [id, visual_top, collision_top])
		elif kind == "ramp":
			# 斜面：可见几何的顶面高度与坡顶应吻合（碰撞盒顶面就是坡面）。
			ok = absf(visual_top - collision_top) <= 0.25
			if not ok:
				mismatched.append("%s(坡顶 可视%.2f / 碰撞%.2f)" % [id, visual_top, collision_top])
		else:
			# 墙：占地中心与高度量级一致即可（可见几何含压顶外挑）。
			ok = absf(visual_aabb.position.x + visual_aabb.size.x * 0.5
				- (collision_aabb.position.x + collision_aabb.size.x * 0.5)) <= 0.3 \
				and absf(visual_top - collision_top) <= 0.3
			if not ok:
				mismatched.append("%s(中心/高度偏差)" % id)
		checked += 1
	_check(mismatched.is_empty(), "可视几何与碰撞盒逐装置对齐（检查 %d 项，偏差 %s）" % [checked, str(mismatched)])


func _body_aabb(body: StaticBody3D) -> AABB:
	var local := AABB()
	var first := true
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue
		var box := shape_node.shape as BoxShape3D
		if box == null:
			continue
		var half := box.size * 0.5
		var box_aabb := AABB(shape_node.position - half, box.size)
		local = box_aabb if first else local.merge(box_aabb)
		first = false
	return body.global_transform * local


func _node_aabb(node: Node3D) -> AABB:
	var instance := node as MeshInstance3D
	if instance == null or instance.mesh == null:
		return AABB()
	return instance.mesh.get_aabb()


func _box_size(body: StaticBody3D) -> Vector3:
	var shape_node := body.get_child(0) as CollisionShape3D
	var box := shape_node.shape as BoxShape3D
	return box.size


func _device(id: String) -> Dictionary:
	for device in _stage.devices():
		if str(device["id"]) == id:
			return device
	return {}


## staging：把角色放到批次起点并清输入；随后必须由真实按键产生位移。
func _go_to(id: String, position: Vector3) -> void:
	_place(position)
	await _frames(8)
	await _frames(2)


func _place(position: Vector3) -> void:
	_actor.global_position = position
	_actor.reset_motion()
	_actor.set_aim_direction(Vector3.RIGHT)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame


func _hud_label(tag: String) -> Label:
	var panel := _stage.get_node_or_null("Overlay/Interface/Margin/Layout/Header/ReadoutPanel/Readout/%s" % tag)
	return panel as Label


func _control_text(path: String) -> String:
	var node := _stage.get_node_or_null(path)
	if node is Button:
		return (node as Button).text
	if node is Label:
		return (node as Label).text
	return ""


func _canvas_size() -> Vector2:
	return root.get_visible_rect().size


func _rect_fits(control: Control) -> bool:
	if control == null:
		return false
	var canvas := _canvas_size()
	var rect := control.get_global_rect()
	return rect.position.x >= -0.5 and rect.position.y >= -0.5 \
		and rect.end.x <= canvas.x + 0.5 and rect.end.y <= canvas.y + 0.5


func _hud_fits_canvas() -> bool:
	for path in [
		"Overlay/Interface/Margin/Layout/Header/ReadoutPanel",
		"Overlay/Interface/Margin/Layout/Header/Buttons",
		"Overlay/Interface/Margin/Layout/Footer/ControlsPanel",
	]:
		if not _rect_fits(_stage.get_node_or_null(path) as Control):
			return false
	return true


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
	print("GROUND_CONTACT_PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)
