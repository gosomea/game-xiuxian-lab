extends SceneTree
## 剑法工作台真实窗口验收：用 Input.parse_input_event 送鼠标移动、左键、C 与 F，
## 依次比较剑气、飞剑出击、剑阵蓄势与齐射，检查命中、阻塞与表现，并截图。
## 运行：Godot --path src --script res://tests/sword_workbench_playtest.gd -- --capture-prefix=/abs/path/sword
## 依据 notes/implemented/gameplay/2026-10-09-sword-workbench.md。

const SCENE := "res://levels/experiments/sword_combat/sword_workbench.tscn"

var _failed := 0
var _passed := 0
var _prefix := ""
var _scene: Node
var _cast: SwordCastComponent
var _actor: Swordsman


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-prefix="):
			_prefix = arg.trim_prefix("--capture-prefix=")
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("PASS ", label)
	else:
		_failed += 1
		print("FAIL ", label)


func _run() -> void:
	change_scene_to_file(SCENE)
	await scene_changed
	await _frames(30)
	_scene = current_scene
	_actor = _scene.call("actor")
	_cast = _scene.call("cast_component")
	var dummies: Array = _scene.call("dummies")
	var front: TrainingDummy = dummies[0]
	var far: TrainingDummy = dummies[4]
	var presentation := _actor.get_node("SwordCastPresentation") as SwordCastPresentation
	_check(presentation.sword_node().visible, "本命剑可见并悬浮")
	await _capture("idle")

	# 剑气：C 切换顺序从剑气开始；左键朝前方木桩出剑。
	_check(_cast.form == SwordCastComponent.FORM_QI, "默认招式为剑气")
	var hits := int(_scene.call("total_hits"))
	await _aim(front.global_position)
	_click(true)
	await _frames(14)
	_check(_cast.qi_shots.size() == 1, "左键放出一道剑气")
	await _capture("qi")
	_click(false)
	await _frames(40)
	_check(int(_scene.call("total_hits")) > hits, "剑气命中木桩")
	_check(presentation.pose_weight() < 0.5, "出招姿势随后放下")

	# 飞剑：C 切到飞剑，指向远处木桩。
	_key(KEY_C)
	await _frames(2)
	_check(_cast.form == SwordCastComponent.FORM_STRIKE, "C 切换到飞剑")
	hits = int(_scene.call("total_hits"))
	await _aim(far.global_position)
	_click(true)
	await _frames(14)
	_check(_cast.sword_away, "飞剑离开悬浮位")
	_check(presentation.pose_weight() > 0.5, "出招时右臂前指")
	await _capture("strike")
	_key(KEY_F)
	await _frames(3)
	_check(not _actor.motion().flight_active, "飞剑在外时 F 不起飞")
	_click(false)
	for i in range(120):
		await _frames(1)
		if not _cast.sword_away:
			break
	_check(not _cast.sword_away, "飞剑飞回悬浮位")
	_check(int(_scene.call("total_hits")) > hits, "飞剑命中远处木桩")

	# 剑阵：按住蓄势、松开齐射。
	_key(KEY_C)
	await _frames(2)
	_check(_cast.form == SwordCastComponent.FORM_ARRAY, "C 切换到剑阵")
	hits = int(_scene.call("total_hits"))
	await _aim(front.global_position)
	_click(true)
	for i in range(70):
		await _aim(front.global_position)
	_check(_cast.array_swords.size() >= 20, "按住蓄势，身后悬停 %d 把剑" % _cast.array_swords.size())
	await _capture("array_hold")
	_click(false)
	await _frames(14)
	await _capture("array_volley")
	for i in range(240):
		await _frames(1)
		if _cast.array_swords.is_empty():
			break
	_check(int(_scene.call("total_hits")) > hits, "剑阵齐射命中木桩（%d 次）" % (int(_scene.call("total_hits")) - hits))
	_check(_cast.array_swords.is_empty(), "齐射结束后剑阵消散")

	# 御剑时仍可放剑气。
	_scene.call("select_form", SwordCastComponent.FORM_QI)
	await _frames(2)
	_key(KEY_F)
	await _frames(20)
	_check(_actor.motion().flight_active, "飞剑在悬浮位时可以御剑")
	var casts := _cast.casts_total
	await _aim(front.global_position)
	_click(true)
	await _frames(4)
	_click(false)
	_check(_cast.casts_total == casts + 1, "御剑时可以放剑气")
	await _capture("flight_qi")
	_key(KEY_F)
	await _frames(60)

	_check(TimeKeeper.request_count() == 0, "顿帧请求全部释放")
	print("SUMMARY passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed else 0)


func _aim(point: Vector3) -> void:
	var camera := root.get_viewport().get_camera_3d()
	var event := InputEventMouseMotion.new()
	event.position = camera.unproject_position(Vector3(point.x, 0.0, point.z))
	event.global_position = event.position
	Input.parse_input_event(event)
	await _frames(1)


func _click(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	var camera := root.get_viewport().get_camera_3d()
	event.position = camera.unproject_position(_cast.aim_point)
	event.global_position = event.position
	Input.parse_input_event(event)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)


func _capture(label: String) -> void:
	print("STATE %s form=%s hits=%d qi=%d array=%d away=%s" % [label, _cast.form,
		int(_scene.call("total_hits")), _cast.qi_shots.size(), _cast.array_swords.size(), _cast.sword_away])
	if _prefix.is_empty():
		return
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(_prefix + "-" + label + ".png")
	_check(result == OK, "capture " + label)


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame
		await process_frame
