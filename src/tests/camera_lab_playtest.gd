extends SceneTree

## 镜头实验室的无头 / 窗口验收（依据 notes/proposed/gameplay/2026-09-18-character-movement-subexperiments.md）。
##
## 覆盖：
## - 场景装配与灰盒齐备、默认策略、角色三能力原样；
## - 四种跟随策略（硬跟随 / 平滑 / 死区 / 死区+前视）真实按键切换 + 运行时读回；
## - 镜头旋转后屏幕相对移动仍按相机地面基解释（与真实 Camera3D basis 对照）；
## - 手动缩放（滚轮 / Z / X）与限幅；
## - 切换策略不改变三 Capability 装配、阻塞清账与角色物理参数；
## - 静态边界：本实验脚本不写 velocity / 意图 / 能力内部状态，不引用具体能力类名；
## - Esc 返回角色移动子实验目录。
##
## 未覆盖（交使用者）：跟随舒适度、缩放手感与遮挡观感等主观判断。

const SCENE := "res://levels/experiments/character_movement/camera_lab.tscn"
const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const HUB_ROOT := "MovementLabHub"
const RIG_PATH := "res://levels/experiments/character_movement/camera_lab_rig.gd"
const SCENE_SCRIPT_PATH := "res://levels/experiments/character_movement/camera_lab.gd"
const GRAYBOX_SCRIPT_PATH := "res://levels/experiments/character_movement/camera_lab_graybox.gd"

const EXPECTED_CAPABILITIES := ["Jump", "SwordFlight", "SwordsmanMovement"]

## 静态边界规则（正则只匹配"写"，不匹配只读访问与函数名，避免误报）：
## - 写角色物理 / 意图 / 能力内部状态；
## - 直接引用具体 Capability 类名。
const FORBIDDEN_WRITES := [
	"\\.velocity\\s*=",
	"\\.move_input\\s*=",
	"\\.desired_horizontal\\s*=",
	"\\.desired_vertical\\s*=",
	"\\.vertical_impulse\\s*=",
	"\\.flight_active\\s*=",
	"\\.on_floor\\s*=",
	"\\bmove_and_slide\\s*\\(",
	"\\badd_block\\s*\\(",
	"\\bremove_block\\s*\\(",
]
const FORBIDDEN_CLASS_REFS := [
	"\\bSwordsmanMovement\\b",
	"\\bSwordFlight\\b",
	"\\bJump\\b",
]
const FLIGHT_TAG := &"sword_flight_block"
const CAPTURE_TIMEOUT_MSEC := 4000

## 静止等待帧数：让平滑/前视收敛，便于比较"停止后"的焦点偏移。
const SETTLE_FRAMES := 70

## 遮挡对照位：站在 4 m 遮挡板背面（高角度相机的视线正好穿过板体）。
## 开阔对照位：出生空地，同一策略与偏航下视线无遮挡。
const OCCLUDED_POSITION := Vector3(6.0, 0.1, -2.6)
const UNOCCLUDED_POSITION := Vector3(0.0, 0.1, -10.0)

var _failed := 0
var _prefix := ""
var _actor: CharacterBody3D
var _motion: SwordsmanMotionComponent
var _camera: Camera3D
var _rig: CameraLabRig
var _lab: Node3D
var _frame_drawn := false
var _msaa_before: Viewport.MSAA = Viewport.MSAA_DISABLED
var _deadzone_camera_lag := 0.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	_msaa_before = root.msaa_3d
	if change_scene_to_file(SCENE) != OK:
		print("FAIL 无法加载镜头实验室场景：%s" % SCENE)
		quit(1)
		return
	await scene_changed
	await _frames(5)
	_bind()
	_check_assembly()
	_check_static_boundaries()

	if not _prefix.is_empty():
		await _run_capture()
		return

	await _run_mode_comparison()
	await _run_screen_relative()
	await _run_zoom()
	await _run_switch_purity()
	await _run_reset_and_exit()
	_finish()


# --- 装配与静态边界 ------------------------------------------------------


func _check_assembly() -> void:
	_check(_actor != null and _motion != null and _camera != null, "镜头实验室装配完成（角色 / 组件 / 相机）")
	_check(_rig != null, "场景装配 CameraLabRig 跟随台架")
	_check(_rig.mode() == CameraLabRig.Mode.HARD, "默认策略为固定偏移硬跟随")
	_check(_camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "相机为正交投影（尺度可读）")
	var required := ["Ground", "Ruler", "WallWithDoor", "Occluders", "Pillars", "Slope", "HighPlatform"]
	var missing := PackedStringArray()
	for path in required:
		if current_scene.get_node_or_null(path) == null:
			missing.append(path)
	_check(missing.is_empty(), "灰盒齐备：网格 / 标尺 / 墙与门洞 / 遮挡 / 高低柱 / 坡 / 高台%s" % [
		"" if missing.is_empty() else "（缺 %s）" % ", ".join(missing)])
	# 门洞必须真的可通行：两侧墙段之间留空，上方有过梁。
	_check(current_scene.get_node_or_null("WallWithDoor/DoorLintel") != null, "墙留门洞且门洞上方有过梁")
	# HUD 必须如实广告四模式切换键：按键集合与模式数量一致，文案不得漏项。
	_check(_hud_advertises_all_modes(), "HUD 控制说明列出 1/2/3/4 四个策略切换键")
	_check(_capability_names() == EXPECTED_CAPABILITIES, "角色保持三项移动能力：%s" % str(_capability_names()))


## 静态边界：本实验脚本不得写角色物理/意图，也不得直接引用具体 Capability 类名。
func _check_static_boundaries() -> void:
	for path in [SCENE_SCRIPT_PATH, RIG_PATH, GRAYBOX_SCRIPT_PATH]:
		var source := _read_source(path)
		_check(not source.is_empty(), "可读取实验脚本源码：%s" % path.get_file())
		var offenders := _scan_forbidden(source)
		_check(offenders.is_empty(), "%s 不写 velocity / 意图 / 能力状态、不引用具体能力类名%s" % [
			path.get_file(), "" if offenders.is_empty() else "（命中 %s）" % ", ".join(offenders)])
	var actor_source := _read_source("res://game/actors/swordsman/swordsman.gd")
	_check(actor_source.count("move_and_slide(") == 1, "角色根仍是唯一 move_and_slide 提交点")
	for path in [SCENE_SCRIPT_PATH, RIG_PATH, GRAYBOX_SCRIPT_PATH]:
		_check(_read_source(path).count("move_and_slide(") == 0, "%s 无第二个物理提交点" % path.get_file())


func _scan_forbidden(source: String) -> PackedStringArray:
	var offenders := PackedStringArray()
	var code := _strip_comments(source)
	for pattern in FORBIDDEN_WRITES:
		if _regex_hits(code, pattern) > 0:
			offenders.append(pattern)
	for pattern in FORBIDDEN_CLASS_REFS:
		if _regex_hits(code, pattern) > 0:
			offenders.append(pattern)
	return offenders


func _regex_hits(source: String, pattern: String) -> int:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return -1
	return regex.search_all(source).size()


## 去掉整行注释与行尾注释，避免注释里的说明文字造成静态扫描误报。
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


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## HUD 文案必须与 MODE_KEYS 实际支持的按键数量一致（防止"四模式却只写三个键"）。
func _hud_advertises_all_modes() -> bool:
	var controls := current_scene.find_child("Controls", true, false) as Label
	if controls == null:
		return false
	var text := controls.text
	var advertised := [
		text.contains("1/2/3/4"),
		not text.contains("1/2/3 "),
		text.contains("Tab"),
	]
	return advertised[0] and advertised[1] and advertised[2]


func _capability_names() -> Array:
	var manager := _actor.get_node_or_null("CapabilityManager")
	if manager == null:
		return []
	var names := []
	for child in manager.get_children():
		var script: Variant = child.get_script()
		names.append(str(script.get_global_name()) if script != null else str(child.name))
	names.sort()
	return names


# --- 四种策略的比较 ------------------------------------------------------


func _run_mode_comparison() -> void:
	# 硬跟随：焦点必须每帧等于角色位置（无缓动、无死区）。
	await _prepare(Vector3(0.0, 0.1, -10.0), CameraLabRig.Mode.HARD)
	_key(KEY_D, true)
	await _frames(30)
	var hard_lag := _focus_lag()
	_key(KEY_D, false)
	_check(hard_lag < 0.05, "硬跟随：移动中焦点与角色位移差 %.3f m（无缓动）" % hard_lag)

	# 平滑跟随：移动中必须落后，停下后有界收敛。
	await _prepare(Vector3(0.0, 0.1, -10.0), CameraLabRig.Mode.SMOOTH)
	_key(KEY_D, true)
	await _frames(30)
	var smooth_lag := _focus_lag()
	var smooth_camera_moved := _camera.global_position
	_key(KEY_D, false)
	await _frames(SETTLE_FRAMES)
	var smooth_settled := _focus_lag()
	_check(smooth_lag > 0.4, "平滑跟随：移动中焦点落后 %.3f m（存在缓动）" % smooth_lag)
	_check(smooth_settled < 0.15, "平滑跟随：停 %.2fs 后收敛到 %.3f m" % [SETTLE_FRAMES / 60.0, smooth_settled])

	# 死区：目标未越界时焦点不动；越界后按死区边界拖动，且不产生前视。
	await _prepare(Vector3(0.0, 0.1, -10.0), CameraLabRig.Mode.DEADZONE)
	var focus_before := _focus_position()
	_key(KEY_D, true)
	await _frames(20)
	var deadzone_early := _focus_position().distance_to(focus_before)
	await _frames(90)
	var deadzone_lag := _focus_lag()
	var deadzone_lead := _lookahead_length()
	_deadzone_camera_lag = _camera_lag()
	_key(KEY_D, false)
	_check(deadzone_early < 0.05, "死区：目标在死区内时焦点不动（位移 %.3f m）" % deadzone_early)
	_check(deadzone_lag > 2.0, "死区：越界后焦点被拖动，落后 %.3f m" % deadzone_lag)
	_check(deadzone_lead < 0.01, "死区：无前视分量（%.3f m）" % deadzone_lead)

	# 死区 + 前视：同样的移动下前视分量非零，且焦点落后明显减小。
	await _prepare(Vector3(0.0, 0.1, -10.0), CameraLabRig.Mode.LOOKAHEAD)
	_key(KEY_D, true)
	await _frames(110)
	var lookahead_camera_lag := _camera_lag()
	var lookahead_lead := _lookahead_length()
	_key(KEY_D, false)
	# 前视只偏移相机瞄准点，不改变死区焦点本身；比较必须读相机瞄准点的落后。
	var deadzone_camera_lag := _deadzone_camera_lag
	_check(lookahead_lead > 0.5, "前视：移动中产生前视偏移 %.3f m" % lookahead_lead)
	_check(lookahead_camera_lag < deadzone_camera_lag - 0.5,
		"前视：相机瞄准点落后由 %.3f m 减到 %.3f m" % [deadzone_camera_lag, lookahead_camera_lag])

	# 同一段移动下三种非硬跟随策略的相机位姿互不相同，证明比较对象真的不同。
	var samples := {}
	for mode in [CameraLabRig.Mode.SMOOTH, CameraLabRig.Mode.DEADZONE, CameraLabRig.Mode.LOOKAHEAD]:
		await _prepare(Vector3(0.0, 0.1, -10.0), mode)
		_key(KEY_D, true)
		await _frames(40)
		samples[mode] = _camera.global_position
		_key(KEY_D, false)
		await _frames(2)
	var distinct := true
	var modes: Array = samples.keys()
	for i in range(modes.size()):
		for j in range(i + 1, modes.size()):
			if (samples[modes[i]] as Vector3).distance_to(samples[modes[j]] as Vector3) < 0.2:
				distinct = false
	_check(distinct, "同一段输入下平滑 / 死区 / 前视的相机位姿互不相同")


func _prepare(position: Vector3, mode: CameraLabRig.Mode) -> void:
	_actor.global_position = position
	_actor.reset_motion()
	_actor.set_aim_direction(Vector3.FORWARD)
	_rig.set_mode(mode)
	_rig.reset_state()
	await _frames(3)
	_check(_rig.mode() == mode, "策略切换到 %s 并读回" % str(CameraLabRig.MODE_NAMES[mode]))


func _focus_lag() -> float:
	return _rig.snapshot()["focus"].distance_to(_actor.global_position)


## 相机实际瞄准点的水平落后（含前视）；焦点落后只反映死区/缓动。
func _camera_lag() -> float:
	var aim: Vector3 = _rig.snapshot()["camera_focus"]
	var actor := _actor.global_position
	return Vector2(aim.x - actor.x, aim.z - actor.z).length()


func _focus_position() -> Vector3:
	return _rig.snapshot()["focus"]


## 角色在屏幕上的取景半径（像素）：正交 size 变化必须体现在这里。
func _screen_radius() -> float:
	var center := Vector2(root.size) * 0.5
	var screen := _camera.unproject_position(_actor.global_position + Vector3(0.0, 0.9, 0.0))
	return screen.distance_to(center)


func _lookahead_length() -> float:
	return (_rig.snapshot()["lookahead"] as Vector3).length()


# --- 屏幕相对方向 --------------------------------------------------------


func _run_screen_relative() -> void:
	# 镜头旋转后，角色位移必须沿相机地面基：与真实 Camera3D basis 的水平投影对照。
	for yaw in [0.0, 55.0, 140.0, -95.0]:
		await _prepare(Vector3(0.0, 0.1, -10.0), CameraLabRig.Mode.HARD)
		_rig.set_yaw_degrees(yaw)
		await _frames(6)
		var right := _ground(_camera.global_transform.basis.x)
		var forward := _ground(-_camera.global_transform.basis.z)
		_check(right.distance_to(_rig.right_axis()) < 0.01 and forward.distance_to(_rig.forward_axis()) < 0.01,
			"偏航 %d°：台架地面基与真实相机 basis 一致" % int(yaw))
		# W 输入 → 相机地面前方。
		var before := _actor.global_position
		_key(KEY_W, true)
		await _frames(12)
		_key(KEY_W, false)
		var displacement := _actor.global_position - before
		displacement.y = 0.0
		_check(displacement.length() > 0.15, "偏航 %d°：W 产生真实位移 %.2f m" % [int(yaw), displacement.length()])
		_check(displacement.normalized().dot(forward) > 0.95,
			"偏航 %d°：W 位移沿相机地面前方（dot %.3f）" % [int(yaw), displacement.normalized().dot(forward)])
		await _frames(2)
		# D 输入 → 相机地面右方。
		before = _actor.global_position
		_key(KEY_D, true)
		await _frames(12)
		_key(KEY_D, false)
		displacement = _actor.global_position - before
		displacement.y = 0.0
		_check(displacement.normalized().dot(right) > 0.95,
			"偏航 %d°：D 位移沿相机地面右方（dot %.3f）" % [int(yaw), displacement.normalized().dot(right)])
		_check(_motion.aim_direction.dot(right) > 0.9, "偏航 %d°：角色朝向相机右方" % int(yaw))
		await _frames(2)


func _ground(value: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


# --- 缩放 ----------------------------------------------------------------


func _run_zoom() -> void:
	await _prepare(Vector3(0.0, 0.1, -10.0), CameraLabRig.Mode.HARD)
	var base := _rig.zoom_size()
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	await _frames(2)
	var zoomed_in := _rig.zoom_size()
	_check(zoomed_in < base, "滚轮上滚拉近：size %.1f → %.1f" % [base, zoomed_in])
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _frames(2)
	var zoomed_out := _rig.zoom_size()
	_check(zoomed_out > base, "滚轮下滚拉远：size %.1f → %.1f" % [base, zoomed_out])
	# 正交相机的缩放体现在 size（取景范围）而非 position：用屏幕投影验证真实取景变化。
	# 注意测量点：必须在"拉近之后、拉远之前"读取，否则回到原 size 时取景当然不变。
	var screen_before := _screen_radius()
	_key(KEY_Z, true)
	await _frames(1)
	_key(KEY_Z, false)
	await _frames(2)
	var screen_zoomed := _screen_radius()
	_check(_rig.zoom_size() < zoomed_out, "Z 键拉近：size %.1f → %.1f" % [zoomed_out, _rig.zoom_size()])
	_check(screen_zoomed > screen_before, "拉近使角色屏幕取景变大（%.1f → %.1f px）" % [screen_before, screen_zoomed])
	_check(is_equal_approx(_camera.size, _rig.zoom_size()), "相机 size 与台架读数一致（%.1f）" % _camera.size)
	_key(KEY_X, true)
	await _frames(1)
	_key(KEY_X, false)
	await _frames(2)
	_check(_rig.zoom_size() > zoomed_out - 0.01, "X 键拉远：size 回到 %.1f" % _rig.zoom_size())
	_check(absf(_screen_radius() - screen_before) < 0.5, "X 键拉远后取景回到拉近前（%.1f px）" % _screen_radius())
	# 限幅：连续拉近 / 拉远都停在声明范围内。
	for _index in range(30):
		_rig.adjust_zoom(1.0)
	_check(is_equal_approx(_rig.zoom_size(), _rig.zoom_min), "连续拉近被限幅在 zoom_min=%.1f" % _rig.zoom_min)
	for _index in range(60):
		_rig.adjust_zoom(-1.0)
	_check(is_equal_approx(_rig.zoom_size(), _rig.zoom_max), "连续拉远被限幅在 zoom_max=%.1f" % _rig.zoom_max)
	await _frames(2)


# --- 切模式不改装配 / 物理 -----------------------------------------------


func _run_switch_purity() -> void:
	await _prepare(Vector3(0.0, 0.1, -10.0), CameraLabRig.Mode.HARD)
	var capabilities_before := _capability_names()
	var manager_count := _actor.get_node("CapabilityManager").get_child_count()
	var motion_before := _motion_snapshot()
	# 用真实按键依次切换四个策略（1/2/3/4），每种模式都在移动中切一次。
	var keyed := [KEY_1, KEY_2, KEY_3, KEY_4]
	var modes := [CameraLabRig.Mode.HARD, CameraLabRig.Mode.SMOOTH, CameraLabRig.Mode.DEADZONE, CameraLabRig.Mode.LOOKAHEAD]
	_key(KEY_D, true)
	for index in range(keyed.size()):
		_key(keyed[index], true)
		await _frames(1)
		_key(keyed[index], false)
		await _frames(8)
		_check(_rig.mode() == modes[index], "按键 %d 切换到 %s 并读回" % [index + 1, str(CameraLabRig.MODE_NAMES[modes[index]])])
		_check(absf(_motion.actual_velocity.length() - _motion.move_speed) < 0.6,
			"切到 %s 时角色仍按 move_speed 移动（%.2f m/s）" % [str(CameraLabRig.MODE_NAMES[modes[index]]), _motion.actual_velocity.length()])
	# Tab 循环：从 LOOKAHEAD 回到 HARD。
	_key(KEY_TAB, true)
	await _frames(1)
	_key(KEY_TAB, false)
	await _frames(2)
	_key(KEY_D, false)
	await _frames(2)
	_check(_rig.mode() == CameraLabRig.Mode.HARD, "Tab 从最后一个策略循环回硬跟随")
	_check(_capability_names() == capabilities_before, "切换全部策略后三能力装配不变：%s" % str(_capability_names()))
	_check(_actor.get_node("CapabilityManager").get_child_count() == manager_count, "CapabilityManager 子节点数不变（%d）" % manager_count)
	_check(_motion_snapshot() == motion_before, "切换策略不改角色物理参数")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "切模式不产生 sword_flight_block 残留")
	_check(_single_commit_point(), "切模式后角色根仍是唯一物理提交点")


func _motion_snapshot() -> Dictionary:
	return {
		"move_speed": _motion.move_speed,
		"jump_speed": _motion.jump_speed,
		"gravity": _motion.gravity,
		"flight_speed": _motion.flight_speed,
		"flight_lift_speed": _motion.flight_lift_speed,
		"flight_sink_speed": _motion.flight_sink_speed,
		"flight_launch_speed": _motion.flight_launch_speed,
		"flight_launch_time": _motion.flight_launch_time,
	}


func _single_commit_point() -> bool:
	return _read_source("res://game/actors/swordsman/swordsman.gd").count("move_and_slide(") == 1 		and _read_source(SCENE_SCRIPT_PATH).count("move_and_slide(") == 0


# --- 重置与退出 ----------------------------------------------------------


func _run_reset_and_exit() -> void:
	_actor.global_position = Vector3(0.0, 0.1, -10.0)
	_rig.set_mode(CameraLabRig.Mode.LOOKAHEAD)
	_rig.set_yaw_degrees(120.0)
	_rig.adjust_zoom(3.0)
	_key(KEY_D, true)
	await _frames(30)
	_key(KEY_D, false)
	_key(KEY_R, true)
	await _frames(1)
	_key(KEY_R, false)
	await _frames(6)
	_bind()
	_check(_actor.global_position.distance_to(Vector3(0.0, 0.1, -10.0)) < 0.2, "R 复位角色到出生点")
	_check(absf(_rig.yaw_degrees - (-35.0)) < 0.01, "R 复位镜头偏航到 -35°")
	_check(_focus_lag() < 0.05, "R 复位焦点贴回角色")
	_check(_rig.zoom_size() > 0.0 and _rig.zoom_size() <= _rig.zoom_max, "R 后缩放仍在限幅内（%.1f）" % _rig.zoom_size())
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(8)
	_check(current_scene != null and current_scene.name == HUB_ROOT,
		"Esc 返回角色移动子实验目录（实际 %s）" % (current_scene.name if current_scene != null else "<null>"))
	_check(root.msaa_3d == _msaa_before, "返回目录后根视口 MSAA 恢复为进入前的值（%d）" % _msaa_before)


# --- 截图（窗口模式） ----------------------------------------------------


func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "无头渲染器无法截图，请用窗口模式运行截图")
		_finish()
		return
	# 首帧字形尚未上传时截图会丢掉整层 HUD 文字；先有界等待真实渲染帧完成字形预热。
	await _wait_render_frames(48)
	root.get_texture().get_image()
	await _frames(4)
	# 四种策略跑同一段输入并同时截图：唯一变量是跟随策略。
	for mode in CameraLabRig.MODE_ORDER:
		await _prepare(Vector3(0.0, 0.1, -10.0), mode)
		_key(KEY_D, true)
		await _frames(45)
		_print_snapshot(str(CameraLabRig.MODE_KEYS[mode]))
		await _capture("%s-moving" % str(CameraLabRig.MODE_KEYS[mode]))
		_key(KEY_D, false)
		await _frames(2)
	# 遮挡对照：角色站在 4 m 遮挡板背面（相对高角度相机），视线被挡住。
	await _prepare(OCCLUDED_POSITION, CameraLabRig.Mode.HARD)
	_rig.set_yaw_degrees(-35.0)
	await _frames(20)
	_check(bool(_lab.call("is_occluded")), "遮挡对照位：相机到角色的视线被遮挡板挡住")
	_print_snapshot("occluded")
	await _capture("occluded")
	await _prepare(UNOCCLUDED_POSITION, CameraLabRig.Mode.HARD)
	_rig.set_yaw_degrees(-35.0)
	await _frames(20)
	_check(not bool(_lab.call("is_occluded")), "开阔位：同一策略下视线不被遮挡（对照）")
	_print_snapshot("open")
	await _capture("open")
	# 缩放对照：同一构图下近景与远景。
	await _prepare(Vector3(0.0, 0.1, -10.0), CameraLabRig.Mode.SMOOTH)
	_rig.adjust_zoom(6.0)
	await _frames(20)
	await _capture("zoom-near")
	_rig.adjust_zoom(-9.0)
	await _frames(20)
	await _capture("zoom-far")
	# 小窗布局：HUD 不得溢出。
	root.size = Vector2i(960, 640)
	await _frames(6)
	await _capture("small")
	_finish()


## 截图前打印可核对的运行时读数：策略、相机 transform、角色位移与焦点偏移。
func _print_snapshot(label: String) -> void:
	var snapshot := _rig.snapshot()
	var camera := _camera.global_transform
	print("SNAPSHOT %s mode=%s camera_pos=(%.2f, %.2f, %.2f) actor=(%.2f, %.2f, %.2f) focus=(%.2f, %.2f, %.2f) lag=%.3f lookahead=%.3f yaw=%.1f zoom=%.1f" % [
		label, str(snapshot["mode"]),
		camera.origin.x, camera.origin.y, camera.origin.z,
		_actor.global_position.x, _actor.global_position.y, _actor.global_position.z,
		(snapshot["focus"] as Vector3).x, (snapshot["focus"] as Vector3).y, (snapshot["focus"] as Vector3).z,
		_focus_lag(), (_lookahead_length()), float(snapshot["yaw_degrees"]), float(snapshot["zoom_size"]),
	])


# --- 基础设施 ------------------------------------------------------------


func _bind() -> void:
	_lab = current_scene
	_actor = null
	for child in current_scene.find_children("*", "CharacterBody3D", true, false):
		_actor = child
		break
	_motion = _actor.get_node("SwordsmanMotionComponent")
	_camera = root.get_camera_3d()
	_rig = current_scene.get_node_or_null("CameraRig") as CameraLabRig


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = Vector2(640, 400)
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame


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
	print("CAMERA_LAB_PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)
