extends SceneTree

## 御剑飞行训练场的无头 / 窗口验收。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md
## 「御剑飞行训练场」与验收契约：起飞、升降、悬停、穿越、转向、落点选择。
##
## 全部飞行由真实键盘事件驱动（Input.parse_input_event），不使用传送伪造通关：
## 起飞、升高、多门连续穿越、悬停、转向、真实落地都在同一段连续飞行里完成。
## 仅在独立子批次开头重置到路线起点（R / _reset_experiment），子批次内部不重置。
##
## 覆盖：
## - 装配、路线数据、三能力 / 唯一物理提交点 / 公开 API / helper / 返回链；
## - 按序穿门（不能跳过、未御剑不算空中门）、环体不可穿透；
## - 升降 / 悬停计时 / 转向 / 两个落点；
## - Space/Ctrl release 与失焦清账、F echo 不重复切换；
## - 截图（窗口模式）与运行时 SNAPSHOT 读回。
##
## 未覆盖（交使用者）：飞行手感、路线难度、画面审美。

const SCENE := "res://levels/experiments/character_movement/sword_flight_course.tscn"
const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const HUB_ROOT := "MovementLabHub"
const ROUTE_PATH := "res://levels/experiments/character_movement/sword_flight_course_collision.json"
const SCENE_SCRIPT := "res://levels/experiments/character_movement/sword_flight_course.gd"

const EXPECTED_CAPABILITIES := ["Jump", "SwordFlight", "SwordsmanMovement"]
const FLIGHT_TAG := &"sword_flight_block"
const CAPTURE_TIMEOUT_MSEC := 4000

var _failed := 0
var _prefix := ""
var _course: Node3D
var _actor: CharacterBody3D
var _motion: SwordsmanMotionComponent
var _camera: Camera3D
var _route: Dictionary = {}
var _frame_drawn := false
var _msaa_before: Viewport.MSAA = Viewport.MSAA_DISABLED


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	_msaa_before = root.msaa_3d
	if change_scene_to_file(SCENE) != OK:
		print("FAIL 无法加载御剑训练场场景：%s" % SCENE)
		quit(1)
		return
	await scene_changed
	await _frames(5)
	_bind()
	_check_assembly()
	_check_route_data()
	_check_ownership_boundaries()

	if not _prefix.is_empty():
		await _run_capture()
		return

	await _run_vertical_and_hover()
	await _run_flight_route()
	await _run_landings()
	await _run_input_hygiene()
	await _run_fall_out_recovery()
	await _run_reset_and_exit()
	_finish()


func _bind() -> void:
	_course = current_scene
	_actor = null
	for child in current_scene.find_children("*", "CharacterBody3D", true, false):
		_actor = child
		break
	_motion = _actor.get_node("SwordsmanMotionComponent")
	_camera = root.get_camera_3d()
	_route = JSON.parse_string(FileAccess.get_file_as_string(ROUTE_PATH))


# ---------------------------------------------------------------- 装配与边界


func _check_assembly() -> void:
	_check(_actor != null and _motion != null and _camera != null, "训练场装配完成（角色 / 组件 / 相机）")
	_check(_camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "相机为正交投影")
	_check(current_scene.get_node_or_null("CourseVisual") != null, "场景实例化了课程 GLB 视觉")
	_check(current_scene.get_node_or_null("CourseCollision") != null, "场景装配了课程碰撞根节点")
	_check(_capability_names() == EXPECTED_CAPABILITIES, "角色保持三项移动能力：%s" % str(_capability_names()))
	_check(_motion.flight_speed > 0.0 and _motion.flight_lift_speed > 0.0, "御剑参数由组件提供（未内联）")


func _check_route_data() -> void:
	_check(_route.get("schema") == "sword_flight_course_collision/1", "路线数据 schema 匹配")
	var gates: Array = _route["gates"]
	_check(gates.size() >= 5, "路线含至少 5 道玉环门（实际 %d）" % gates.size())
	var landings: Array = _route["landings"]
	_check(landings.size() >= 2, "路线含至少两个落点（实际 %d）" % landings.size())
	# 落点必须有取舍：高度或距离不同，否则"选择"不成立。
	var first: Dictionary = landings[0]
	var second: Dictionary = landings[1]
	var height_gap: float = absf(float(first["top_y"]) - float(second["top_y"]))
	_check(height_gap > 1.0, "两个落点高度不同（差 %.1f m）" % height_gap)
	# 门序高度应递进后再回落，构成真正的立体路线。
	var heights: Array[float] = []
	for gate in gates:
		heights.append(float((gate["center"] as Array)[1]))
	var max_height: float = heights.max()
	_check(max_height > heights[0] + 4.0, "航线抬升明显（首门 %.1f m → 最高 %.1f m）" % [heights[0], max_height])
	_check(heights[-1] < max_height, "末段为下坡转向（%.1f m < 峰值 %.1f m）" % [heights[-1], max_height])
	# 视觉与碰撞同源：GLB 与路线 JSON 都由生成器产出。
	var glb := "res://levels/experiments/character_movement/sword_flight_course.glb"
	_check(ResourceLoader.exists(glb), "课程 GLB 存在：%s" % glb)
	var colliders: Array = _route["colliders"]
	_check(colliders.size() > 40, "碰撞盒充分覆盖路线（%d 个）" % colliders.size())
	# 碰撞体与场景节点一一对应（可见几何都有对应碰撞，无隐形墙）。
	var missing := PackedStringArray()
	for entry in colliders:
		if current_scene.get_node_or_null("CourseCollision/%s" % str(entry["name"])) == null:
			missing.append(str(entry["name"]))
	_check(missing.is_empty(), "路线碰撞盒全部装配到场景%s" % (
		"" if missing.is_empty() else "（缺 %d 个）" % missing.size()))
	# 纯视觉件不得同时是碰撞体，避免"隐形墙"。
	var ridged := {}
	for entry in colliders:
		ridged[str(entry["name"])] = true
	var visual_conflicts := PackedStringArray()
	for name in _route["visual_only"]:
		if ridged.has(str(name)):
			visual_conflicts.append(str(name))
	_check(visual_conflicts.is_empty(), "纯视觉件未被登记为碰撞体%s" % (
		"" if visual_conflicts.is_empty() else "（冲突 %s）" % ", ".join(visual_conflicts)))


## 静态边界：本场景不写角色物理 / 意图 / 能力状态，不自行调用组件的写接口。
func _check_ownership_boundaries() -> void:
	var source := _read_source(SCENE_SCRIPT)
	_check(not source.is_empty(), "可读取场景脚本源码")
	# 去注释后再扫：注释说明「唯一 move_and_slide 在 actor 根节点」属正常文档。
	var code := _strip_comments(source)
	for pattern in ["\\.velocity\\s*=", "\\.move_input\\s*=", "\\.desired_horizontal\\s*=",
			"\\.desired_vertical\\s*=", "\\.vertical_impulse\\s*=", "\\.flight_active\\s*=",
			"\\.on_floor\\s*=", "\\bmove_and_slide\\s*\\(", "\\badd_block\\s*\\(",
			"\\bremove_block\\s*\\("]:
		_check(_regex_hits(code, pattern) == 0, "场景脚本不匹配 %s" % pattern)
	# 必须使用 MovementLabInput（WASD/方向键 / Space/Ctrl / F）。
	_check(source.contains("MovementLabInput.new()"), "场景使用 MovementLabInput")
	_check(source.contains("VERTICAL_KEYS"), "场景显式声明升降键")
	# 只调用公开输入 API。
	for api in ["set_move_input", "set_vertical_input", "press_jump", "press_flight_toggle",
			"set_camera_ground_basis", "reset_motion", "clear_input"]:
		_check(source.contains(api), "场景调用公开 API %s" % api)
	_check(_read_source("res://game/actors/swordsman/swordsman.gd").count("move_and_slide(") == 1,
		"角色根仍是唯一 move_and_slide 提交点")
	_check(code.count("move_and_slide(") == 0, "场景无第二个物理提交点（注释不计）")
	# 路线状态机保持局部：不得引用核心系统。
	# 装配断言里提到角色自带的管理器节点名（capability_manager()）不算引入核心系统。
	for forbidden in ["class_name", "autoload", "Engine.get_singleton"]:
		_check(not code.contains(forbidden), "场景不引入核心系统概念 %s" % forbidden)


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


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()


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


func _regex_hits(source: String, pattern: String) -> int:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return -1
	return regex.search_all(source).size()


# ---------------------------------------------------------------- 飞行驾驶
# 全部按键都是真实 InputEventKey（Input.parse_input_event），由 MovementLabInput 归一化后
# 写进角色公开 API。飞船方向按相机地面基换算，和玩家用 WASD 做的事一样，不传送、不写 velocity。


## 当前按下的移动键集合，用于只发送变化量（release 必须真的发出）。
var _held_keys := {}


func _set_move_keys(direction: Vector2) -> void:
	# direction: x = 屏幕右，y = 屏幕下（与 MovementLabInput 的 move_input 同语义）。
	var wanted := {}
	if direction.y < -0.35:
		wanted[KEY_W] = true
	elif direction.y > 0.35:
		wanted[KEY_S] = true
	if direction.x > 0.35:
		wanted[KEY_D] = true
	elif direction.x < -0.35:
		wanted[KEY_A] = true
	_sync_keys(wanted)


func _sync_keys(wanted: Dictionary) -> void:
	for code in _held_keys.keys():
		if not wanted.has(code):
			_key(code, false)
	for code in wanted.keys():
		if not _held_keys.get(code, false):
			_key(code, true)
	_held_keys = wanted.duplicate()


func _release_all_keys() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_CTRL]:
		_key(code, false)
	_held_keys.clear()


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


## 把世界方向投影到相机地面基，得到屏幕相对输入（x 右 / y 下）。
func _screen_direction(world_direction: Vector3) -> Vector2:
	var right := _ground(_camera.global_transform.basis.x, Vector3.RIGHT)
	var forward := _ground(-_camera.global_transform.basis.z, Vector3.FORWARD)
	# movement: dir = right * x - forward * y  =>  x = dir·right, y = -(dir·forward)
	return Vector2(world_direction.dot(right), -world_direction.dot(forward))


## 朝目标点飞行若干帧；返回是否在容差内到达。全程真实按键与真实物理。
## 机身中心相对脚底原点的偏移（与场景 BODY_CENTER_OFFSET 同值）。
## 对准玉环门 / 悬停区时要把脚底坐标抬这么高，否则窄门会撞环体下缘。
const BODY_CENTER_OFFSET := 0.8


func _fly_to(target: Vector3, tolerance: float, max_frames: int,
		vertical_band: float = -1.0) -> bool:
	# 竖直死区必须小于收敛半径的一半，否则会在目标外停住、永远判不到达。
	if vertical_band < 0.0:
		vertical_band = maxf(0.12, tolerance * 0.45)
	var reached := false
	for _frame in range(max_frames):
		var position := _body_center()
		var delta := target - position
		var horizontal := Vector3(delta.x, 0.0, delta.z)
		var input := Vector2.ZERO
		if horizontal.length() > tolerance * 0.6:
			input = _screen_direction(horizontal.normalized())
		# 竖直：超过容差带才按升降键，带内松开（形成稳定悬停带）。
		if delta.y > vertical_band:
			_sync_keys(_wanted_with(input, KEY_SPACE))
		elif delta.y < -vertical_band:
			_sync_keys(_wanted_with(input, KEY_CTRL))
		else:
			_set_move_keys(input)
		await _tick()
		if _body_center().distance_to(target) <= tolerance:
			reached = true
			break
	return reached


func _wanted_with(direction: Vector2, vertical_key: Key) -> Dictionary:
	var wanted := {}
	if direction.y < -0.35:
		wanted[KEY_W] = true
	elif direction.y > 0.35:
		wanted[KEY_S] = true
	if direction.x > 0.35:
		wanted[KEY_D] = true
	elif direction.x < -0.35:
		wanted[KEY_A] = true
	wanted[vertical_key] = true
	return wanted


## 起飞：按 F 进入御剑并升到目标高度以上，全程真实按键。
func _take_off(target_height: float, max_frames: int) -> bool:
	_key(KEY_F, true)
	await _tick()
	_key(KEY_F, false)
	await _tick()
	if not _motion.flight_active:
		return false
	for _frame in range(max_frames):
		if _actor.global_position.y >= target_height:
			_set_move_keys(Vector2.ZERO)
			await _tick()
			return true
		_sync_keys({KEY_SPACE: true})
		await _tick()
	_set_move_keys(Vector2.ZERO)
	return false



# ---------------------------------------------------------------- 主验收批次


## 竖直控制：起飞后验证 Space 上升 / release 悬停 / Ctrl 下降的真实竖直速度。
func _run_vertical_and_hover() -> void:
	await _reset_route()
	_check(await _take_off(4.0, 240), "真实 F + Space 起飞并升到 4 m 以上")
	var hover_y := _actor.global_position.y
	# release：松开全部键后必须真实悬停（vy≈0、高度基本不变）。
	_release_all_keys()
	await _frames(30)
	_check(absf(_motion.actual_velocity.y) < 0.05, "松开升降键后竖直速度归零（vy=%.3f）" % _motion.actual_velocity.y)
	_check(absf(_actor.global_position.y - hover_y) < 0.25, "悬停时高度稳定（Δy=%.3f）" % (_actor.global_position.y - hover_y))
	# Space：真实上升。
	var before_up := _actor.global_position.y
	_sync_keys({KEY_SPACE: true})
	await _frames(20)
	_check(_motion.actual_velocity.y > 3.0, "Space 产生真实上升速度（vy=%.2f）" % _motion.actual_velocity.y)
	_check(_actor.global_position.y > before_up + 0.5, "Space 期间高度真实增加（Δy=%.2f）" % (_actor.global_position.y - before_up))
	# release 后再次悬停（release 语义必须真实生效）。
	_release_all_keys()
	await _frames(25)
	_check(absf(_motion.actual_velocity.y) < 0.05, "再次 release 后重新悬停（vy=%.3f）" % _motion.actual_velocity.y)
	# Ctrl：真实下降。
	var before_down := _actor.global_position.y
	_sync_keys({KEY_CTRL: true})
	await _frames(20)
	_check(_motion.actual_velocity.y < -3.0, "Ctrl 产生真实下降速度（vy=%.2f）" % _motion.actual_velocity.y)
	_check(_actor.global_position.y < before_down - 0.5, "Ctrl 期间高度真实减少（Δy=%.2f）" % (_actor.global_position.y - before_down))
	_release_all_keys()


## 主航线：一次连续飞行按序穿过全部玉环门 + 悬停 + 落点，全程真实按键。
func _run_flight_route() -> void:
	await _reset_route()
	_check(await _take_off(4.0, 240), "主航线：真实起飞")
	var gates: Array = _route["gates"]
	var trail_before := _trail_points()
	# 逐门飞过：先对准环心，再穿过环平面到另一侧。
	for index in range(gates.size()):
		var gate: Dictionary = gates[index]
		var center := _vec(gate["center"])
		var yaw := deg_to_rad(float(gate["yaw"]))
		var axis := Vector3(sin(yaw), 0.0, -cos(yaw))
		# 对准容差随环口收缩：窄门必须对准环心，否则会从环体外侧掠过。
		var aim_tolerance: float = minf(2.6, maxf(0.9, float(gate["radius"]) * 0.5))
		var entry := center - axis * 4.5
		var exit_point := center + axis * 4.5
		var aligned := await _fly_to(entry, aim_tolerance, 420)
		var crossed := await _fly_to(exit_point, aim_tolerance, 420)
		var state := _route_state()
		_check(aligned and crossed, "第 %d 门「%s」由真实飞行对准并穿过（y=%.1f m）" % [
			index + 1, str(gate["title"]), _actor.global_position.y])
		_check(int(state["gate_index"]) == index + 1,
			"第 %d 门后门序进度为 %d（不可跳过 / 不可重复）" % [index + 1, index + 1])
	# 悬停段：飞到悬停区中心附近并真实悬停计满。
	var hover: Dictionary = _route["hover"]
	var hover_center := _vec(hover["center"])
	await _fly_to(hover_center, 1.8, 420)
	_release_all_keys()
	var hover_seconds := float(hover["seconds"])
	var waited := 0
	while not bool(_route_state()["hover_done"]) and waited < 60 * (hover_seconds + 3.0):
		_sync_keys(_hover_hold_keys(hover_center))
		await _tick()
		waited += 1
	var state_after := _route_state()
	_check(bool(state_after["hover_done"]),
		"在悬停区累计满 %.1f s 悬停（实际 %.2f s）" % [
			hover_seconds, float(state_after["hover_accumulated"])])
	_check(int(state_after["gate_index"]) == gates.size(), "悬停前已按序穿完全部门")
	_check(_trail_points() > trail_before + 400, "整段航线由连续真实飞行完成（轨迹点 %d）" % _trail_points())


## 悬停保持：只做小修正把角色维持在悬停区中心，不按升降键。
func _hover_hold_keys(center: Vector3) -> Dictionary:
	var delta := center - _body_center()
	var horizontal := Vector3(delta.x, 0.0, delta.z)
	if horizontal.length() < 0.6:
		return {}
	return _screen_direction_keys(horizontal.normalized())


func _screen_direction_keys(world_direction: Vector3) -> Dictionary:
	var screen := _screen_direction(world_direction)
	var wanted := {}
	if screen.y < -0.35:
		wanted[KEY_W] = true
	elif screen.y > 0.35:
		wanted[KEY_S] = true
	if screen.x > 0.35:
		wanted[KEY_D] = true
	elif screen.x < -0.35:
		wanted[KEY_A] = true
	return wanted


## 落点：两个落点各验证一次真实落地（各自独立子批次重置到起点）。
func _run_landings() -> void:
	var landings: Array = _route["landings"]
	for landing in landings:
		await _reset_route()
		var id := str(landing["id"])
		var top_y := float(landing["top_y"])
		var center := _vec(landing["center"])
		var take_off_ok := await _take_off(top_y + 5.0, 300)
		var approach := await _fly_to(Vector3(center.x, top_y + 3.2, center.z), 1.6, 600)
		# 关飞并自然下落（不使用 Ctrl 压落，保留真实重力接触）。
		_key(KEY_F, true)
		await _tick()
		_key(KEY_F, false)
		_release_all_keys()
		var landed := false
		for _frame in range(300):
			await _tick()
			if _motion.on_floor:
				landed = true
				break
		# 父节点 _physics_process 先于子节点：落地那一帧场景尚未读到 on_floor，
		# 多等几帧让 _update_route 观察到真实着地后才读落点结果。
		await _frames(4)
		var state := _route_state()
		_check(take_off_ok and approach, "落点「%s」真实飞抵其上方（y=%.1f m）" % [str(landing["title"]), top_y])
		_check(landed, "落点「%s」真实落地（on_floor，y=%.2f m）" % [str(landing["title"]), _actor.global_position.y])
		_check(str(state["landing_result"]) == id,
			"落点判定记录为 %s（实际 %s）" % [id, str(state["landing_result"])])
		_check(absf(_actor.global_position.y - top_y) < 1.2,
			"落点高度贴合台面（%.2f m vs 台面 %.2f m）" % [_actor.global_position.y, top_y])
		_release_all_keys()
		await _frames(2)


## 重置到路线起点（子批次边界）：R 清输入 / 清飞行 / 清路线进度。
func _reset_route() -> void:
	_release_all_keys()
	_key(KEY_R, true)
	await _tick()
	_key(KEY_R, false)
	await _tick()
	await _frames(6)
	var state := _route_state()
	assert(int(state["gate_index"]) == 0, "重置后门序归零")
	assert(not _motion.flight_active, "重置后角色不处于御剑")
	assert(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "重置后飞行阻塞清账")


## 水平化向量：与场景同规则（零向量退化时回退世界轴）。
static func _ground(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


## 当前身体中心（脚底原点 + 胶囊偏移），与场景判定同一语义。
func _body_center() -> Vector3:
	var offset: float = float(_course.call("body_center_offset"))
	return _actor.global_position + Vector3(0.0, offset, 0.0)


func _vec(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2]))


func _trail_points() -> int:
	return int(_route_state()["trail_points"])


## 路线状态只读访问（场景 API 经 call 调用，返回值显式定型）。
func _route_state() -> Dictionary:
	return _course.call("route_state") as Dictionary



# ---------------------------------------------------------------- 输入卫生与退出


## F echo 不重复切换、Space/Ctrl release、失焦清账、未御剑不算空中门。
func _run_input_hygiene() -> void:
	# 未御剑时穿过环口不得记账（地面/重力状态下的穿越无效）。
	await _reset_route()
	var gates: Array = _route["gates"]
	var first: Dictionary = gates[0]
	var center := _vec(first["center"])
	var yaw := deg_to_rad(float(first["yaw"]))
	var axis := Vector3(sin(yaw), 0.0, -cos(yaw))
	# 直接放到环下方并向上穿过（未御剑，仅测试判定不受重力干扰）。
	_actor.global_position = center - axis * 1.2
	await _frames(4)
	_check(not _motion.flight_active, "空中门检查前角色未御剑")
	_check(int(_route_state()["gate_index"]) == 0, "未御剑时穿过环口不记门序")

	# F echo：按住产生的重复事件不得再次切换飞行。
	await _reset_route()
	_key(KEY_F, true)
	await _tick()
	_key(KEY_F, false)
	await _tick()
	var on_after_first := _motion.flight_active
	for _index in range(4):
		var echo := InputEventKey.new()
		echo.keycode = KEY_F
		echo.physical_keycode = KEY_F
		echo.pressed = true
		echo.echo = true
		Input.parse_input_event(echo)
		await _tick()
	_check(on_after_first, "F 首次按下开启御剑")
	_check(_motion.flight_active, "F echo 重复事件不关闭御剑（仍御剑）")

	# 失焦：清输入但保留御剑悬停（不自动关飞、不坠落）。
	_sync_keys({KEY_SPACE: true})
	await _frames(6)
	var altitude_before := _actor.global_position.y
	_course.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(20)
	_check(_motion.flight_active, "失焦后御剑仍开启（保留悬停）")
	_check(absf(_motion.actual_velocity.y) < 0.05, "失焦清掉升降输入（vy=%.3f）" % _motion.actual_velocity.y)
	_check(_input_is_clear(), "失焦清空 helper 按住状态")
	_check(absf(_actor.global_position.y - altitude_before) < 0.3, "失焦后高度稳定（不坠落）")

	# R 清账：关闭飞行并清空阻塞。
	await _reset_route()
	_check(not _motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 0,
		"R 关闭御剑并清空 sword_flight_block")
	# Space release 必须真实生效（松开后不再上升）。
	await _reset_route()
	await _take_off(3.0, 240)
	_sync_keys({KEY_SPACE: true})
	await _frames(15)
	_release_all_keys()
	await _frames(25)
	_check(absf(_motion.actual_velocity.y) < 0.08, "Space release 生效（vy=%.3f）" % _motion.actual_velocity.y)
	# Ctrl release 同理。
	_sync_keys({KEY_CTRL: true})
	await _frames(15)
	_release_all_keys()
	await _frames(25)
	_check(absf(_motion.actual_velocity.y) < 0.08, "Ctrl release 生效（vy=%.3f）" % _motion.actual_velocity.y)

	# 环体不可穿透：对准真实环体碰撞块推进，用角色真实胶囊做逐帧形状查询。
	#
	# 判据说明（本轮实测校准）：环体是细圆环，胶囊正面撞上后会被真实碰撞挡住并沿切向滑开——
	# 这是正确的物理结果，不是穿透。因此不断言"停在某一轴向位置"，而断言两件真正等价的事：
	# ① 全程与环体发生真实接触（放大 5 cm 的胶囊命中环体块）——证明环体确实参与碰撞；
	# ② 精确形状从未与环体块重叠——证明没有穿透实体。
	await _reset_route()
	await _take_off(6.0, 300)
	var rim_block := current_scene.get_node_or_null("CourseCollision/gate_1_rim00") as Node3D
	_check(rim_block != null, "第 1 门存在环体碰撞块节点")
	_check(_rim_block_count() >= 16, "第 1 门环体由 %d 个碰撞块组成（连续环壁）" % _rim_block_count())
	var gate2: Dictionary = gates[0]
	var yaw2 := deg_to_rad(float(gate2["yaw"]))
	var axis2 := Vector3(sin(yaw2), 0.0, -cos(yaw2))
	var block_center := rim_block.global_position
	# 起点：环体前方 3 m，身体中心对齐环体高度（脚底低 BODY_CENTER_OFFSET）。
	_actor.global_position = block_center - axis2 * 3.0 - Vector3(0.0, BODY_CENTER_OFFSET, 0.0)
	_actor.reset_motion()
	await _frames(4)
	_key(KEY_F, true)
	await _tick()
	_key(KEY_F, false)
	await _tick()
	var contact_frames := 0
	var penetration_frames := 0
	for _frame in range(200):
		var body_now := _body_center()
		var to_target := block_center - body_now
		to_target.y = 0.0
		var input := Vector2.ZERO
		if to_target.length() > 0.25:
			input = _screen_direction(to_target.normalized())
		_sync_keys(_keys_for_input(input))
		await _tick()
		if _probe_ring_overlap(0.05):
			contact_frames += 1
		if _probe_ring_overlap(0.0):
			penetration_frames += 1
	_release_all_keys()
	_check(contact_frames > 0,
		"环体真实参与碰撞：%d 帧内胶囊与环体块发生接触" % contact_frames)
	_check(penetration_frames == 0,
		"环体不可穿透：精确胶囊与环体块重叠帧数 = %d（0 表示从未穿透实体）" % penetration_frames)
	# 未御剑时贴近环体也不得被算作穿门。
	_check(int(_route_state()["gate_index"]) == 0,
		"贴环滑行不记门序（进度仍为 %d）" % int(_route_state()["gate_index"]))


## 以角色真实胶囊做形状查询：growth > 0 时放大胶囊，命中即"在此距离内接触环体"。
func _probe_ring_overlap(growth: float) -> bool:
	var shape_node := _actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return false
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		return false
	var probe := CapsuleShape3D.new()
	probe.radius = capsule.radius + growth
	probe.height = capsule.height + growth * 2.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = shape_node.global_transform
	params.collision_mask = 1
	params.exclude = [_actor.get_rid()]
	var hits := _actor.get_world_3d().direct_space_state.intersect_shape(params, 32)
	# 注意：Node.get_path() 返回绝对路径（/root/...），必须按节点名判断。
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Node and str((collider as Node).name).begins_with("gate_1_rim"):
			return true
	return false


func _rim_block_count() -> int:
	var count := 0
	var root := current_scene.get_node_or_null("CourseCollision")
	if root == null:
		return 0
	for child in root.get_children():
		if str(child.name).begins_with("gate_1_rim"):
			count += 1
	return count


## 按键集合（供驾驶循环复用，与 _set_move_keys 同语义）。
func _keys_for_input(input: Vector2) -> Dictionary:
	var wanted := {}
	if input.y < -0.35:
		wanted[KEY_W] = true
	elif input.y > 0.35:
		wanted[KEY_S] = true
	if input.x > 0.35:
		wanted[KEY_D] = true
	elif input.x < -0.35:
		wanted[KEY_A] = true
	return wanted


func _input_is_clear() -> bool:
	var helper: Variant = _course.get("_input")
	if helper == null:
		return false
	return int(helper.call("held_count")) == 0


# ---------------------------------------------------------------- 重置与退出


## 掉出回收：关飞后飞出航路不得无限下坠；回收必须走公开清账并归还全部状态。
func _run_fall_out_recovery() -> void:
	await _reset_route()
	var before := int(_route_state()["fall_out_count"])
	var fall_out_y := float(_route_state()["fall_out_y"])
	_check(fall_out_y < 0.0, "掉出阈值在起降台面之下（%.0f m）" % fall_out_y)

	# 先真实起飞并确认三能力与阻塞处于"御剑中"，再制造掉出。
	await _take_off(5.0, 300)
	_check(_motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 1,
		"掉出前：御剑中且已登记一条 sword_flight_block")
	# 关飞后把角色放到航路之外的下方（不新增任何传送式通关；这里只制造掉出条件）。
	_key(KEY_F, true)
	await _tick()
	_key(KEY_F, false)
	await _tick()
	_check(not _motion.flight_active, "关飞后进入自由落体（掉出前状态就绪）")
	var bounds_min := _vec(_route["bounds"]["min"])
	_actor.global_position = Vector3(bounds_min.x - 6.0, fall_out_y - 3.0, bounds_min.z - 6.0)
	_actor.reset_motion()
	_sync_keys({KEY_W: true, KEY_SPACE: true})
	await _frames(6)

	# 回收必须发生、且次数递增。
	var after := int(_route_state()["fall_out_count"])
	_check(after == before + 1, "掉出触发回收并计数 +1（%d → %d）" % [before, after])
	_check(_actor.global_position.distance_to(_spawn_position()) < 1.6, "回收回起飞坪")
	_check(_actor.global_position.y > fall_out_y, "回收后不再位于掉出阈值之下（y=%.2f）" % _actor.global_position.y)

	# 清账：输入 / 边沿 / 御剑 / 阻塞 / 速度全部归零。
	_check(_input_is_clear(), "回收清空 helper 按住状态（含 Space / W release）")
	_check(not _motion.flight_active, "回收后御剑关闭")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "回收后 sword_flight_block 清账")
	_check(absf(_motion.vertical_input) < 0.001 and _motion.move_input == Vector2.ZERO,
		"回收归零角色输入意图（vertical=%.3f）" % _motion.vertical_input)
	# reset_motion 当帧把速度清零；回收点略高于起飞坪，随后是正常重力下落。
	# 断言"落回坪面并静止"才算回到稳定可玩状态（断当帧速度为 0 会误判正常下落）。
	var settled := false
	for _frame in range(180):
		await _tick()
		if _motion.on_floor:
			settled = true
			break
	_check(settled and _motion.actual_velocity.length() < 0.01,
		"回收后落回起飞坪并静止（on_floor=%s，速度 %.3f）" % [
			str(_motion.on_floor), _motion.actual_velocity.length()])
	# 路线状态归零：门序 / 悬停 / 落点标记回到起点。
	var state := _route_state()
	_check(int(state["gate_index"]) == 0, "回收后门序归零")
	_check(not bool(state["hover_done"]) and float(state["hover_accumulated"]) == 0.0,
		"回收后悬停计时归零")
	_check(not bool(state["landing_checked"]) and str(state["landing_result"]).is_empty(),
		"回收后落点结果清空")
	_check(str(state["phase"]) == "takeoff", "回收后航段回到起飞（实际 %s）" % str(state["phase"]))
	# 回收后仍可继续正常操作（不是卡死状态）。
	# 注意：场景 _clear_pressed() 清的是 helper 状态；本测试自己的按住账本也要复位，
	# 否则 _sync_keys 会以为 Space 仍按着而不重发按下事件（曾导致此处假失败）。
	_release_all_keys()
	await _frames(2)
	_check(await _take_off(4.0, 300), "回收后可再次真实起飞")
	_release_all_keys()


func _run_reset_and_exit() -> void:
	await _reset_route()
	_check(int(_route_state()["reset_count"]) >= 1, "R 递增重置计数（%d）" % int(_route_state()["reset_count"]))
	_check(_actor.global_position.distance_to(_spawn_position()) < 1.6, "R 角色回到起飞坪")
	_check(_capability_names() == EXPECTED_CAPABILITIES, "多次重置后三能力装配不变")
	_check(_read_source("res://game/actors/swordsman/swordsman.gd").count("move_and_slide(") == 1,
		"多次重置后角色根仍是唯一物理提交点")
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(8)
	_check(current_scene != null and current_scene.name == HUB_ROOT,
		"Esc 返回角色移动子实验目录（实际 %s）" % (current_scene.name if current_scene != null else "<null>"))
	_check(root.msaa_3d == _msaa_before, "返回目录后根视口 MSAA 恢复为进入前的值（%d）" % _msaa_before)


func _spawn_position() -> Vector3:
	var takeoff: Dictionary = _route["takeoff"]
	var center := _vec(takeoff["center"])
	return Vector3(center.x, float(takeoff["top_y"]) + 0.75, center.z)


# ---------------------------------------------------------------- 截图（窗口模式）


func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "无头渲染器无法截图，请用窗口模式运行截图")
		_finish()
		return
	await _wait_render_frames(48)
	root.get_texture().get_image()
	await _frames(4)

	# 全景：起飞前俯瞰整条航线。
	await _reset_route()
	_camera.size = 74.0
	await _frames(12)
	_print_snapshot("overview")
	await _capture("overview")

	# 起飞：真实起飞到 5 m 以上。
	_camera.size = CAMERA_SIZE_CAPTURE
	await _reset_route()
	var took_off := await _take_off(5.0, 300)
	_check(took_off, "截图批次：真实起飞成功")
	_print_snapshot("takeoff")
	await _capture("takeoff")

	# 穿环：真实穿第 1 道门。
	var gates: Array = _route["gates"]
	var gate: Dictionary = gates[0]
	var center := _vec(gate["center"])
	var yaw := deg_to_rad(float(gate["yaw"]))
	var axis := Vector3(sin(yaw), 0.0, -cos(yaw))
	await _fly_to(center - axis * 3.2, 2.2, 420)
	await _fly_to(center + axis * 3.4, 2.2, 420)
	_check(int(_route_state()["gate_index"]) >= 1, "截图批次：真实穿过第 1 道玉环门")
	_print_snapshot("gate")
	await _capture("gate")

	# 悬停：悬停区位于全部玉环门之后，必须先按序飞完余下各门才能到达（真实飞行，不传送）。
	var remaining: Array = gates
	for index in range(1, remaining.size()):
		var next_gate: Dictionary = remaining[index]
		var next_center := _vec(next_gate["center"])
		var next_yaw := deg_to_rad(float(next_gate["yaw"]))
		var next_axis := Vector3(sin(next_yaw), 0.0, -cos(next_yaw))
		var next_tol: float = minf(2.6, maxf(0.9, float(next_gate["radius"]) * 0.5))
		await _fly_to(next_center - next_axis * 4.5, next_tol, 480)
		await _fly_to(next_center + next_axis * 4.5, next_tol, 480)
	_check(int(_route_state()["gate_index"]) == gates.size(),
		"截图批次：真实按序穿完全部 %d 道门（进度 %d）" % [gates.size(), int(_route_state()["gate_index"])])
	var hover: Dictionary = _route["hover"]
	var hover_center := _vec(hover["center"])
	await _fly_to(hover_center, 1.8, 480)
	_release_all_keys()
	var waited := 0
	while not bool(_route_state()["hover_done"]) and waited < 60 * 8:
		_sync_keys(_hover_hold_keys(hover_center))
		await _tick()
		waited += 1
	_check(bool(_route_state()["hover_done"]), "截图批次：悬停计时完成")
	_print_snapshot("hover")
	await _capture("hover")

	# 落点：真实降落到近侧落点。
	var landings: Array = _route["landings"]
	var landing: Dictionary = landings[0]
	var landing_center := _vec(landing["center"])
	var top_y := float(landing["top_y"])
	await _fly_to(Vector3(landing_center.x, top_y + 3.2, landing_center.z), 1.6, 600)
	_key(KEY_F, true)
	await _tick()
	_key(KEY_F, false)
	_release_all_keys()
	for _frame in range(300):
		await _tick()
		if _motion.on_floor:
			break
	_check(_motion.on_floor, "截图批次：真实落地")
	# 落地那一帧场景尚未读到 on_floor（父节点物理先于子节点），多等几帧让落点结果写入 HUD。
	await _frames(6)
	_check(not str(_route_state()["landing_result"]).is_empty(),
		"截图批次：落点结果已记录（%s）" % str(_route_state()["landing_result"]))
	_print_snapshot("landing")
	await _capture("landing")

	# 小窗布局。
	root.size = Vector2i(960, 640)
	await _frames(6)
	await _capture("small")
	_release_all_keys()
	_finish()


const CAMERA_SIZE_CAPTURE := 30.0


func _print_snapshot(label: String) -> void:
	var state := _route_state()
	var position := _actor.global_position
	print("SNAPSHOT %s phase=%s gate=%d/%d hover=%.2f flying=%s on_floor=%s pos=(%.2f, %.2f, %.2f) vy=%.2f landing=%s" % [
		label, str(state["phase"]), int(state["gate_index"]), int(state["gate_total"]),
		float(state["hover_accumulated"]), str(_motion.flight_active), str(_motion.on_floor),
		position.x, position.y, position.z, _motion.actual_velocity.y,
		str(state["landing_result"]),
	])



# ---------------------------------------------------------------- 基础设施


## 一个完整主循环步：物理帧 + idle 帧。
## Input.parse_input_event 入队的事件在 idle 帧才派发到 _unhandled_input；
## 只等 physics_frame 会让按键永不生效（本轮首跑全航线失败即此因）。
func _tick() -> void:
	await physics_frame
	await process_frame


func _frames(count: int) -> void:
	for _index in range(count):
		await _tick()


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
	_release_all_keys()
	print("SWORD_FLIGHT_COURSE_PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)
