extends SceneTree

## 独立运行取证，生产场景无截图钩子。实际按键后回读状态，再保存视口。
const SCENE := "res://levels/experiments/character_movement/ink_lakeside_sample.tscn"
var _output := ""
var _shot := "default"
var _small := false
var _failed := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--shot="):
			_shot = argument.trim_prefix("--shot=")
		elif argument == "--small":
			_small = true
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 640) if _small else Vector2i(1280, 800)
	_check(change_scene_to_file("res://levels/experiments/character_movement/movement_lab_hub.tscn") == OK, "加载移动目录")
	await scene_changed
	await _frames(3)
	current_scene.call("activate_entry", "ink_lakeside_sample")
	await scene_changed
	_check(current_scene.scene_file_path == SCENE, "从真实目录进入水墨湖岸")
	await _frames(30)
	var actor := current_scene.find_child("Swordsman", true, false) as Swordsman
	_check(actor.motion().on_floor, "出生点着地")
	if _shot == "close":
		for _i in range(8):
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			Input.parse_input_event(wheel)
			await _frames(1)
	elif _shot == "flight":
		_key(KEY_F, true)
		_key(KEY_F, false)
		await _frames(20)
		_key(KEY_SPACE, true)
		await _frames(40)
		_key(KEY_SPACE, false)
		await _frames(12)
		_check(actor.motion().flight_active and actor.global_position.y > 4, "真实输入御剑升空")
		_check(actor.flight_visual_node().visible, "御剑飞剑显示")
	elif _shot == "jump":
		_key(KEY_SPACE, true)
		_key(KEY_SPACE, false)
		await _frames(4)
		_check(not actor.motion().on_floor and actor.velocity.y > 0, "真实输入起跳")
	elif _shot == "walk":
		_key(KEY_D, true)
		_key(KEY_SHIFT, true)
		await _frames(30)
		_check(absf(Vector2(actor.velocity.x, actor.velocity.z).length() - actor.motion().sprint_speed) < .02, "真实输入疾跑")
	await _frames(30)
	var camera := current_scene.get_node("Camera3D") as Camera3D
	var safe_frame := root.get_visible_rect().grow(-24)
	_check(safe_frame.has_point(camera.unproject_position(actor.global_position)), "取景完整保留人物脚底")
	_check(safe_frame.has_point(camera.unproject_position(actor.global_position + Vector3.UP * 1.8)), "取景完整保留人物头部")
	if not _output.is_empty():
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_check(image != null and not image.is_empty(), "实际视口有渲染像素")
		_check(image.save_png(_output) == OK, "保存截图")
		print("CAPTURE %s %dx%d" % [_output, image.get_width(), image.get_height()])
	print("RENDER draw_calls=%d primitives=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("VIEW size=%.1f actor=%s" % [current_scene.rig().snapshot()["zoom_size"], actor.global_position])
	_key(KEY_D, false)
	_key(KEY_SHIFT, false)
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(10)
	_check(current_scene.scene_file_path.ends_with("movement_lab_hub.tscn"), "Esc 返回移动目录")
	current_scene.queue_free()
	current_scene = null
	await _frames(3)
	quit.call_deferred(1 if _failed else 0)


func _frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failed = true
