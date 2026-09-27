extends SceneTree

## 独立步行来源实验：验证三个候选共用场景和速度，并在窗口模式留图。

const SCENE := "res://levels/experiments/character_movement/walk_source_comparison.tscn"
const EXPECTED_CLIPS: Array[String] = ["walk", "walk_kaykit", "walk_cmu"]
var _capture_prefix := ""
var _failed := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_capture_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	if change_scene_to_file(SCENE) != OK:
		_check(false, "步行来源实验场景可加载")
		_finish()
		return
	await scene_changed
	await _frames(10)
	var stage := current_scene
	_check(stage != null, "独立场景已运行")
	for index in range(EXPECTED_CLIPS.size()):
		stage.select_candidate(index)
		# 超过三种 clip 的单周期，确认长时间移动时不会定格。
		await create_timer(1.5).timeout
		await _frames(2)
		_check(stage.active_candidate() == index and stage.active_clip() == EXPECTED_CLIPS[index],
			"候选 %d 绑定正确 clip" % index)
		var visual := stage.get_node("候选人物") as Node3D
		var players: Array[Node] = visual.find_children("*", "AnimationPlayer", true, false)
		_check(players.size() == 1, "候选 %d 恰有一个动作播放器" % index)
		if players.size() == 1:
			_check((players[0] as AnimationPlayer).is_playing(), "候选 %d 正在播放" % index)
		_check(visual.position.x > -0.7, "候选 %d 以游戏速度推进" % index)
		if not _capture_prefix.is_empty():
			await _capture("candidate-%d" % index)
	_finish()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "截图需要窗口模式")
		return
	await _frames(5)
	var path := "%s-%s.png" % [_capture_prefix, suffix]
	var image := root.get_texture().get_image()
	_check(image != null and image.get_width() > 0 and image.save_png(path) == OK,
		"截图 %s" % path)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failed += 1
		push_error("FAIL " + label)


func _finish() -> void:
	print("步行来源实验验收：%s" % ("PASS" if _failed == 0 else "FAIL %d" % _failed))
	quit(0 if _failed == 0 else 1)
