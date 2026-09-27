extends RefCounted
## 修仙动作 v1 现役人物视觉链接线回归测试。
##
## 覆盖范围超出单一资源：默认 Swordsman prefab、motion preview、青玉纸样板三条消费路径
## 必须到达**同一个** 修仙动作视觉场景，且该场景提供唯一 Skeleton3D + 唯一 AnimationPlayer +
## 精确四段 clip。同时锁死旧视觉资产仍可独立加载（探索资产保留），以及朝向契约与飞剑装配
## 不因换人而改变。
##
## 依据 notes/implemented/art/2026-09-26-ink-cultivator-runtime.md。

const SWORDSMAN_SCENE := "res://game/actors/swordsman/swordsman.tscn"
const ACTIVE_VISUAL_SCENE := "res://game/actors/swordsman/cultivator_xianxia_motion_v1_visual.tscn"
const ACTIVE_MODEL := "res://game/actors/swordsman/models/cultivator_xianxia_motion_v1.glb"
const PREVIEW_DISPLAY := "res://game/systems/motion_preview/motion_preview_display.gd"
const SAMPLE_SCRIPT := "res://levels/experiments/character_movement/jade_paper_sample.gd"
const SAMPLE_SCENE := "res://levels/experiments/character_movement/jade_paper_sample.tscn"

## 旧视觉链：必须是「仍可独立加载」的回退资产，只是不再接入现役移动链。
const LEGACY_VISUALS := {
	"v7 中性底座": "res://game/actors/swordsman/cultivator_visual_neutral_youth_v7.tscn",
	"旧分件刚体": "res://game/actors/swordsman/cultivator_visual.tscn",
	"旧 v9 骨骼与动画": "res://game/actors/swordsman/cultivator_tripo_v9_visual.tscn",
	"旧青玉长袍骨骼": "res://game/actors/swordsman/cultivator_visual_rigged.tscn",
}
## 四段核心动作：表现层按速度自动选择，资产必须全部具备。
const CLIPS := ["idle", "walk", "run", "jump"]
## 手工摆出的额外状态（库里没有）。可选：缺失时表现层照常工作，对应状态退化为 idle。
const OPTIONAL_STATES := ["idle_guarded", "meditate", "sword_ride"]


static func run(t) -> void:
	t.begin_case()
	_assert_shared_prefab(t)
	_assert_visual_scene_contract(t)
	_assert_preview_shares_same_source(t)
	_assert_sample_no_longer_swaps_visual(t)
	_assert_sprint_ladder(t)
	_assert_optional_states(t)
	_assert_facing_contract(t)
	_assert_legacy_visuals_still_load(t)


## 默认 prefab 必须直达 修仙动作 v1，且保持 Visual 这个公开节点名（FlightBundle 与 Swordsman 都依赖它）。
static func _assert_shared_prefab(t) -> void:
	var packed := load(SWORDSMAN_SCENE) as PackedScene
	t.assert_true(packed != null, "swordsman.tscn 可加载")
	if packed == null:
		return
	var actor := packed.instantiate() as Node3D
	t.track(actor)
	var visual := actor.get_node_or_null("Visual") as Node3D
	t.assert_true(visual != null, "共享角色保留公开节点名 Visual")
	t.assert_eq(visual.scene_file_path, ACTIVE_VISUAL_SCENE,
		"默认 Swordsman 的 Visual 就是 修仙动作 v1 视觉场景")
	t.assert_true(actor.get_node_or_null("Visual/CultivatorXianxiaV1") != null,
		"修仙动作 v1 视觉装入 修仙动作 v1 模型实例")
	t.assert_true(actor.get_node_or_null("Visual/CultivatorSkeletonPresentation") != null,
		"修仙动作 v1 视觉装入骨骼表现层")
	# 旧视觉不得作为现役人物出现。
	for legacy in ["Visual/Cultivator", "Visual/CultivatorRigged",
			"Visual/CultivatorNeutralYouthV7", "Visual/CultivatorPresentation"]:
		t.assert_true(actor.get_node_or_null(legacy) == null,
			"默认角色不再包含旧视觉节点 %s" % legacy)


## 修仙动作 v1 场景本身的结构契约：唯一骨架、唯一播放器、精确四段 clip、正确的循环语义。
static func _assert_visual_scene_contract(t) -> void:
	var packed := load(ACTIVE_VISUAL_SCENE) as PackedScene
	t.assert_true(packed != null, "修仙动作 v1 视觉场景可加载")
	if packed == null:
		return
	var host := Node3D.new()
	host.name = "Host"
	t.track(host)
	var visual := packed.instantiate() as Node3D
	t.assert_true(visual != null, "修仙动作 v1 视觉场景根是 Node3D")
	if visual == null:
		return
	# 独立实例化时表现层没有 actor 可读；关掉自动读取后才能安全入树（预览路径同做法）。
	var presentation := visual.get_node_or_null("CultivatorSkeletonPresentation")
	if presentation != null:
		presentation.set("auto_read_actor", false)
	host.add_child(visual)
	if presentation != null:
		t.assert_true(not bool(presentation.get("prefer_guarded_idle")),
			"现役静止默认关闭负手偏好")
		presentation.call("reset_pose")
		t.assert_eq(str(presentation.call("pose_state").get("current_clip", "")), "idle",
			"现役静止与预览重置选用普通站姿 idle")

	var skeletons := visual.find_children("*", "Skeleton3D", true, false)
	t.assert_eq(skeletons.size(), 1, "修仙动作 v1 视觉恰好一个 Skeleton3D")
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	t.assert_eq(players.size(), 1, "修仙动作 v1 视觉恰好一个 AnimationPlayer")
	if players.size() != 1:
		return
	var player := players[0] as AnimationPlayer
	var listed := player.get_animation_list()
	# 四段核心动作必须齐备；手作额外状态是增量，因此断言「至少四段且核心齐全」，
	# 而不是写死总数——写死总数会在每次新增手作姿态时变成假失败（本用例已如此失败过一次）。
	for clip in CLIPS:
		t.assert_true(player.has_animation(clip), "修仙动作 v1 动作库包含精确名 %s" % clip)
	t.assert_true(listed.size() >= CLIPS.size(),
		"修仙动作 v1 至少四段核心 clip（实际 %d：%s）" % [listed.size(), listed])
	# 不得混入非预期 clip：除核心四段与登记的手作状态之外，不该有别的。
	var allowed := {}
	for clip in CLIPS + OPTIONAL_STATES:
		allowed[clip] = true
	for clip in listed:
		t.assert_true(allowed.has(clip),
			"资产只含核心四段与登记的手作状态，未混入 %s（全部 %s）" % [clip, listed])

	# 模型实例必须指向 修仙动作 v1 GLB 本体，而不是旧模型。
	var model := visual.get_node_or_null("CultivatorXianxiaV1") as Node3D
	t.assert_true(model != null, "修仙动作 v1 视觉包含模型实例节点")
	if model != null:
		t.assert_eq(model.scene_file_path, ACTIVE_MODEL, "模型实例就是 修仙动作 v1 GLB")

	# 表现层在 _ready 里显式设置循环：idle/walk/run 线性循环、jump 单次。
	for clip in ["idle", "walk", "run"]:
		t.assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR,
			"%s 为线性循环（glTF 导入默认 LOOP_NONE，需表现层修正）" % clip)
	t.assert_eq(player.get_animation("jump").loop_mode, Animation.LOOP_NONE,
		"jump 保持单次播放")

	# 播放位置必须真的推进，且 phase 快照与播放器同源。
	player.play("walk")
	var before := player.current_animation_position
	player.advance(0.2)
	var after := player.current_animation_position
	t.assert_true(after > before, "walk 播放位置随时间推进（%.4f -> %.4f）" % [before, after])
	if presentation != null:
		presentation.call("reset_pose")
		presentation.call("advance_state",
			{"velocity": Vector3(2.25, 0.0, 0.0), "grounded": true, "flying": false}, 0.1)
		var pose: Dictionary = presentation.call("pose_state")
		t.assert_eq(str(pose.get("current_clip", "")), "run",
			"2.25 m/s（疾行速度）着地映射到 run：run 现已真实可达")
		t.assert_true(absf(float(pose.get("phase", -1.0))
			- player.current_animation_position) < 0.0001,
			"快照 phase 就是 AnimationPlayer 播放位置（%.4f vs %.4f）"
			% [float(pose.get("phase", -1.0)), player.current_animation_position])


## motion preview 必须显式指到 修仙动作 v1 场景与 修仙动作 v1 表现层节点名。
## 它独立 preload 视觉场景，改 swordsman.tscn 不会自动带上它——本断言就是防这条分叉。
static func _assert_preview_shares_same_source(t) -> void:
	var source := FileAccess.get_file_as_string(PREVIEW_DISPLAY)
	t.assert_true(not source.is_empty(), "可读取 motion preview 脚本")
	if source.is_empty():
		return
	t.assert_true(source.contains(ACTIVE_VISUAL_SCENE),
		"motion preview 指向 修仙动作 v1 视觉场景（与默认 prefab 同源）")
	t.assert_true(not source.contains("cultivator_visual.tscn"),
		"motion preview 不再 preload 旧共享视觉")
	t.assert_true(source.contains("CultivatorSkeletonPresentation"),
		"motion preview 读取 修仙动作 v1 表现层节点名")


## 青玉纸样板必须已删除 v7 场景侧替换：入树前换 Visual 会绕过共享装配契约。
static func _assert_sample_no_longer_swaps_visual(t) -> void:
	var source := FileAccess.get_file_as_string(SAMPLE_SCRIPT)
	t.assert_true(not source.is_empty(), "可读取青玉纸样板脚本")
	if source.is_empty():
		return
	t.assert_true(not source.contains("NEUTRAL_YOUTH_VISUAL_SCENE"),
		"样板不再声明 v7 视觉常量")
	t.assert_true(not source.contains("remove_child"),
		"样板不再拆卸默认 Visual（v7 特例已移除）")
	t.assert_true(source.contains("Visual/CultivatorXianxiaV1"),
		"样板断言的是 修仙动作 v1 模型节点")

	# 真实入口：t.track() 会把样板挂进测试根（活动场景树），ActorAssembly 因此真的跑完装配。
	# 这也是同目录 test_jade_paper_rigged_animation.gd 观察飞剑的方式。
	var sample := load(SAMPLE_SCENE)
	t.assert_true(sample != null, "青玉纸样板场景可加载")
	if sample == null:
		return
	var instance := (sample as PackedScene).instantiate() as Node3D
	t.assert_true(instance != null, "青玉纸样板场景可实例化")
	if instance == null:
		return
	t.track(instance)
	var actor := instance.get_node_or_null("Swordsman") as Node3D
	t.assert_true(actor != null, "样板生成正式 Swordsman")
	if actor == null:
		return
	t.assert_true(actor.get_node_or_null("Visual/CultivatorXianxiaV1") != null,
		"样板运行时角色使用 修仙动作 v1 模型")
	var visual := actor.get_node_or_null("Visual") as Node3D
	t.assert_eq(visual.scene_file_path if visual != null else "", ACTIVE_VISUAL_SCENE,
		"样板的 Visual 就是共享 修仙动作 v1 场景（未被场景侧替换）")

	# 飞剑由 ActorAssembly 在 _ready 阶段装到 Visual 下，不是 .tscn 里的静态节点
	# （swordsman.tscn 与 修仙动作 v1 视觉场景都不含 FlyingSword 声明）。装配后必须唯一存在，
	# 且局部 yaw 补偿保持 180°——换人不改变这条契约。
	t.assert_true(actor.get_node_or_null("Visual/FlyingSword") != null,
		"修仙动作 v1 视觉下 ActorAssembly 仍把飞剑装到 Visual 下")
	# 注意：find_children 的第二个参数是**类型**过滤，传 "*" 会永远返回 0 个节点
	# （不是「任意类型」）。这里按真实类型 Node3D 过滤。
	var swords := actor.find_children("FlyingSword", "Node3D", true, false)
	t.assert_eq(swords.size(), 1,
		"飞剑视觉唯一（不因换人重复装配，实际 %d）" % swords.size())
	if swords.size() == 1:
		var sword := swords[0] as Node3D
		t.assert_true(absf(absf(sword.rotation.y) - PI) < 0.0001,
			"飞剑适配根局部 yaw 补偿 180° 不变（实际 %.4f）" % sword.rotation.y)
		t.assert_true(sword.get_node_or_null("FlyingSwordModel") != null,
			"飞剑适配根下仍实例化原 GLB 模型")


## 疾行两档：走/跑必须各有唯一可达速度带，且播放速率贴近原速（防快放）。
## 这一节锁住「run 不再是死分支」——它曾因 move_speed 4.0 < 阈值 5.5 而永远选不到。
static func _assert_sprint_ladder(t) -> void:
	var motion_script := load(
		"res://game/actors/swordsman/swordsman_motion_component.gd") as GDScript
	t.assert_true(motion_script != null, "运动组件脚本可加载")
	if motion_script == null:
		return
	var probe := motion_script.new() as SwordsmanMotionComponent
	t.assert_true(probe != null, "运动组件可实例化")
	if probe == null:
		return
	var walk_speed := probe.move_speed
	var sprint_speed := probe.sprint_speed
	t.assert_true(sprint_speed > walk_speed,
		"疾行速度高于步行（%.2f > %.2f）" % [sprint_speed, walk_speed])
	# 两档必须真的分居 run 阈值两侧，否则其中一档的 clip 永远选不到。
	t.assert_true(walk_speed < CultivatorSkeletonPresentation.RUN_SPEED_MPS,
		"步行速度低于 run 阈值（%.2f < %.2f）" % [
			walk_speed, CultivatorSkeletonPresentation.RUN_SPEED_MPS])
	t.assert_true(sprint_speed > CultivatorSkeletonPresentation.RUN_SPEED_MPS,
		"疾行速度高于 run 阈值（%.2f > %.2f）=> run 可达" % [
			sprint_speed, CultivatorSkeletonPresentation.RUN_SPEED_MPS])
	probe.free()

	# 两档各自的播放速率必须贴近原速：明显偏离说明阈值/参考速度与 clip 不匹配。
	var packed := load(ACTIVE_VISUAL_SCENE) as PackedScene
	if packed == null:
		return
	var host := Node3D.new()
	host.name = "SprintHost"
	t.track(host)
	var visual := packed.instantiate() as Node3D
	var presentation := visual.get_node_or_null("CultivatorSkeletonPresentation")
	if presentation != null:
		presentation.set("auto_read_actor", false)
	host.add_child(visual)
	if presentation == null:
		return
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		return
	var player := players[0] as AnimationPlayer
	for spec in [["walk", walk_speed], ["run", sprint_speed]]:
		presentation.call("reset_pose")
		presentation.call("advance_state",
			{"velocity": Vector3(spec[1], 0.0, 0.0), "grounded": true, "flying": false}, 0.1)
		var pose: Dictionary = presentation.call("pose_state")
		t.assert_eq(str(pose.get("current_clip", "")), str(spec[0]),
			"%.2f m/s 映射到 %s" % [spec[1], spec[0]])
		# 两档真实速度与新 clip 的估算自然速度须相近，避免靠快放掩盖滑步。
		var rate := player.speed_scale
		t.assert_true(rate > 0.85 and rate < 1.25,
			"%s 播放速率贴近原速（%.2f，速度 %.2f m/s）" % [spec[0], rate, spec[1]])


## 手作额外状态：资产里有就必须可用，且显式覆盖不被速度推翻。
static func _assert_optional_states(t) -> void:
	var packed := load(ACTIVE_VISUAL_SCENE) as PackedScene
	if packed == null:
		return
	var host := Node3D.new()
	host.name = "StatesHost"
	t.track(host)
	var visual := packed.instantiate() as Node3D
	var presentation := visual.get_node_or_null("CultivatorSkeletonPresentation")
	if presentation != null:
		presentation.set("auto_read_actor", false)
	host.add_child(visual)
	if presentation == null:
		return
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		return
	var player := players[0] as AnimationPlayer

	for clip in OPTIONAL_STATES:
		if not presentation.call("has_state", clip):
			# 允许旧的四段资产：缺就跳过，但要说清楚为什么没测。
			t.assert_true(not player.has_animation(clip),
				"has_state(%s) 与实际 clip 表一致（%s 不在表里）" % [clip, clip])
			continue
		t.assert_true(player.has_animation(clip),
			"手作状态 %s 已打进运行时资产" % clip)
		# 额外状态是持续姿态，必须线性循环（否则 3 秒后停在末帧）。
		t.assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR,
			"%s 为线性循环" % clip)

	# 显式覆盖：play_state 后即便速度很高也不得被自动选择推翻。
	if presentation.call("has_state", "meditate"):
		t.assert_true(bool(presentation.call("play_state", "meditate")),
			"play_state(meditate) 成功")
		presentation.call("advance_state",
			{"velocity": Vector3(9.0, 0.0, 0.0), "grounded": true, "flying": false}, 0.1)
		var held: Dictionary = presentation.call("pose_state")
		t.assert_eq(str(held.get("current_clip", "")), "meditate",
			"显式覆盖不被速度推翻（9 m/s 仍保持 meditate）")
		t.assert_true(bool(held.get("overridden", false)), "快照标记 overridden")
		# 解除覆盖后必须回到速度驱动。
		presentation.call("release_state")
		presentation.call("advance_state",
			{"velocity": Vector3(2.25, 0.0, 0.0), "grounded": true, "flying": false}, 0.1)
		var released: Dictionary = presentation.call("pose_state")
		t.assert_eq(str(released.get("current_clip", "")), "run",
			"release_state 后回到速度驱动（2.25 m/s -> run）")
		t.assert_true(not bool(released.get("overridden", false)),
			"释放后 overridden 归假")
	# 未知状态必须被拒绝，不能静默成功。
	t.assert_true(not bool(presentation.call("play_state", "no_such_clip")),
		"play_state 拒绝不存在的 clip")


## 朝向契约：模型局部 +Z 是正面，visual_yaw_for_aim 把正面转到 aim 方向。
## 换人物最容易破坏的就是这条（轴向转换可能带来 180° 常量偏差）。
static func _assert_facing_contract(t) -> void:
	var aim := Vector3(1.0, 0.0, 0.0)
	var yaw := Swordsman.visual_yaw_for_aim(aim)
	var front := Basis(Vector3.UP, yaw) * Vector3.BACK
	t.assert_true(front.dot(aim) > 0.999,
		"visual_yaw_for_aim 后模型局部 +Z 正面与 aim 同向（dot=%.4f）" % front.dot(aim))

	# 反向与侧向也必须一致，避免只在单一轴向上成立。
	var west := Vector3(-1.0, 0.0, 0.0)
	var west_front := Basis(Vector3.UP, Swordsman.visual_yaw_for_aim(west)) * Vector3.BACK
	t.assert_true(west_front.dot(west) > 0.999,
		"朝西时正面同样对齐（dot=%.4f）" % west_front.dot(west))
	var south := Vector3(0.0, 0.0, 1.0)
	var south_front := Basis(Vector3.UP, Swordsman.visual_yaw_for_aim(south)) * Vector3.BACK
	t.assert_true(south_front.dot(south) > 0.999,
		"朝南时正面同样对齐（dot=%.4f）" % south_front.dot(south))

	# 真实角色把该 yaw 写在 Visual 上：修仙动作 v1 视觉下这条链路未被换人打断。
	var actor := (load(SWORDSMAN_SCENE) as PackedScene).instantiate() as Node3D
	t.track(actor)
	var visual := actor.get_node_or_null("Visual") as Node3D
	t.assert_true(visual != null, "默认角色有 Visual 可承载朝向")
	if visual != null:
		t.assert_true(absf(visual.rotation.y) < 0.0001 or is_finite(visual.rotation.y),
			"Visual 朝向初始为有限值（%.4f）" % visual.rotation.y)


## 探索资产保留：三条旧视觉链必须仍能独立加载（不再接入，但不得被删除或破坏）。
static func _assert_legacy_visuals_still_load(t) -> void:
	for label in LEGACY_VISUALS:
		var path: String = LEGACY_VISUALS[label]
		var packed := load(path) as PackedScene
		t.assert_true(packed != null, "旧视觉仍可加载：%s（%s）" % [label, path])
		if packed == null:
			continue
		var node := packed.instantiate() as Node3D
		t.assert_true(node != null, "旧视觉可实例化：%s" % label)
		if node != null:
			t.assert_true(node.get_child_count() > 0,
				"旧视觉实例保留子树（%s 实际 %d 个子节点）"
				% [label, node.get_child_count()])
			node.free()
