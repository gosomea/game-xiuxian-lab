extends RefCounted
## 青玉纸白样板的骨骼动作接线回归测试（v9 现役人物）。
##
## 覆盖真实入口而非孤立资源：样板直接实例化 Swordsman，其 Visual 即共享的 v9 视觉，
## 样板**不再**做任何场景侧视觉替换（v7 特例已移除）；ActorAssembly 仍把 FlyingSword
## 装到同一 Visual 下。动作映射只经公开 advance_state()/pose_state() 读写，
## 不访问表现层私有字段。
##
## 依据 notes/implemented/art/2026-09-19-cultivator-tripo-v9-runtime.md。

const SAMPLE_SCENE := "res://levels/experiments/character_movement/jade_paper_sample.tscn"
const EPSILON := 0.0001


static func run(t) -> void:
	t.begin_case()
	var sample := load(SAMPLE_SCENE).instantiate() as Node3D
	t.assert_true(sample != null, "青玉纸白样板可实例化")
	if sample == null:
		return
	t.track(sample)
	var actor := sample.get_node_or_null("Swordsman") as Swordsman
	t.assert_true(actor != null, "样板生成正式 Swordsman")
	if actor == null:
		return
	var visual := actor.get_node_or_null("Visual") as Node3D
	t.assert_true(visual != null, "骨骼视觉保持角色公开节点名 Visual")
	t.assert_true(actor.get_node_or_null("Visual/CultivatorTripoV9") != null,
		"样板正式运行路径装入 v9 人物模型")
	t.assert_true(actor.get_node_or_null("Visual/Cultivator") == null,
		"样板不再保留旧分件模型")
	t.assert_true(actor.get_node_or_null("Visual/CultivatorRigged") == null,
		"样板不加载旧青玉长袍骨骼模型（保留为回退资产，不接入运行时）")
	t.assert_true(actor.get_node_or_null("Visual/CultivatorNeutralYouthV7") == null,
		"样板不再做 v7 场景侧视觉替换（保留为回退资产，不接入运行时）")
	var presentation := actor.get_node_or_null(
		"Visual/CultivatorSkeletonPresentation") as CultivatorSkeletonPresentation
	t.assert_true(presentation != null, "样板装入骨骼表现层")
	t.assert_true(actor.get_node_or_null("Visual/FlyingSword") != null,
		"ActorAssembly 仍把飞剑装到共享 Visual 下")
	if presentation == null:
		return
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	t.assert_eq(players.size(), 1, "骨骼视觉恰好一个 AnimationPlayer")
	if players.size() != 1:
		return
	var animation_player := players[0] as AnimationPlayer
	var skeletons := visual.find_children("*", "Skeleton3D", true, false)
	t.assert_eq(skeletons.size(), 1, "v9 骨骼视觉恰好一个 Skeleton3D")
	for clip in ["idle", "walk", "run", "jump"]:
		t.assert_true(animation_player.has_animation(clip), "骨骼动作库包含 %s" % clip)

	# 导入的 glTF clip 默认 LOOP_NONE；表现层必须把持续动作改成线性循环、jump 保持单次，
	# 否则 idle/walk/run 播完一个周期就停在末帧，而状态快照仍报当前 gait。
	for clip in ["idle", "walk", "run"]:
		t.assert_eq(animation_player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR,
			"%s 为线性循环（否则一个周期后静止）" % clip)
	t.assert_eq(animation_player.get_animation("jump").loop_mode, Animation.LOOP_NONE,
		"jump 保持单次播放")

	# 播放位置必须真的随时间推进（v9 是骨骼 clip 驱动，phase 即 current_animation_position）。
	animation_player.play("walk")
	var phase_before := animation_player.current_animation_position
	animation_player.advance(0.2)
	var phase_after := animation_player.current_animation_position
	t.assert_true(phase_after > phase_before,
		"walk 播放位置随时间推进（%.4f -> %.4f）" % [phase_before, phase_after])

	_assert_action_mapping(t, presentation, animation_player)


static func _assert_action_mapping(t, presentation: CultivatorSkeletonPresentation,
		animation_player: AnimationPlayer) -> void:
	presentation.reset_pose()
	# 走：1.55 m/s（SwordsmanMotionComponent.move_speed）落在 walk 带。
	presentation.advance_state(_state(Vector3(1.55, 0.0, 0.0), true, false), 0.1)
	var walk := presentation.pose_state()
	t.assert_eq(str(walk.get("current_clip", "")), "walk", "1.55 m/s 着地状态映射到 walk")
	# 播放速率 = 速度 / walk 原速参考（实测 1.288 m/s），此处 ≈1.203。
	t.assert_true(absf(animation_player.speed_scale - 1.55 / 1.288) < EPSILON,
		"walk 切换首帧即按实际速度同步播放率（%.3f）" % animation_player.speed_scale)

	# 疾行：3.45 m/s（sprint_speed）越过 2.2 阈值，进入 run 带。
	presentation.advance_state(_state(Vector3(3.45, 0.0, 0.0), true, false), 0.1)
	var run := presentation.pose_state()
	t.assert_eq(str(run.get("current_clip", "")), "run",
		"3.45 m/s（疾行）映射到 run —— run 不再是死分支")
	t.assert_true(absf(animation_player.speed_scale - 3.45 / 3.426) < EPSILON,
		"run 按实际速度同步播放率（%.3f）" % animation_player.speed_scale)
	# 走/跑两档都必须真能触发，否则 run clip 仍不可达。
	t.assert_true(
		float(walk.get("speed", 0.0)) < CultivatorSkeletonPresentation.RUN_SPEED_MPS
		and float(run.get("speed", 0.0)) > CultivatorSkeletonPresentation.RUN_SPEED_MPS,
		"两档速度分居 run 阈值两侧（walk %.2f / run %.2f，阈值 %.2f）" % [
			float(walk.get("speed", 0.0)), float(run.get("speed", 0.0)),
			CultivatorSkeletonPresentation.RUN_SPEED_MPS])

	presentation.advance_state(_state(Vector3(0.0, 4.0, 0.0), false, false), 0.1)
	var jump := presentation.pose_state()
	t.assert_eq(str(jump.get("current_clip", "")), "jump", "非御剑腾空状态映射到 jump")

	presentation.advance_state(_state(Vector3(12.0, 0.0, 0.0), false, true), 0.1)
	var flight := presentation.pose_state()
	# 御剑现在优先用专门手作的「御剑而立」姿态（自带前倾），不再拿 idle 抬速充数。
	# 旧资材缺该 clip 时退回 idle@0.6；两种路径都要被覆盖，因此按资产实际内容分支断言。
	var ride_expected := "sword_ride" if presentation.has_state("sword_ride") else "idle"
	t.assert_eq(str(flight.get("current_clip", "")), ride_expected,
		"御剑状态映射到 %s" % ride_expected)
	t.assert_true(bool(flight.get("flying", false)), "御剑状态写入公开姿态快照")
	if ride_expected == "sword_ride":
		t.assert_true(absf(animation_player.speed_scale - 1.0) < EPSILON,
			"御剑而立按原速播放（%.3f）——前倾由姿态自带，无需倍速或叠加倾斜"
			% animation_player.speed_scale)
	else:
		t.assert_true(absf(animation_player.speed_scale - 0.6) < EPSILON,
			"退回路径：御剑 idle 播放率为 0.6（%.3f）" % animation_player.speed_scale)

	presentation.reset_pose()
	var reset := presentation.pose_state()
	t.assert_eq(str(reset.get("current_clip", "")), "idle", "reset_pose 回到 idle")
	t.assert_true(absf(float(reset.get("clock", -1.0))) < EPSILON,
		"reset_pose 同步归零表现时钟（%.3f）" % float(reset.get("clock", -1.0)))


static func _state(velocity: Vector3, grounded: bool, flying: bool) -> Dictionary:
	return {
		"velocity": velocity,
		"grounded": grounded,
		"flying": flying,
		"aim": Vector3.FORWARD,
	}
