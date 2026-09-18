extends Node3D

## 地形接触训练场（ground_contact_course）：用真实角色与真实碰撞回答
## 「斜坡、台阶、墙角、窄路、边缘上的移动与碰撞是否稳定」。
##
## 依据 notes/proposed/gameplay/2026-09-18-character-movement-subexperiments.md 的子实验条目。
##
## 职责边界：
## - 角色与三项能力归 res://game/actors/swordsman/ 与 res://game/abilities/；本场景不新增能力，
##   不写 velocity / 意图 / 能力内部状态，只调用角色公开输入 API。
## - 物理尺寸真源是同目录 ground_contact_course_layout.json。Godot 由它建碰撞，
##   Blender 资产由同一份 devices 推导可见几何，两边共用同一套公式，因此
##   「看得见的装置」与「走得上去的装置」是同一个数学对象；playtest 再回读两侧做对齐断言。
## - 输入状态由 MovementLabInput 承担（按键映射 / 按住状态 / 二维归一化 / 升降）；
##   相机地面基、跳跃边沿、公开 API 调用、重置与返回由本场景负责。
## - 相机是固定偏移跟随，不做镜头实验（那是 camera_lab 的职责）。
##
## 只读语义：场景 _physics_process 早于子节点 actor，因此本帧读到的
## is_on_floor / get_floor_normal / get_slide_collision 都是**上一帧** move_and_slide 的结果，
## 与 motion.on_floor 的口径一致。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")
const VISUAL_SCENE: PackedScene = preload("res://levels/experiments/character_movement/ground_contact_course.glb")
const LAYOUT_PATH := "res://levels/experiments/character_movement/ground_contact_course_layout.json"
const LAYOUT_SCHEMA := "ground_contact_course/1"

## 世界碰撞统一层：地面 / 装置 / 角色同层，不引入额外层。
const COLLISION_LAYER := 1

## 远景底盘：远低于 fall_out_y 的一块大平板，只做背景。
## 没有它，越过院墙看到的就是空白背景与「场地浮在空中」；
## 有了它，落下回收区才读成有深度的竖井。不建碰撞、不投影、不参与可玩区判定。
## 与 mountain_realm 的 DistantFloor 同一做法：环境背景属场景编排，不进 GLB 资产。
const PLATE_Y := -7.0
const PLATE_HALF := 110.0
const PLATE_COLOR := Color(0.376471, 0.403922, 0.388235, 1.0)
## 基线台碰撞厚度：顶面对齐声明 top_y，底面向下埋，避免出现可见铺装之上的浮空碰撞。
const PAD_THICKNESS := 0.3

## 场地压暗：GLB 的青石在日光下接近纯白，装置边缘读不出来。
## 只对「地面层」网格做运行时反照率缩放（材质副本），不改 GLB 源资产与其他装置。
const GROUND_SHADE := 0.62

## 出生点朝向：沿 +X，正对台阶 / 墙角 / 窄路区。
const SPAWN_AIM := Vector3.RIGHT

var _layout: Dictionary = {}
var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _input := MovementLabInput.new()

var _spawn_position := Vector3.ZERO
var _fall_out_y := -6.0
var _bounds_min := Vector3.ZERO
var _bounds_max := Vector3.ZERO
var _camera_offset := Vector3.ZERO
var _camera_size := 17.0
var _camera_size_min := 6.0
var _camera_size_max := 40.0
var _camera_zoom_step := 1.5
var _camera_follow_speed := 5.0
var _camera_clamp_min := Vector2.ZERO
var _camera_clamp_max := Vector2.ZERO
var _follow_target := Vector3.ZERO

var _devices: Array[Dictionary] = []
var _device_colliders: Dictionary = {}
var _jump_edge_pending := false
var _jump_edges := 0
var _recoveries := 0
var _physics_ticks := 0

var _hud_zone: Label
var _hud_declared: Label
var _hud_motion: Label
var _hud_contact: Label
var _hud_recovery: Label


func _ready() -> void:
	# 固定返回目标是同目录子实验目录；缺它属装配缺陷，启动即断言（与 motion_stage 同一口径）。
	assert(ResourceLoader.exists(HUB_SCENE, "PackedScene"),
		"ground_contact_course: 缺少返回目标 %s" % HUB_SCENE)
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "ground_contact_course: 场景必须提供 Camera3D")
	_read_layout()
	_build_ground()
	_build_devices()
	_build_visual()
	_shade_ground()
	_build_distant_plate()
	_spawn_player()
	_build_hud()
	_reset_camera()
	_update_hud()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	# 失焦只清输入；不改变能力状态（与套件其它场景一致）。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_input.clear()
		if _player != null:
			_player.clear_input()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		# 先交给 helper：它只认移动键与场景声明的升降键，其余键返回 false 由本场景处理。
		if _input.track_key(key_event, MovementLabInput.VERTICAL_KEYS):
			# 跳跃是 key-down 边沿（echo 不算）；记一个待消费边沿，在物理帧里交给 actor。
			if MovementLabInput.key_code(key_event) == MovementLabInput.KEY_VERTICAL_UP \
					and MovementLabInput.is_key_down_edge(key_event):
				_jump_edge_pending = true
			get_viewport().set_input_as_handled()
			return
		if MovementLabInput.is_key_down_edge(key_event):
			var code := MovementLabInput.key_code(key_event)
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
			_camera.size = clampf(_camera.size - _camera_zoom_step, _camera_size_min, _camera_size_max)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + _camera_zoom_step, _camera_size_min, _camera_size_max)
			get_viewport().set_input_as_handled()


## 场景先写输入、actor 子节点随后 tick（父节点 _physics_process 先于子节点）。
func _physics_process(delta: float) -> void:
	if _player == null or _motion == null:
		return
	_physics_ticks += 1
	var right := _ground_vector(_camera.global_transform.basis.x, Vector3.RIGHT)
	var forward := _ground_vector(-_camera.global_transform.basis.z, Vector3.FORWARD)
	_player.set_camera_ground_basis(right, forward)
	var move := _input.move_input()
	_player.set_move_input(move)
	_player.set_vertical_input(_input.vertical_input())
	# 跳跃边沿：事件期只记边沿，物理帧里消费一次，避免同一次按下被两帧读到。
	if _jump_edge_pending:
		_jump_edge_pending = false
		_jump_edges += 1
		_player.press_jump()
	# 角色朝运动方向；停下保留最后朝向。
	if move != Vector2.ZERO:
		var direction := right * move.x - forward * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())
	_check_fall_out()
	_follow_camera(delta)


func _process(_delta: float) -> void:
	_update_hud()


# --- 布局 -------------------------------------------------------------------


func _read_layout() -> void:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	assert(not text.is_empty(), "ground_contact_course: 无法读取布局 %s" % LAYOUT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "ground_contact_course: 布局 JSON 顶层必须是对象")
	_layout = parsed as Dictionary
	assert(str(_layout.get("schema", "")) == LAYOUT_SCHEMA,
		"ground_contact_course: 布局 schema 必须为 %s" % LAYOUT_SCHEMA)
	assert(str(_layout.get("units", "")) == "meters", "ground_contact_course: 布局 units 必须为 meters")
	assert(str(_layout.get("up_axis", "")) == "Y", "ground_contact_course: 布局 up_axis 必须为 Y")
	for key in ["spawn", "bounds", "camera", "ground_pieces", "devices", "void_gap"]:
		assert(_layout.has(key), "ground_contact_course: 布局缺少字段 %s" % key)
	_spawn_position = _vector3((_layout["spawn"] as Dictionary)["position"])
	var bounds: Dictionary = _layout["bounds"]
	_bounds_min = _vector3(bounds["min"])
	_bounds_max = _vector3(bounds["max"])
	_fall_out_y = float(bounds.get("fall_out_y", _bounds_min.y))
	var camera: Dictionary = _layout["camera"]
	_camera_offset = _vector3(camera["offset"])
	_camera_size = float(camera["size"])
	_camera_size_min = float(camera.get("size_min", 6.0))
	_camera_size_max = float(camera.get("size_max", 40.0))
	_camera_follow_speed = float(camera.get("follow_speed", 5.0))
	_camera_clamp_min = _vector2(camera["clamp_min"])
	_camera_clamp_max = _vector2(camera["clamp_max"])
	for value in _layout["devices"] as Array:
		_devices.append(value as Dictionary)
	assert(not _devices.is_empty(), "ground_contact_course: 布局 devices 不能为空")


func _vector3(value: Variant) -> Vector3:
	assert(value is Array and (value as Array).size() == 3,
		"ground_contact_course: 坐标必须是长度 3 的数组")
	var values := value as Array
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _vector2(value: Variant) -> Vector2:
	assert(value is Array and (value as Array).size() == 2,
		"ground_contact_course: 二维字段必须是长度 2 的数组")
	var values := value as Array
	return Vector2(float(values[0]), float(values[1]))


## 斜面推导：与 Blender 生成器 ramp_shape() 同一套公式（角度式与 直角边式 二选一）。
static func ramp_shape(device: Dictionary) -> Dictionary:
	var thickness := float(device["thickness"])
	var run := 0.0
	var rise := 0.0
	var angle := 0.0
	if device.has("run_m") or device.has("rise_m"):
		run = float(device.get("run_m", 0.0))
		rise = float(device.get("rise_m", 0.0))
		angle = atan2(rise, run)
	else:
		angle = deg_to_rad(float(device["angle_deg"]))
		var length := float(device["slope_length"])
		run = length * cos(angle)
		rise = length * sin(angle)
	var base := Vector3(device["base"][0], device["base"][1], device["base"][2])
	var length_total := sqrt(run * run + rise * rise)
	var center := Vector3(
		base.x + run * 0.5 + thickness * 0.5 * sin(angle),
		base.y + rise * 0.5 - thickness * 0.5 * cos(angle),
		base.z)
	return {
		"center": center,
		"size": Vector3(length_total, thickness, float(device["width"])),
		"angle": angle,
		"run": run,
		"rise": rise,
		"top_x": base.x + run,
		"top_y": base.y + rise,
	}


# --- 装配 -------------------------------------------------------------------


func _world() -> Node3D:
	var world := get_node_or_null("World") as Node3D
	if world == null:
		world = Node3D.new()
		world.name = "World"
		add_child(world)
	return world


## 地面：按布局 ground_pieces 建实体盒；void_gap 处刻意不建地面（落下回收区）。
func _build_ground() -> void:
	var root := Node3D.new()
	root.name = "Ground"
	_world().add_child(root)
	for value in _layout["ground_pieces"] as Array:
		var piece: Dictionary = value
		_make_block(root, str(piece["name"]), _vector3(piece["center"]), _vector3(piece["size"]))


## 装置碰撞：只按 devices 建盒子；视觉由 GLB 承担，两者尺寸来自同一份 JSON。
func _build_devices() -> void:
	var root := Node3D.new()
	root.name = "Devices"
	_world().add_child(root)
	for device in _devices:
		var id := str(device["id"])
		var kind := str(device["kind"])
		var body: StaticBody3D = null
		match kind:
			"pad":
				# 基线台是薄地贴：碰撞顶面必须等于声明 top_y，否则角色会浮在可见铺装之上。
				var center := _vector3(device["center"])
				var size := _vector3(device["size"])
				var top_y := float(device.get("top_y", size.y))
				body = _make_block(root, id,
					Vector3(center.x, top_y - PAD_THICKNESS * 0.5, center.z),
					Vector3(size.x, PAD_THICKNESS, size.z))
			"ramp":
				var shape := ramp_shape(device)
				body = _make_block(root, id, shape["center"], shape["size"])
				body.rotation.z = shape["angle"]
				var depth := float(device.get("landing_depth", 0.0))
				if depth > 0.0:
					var base := _vector3(device["base"])
					var top_y := float(shape["top_y"])
					# 坡顶平台：从坡顶延伸到 base + run + depth，高度 = 坡顶高度。
					var landing_center := Vector3(float(shape["top_x"]) + depth * 0.5, top_y * 0.5, base.z)
					_make_block(root, id + "_landing", landing_center,
						Vector3(depth, maxf(top_y, 0.2), float(device["width"])))
			"step":
				body = _make_block(root, id, _vector3(device["center"]), _vector3(device["size"]))
			"terrace":
				body = _make_block(root, id, _vector3(device["center"]), _vector3(device["size"]))
			"wall":
				body = _make_block(root, id, _vector3(device["center"]), _vector3(device["size"]))
			_:
				assert(false, "ground_contact_course: 未知装置类型 %s（%s）" % [kind, id])
		assert(body != null, "ground_contact_course: 装置 %s 未生成碰撞体" % id)
		_device_colliders[id] = body
	# 覆盖校验：布局里每个 device 都必须有碰撞体，且数量一致。
	assert(_device_colliders.size() == _devices.size(),
		"ground_contact_course: 装置碰撞体 %d 与布局条目 %d 不一致" % [_device_colliders.size(), _devices.size()])


## 可见几何：GLB 在原点实例化（导出时已是 Godot 世界坐标）。
func _build_visual() -> void:
	var visual := VISUAL_SCENE.instantiate() as Node3D
	assert(visual != null, "ground_contact_course: GLB 根节点必须是 Node3D")
	visual.name = "CourseVisual"
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() > 60, "ground_contact_course: GLB 网格数量异常（%d）" % meshes.size())
	for node in meshes:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_world().add_child(visual)


## 地面层压暗：只处理 GLB 里以 ground_ 开头的网格（地面 / 分格线 / 苔石基座）。
## 注意地面**视觉**在 World/CourseVisual 下，World/Ground 容器里只有碰撞体——
## 对着碰撞容器找网格会静默变成空操作，所以这里按名字前缀在 CourseVisual 内筛。
func _shade_ground() -> void:
	var visual := _world().get_node_or_null("CourseVisual") as Node3D
	if visual == null:
		return
	var shaded := 0
	for node in visual.find_children("ground_*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		if mesh == null:
			continue
		shaded += 1
		for surface in range(mesh.get_surface_count()):
			var material := instance.get_active_material(surface)
			if material == null:
				continue
			var copy := material.duplicate() as BaseMaterial3D
			if copy == null:
				continue
			copy.albedo_color = Color(
				copy.albedo_color.r * GROUND_SHADE,
				copy.albedo_color.g * GROUND_SHADE,
				copy.albedo_color.b * GROUND_SHADE,
				copy.albedo_color.a)
			instance.set_surface_override_material(surface, copy)
	assert(shaded > 0, "ground_contact_course: 地面压暗未命中任何网格")


## 远景底盘：不受光的大平板，垫在回收竖井之下，让场地不像浮在空中。
func _build_distant_plate() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(PLATE_HALF * 2.0, 1.0, PLATE_HALF * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = PLATE_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var instance := MeshInstance3D.new()
	instance.name = "DistantPlate"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(4.0, PLATE_Y, 0.0)
	_world().add_child(instance)


func _spawn_player() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "ground_contact_course: swordsman.tscn 根节点必须是 Swordsman")
	actor.name = "Swordsman"
	add_child(actor)
	_player = actor
	_motion = actor.motion()
	assert(_motion != null, "ground_contact_course: 角色缺少 SwordsmanMotionComponent")
	actor.reset_motion()
	actor.global_position = _spawn_position
	actor.set_aim_direction(SPAWN_AIM)


func _make_block(parent: Node, block_name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = center
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = COLLISION_LAYER
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.01), maxf(size.y, 0.01), maxf(size.z, 0.01))
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	return body


# --- 相机 -------------------------------------------------------------------


func _ground_vector(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


func _follow_camera(delta: float) -> void:
	var target := _player.global_position
	target.x = clampf(target.x, _camera_clamp_min.x, _camera_clamp_max.x)
	target.z = clampf(target.z, _camera_clamp_min.y, _camera_clamp_max.y)
	target.y = maxf(target.y * 0.5, 0.0)
	if _follow_target.distance_squared_to(target) > 400.0:
		_follow_target = target
	else:
		_follow_target = _follow_target.lerp(target, clampf(delta * _camera_follow_speed, 0.0, 1.0))
	_camera.position = _follow_target + _camera_offset
	_camera.look_at(_follow_target, Vector3.UP)


func _reset_camera() -> void:
	_follow_target = _spawn_position
	_camera.size = _camera_size
	_camera.position = _follow_target + _camera_offset
	_camera.look_at(_follow_target, Vector3.UP)


# --- 重置 / 回收 / 返回 ------------------------------------------------------


func _reset_experiment() -> void:
	_input.clear()
	_player.global_position = _spawn_position
	_player.reset_motion()
	_player.set_aim_direction(SPAWN_AIM)
	_jump_edge_pending = false
	_jump_edges = 0
	_physics_ticks = 0
	_reset_camera()
	_update_hud()


## 掉出下沿才回收：回到 spawn 并走 R 的同一套清理；回收次数供验收读回。
func _check_fall_out() -> void:
	if _player.global_position.y < _fall_out_y:
		push_warning("ground_contact_course: 角色掉出训练场（y=%.2f），回收至 spawn" % _player.global_position.y)
		_recoveries += 1
		_reset_experiment()


func _return_to_hub() -> void:
	_input.clear()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	assert(result == OK, "ground_contact_course: 返回子实验目录失败（%s，错误码 %d）" % [HUB_SCENE, result])


# --- 公开只读接口（供 HUD 与验收脚本读取，不写任何状态） ---------------------


func player() -> Swordsman:
	return _player


func motion() -> SwordsmanMotionComponent:
	return _motion


func input_state() -> MovementLabInput:
	return _input


func layout() -> Dictionary:
	return _layout


func devices() -> Array[Dictionary]:
	return _devices


func device_collider(id: String) -> StaticBody3D:
	return _device_colliders.get(id) as StaticBody3D


func device_colliders() -> Dictionary:
	return _device_colliders


## 当前所在装置：按 XZ 包含判定（点是否落在装置占地内），多个命中时取占地最小者。
##
## 关键取舍：**不按「最近中心」判定**。院墙这类细长装置中心远在场地边缘、占地却横跨全场，
## 用距离减半径会让角色一出生就被判成「站在西墙上」。包含判定则天然正确：
## 人没踩在装置上就没有装置，且小装置（台阶、窄路）压过大装置（院墙）胜出。
func current_device() -> Dictionary:
	if _player == null:
		return {}
	var point := Vector2(_player.global_position.x, _player.global_position.z)
	var best: Dictionary = {}
	var best_area := INF
	for device in _devices:
		var rect := device_footprint(device)
		if rect == Rect2():
			continue
		if not rect.has_point(point):
			continue
		var area := rect.size.x * rect.size.y
		if area < best_area:
			best_area = area
			best = device
	return best


## 装置的 XZ 占地矩形（Godot Rect2：position = 最小角，size = 全尺寸）。
## 与可见几何、碰撞盒同源：都来自同一份 devices 字段。
func device_footprint(device: Dictionary) -> Rect2:
	if device["kind"] == "ramp":
		var shape := ramp_shape(device)
		var base := _vector3(device["base"])
		var depth := float(device.get("landing_depth", 0.0))
		var width := float(device["width"])
		var min_x := base.x
		var max_x := float(shape["top_x"]) + depth
		return Rect2(min_x, base.z - width * 0.5, maxf(max_x - min_x, 0.01), width)
	if device.has("center") and device.has("size"):
		var center := _vector3(device["center"])
		var size := _vector3(device["size"])
		return Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z)
	return Rect2()


## 装置声明尺寸的人读文本（与可见几何、碰撞盒同源）。
func device_declared_text(device: Dictionary) -> String:
	if device.is_empty():
		return "—"
	match str(device.get("kind", "")):
		"ramp":
			var shape := ramp_shape(device)
			return "坡度 %.1f°  坡长 %.2f m  抬升 %.2f m  宽 %.2f m" % [
				rad_to_deg(float(shape["angle"])), float(shape["size"].x),
				float(shape["rise"]), float(device["width"])]
		"step":
			return "抬升 %.2f m  台面 %.1f×%.1f m" % [
				float(device["rise"]), float(device["size"][0]), float(device["size"][2])]
		"terrace":
			return "台面顶 %.2f m  东侧无栏" % float(device["top_y"])
		"wall":
			if device.has("gap_m"):
				return "净宽 %.2f m  墙高 %.2f m" % [float(device["gap_m"]), float(device["size"][1])]
			if device.has("corner"):
				return "墙角 %s  高 %.2f m" % ["内" if str(device["corner"]) == "inner" else "外",
					float(device["size"][1])]
			return "尺寸 %.2f×%.2f×%.2f m" % [
				float(device["size"][0]), float(device["size"][1]), float(device["size"][2])]
		"pad":
			return "基线台 %.1f×%.1f m" % [float(device["size"][0]), float(device["size"][2])]
	return str(device.get("title", "—"))


## 实测地面法线倾角（度）；未着地返回 -1。
func _measured_floor_angle() -> float:
	if _player == null or not _player.is_on_floor():
		return -1.0
	var normal := _player.get_floor_normal()
	return rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))


## 当前滑动碰撞体名字（上一帧 move_and_slide 结果）；无接触返回空数组。
func contact_names() -> PackedStringArray:
	var names := PackedStringArray()
	if _player == null:
		return names
	for index in range(_player.get_slide_collision_count()):
		var collision := _player.get_slide_collision(index)
		if collision == null:
			continue
		var collider := collision.get_collider()
		if collider == null:
			continue
		if collider is Node:
			names.append(str((collider as Node).get_path()).get_file())
	return names


## 工作台可观察量汇总：输入意图、物理状态、接触、区域读数与表现快照。
func stage_state() -> Dictionary:
	if _player == null or _motion == null:
		return {}
	var device := current_device()
	return {
		"position": _player.global_position,
		"move_input": _motion.move_input,
		"vertical_input": _motion.vertical_input,
		"aim_direction": _motion.aim_direction,
		"actual_velocity": _motion.actual_velocity,
		"horizontal_speed": Vector2(_motion.actual_velocity.x, _motion.actual_velocity.z).length(),
		"on_floor": _motion.on_floor,
		"is_on_wall": _player.is_on_wall(),
		"flight_active": _motion.flight_active,
		"floor_angle_deg": _measured_floor_angle(),
		"floor_normal": _player.get_floor_normal(),
		"contacts": contact_names(),
		"device_id": str(device.get("id", "")),
		"device_zone": str(device.get("zone", "")),
		"device_title": str(device.get("title", "")),
		"device_declared": device_declared_text(device),
		"jump_edges": _jump_edges,
		"recoveries": _recoveries,
		"physics_ticks": _physics_ticks,
		"held_keys": _input.held_count(),
	}


# --- HUD --------------------------------------------------------------------


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
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 14)
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

	var panel := PanelContainer.new()
	panel.name = "ReadoutPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _backdrop())
	header.add_child(panel)

	var readout := VBoxContainer.new()
	readout.name = "Readout"
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.add_theme_constant_override("separation", 2)
	panel.add_child(readout)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.theme_type_variation = "AccentLabel"
	kicker.add_theme_font_size_override("font_size", 12)
	kicker.text = "EXPERIMENT    /    CHARACTER MOVEMENT · GROUND CONTACT"
	readout.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 22)
	title.text = "地形接触训练场"
	readout.add_child(title)

	_hud_zone = _make_readout_label(readout, "Zone")
	_hud_declared = _make_readout_label(readout, "Declared")
	_hud_motion = _make_readout_label(readout, "Motion")
	_hud_contact = _make_readout_label(readout, "Contact")
	_hud_recovery = _make_readout_label(readout, "Recovery")

	var buttons := VBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 8)
	header.add_child(buttons)

	var return_button := Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "返回子实验目录"
	return_button.custom_minimum_size = Vector2(132, 40)
	return_button.focus_mode = Control.FOCUS_NONE
	return_button.pressed.connect(_return_to_hub)
	buttons.add_child(return_button)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置 (R)"
	reset_button.custom_minimum_size = Vector2(132, 40)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_experiment)
	buttons.add_child(reset_button)

	var spacer := Control.new()
	spacer.name = "Space"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(footer)

	var controls_panel := PanelContainer.new()
	controls_panel.name = "ControlsPanel"
	controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_panel.add_theme_stylebox_override("panel", _backdrop())
	footer.add_child(controls_panel)

	var controls := Label.new()
	controls.name = "Controls"
	controls.theme_type_variation = "MutedLabel"
	controls.add_theme_font_size_override("font_size", 13)
	controls.text = "WASD / 方向键 地面移动  ·  Space 跳跃  ·  滚轮缩放  ·  R 重置  ·  Esc 返回子实验目录"
	# 中文没有词间空格，WORD_SMART 会把整句当一个长词并撑出最小宽度；小窗会顶穿右边界。
	controls.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_panel.add_child(controls)


func _make_readout_label(parent: Node, tag: String) -> Label:
	var label := Label.new()
	label.name = tag
	label.theme_type_variation = "MutedLabel"
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	parent.add_child(label)
	return label


func _backdrop() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.980392, 0.972549, 0.949020, 0.86)
	style.border_color = Color(0.505882, 0.611765, 0.533333, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


## 只读组件与场景读数；不伪造能力状态，不写任何运动数据。
func _update_hud() -> void:
	if _hud_zone == null or _motion == null or _player == null:
		return
	var device := current_device()
	var zone := str(device.get("zone", "—"))
	var title := str(device.get("title", "—"))
	_hud_zone.text = "区域  %s  ·  %s" % [zone, title]
	_hud_declared.text = "装置声明  " + device_declared_text(device)
	var velocity := _motion.actual_velocity
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var angle := _measured_floor_angle()
	_hud_motion.text = "实测  着地=%s  水平 %.2f m/s  vy=%+.2f  高度 %.2f m  地面倾角=%s" % [
		"是" if _motion.on_floor else "否", horizontal, velocity.y,
		_player.global_position.y,
		"%.1f°" % angle if angle >= 0.0 else "未着地",
	]
	var contacts := contact_names()
	_hud_contact.text = "接触  贴墙=%s  滑动碰撞=%s" % [
		"是" if _player.is_on_wall() else "否",
		"—" if contacts.is_empty() else ", ".join(contacts),
	]
	_hud_recovery.text = "输入  移动=(%+.2f, %+.2f)  跳跃边沿=%d  回收=%d  物理帧=%d" % [
		_motion.move_input.x, _motion.move_input.y, _jump_edges, _recoveries, _physics_ticks,
	]
