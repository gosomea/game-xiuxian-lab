extends SceneTree

## CLI 窗口实机证据：生产场景无截图/调试定位钩子。
const SCENE := "res://levels/experiments/character_movement/west_lake_sunset.tscn"
var _output := ""
var _shot := "ground"
var _failed := false
var _small := false


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
	root.size = Vector2i(960,640) if _small else Vector2i(1440,900)
	DisplayServer.window_move_to_foreground()
	_check(change_scene_to_file("res://levels/experiments/character_movement/movement_lab_hub.tscn") == OK,"加载移动目录")
	await scene_changed
	await _frames(3)
	current_scene.call("activate_entry","west_lake_sunset")
	await scene_changed
	_check(current_scene.scene_file_path == SCENE,"目录最后一项真实进入西湖")
	await _frames(30)
	var actor := current_scene.find_child("Swordsman",true,false) as Swordsman
	_check(actor.motion().on_floor,"出生实际落地")
	if _shot == "panorama":
		_key(KEY_M,true); _key(KEY_M,false)
	elif _shot == "close":
		for _i in range(3):
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			Input.parse_input_event(wheel)
	elif _shot == "run":
		_key(KEY_D,true); _key(KEY_SHIFT,true)
		await _frames(24)
		_check(absf(Vector2(actor.velocity.x,actor.velocity.z).length()-actor.motion().sprint_speed)<.02,"真实 Shift 疾跑")
	elif _shot == "jump":
		_key(KEY_SPACE,true); _key(KEY_SPACE,false)
		await _frames(5)
		_check(actor.velocity.y>0 and not actor.motion().on_floor,"真实 Space 起跳")
	elif _shot in ["cloud_view","above_view"]:
		_key(KEY_F,true); _key(KEY_F,false)
		await _frames(20)
		actor.global_position.y = 39.0 if _shot == "cloud_view" else 61.0
		current_scene.rig().component().pitch_degrees = 25.0
		print("FRAMING_ONLY 云中/云上定位；真实连续直飞以运行测试和前轮窗口证据为准")
	elif _shot in ["cloud","above"]:
		_key(KEY_F,true); _key(KEY_F,false)
		await _frames(20)
		_key(KEY_SPACE,true)
		await _frames(325 if _shot == "cloud" else 520)
		_key(KEY_SPACE,false)
		_check(actor.motion().flight_active and actor.flight_visual_node().visible,"共享御剑实际直飞")
		_check(actor.global_position.y>48 if _shot=="above" else current_scene.cloud_density(actor.global_position.y)>.8,"越云顶" if _shot=="above" else "进入云中")
		_check(current_scene.rig().snapshot()["focus"].y>32,"镜头跟随穿云高度")
		# Cosmetic framing only after real ascent; camera writes remain in CameraRig.
		current_scene.rig().component().pitch_degrees = 25.0
	elif _shot == "leifeng":
		actor.global_position = Vector3(15,0.5,80)
		current_scene.rig().component().yaw_degrees = 5.0
		current_scene.rig().component().pitch_degrees = 20.0
		current_scene.rig().component().size = 32.0
		print("FRAMING_ONLY 塔前定位，碰撞降落另由运行测试验证")
	if _shot != "jump":
		await _frames(30)
	var camera := current_scene.get_node("Camera3D") as Camera3D
	var safe := root.get_visible_rect().grow(-24)
	_check(safe.has_point(camera.unproject_position(actor.global_position)),"人物脚底在取景内")
	_check(safe.has_point(camera.unproject_position(actor.global_position+Vector3.UP*1.8)),"人物头部在取景内")
	if not _output.is_empty():
		await RenderingServer.frame_post_draw
		var pixels := root.get_texture().get_image()
		_check(pixels!=null and not pixels.is_empty(),"实际窗口像素")
		_check(pixels.save_png(_output)==OK,"保存截图")
	print("VIEW shot=%s actor=%s cloud=%.2f camera=%s mode=%s" % [_shot,actor.global_position,current_scene.cloud_density(actor.global_position.y),camera.global_position,current_scene.rig().mode_id()])
	print("RENDER draw_calls=%d primitives=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	for key in [KEY_D,KEY_SHIFT,KEY_SPACE,KEY_F]:
		_key(key,false)
	_key(KEY_ESCAPE,true); _key(KEY_ESCAPE,false)
	await _frames(10)
	_check(current_scene.scene_file_path.ends_with("movement_lab_hub.tscn"),"Esc 返回移动目录")
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
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL",label])
	if not condition:
		_failed = true
