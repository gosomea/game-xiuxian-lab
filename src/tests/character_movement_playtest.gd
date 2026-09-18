extends SceneTree

## 纯移动庭院的无头调用链验收（见 notes/implemented/gameplay/2026-09-18-character-movement-garden.md）。
##
## 输入/物理断言优先 --headless（不依赖桌面窗口焦点，失焦断言可自行通知）；
## 渲染截图单独走窗口模式（--capture-prefix=...），无头渲染不会出帧，因此显式判失败而不是挂死。
##
## 边界：只验证移动、转向、停止、斜向限速、静态碰撞（边界 + 两个障碍）、重置、退出、
## 鼠标不触发攻击、无战斗装配。不验证审美与手感（交使用者）。
##
## 命名说明：Swordsman / SwordsmanMovement / SwordsmanMotionComponent 是已保留的历史命名，
## 与战斗无关；本测试不据此判定战斗装配，只按实际战斗语义（slash/attack/hitbox/damage/weapon 类）
## 与能力数量、输入行为判定。

const SCENE := "res://levels/experiments/character_movement/movement_garden.tscn"
## 顶层入口已改为角色移动子实验目录；本文件直接运行庭院做小场景回归。
const MODULE_ENTRY_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SUBEXPERIMENTS_PATH := "res://data/content/character_movement_subexperiments.json"
const HUB_SCENE := "res://levels/lab_hub.tscn"
const MOVEMENT_HUB_NODE_NAME := "MovementLabHub"
const SWORD_MODULE := "sword_combat"
const MOVE_MODULE := "character_movement"
## 战斗装配只按实际战斗类/节点语义识别；不含 "sword"（角色历史命名，非战斗装配）。
const COMBAT_KEYWORDS := ["slash", "attack", "hitbox", "hurtbox", "damage", "projectile"]
const CAPTURE_TIMEOUT_MSEC := 4000

var _failed := 0
var _prefix := ""
var _actor: CharacterBody3D
var _motion: SwordsmanMotionComponent
var _camera: Camera3D
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
		print("FAIL 无法加载实验场景：%s" % SCENE)
		quit(1)
		return
	await scene_changed
	await _frames(5)
	_bind()
	_check(_actor != null and _motion != null and _camera != null, "真实移动场景装配完成")
	_check(_actor.get_node("Visual/Cultivator").find_children("*", "MeshInstance3D", true, false).size() > 5, "角色实例包含 Blender 导入网格")
	_check(_garden_mesh_count() > 5, "庭院实例包含 Blender 导入网格")
	_check_no_combat_rig()

	if not _prefix.is_empty():
		await _run_capture()
		return

	await _run_input_and_physics()
	await _run_orbit_combined_mode()
	await _run_hub_gate()
	_finish()


func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		# 无头是 dummy 渲染器，永远不会发出 frame_post_draw；截图必须换窗口模式。
		_check(false, "无头渲染器无法截图，请用窗口模式运行截图")
		_finish()
		return
	# 首帧字形尚未上传时截图会丢掉整层 HUD 文字；先有界等待真实渲染帧完成字形预热。
	await _wait_render_frames(48)
	# 首次 GPU 读回仍可能缺字；丢弃预热读回，再取完整帧。
	root.get_texture().get_image()
	await _frames(4)
	# 角色近景：等待跟随收敛后缩放视野（size 16 / 14），不裁掉角色本体。
	await _frames(30)
	_camera.size = 16.0
	await _frames(4)
	await _capture("character-closeup")
	_camera.size = 14.0
	await _frames(4)
	await _capture("character-near")
	_camera.size = 24.0
	await _frames(4)
	await _capture("garden")
	root.size = Vector2i(960, 640)
	await _frames(6)
	await _capture("small")
	_finish()


func _run_input_and_physics() -> void:
	var start := _actor.global_position

	# 方向：D → 相机地面右方；松键 → 停止；A → 相机地面左方；停下保留朝向。
	# 默认组合环绕软跟随目标，角色在屏幕上保持居中，因此断言世界位移沿已发布的地面基，
	# 而不是固定的屏幕像素位移（那是 fixed_follow 软区滞后的产物，不是移动语义）。
	_key(KEY_D, true)
	await _frames(12)
	_key(KEY_D, false)
	await _frames(2)
	var right_delta := _actor.global_position - start
	right_delta.y = 0.0
	_check(right_delta.length() > 0.15 and right_delta.normalized().dot(_motion.camera_right) > 0.95,
		"D 输入产生沿相机地面右方的真实位移 %.2f m（dot %.3f）" % [right_delta.length(), right_delta.normalized().dot(_motion.camera_right)])
	_check(_actor.velocity.length() < 0.01, "松键停止")
	_check(_motion.aim_direction.dot(_motion.camera_right) > 0.95, "角色朝行进方向转向")

	_actor.global_position = start
	await _frames(2)
	_key(KEY_A, true)
	await _frames(12)
	_key(KEY_A, false)
	await _frames(2)
	# 相机随角色跟随，屏幕位移含跟随分量；断言世界位移沿相机左方而非仅看屏幕 x。
	_check(_motion.aim_direction.dot(-_motion.camera_right) > 0.95, "A 输入使角色朝相机左方移动并转向左")
	_check(_motion.actual_velocity.length() < 0.01, "松开 A 后角色停止")

	# 相机地面基：W → 相机前方，S → 相机后方；两键齐按不超速。
	_actor.global_position = start
	await _frames(2)
	_key(KEY_W, true)
	await _frames(3)
	_check(_motion.actual_velocity.dot(_motion.camera_forward) > 3.5, "W 输入对应相机地面前方速度")
	_key(KEY_D, true)
	await _frames(3)
	_check(_actor.velocity.length() <= _motion.move_speed + 0.001, "斜向移动不额外加速")
	_key(KEY_W, false)
	_key(KEY_D, false)
	await _frames(2)
	_key(KEY_S, true)
	await _frames(3)
	_check(_motion.actual_velocity.dot(_motion.camera_forward) < -3.5, "S 输入对应相机地面后方速度")
	_key(KEY_S, false)
	await _frames(2)

	# 停下保留朝向；鼠标移动与左键不改变任何运动状态，也不触发攻击。
	var stopped_facing := _motion.aim_direction
	var stopped_position := _actor.global_position
	var stopped_velocity := _actor.velocity
	var mouse := InputEventMouseMotion.new()
	mouse.position = Vector2(200, 200)
	Input.parse_input_event(mouse)
	var click := InputEventMouseButton.new()
	click.position = Vector2(640, 400)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await _frames(2)
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await _frames(2)
	_check(_motion.aim_direction.is_equal_approx(stopped_facing), "停下保留朝向，鼠标移动和左键不改变角色朝向")
	_check(_actor.global_position.distance_to(stopped_position) < 0.01, "鼠标移动和左键不产生位移")
	_check(_actor.velocity.length() <= stopped_velocity.length() + 0.01, "鼠标移动和左键不产生速度")

	# 静态碰撞：逐个断言命中的碰撞体就是该几何本体，避免"任意碰撞"掩盖某个碰撞体缺失。
	# 东西向专用通道 z=+4：避开两个障碍的真实包围盒（z ∈ [-2,0]），确保先撞到的必须是边界。
	_check_blocked_by(Vector3(0.0, 0.0, 4.0), Vector3(30.0, 0.0, 0.0), "Boundaries/East", "东侧边界阻挡真实角色形状")
	_check_blocked_by(Vector3(0.0, 0.0, 4.0), Vector3(-30.0, 0.0, 0.0), "Boundaries/West", "西侧边界阻挡真实角色形状")
	_check_blocked_by(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 30.0), "Boundaries/South", "南侧边界阻挡真实角色形状")
	_check_blocked_by(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -30.0), "Boundaries/North", "北侧边界阻挡真实角色形状")
	# 障碍 1（-4,0,0）与障碍 2（4,0,-1）：从障碍正面外 2~3 米朝它 sweep，必须命中该障碍本体。
	_check_blocked_by(Vector3(-4.0, 0.0, 3.0), Vector3(0.0, 0.0, -12.0), "Obstacles/Obstacle1", "障碍 1 阻挡真实角色形状")
	_check_blocked_by(Vector3(4.0, 0.0, 2.0), Vector3(0.0, 0.0, -12.0), "Obstacles/Obstacle2", "障碍 2 阻挡真实角色形状")

	# 失焦：清输入、停速。
	_actor.global_position = Vector3(0, 0, 0)
	_key(KEY_D, true)
	await _frames(3)
	current_scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(3)
	_check(_actor.velocity.length() < 0.01, "失焦清除移动输入")
	_key(KEY_D, false)

	# 重置与退出。
	_key(KEY_R, true)
	await _frames(1)
	_key(KEY_R, false)
	await _frames(8)
	_bind()
	_check(_actor.global_position.distance_to(start) < 0.1, "R 重置到初始位置")
	# 返回层级语义：按钮与控制提示文本必须与实际目标（子实验目录）一致，防止漂移。
	var return_button := current_scene.find_child("ReturnButton", true, false) as Button
	_check(return_button != null and return_button.text == "返回子实验目录",
		"庭院返回按钮文本指向子实验目录：%s" % (return_button.text if return_button != null else "<缺失>"))
	# HUD 常显只留一句核心操作；完整按键表（含返回目标）进详情 tooltip，见 set_controls。
	var controls := current_scene.find_child("Hint", true, false) as Label
	_check(controls != null and controls.text.contains("H 详情"),
		"庭院常显提示为一句核心操作：%s" % (controls.text if controls != null else "<缺失>"))
	var toggle := current_scene.find_child("DetailsToggle", true, false) as Button
	_check(toggle != null and toggle.tooltip_text.contains("返回子实验目录"),
		"庭院完整控制说明指向子实验目录：%s" % (toggle.tooltip_text if toggle != null else "<缺失>"))
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(8)
	_check(current_scene != null and current_scene.name == MOVEMENT_HUB_NODE_NAME,
		"Esc 返回角色移动子实验目录（%s）" % (current_scene.name if current_scene != null else "<null>"))
	_check(root.msaa_3d == _msaa_before, "返回目录后根视口 MSAA 恢复为进入场景前的值（%d）" % _msaa_before)
	# 子实验目录的 Esc 再回顶层实验目录（两级返回路径都真实可走）。
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await _frames(8)
	_check(current_scene != null and current_scene.name == "LabHub", "子实验目录 Esc 返回顶层实验目录")


## 第二消费者验收：庭院默认进入组合环绕（orbit），RMB 旋转后相机基与 WASD 地面基一致，
## 组合模式可切回 fixed_follow（旧构图对照），且常显 HUD 完整广告四组输入。
func _run_orbit_combined_mode() -> void:
	# 上一段输入验收结尾会真实返回子实验目录，因此这里重新进入庭院再测第二消费者。
	if change_scene_to_file(SCENE) != OK:
		_check(false, "无法重新加载庭院场景：%s" % SCENE)
		return
	await scene_changed
	await _frames(5)
	_bind()
	var rig := current_scene.get_node_or_null("CameraRig") as CameraRig
	_check(rig != null, "庭院装配共享 CameraRig")
	if rig == null:
		return
	_check(rig.mode_id() == "orbit", "庭院默认进入组合环绕（orbit）")
	var baseline_distance := float(rig.component().distance)

	# 可发现性（庭院自身入口，不镜像 camera_lab 的四词逐项断言）：常显提示写出四组输入
	# 关键项，且可视按钮使用组合环绕命名。
	var hint := current_scene.find_child("Hint", true, false) as Label
	var hint_text := hint.text if hint != null else ""
	var missing := PackedStringArray()
	for keyword in ["WASD", "Q/E", "滚轮", "右键"]:
		if not hint_text.contains(keyword):
			missing.append(keyword)
	_check(missing.is_empty(), "庭院常显提示完整写出四组输入%s（%s）" % ["" if missing.is_empty() else "（缺 %s）" % ",".join(missing), hint_text])
	var button := current_scene.find_child("ModeToggleButton", true, false) as Button
	_check(button != null and button.text.contains("组合环绕"), "庭院提供组合环绕命名的模式切换控件（%s）" % (button.text if button != null else "<缺失>"))

	# 数字键必须仍然不被镜头包抢占（庭院不启用模式选择键）。
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.physical_keycode = KEY_2
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(3)
	_check(rig.mode_id() == "orbit", "庭院不因数字键改变模式（镜头包不抢场景按键）")

	# Q/E 连续偏航：按住 E 多帧连续增大（保留现状，不是离散 90°）。
	var yaw_before_qe := float(rig.snapshot()["yaw_degrees"])
	_key(KEY_E, true)
	await _frames(12)
	_key(KEY_E, false)
	await _frames(2)
	var qe_delta := absf(float(rig.snapshot()["yaw_degrees"]) - yaw_before_qe)
	_check(qe_delta > 5.0, "组合环绕：Q/E 按住连续偏航 %.1f°（非离散一次转）" % qe_delta)
	_key(KEY_Q, true)
	await _frames(6)
	_key(KEY_Q, false)
	await _frames(2)

	# 滚轮缩放：组合模式下仍可缩放（庭院 enable_zoom_keys=false，滚轮不受该开关限制）。
	var zoom_before := float(rig.snapshot()["zoom_size"])
	_press_mouse(MOUSE_BUTTON_WHEEL_UP, true)
	await _frames(3)
	_check(float(rig.snapshot()["zoom_size"]) < zoom_before,
		"组合环绕：滚轮缩放生效（%.1f → %.1f）" % [zoom_before, float(rig.snapshot()["zoom_size"])])

	# RMB 旋转：相机基必须与真实相机一致，且角色 WASD 沿新的相机地面基移动。
	var yaw_before := float(rig.snapshot()["yaw_degrees"])
	_press_mouse(MOUSE_BUTTON_RIGHT, true)
	await _frames(2)
	_check(rig.is_captured(), "组合环绕：RMB 取得捕获")
	_move_mouse(Vector2(-120.0, 0.0))
	await _frames(4)
	_press_mouse(MOUSE_BUTTON_RIGHT, false)
	await _frames(3)
	var yaw_after := float(rig.snapshot()["yaw_degrees"])
	_check(absf(yaw_after - yaw_before) > 1.0, "RMB 拖拽真实旋转相机（%.1f° → %.1f°）" % [yaw_before, yaw_after])

	var right := _ground(_camera.global_transform.basis.x)
	var forward := _ground(-_camera.global_transform.basis.z)
	_check(right.distance_to(rig.right_axis()) < 0.01 and forward.distance_to(rig.forward_axis()) < 0.01,
		"旋转后 rig 地面基与真实相机 basis 一致")

	var start := _actor.global_position
	_key(KEY_W, true)
	await _frames(12)
	_key(KEY_W, false)
	var displacement := _actor.global_position - start
	displacement.y = 0.0
	_check(displacement.length() > 0.15, "组合环绕：W 产生真实位移 %.2f m" % displacement.length())
	_check(displacement.normalized().dot(forward) > 0.95,
		"组合环绕：W 位移沿旋转后的相机地面前方（dot %.3f）" % displacement.normalized().dot(forward))

	# fixed_follow fallback（庭院场景级冒烟；穷尽矩阵在 camera_lab_playtest 与
	# test_camera_rig_executor）：切回后世界区域右键不捕获、不改 mouse mode、不写偏航。
	if button != null:
		button.pressed.emit()
	await _frames(6)
	_check(rig.mode_id() == "fixed_follow", "可切回 fixed_follow（旧构图对照）")
	var mouse_mode_before := Input.get_mouse_mode()
	var fallback_yaw := float(rig.snapshot()["yaw_degrees"])
	_press_mouse(MOUSE_BUTTON_RIGHT, true)
	await _frames(2)
	_move_mouse(Vector2(60.0, 20.0))
	await _frames(3)
	_check(not rig.is_captured() and Input.get_mouse_mode() == mouse_mode_before
		and absf(float(rig.snapshot()["yaw_degrees"]) - fallback_yaw) < 0.01,
		"fixed_follow fallback：不捕获 / 不改 mouse mode / 不写偏航")
	_press_mouse(MOUSE_BUTTON_RIGHT, false)
	await _frames(2)
	_check(not rig.is_captured(), "fixed_follow fallback：右键抬起后仍未捕获")

	var camera_to_actor := _camera.global_position.distance_to(_actor.global_position)
	_check(absf(camera_to_actor - baseline_distance) < 1.5,
		"回固定跟随后相机距离回到配置值（%.2f m vs %.2f m）" % [camera_to_actor, baseline_distance])
	_check(rig.right_axis().distance_to(_ground(_camera.global_transform.basis.x)) < 0.01,
		"回固定跟随后地面基仍与真实相机一致")


func _press_mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(640, 400)
	Input.parse_input_event(event)


func _move_mouse(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	event.position = Vector2(640, 400) + relative
	Input.parse_input_event(event)


func _ground(value: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


## 用真实角色形状向给定方向做一次有界 sweep：必须命中指定路径的碰撞体本体，且在行程内被截断。
## 只断言"发生了碰撞"会掩盖某个碰撞体缺失（例如障碍消失后仍撞上远处边界）。
func _check_blocked_by(from: Vector3, direction: Vector3, collider_path: String, message: String) -> void:
	_actor.global_position = from
	_actor.velocity = Vector3.ZERO
	var hit := _actor.move_and_collide(direction, true)
	if hit == null:
		_check(false, "%s（sweep 未命中任何碰撞体）" % message)
		return
	var expected := current_scene.get_node_or_null(collider_path)
	var actual := hit.get_collider()
	var actual_name := "<null>" if actual == null else str(actual.get_path())
	_check(expected != null and actual == expected and hit.get_travel().length() < direction.length() - 0.01,
		"%s（命中 %s）" % [message, actual_name])


## 目录门禁：本轮真实入口已写入，硬断言角色移动入口有效、剑法保持无入口。
## 本用例必须在顶层实验目录上运行（select_module 是 LabHub 的公开 API）；
## 前面的用例会停在其他场景，因此先真实切回顶层目录再断言。
func _run_hub_gate() -> void:
	if change_scene_to_file(HUB_SCENE) != OK:
		_check(false, "无法切回顶层实验目录：%s" % HUB_SCENE)
		return
	await scene_changed
	await _frames(5)
	var entry := _module_entry(MOVE_MODULE)
	_check(not entry.is_empty(), "实验清单存在角色移动条目")
	_check(str(entry.get("scene", "")) == MODULE_ENTRY_SCENE, "顶层角色移动入口指向子实验目录：%s" % str(entry.get("scene", "")))
	_check(ResourceLoader.exists(SCENE), "庭院回归场景仍可直接加载：%s" % SCENE)
	_check(ResourceLoader.exists(MODULE_ENTRY_SCENE), "子实验目录场景真实可加载")
	_check(LabCatalog.can_open(entry), "角色移动目录通过目录门禁可打开")
	var garden := _subexperiment_entry("movement_garden")
	_check(str(garden.get("scene", "")) == SCENE, "子实验清单登记庭院回归场景：%s" % str(garden.get("scene", "")))
	_check(ResourceLoader.exists(str(garden.get("scene", ""))), "子实验清单场景路径有效")
	current_scene.select_module(MOVE_MODULE)
	_check(current_scene.get_node_or_null("%LaunchButton") == null, "旧「进入实验场景」按钮已移除（2 击直达）")
	_check(ResourceLoader.exists(str(entry.get("scene", ""))), "角色移动模块卡可直接打开的入口场景存在")
	current_scene.select_module(SWORD_MODULE)
	_check(not LabCatalog.can_open(_module_entry(SWORD_MODULE)), "剑法保留待设计且无运行入口")


func _subexperiment_entry(id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SUBEXPERIMENTS_PATH))
	if not parsed is Dictionary:
		return {}
	for value in (parsed as Dictionary).get("subexperiments", []) as Array:
		var entry: Dictionary = value
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func _module_entry(id: String) -> Dictionary:
	var result := LabCatalog.read()
	for value in result.get("modules", []):
		var entry: Dictionary = value
		if entry["id"] == id:
			return entry
	return {}


## 角色子树不得含实际战斗语义节点；Swordsman* 历史命名不计入。
func _check_no_combat_rig() -> void:
	var offenders := PackedStringArray()
	for node in _actor.find_children("*", "", true, false):
		var lower := node.name.to_lower()
		for keyword in COMBAT_KEYWORDS:
			if lower.contains(keyword):
				offenders.append(str(node.get_path()))
				break
	_check(offenders.is_empty(), "角色子树无战斗节点：%s" % ", ".join(offenders))
	# 本轮 actor 已扩为三移动能力；本回归只要求「只有移动能力、无战斗能力」，不锁定数量。
	var manager := _actor.get_node("CapabilityManager")
	var names := PackedStringArray()
	for child in manager.get_children():
		names.append(str(child.get_script().get_global_name()) if child.get_script() != null else str(child.name))
	_check(names.has("SwordsmanMovement"), "角色装配移动能力 SwordsmanMovement（实际 %s）" % str(names))
	_check(manager.get_node_or_null("SwordsmanMovement") != null, "移动能力位于 CapabilityManager 下")


func _garden_mesh_count() -> int:
	var garden := current_scene.get_node_or_null("Garden")
	if garden == null:
		return 0
	return garden.find_children("*", "MeshInstance3D", true, false).size()


func _bind() -> void:
	for child in current_scene.find_children("*", "CharacterBody3D", true, false):
		_actor = child
		break
	_motion = _actor.get_node("SwordsmanMotionComponent")
	_camera = root.get_camera_3d()


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


## 有界等待真实绘制帧：headless/dummy 渲染器下不会发出 frame_post_draw，超时判失败而非挂死。
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


## 有界等待真实渲染帧：用于字体上传等首帧预热，避免截到无文字的画面。
func _wait_render_frames(count: int) -> void:
	var drawn: Array[int] = [0]
	var on_draw := func() -> void: drawn[0] += 1
	RenderingServer.frame_post_draw.connect(on_draw)
	var start := Time.get_ticks_msec()
	var deadline := start + CAPTURE_TIMEOUT_MSEC
	# 字形上传与窗口首次呈现还需要墙钟预热，快速绘制帧不能替代此等待。
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
	print("CHARACTER_MOVEMENT_PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)