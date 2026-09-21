extends SceneTree
## 实机取证：把 v9 人物放进真实移动场景，逐状态截图并记录实时 clip。
##
## 必须走**窗口模式**（无头不出帧，get_image() 拿不到内容），对齐同目录其它 playtest 的
## 截图契约。用法：
##   godot --path src --script res://tests/v9_visual_playtest.gd -- \
##       --capture-prefix=/abs/path/v9                # 截图模式（窗口）
##   godot --headless --path src --script res://tests/v9_visual_playtest.gd
##                                                    # 无头只做状态断言
##
## 覆盖四个状态：idle（待机）、walk（行走）、run（奔跑）、jump（腾空），每个状态都从
## 表现层快照读 current_clip 与 grounded/vertical_speed，确保「画面里看到的」与「读数」同源。

## 用动作工作台而非庭院：工作台把移动/跳跃/御剑全部接到角色公开输入 API
## （press_jump / press_flight_toggle / set_vertical_input），因此四个状态都能真实驱动；
## 庭院只读移动输入，跳不起来也跑不到 run 阈值。
const SCENE := "res://levels/experiments/character_movement/motion_stage.tscn"
const CAPTURE_TIMEOUT_MSEC := 6000

var _failed := 0
var _prefix := ""
var _actor: CharacterBody3D
var _motion: SwordsmanMotionComponent
var _presentation: Node
var _player: AnimationPlayer
var _frame_drawn := false
var _shots: Array[String] = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS %s" % message)
	else:
		_failed += 1
		print("FAIL %s" % message)


func _run() -> void:
	if change_scene_to_file(SCENE) != OK:
		print("FAIL 无法加载 %s" % SCENE)
		quit(1)
		return
	await scene_changed
	await _frames(6)
	_bind()
	_check(_actor != null and _motion != null, "真实移动场景装配完成")
	_check(_presentation != null, "角色挂载 v9 骨骼表现层")
	_check(_player != null, "v9 表现层后可读到 AnimationPlayer")
	if _actor == null or _presentation == null or _player == null:
		_report()
		return

	# 等角色落地稳定，否则起手会是 jump。
	var settle := 0
	while not _motion.on_floor and settle < 180:
		await _frames(1)
		settle += 1
	_check(_motion.on_floor, "角色落地稳定（%d 帧）" % settle)

	# 待机。
	await _capture_state("idle", 12)
	# 行走：真实按键，桌面 `move_input` 由输入层写入，不能直接赋值绕过（直接赋值不改物理）。
	_key(KEY_W, true)
	await _capture_state("walk", 30, false)
	_key(KEY_W, false)
	await _frames(30)

	# 疾行：按住 Shift 必须真正进入 run 档。走速 1.55 / 跑速 3.45 m/s 分别对齐各自 clip 的
	# 自然速度（实测 1.288 / 3.426，见 tools/art/measure_clip_stride.py），因此两档都不再
	# 以夸张的倍速播放。
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	var sprint_frames := 0
	while sprint_frames < 240 and str(_presentation.call("pose_state").get("current_clip", "")) != "run":
		await _frames(1)
		sprint_frames += 1
	await _capture_state("run", 6, false)
	var run_pose: Dictionary = _presentation.call("pose_state")
	_check(str(run_pose.get("current_clip", "")) == "run",
		"W+Shift 进入 run 档（%.2f m/s，用时 %d 帧）" % [
			float(run_pose.get("speed", 0.0)), sprint_frames])
	_check(float(run_pose.get("speed", 0.0)) > CultivatorSkeletonPresentation.RUN_SPEED_MPS,
		"疾行速度越过 run 阈值（%.2f > %.2f）" % [
			float(run_pose.get("speed", 0.0)), CultivatorSkeletonPresentation.RUN_SPEED_MPS])
	# 松开 Shift 必须退回 walk。
	_key(KEY_SHIFT, false)
	var back_frames := 0
	while back_frames < 180 and str(_presentation.call("pose_state").get("current_clip", "")) != "walk":
		await _frames(1)
		back_frames += 1
	_check(str(_presentation.call("pose_state").get("current_clip", "")) == "walk",
		"松开 Shift 退回 walk 档（用时 %d 帧）" % back_frames)
	_key(KEY_W, false)
	await _frames(20)
	# 静立时按 Shift 不得进入 run：疾行只在真有移动输入时生效。
	_key(KEY_SHIFT, true)
	await _frames(20)
	_check(str(_presentation.call("pose_state").get("current_clip", "")) == "idle",
		"静立按 Shift 仍是 idle（不误触发奔跑姿态）")
	_key(KEY_SHIFT, false)
	await _frames(10)

	# 御剑：用真实的 F 键切换，确认 flying 优先于速度分支，同样映射到 idle。
	_key(KEY_F, true)
	_key(KEY_F, false)
	var flight_frames := 0
	while flight_frames < 240 and not bool(_presentation.call("pose_state").get("flying", false)):
		await _frames(1)
		flight_frames += 1
	_key(KEY_W, true)
	await _frames(30)
	await _capture_state("flight", 2, false)
	var flight_pose: Dictionary = _presentation.call("pose_state")
	_check(bool(flight_pose.get("flying", false)), "御剑状态写入公开快照")
	_check(str(flight_pose.get("current_clip", "")) == "idle",
		"御剑映射到 idle@0.6（flying 分支优先于速度分支，实际 %s）"
		% str(flight_pose.get("current_clip", "")))
	_check(float(flight_pose.get("speed", 0.0)) > CultivatorSkeletonPresentation.RUN_SPEED_MPS,
		"御剑速度确实超过 run 阈值（%.2f m/s），证明 run 分支是被 flying 抢先而非速度不足"
		% float(flight_pose.get("speed", 0.0)))
	# 收尾：关御剑、停输入，回地面静止。
	_key(KEY_F, true)
	_key(KEY_F, false)
	_key(KEY_W, false)
	var land_frames := 0
	while land_frames < 300 and (bool(_presentation.call("pose_state").get("flying", false))
			or not bool(_presentation.call("pose_state").get("grounded", true))):
		await _frames(1)
		land_frames += 1
	await _frames(20)

	# 腾空：空格触发跳跃，等到真的离地再截图。
	_key(KEY_SPACE, true)
	await _frames(1)
	_key(KEY_SPACE, false)
	var air_frames := 0
	while air_frames < 120 and bool(_presentation.call("pose_state").get("grounded", true)):
		await _frames(1)
		air_frames += 1
	await _capture_state("jump", 3, false)

	_report()


## 推进若干帧、截图并记录该状态下的实时 clip。
## `release` = true 时先松开全部按键（用于 idle 这类静止态）。
func _capture_state(label: String, frames: int, release: bool = true) -> void:
	if release:
		for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_SPACE]:
			_key(code, false)
	await _frames(frames)
	var pose: Dictionary = _presentation.call("pose_state")
	var clip := str(pose.get("current_clip", "?"))
	var line := "%s: clip=%s grounded=%s vspd=%+.2f phase=%.3f speed=%.2f" % [
		label, clip, pose.get("grounded"), float(pose.get("vertical_speed", 0.0)),
		float(pose.get("phase", 0.0)), float(pose.get("speed", 0.0))]
	print("STATE %s" % line)
	_shots.append(line)
	_check(_player.current_animation == clip,
		"%s：快照 clip 与 AnimationPlayer 实际播放一致（%s vs %s）"
		% [label, clip, _player.current_animation])
	if not _prefix.is_empty():
		await _capture(label)


func _bind() -> void:
	_actor = _find_actor(root)
	if _actor == null:
		return
	_motion = _actor.get_node_or_null("SwordsmanMotionComponent") as SwordsmanMotionComponent
	_presentation = _actor.get_node_or_null("Visual/CultivatorSkeletonPresentation")
	if _presentation == null:
		return
	var players := _actor.find_children("*", "AnimationPlayer", true, false)
	if players.size() == 1:
		_player = players[0] as AnimationPlayer


func _find_actor(node: Node) -> CharacterBody3D:
	if node is CharacterBody3D and node.get_script() != null:
		return node as CharacterBody3D
	for child in node.get_children():
		var found := _find_actor(child)
		if found != null:
			return found
	return null


func _capture(suffix: String) -> void:
	_frame_drawn = false
	RenderingServer.frame_post_draw.connect(_on_frame_drawn, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + CAPTURE_TIMEOUT_MSEC
	while not _frame_drawn and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _frame_drawn:
		_check(false, "等待渲染帧超时，未能截图：%s" % suffix)
		return
	var path := "%s-%s.png" % [_prefix, suffix]
	var error := root.get_texture().get_image().save_png(path)
	_check(error == OK, "渲染截图保存：%s（错误 %d）" % [path, error])


func _on_frame_drawn() -> void:
	_frame_drawn = true


## 真实输入事件：桌面移动由输入层消费，直接写 _motion.move_input 不会走物理。
func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _report() -> void:
	print("\n=== V9 状态轨迹 ===")
	for line in _shots:
		print("  " + line)
	print("V9_VISUAL_PLAYTEST 完成：失败 %d" % _failed)
	quit(0 if _failed == 0 else 1)
