extends SceneTree
## 实机验收：三个手工摆出的修仙姿态在真实场景中可用且可见。
##
## 这三个状态（负手而立 / 盘腿打坐 / 御剑而立）是库中没有、在本骨架上手工制作的
## （tools/art/author_cultivator_pose.py）。本用例如实驱动真实场景，逐个切换、截图，
## 并断言表现层快照与 AnimationPlayer 实际播放一致——不靠孤立资源自证。
##
## 必须窗口模式跑截图（无头不出帧）：
##   godot --path src --script res://tests/v9_authored_state_playtest.gd -- ##       --capture-prefix=/abs/path/v9
## 无头只跑状态断言：
##   godot --headless --path src --script res://tests/v9_authored_state_playtest.gd
##
## 资产里若没有这些 clip（旧的四段版本），本用例打印 SKIP 而不是失败——
## 它们是增量状态，不是核心契约。
const SCENE := "res://levels/experiments/character_movement/motion_stage.tscn"
const CAP := 12000
var _prefix := ""
var _actor: CharacterBody3D
var _pres: Node
var _drawn := false
var _fails := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-prefix="): _prefix = a.trim_prefix("--capture-prefix=")
	_run.call_deferred()

func _check(ok: bool, msg: String) -> void:
	if ok: print("PASS %s" % msg)
	else: _fails += 1; print("FAIL %s" % msg)

func _run() -> void:
	change_scene_to_file(SCENE)
	await scene_changed
	await _frames(8)
	_actor = _find(root)
	_pres = _actor.get_node_or_null("Visual/CultivatorSkeletonPresentation")
	_check(_pres != null, "场景装配 v9 表现层")
	if _pres == null: _report(); return
	for clip in ["idle_guarded", "meditate", "sword_ride"]:
		if not _pres.call("has_state", clip):
			print("SKIP %s 不在资产中" % clip); continue
		_check(bool(_pres.call("play_state", clip)), "play_state(%s) 成功" % clip)
		await _frames(10)
		var pose: Dictionary = _pres.call("pose_state")
		_check(str(pose.get("current_clip")) == clip, "%s 生效（实际 %s）" % [clip, pose.get("current_clip")])
		if not _prefix.is_empty():
			await _capture(clip)
		_pres.call("release_state")
		await _frames(4)
	# 真实飞行：按 F 切御剑，断言表现层自动选 sword_ride 且不叠加节点倾斜。
	var model := _actor.get_node_or_null("Visual/CultivatorTripoV9") as Node3D
	_key(KEY_F, true)
	_key(KEY_F, false)
	await _frames(30)
	var fly: Dictionary = _pres.call("pose_state")
	_check(bool(fly.get("flying", false)), "按 F 进入御剑状态")
	if _pres.call("has_state", "sword_ride"):
		_check(str(fly.get("current_clip")) == "sword_ride",
			"御剑时自动选 sword_ride（实际 %s）" % fly.get("current_clip"))
		if model != null:
			_check(absf(model.rotation.x) < 0.01,
				"御剑而立不叠加节点前倾（rotation.x=%.4f）——前倾由姿态自带" % model.rotation.x)
		if not _prefix.is_empty():
			await _capture("sword_ride_flying")
	_key(KEY_F, true)
	_key(KEY_F, false)
	await _frames(20)
	_report()


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _capture(suffix: String) -> void:
	_drawn = false
	RenderingServer.frame_post_draw.connect(func(): _drawn = true, CONNECT_ONE_SHOT)
	# Wait for real draw frames until the deadline. A single `await process_frame` is not
	# enough right after an input-driven state change: the viewport can still be mid-resize
	# or waiting on a physics step, so the connect callback may not fire within one frame.
	var deadline := Time.get_ticks_msec() + CAP
	while not _drawn and Time.get_ticks_msec() < deadline:
		await process_frame
		await process_frame
	if not _drawn: _check(false, "等待渲染帧超时：%s" % suffix); return
	var path := "%s-%s.png" % [_prefix, suffix]
	_check(root.get_texture().get_image().save_png(path) == OK, "截图 %s" % path)

func _frames(n: int) -> void:
	for i in n: await process_frame

func _find(n: Node) -> CharacterBody3D:
	if n is CharacterBody3D and n.get_script() != null: return n
	for c in n.get_children():
		var r := _find(c)
		if r != null: return r
	return null

func _report() -> void:
	print("POSE_SHOT 完成：失败 %d" % _fails)
	quit(0 if _fails == 0 else 1)
