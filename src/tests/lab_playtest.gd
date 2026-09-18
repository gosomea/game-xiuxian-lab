extends SceneTree

## 实际渲染与输入验收。自定义 SceneTree 延迟到初始化完成后才加载场景，
## 并显式检查 is_inside_tree；不替代 test_runner 的主场景模式单元测试。
## godot --path src --script res://tests/lab_playtest.gd -- --capture-prefix=/absolute/path/prefix

var _failed := 0
var _prefix := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	if change_scene_to_file("res://levels/lab_hub.tscn") != OK:
		quit(1)
		return
	await scene_changed
	await _settle()
	_check(current_scene.is_inside_tree(), "实验目录已进入真实场景树")
	_check(current_scene.get_node("%ModuleGrid").get_child_count() == 8, "八个计划模块可见")
	_check(current_scene.get_node("%LaunchButton").disabled, "待探索模块不能启动")
	await _capture("hub-1280x800")
	await _activate(current_scene.get_node("%ModuleGrid/Module_sword_combat"))
	_check(current_scene.get_node("%DetailTitle").text == "剑法战斗", "键盘激活模块后详情更新")
	_check("角色移动" in current_scene.get_node("%DetailDependencies").text, "组合依赖展示真实模块名")
	_check(current_scene.get_node("%LaunchButton").disabled, "剑法待设计，不提供运行入口")
	root.size = Vector2i(960, 640)
	await _settle()
	await _capture("hub-960x640")
	root.size = Vector2i(1280, 800)
	await _settle()
	await _activate(current_scene.get_node("%StageButton"))
	await _settle()
	if not _check(current_scene.name == "EmptyStage", "从入口进入空白工作台"):
		quit(1)
		return
	var camera: Camera3D = current_scene.get_node("%Camera3D")
	_check(camera.current and camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "正交俯视相机已激活")
	await _capture("empty-stage")
	var original_size := camera.size
	var scroll := InputEventMouseButton.new()
	scroll.button_index = MOUSE_BUTTON_WHEEL_UP
	scroll.position = Vector2(640, 400)
	scroll.pressed = true
	Input.parse_input_event(scroll)
	await _settle()
	_check(camera.size < original_size, "滚轮改变工作台视野")
	await _press_key(KEY_R)
	_check(is_equal_approx(camera.size, original_size), "R 重置视野")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_check(current_scene.name == "LabHub", "Esc 返回实验目录")
	_check(current_scene.get_node("%LaunchButton").disabled, "返回后模块仍为真实计划状态")
	await _activate(current_scene.get_node("%StageButton"))
	await _settle()
	await _activate(current_scene.get_node("%ReturnButton"))
	await _settle()
	_check(current_scene.name == "LabHub", "工作台返回按钮正常")
	print("PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)


func _activate(button: Button) -> void:
	button.grab_focus()
	await _press_key(KEY_ENTER)


func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()


func _settle() -> void:
	for index in range(5):
		await process_frame


func _capture(suffix: String) -> void:
	if _prefix.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "%s-%s.png" % [_prefix, suffix]
	_check(root.get_texture().get_image().save_png(path) == OK, "截图保存：" + suffix)


func _check(ok: bool, message: String) -> bool:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failed += 1
	return ok
