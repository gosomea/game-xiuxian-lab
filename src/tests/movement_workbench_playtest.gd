extends SceneTree

## 真实窗口输入验收，隔离保存文件；所有图为实际游戏视口输出。
const WORKBENCH := "res://levels/experiments/character_movement/movement_workbench.tscn"
const GARDEN := "res://levels/experiments/character_movement/movement_garden.tscn"
var _failed := 0
var _passed := 0
var _prefix := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()


func _run() -> void:
	LabDefaults.reset_test_state()
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.gui_embed_subwindows = true
	change_scene_to_file(WORKBENCH)
	await scene_changed
	await _settle(20)
	var scene := current_scene
	var actor := scene.actor() as Swordsman
	_check(actor.motion().on_floor, "角色真实着地")
	await _capture("initial-1280x800")
	var sprint := scene.editor("SwordsmanMotionComponent", "sprint_speed") as SpinBox
	await _type_number(sprint, "6.5")
	_check(is_equal_approx(actor.motion().sprint_speed, 6.5), "键盘编辑疾跑速度实时应用")
	await _key(KEY_SHIFT, true)
	await _key(KEY_D, true)
	await _settle(8)
	_check(absf(Vector2(actor.velocity.x, actor.velocity.z).length() - 6.5) < 0.02,
		"真实 Shift+D 达到 6.5 m/s")
	await _key(KEY_D, false)
	await _key(KEY_SHIFT, false)
	scene.reset_actor()
	await _settle(12)
	await _click(scene.editor("", "jump"))
	_check(actor.capability_manager().get_node_or_null("Jump") == null, "鼠标卸下跳跃节点")
	await _tap(KEY_SPACE)
	_check(actor.position.y < 0.3, "卸载后真实 Space 不再起跳")
	await _click(scene.editor("", "jump"))
	await _tap(KEY_SPACE)
	_check(actor.position.y > 0.3, "恢复后真实 Space 可以起跳")
	await _settle(65)
	await _tap(KEY_F)
	await _settle(20)
	_check(actor.motion().flight_active, "真实 F 进入御剑")
	var flight := actor.capability_manager().get_node("SwordFlight")
	await _click(scene.editor("", "jump"))
	_check(actor.motion().flight_active and actor.capability_manager().get_node("SwordFlight") == flight,
		"御剑中撤销跳跃保留原御剑与状态")
	await _capture("jump-unloaded-flight")
	await _click(scene.editor("", "flight"))
	_check(not actor.motion().flight_active and actor.flight_visual_node() == null,
		"鼠标卸下御剑清理状态与视觉")
	await _settle(30)
	_check(actor.velocity.y < 0.0 or actor.motion().on_floor, "卸下御剑后重力恢复")
	await _click(scene.editor("", "flight"))
	await _click(scene.editor("", "jump"))
	scene.reset_actor()
	await _settle(12)
	# 切换真实 Tab 控件，再由键盘操作 OptionButton 弹出菜单。
	var tabs := scene.get("_tabs") as TabContainer
	var bar := tabs.get_tab_bar()
	await _click_at(bar.global_position + bar.get_tab_rect(1).get_center())
	_check(tabs.current_tab == 1, "鼠标切到镜头页")
	var mode := scene.editor("camera", "start_mode") as OptionButton
	mode.grab_focus()
	await _tap(KEY_SPACE)
	await _tap(KEY_DOWN)
	await _tap(KEY_ENTER)
	await _resume_play_input()
	await _settle(20)
	_check(scene.rig().component().mode_id == "overview", "真实菜单切换全景镜头")
	await _capture("camera-overview")
	await _click(scene.editor("", "camera"))
	_check(not scene.rig().is_active() and scene.rig().get_node("CapabilityManager").get_child_count() == 0,
		"鼠标卸下镜头模式并停止写入")
	await _click(scene.editor("", "camera"))
	_check(scene.rig().get_node("CapabilityManager").get_child_count() == 4, "鼠标重新装回四镜头模式")
	await _click(scene.save_button)
	_check(not LabDefaults.is_dirty() and FileAccess.file_exists(LabDefaults.storage_path), "鼠标保存为全局默认")
	await _capture("saved-defaults")
	change_scene_to_file(GARDEN)
	await scene_changed
	await _settle(16)
	actor = current_scene.find_child("Swordsman", true, false) as Swordsman
	var rig := current_scene.find_child("CameraRig", true, false) as CameraRig
	_check(is_equal_approx(actor.motion().sprint_speed, 6.5), "切换庭院继承已保存疾跑")
	_check(rig.component().mode_id == "overview", "切换庭院继承默认镜头")
	await _capture("garden-inherits")
	change_scene_to_file(WORKBENCH)
	await scene_changed
	await _settle(12)
	scene = current_scene
	root.size = Vector2i(960, 600)
	root.content_scale_size = Vector2i(960, 600)
	await _settle(12)
	tabs = scene.get("_tabs") as TabContainer
	bar = tabs.get_tab_bar()
	await _click_at(bar.global_position + bar.get_tab_rect(0).get_center())
	_check(scene.save_button.get_global_rect().end.y <= 600 and scene.return_button.get_global_rect().end.y <= 600,
		"960×600 保存与返回按钮在画布内")
	var panel := tabs.get_child(0) as ScrollContainer
	panel.scroll_vertical = 10000
	await _settle(6)
	_check(panel.scroll_vertical > 0, "小窗口参数页可真实滚动")
	await _capture("small-960x600")
	await _click_at(bar.global_position + bar.get_tab_rect(1).get_center())
	_check(tabs.get_global_rect().end.x <= 421, "小窗口镜头参数没有撑宽侧栏")
	await _capture("camera-small-960x600")
	await _click(scene.restore_button)
	_check(is_equal_approx(scene.actor().motion().sprint_speed, 4.2) and not LabDefaults.is_dirty(),
		"恢复原始默认按钮还原并保存")
	await _click(scene.return_button)
	await _settle(8)
	_check(current_scene.scene_file_path.ends_with("movement_lab_hub.tscn"), "返回按钮进入移动目录")
	DirAccess.remove_absolute(LabDefaults.storage_path)
	print("WORKBENCH PLAYTEST 通过 %d / 失败 %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _type_number(spin: SpinBox, value: String) -> void:
	var line := spin.get_line_edit()
	line.grab_focus()
	await create_timer(0.3).timeout
	# macOS 输入法焦点更新异步发生；逐键留间隔，必要时完整重输入一次。
	for attempt in range(2):
		line.select_all()
		for character in value:
			var event := InputEventKey.new()
			event.pressed = true
			event.unicode = character.unicode_at(0)
			event.keycode = character.unicode_at(0)
			event.physical_keycode = event.keycode
			Input.parse_input_event(event)
			await create_timer(0.08).timeout
			event = event.duplicate()
			event.pressed = false
			Input.parse_input_event(event)
			await create_timer(0.04).timeout
		if line.text == value:
			break
	print("EDITOR INPUT text=%s focus=%s" % [line.text, line.has_focus()])
	await _tap(KEY_ENTER)
	print("EDITOR COMMIT value=%s text=%s" % [spin.value, line.text])
	await _resume_play_input()
	_check(root.gui_get_focus_owner() == null, "编辑后点击预览区域释放输入焦点")


func _click(control: Control) -> void:
	control.grab_focus()
	await _settle(3)
	await _click_at(control.get_global_rect().get_center())
	await _resume_play_input()


func _click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await _settle(4)


func _resume_play_input() -> void:
	await _click_at(Vector2(root.content_scale_size.x - 90.0, 100.0))


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await physics_frame
	await process_frame


func _tap(code: Key) -> void:
	await _key(code, true)
	await _key(code, false)
	await _settle(4)


func _settle(frames: int) -> void:
	for _index in range(frames):
		await physics_frame
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
	print("%s %s" % ["PASS" if condition else "FAIL", message])


func _capture(suffix: String) -> void:
	if _prefix.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var path := "%s-%s.png" % [_prefix, suffix]
	_check(shot.save_png(path) == OK, "截图 %s %d×%d" % [suffix, shot.get_width(), shot.get_height()])
