extends RefCounted

## 动作预览（S2 P0）专项单元测试：纯状态机行为 + 真实展示实例的姿态/时钟行为。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md「动作工作台与动作库（S2）」。
## 断言纪律：
## - 只经公开 API（state() / advance / step_once / select_action / preview_snapshot）驱动；
## - 不访问 _legs / _arms 等私有字段，不镜像实现常量去凑绿；
## - 暂停 / 单步 / 倍率 / 帧率一致 / 循环回卷 / 切换连续性都断言**可观察量**：
##   local_time、consumed_delta、clock、phase、gait、过渡进度与动作 id。

const MotionPreviewState := preload("res://game/systems/motion_preview/motion_preview_state.gd")
const MotionPreviewDisplay := preload("res://game/systems/motion_preview/motion_preview_display.gd")
const MotionPreviewAction := preload("res://game/systems/motion_preview/motion_preview_action.gd")
const MotionPreviewParams := preload("res://game/systems/motion_preview/motion_preview_params.gd")


static func run(t) -> void:
	t.begin_case()
	_assert_library(t)
	t.begin_case()
	_assert_profiles(t)
	t.begin_case()
	_assert_loop_boundary_consistency(t)
	t.begin_case()
	_assert_params_injection(t)
	t.begin_case()
	_assert_vertical_travel(t)
	t.begin_case()
	_assert_initial_aim(t)
	t.begin_case()
	_assert_jump_full_playback(t)
	t.begin_case()
	_assert_jump_default_unchanged(t)
	t.begin_case()
	_assert_clock_contract(t)
	t.begin_case()
	_assert_rate_contract(t)
	t.begin_case()
	_assert_loop_and_stop(t)
	t.begin_case()
	_assert_transition_from_current(t)
	t.begin_case()
	_assert_display_pose(t)


# --- 动作库 -----------------------------------------------------------------


static func _assert_library(t) -> void:
	var actions := MotionPreviewAction.library()
	var ids := PackedStringArray()
	for action in actions:
		ids.append(str(action.id))
	t.assert_true(actions.size() >= 6, "动作库至少 6 条（实际 %d）" % actions.size())
	for expected in ["idle", "walk", "run", "start_stop", "jump", "flight"]:
		t.assert_true(ids.has(expected), "动作库包含 %s（实际 %s）" % [expected, ids])
	var walk := MotionPreviewAction.find(actions, "walk")
	t.assert_true(walk != null and walk.source == MotionPreviewAction.SOURCE_PROGRAM,
		"当前动作来源如实标注为程序近似（不是骨骼 clip）")
	var flight := MotionPreviewAction.find(actions, "flight")
	t.assert_true(flight != null and flight.flying and flight.shows_sword,
		"御剑动作要求飞行状态与飞剑视觉")


# --- 剖面采样：动作必须真的随相位变化 ---------------------------------------


## 每个动作在其描述的关键相位上，采样值必须与 note 描述一致。
## 这是「不是空壳」的核心判据：不是 assert 动作名存在，而是 assert 姿态数据真的在动。
static func _assert_profiles(t) -> void:
	var actions := MotionPreviewAction.library()
	# 剖面采样统一使用契约默认参数（本段验证"随相位变化"，参数注入由专门用例覆盖）。
	var profile_params := MotionPreviewParams.new()

	# 起步 / 停下：速度先升后归零，相位 0 与 1 严格为 0。
	var start_stop := MotionPreviewAction.find(actions, "start_stop")
	t.assert_true(start_stop != null and start_stop.profile == MotionPreviewAction.PROFILE_START_STOP,
		"start_stop 使用随相位变化的剖面（不是静态常量）")
	var s0 := start_stop.sample(0.0, profile_params)
	var s15 := start_stop.sample(0.15, profile_params)
	var s50 := start_stop.sample(0.5, profile_params)
	var s90 := start_stop.sample(0.9, profile_params)
	var s100 := start_stop.sample(1.0, profile_params)
	t.assert_true(is_zero_approx(float(s0.get("speed_factor", 1.0))), "起步相位 0 速度从 0 开始（%.3f）" % float(s0.get("speed_factor", 0.0)))
	t.assert_true(float(s15.get("speed_factor", 0.0)) > 0.0 and float(s15.get("speed_factor", 0.0)) < float(s50.get("speed_factor", 0.0)),
		"起步途中速度介于 0 与巡航之间（%.3f）" % float(s15.get("speed_factor", 0.0)))
	t.assert_true(absf(float(s50.get("speed_factor", 0.0)) - start_stop.speed_factor) < 0.0001,
		"中段保持巡航速度（%.3f）" % float(s50.get("speed_factor", 0.0)))
	t.assert_true(float(s90.get("speed_factor", 0.0)) < float(s50.get("speed_factor", 0.0)) and float(s90.get("speed_factor", 0.0)) > 0.0,
		"停下段速度向 0 回落（%.3f）" % float(s90.get("speed_factor", 0.0)))
	t.assert_true(is_zero_approx(float(s100.get("speed_factor", 1.0))), "停下相位 1 速度归 0（%.3f）" % float(s100.get("speed_factor", 0.0)))

	# 跳跃：竖直速度 正 → 0 → 负 → 落地着地。
	var jump := MotionPreviewAction.find(actions, "jump")
	t.assert_true(jump != null and jump.profile == MotionPreviewAction.PROFILE_JUMP, "jump 使用抛物线剖面")
	# 采样点由注入参数推导（不再是写死常量）：飞行时长的 90% 处仍在空中且竖速为负。
	var j_start := jump.sample(0.0, profile_params)
	var j_peak := jump.sample(
		profile_params.jump_speed / (profile_params.gravity * jump.effective_duration(profile_params)), profile_params)
	var j_fall := jump.sample(
		profile_params.jump_flight_seconds() * 0.9 / jump.effective_duration(profile_params), profile_params)
	var j_end := jump.sample(1.0, profile_params)
	var j_landing := jump.sample(
		profile_params.jump_flight_seconds() / jump.effective_duration(profile_params), profile_params)
	t.assert_true(float(j_start.get("vertical", 0.0)) > 5.0, "起跳竖速为正（%.2f m/s）" % float(j_start.get("vertical", 0.0)))
	t.assert_true(absf(float(j_peak.get("vertical", 99.0))) < 0.01, "顶点竖速为 0（%.3f m/s）" % float(j_peak.get("vertical", 0.0)))
	t.assert_true(float(j_fall.get("vertical", 0.0)) < -1.0, "下落段竖速为负（%.2f m/s）" % float(j_fall.get("vertical", 0.0)))
	t.assert_true(not bool(j_start.get("grounded", true)), "起跳离地")
	t.assert_true(float(j_end.get("vertical", 99.0)) == 0.0 and bool(j_end.get("grounded", false)),
		"落地后着地且竖速归零（%.3f，grounded=%s）" % [float(j_end.get("vertical", 0.0)), str(j_end.get("grounded", false))])

	# 御剑：升 → 悬 → 降 → 悬，全程飞剑可见。
	var flight := MotionPreviewAction.find(actions, "flight")
	t.assert_true(flight != null and flight.profile == MotionPreviewAction.PROFILE_FLIGHT, "flight 使用升/悬/降剖面")
	var f_lift := flight.sample(0.1, profile_params)
	var f_hover := flight.sample(0.35, profile_params)
	var f_sink := flight.sample(0.6, profile_params)
	var f_hover2 := flight.sample(0.85, profile_params)
	t.assert_true(float(f_lift.get("vertical", 0.0)) > 5.0, "御剑起升竖速为正（%.2f m/s）" % float(f_lift.get("vertical", 0.0)))
	t.assert_true(float(f_hover.get("vertical", 99.0)) == 0.0, "悬停段竖速为 0（%.3f）" % float(f_hover.get("vertical", 0.0)))
	t.assert_true(float(f_sink.get("vertical", 0.0)) < -5.0, "下降段竖速为负（%.2f m/s）" % float(f_sink.get("vertical", 0.0)))
	t.assert_true(float(f_hover2.get("vertical", 99.0)) == 0.0, "末段回到悬停（%.3f）" % float(f_hover2.get("vertical", 0.0)))
	for sample_name in ["起升", "悬停", "下降"]:
		var point := flight.sample(0.1 if sample_name == "起升" else (0.35 if sample_name == "悬停" else 0.6), profile_params)
		t.assert_true(bool(point.get("sword", false)) and bool(point.get("flying", false)),
			"御剑%s阶段飞剑可见且处于御剑状态" % sample_name)

	# note 文案必须与剖面一致：描述里提到的阶段名要真的可采样到（防止文案吹牛）。
	t.assert_true(start_stop.note.contains("0 → 巡航 → 0") or start_stop.note.contains("起步"),
		"start_stop 说明描述起步 / 停下过程")
	t.assert_true(jump.note.contains("顶点") and jump.note.contains("落地"), "jump 说明描述顶点与落地")
	t.assert_true(flight.note.contains("升") and flight.note.contains("悬") and flight.note.contains("降"),
		"flight 说明描述升 / 悬 / 降")


# --- 循环边界的帧率一致性 ---------------------------------------------------


## 同一墙钟时长下，30fps 与 60fps 走过循环边界后必须落在同一相位：
## 姿态推进采用回卷余量，而不是把整帧都算在新一圈起点。
static func _assert_loop_boundary_consistency(t) -> void:
	var thirty := MotionPreviewState.new()
	thirty.select("start_stop")
	thirty.playing = true
	var sixty := MotionPreviewState.new()
	sixty.select("start_stop")
	sixty.playing = true
	# 跑满两圈多，一定会跨过多个循环边界。
	for index in range(150):
		thirty.tick(1.0 / 30.0)
	for index in range(300):
		sixty.tick(1.0 / 60.0)
	t.assert_true(absf(thirty.local_time - sixty.local_time) < 0.005,
		"跨多个循环边界后 local_time 一致（%.4f vs %.4f）" % [thirty.local_time, sixty.local_time])
	t.assert_true(absf(thirty.phase() - sixty.phase()) < 0.005,
		"跨多个循环边界后相位一致（%.4f vs %.4f）" % [thirty.phase(), sixty.phase()])
	var thirty_target := thirty.target_state()
	var sixty_target := sixty.target_state()
	t.assert_true(absf(float(thirty_target.get("speed_factor", 0.0)) - float(sixty_target.get("speed_factor", 0.0))) < 0.005,
		"边界后的采样速度一致（%.4f vs %.4f）" % [
			float(thirty_target.get("speed_factor", 0.0)), float(sixty_target.get("speed_factor", 0.0))])


# --- 参数注入：剖面跟随组件参数，不与真实运动分叉 ---------------------------


## 用与默认值不同的参数证明剖面真的读注入值，而不是写死常量。
static func _assert_params_injection(t) -> void:
	var actions := MotionPreviewAction.library()
	var jump := MotionPreviewAction.find(actions, "jump")
	var flight := MotionPreviewAction.find(actions, "flight")

	# 默认参数下是契约值。
	var default_params := MotionPreviewParams.new()
	t.assert_true(is_equal_approx(default_params.jump_speed, 6.0) and is_equal_approx(default_params.gravity, 18.0),
		"默认剖面参数等于 traversal-contract 的组件默认值（%.1f / %.1f）" % [default_params.jump_speed, default_params.gravity])

	# 换成非默认参数：起跳竖速、飞行时长、御剑升降都必须跟着变。
	var custom := MotionPreviewParams.new()
	custom.jump_speed = 9.0
	custom.gravity = 12.0
	custom.lift_speed = 11.0
	custom.sink_speed = 3.5
	custom.move_speed = 7.5

	var custom_jump_start := jump.sample(0.0, custom)
	t.assert_true(absf(float(custom_jump_start.get("vertical", 0.0)) - 9.0) < 0.0001,
		"起跳竖速取注入的 jump_speed（期望 9.0，实际 %.2f）" % float(custom_jump_start.get("vertical", 0.0)))
	var default_jump_start := jump.sample(0.0, default_params)
	t.assert_true(not is_equal_approx(float(custom_jump_start.get("vertical", 0.0)), float(default_jump_start.get("vertical", 0.0))),
		"注入非默认参数后剖面与默认值不同（不是写死常量）")
	t.assert_true(absf(custom.jump_flight_seconds() - 2.0 * 9.0 / 12.0) < 0.0001,
		"飞行时长随注入参数变化（期望 %.3f，实际 %.3f）" % [2.0 * 9.0 / 12.0, custom.jump_flight_seconds()])
	# 顶点相位由注入参数决定：该相位处竖速应为 0。
	var custom_peak := jump.sample(
		custom.jump_speed / (custom.gravity * jump.effective_duration(custom)), custom)
	t.assert_true(absf(float(custom_peak.get("vertical", 99.0))) < 0.01,
		"顶点相位按注入的 jump_speed / gravity 计算，竖速为 0（%.3f）" % float(custom_peak.get("vertical", 0.0)))

	var custom_lift := flight.sample(0.1, custom)
	var custom_sink := flight.sample(0.6, custom)
	t.assert_true(absf(float(custom_lift.get("vertical", 0.0)) - 11.0) < 0.0001,
		"御剑升速取注入的 lift_speed（期望 11.0，实际 %.2f）" % float(custom_lift.get("vertical", 0.0)))
	t.assert_true(absf(float(custom_sink.get("vertical", 0.0)) + 3.5) < 0.0001,
		"御剑降速取注入的 sink_speed（期望 −3.5，实际 %.2f）" % float(custom_sink.get("vertical", 0.0)))

	# 状态机持有参数：从组件注入后 target_state() 走注入值。
	var state := MotionPreviewState.new()
	state.params = custom
	state.select("jump")
	var from_state := state.target_state()
	t.assert_true(absf(float(from_state.get("vertical", 0.0)) - 9.0) < 0.0001,
		"状态机 target_state() 使用注入参数（期望 9.0，实际 %.2f）" % float(from_state.get("vertical", 0.0)))

	# 工作台注入路径：from_motion() 必须逐字段复制组件导出参数（无组件时保持默认）。
	var defaults_only := MotionPreviewParams.from_motion(null)
	t.assert_true(is_equal_approx(defaults_only.jump_speed, 6.0) and is_equal_approx(defaults_only.move_speed, 4.0),
		"无可注入组件时保持契约默认值（jump=%.1f move=%.1f）" % [defaults_only.jump_speed, defaults_only.move_speed])


# --- 跳跃完整播放：时长必须覆盖飞行段，末尾必须真的落地 --------------------


## 复现并锁死"参数调大后动作在落地前结束"的缺陷：
## jump_speed=9 / gravity=12 → 理论飞行 1.5 s。此前动作登记时长固定 1.1 s，
## 播放到末尾时仍在空中（v = −4.2、grounded=false），而 summary 说"落地"。
## 本用例播放整段（非 loop、非单步），断言末尾落地、离地归零、且时长覆盖飞行段。
static func _assert_jump_full_playback(t) -> void:
	var custom := MotionPreviewParams.new()
	custom.jump_speed = 9.0
	custom.gravity = 12.0
	var flight := custom.jump_flight_seconds()
	t.assert_true(absf(flight - 1.5) < 0.0001, "自定义参数理论飞行 1.5 s（实际 %.3f）" % flight)

	var jump := MotionPreviewAction.find(MotionPreviewAction.library(), "jump")
	var effective := jump.effective_duration(custom)
	t.assert_true(effective >= flight,
		"有效时长覆盖飞行段（时长 %.3f >= 飞行 %.3f）" % [effective, flight])
	t.assert_true(effective > jump.duration,
		"自定义参数下有效时长超过登记时长（%.3f > %.3f）——时长由参数决定，不是写死" % [effective, jump.duration])

	# 完整非循环播放：一直播到自动停止。
	var display := MotionPreviewDisplay.new()
	display.speed_reference = 4.0
	display.apply_params(custom)
	t.track(display)
	display.reset_preview()
	display.select_action("jump")
	display.state().playing = true
	display.state().looping = false
	var peak := 0.0
	var saw_positive := false
	var saw_negative := false
	var elapsed := 0.0
	var guard := 0
	while display.state().playing and guard < 3000:
		display.advance(1.0 / 60.0)
		elapsed += 1.0 / 60.0
		var snap: Dictionary = display.preview_snapshot()
		var eff: Dictionary = snap.get("effective", {})
		var v := float(eff.get("vertical", 0.0))
		peak = maxf(peak, float(snap.get("offset_y", 0.0)))
		if v > 0.5:
			saw_positive = true
		if v < -0.5:
			saw_negative = true
		guard += 1
	t.assert_true(saw_positive, "播放过程中出现上升段（竖速为正）")
	t.assert_true(saw_negative, "播放过程中出现下落段（竖速为负）")

	# 末尾三条硬断言：落地、竖速归零、离地归零。
	var final_snap: Dictionary = display.preview_snapshot()
	var final_eff: Dictionary = final_snap.get("effective", {})
	t.assert_true(bool(final_eff.get("grounded", false)), "播放结束后着地 groundy=true（实际 %s）" % str(final_eff.get("grounded", false)))
	t.assert_true(is_zero_approx(float(final_eff.get("vertical", 99.0))),
		"播放结束后竖速归零（实际 %.3f）" % float(final_eff.get("vertical", 0.0)))
	t.assert_true(is_zero_approx(float(final_snap.get("offset_y", 99.0))),
		"播放结束后局部离地归零（实际 %.3f）" % float(final_snap.get("offset_y", 0.0)))
	t.assert_true(peak > 1.0, "自定义参数下跳跃峰值更高（%.3f m，理论 %.3f）" % [peak, 9.0 * 9.0 / (2.0 * 12.0)])

	# 时长覆盖：播放到结束的墙钟时间必须 >= 飞行段 + 停留段（不是 1.1 s 就断）。
	t.assert_true(elapsed >= flight,
		"实际播放时长覆盖飞行段（%.3f s >= %.3f s）" % [elapsed, flight])
	t.assert_true(absf(elapsed - display.state().action_duration()) < 0.05,
		"播放总时长与有效时长一致（%.3f vs %.3f）" % [elapsed, display.state().action_duration()])

	# 相位 1.0 处必须已是落地态：时间轴与采样同源，不是靠倍率凑。
	var end_sample: Dictionary = jump.sample(1.0, custom)
	t.assert_true(bool(end_sample.get("grounded", false)) and is_zero_approx(float(end_sample.get("vertical", 99.0))),
		"相位 1.0 采样即落地且竖速为 0（grounded=%s，v=%.3f）" % [
			str(end_sample.get("grounded", false)), float(end_sample.get("vertical", 0.0))])


## 默认参数不得回归：默认 6 / 18 下有效时长仍是原来的 1.1 s 体验。
static func _assert_jump_default_unchanged(t) -> void:
	var defaults := MotionPreviewParams.new()
	var jump := MotionPreviewAction.find(MotionPreviewAction.library(), "jump")
	t.assert_true(is_equal_approx(jump.effective_duration(defaults), jump.duration),
		"默认参数下有效时长等于登记时长 %.2f s（实际 %.4f）——默认体验不变" % [
			jump.duration, jump.effective_duration(defaults)])
	# 默认参数的完整播放仍以落地结束。
	var display := MotionPreviewDisplay.new()
	display.speed_reference = 4.0
	t.track(display)
	display.reset_preview()
	display.select_action("jump")
	display.state().playing = true
	display.state().looping = false
	var guard := 0
	while display.state().playing and guard < 3000:
		display.advance(1.0 / 60.0)
		guard += 1
	var snap: Dictionary = display.preview_snapshot()
	var eff: Dictionary = snap.get("effective", {})
	t.assert_true(bool(eff.get("grounded", false)), "默认参数播放结束后着地")
	t.assert_true(is_zero_approx(float(snap.get("offset_y", 99.0))), "默认参数播放结束后离地归零")
	t.assert_true(absf(display.state().action_duration() - jump.duration) < 0.0001,
		"默认参数下动作时长仍为 %.2f s" % jump.duration)


# --- 预览初始朝向：由注入 aim 决定，reset / 回卷保持它 ----------------------


## 共享预览包不得硬编码场景方向：初始朝向必须来自注入的 aim，
## 且与 actor 的 _face_aim() 同一约定（模型局部 −Z 为正面）。
static func _assert_initial_aim(t) -> void:
	# 默认：aim = −Z → heading 0（独立单测 / 无宿主用法保持原语义）。
	t.assert_true(absf(MotionPreviewDisplay.heading_for_aim(Vector3.FORWARD)) < 0.0001,
		"aim=−Z 时 heading=0（默认语义不变）")
	# +X（动作工作台的 SPAWN_AIM）：模型正面转向 +X。
	var heading_x := MotionPreviewDisplay.heading_for_aim(Vector3.RIGHT)
	var forward_x := Vector3(-sin(heading_x), 0.0, -cos(heading_x))
	t.assert_true(forward_x.dot(Vector3.RIGHT) > 0.9,
		"aim=+X 时预览正面指向 +X（forward=(%.2f, %.2f, %.2f)）" % [forward_x.x, forward_x.y, forward_x.z])
	# 与 actor 公式一致：同一 aim 必须给出同一个 rotation.y。
	t.assert_true(is_equal_approx(heading_x, atan2(-Vector3.RIGHT.x, -Vector3.RIGHT.z)),
		"heading 公式与 actor._face_aim() 一致（%.4f）" % heading_x)
	# 退化输入不产生 NaN。
	t.assert_true(absf(MotionPreviewDisplay.heading_for_aim(Vector3.ZERO)) < 0.0001, "零向量 aim 回退为 0")
	t.assert_true(is_finite(MotionPreviewDisplay.heading_for_aim(Vector3(0.0, 9.0, 0.0))),
		"纯竖直 aim 不产生 NaN")

	# 行为：注入 aim 后实例化，reset 与循环回卷都保持该朝向。
	var display := MotionPreviewDisplay.new()
	display.speed_reference = 4.0
	display.initial_aim = Vector3.RIGHT
	t.track(display)
	var expected := MotionPreviewDisplay.heading_for_aim(Vector3.RIGHT)
	t.assert_true(absf(float(display.preview_snapshot().get("heading", 0.0)) - expected) < 0.0001,
		"实例化后朝向即注入 aim 的朝向（%.4f）" % float(display.preview_snapshot().get("heading", 0.0)))
	t.assert_true(absf(float(display.preview_snapshot().get("initial_heading", 0.0)) - expected) < 0.0001,
		"initial_heading 记录注入值（%.4f）" % float(display.preview_snapshot().get("initial_heading", 0.0)))
	display.reset_preview()
	t.assert_true(absf(float(display.preview_snapshot().get("heading", 0.0)) - expected) < 0.0001,
		"reset_preview 回到注入朝向而不是 0（%.4f）" % float(display.preview_snapshot().get("heading", 0.0)))


# --- 预览局部竖直位移：剖面高度可读，且不写物理 -----------------------------


## 跳跃在预览里必须真的离地再落回；御剑必须真的上升。
## 断言的是展示实例自己的 position.y 与快照 offset_y，与 actor / Component 无关。
static func _assert_vertical_travel(t) -> void:
	var display := MotionPreviewDisplay.new()
	display.speed_reference = 4.0
	t.track(display)
	display.reset_preview()
	var base_y: float = display.position.y

	# 跳跃：飞行段离地（offset_y > 0），落地后回到基准高度。
	display.select_action("jump")
	display.state().playing = true
	display.state().looping = false
	var peak := 0.0
	var guard := 0
	while display.state().playing and guard < 1200:
		display.advance(1.0 / 60.0)
		peak = maxf(peak, float(display.preview_snapshot().get("offset_y", 0.0)))
		guard += 1
	t.assert_true(peak > 0.2, "跳跃预览在飞行段离地（峰值 %.3f m）" % peak)
	t.assert_true(absf(display.position.y - base_y) < 0.001,
		"跳跃落到末尾后回到基准高度（%.4f vs %.4f）" % [display.position.y, base_y])
	t.assert_true(is_zero_approx(float(display.preview_snapshot().get("offset_y", 0.0))),
		"落地后局部竖直位移归零（不跨动作累积）")

	# 御剑：升 / 悬 / 降 —— 上升段必须在悬停段之后被下降抵消，且高度始终 >= 0。
	display.reset_preview()
	display.select_action("flight")
	display.state().playing = true
	display.state().looping = false
	var lift_height := 0.0
	var hover_height := 0.0
	var guard_flight := 0
	while display.state().playing and guard_flight < 2000:
		display.advance(1.0 / 60.0)
		var phase := display.state().phase()
		var offset := float(display.preview_snapshot().get("offset_y", 0.0))
		if phase < 0.20:
			lift_height = maxf(lift_height, offset)
		elif phase >= 0.20 and phase < 0.50:
			hover_height = maxf(hover_height, offset)
		guard_flight += 1
	t.assert_true(lift_height > 0.5, "御剑预览上升段真的升高（峰值 %.3f m）" % lift_height)
	t.assert_true(hover_height >= lift_height - 0.001,
		"升后悬停保持高度不回落（悬停峰值 %.3f >= 上升峰值 %.3f）" % [hover_height, lift_height])
	t.assert_true(display.position.y >= base_y - 0.001, "御剑预览高度不会低于基准（不穿地）")

	# 复位：回基准高度。
	display.reset_preview()
	t.assert_true(absf(display.position.y - base_y) < 0.0001, "reset_preview 回到基准高度（%.4f）" % display.position.y)


# --- 时钟契约：暂停 / 单步 / 真实 delta --------------------------------------


static func _assert_clock_contract(t) -> void:
	var state := MotionPreviewState.new()
	state.select("walk")
	t.assert_true(state.playing == false, "选中动作后默认不自动播放")

	# 暂停：tick 不得推进任何时间量。
	state.tick(0.5)
	t.assert_true(is_zero_approx(state.local_time), "暂停时 tick 不推进 local_time（%.4f）" % state.local_time)
	t.assert_true(is_zero_approx(state.consumed_delta), "暂停时 consumed_delta 为 0（%.4f）" % state.consumed_delta)
	t.assert_true(not state.wrapped_last_tick, "暂停时不会发生循环回卷")

	# 播放使用真实帧 delta，而不是固定 1/30。
	state.playing = true
	state.tick(0.1)
	t.assert_true(absf(state.local_time - 0.1) < 0.0001,
		"播放推进量 = 真实帧 delta（期望 0.1000，实际 %.4f）" % state.local_time)
	t.assert_true(absf(state.consumed_delta - 0.1) < 0.0001,
		"consumed_delta 等于本帧实际推进量（%.4f）" % state.consumed_delta)

	# 单步：与播放状态无关，固定 STEP_SECONDS * rate。
	var before_step := state.local_time
	state.playing = false
	state.step_once()
	var expected_step := MotionPreviewState.STEP_SECONDS * state.rate
	t.assert_true(absf((state.local_time - before_step) - expected_step) < 0.0001,
		"单步恰好推进 STEP_SECONDS × rate（期望 %.4f，实际 %.4f）" % [expected_step, state.local_time - before_step])
	t.assert_true(absf(state.consumed_delta - expected_step) < 0.0001,
		"单步的 consumed_delta 等于这一步的实际推进量（%.4f）" % state.consumed_delta)

	# 零长帧：不推进、不产生回卷。
	var before_zero := state.local_time
	state.playing = true
	state.tick(0.0)
	t.assert_true(is_equal_approx(state.local_time, before_zero), "零长帧不推进 local_time")
	t.assert_true(is_zero_approx(state.consumed_delta), "零长帧 consumed_delta 为 0")


# --- 倍率：只缩放推进量，时钟与姿态同源 ---------------------------------------


static func _assert_rate_contract(t) -> void:
	var full := MotionPreviewState.new()
	full.select("walk")
	full.playing = true
	full.rate = 1.0
	full.tick(0.2)

	var half := MotionPreviewState.new()
	half.select("walk")
	half.playing = true
	half.rate = 0.5
	half.tick(0.2)
	t.assert_true(absf(half.local_time - full.local_time * 0.5) < 0.0001,
		"0.5 倍率下同一帧的推进量是一半（%.4f vs %.4f）" % [half.local_time, full.local_time])

	var quarter := MotionPreviewState.new()
	quarter.select("walk")
	quarter.playing = true
	quarter.rate = 0.25
	quarter.tick(0.2)
	t.assert_true(absf(quarter.local_time - full.local_time * 0.25) < 0.0001,
		"0.25 倍率下同一帧的推进量是四分之一（%.4f）" % quarter.local_time)

	# 帧率一致：30fps 若干帧与 60fps 两倍帧数，同一墙钟时长推进相同。
	var thirty := MotionPreviewState.new()
	thirty.select("run")
	thirty.playing = true
	for index in range(30):
		thirty.tick(1.0 / 30.0)
	var sixty := MotionPreviewState.new()
	sixty.select("run")
	sixty.playing = true
	for index in range(60):
		sixty.tick(1.0 / 60.0)
	t.assert_true(absf(thirty.local_time - sixty.local_time) < 0.002,
		"30fps 与 60fps 在 1 秒墙钟内推进量一致（%.4f vs %.4f）" % [thirty.local_time, sixty.local_time])
	t.assert_true(absf(thirty.transition - sixty.transition) < 0.01,
		"过渡进度同样与帧率无关（%.3f vs %.3f）" % [thirty.transition, sixty.transition])


# --- 循环回卷与非循环末尾 clamp ----------------------------------------------


static func _assert_loop_and_stop(t) -> void:
	var looping := MotionPreviewState.new()
	looping.select("run")
	looping.playing = true
	looping.looping = true
	var duration := looping.current.duration
	var guard := 0
	while not looping.wrapped_last_tick and guard < 1000:
		looping.tick(0.05)
		guard += 1
	t.assert_true(looping.wrapped_last_tick, "循环动作在时长走满后回卷（耗时 %d 帧）" % guard)
	t.assert_true(looping.local_time < duration, "回卷后 local_time 落在 [0, duration)（%.3f）" % looping.local_time)

	var once := MotionPreviewState.new()
	once.select("jump")
	once.playing = true
	once.looping = false
	var guard_once := 0
	while once.playing and guard_once < 1000:
		once.tick(0.05)
		guard_once += 1
	t.assert_true(not once.playing, "非循环动作到达末尾后自动停止")
	t.assert_true(absf(once.local_time - once.current.duration) < 0.0001,
		"非循环动作停在精确末尾（%.4f / %.4f）" % [once.local_time, once.current.duration])
	# 末尾后的 tick 不得再推进或回卷。
	var end_time := once.local_time
	once.tick(0.5)
	t.assert_true(absf(once.local_time - end_time) < 0.0001, "停止后 tick 不再推进 local_time")
	t.assert_true(is_zero_approx(once.consumed_delta), "停止后 consumed_delta 为 0（不会继续推姿态）")

	# 非循环末尾的 clamp：最后一步只吃掉剩余时间，不越界。
	var clamp_state := MotionPreviewState.new()
	clamp_state.select("jump")
	clamp_state.playing = true
	clamp_state.looping = false
	clamp_state.tick(clamp_state.current.duration - 0.01)
	var overshoot := clamp_state.current.duration + 5.0
	clamp_state.tick(overshoot)
	t.assert_true(clamp_state.local_time <= clamp_state.current.duration + 0.0001,
		"超大 delta 被 clamp 到末尾，不越过动作长度（%.4f）" % clamp_state.local_time)


# --- 过渡：A 端来自当前实际状态，切换不清姿态 --------------------------------


static func _assert_transition_from_current(t) -> void:
	var state := MotionPreviewState.new()
	# 先把 run 跑起来，记录它的实际速度系数。
	state.select("run")
	state.playing = true
	state.tick(0.2)
	var run_effective := state.effective_state()
	state.note_effective(run_effective)
	var run_speed := float(run_effective.get("speed", 0.0))
	t.assert_true(run_speed > 0.5, "run 的实际速度系数在高位（%.2f）" % run_speed)

	# 切到 walk：过渡 A 端必须是 run 的实际状态，而不是默认 0。
	var changed := state.select("walk")
	t.assert_true(changed, "select(walk) 返回真表示动作真的切换了")
	t.assert_true(absf(state.transition_from_speed - run_speed) < 0.0001,
		"过渡 A 端采样切换前的实际状态（期望 %.2f，实际 %.2f）" % [run_speed, state.transition_from_speed])
	var blend_start := state.effective_state()
	t.assert_true(absf(float(blend_start.get("speed", 0.0)) - run_speed) < 0.0001,
		"切换瞬间速度不跳到 0：仍等于切换前的值（%.2f）" % float(blend_start.get("speed", 0.0)))

	# 过渡推进后落在新旧之间，最终收敛到目标。
	state.playing = true
	state.tick(MotionPreviewState.TRANSITION_SECONDS * 0.5)
	var mid := state.effective_state()
	t.assert_true(state.is_transitioning(), "过渡中途标记为进行中")
	t.assert_true(float(mid.get("speed", 0.0)) < run_speed, "过渡中途速度向目标靠拢（%.2f）" % float(mid.get("speed", 0.0)))
	state.tick(MotionPreviewState.TRANSITION_SECONDS)
	var settled := state.effective_state()
	t.assert_true(not state.is_transitioning(), "过渡完成后不再标记进行中")
	t.assert_true(absf(float(settled.get("speed", 0.0)) - state.current.speed_factor) < 0.0001,
		"过渡完成后等于目标动作的速度系数（%.2f）" % float(settled.get("speed", 0.0)))

	# 同一动作重复切换幂等：不重置过渡、不回卷时钟。
	var time_before := state.local_time
	var repeated := state.select("walk")
	t.assert_true(not repeated, "重复选择当前动作是幂等的")
	t.assert_true(is_equal_approx(state.local_time, time_before), "幂等切换不回卷 local_time")


# --- 展示实例：暂停逐位不动、循环不累积 ---------------------------------------


static func _assert_display_pose(t) -> void:
	var display := MotionPreviewDisplay.new()
	display.speed_reference = 4.0
	t.track(display)
	# 不 await：本套件必须同步跑完，否则 runner 会在协程挂起期间 cleanup 并释放已登记的节点。
	display.reset_preview()
	display.select_action("walk")
	display.state().playing = true

	# 播放若干帧：clock 与 local_time 同步增长。
	for index in range(20):
		display.advance(1.0 / 60.0)
	var running := display.preview_snapshot()
	var pose_running: Dictionary = running.get("pose", {})
	t.assert_true(float(pose_running.get("clock", 0.0)) > 0.0, "播放时表现层 clock 前进（%.3f）" % float(pose_running.get("clock", 0.0)))
	t.assert_true(absf(float(running.get("local_time", 0.0)) - float(pose_running.get("clock", 0.0))) < 0.02,
		"local_time 与表现层 clock 同步（%.4f vs %.4f）" % [float(running.get("local_time", 0.0)), float(pose_running.get("clock", 0.0))])
	t.assert_true(float(pose_running.get("phase", 0.0)) > 0.0, "行走时步态相位在推进（%.3f）" % float(pose_running.get("phase", 0.0)))

	# 暂停：完整 pose 与 clock 逐位不变。
	display.state().playing = false
	var before_pause := display.preview_snapshot()
	for index in range(30):
		display.advance(1.0 / 60.0)
	var after_pause := display.preview_snapshot()
	t.assert_true(is_equal_approx(float(before_pause.get("local_time", -1.0)), float(after_pause.get("local_time", -2.0))),
		"暂停时 local_time 逐位不变（%.6f）" % float(after_pause.get("local_time", 0.0)))
	t.assert_true(float(after_pause.get("consumed_delta", -1.0)) == 0.0, "暂停时 consumed_delta 为 0")
	t.assert_true(not bool(after_pause.get("advanced_last_frame", true)), "暂停时标记为未推进姿态")
	t.assert_true(_pose_equal(before_pause.get("pose", {}), after_pause.get("pose", {})),
		"暂停 30 帧后完整 pose 快照逐字段相等（clock/phase/gait/四肢/俯仰/起伏）")

	# 单步：恰好一步，clock 前进 STEP_SECONDS * rate，且姿态真的变了。
	var step_before := display.preview_snapshot()
	display.step_once()
	var step_after := display.preview_snapshot()
	var pose_before: Dictionary = step_before.get("pose", {})
	var pose_after: Dictionary = step_after.get("pose", {})
	var expected := MotionPreviewState.STEP_SECONDS * display.state().rate
	t.assert_true(absf(float(step_after.get("local_time", 0.0)) - float(step_before.get("local_time", 0.0)) - expected) < 0.0001,
		"单步推进恰好 STEP_SECONDS × rate（%.4f）" % expected)
	t.assert_true(absf(float(pose_after.get("clock", 0.0)) - float(pose_before.get("clock", 0.0)) - expected) < 0.0001,
		"单步时表现层 clock 同步前进同样一步（不分叉）")
	t.assert_true(not display.state().playing, "单步结束后仍处于暂停（步进可复算）")

	# 循环回卷不累积：跑满一整圈后 clock 与 phase 复位到起点附近。
	display.reset_preview()
	display.select_action("run")
	display.state().playing = true
	display.state().looping = true
	var duration: float = display.state().current.duration
	var elapsed := 0.0
	var saw_wrap := false
	while elapsed < duration + 0.5 and not saw_wrap:
		display.advance(1.0 / 60.0)
		elapsed += 1.0 / 60.0
		saw_wrap = display.state().wrapped_last_tick
	t.assert_true(display.state().local_time < duration, "循环回卷后 local_time 回到一圈之内（%.3f）" % display.state().local_time)
	var wrapped_pose: Dictionary = display.preview_snapshot().get("pose", {})
	t.assert_true(float(wrapped_pose.get("clock", 999.0)) < duration,
		"回卷时表现层 clock 被复位，不跨循环累积（%.3f）" % float(wrapped_pose.get("clock", 0.0)))
	t.assert_true(float(display.state().effective_state().get("speed", 0.0)) > 0.0, "回卷后仍处于跑动动作状态")
	# 飞剑：读取共享御剑表现资源。离散量在过渡中点切换——切换瞬间不得立刻跳变，
	# 过渡过半后才翻转，这是 A-B 连续性的可观察证据。
	display.reset_preview()
	display.state().playing = false
	display.select_action("flight")
	t.assert_true(not display.preview_snapshot().get("sword_visible", true),
		"刚切到御剑时飞剑尚未出现（离散量在过渡中点才翻转，不在切换瞬间跳变）")
	display.state().playing = true
	var guard_sword := 0
	while display.state().is_transitioning() and guard_sword < 600:
		display.advance(1.0 / 60.0)
		guard_sword += 1
	t.assert_true(not display.state().is_transitioning(), "御剑过渡在有限帧内完成（%d 帧）" % guard_sword)
	t.assert_true(display.preview_snapshot().get("sword_visible", false), "过渡完成后御剑预览显示共享飞剑资源")
	display.select_action("walk")
	var guard_hide := 0
	while display.state().is_transitioning() and guard_hide < 600:
		display.advance(1.0 / 60.0)
		guard_hide += 1
	t.assert_true(not display.preview_snapshot().get("sword_visible", true), "切回行走并过渡完成后飞剑隐藏")


## 完整 pose 快照逐字段比较（只比较可观察数值字段，不镜像实现内部状态）。
static func _pose_equal(before: Variant, after: Variant) -> bool:
	var left: Dictionary = before
	var right: Dictionary = after
	if left.size() != right.size():
		return false
	for key in left:
		if not right.has(key):
			return false
		var a: Variant = left[key]
		var b: Variant = right[key]
		if a is float and b is float:
			if not is_equal_approx(a as float, b as float):
				return false
		elif a is Vector3 and b is Vector3:
			if not (a as Vector3).is_equal_approx(b as Vector3):
				return false
		elif a != b:
			return false
	return true
