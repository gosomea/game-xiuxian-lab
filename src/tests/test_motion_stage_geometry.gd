extends RefCounted
## 人物动作工作台（motion_stage）地面量具几何 / 材质机械测试。
##
## 依据 notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md 的「第五场」：
## 修复前的缺陷是「水平标记与承托面精确共面 + 透明材质 + 体积穿叠」。
## 本测试只读实例化后的真实节点，不复述实现常量：
##   - 物理地面 Floor 的碰撞盒顶面严格 y = 0，且 Floor 子树没有任何 MeshInstance3D；
##   - 水平量具的 Mesh AABB 世界 Y 区间按层严格分离，相邻间隙 >= 1.5 mm；
##   - 全部地面量具材质 transparency 关闭、albedo alpha = 1；
##   - 负向控制：用 note 记录的修复前实测区间复算，证明净空 / 不透明判据会拒绝原几何。
##
## 场景由本套件实例化并挂到 t.root()；motion_stage_playtest.gd 的 surface 批次
## 对已运行场景调用 assert_stage() 做同一组断言（同一判据、同一失败文案）。

const SCENE_PATH := "res://levels/experiments/character_movement/motion_stage.tscn"

## 相邻可见层的最小净空门限：1.5 mm，取自缺陷判据（垂直重合 <=1.5 mm 即视为共面），
## 低于实现使用的 4 mm。RulerBase 等判据不镜像实现常量，只读相对 FloorPlate 顶面的净空。
const CLEARANCE := 0.0015
const EPSILON := 0.000001

const FLOOR_PLATE := "FloorPlate"
const RUNWAY := "Runway"
const RUNWAY_BED := "Runway/RunwayBed"
const RUNWAY_CENTER := "Runway/RunwayCenterLine"
const TURN_PAD := "TurnPad"
const TURN_DISC := "TurnPad/TurnPadDisc"
const TURN_RING := "TurnPad/TurnPadRing"
const FLIGHT_PAD := "FlightPad"
const FLIGHT_DISC := "FlightPad/FlightPadDisc"
const FLIGHT_RING := "FlightPad/FlightPadRing"
const RULER_BASE := "JumpRuler/RulerBase"

## 无效区间的哨兵：节点缺失时返回；此时由缺失断言报错，层间断言不再级联。
const INVALID := Vector2(-1.0e9, -1.0e9)


static func run(t) -> void:
	t.begin_case()
	var stage := _instantiate_stage(t)
	if stage == null:
		return
	assert_stage(t, stage)
	t.begin_case()
	_negative_control(t)


## 对真实场景执行全部断言：新建实例与运行中的 playtest 场景共用同一条判据。
static func assert_stage(t, stage: Node3D) -> void:
	_assert_floor(t, stage)

	var floor_plate := _mesh_interval(t, stage, FLOOR_PLATE)
	var bed := _mesh_interval(t, stage, RUNWAY_BED)
	var center := _mesh_interval(t, stage, RUNWAY_CENTER)
	_assert_above(t, "RunwayBed", floor_plate, "FloorPlate", bed)
	_assert_above(t, "RunwayCenterLine", bed, "RunwayBed", center)
	var stripes := _stripe_nodes(stage)
	t.assert_true(stripes.size() >= 12, "跑道刻度线按米生成（实际 %d 条）" % stripes.size())
	for index in range(stripes.size()):
		_assert_above(t, "Stripe%02d" % index, center, "RunwayCenterLine", _interval_of(stripes[index]))

	_assert_pad(t, stage, TURN_PAD, TURN_DISC, TURN_RING, 8)
	_assert_pad(t, stage, FLIGHT_PAD, FLIGHT_DISC, FLIGHT_RING, 0)

	var ruler_base := _mesh_interval(t, stage, RULER_BASE)
	# RulerBase 与其他地面量具同样按「相对 FloorPlate 顶面的净空」判定，不断言「抬升 2 cm」
	# 这个实现常量（不镜像实现参数）。
	_assert_above(t, "RulerBase", floor_plate, "FloorPlate", ruler_base)

	_assert_gauge_materials(t, stage)


# --- 物理地面 ---------------------------------------------------------------


static func _assert_floor(t, stage: Node3D) -> void:
	var floor_body := stage.get_node_or_null("Floor") as StaticBody3D
	t.assert_true(floor_body != null, "Floor 是 StaticBody3D 物理地面")
	if floor_body == null:
		return
	t.assert_true(floor_body.find_children("*", "MeshInstance3D", true, false).is_empty(),
		"Floor 子树无 Mesh：物理地面不可见，不存在可见面竞争")
	var collision_shape := _first_collision_shape(floor_body)
	t.assert_true(collision_shape != null, "Floor 带 CollisionShape3D")
	if collision_shape == null:
		return
	var box := collision_shape.shape as BoxShape3D
	t.assert_true(box != null, "Floor 碰撞形状是 BoxShape3D")
	if box == null:
		return
	var interval := _box_interval(collision_shape, box.size)
	t.assert_true(absf(interval.y) <= EPSILON,
		"Floor 碰撞盒顶面严格 y=0（实际 %.6f）" % interval.y)


static func _first_collision_shape(parent: Node) -> CollisionShape3D:
	for child in parent.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


# --- 水平量具分层 -----------------------------------------------------------


## 单个圆盘区（TurnPad / FlightPad）：disc / 八辐条 / ring 的世界 Y 区间两两严格分离，
## 且全部抬到 FloorPlate 之上；不读取实现常量，只读运行时 Mesh AABB。
static func _assert_pad(t, stage: Node3D, pad_path: String, disc_path: String, ring_path: String,
		min_spokes: int) -> void:
	var pad := stage.get_node_or_null(pad_path)
	t.assert_true(pad != null, "存在 %s" % pad_path)
	if pad == null:
		return
	var floor_plate := _mesh_interval(t, stage, FLOOR_PLATE)
	var disc := _mesh_interval(t, stage, disc_path)
	var ring := _mesh_interval(t, stage, ring_path)
	var spokes: Array[Vector2] = []
	for child in pad.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("Spoke"):
			spokes.append(_interval_of(child as MeshInstance3D))
	t.assert_true(spokes.size() >= min_spokes,
		"%s 辐条数量不少于 %d（实际 %d）" % [pad_path, min_spokes, spokes.size()])
	_assert_above(t, "%s disc" % pad_path, floor_plate, "FloorPlate", disc)
	for index in range(spokes.size()):
		_assert_above(t, "%s Spoke%d" % [pad_path, index], disc, "%s disc" % pad_path, spokes[index])
	_assert_above(t, "%s ring" % pad_path, disc, "%s disc" % pad_path, ring)
	for index in range(spokes.size()):
		_assert_above(t, "%s ring" % pad_path, spokes[index], "%s Spoke%d" % [pad_path, index], ring)


## 净空判据本体：above 的底面高于 below 的顶面且间隙达标。实景断言与负向控制共用同一函数。
static func _has_clearance(above: Vector2, below: Vector2) -> bool:
	if not _interval_valid(above) or not _interval_valid(below):
		return false
	return above.x - below.y >= CLEARANCE - EPSILON


## above 的底面必须高于 below 的顶面且净空达标；任一区间无效（节点缺失）时跳过，避免级联噪声。
static func _assert_above(t, above_name: String, below: Vector2, below_name: String, above: Vector2) -> void:
	if not _interval_valid(below) or not _interval_valid(above):
		return
	var gap := above.x - below.y
	t.assert_true(gap >= CLEARANCE - EPSILON,
		"%s 底面高于 %s 顶面且净空 >= %.1f mm（实际 %.2f mm）" % [
			above_name, below_name, CLEARANCE * 1000.0, gap * 1000.0,
		])


# --- 地面量具材质 -----------------------------------------------------------


static func _assert_gauge_materials(t, stage: Node3D) -> void:
	var paths: Array[String] = [
		FLOOR_PLATE, RUNWAY_BED, RUNWAY_CENTER, RULER_BASE,
		TURN_DISC, TURN_RING, FLIGHT_DISC, FLIGHT_RING,
	]
	for pad_path in [TURN_PAD, FLIGHT_PAD]:
		var pad := stage.get_node_or_null(pad_path)
		if pad != null:
			for child in pad.get_children():
				if child is MeshInstance3D and str(child.name).begins_with("Spoke"):
					paths.append("%s/%s" % [pad_path, child.name])
	for stripe in _stripe_nodes(stage):
		paths.append("%s/%s" % [RUNWAY, stripe.name])
	for path in paths:
		var node := stage.get_node_or_null(path) as MeshInstance3D
		if node == null:
			t.assert_true(false, "地面量具节点存在：%s" % path)
			continue
		var material := node.material_override as StandardMaterial3D
		t.assert_true(material != null, "%s 使用 StandardMaterial3D 覆盖材质" % path)
		if material == null:
			continue
		t.assert_true(_material_is_opaque(material),
			"%s 材质不透明（transparency=%d，alpha=%.3f）" % [path, material.transparency, material.albedo_color.a])


static func _material_is_opaque(material: StandardMaterial3D) -> bool:
	return material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(material.albedo_color.a, 1.0)


# --- 负向控制：修复前几何必须被同一判据拒绝 ---------------------------------


## 修复前实测（note「第五场」）：FloorPlate 顶 = RunwayBed 底 = 0；RunwayBed ∈ [0, 0.012]；
## CenterLine ∈ [0.005, 0.015]；Stripe ∈ [0.008, 0.020]；disc 顶 = spoke 顶 = 0.022；
## 平放 Torus 环最低 y = -0.086（穿地）；7 个标记走 TRANSPARENCY_ALPHA 且 alpha < 1。
static func _negative_control(t) -> void:
	var old_floor_plate := Vector2(-0.04, 0.0)
	var old_bed := Vector2(0.0, 0.012)
	var old_center := Vector2(0.005, 0.015)
	var old_stripe := Vector2(0.008, 0.020)
	var old_disc := Vector2(0.012, 0.022)
	var old_spoke := Vector2(0.010, 0.022)
	var old_ring := Vector2(-0.086, 0.114)

	t.assert_false(_has_clearance(old_bed, old_floor_plate),
		"负向控制：修复前 RunwayBed 与 FloorPlate 共面（间隙 %.2f mm）被同一净空判据拒绝" % [
			(old_bed.x - old_floor_plate.y) * 1000.0,
		])
	t.assert_false(_has_clearance(old_center, old_bed),
		"负向控制：修复前 RunwayCenterLine 与 RunwayBed 穿叠（间隙 %.2f mm）被同一净空判据拒绝" % [
			(old_center.x - old_bed.y) * 1000.0,
		])
	t.assert_false(_has_clearance(old_stripe, old_center),
		"负向控制：修复前 Stripe 与 CenterLine 穿叠（间隙 %.2f mm）被同一净空判据拒绝" % [
			(old_stripe.x - old_center.y) * 1000.0,
		])
	t.assert_true(_has_clearance(old_disc, old_floor_plate),
		"负向控制边界：修复前 PadDisc 与 FloorPlate 的 12 mm 间隙本就达标，该对不在拒绝样本内" )
	t.assert_false(_has_clearance(old_spoke, old_disc),
		"负向控制：修复前 Spoke 埋进 Disc（间隙 %.2f mm）被同一净空判据拒绝" % [
			(old_spoke.x - old_disc.y) * 1000.0,
		])
	t.assert_false(_has_clearance(old_ring, old_disc),
		"负向控制：修复前平放环穿地并切进盘体（最低 %.3f m）被同一净空判据拒绝" % old_ring.x)
	t.assert_true(_has_clearance(old_floor_plate, old_floor_plate) == false,
		"负向控制：零间隙区间对会被净空判据拒绝（下界敏感度自检）")

	var old_material := StandardMaterial3D.new()
	old_material.albedo_color = Color(0.941, 0.929, 0.898, 0.9)
	old_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t.assert_false(_material_is_opaque(old_material),
		"负向控制：修复前 alpha=0.9 + TRANSPARENCY_ALPHA 会被不透明判据拒绝")


# --- 工具 -------------------------------------------------------------------


static func _instantiate_stage(t) -> Node3D:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		t.assert_true(false, "无法加载 %s" % SCENE_PATH)
		return null
	var stage := packed.instantiate() as Node3D
	t.assert_true(stage != null, "motion_stage 场景根是 Node3D")
	if stage == null:
		return null
	t.track(stage)
	return stage


static func _stripe_nodes(stage: Node3D) -> Array[MeshInstance3D]:
	var stripes: Array[MeshInstance3D] = []
	var runway := stage.get_node_or_null(RUNWAY)
	if runway == null:
		return stripes
	for child in runway.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("Stripe"):
			stripes.append(child as MeshInstance3D)
	return stripes


static func _mesh_interval(t, stage: Node3D, path: String) -> Vector2:
	var node := stage.get_node_or_null(path) as MeshInstance3D
	t.assert_true(node != null, "存在地面量具节点：%s" % path)
	if node == null or node.mesh == null:
		return INVALID
	return _interval_of(node)


## 世界空间 Mesh AABB 的 Y 区间：不读节点 position / 实现常量，直接量渲染几何。
static func _interval_of(instance: MeshInstance3D) -> Vector2:
	var world := instance.global_transform * instance.mesh.get_aabb()
	return Vector2(world.position.y, world.position.y + world.size.y)


static func _box_interval(node: Node3D, size: Vector3) -> Vector2:
	var world := node.global_transform * AABB(-size * 0.5, size)
	return Vector2(world.position.y, world.position.y + world.size.y)


static func _interval_valid(interval: Vector2) -> bool:
	return interval.x > INVALID.x * 0.5
