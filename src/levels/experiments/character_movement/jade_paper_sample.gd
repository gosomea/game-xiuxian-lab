extends Node3D

## 青玉纸白样板场景（美术方向实施，第二轮：补山水草竹与建筑群，替换人物）。
##
## 2026-09-19 v7：人物换成无仙侠衣装的中性动画底座
## （cultivator_visual_neutral_youth_v7.tscn）。旧青玉长袍视觉不再接入。
##
## 职责边界：
## - 只装配视觉与碰撞：地形 GLB（台基/台阶/铺装/收边）+ 混元生成资产（亭/松/岩/远山/山门/
##   石灯笼/竹丛）+ 程序草簇 + Godot 侧水面/石桥 + 共享角色。
## - 三能力归角色根与 res://game/abilities/ 叶子包；本场景只做输入编排、相机与 HUD。
## - 碰撞盒在本脚本内显式声明（样板规模不需要布局 JSON 机制）；地形装饰面契约由 GLB 自带
##   （压顶高出主体 0.02、踏面条高出踏步 0.02、砖面高出地面 0.02）。
## - 相机走共享 CameraRig（fixed_follow + 滚轮缩放）；HUD 走共享 LabHud；
##   输入按住状态复用实验组共享 MovementLabInput。
##
## 布局（俯视，+Z 朝出生点）：
##   中央台基+亭；南为出生点；北 14 m 山门；台阶两侧石灯笼；
##   东侧水塘（半径 4.2 m）+ 三板石桥；西侧竹丛成组；远山环带 60–140 m 靠雾成剪影。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
## 样板人物视觉自 v9 起由共享 swordsman.tscn 提供（cultivator_tripo_v9_visual.tscn）。
## 本场景不再替换 Visual：v9 已是全项目现役人物，样板换装会重新制造视觉分叉。
## 旧 v7 中性底座、旧青玉长袍与全部分件视觉保留为回退与故障对照资产，不接入本场景。
const HUD_SCRIPT := preload("res://ui/lab_hud.gd")
const RIG_SHEET: PackedScene = preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")
const InputHelper := preload("res://levels/experiments/character_movement/movement_lab_input.gd")

const TERRAIN_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_sample_terrain.glb")
const PAVILION_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_pavilion.glb")
const PINE_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_pine.glb")
const ROCK_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_rock.glb")
const MOUNTAIN_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_mountain.glb")
const GATE_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_gate.glb")
const LANTERN_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_lantern.glb")
const BAMBOO_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_bamboo.glb")
const GRASS_SCENE: PackedScene = preload("res://levels/experiments/character_movement/jade_grass.glb")

## 世界碰撞统一层：与实验组其它场景同层。
const COLLISION_LAYER := 1

## 场地：铺装区 16×16 m，边界 20 m（容纳水塘与山门），出界回收。
const PLAZA_HALF := 8.0
const BOUND := 20.0
## 地面暗底（砖缝露出的底色，albedo 线性语义；比铺装砖明显深一档，砖缝才读得出）。
const GROUND_COLOR := Color(0.10, 0.09, 0.075, 1.0)
## 远景地平：只做背景，不建碰撞、不投影。圆柱中心 y=-0.71 → 顶面 -0.21，
## 必须低于地面 0 与铺装 0.02，否则顶面会把整个地面盖住（本轮实测踩坑）。
const FLOOR_RADIUS := 300.0
const FLOOR_COLOR := Color(0.52, 0.56, 0.52, 1.0)

## 水塘：东侧；水面低饱和青蓝；基座暗环 + 石岸岩 + 不可见护环（不可趟水）。
const POND_CENTER := Vector3(11.5, 0.0, 2.5)
const POND_RADIUS := 4.2
const WATER_COLOR := Color(0.16, 0.28, 0.34, 1.0)
const BASIN_COLOR := Color(0.055, 0.075, 0.085, 1.0)

## 相机：默认近景看清角色与脚边，滚轮缩放到一屏比较样板全景。
const CAMERA_OFFSET := Vector3(13.0, 15.0, 13.5)
const CAMERA_SIZE := 18.0
const CAMERA_SIZE_MIN := 6.0
const CAMERA_SIZE_MAX := 90.0
const CAMERA_FAR := 900.0

## 布景（Pine 6 m / Rock 2.2 m 已在资产内归一；scale 只做构图变体）。
const PAVILION_YAW_DEG := 180.0
const PINES := [
	{"pos": Vector3(-7.0, 0.0, -5.0), "yaw": 20.0, "scale": 1.0},
	{"pos": Vector3(6.6, 0.0, -9.5), "yaw": 140.0, "scale": 0.9},
	{"pos": Vector3(-9.5, 0.0, 4.0), "yaw": 250.0, "scale": 0.75},
]
const ROCKS := [
	{"pos": Vector3(-8.2, 0.0, -10.5), "yaw": 190.0, "scale": 0.7},
]
const POND_ROCKS := [
	{"pos": Vector3(9.6, 0.0, 6.6), "yaw": 15.0, "scale": 0.45},
	{"pos": Vector3(13.4, 0.0, 7.0), "yaw": 75.0, "scale": 0.4},
	{"pos": Vector3(16.0, 0.0, 3.4), "yaw": 130.0, "scale": 0.5},
	{"pos": Vector3(15.2, 0.0, -1.4), "yaw": 200.0, "scale": 0.42},
	{"pos": Vector3(11.0, 0.0, -2.4), "yaw": 260.0, "scale": 0.36},
	{"pos": Vector3(7.2, 0.0, -0.6), "yaw": 310.0, "scale": 0.4},
]
const LANTERNS := [
	{"pos": Vector3(-4.2, 0.0, 5.4), "yaw": 8.0},
	{"pos": Vector3(4.2, 0.0, 5.4), "yaw": -8.0},
]
const BAMBOOS := [
	{"pos": Vector3(-11.8, 0.0, -4.2), "yaw": 0.0, "scale": 1.0},
	{"pos": Vector3(-9.9, 0.0, -7.6), "yaw": 70.0, "scale": 1.15},
	{"pos": Vector3(-13.4, 0.0, -0.6), "yaw": 150.0, "scale": 0.85},
	{"pos": Vector3(-14.2, 0.0, 8.8), "yaw": 210.0, "scale": 0.95},
]
## 远山环带：只做剪影层次，全部处于雾距（60 m 外）。
## 远山：北侧背景带 25–45 m 矮山包（正交视野 35 m 外被雾吞没、近距高墙会填满整帧；
## 甜点 = 台基正后方 6–10 m 山包剪影，成水墨中景层次，实测多轮标定）。
const MOUNTAINS := [
	{"pos": Vector3(-15.0, 0.0, -26.0), "yaw": 15.0, "scale": 0.26},
	{"pos": Vector3(1.0, 0.0, -30.0), "yaw": 0.0, "scale": 0.32},
	{"pos": Vector3(16.0, 0.0, -25.0), "yaw": -30.0, "scale": 0.28},
	{"pos": Vector3(-30.0, 0.0, -20.0), "yaw": 80.0, "scale": 0.22},
	{"pos": Vector3(29.0, 0.0, -18.0), "yaw": -70.0, "scale": 0.24},
]
## 草簇：成组聚散（方向 note §2 植被条），贴水岸、台基角、铺装边缘。
const GRASS_TUFTS := [
	{"pos": Vector3(8.6, 0.02, 7.4), "yaw": 10.0, "scale": 1.2},
	{"pos": Vector3(9.4, 0.02, 4.9), "yaw": 80.0, "scale": 0.9},
	{"pos": Vector3(14.8, 0.02, 5.8), "yaw": 150.0, "scale": 1.1},
	{"pos": Vector3(15.6, 0.02, -0.2), "yaw": 210.0, "scale": 0.85},
	{"pos": Vector3(6.9, 0.02, -3.4), "yaw": 300.0, "scale": 1.0},
	{"pos": Vector3(-7.6, 0.02, 7.8), "yaw": 40.0, "scale": 1.3},
	{"pos": Vector3(-6.8, 0.02, -8.4), "yaw": 120.0, "scale": 0.95},
	{"pos": Vector3(7.4, 0.02, -8.2), "yaw": 250.0, "scale": 1.15},
	{"pos": Vector3(-2.9, 0.02, 10.6), "yaw": 0.0, "scale": 0.8},
	{"pos": Vector3(3.1, 0.02, 10.2), "yaw": 190.0, "scale": 1.05},
	{"pos": Vector3(11.2, 0.02, 10.4), "yaw": 60.0, "scale": 0.9},
	{"pos": Vector3(-12.6, 0.02, 2.8), "yaw": 280.0, "scale": 1.1},
]
## 石桥：三板跨水塘（Godot 侧几何 + 碰撞；略拱）。
const BRIDGE_SLABS := [
	{"pos": Vector3(8.6, 0.22, 2.5), "size": Vector3(3.0, 0.16, 1.7)},
	{"pos": Vector3(11.5, 0.34, 2.5), "size": Vector3(3.2, 0.16, 1.7)},
	{"pos": Vector3(14.4, 0.22, 2.5), "size": Vector3(3.0, 0.16, 1.7)},
]

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _spawn_position := Vector3(0, 0.1, 8.0)
var _spawn_aim := Vector3(0, 0, -1)
var _rig: CameraRig
var _input := InputHelper.new()
var _hud: LabHud


func _ready() -> void:
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "jade_paper_sample: 场景必须提供 Camera3D")
	_build_ground()
	_build_water_and_bridge()
	_build_world_visual()
	_build_collision()
	_build_boundaries()
	_spawn_player()
	_build_rig()
	_build_hud()
	_update_status()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if _input.track_key(key_event, InputHelper.VERTICAL_KEYS):
			if InputHelper.key_code(key_event) == InputHelper.KEY_VERTICAL_UP \
					and InputHelper.is_key_down_edge(key_event) and _player != null:
				_player.press_jump()
			get_viewport().set_input_as_handled()
			return
		if InputHelper.is_key_down_edge(key_event):
			var code := InputHelper.key_code(key_event)
			if code == KEY_F and _player != null:
				_player.press_flight_toggle()
				get_viewport().set_input_as_handled()
				return
			if code == KEY_R:
				get_viewport().set_input_as_handled()
				_reset_experiment()
				return
			if event.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				_return_to_hub()
				return


func _physics_process(_delta: float) -> void:
	if _player == null or _motion == null:
		return
	var right := _rig.right_axis() if _rig != null else Vector3.RIGHT
	var forward := _rig.forward_axis() if _rig != null else Vector3.FORWARD
	var move := _input.move_input()
	_player.set_move_input(move)
	_player.set_vertical_input(_input.vertical_input())
	if move != Vector2.ZERO:
		var direction := right * move.x - forward * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())
	_check_fall_out()


func _process(_delta: float) -> void:
	_update_status()


func _build_rig() -> void:
	var rig := RIG_SHEET.instantiate() as CameraRig
	assert(rig != null, "jade_paper_sample: camera_rig_sheet.tscn 根节点必须是 CameraRig")
	rig.name = "CameraRig"
	add_child(rig)
	_rig = rig
	var config := CameraRigConfig.new()
	var radius := CAMERA_OFFSET.length()
	config.start_mode = "fixed_follow"
	config.follow_preset = "smooth"
	config.distance = radius
	config.pitch_degrees = rad_to_deg(asin(CAMERA_OFFSET.y / maxf(radius, 0.001)))
	config.yaw_degrees = rad_to_deg(atan2(CAMERA_OFFSET.x, CAMERA_OFFSET.z))
	config.size = CAMERA_SIZE
	config.size_min = CAMERA_SIZE_MIN
	config.size_max = CAMERA_SIZE_MAX
	config.zoom_step = 4.0
	config.smooth_time = 1.0 / 4.0
	config.near = 0.1
	config.far = CAMERA_FAR
	config.mode_choices = PackedStringArray(["fixed_follow"])
	config.enable_mode_selection_keys = false
	config.enable_preset_key = false
	config.enable_zoom_keys = false
	config.enable_zoom_wheel = true
	config.enable_yaw_keys = false
	config.consume_unowned_rmb = true
	rig.bind(_camera, _player, config)


func _check_fall_out() -> void:
	# 场地是平地，只有真正掉出边界（不可能事件兜底）才回收。
	if _player.global_position.y < -4.0:
		push_warning("jade_paper_sample: 角色掉出场地（y=%.2f），回收至 spawn" % _player.global_position.y)
		_reset_experiment()


func rig() -> CameraRig:
	return _rig


func _clear_pressed() -> void:
	_input.clear()
	if _player != null:
		_player.clear_input()


func _reset_experiment() -> void:
	_clear_pressed()
	_player.global_position = _spawn_position
	_player.reset_motion()
	_player.set_aim_direction(_spawn_aim)
	if _rig != null:
		_rig.reset_state()


func _return_to_hub() -> void:
	_clear_pressed()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	if result != OK:
		push_error("jade_paper_sample: 返回子实验目录失败，错误码 %d" % result)

# --- 视觉装配 -------------------------------------------------------------


## 地面暗底 + 远景地平。地面接收阴影；远景盘不受光、不投影、不碰撞。
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(BOUND * 2.0, BOUND * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	material.roughness = 0.95
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = material
	_world().add_child(ground)

	var disc := CylinderMesh.new()
	disc.top_radius = FLOOR_RADIUS
	disc.bottom_radius = FLOOR_RADIUS
	disc.height = 1.0
	disc.radial_segments = 96
	disc.rings = 0
	var far_material := StandardMaterial3D.new()
	far_material.albedo_color = FLOOR_COLOR
	far_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	far_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	far_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var distant := MeshInstance3D.new()
	distant.name = "DistantFloor"
	distant.mesh = disc
	distant.material_override = far_material
	distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 圆柱中心 y=-0.71 → 顶面 -0.21，必须低于地面 0 与铺装 0.02（实测踩坑）。
	distant.position = Vector3(0.0, -0.71, 0.0)
	_world().add_child(distant)


## 水塘：暗色基座环 + 水面 + 三板石桥。水面不投影（避免大面积阴影 acne），不建碰撞由护环负责。
func _build_water_and_bridge() -> void:
	var root := Node3D.new()
	root.name = "Pond"
	_world().add_child(root)

	var basin := CylinderMesh.new()
	basin.top_radius = POND_RADIUS + 0.4
	basin.bottom_radius = POND_RADIUS + 0.4
	basin.height = 0.02
	basin.radial_segments = 48
	var basin_material := StandardMaterial3D.new()
	basin_material.albedo_color = BASIN_COLOR
	basin_material.roughness = 1.0
	var basin_node := MeshInstance3D.new()
	basin_node.name = "Basin"
	basin_node.mesh = basin
	basin_node.material_override = basin_material
	basin_node.position = POND_CENTER + Vector3(0.0, 0.012, 0.0)
	basin_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(basin_node)

	var water := CylinderMesh.new()
	water.top_radius = POND_RADIUS
	water.bottom_radius = POND_RADIUS
	water.height = 0.02
	water.radial_segments = 48
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = WATER_COLOR
	water_material.roughness = 0.18
	water_material.metallic = 0.2
	var water_node := MeshInstance3D.new()
	water_node.name = "Water"
	water_node.mesh = water
	water_node.material_override = water_material
	water_node.position = POND_CENTER + Vector3(0.0, 0.045, 0.0)
	water_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water_node)

	# 石桥：略拱三板，材质复用地形石色（Godot 侧 albedo 与 GLB 显示口径一致）。
	var slab_material := StandardMaterial3D.new()
	slab_material.albedo_color = Color(0.212, 0.177, 0.119, 1.0)
	slab_material.roughness = 0.9
	for i in range(BRIDGE_SLABS.size()):
		var spec: Dictionary = BRIDGE_SLABS[i]
		var box := BoxMesh.new()
		box.size = spec["size"]
		var slab := MeshInstance3D.new()
		slab.name = "BridgeSlab%d" % (i + 1)
		slab.mesh = box
		slab.material_override = slab_material
		slab.position = spec["pos"]
		root.add_child(slab)


## 美术 GLB：地形 + 亭 + 松 + 岩 + 山门 + 灯笼 + 竹 + 草 + 远山 + 水岸岩。
func _build_world_visual() -> void:
	var terrain := TERRAIN_SCENE.instantiate() as Node3D
	terrain.name = "JadeTerrain"
	_world().add_child(terrain)

	var pavilion := PAVILION_SCENE.instantiate() as Node3D
	pavilion.name = "JadePavilion"
	pavilion.position = Vector3(0, 0.6, 0)
	pavilion.rotation_degrees = Vector3(0, PAVILION_YAW_DEG, 0)
	_world().add_child(pavilion)

	for i in range(PINES.size()):
		var spec: Dictionary = PINES[i]
		var pine := PINE_SCENE.instantiate() as Node3D
		pine.name = "JadePine%d" % (i + 1)
		pine.position = spec["pos"]
		pine.rotation_degrees = Vector3(0, spec["yaw"], 0)
		pine.scale = Vector3.ONE * float(spec["scale"])
		_world().add_child(pine)

	for i in range(ROCKS.size()):
		var spec: Dictionary = ROCKS[i]
		var rock := ROCK_SCENE.instantiate() as Node3D
		rock.name = "JadeRock%d" % (i + 1)
		rock.position = spec["pos"]
		rock.rotation_degrees = Vector3(0, spec["yaw"], 0)
		rock.scale = Vector3.ONE * float(spec["scale"])
		_world().add_child(rock)

	for i in range(POND_ROCKS.size()):
		var spec: Dictionary = POND_ROCKS[i]
		var rock := ROCK_SCENE.instantiate() as Node3D
		rock.name = "PondRock%d" % (i + 1)
		rock.position = spec["pos"]
		rock.rotation_degrees = Vector3(0, spec["yaw"], 0)
		rock.scale = Vector3.ONE * float(spec["scale"])
		_world().add_child(rock)

	for i in range(LANTERNS.size()):
		var spec: Dictionary = LANTERNS[i]
		var lantern := LANTERN_SCENE.instantiate() as Node3D
		lantern.name = "JadeLantern%d" % (i + 1)
		lantern.position = spec["pos"]
		lantern.rotation_degrees = Vector3(0, spec["yaw"], 0)
		_world().add_child(lantern)

	var gate := GATE_SCENE.instantiate() as Node3D
	gate.name = "JadeGate"
	gate.position = Vector3(0, 0, -14)
	_world().add_child(gate)

	for i in range(BAMBOOS.size()):
		var spec: Dictionary = BAMBOOS[i]
		var bamboo := BAMBOO_SCENE.instantiate() as Node3D
		bamboo.name = "JadeBamboo%d" % (i + 1)
		bamboo.position = spec["pos"]
		bamboo.rotation_degrees = Vector3(0, spec["yaw"], 0)
		bamboo.scale = Vector3.ONE * float(spec["scale"])
		_world().add_child(bamboo)

	for i in range(GRASS_TUFTS.size()):
		var spec: Dictionary = GRASS_TUFTS[i]
		var tuft := GRASS_SCENE.instantiate() as Node3D
		tuft.name = "JadeGrass%d" % (i + 1)
		tuft.position = spec["pos"]
		tuft.rotation_degrees = Vector3(0, spec["yaw"], 0)
		tuft.scale = Vector3.ONE * float(spec["scale"])
		_world().add_child(tuft)

	for i in range(MOUNTAINS.size()):
		var spec: Dictionary = MOUNTAINS[i]
		var mountain := MOUNTAIN_SCENE.instantiate() as Node3D
		mountain.name = "JadeMountain%d" % (i + 1)
		mountain.position = spec["pos"]
		mountain.rotation_degrees = Vector3(0, spec["yaw"], 0)
		mountain.scale = Vector3.ONE * float(spec["scale"])
		_world().add_child(mountain)

# --- 碰撞（样板规模：显式盒，不引入布局 JSON） -----------------------------


func _build_collision() -> void:
	var container := Node3D.new()
	container.name = "Collision"
	_world().add_child(container)
	# 地面板：顶面 0.02 与铺装砖面齐平（砖缝只是视觉，1 cm 收边沿可走上去）。
	_add_box(container, "Floor", Vector3(0, -0.03, 0), Vector3(BOUND * 2, 0.1, BOUND * 2))
	# 台基与台阶（与地形 GLB 同数值）。
	_add_box(container, "Platform", Vector3(0, 0.3, 0), Vector3(6.44, 0.6, 6.44))
	_add_box(container, "Step1", Vector3(0, 0.1, 3.425), Vector3(2.4, 0.2, 0.45))
	_add_box(container, "Step2", Vector3(0, 0.2, 3.875), Vector3(2.4, 0.4, 0.45))
	# 树干与岩石：粗盒近似，样板不做精确壳。
	for i in range(PINES.size()):
		var spec: Dictionary = PINES[i]
		var pos: Vector3 = spec["pos"]
		var s := float(spec["scale"])
		_add_box(container, "PineTrunk%d" % (i + 1),
			Vector3(pos.x, 3.0 * s, pos.z), Vector3(0.7 * s, 6.0 * s, 0.7 * s))
	for i in range(ROCKS.size()):
		var spec: Dictionary = ROCKS[i]
		var pos: Vector3 = spec["pos"]
		var s := float(spec["scale"])
		_add_box(container, "RockBody%d" % (i + 1),
			Vector3(pos.x, 1.0 * s, pos.z), Vector3(1.7 * s, 2.0 * s, 1.6 * s))
	# 竹丛根部：细盒防穿。
	for i in range(BAMBOOS.size()):
		var spec: Dictionary = BAMBOOS[i]
		var pos: Vector3 = spec["pos"]
		var s := float(spec["scale"])
		_add_box(container, "BambooRoot%d" % (i + 1),
			Vector3(pos.x, 0.6 * s, pos.z), Vector3(1.1 * s, 1.2 * s, 1.1 * s))
	# 山门柱：中门可走，两侧柱体近似（宽门按 4.5 m 净宽留白）。
	_add_box(container, "GatePostWest", Vector3(-2.9, 1.8, -14.0), Vector3(1.2, 3.6, 1.2))
	_add_box(container, "GatePostEast", Vector3(2.9, 1.8, -14.0), Vector3(1.2, 3.6, 1.2))
	# 石灯笼座。
	for i in range(LANTERNS.size()):
		var spec: Dictionary = LANTERNS[i]
		var pos: Vector3 = spec["pos"]
		_add_box(container, "LanternBase%d" % (i + 1),
			Vector3(pos.x, 0.45, pos.z), Vector3(0.7, 0.9, 0.7))
	# 水塘护环：10 段切向不可见墙，不可趟水。
	var segments := 10
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		var wall_pos := POND_CENTER + Vector3(cos(angle) * (POND_RADIUS + 0.35), 0.3,
			sin(angle) * (POND_RADIUS + 0.35))
		var wall := _add_box(container, "PondRim%d" % (i + 1), wall_pos,
			Vector3(2.9, 0.6, 0.7))
		wall.rotation.y = -angle
	# 石桥踏步：三板 + 台面（0.22/0.34 拱高差用小台阶过渡）。
	for i in range(BRIDGE_SLABS.size()):
		var spec: Dictionary = BRIDGE_SLABS[i]
		var pos: Vector3 = spec["pos"]
		var size: Vector3 = spec["size"]
		_add_box(container, "BridgeDeck%d" % (i + 1),
			pos, size)
	_add_box(container, "BridgeStepWest", Vector3(7.0, 0.11, 2.5), Vector3(0.9, 0.22, 1.7))
	_add_box(container, "BridgeStepEast", Vector3(16.0, 0.11, 2.5), Vector3(0.9, 0.22, 1.7))


func _build_boundaries() -> void:
	var root := Node3D.new()
	root.name = "Boundaries"
	_world().add_child(root)
	var thickness := 2.0
	var height := 8.0
	_add_box(root, "West", Vector3(-BOUND - thickness * 0.5, height * 0.5, 0),
		Vector3(thickness, height, BOUND * 2 + thickness * 2))
	_add_box(root, "East", Vector3(BOUND + thickness * 0.5, height * 0.5, 0),
		Vector3(thickness, height, BOUND * 2 + thickness * 2))
	_add_box(root, "North", Vector3(0, height * 0.5, -BOUND - thickness * 0.5),
		Vector3(BOUND * 2 + thickness * 2, height, thickness))
	_add_box(root, "South", Vector3(0, height * 0.5, BOUND + thickness * 0.5),
		Vector3(BOUND * 2 + thickness * 2, height, thickness))


func _add_box(parent: Node3D, box_name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = center
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = COLLISION_LAYER
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	return body


func _world() -> Node3D:
	var world := get_node_or_null("World") as Node3D
	if world == null:
		world = Node3D.new()
		world.name = "World"
		add_child(world)
	return world


func _spawn_player() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "jade_paper_sample: swordsman.tscn 根节点必须是 Swordsman")
	# 不再替换 Visual：swordsman.tscn 已直达 v9 视觉。
	# 历史上本场景在入树前换掉 Visual（v7 特例）；v9 统一后该替换只会制造第二套装配路径。
	assert(actor.get_node_or_null("Visual/CultivatorTripoV9") != null,
		"jade_paper_sample: 默认角色未装入 v9 视觉模型")
	actor.name = "Swordsman"
	add_child(actor)
	_player = actor
	_motion = actor.motion()
	assert(_motion != null, "jade_paper_sample: 角色缺少 SwordsmanMotionComponent")
	assert(actor.get_node_or_null("Visual/CultivatorSkeletonPresentation") != null,
		"jade_paper_sample: v9 骨骼表现层未接入正式角色")
	assert(actor.get_node_or_null("Visual/FlyingSword") != null,
		"jade_paper_sample: v9 视觉下御剑视觉必须仍由 ActorAssembly 装配")
	actor.reset_motion()
	actor.global_position = _spawn_position
	actor.set_aim_direction(_spawn_aim)

# --- HUD ------------------------------------------------------------------


func _build_hud() -> void:
	_hud = HUD_SCRIPT.new()
	add_child(_hud)
	_hud.configure("JADE", "青玉纸白 · 样板", "方向样板的观感与可读性是否成立？")
	_hud.set_controls("WASD / 方向键 移动 · Space 跳跃 / 上升 · Ctrl 下降 · F 御剑 · 滚轮缩放 · R 复位 · Esc 返回子实验目录")
	_hud.set_question("青玉瓦 / 暖木 / 靛青角色 / 水墨远景的组合在实机中是否成立？")
	_hud.set_return_text("返回子实验目录")
	_hud.return_pressed.connect(_return_to_hub)
	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.pressed.connect(_reset_experiment)
	_hud.add_button(reset_button)


func _update_status() -> void:
	if _hud == null or _motion == null or _player == null:
		return
	var state := "步行"
	if _motion.flight_active:
		state = "御剑"
	elif not _motion.on_floor:
		state = "空中"
	_hud.set_status("状态：%s  ·  高度 %.1f m" % [state, _player.global_position.y])
