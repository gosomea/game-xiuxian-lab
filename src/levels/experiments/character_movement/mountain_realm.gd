extends Node3D

## 群山宗门移动探索场景（本轮入口）。
##
## 职责边界（依据 docs/experiments/traversal-contract.md 与 docs/art/mountain_realm/layout-contract.md）：
## - 平面移动 / 跳跃 / 御剑三能力归角色根与 res://game/abilities/ 叶子包；本场景只做输入编排、
##   布局装配、边界约束、相机与 HUD，不复制任何能力逻辑，不直接改 velocity。
## - 布局坐标真源为同目录 mountain_realm_layout.json，本场景只消费不生成。
## - 山体碰撞壳 mountain_realm_collision.glb 只提取网格生成 StaticBody3D + trimesh，不做可见渲染。
## - 美术资源均为 preload 硬依赖：资源缺失即脚本加载失败，不静默降级、不伪造可运行入口。
## - 御剑视觉由本场景实例化为角色 Visual 子节点，经 actor.bind_flight_visual() 交给角色统一显示/隐藏。

const HUB_SCENE := "res://levels/lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")

const VISUAL_PATH := "res://levels/experiments/character_movement/mountain_realm.glb"
const LAYOUT_PATH := "res://levels/experiments/character_movement/mountain_realm_layout.json"
const SWORD_PATH := "res://game/abilities/sword_flight/models/flying_sword.glb"
const VISUAL_SCENE: PackedScene = preload("res://levels/experiments/character_movement/mountain_realm.glb")
const SHELL_PATH := "res://levels/experiments/character_movement/mountain_realm_collision.glb"
const SHELL_SCENE: PackedScene = preload("res://levels/experiments/character_movement/mountain_realm_collision.glb")
const FLYING_SWORD_SCENE: PackedScene = preload("res://game/abilities/sword_flight/models/flying_sword.glb")
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
## 方向约定不变：相机地面基仍由本脚本每帧写入角色，屏幕相对移动不受数值影响。
const CAMERA_OFFSET := Vector3(15.0, 19.0, 16.5)
const CAMERA_SIZE := 30.0
const CAMERA_SIZE_MIN := 7.0
## 上限收紧：再远就会露出地形截断面，而不是"更开阔的群山"。
const CAMERA_SIZE_MAX := 170.0
const CAMERA_ZOOM_STEP := 6.0
const CAMERA_FOLLOW_SPEED := 4.0
const CAMERA_FAR := 600.0

## 物理键 → 屏幕输入（x = 右，y = 下）；WASD 与方向键等价。
const MOVE_KEYS := {
	KEY_W: Vector2(0.0, -1.0),
	KEY_UP: Vector2(0.0, -1.0),
	KEY_S: Vector2(0.0, 1.0),
	KEY_DOWN: Vector2(0.0, 1.0),
	KEY_A: Vector2(-1.0, 0.0),
	KEY_LEFT: Vector2(-1.0, 0.0),
	KEY_D: Vector2(1.0, 0.0),
	KEY_RIGHT: Vector2(1.0, 0.0),
}

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
var _follow_target := Vector3.ZERO
var _pressed: Dictionary = {}
var _status: Label


func _ready() -> void:
	# 进入本场景开 4x MSAA（大场景轮廓多），离开时恢复进入前的值，不把状态泄漏给目录等其他场景。
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "mountain_realm: 场景必须提供 Camera3D")
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.near = 0.1
	_camera.far = CAMERA_FAR
	_read_layout()
	_build_visual()
	_build_shell_collision()
	_build_box_collision()
	_build_courtyard_overlay()
	_build_distant_floor()
	_build_boundaries()
	_build_landing_points()
	_spawn_player()
	_build_hud()
	_reset_camera()
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
		# 物理键码优先（不看键盘布局）；个别平台 Ctrl 只填逻辑键码时回退。
		var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if MOVE_KEYS.has(code):
			_pressed[code] = key_event.pressed
			get_viewport().set_input_as_handled()
			return
		if code == KEY_SPACE or code == KEY_CTRL:
			_pressed[code] = key_event.pressed
			# 跳跃是 key-down 边沿（echo 不算）；actor 在帧末自行清零。
			if key_event.pressed and not key_event.echo and code == KEY_SPACE and _player != null:
				_player.press_jump()
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo:
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
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = clampf(_camera.size - CAMERA_ZOOM_STEP, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + CAMERA_ZOOM_STEP, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _player == null or _motion == null:
		return
	# 屏幕相对：相机右方/前方投影到水平面后规范化，退化时回退世界轴。
	var right := _ground_vector(_camera.global_transform.basis.x, Vector3.RIGHT)
	var forward := _ground_vector(-_camera.global_transform.basis.z, Vector3.FORWARD)
	_player.set_camera_ground_basis(right, forward)
	var move := _read_move_input()
	_player.set_move_input(move)
	_player.set_vertical_input(_read_vertical_input())
	# 角色朝运动方向；停下时不写朝向，由角色保留最后一次朝向。
	if move != Vector2.ZERO:
		var direction := right * move.x - forward * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())
	_check_fall_out()
	_follow_camera(delta)


func _process(_delta: float) -> void:
	_update_status()


## 场景先写输入、actor 子节点随后 tick（父节点 _physics_process 先于子节点）。
func _read_move_input() -> Vector2:
	var input_vector := Vector2.ZERO
	for code in MOVE_KEYS:
		if _pressed.get(code, false):
			input_vector += MOVE_KEYS[code] as Vector2
	return input_vector.limit_length(1.0)


func _read_vertical_input() -> float:
	var value := 0.0
	if _pressed.get(KEY_SPACE, false):
		value += 1.0
	if _pressed.get(KEY_CTRL, false):
		value -= 1.0
	return clampf(value, -1.0, 1.0)


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


func _follow_camera(delta: float) -> void:
	var target := _player.global_position
	target.x = clampf(target.x, _bounds_min.x, _bounds_max.x)
	target.z = clampf(target.z, _bounds_min.z, _bounds_max.z)
	target.y = clampf(target.y, _bounds_min.y, _bounds_max.y)
	_follow_target = _follow_target.lerp(target, clampf(delta * CAMERA_FOLLOW_SPEED, 0.0, 1.0))
	_camera.position = _follow_target + CAMERA_OFFSET
	_camera.look_at(_follow_target, Vector3.UP)


func _reset_camera() -> void:
	_follow_target = _spawn_position
	_camera.size = CAMERA_SIZE
	_camera.position = _follow_target + CAMERA_OFFSET
	_camera.look_at(_follow_target, Vector3.UP)


func _clear_pressed() -> void:
	_pressed.clear()
	if _player != null:
		_player.clear_input()


func _reset_experiment() -> void:
	_clear_pressed()
	_player.global_position = _spawn_position
	_player.reset_motion()
	_player.set_aim_direction(_spawn_aim)
	_reset_camera()


func _return_to_hub() -> void:
	_clear_pressed()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	if result != OK:
		push_error("mountain_realm: 返回实验目录失败，错误码 %d" % result)

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
	_bind_flight_visual(actor)


## 御剑视觉由场景绑定：作为角色 Visual 子节点，朝向随 Visual 同步；剑原点在顶面中心，无需偏移。
func _bind_flight_visual(actor: Swordsman) -> void:
	var sword := _instantiate_glb(FLYING_SWORD_SCENE, SWORD_PATH)
	sword.name = "FlyingSword"
	var visual := actor.get_node_or_null("Visual") as Node3D
	assert(visual != null, "mountain_realm: 角色缺少 Visual 节点")
	visual.add_child(sword)
	actor.bind_flight_visual(sword)


# --- HUD ------------------------------------------------------------------


## 文字衬底：纸白半透明薄面板（沿用 lab 主题的纸白/青绿描边），四周留内边距；
## 只贴合文字块，不做覆盖中心的大面板。纯样式，不参与输入。
func _make_text_backdrop() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.980392, 0.972549, 0.949020, 0.82)
	style.border_color = Color(0.505882, 0.611765, 0.533333, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


## HUD 骨架沿用 movement_garden 的 CanvasLayer + Control + Margin/VBox；按钮不抢键盘焦点。
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	add_child(layer)

	var interface := Control.new()
	interface.name = "Interface"
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interface.theme = LAB_THEME
	layer.add_child(interface)
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 20)
	interface.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(header)

	# 顶部信息块用贴合内容的纸白半透明底：只护住标题与状态文字，不铺满屏幕、不遮场景中心。
	var titles_panel := PanelContainer.new()
	titles_panel.name = "TitlesPanel"
	titles_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles_panel.add_theme_stylebox_override("panel", _make_text_backdrop())
	header.add_child(titles_panel)

	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles_panel.add_child(titles)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.theme_type_variation = "AccentLabel"
	kicker.add_theme_font_size_override("font_size", 13)
	kicker.text = "EXPERIMENT    /    CHARACTER MOVEMENT · MOUNTAIN"
	titles.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 28)
	title.text = "角色移动 · 群山宗门"
	titles.add_child(title)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = "MutedLabel"
	_status.add_theme_font_size_override("font_size", 14)
	titles.add_child(_status)

	var return_button := Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回实验目录"
	return_button.custom_minimum_size = Vector2(140, 44)
	return_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 按钮不抢键盘焦点：移动键事件始终抵达场景的 _unhandled_input。
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.pressed.connect(_return_to_hub)
	header.add_child(return_button)

	var spacer := Control.new()
	spacer.name = "Space"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(footer)

	# 底部按键说明同样加薄底衬；重置按钮留在面板外，避免按钮背景被衬底吞掉。
	var controls_panel := PanelContainer.new()
	controls_panel.name = "ControlsPanel"
	controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_panel.add_theme_stylebox_override("panel", _make_text_backdrop())
	footer.add_child(controls_panel)

	var controls := Label.new()
	controls.name = "Controls"
	controls.theme_type_variation = "MutedLabel"
	controls.add_theme_font_size_override("font_size", 14)
	controls.text = "WASD / 方向键 移动  ·  Space 跳跃 / 上升  ·  Ctrl 下降  ·  F 御剑  ·  滚轮缩放  ·  R 复位  ·  Esc 返回"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_panel.add_child(controls)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.custom_minimum_size = Vector2(96, 44)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_experiment)
	footer.add_child(reset_button)


## 状态文本只读组件字段：御剑优先于着地判定，其次空中，最后步行。
func _update_status() -> void:
	if _status == null or _motion == null or _player == null:
		return
	var state := "步行"
	if _motion.flight_active:
		state = "御剑"
	elif not _motion.on_floor:
		state = "空中"
	_status.text = "状态：%s  ·  高度 %.1f m" % [state, _player.global_position.y]