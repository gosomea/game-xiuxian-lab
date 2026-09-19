extends RefCounted
## 路线 A 代表链测试：KayKit 原生 GLB（41 骨 / 76 clips）直接接 Godot 的可用性回归。
##
## 覆盖真实入口而非孤立资源：实例化 kaykit_route_a_visual.tscn，断言骨架/动作可达、
## 武器隐藏、披风保留、材质存在，并只经公开 API（set_motion_state / advance_state /
## pose_state / reset_pose）验证状态映射，不访问表现层私有字段。
##
## 受控 A/B 契约：阈值 0.3 / 5.5、步幅 1.6 / 3.2、blend 0.15 必须与
## CultivatorSkeletonPresentation 逐字一致 —— 本测试同时锁死这组常量。

const VISUAL_SCENE := "res://game/actors/swordsman/kaykit_route_a/kaykit_route_a_visual.tscn"
const STAGE_SCENE := "res://game/actors/swordsman/kaykit_route_a/kaykit_route_a_stage.tscn"
const PRESENTATION_SCRIPT := "res://game/actors/swordsman/kaykit_route_a/kaykit_route_a_presentation.gd"
const ROUTE_C_SCRIPT := "res://game/actors/swordsman/cultivator_skeleton_presentation.gd"
const EPSILON := 0.0001

const HIDDEN_WEAPONS: Array[String] = [
	"Knife", "Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Throwable",
]


static func run(t) -> void:
	t.begin_case()
	var visual := load(VISUAL_SCENE).instantiate() as Node3D
	t.assert_true(visual != null, "路线 A 视觉场景可实例化")
	if visual == null:
		return
	t.track(visual)
	var presentation := visual.get_node_or_null(
		"KaykitRouteAPresentation") as KaykitRouteAPresentation
	t.assert_true(presentation != null, "视觉场景装入 KaykitRouteAPresentation")
	if presentation == null:
		return

	_assert_native_rig(t, visual)
	_assert_clips(t, visual)
	_assert_weapons_hidden_keep_cape(t, visual, presentation)
	_assert_materials(t, visual)
	_assert_api_shape(t, presentation)
	_assert_contract_constants(t)
	_assert_state_mapping(t, presentation)

	# 演示台：独立可运行入口。自动截图在 headless 下不可用（无渲染帧），
	# 因此这里用**可退出的结构断言 + 真实驱动**替代像素证据；
	# 观感/审美仍须使用者实机确认（见 docs/playtest/2026-09-19-kaykit-route-a.md）。
	t.begin_case()
	var stage := load(STAGE_SCENE).instantiate() as Node3D
	t.assert_true(stage != null, "路线 A 演示场景可实例化")
	if stage == null:
		return
	t.track(stage)
	t.assert_true(stage.get_node_or_null("KaykitRouteAVisual") != null,
		"演示场景装入视觉子树")
	# 最小环境齐备：相机 / 方向光 / 地面 —— 使用者打开即可看见角色。
	t.assert_eq(stage.find_children("*", "Camera3D", true, false).size(), 1,
		"演示场景含 1 台相机")
	t.assert_eq(stage.find_children("*", "DirectionalLight3D", true, false).size(), 1,
		"演示场景含 1 盏方向光")
	t.assert_true(stage.get_node_or_null("Ground") != null, "演示场景含地面")

	# 演示台持有的表现层可被真实驱动（与键盘路径同一公开 API）。
	var stage_presentation := stage.get_node_or_null(
		"KaykitRouteAVisual/KaykitRouteAPresentation") as KaykitRouteAPresentation
	t.assert_true(stage_presentation != null, "演示台取到表现层")
	if stage_presentation != null:
		var stage_player := _player_of(stage_presentation)
		t.assert_true(stage_player != null, "演示台取到 AnimationPlayer")
		stage_presentation.reset_pose()
		t.assert_eq(str(stage_presentation.pose_state().get("current_clip", "")),
			"Unarmed_Idle", "演示台初始态为 Unarmed_Idle")
		for probe in [
			[KaykitRouteAPresentation.MODE_GROUND, 2.0, true, "Walking_A"],
			[KaykitRouteAPresentation.MODE_GROUND, 7.0, true, "Running_A"],
			[KaykitRouteAPresentation.MODE_AIR, 0.0, false, "Jump_Idle"],
			[KaykitRouteAPresentation.MODE_FLIGHT, 12.0, false, "Jump_Idle"],
		]:
			stage_presentation.set_motion_state(probe[0], probe[1], probe[2])
			t.assert_eq(str(stage_presentation.pose_state().get("current_clip", "")),
				probe[3], "演示台五态驱动：%s -> %s" % [probe[0], probe[3]])


## 原生骨架：恰好 1 个 Skeleton3D、41 骨，且无 Mixamo 重定向痕迹。
static func _assert_native_rig(t, visual: Node3D) -> void:
	var skeletons: Array[Node] = visual.find_children("*", "Skeleton3D", true, false)
	t.assert_eq(skeletons.size(), 1, "原生 GLB 恰好一个 Skeleton3D")
	if skeletons.size() != 1:
		return
	var skeleton := skeletons[0] as Skeleton3D
	t.assert_eq(skeleton.get_bone_count(), 41, "原生骨架 41 骨")
	for bone in ["root", "hips", "chest", "upperarm.l", "upperarm.r", "hand.l", "hand.r"]:
		t.assert_true(skeleton.find_bone(bone) != -1, "原生骨架包含骨 %s" % bone)


## 76 clips 直接可用，且映射所需的 4 条原生名可达（不重命名）。
static func _assert_clips(t, visual: Node3D) -> void:
	var players: Array[Node] = visual.find_children("*", "AnimationPlayer", true, false)
	t.assert_eq(players.size(), 1, "路线 A 视觉恰好一个 AnimationPlayer")
	if players.size() != 1:
		return
	var player := players[0] as AnimationPlayer
	t.assert_eq(player.get_animation_list().size(), 76, "原生 GLB 导入 76 条 clip")
	for clip in ["Unarmed_Idle", "Walking_A", "Running_A", "Jump_Idle"]:
		t.assert_true(player.has_animation(clip), "原生 clip 可达：%s" % clip)
		if player.has_animation(clip):
			t.assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR,
				"持续状态 clip 显式设为线性循环：%s" % clip)


## 5 件武器隐藏、披风保留可见。
static func _assert_weapons_hidden_keep_cape(t, visual: Node3D,
		presentation: KaykitRouteAPresentation) -> void:
	var hidden_count := 0
	for weapon_name in HIDDEN_WEAPONS:
		var found: Array[Node] = visual.find_children(weapon_name, "MeshInstance3D", true, false)
		t.assert_eq(found.size(), 1, "上游自带武器件存在：%s" % weapon_name)
		if found.size() == 1:
			var mesh_instance := found[0] as MeshInstance3D
			t.assert_false(mesh_instance.visible, "武器已隐藏：%s" % weapon_name)
			hidden_count += 1
	t.assert_eq(hidden_count, HIDDEN_WEAPONS.size(), "5 件武器全部匹配并隐藏")
	var reported: Array[String] = presentation.hidden_parts()
	t.assert_eq(reported.size(), HIDDEN_WEAPONS.size(), "公开 API 报告隐藏了 5 件武器")

	var capes: Array[Node] = visual.find_children("Rogue_Cape", "MeshInstance3D", true, false)
	t.assert_eq(capes.size(), 1, "披风 Rogue_Cape 保留在场景中")
	if capes.size() == 1:
		t.assert_true((capes[0] as MeshInstance3D).visible, "披风保持可见（路线 B 对照锚点）")


## 材质与贴图随 GLB 导入，供 A/B 材质对照。
static func _assert_materials(t, visual: Node3D) -> void:
	var meshes: Array[Node] = visual.find_children("*", "MeshInstance3D", true, false)
	t.assert_eq(meshes.size(), 12, "原生 GLB 12 个 mesh（6 人体 + 1 披风 + 5 武器）")
	var with_material := 0
	var total_tris := 0
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mat := mesh_instance.get_active_material(0)
		if mat != null and mat is StandardMaterial3D:
			if (mat as StandardMaterial3D).albedo_texture != null:
				with_material += 1
		for si in mesh_instance.mesh.get_surface_count():
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(si)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			total_tris += indices.size() / 3
	t.assert_true(with_material >= 12, "全部 12 个 mesh 都带贴图材质（实际 %d）" % with_material)
	t.assert_eq(total_tris, 6035, "原生 GLB 合计 6035 tris（台账读数）")


## 公开 API 形状与既有骨骼表现层一致（可互换的前提）。
static func _assert_api_shape(t, presentation: KaykitRouteAPresentation) -> void:
	for method in ["set_motion_state", "advance_state", "sample_state", "pose_state",
			"reset_pose", "hidden_parts"]:
		t.assert_true(presentation.has_method(method), "表现层公开 API 存在：%s" % method)
	var script: Script = load(PRESENTATION_SCRIPT)
	t.assert_true(script != null, "表现层脚本可加载")
	if script != null:
		var instance := script.new() as Node
		t.assert_true(instance is Node3D, "表现层 extends Node3D（可挂 Visual 下）")
		instance.free()


## 受控 A/B：常量必须与 CultivatorSkeletonPresentation 逐字一致。
static func _assert_contract_constants(t) -> void:
	var route_a: GDScript = load(PRESENTATION_SCRIPT)
	var route_c: GDScript = load(ROUTE_C_SCRIPT)
	t.assert_true(route_a != null and route_c != null, "A / C 表现层脚本均可加载")
	if route_a == null or route_c == null:
		return
	for name in ["WALK_SPEED_MPS", "RUN_SPEED_MPS", "BLEND"]:
		t.assert_true(name in route_a, "路线 A 声明常量 %s" % name)
		t.assert_true(name in route_c, "既有骨骼表现层声明常量 %s" % name)
		t.assert_eq(route_a.get(name), route_c.get(name),
			"受控 A/B 常量一致：%s（A=%s C=%s）" % [name, route_a.get(name), route_c.get(name)])
	t.assert_eq(route_a.get("WALK_SPEED_MPS"), 0.3, "walk 阈值 = 0.3")
	t.assert_eq(route_a.get("RUN_SPEED_MPS"), 5.5, "run 阈值 = 5.5")
	t.assert_eq(route_a.get("BLEND"), 0.15, "blend = 0.15")
	var probe := route_a.new() as Node
	t.assert_true(absf(probe.walk_stride_meters - 1.6) < EPSILON, "walk 步幅 = 1.6")
	t.assert_true(absf(probe.run_stride_meters - 3.2) < EPSILON, "run 步幅 = 3.2")
	t.assert_true(absf(probe.flight_lean - deg_to_rad(21.0)) < EPSILON,
		"御剑前倾 = deg_to_rad(21)（%.6f rad）" % probe.flight_lean)
	probe.free()


## 状态映射（只经公开 API）。
static func _assert_state_mapping(t, presentation: KaykitRouteAPresentation) -> void:
	var player := _player_of(presentation)
	if player == null:
		t.assert_true(false, "无法取得 AnimationPlayer 以核对播放率")
		return

	presentation.reset_pose()
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Unarmed_Idle",
		"reset_pose 回到 Unarmed_Idle")

	# idle：速度为 0 且着地。
	presentation.set_motion_state(KaykitRouteAPresentation.MODE_GROUND, 0.0, true)
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Unarmed_Idle",
		"0 速度着地映射到 Unarmed_Idle")

	# walk：>0.3 且 <=5.5；首帧即同步播放率（2.0 / 1.6 = 1.25）。
	presentation.set_motion_state(KaykitRouteAPresentation.MODE_GROUND, 2.0, true)
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Walking_A",
		"2 m/s 着地映射到 Walking_A")
	t.assert_true(absf(player.speed_scale - 1.25) < EPSILON,
		"walk 切换首帧即同步播放率（%.3f）" % player.speed_scale)
	var walk_length := player.get_animation("Walking_A").length
	player.advance(walk_length * 2.2 / player.speed_scale)
	t.assert_true(player.is_playing(), "walk 推进超过两个周期后仍在播放")
	t.assert_eq(player.current_animation, "Walking_A", "walk 循环后仍保持当前 clip")
	t.assert_true(player.current_animation_position < walk_length,
		"walk 循环后播放位置回绕（pos=%.4f length=%.4f）" % [
			player.current_animation_position, walk_length])

	# run：>5.5；（7.0 / 3.2 = 2.1875）。
	presentation.set_motion_state(KaykitRouteAPresentation.MODE_GROUND, 7.0, true)
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Running_A",
		"7 m/s 着地映射到 Running_A")
	t.assert_true(absf(player.speed_scale - 2.1875) < EPSILON,
		"run 按实际速度同步播放率（%.4f）" % player.speed_scale)

	# 阈值边界：恰好 0.3 仍 idle，恰好 5.5 仍 walk（严格大于才切换）。
	presentation.set_motion_state(KaykitRouteAPresentation.MODE_GROUND, 0.3, true)
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Unarmed_Idle",
		"恰好 0.3 仍为 Unarmed_Idle（阈值严格大于）")
	presentation.set_motion_state(KaykitRouteAPresentation.MODE_GROUND, 5.5, true)
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Walking_A",
		"恰好 5.5 仍为 Walking_A（阈值严格大于）")

	# airborne：非着地 → Jump_Idle 循环。
	presentation.set_motion_state(KaykitRouteAPresentation.MODE_AIR, 0.0, false)
	var air := presentation.pose_state()
	t.assert_eq(str(air.get("current_clip", "")), "Jump_Idle", "腾空映射到 Jump_Idle")
	t.assert_true(not bool(air.get("grounded", true)), "腾空状态写入公开姿态快照")
	t.assert_true(absf(float(air.get("lean_target", -1.0))) < EPSILON, "腾空不前倾")

	# flight：Jump_Idle + 0.6 速率 + 21 度前倾。
	presentation.set_motion_state(KaykitRouteAPresentation.MODE_FLIGHT, 12.0, false)
	var flight := presentation.pose_state()
	t.assert_eq(str(flight.get("current_clip", "")), "Jump_Idle", "御剑映射到 Jump_Idle")
	t.assert_true(bool(flight.get("flying", false)), "御剑状态写入公开姿态快照")
	t.assert_true(absf(player.speed_scale - 0.6) < EPSILON,
		"御剑播放率为 0.6（%.3f）" % player.speed_scale)
	t.assert_true(absf(float(flight.get("lean_target", 0.0)) - deg_to_rad(21.0)) < EPSILON,
		"御剑前倾目标为 21 度（%.6f rad）" % float(flight.get("lean_target", 0.0)))

	# advance_state 的宿主快照路径与 set_motion_state 等价。
	presentation.reset_pose()
	presentation.advance_state(_state(Vector3(2.0, 0.0, 0.0), true, false), 0.1)
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Walking_A",
		"advance_state 快照路径映射 walk")
	presentation.advance_state(_state(Vector3(0.0, 4.0, 0.0), false, false), 0.1)
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Jump_Idle",
		"advance_state 快照路径映射腾空")
	presentation.advance_state(_state(Vector3(12.0, 0.0, 0.0), false, true), 0.1)
	t.assert_eq(str(presentation.pose_state().get("current_clip", "")), "Jump_Idle",
		"advance_state 快照路径映射御剑")
	t.assert_true(absf(player.speed_scale - 0.6) < EPSILON, "御剑经快照路径仍为 0.6 速率")

	# 归零断言。
	presentation.reset_pose()
	var reset := presentation.pose_state()
	t.assert_eq(str(reset.get("current_clip", "")), "Unarmed_Idle", "reset_pose 回到 Unarmed_Idle")
	t.assert_true(absf(float(reset.get("clock", -1.0))) < EPSILON,
		"reset_pose 同步归零表现时钟（%.3f）" % float(reset.get("clock", -1.0)))


static func _player_of(presentation: KaykitRouteAPresentation) -> AnimationPlayer:
	var found: Array[Node] = presentation.get_parent().find_children(
		"*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if found.size() == 1 else null


static func _state(velocity: Vector3, grounded: bool, flying: bool) -> Dictionary:
	return {
		"velocity": velocity,
		"grounded": grounded,
		"flying": flying,
		"aim": Vector3.FORWARD,
	}
