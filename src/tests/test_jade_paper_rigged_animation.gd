extends RefCounted
## 青玉纸白样板的真人骨骼动作接线回归测试（v7 中性动画底座）。
##
## 覆盖真实入口而非孤立资源：样板实例化 Swordsman 时必须在入树前把默认分件 Visual
## 换成 v7 中性动画底座视觉（无仙侠衣装）；ActorAssembly 随后仍应把 FlyingSword
## 装到新 Visual 下。动作映射只经公开 advance_state()/pose_state() 读写，
## 不访问表现层私有字段。
##
## 依据 notes/proposed/art/2026-09-19-neutral-youth-animation-base-v7.md。

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
	t.assert_true(actor.get_node_or_null("Visual/CultivatorNeutralYouthV7") != null,
		"样板正式运行路径装入 v7 中性动画底座模型")
	t.assert_true(actor.get_node_or_null("Visual/Cultivator") == null,
		"样板不再保留旧分件模型")
	t.assert_true(actor.get_node_or_null("Visual/CultivatorRigged") == null,
		"样板不再加载旧青玉长袍骨骼模型（保留为回退资产，不接入运行时）")
	var presentation := actor.get_node_or_null(
		"Visual/CultivatorSkeletonPresentation") as CultivatorSkeletonPresentation
	t.assert_true(presentation != null, "样板装入骨骼表现层")
	t.assert_true(actor.get_node_or_null("Visual/FlyingSword") != null,
		"入树前替换后 ActorAssembly 仍把飞剑装到新 Visual")
	if presentation == null:
		return
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	t.assert_eq(players.size(), 1, "骨骼视觉恰好一个 AnimationPlayer")
	if players.size() != 1:
		return
	var animation_player := players[0] as AnimationPlayer
	for clip in ["idle", "walk", "run", "jump"]:
		t.assert_true(animation_player.has_animation(clip), "骨骼动作库包含 %s" % clip)

	_assert_action_mapping(t, presentation, animation_player)


static func _assert_action_mapping(t, presentation: CultivatorSkeletonPresentation,
		animation_player: AnimationPlayer) -> void:
	presentation.reset_pose()
	presentation.advance_state(_state(Vector3(4.0, 0.0, 0.0), true, false), 0.1)
	var walk := presentation.pose_state()
	t.assert_eq(str(walk.get("current_clip", "")), "walk", "4 m/s 着地状态映射到 walk")
	t.assert_true(absf(animation_player.speed_scale - 2.5) < EPSILON,
		"walk 切换首帧即按实际速度同步播放率（%.3f）" % animation_player.speed_scale)

	presentation.advance_state(_state(Vector3(6.0, 0.0, 0.0), true, false), 0.1)
	var run := presentation.pose_state()
	t.assert_eq(str(run.get("current_clip", "")), "run", "6 m/s 着地状态映射到 run")
	t.assert_true(absf(animation_player.speed_scale - 1.875) < EPSILON,
		"run 按实际速度同步播放率（%.3f）" % animation_player.speed_scale)

	presentation.advance_state(_state(Vector3(0.0, 4.0, 0.0), false, false), 0.1)
	var jump := presentation.pose_state()
	t.assert_eq(str(jump.get("current_clip", "")), "jump", "非御剑腾空状态映射到 jump")

	presentation.advance_state(_state(Vector3(12.0, 0.0, 0.0), false, true), 0.1)
	var flight := presentation.pose_state()
	t.assert_eq(str(flight.get("current_clip", "")), "idle", "御剑状态映射到慢速 idle")
	t.assert_true(bool(flight.get("flying", false)), "御剑状态写入公开姿态快照")
	t.assert_true(absf(animation_player.speed_scale - 0.6) < EPSILON,
		"御剑 idle 播放率为 0.6（%.3f）" % animation_player.speed_scale)

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
