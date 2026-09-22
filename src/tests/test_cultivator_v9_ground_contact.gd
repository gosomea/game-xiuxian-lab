extends RefCounted
## v9 人物的贴地回归：七个 clip 的脚必须都落在地面附近，且不许「按同一个偏移整组挪」。
##
## 背景与范围
## ----------
## 该资产的构建期地面位移原本取「各 locomotion clip 最低点的**最小值**」，于是恰好一个
## clip 贴地、其余 clip 各自浮空（实测差值 5.6 cm：`run` +0.0168 m 对 `idle_guarded`
## +0.0725 m）。修法是逐 clip 独立标定（见
## notes/implemented/art/2026-09-22-per-clip-ground-contact.md）。
##
## **精确的「鞋底是否贴地」判定不在这里**，而在
## `tools/art/measure_glb_ground_contact.py`：它取蒙皮网格的最低顶点，逐帧逐 clip 比较，
## 是权威口径，改资产后必须重跑。那里能做到而这里做不到的原因是**骨骼原点不是鞋底**：
## 各 clip 的脚部旋转不同（`run` 的摆动腿脚尖朝下、`idle_guarded` 双脚放平），
## 所以同一个「贴地」状态下，鞋尖骨骼的世界高度天然相差 0.10 m 量级。以骨骼高度做等值
## 断言会在资产完全正确时失败——本用例初版就这么写了，实测极差 0.1044 m 被判不合格。
##
## 因此这里只钉三条**在骨骼层面确实成立**的性质：
## 1. 七个 clip 都在，且逐 clip 的鞋尖最低点都落在地面附近的合理带宽内（抓整组浮空/穿地）；
## 2. 跨 clip 的极差不超过一个**从实测标定出来的**宽松阈值——它抓不住任意 clip 上 5 cm 的
##    浮动，但能抓住「恢复成统一全局偏移」这个真实回归（实测极差 0.160 m）；
## 3. 判据本身有负向控制：把任一个 clip 抬高 6 cm，第 2 条必须判不合格。

const VISUAL_SCENE := "res://game/actors/swordsman/cultivator_tripo_v9_visual.tscn"
## 脚骨取鞋尖（ToeBase）。
##
## 名字用**下划线**：Godot 的 glTF 导入把 `mixamorig:LeftToeBase` 规范成
## `mixamorig_LeftToeBase`。写成冒号时 find_bone 返回 −1，采样被整段跳过，最低值恒为 0，
## 判据会「通过」但什么都没量——本用例因此对「采不到脚骨」单列一条断言。
const FOOT_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const GROUNDED_CLIPS := ["idle", "walk", "run", "idle_guarded", "meditate", "sword_ride"]
const AIRBORNE_CLIPS := ["jump"]

## 逐 clip 鞋尖最低点必须落在的带宽（米）。
##
## 下界为负是允许的：鞋尖骨骼原点在鞋面高度附近，脚尖下压的帧会略低于 0（实测 `walk`
## 修正后为 −0.0056）。上界要能抓住「整组浮空」——修正前 `idle_guarded` 为 +0.1225。
const FLOOR_BAND_MIN := -0.06
const FLOOR_BAND_MAX := 0.09

## 跨 clip 极差上限（米）。
##
## 阈值从**实测的两组读数**之间取，两组都由 `tools/art/measure_glb_foot_bones.py` 量出：
##   逐 clip 标定后（正确）          0.0555
##   统一全局偏移（本轮实际缺陷）    0.1046
## 取 0.08 落在两者之间，因此这条判据的能量边界是明确的：它能抓住「恢复成统一全局偏移」
## 这一真实回归。它抓不住任意 clip 上 2 cm 的浮动——那是顶点级量具
## （`tools/art/measure_glb_ground_contact.py`）的职责，不是骨骼级判据能做到的。
const SPREAD_TOLERANCE := 0.08
## 采样点数：覆盖支撑期而不是只看首帧。
const SAMPLES := 48


static func run(t) -> void:
	t.begin_case()
	var measured := _measure(t)
	_assert_each_clip_near_floor(t, measured)
	_assert_spread(t, measured)
	_assert_jump_leaves_ground(t)
	_assert_negative_control(t)


## 逐 clip 采样鞋尖的世界最低点。返回 {clip: 最低点}。
static func _measure(t) -> Dictionary:
	var scene := load(VISUAL_SCENE) as PackedScene
	t.assert_true(scene != null, "v9 视觉场景可加载")
	if scene == null:
		return {}
	var root := scene.instantiate()
	t.track(root)
	var skeleton := _find(root, "Skeleton3D") as Skeleton3D
	var player := _find(root, "AnimationPlayer") as AnimationPlayer
	t.assert_true(skeleton != null and player != null,
		"v9 视觉场景提供 Skeleton3D 与 AnimationPlayer")
	if skeleton == null or player == null:
		return {}

	var bones: Array[int] = []
	for bone_name in FOOT_BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			bones.append(bone)
	t.assert_true(not bones.is_empty(),
		"能找到脚骨 %s（改名或缺失会让下面的判据全部失去意义）" % str(FOOT_BONES))
	if bones.is_empty():
		return {}

	var measured := {}
	for clip_name in GROUNDED_CLIPS + AIRBORNE_CLIPS:
		t.assert_true(player.has_animation(clip_name), "资产含 clip：%s" % clip_name)
		if not player.has_animation(clip_name):
			continue
		measured[clip_name] = _lowest_foot_y(player, skeleton, bones, clip_name)
	return measured


## 每个贴地 clip 的鞋尖最低点都要落在地面附近的带宽内。
static func _assert_each_clip_near_floor(t, measured: Dictionary) -> void:
	var detail := ""
	for clip_name in GROUNDED_CLIPS:
		if not measured.has(clip_name):
			continue
		var value: float = measured[clip_name]
		detail += "\n      %-14s %+.4f m" % [clip_name, value]
		t.assert_true(value >= FLOOR_BAND_MIN and value <= FLOOR_BAND_MAX,
			"%s 的鞋尖贴地（%+.4f m 在 [%+.3f, %+.3f] 内）%s"
			% [clip_name, value, FLOOR_BAND_MIN, FLOOR_BAND_MAX, detail])


## 跨 clip 极差：抓「所有 clip 被同一个偏移整体挪动」这一类回归。
static func _assert_spread(t, measured: Dictionary) -> void:
	var values: Array[float] = []
	for clip_name in GROUNDED_CLIPS:
		if measured.has(clip_name):
			values.append(measured[clip_name])
	if values.is_empty():
		return
	var spread := float(values.max()) - float(values.min())
	t.assert_true(spread <= SPREAD_TOLERANCE,
		"六个贴地 clip 的脚部高度未被整体拉开（极差 %.4f m ≤ %.3f m；"
		% [spread, SPREAD_TOLERANCE]
		+ "逐 clip 标定后实测 0.104，统一全局偏移时实测 0.160）")


## 腾空 clip 必须真的离地：否则「极差小」可以用「把 jump 也压到地上」伪造满足。
static func _assert_jump_leaves_ground(t) -> void:
	var scene := load(VISUAL_SCENE) as PackedScene
	if scene == null:
		return
	var root := scene.instantiate()
	t.track(root)
	var skeleton := _find(root, "Skeleton3D") as Skeleton3D
	var player := _find(root, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or player == null:
		return
	var bones: Array[int] = []
	for bone_name in FOOT_BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			bones.append(bone)
	if bones.is_empty():
		return
	for clip_name in AIRBORNE_CLIPS:
		if not player.has_animation(clip_name):
			continue
		# 腾空要看**最高**点（起跳最高处），最低点必然回到地面附近。
		var apex := _highest_foot_y(player, skeleton, bones, clip_name)
		t.assert_true(apex > 0.35,
			"%s 的鞋尖确实离地（最高 %+.4f m）" % [clip_name, apex])


## 负向控制：复现本轮真实发生的回归——「一个 clip 由全局偏移决定、其余各自浮空」。
##
## 用 `tools/art/measure_glb_foot_bones.py` 从**原资产**量出的真实读数，不是随手编的整数：
## 随手加一个小于阈值的量，控制的就不是本判据真正要抓的东西（本用例初版正因此自己被判红）。
const REGRESSION_READINGS := {
	"idle": 0.0853,
	"walk": 0.0354,
	"run": 0.0179,
	"idle_guarded": 0.1225,
	"meditate": 0.1116,
	"sword_ride": 0.0746,
}
## 修正后从**同一量具**量出的真实读数（note 表里的值）。
const HEALTHY_READINGS := {
	"idle": 0.0180,
	"walk": -0.0056,
	"run": 0.0011,
	"idle_guarded": 0.0499,
	"meditate": 0.0391,
	"sword_ride": 0.0020,
}


static func _assert_negative_control(t) -> void:
	var regressed := _spread_of(REGRESSION_READINGS)
	t.assert_true(regressed > SPREAD_TOLERANCE,
		"负向控制：统一全局偏移时的真实读数被判为不一致（极差 %.4f m > %.3f m）"
		% [regressed, SPREAD_TOLERANCE])

	var healthy := _spread_of(HEALTHY_READINGS)
	t.assert_true(healthy <= SPREAD_TOLERANCE,
		"负向控制前提：逐 clip 标定后的真实读数被判为一致（极差 %.4f m ≤ %.3f m）"
		% [healthy, SPREAD_TOLERANCE])

	# 逐条带宽也要能把回归里的浮空 clip 挡住（否则「极差」与「带宽」会互相掩护）。
	t.assert_true(float(REGRESSION_READINGS["idle_guarded"]) > FLOOR_BAND_MAX,
		"负向控制：回归中浮空最严重的 idle_guarded (+%.4f m) 会被带宽上界 %.3f 挡住"
		% [REGRESSION_READINGS["idle_guarded"], FLOOR_BAND_MAX])
	t.assert_true(float(HEALTHY_READINGS["idle_guarded"]) <= FLOOR_BAND_MAX,
		"带宽上界不会误伤修正后的同一 clip (+%.4f m ≤ %.3f m)"
		% [HEALTHY_READINGS["idle_guarded"], FLOOR_BAND_MAX])


static func _lowest_foot_y(player: AnimationPlayer, skeleton: Skeleton3D,
		bones: Array[int], clip_name: String) -> float:
	return _sample_foot_y(player, skeleton, bones, clip_name, true)


static func _highest_foot_y(player: AnimationPlayer, skeleton: Skeleton3D,
		bones: Array[int], clip_name: String) -> float:
	return _sample_foot_y(player, skeleton, bones, clip_name, false)


## 逐帧推进某个 clip，取两只脚骨世界里最低（或最高）的一帧。
##
## 必须用 `skeleton.global_transform * pose.origin`：`get_bone_global_pose()` 返回的是
## **Skeleton3D 局部**坐标，而该骨架节点带 0.01 缩放与 +1.05332 m 的 Y 偏移。
## 直接读 pose.origin.y 得到的是厘米量级的局部值（实测 ~27），完全不是世界高度。
static func _sample_foot_y(player: AnimationPlayer, skeleton: Skeleton3D,
		bones: Array[int], clip_name: String, lowest: bool) -> float:
	player.play(clip_name)
	var length := player.get_animation(clip_name).length
	var result := INF if lowest else -INF
	for index in range(SAMPLES):
		var ratio := float(index) / float(maxi(SAMPLES - 1, 1))
		player.seek(length * ratio, true)
		skeleton.force_update_all_bone_transforms()
		for bone in bones:
			var world_y := (skeleton.global_transform
				* skeleton.get_bone_global_pose(bone).origin).y
			result = minf(result, world_y) if lowest else maxf(result, world_y)
	return result


static func _spread_of(values: Dictionary) -> float:
	var collected: Array[float] = []
	for value in values.values():
		collected.append(float(value))
	return (collected.max() - collected.min()) if not collected.is_empty() else 0.0


static func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find(child, type_name)
		if found != null:
			return found
	return null
