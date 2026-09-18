extends Node3D

## 群山宗门移动探索场景（本轮入口）。
##
## 职责边界（依据 docs/experiments/traversal-contract.md 与 docs/art/mountain_realm/layout-contract.md）：
## - 平面移动 / 跳跃 / 御剑三能力归角色根与 res://game/abilities/ 叶子包；本场景只做输入编排、
##   布局装配、边界约束、相机与 HUD，不复制任何能力逻辑，不直接改 velocity。
## - 布局坐标真源为同目录 mountain_realm_layout.json，本场景只消费不生成。
## - 山体碰撞壳 mountain_realm_collision.glb 只提取网格生成 StaticBody3D + trimesh，不做可见渲染。
## - 美术资源均为 preload 硬依赖：资源缺失即脚本加载失败，不静默降级、不伪造可运行入口。
## - 御剑视觉由 ActorAssembly/FlightBundle 随飞行行为统一装配（本场景不再手动绑剑）。
## - 相机走共享 CameraRig（唯一 executor）+ bounds focus clamp；HUD 走共享 LabHud；
##   移动/升降按住状态复用实验组共享 MovementLabInput。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const HUD_SCRIPT := preload("res://ui/lab_hud.gd")
const RIG_SHEET: PackedScene = preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")
const InputHelper := preload("res://levels/experiments/character_movement/movement_lab_input.gd")

const VISUAL_PATH := "res://levels/experiments/character_movement/mountain_realm.glb"
const LAYOUT_PATH := "res://levels/experiments/character_movement/mountain_realm_layout.json"
const VISUAL_SCENE: PackedScene = preload("res://levels/experiments/character_movement/mountain_realm.glb")
const SHELL_PATH := "res://levels/experiments/character_movement/mountain_realm_collision.glb"
const SHELL_SCENE: PackedScene = preload("res://levels/experiments/character_movement/mountain_realm_collision.glb")
const LAYOUT_SCHEMA := "mountain_realm_layout/1"

## 庭院产物（正式依赖，随场景一起交付）。
const COURTYARD_VISUAL_PATH := "res://levels/experiments/character_movement/mountain_realm_courtyards.glb"
const COURTYARD_COLLISION_PATH := "res://levels/experiments/character_movement/mountain_realm_courtyards_collision.json"
const COURTYARD_SCHEMA := "peak_courtyards_collision/1"
const COURTYARD_VISUAL: PackedScene = preload("res://levels/experiments/character_movement/mountain_realm_courtyards.glb")

## 世界碰撞统一层：山体 / 盒体 / 边界 / 角色同层，契约不引入额外碰撞层。
const COLLISION_LAYER := 1

## 远景地平：地形之外的连续远地面，让地面越过地形边界继续延伸到雾里。
## 只做背景，不建碰撞、不进 World/BoxCollision，不改变可玩区。
const FLOOR_RADIUS := 2200.0
const FLOOR_Y := -2.6
const FLOOR_COLOR := Color(0.478431, 0.537255, 0.490196, 1.0)

## 浅色石材过曝校正：只在场景侧复制材质并降低反照率，不改动美术 GLB 与源材质。
## glTF baseColorFactor 是线性值，Ivory paving 0.78 本身已接近显示白，必须压到中间调。
const BRIGHT_MATERIAL_KEYS := ["ivory", "plaster", "limestone", "step stone"]
const BRIGHT_ALBEDO_SCALE := 0.55

## 固定俯视方向，跟随目标 XYZ。默认取近景（能看清角色与脚边地面），滚轮到远景看群山。
## 相机位姿由共享 CameraRig 独占写；本场景只提供构图参数与可选模式开关。
const CAMERA_OFFSET := Vector3(15.0, 19.0, 16.5)
const CAMERA_SIZE := 30.0
const CAMERA_SIZE_MIN := 7.0
## 上限收紧：再远就会露出地形截断面，而不是"更开阔的群山"。
const CAMERA_SIZE_MAX := 170.0
const CAMERA_FOLLOW_SPEED := 4.0
const CAMERA_FAR := 600.0

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _layout: Dictionary = {}
var _spawn_position := Vector3.ZERO
var _spawn_aim := Vector3.FORWARD
var _bounds_min := Vector3.ZERO
var _bounds_max := Vector3.ZERO
var _fall_out_y := -6.0
var _rig: CameraRig
## 输入按住状态复用实验组共享 helper（与 camera_lab / motion_stage / ground / sword 同一实现）。
var _input := InputHelper.new()
var _hud: LabHud


func _ready() -> void:
	# 进入本场景开 4x MSAA（大场景轮廓多），离开时恢复进入前的值，不把状态泄漏给目录等其他场景。
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "mountain_realm: 场景必须提供 Camera3D")
	# projection / size / near / far 由 CameraRig 按 Config 独占写；本场景不写相机参数。
	_read_layout()
	_build_visual()
	_build_shell_collision()
	_build_box_collision()
	_build_courtyard_overlay()
	_build_distant_floor()
	_build_boundaries()
	_build_landing_points()
	_spawn_player()
	_build_rig()
	_build_hud()
	_update_status()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	# 失焦只清输入（水平 / 升降 / 跳跃边沿 / F 边沿）：已开启的御剑保持悬停，
	# 不自动关飞、不坠落；只有 R 关闭飞行并清账（见 traversal-contract「场景调用 API 与失焦」）。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		# 共享 helper 管移动键与升降键的按住状态；本场景只决定语义边沿。
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
	# 滚轮缩放由共享 CameraRig 处理；本场景不再写相机 size。


func _physics_process(delta: float) -> void:
	if _player == null or _motion == null:
		return
	# 相机地面基由 CameraRig 桥接写入角色；本场景只读它来定朝向。
	var right := _rig.right_axis() if _rig != null else Vector3.RIGHT
	var forward := _rig.forward_axis() if _rig != null else Vector3.FORWARD
	var move := _input.move_input()
	_player.set_move_input(move)
	_player.set_vertical_input(_input.vertical_input())
	# 角色朝运动方向；停下时不写朝向，由角色保留最后一次朝向。
	if move != Vector2.ZERO:
		var direction := right * move.x - forward * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())
	_check_fall_out()


func _process(_delta: float) -> void:
	_update_status()


## 装配共享 CameraRig：bounds 转 focus clamp，保留原构图、跟随速度与缩放范围；
## 大空间不占用 1-4 模式键（群山自己的 R / F / 滚轮是实验控制）。
func _build_rig() -> void:
	var rig := RIG_SHEET.instantiate() as CameraRig
	assert(rig != null, "mountain_realm: camera_rig_sheet.tscn 根节点必须是 CameraRig")
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
	config.zoom_step = 6.0
	config.smooth_time = 1.0 / maxf(CAMERA_FOLLOW_SPEED, 0.001)
	config.focus_clamp_enabled = true
	config.focus_clamp_min = _bounds_min
	config.focus_clamp_max = _bounds_max
	# 高空必须跟随：不能把焦点压到 y=0（focus_clamp_y_enabled 保留真实 y，见镜头契约）。
	config.focus_clamp_y_enabled = true
	config.near = 0.1
	config.far = CAMERA_FAR
	config.mode_choices = PackedStringArray(["fixed_follow"])
	config.enable_mode_selection_keys = false
	config.enable_preset_key = false
	config.enable_zoom_keys = false
	config.enable_zoom_wheel = true
	config.enable_yaw_keys = false
	# 未归属 RMB：fixed_follow 下消费世界区域右键但不捕获，避免右键泄漏到宿主视图。
	config.consume_unowned_rmb = true
	rig.bind(_camera, _player, config)


func _ground_vector(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


## 掉出 bounds 下沿才回收：回到 spawn 并走 R 的同一套清理（含关闭御剑）。
func _check_fall_out() -> void:
	if _player.global_position.y < _fall_out_y:
		push_warning("mountain_realm: 角色掉出探索区（y=%.2f），回收至 spawn" % _player.global_position.y)
		_reset_experiment()


## 公开只读访问器：验收脚本经此读 CameraRig，而不是绕过它写 Camera3D。
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
		push_error("mountain_realm: 返回子实验目录失败，错误码 %d" % result)

# --- 布局装配 -------------------------------------------------------------


## 读取并校验布局 JSON；坐标只在运行时从 JSON 取，不硬编码文档里的早期数值。
func _read_layout() -> void:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	assert(not text.is_empty(), "mountain_realm: 无法读取布局 %s" % LAYOUT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "mountain_realm: 布局 JSON 顶层必须是对象")
	_layout = parsed as Dictionary
	assert(str(_layout.get("schema", "")) == LAYOUT_SCHEMA, "mountain_realm: 布局 schema 必须为 %s" % LAYOUT_SCHEMA)
	assert(str(_layout.get("units", "")) == "meters", "mountain_realm: 布局 units 必须为 meters")
	assert(str(_layout.get("up_axis", "")) == "Y", "mountain_realm: 布局 up_axis 必须为 Y")
	for key in ["bounds", "spawn", "landing_points", "boxes", "collision"]:
		assert(_layout.has(key), "mountain_realm: 布局缺少字段 %s" % key)
	var bounds: Dictionary = _layout["bounds"]
	_bounds_min = _vector3(bounds["min"])
	_bounds_max = _vector3(bounds["max"])
	_fall_out_y = float(bounds.get("fall_out_y", _bounds_min.y))
	assert(_bounds_min.x < _bounds_max.x and _bounds_min.y < _bounds_max.y and _bounds_min.z < _bounds_max.z,
		"mountain_realm: bounds min 必须严格小于 max")
	var spawn: Dictionary = _layout["spawn"]
	_spawn_position = _vector3(spawn["position"])
	var yaw := deg_to_rad(float(spawn.get("yaw_deg", 0.0)))
	# 与世界朝向一致：Visual 局部 -Z 为正面，rotation.y = atan2(-aim.x, -aim.z)。
	_spawn_aim = Vector3(-sin(yaw), 0.0, -cos(yaw))


func _vector3(value: Variant) -> Vector3:
	assert(value is Array and (value as Array).size() == 3, "mountain_realm: 坐标必须是长度 3 的数组")
	var values := value as Array
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


## 布局中 rect 类字段（landing_points/center、mountains/base/center）是 [x, z] 两元组，
## y 由 top_y 等字段单独给出；不按 3 元组读，也不改 schema。
func _vector2_xz(value: Variant, field: String) -> Vector2:
	assert(value is Array and (value as Array).size() == 2,
		"mountain_realm: %s 必须是长度 2 的 [x, z] 数组" % field)
	var values := value as Array
	return Vector2(float(values[0]), float(values[1]))


func _world() -> Node3D:
	var world := get_node_or_null("World") as Node3D
	if world == null:
		world = Node3D.new()
		world.name = "World"
		add_child(world)
	return world


## 实例化 preload 的美术子场景；根节点类型不符立即失败，不静默跳过。
func _instantiate_glb(scene: PackedScene, path: String) -> Node3D:
	var instance := scene.instantiate()
	assert(instance is Node3D, "mountain_realm: %s 根节点必须是 Node3D" % path)
	return instance as Node3D


## 地形视觉：只关闭主高度场节点 Terrain 的 cast_shadow。
## 原因：大面积起伏高度场在大范围方向光阴影图下产生碎块状阴影痤疮（同视角关阴影即消失，见
## docs/experiments/mountain-visual-integration.md 的诊断记录）；提高 normal_bias / 收紧阴影距离
## 只能减轻不能稳定消除。Terrain 仍然接收阴影，因此建筑、树、角色仍会在其表面投影，接地感保留。
## 同 GLB 内的松树与灌木保持默认投射，否则会出现"树悬浮"的观感。
## 限制：山体自身不再向谷地投远大阴影，远景层次靠雾与明暗面区分。
func _build_visual() -> void:
	var visual := _instantiate_glb(VISUAL_SCENE, VISUAL_PATH)
	visual.name = "MountainVisual"
	# 只认主高度场这一个节点：名字必须精确匹配 Terrain，且必须恰好 1 个；找不到即装配失败，
	# 不允许退化成"全部关闭"或"一个都不关"。
	var terrain_count := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.name != "Terrain":
			continue
		terrain_count += 1
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	assert(terrain_count == 1,
		"mountain_realm: 地形主高度场节点 Terrain 应恰好 1 个，实际 %d 个" % terrain_count)
	_world().add_child(visual)


## 碰撞壳只做物理：提取每个 MeshInstance3D 的 trimesh 到同名 StaticBody3D，然后释放可见源节点。
## 节点路径稳定为 World/ShellCollision/<碰撞壳节点名>，便于集成测试按本体断言。
func _build_shell_collision() -> void:
	var container := Node3D.new()
	container.name = "ShellCollision"
	_world().add_child(container)
	var declared_shell := str((_layout["collision"] as Dictionary).get("shell_glb", ""))
	assert(declared_shell == SHELL_SCENE.resource_path,
		"mountain_realm: 布局声明的碰撞壳 %s 与场景装配的 %s 不一致" % [declared_shell, SHELL_SCENE.resource_path])
	var shell := _instantiate_glb(SHELL_SCENE, SHELL_PATH)
	shell.name = "ShellSource"
	shell.visible = false
	add_child(shell)
	var mesh_nodes := shell.find_children("*", "MeshInstance3D", true, false)
	assert(not mesh_nodes.is_empty(), "mountain_realm: 碰撞壳未包含任何 MeshInstance3D")
	for node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		var shape: Shape3D = mesh.create_trimesh_shape() if mesh != null else null
		assert(shape != null, "mountain_realm: 碰撞网格 %s 无法生成 trimesh" % mesh_instance.name)
		var body := StaticBody3D.new()
		body.name = mesh_instance.name
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = COLLISION_LAYER
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		shape_node.shape = shape
		body.add_child(shape_node)
		container.add_child(body)
		body.global_transform = mesh_instance.global_transform
	shell.queue_free()
	assert(container.get_child_count() > 0, "mountain_realm: 碰撞壳未生成任何碰撞体")


## 盒体严格按 JSON 建实体：节点名 = JSON name，位置 = center，尺寸 = size；不猜测、不合并、不挖空。
func _build_box_collision() -> void:
	var container := Node3D.new()
	container.name = "BoxCollision"
	_world().add_child(container)
	var boxes: Array = _layout["boxes"]
	var created := 0
	for value in boxes:
		var box: Dictionary = value
		var box_name := str(box.get("name", ""))
		assert(not box_name.is_empty(), "mountain_realm: boxes 条目缺少 name")
		assert(bool(box.get("solid", true)),
			"mountain_realm: 盒 %s 标记为非实体，但布局契约要求 boxes 每项都是实体" % box_name)
		var size := _vector3(box["size"])
		assert(size.x > 0.0 and size.y > 0.0 and size.z > 0.0, "mountain_realm: 盒 %s 尺寸必须为正" % box_name)
		var body := StaticBody3D.new()
		body.name = box_name
		body.position = _vector3(box["center"])
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = COLLISION_LAYER
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
		container.add_child(body)
		created += 1
	assert(created == boxes.size(),
		"mountain_realm: 布局有 %d 个盒但只建了 %d 个碰撞体" % [boxes.size(), created])


## 庭院层：视觉与 solid 盒均为正式依赖（preload + schema 断言）；原 layout 75 盒不动。
## 额外做一次浅色材质校正：复制实例内材质并降低反照率，避免铺地/粉墙在日光下压成纯白。
func _build_courtyard_overlay() -> void:
	_build_courtyard_boxes(_read_courtyard_collision())
	var visual := _instantiate_glb(COURTYARD_VISUAL, COURTYARD_VISUAL_PATH)
	visual.name = "CourtyardVisual"
	_tone_down_bright_materials(visual)
	_world().add_child(visual)


## 浅色石材反照率校正：只改本实例的材质副本（duplicate），不影响美术 GLB 源材质与旧庭院。
func _tone_down_bright_materials(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface)
			if material == null:
				continue
			var key := material.resource_name.to_lower()
			if not _is_bright_material(key):
				continue
			var copy := material.duplicate() as BaseMaterial3D
			if copy == null:
				continue
			copy.albedo_color = Color(
				copy.albedo_color.r * BRIGHT_ALBEDO_SCALE,
				copy.albedo_color.g * BRIGHT_ALBEDO_SCALE,
				copy.albedo_color.b * BRIGHT_ALBEDO_SCALE,
				copy.albedo_color.a
			)
			mesh_instance.set_surface_override_material(surface, copy)


func _is_bright_material(material_name: String) -> bool:
	for key in BRIGHT_MATERIAL_KEYS:
		if material_name.contains(key):
			return true
	return false


## 读庭院附加碰撞 JSON 并校验 schema；box 与 layout 同格式（center 三元组 + size 三元组）。
func _read_courtyard_collision() -> Array:
	var text := FileAccess.get_file_as_string(COURTYARD_COLLISION_PATH)
	assert(not text.is_empty(), "mountain_realm: 无法读取庭院碰撞 %s" % COURTYARD_COLLISION_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "mountain_realm: 庭院碰撞 JSON 顶层必须是对象")
	var data := parsed as Dictionary
	assert(str(data.get("schema", "")) == COURTYARD_SCHEMA,
		"mountain_realm: 庭院碰撞 schema 必须为 %s" % COURTYARD_SCHEMA)
	assert(data.get("boxes") is Array, "mountain_realm: 庭院碰撞缺少 boxes 数组")
	return data["boxes"] as Array


## 庭院盒放入独立容器 World/CourtyardCollision：原 World/BoxCollision 仍恰好 75 个布局盒，
## 既有集成断言（数量与逐盒路径）不受附加层影响；跨容器重名仍在装配期直接失败。
func _build_courtyard_boxes(boxes: Array) -> void:
	var layout_container := _world().get_node_or_null("BoxCollision") as Node3D
	assert(layout_container != null, "mountain_realm: BoxCollision 容器未建立")
	var container := Node3D.new()
	container.name = "CourtyardCollision"
	_world().add_child(container)
	for value in boxes:
		var box: Dictionary = value
		var box_name := str(box.get("name", ""))
		assert(not box_name.is_empty(), "mountain_realm: 庭院盒缺少 name")
		assert(layout_container.get_node_or_null(box_name) == null and container.get_node_or_null(box_name) == null,
			"mountain_realm: 庭院盒 %s 与已有碰撞盒重名，拒绝覆盖" % box_name)
		var size := _vector3(box["size"])
		assert(size.x > 0.0 and size.y > 0.0 and size.z > 0.0, "mountain_realm: 庭院盒 %s 尺寸必须为正" % box_name)
		var body := StaticBody3D.new()
		body.name = box_name
		body.position = _vector3(box["center"])
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = COLLISION_LAYER
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
		container.add_child(body)


## 远景地平：不受光的大圆盘垫在地形最低点之下，让地面越出地形边界继续延伸到雾中，
## 从而不再出现"地形矩形切到天空"的硬边；不参与碰撞，也不投影。
func _build_distant_floor() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = FLOOR_RADIUS
	mesh.bottom_radius = FLOOR_RADIUS
	mesh.height = 1.0
	mesh.radial_segments = 96
	mesh.rings = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = FLOOR_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.name = "DistantFloor"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(0.0, FLOOR_Y, 0.0)
	_world().add_child(instance)


## 边界墙 + 天花板按 bounds 做实体约束；越下沿由 _check_fall_out() 回收。
func _build_boundaries() -> void:
	var root := Node3D.new()
	root.name = "Boundaries"
	_world().add_child(root)
	var thickness := 2.0
	var height := _bounds_max.y - _bounds_min.y
	var center_y := (_bounds_min.y + _bounds_max.y) * 0.5
	var span_x := _bounds_max.x - _bounds_min.x
	var span_z := _bounds_max.z - _bounds_min.z
	_make_block(root, "West", Vector3(_bounds_min.x - thickness * 0.5, center_y, 0.0),
		Vector3(thickness, height, span_z + thickness * 2.0))
	_make_block(root, "East", Vector3(_bounds_max.x + thickness * 0.5, center_y, 0.0),
		Vector3(thickness, height, span_z + thickness * 2.0))
	_make_block(root, "North", Vector3(0.0, center_y, _bounds_min.z - thickness * 0.5),
		Vector3(span_x + thickness * 2.0, height, thickness))
	_make_block(root, "South", Vector3(0.0, center_y, _bounds_max.z + thickness * 0.5),
		Vector3(span_x + thickness * 2.0, height, thickness))
	_make_block(root, "Ceiling", Vector3(0.0, _bounds_max.y + thickness * 0.5, 0.0),
		Vector3(span_x + thickness * 2.0, thickness, span_z + thickness * 2.0))


func _make_block(parent: Node, block_name: String, block_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = block_position
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


## 落脚点只做标记（真源仍是布局 JSON），供飞行导航与测试读取高度。
func _build_landing_points() -> void:
	var root := Node3D.new()
	root.name = "LandingPoints"
	_world().add_child(root)
	for value in _layout["landing_points"] as Array:
		var point: Dictionary = value
		var center := _vector2_xz(point["center"], "landing_points[].center")
		var marker := Marker3D.new()
		marker.name = str(point.get("name", "LandingPoint"))
		marker.position = Vector3(center.x, float(point["top_y"]), center.y)
		root.add_child(marker)


func _spawn_player() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "mountain_realm: swordsman.tscn 根节点必须是 Swordsman")
	actor.name = "Swordsman"
	add_child(actor)
	_player = actor
	_motion = actor.motion()
	assert(_motion != null, "mountain_realm: 角色缺少 SwordsmanMotionComponent")
	# reset_motion 会清输入与御剑状态，因此先重置、再写落点与朝向。
	actor.reset_motion()
	actor.global_position = _spawn_position
	actor.set_aim_direction(_spawn_aim)
	# 御剑视觉不再由场景手动绑定：ActorAssembly 的 FlightBundle 随飞行行为一起装 flying_sword.glb，
	# 场景重复实例化会撞上「拒绝覆盖绑定」的装配契约。


# --- HUD ------------------------------------------------------------------


## 共享 HUD：标题 + 状态 + 短提示常显；控制说明进详情按钮 tooltip。
func _build_hud() -> void:
	_hud = HUD_SCRIPT.new()
	add_child(_hud)
	_hud.configure("MOUNTAIN", "角色移动 · 群山宗门", "WASD 移动 · Space 跳跃 · F 御剑 · R 复位 · Esc 返回 · H 详情")
	_hud.set_controls("WASD / 方向键 移动 · Space 跳跃 / 上升 · Ctrl 下降 · F 御剑 · 滚轮缩放 · R 复位 · Esc 返回子实验目录")
	_hud.set_question("三项移动能力在完整空间与美术中的组合体验是否成立？")
	_hud.set_return_text("返回子实验目录")
	_hud.return_pressed.connect(_return_to_hub)
	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.pressed.connect(_reset_experiment)
	_hud.add_button(reset_button)


## 状态文本只读组件字段：御剑优先于着地判定，其次空中，最后步行。
func _update_status() -> void:
	if _hud == null or _motion == null or _player == null:
		return
	var state := "步行"
	if _motion.flight_active:
		state = "御剑"
	elif not _motion.on_floor:
		state = "空中"
	_hud.set_status("状态：%s  ·  高度 %.1f m" % [state, _player.global_position.y])