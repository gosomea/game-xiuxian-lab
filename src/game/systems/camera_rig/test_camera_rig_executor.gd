extends RefCounted
## test_camera_rig_executor：CameraRig（唯一 executor）的行为测试。
##
## 覆盖：混合起点取真实渲染状态（含焦点迁移，deadzone 离目标切 orbit 不跳）、
## 连续切换不跳、切换清捕获与旧 delta、RMB 仅 orbit / MMB 仅 overview、
## 模式选择键默认关闭（不抢场景按键）、Q/E 按模式消费、透视缩放改 distance、
## 唯一写 Camera3D（其它写者不存在）、focus_offset 取景但速度仍用真实位置。

const CAMERA_SCRIPT := "res://game/systems/camera_rig/camera_rig.gd"
const RIG_SHEET := "res://game/systems/camera_rig/camera_rig_sheet.tscn"


static func run(t) -> void:
	_test_blend_starts_from_real_render_state(t)
	_test_chained_switch_is_continuous(t)
	_test_capture_is_orbit_only_and_released_on_switch(t)
	_test_mmb_is_overview_only(t)
	_test_pan_ends_even_when_release_is_swallowed(t)
	_test_pan_cleared_on_focus_loss_and_mode_switch(t)
	_test_mode_keys_default_off_and_opt_in(t)
	_test_yaw_keys_mode_scoped(t)
	_test_perspective_zoom_changes_distance(t)
	_test_focus_offset_frames_target_but_speed_uses_real_position(t)
	_test_high_altitude_not_flattened_by_clamp(t)
	_test_y_clamp_when_enabled(t)
	_test_only_executor_writes_camera(t)


static func _host(t) -> Dictionary:
	var root := Node3D.new()
	t.track(root)
	var camera := Camera3D.new()
	root.add_child(camera)
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(0.0, 0.0, 0.0)
	var sheet: PackedScene = load(RIG_SHEET)
	var rig := sheet.instantiate() as CameraRig
	root.add_child(rig)
	var config := CameraRigConfig.new()
	config.mode_choices = PackedStringArray(["fixed_follow", "quarter_turn", "orbit", "overview"])
	rig.bind(camera, target, config)
	return {"root": root, "camera": camera, "target": target, "rig": rig, "config": config}


## 混合起点必须是真实渲染状态：deadzone 让焦点停在别处时切 orbit，位置不得跳。
static func _test_blend_starts_from_real_render_state(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var target := scene["target"] as Node3D
	var camera := scene["camera"] as Camera3D
	var config := scene["config"] as CameraRigConfig
	config.transition_time = 0.5
	config.follow_preset = "deadzone"
	rig.bind(camera, target, config)
	rig.process_mode = Node.PROCESS_MODE_DISABLED

	# deadzone：目标走出死区，焦点被拖到别处（焦点与目标分离）。
	rig.advance(0.016)
	target.position = Vector3(30.0, 0.0, 0.0)
	for _index in range(60):
		rig.advance(0.016)
	var before := camera.global_position
	rig.request_mode("orbit")
	rig.advance(0.016)
	var after := camera.global_position
	t.assert_true(before.distance_to(after) < 0.5,
		"切 orbit 首帧相机不跳（位移 %.3f m）" % before.distance_to(after))


## 混合进行中再次切换：以当前实际状态重启混合，仍然连续。
static func _test_chained_switch_is_continuous(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	var config := scene["config"] as CameraRigConfig
	config.transition_time = 0.5
	rig.bind(camera, scene["target"] as Node3D, config)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.advance(0.016)

	rig.request_mode("orbit")
	for _index in range(3):
		rig.advance(0.016)
	var mid := camera.global_position
	rig.request_mode("overview")
	rig.advance(0.016)
	var after := camera.global_position
	t.assert_true(mid.distance_to(after) < 0.5,
		"混合中再次切换仍连续（位移 %.3f m）" % mid.distance_to(after))


static func _test_capture_is_orbit_only_and_released_on_switch(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	rig.bind(camera, scene["target"] as Node3D, scene["config"] as CameraRigConfig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.advance(0.016)

	# fixed_follow 下 RMB 不被消费。
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	t.assert_false(rig.handle_input(rmb), "fixed_follow 下 RMB 不被镜头包消费")
	t.assert_false(rig.is_captured(), "fixed_follow 下不进入捕获")

	# orbit 下 RMB 捕获，切换模式时释放。
	rig.request_mode("orbit")
	rig.advance(0.016)
	t.assert_true(rig.handle_input(rmb), "orbit 下 RMB 被消费")
	t.assert_true(rig.is_captured(), "orbit 下取得捕获")
	rig.request_mode("overview")
	rig.advance(0.016)
	t.assert_false(rig.is_captured(), "切换模式释放捕获（不把光标留给新模式）")


static func _test_mmb_is_overview_only(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	rig.bind(camera, scene["target"] as Node3D, scene["config"] as CameraRigConfig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.advance(0.016)
	var mmb := InputEventMouseButton.new()
	mmb.button_index = MOUSE_BUTTON_MIDDLE
	mmb.pressed = true
	t.assert_false(rig.handle_input(mmb), "fixed_follow 下 MMB 不被消费")

	rig.request_mode("overview")
	rig.advance(0.016)
	t.assert_true(rig.handle_input(mmb), "overview 下 MMB 被消费")
	t.assert_true((rig.component() as CameraRigComponent).pan_active, "MMB 按下进入平移态")
	mmb = mmb.duplicate()
	mmb.pressed = false
	rig.handle_input(mmb)
	t.assert_false((rig.component() as CameraRigComponent).pan_active, "MMB 抬起结束平移")
	t.assert_false(rig.is_captured(), "overview 的 MMB 不进入鼠标捕获（不锁光标）")


## MMB 抬起若被 GUI 消费（脚本收不到 _unhandled_input），平移仍必须结束。
static func _test_pan_ends_even_when_release_is_swallowed(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	rig.bind(camera, scene["target"] as Node3D, scene["config"] as CameraRigConfig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.advance(0.016)
	rig.request_mode("overview")
	rig.advance(0.016)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	t.assert_true(rig.handle_input(down), "overview 下 MMB 开始平移")
	t.assert_true(rig.is_panning(), "平移态已建立")

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_MIDDLE
	up.pressed = false
	# 模拟 GUI 消费：抬起事件只走 _input 兜底路径，不经过 handle_input。
	t.assert_true(rig.handle_drag_end_input(up), "_input 兜底消费 MMB 抬起")
	t.assert_false(rig.is_panning(), "平移结束（即使抬起事件被 GUI 消费）")
	t.assert_eq((rig.component() as CameraRigComponent).pan_delta, Vector2.ZERO, "结束平移清累积像素位移")
	# 结束之后再回 overview：鼠标未按也不得平移。
	rig.request_mode("fixed_follow")
	rig.advance(0.016)
	rig.request_mode("overview")
	rig.advance(0.016)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50.0, 0.0)
	motion.screen_relative = Vector2(50.0, 0.0)
	rig.handle_input(motion)
	rig.advance(0.016)
	var focus_offset := (rig.component() as CameraRigComponent).focus - (rig.component() as CameraRigComponent).target_position
	t.assert_true(focus_offset.length() < 0.001, "重新进入 overview 后未按鼠标不产生平移（%.3f m）" % focus_offset.length())


## 失焦 / 切模式都必须清平移态与累积位移；再次进入 overview 无残留。
static func _test_pan_cleared_on_focus_loss_and_mode_switch(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	rig.bind(camera, scene["target"] as Node3D, scene["config"] as CameraRigConfig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.advance(0.016)
	rig.request_mode("overview")
	rig.advance(0.016)

	# 切模式清平移。
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	rig.handle_input(down)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40.0, 10.0)
	motion.screen_relative = Vector2(40.0, 10.0)
	rig.handle_input(motion)
	t.assert_true(rig.is_panning(), "前置：平移进行中")
	rig.request_mode("orbit")
	rig.advance(0.016)
	t.assert_false(rig.is_panning(), "切模式结束平移")
	t.assert_eq((rig.component() as CameraRigComponent).pan_delta, Vector2.ZERO, "切模式清累积像素位移")

	# 失焦清平移（复用 release_capture 这一生命周期入口）。
	rig.request_mode("overview")
	rig.advance(0.016)
	rig.handle_input(down)
	rig.handle_input(motion)
	t.assert_true(rig.is_panning(), "前置：再次平移中")
	rig.release_capture()
	t.assert_false(rig.is_panning(), "失焦 / 释放路径结束平移")
	t.assert_eq((rig.component() as CameraRigComponent).pan_delta, Vector2.ZERO, "释放路径清累积像素位移")

	# reset 清 recenter 与平移。
	rig.request_recenter()
	t.assert_true((rig.component() as CameraRigComponent).recenter_request, "前置：回中请求已登记")
	rig.reset_state()
	t.assert_false((rig.component() as CameraRigComponent).recenter_request, "reset 清回中请求")
	t.assert_false(rig.is_panning(), "reset 后不处于平移")


static func _test_mode_keys_default_off_and_opt_in(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	var config := scene["config"] as CameraRigConfig
	config.enable_mode_selection_keys = false
	rig.bind(camera, scene["target"] as Node3D, config)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.advance(0.016)

	var key := InputEventKey.new()
	key.physical_keycode = KEY_2
	key.pressed = true
	t.assert_false(rig.handle_input(key), "默认不抢数字模式键（独立场景可留作他用）")
	t.assert_true(rig.mode_id() == "fixed_follow", "默认关闭时按键不切模式")

	config.enable_mode_selection_keys = true
	rig.bind(camera, scene["target"] as Node3D, config)
	rig.advance(0.016)
	t.assert_true(rig.handle_input(key), "lab 显式开启后数字键被消费")
	rig.advance(0.016)
	t.assert_true(rig.mode_id() == "quarter_turn", "开启后 2 键切到 quarter_turn")


static func _test_yaw_keys_mode_scoped(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	rig.bind(camera, scene["target"] as Node3D, scene["config"] as CameraRigConfig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.advance(0.016)
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	t.assert_false(rig.handle_input(q), "fixed_follow 下 Q 不被消费（放行给场景）")

	rig.request_mode("quarter_turn")
	rig.advance(0.016)
	var rig_component := rig.component() as CameraRigComponent
	t.assert_true(rig.handle_input(q), "quarter_turn 下 Q 被消费")
	t.assert_true(absf(rig_component.yaw_step_request) > 0.0, "Q key-down 记一次离散步进")
	var before := rig_component.yaw_step_request
	# 键盘重复事件带 echo=true；这类事件不得再记一步。
	var repeat := q.duplicate()
	repeat.echo = true
	rig.handle_input(repeat)
	t.assert_true(absf(rig_component.yaw_step_request - before) < 0.001, "按住重复事件（echo）不再累加步进")


static func _test_perspective_zoom_changes_distance(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	var config := scene["config"] as CameraRigConfig
	config.projection = Camera3D.PROJECTION_PERSPECTIVE
	config.distance = 20.0
	config.distance_min = 6.0
	config.distance_max = 60.0
	config.distance_step = 1.5
	rig.bind(camera, scene["target"] as Node3D, config)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	t.assert_true(rig.handle_input(wheel), "透视下滚轮被消费")
	rig.advance(0.016)
	var rig_component := rig.component() as CameraRigComponent
	t.assert_true(rig_component.distance < 20.0, "透视滚轮改 distance（%.2f m）" % rig_component.distance)
	t.assert_true(absf(rig_component.size - config.size) < 0.001, "透视下不动正交 size")
	# 限幅
	for _index in range(60):
		rig.adjust_zoom(1.0)
		rig.advance(0.016)
	t.assert_true(rig_component.distance >= config.distance_min - 0.001, "透视缩放被限幅在 distance_min")


static func _test_focus_offset_frames_target_but_speed_uses_real_position(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	var target := scene["target"] as Node3D
	var config := scene["config"] as CameraRigConfig
	config.focus_offset = Vector3(0.0, 1.2, 0.0)
	config.transition_time = 0.0
	config.follow_preset = "hard"
	rig.bind(camera, target, config)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.advance(0.016)
	var rig_component := rig.component() as CameraRigComponent
	t.assert_true(absf(rig_component.target_position.y - 1.2) < 0.001,
		"focus_offset 加进取景目标位置（y=%.2f）" % rig_component.target_position.y)


## 回归：高空御剑时 x/z 夹取不得把焦点 y 压成 0（否则镜头永远看地面）。
static func _test_high_altitude_not_flattened_by_clamp(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	var target := scene["target"] as Node3D
	var config := scene["config"] as CameraRigConfig
	# 开放空域：只夹 x/z，不夹 y（默认）。
	config.focus_clamp_enabled = true
	config.focus_clamp_min = Vector3(-10.0, 0.0, -10.0)
	config.focus_clamp_max = Vector3(10.0, 0.0, 10.0)
	config.transition_time = 0.0
	rig.bind(camera, target, config)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	target.position = Vector3(0.0, 20.0, 0.0)
	rig.advance(0.016)
	var rig_component := rig.component() as CameraRigComponent
	t.assert_true(absf(rig_component.focus.y - 20.0) < 0.001,
		"高空 y=20 不被压成 0（实际 %.2f）" % rig_component.focus.y)

	# x/z 仍被夹取。
	target.position = Vector3(50.0, 20.0, 50.0)
	rig.advance(0.016)
	t.assert_true(absf(rig_component.focus.x - 10.0) < 0.001 and absf(rig_component.focus.z - 10.0) < 0.001,
		"x/z 仍被夹取到边界（%.1f, %.1f）" % [rig_component.focus.x, rig_component.focus.z])
	t.assert_true(absf(rig_component.focus.y - 20.0) < 0.001, "夹取 x/z 时 y 保持 20")


## 显式打开 y 夹取时按 min/max y 生效（庭院地平构图的用法）。
static func _test_y_clamp_when_enabled(t) -> void:
	t.begin_case()
	var scene := _host(t)
	var rig := scene["rig"] as CameraRig
	var camera := scene["camera"] as Camera3D
	var target := scene["target"] as Node3D
	var config := scene["config"] as CameraRigConfig
	config.focus_clamp_enabled = true
	config.focus_clamp_y_enabled = true
	config.focus_clamp_min = Vector3(-10.0, 0.0, -10.0)
	config.focus_clamp_max = Vector3(10.0, 0.0, 10.0)
	config.transition_time = 0.0
	rig.bind(camera, target, config)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	target.position = Vector3(0.0, 20.0, 0.0)
	rig.advance(0.016)
	var rig_component := rig.component() as CameraRigComponent
	t.assert_true(is_zero_approx(rig_component.focus.y), "打开 y 夹取时 y 被压到 max.y=0（地平构图）")

	# 3D bounds 用法：y 在范围内时不被改动。
	config.focus_clamp_min = Vector3(-10.0, 0.0, -10.0)
	config.focus_clamp_max = Vector3(10.0, 40.0, 10.0)
	rig.bind(camera, target, config)
	rig.advance(0.016)
	t.assert_true(absf(rig_component.focus.y - 20.0) < 0.001,
		"3D bounds 下 y=20 在 [0,40] 内保持不变（%.2f）" % rig_component.focus.y)
	target.position = Vector3(0.0, 99.0, 0.0)
	rig.advance(0.016)
	t.assert_true(absf(rig_component.focus.y - 40.0) < 0.001,
		"3D bounds 下超限 y 被夹到 max.y=40（%.2f）" % rig_component.focus.y)


## 唯一写者：executor 之外的包内脚本不得写 Camera3D 姿态。
static func _test_only_executor_writes_camera(t) -> void:
	t.begin_case()
	var source := FileAccess.open(CAMERA_SCRIPT, FileAccess.READ).get_as_text()
	t.assert_true(source.count("global_position =") >= 1, "executor 是相机位置的写入者")
	for path in [
		"res://game/systems/camera_rig/fixed_follow.gd",
		"res://game/systems/camera_rig/quarter_turn.gd",
		"res://game/systems/camera_rig/orbit.gd",
		"res://game/systems/camera_rig/overview.gd",
	]:
		var text := FileAccess.open(path, FileAccess.READ).get_as_text()
		# 模式只写组件数据：不得持有 / 写入 Camera3D。
		t.assert_false(text.contains("_camera.") or text.contains("look_at(") or text.contains("get_camera_3d"),
			"%s 不写相机姿态（只写组件数据）" % path.get_file())