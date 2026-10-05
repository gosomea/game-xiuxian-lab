extends Node3D

## 场景只装配环境、共享角色、CameraRig 与完整输入；碰撞与视觉同源。
const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const ACTOR: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const WORLD: PackedScene = preload("res://levels/experiments/character_movement/ink_lakeside_sample_world.glb")
const RIG: PackedScene = preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")
const PAPER := preload("res://levels/experiments/character_movement/ink_lakeside_sample_paper.gdshader")
const WATER := preload("res://levels/experiments/character_movement/ink_lakeside_sample_water.gdshader")
const LAYOUT := "res://levels/experiments/character_movement/ink_lakeside_sample_layout.json"
const SUN_TEXTURE: Texture2D = preload("res://levels/experiments/character_movement/ink_lakeside_sample_sun.svg")

var _player: Swordsman
var _camera: Camera3D
var _rig: CameraRig
var _input := MovementLabInput.new()
var _hud: LabHud
var _layout: Dictionary
var _previous_msaa: Viewport.MSAA
var _viewport: Viewport


func _ready() -> void:
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	assert(_layout["schema"] == "ink_lakeside/1", "水墨湖岸布局版本错误")
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D
	_build_world()
	_player = ACTOR.instantiate() as Swordsman
	_player.name = "Swordsman"
	_player.position = _vector(_layout["spawn"])
	add_child(_player)
	_style_character()
	_build_rig()
	_build_hud()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if _input.track_key(key):
			get_viewport().set_input_as_handled()
		elif MovementLabInput.is_key_down_edge(key):
			if MovementLabInput.key_code(key) == KEY_R:
				_reset_experiment()
				get_viewport().set_input_as_handled()
			elif key.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				_return_to_hub()


func _physics_process(_delta: float) -> void:
	# Reduce the landscape composition offset when zooming toward the character.
	var camera_data := _rig.component()
	var wide := clampf((camera_data.size - 16.0) / 32.0, 0.0, 1.0)
	camera_data.focus_offset = Vector3(0, 1, 0).lerp(Vector3(0, 5, -12), wide)
	_player.apply_motion_input(_input.consume_motion_input())
	if _player.global_position.y < -1.7:
		_reset_experiment()


func _process(_delta: float) -> void:
	if _hud == null:
		return
	var state := "御剑" if _player.motion().flight_active else ("步行" if _player.motion().on_floor else "空中")
	_hud.set_status("%s · 高度 %.1f m" % [state, _player.global_position.y])


func rig() -> CameraRig:
	return _rig


func _clear_pressed() -> void:
	_input.clear()
	if is_instance_valid(_player):
		_player.clear_input()


func _reset_experiment() -> void:
	_clear_pressed()
	_player.global_position = _vector(_layout["spawn"])
	_player.reset_motion()
	_player.set_aim_direction(Vector3.FORWARD)
	_rig.reset_state()


func _return_to_hub() -> void:
	_clear_pressed()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	assert(result == OK, "返回移动目录失败")


func _build_rig() -> void:
	_rig = RIG.instantiate() as CameraRig
	_rig.name = "CameraRig"
	add_child(_rig)
	var config := CameraRigConfig.new()
	config.start_mode = "fixed_follow"
	config.follow_preset = "smooth"
	config.yaw_degrees = 8.0
	config.pitch_degrees = 20.0
	config.distance = 85.0
	config.size = 48.0
	config.size_min = 10.0
	config.size_max = 85.0
	config.zoom_step = 4.0
	config.focus_offset = Vector3(0, 5, -12)
	config.near = 0.1
	config.far = 600.0
	config.mode_choices = PackedStringArray(["fixed_follow"])
	config.enable_mode_selection_keys = false
	config.enable_preset_key = false
	config.enable_zoom_keys = false
	config.enable_yaw_keys = false
	config.enable_zoom_wheel = true
	config.consume_unowned_rmb = true
	_rig.bind(_camera, _player, config)


func _build_hud() -> void:
	_hud = LabHud.new()
	add_child(_hud)
	_hud.configure("水墨样板", "湖岸 · 春山", "WASD 移动 · Shift 疾跑 · Space 跳跃 · F 御剑 · 滚轮缩放")
	_hud.set_question("纸色、墨瓦、淡粉树与现役修士，在步行和御剑时是否协调？")
	_hud.set_controls("WASD / 方向键移动 · Shift 疾跑 · Space 跳跃 / 御剑上升 · Ctrl 下降 · F 起飞 / 收剑 · R 重置 · Esc 返回 · H 详情")
	_hud.set_return_text("返回移动目录")
	_hud.return_pressed.connect(_return_to_hub)
	var reset := Button.new()
	reset.text = "重置"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_reset_experiment)
	_hud.add_button(reset)


func _build_world() -> void:
	var world := WORLD.instantiate() as Node3D
	world.name = "World"
	add_child(world)
	var palette: Dictionary = _layout["palette"]
	var materials := {}
	for mesh: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(surface)
			var label := original.resource_name
			assert(palette.has(label), "未知湖岸材质：" + label)
			if not materials.has(label):
				if DisplayServer.get_name() == "headless":
					# Dummy renderer does not support custom material parameter lifetimes.
					var flat := StandardMaterial3D.new()
					flat.albedo_color = Color(str(palette[label]))
					flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					materials[label] = flat
				else:
					var material := ShaderMaterial.new()
					material.shader = PAPER
					material.set_shader_parameter("tint", Color(str(palette[label])))
					if label in ["Far", "Middle", "Near"]:
						material.set_shader_parameter("grain_strength", 0.0)
					materials[label] = material
			mesh.set_surface_override_material(surface, materials[label])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.name in ["Shore", "Island"]:
			mesh.create_trimesh_collision()
	# Water has no collision: landing in it triggers the common reset path.
	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000, 180)
	lake.mesh = plane
	lake.position = Vector3(0, -0.6, 20)
	if DisplayServer.get_name() == "headless":
		var flat_water := StandardMaterial3D.new()
		flat_water.albedo_color = Color(0.29, 0.37, 0.37)
		lake.material_override = flat_water
	else:
		var water_material := ShaderMaterial.new()
		water_material.shader = WATER
		lake.material_override = water_material
	world.add_child(lake)
	var sun := MeshInstance3D.new()
	sun.name = "PaintedSun"
	var disc := QuadMesh.new()
	disc.size = Vector2(8, 8)
	sun.mesh = disc
	sun.position = Vector3(20, 4, -44)
	var sun_material := StandardMaterial3D.new()
	sun_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sun_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sun_material.albedo_texture = SUN_TEXTURE
	sun.material_override = sun_material
	world.add_child(sun)
	for spec: Dictionary in _layout["boxes"]:
		_box(world, str(spec["name"]), _vector(spec["position"]), _vector(spec["size"]))
	var bounds: Array = _layout["bounds"]
	_box(world, "West", Vector3(float(bounds[0])-0.5, 20, 4), Vector3(1, 44, 70))
	_box(world, "East", Vector3(float(bounds[1])+0.5, 20, 4), Vector3(1, 44, 70))
	_box(world, "North", Vector3(0, 20, float(bounds[2])-0.5), Vector3(88, 44, 1))
	_box(world, "South", Vector3(0, 20, float(bounds[3])+0.5), Vector3(88, 44, 1))
	_box(world, "Ceiling", Vector3(0, 42, 4), Vector3(88, 1, 70))


func _style_character() -> void:
	for mesh: MeshInstance3D in _player.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var material := original.duplicate() as StandardMaterial3D
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color *= Color(0.85, 0.90, 0.87)
			material.metallic = 0.0
			material.roughness = 1.0
			material.metallic_specular = 0.0
			material.normal_enabled = false
			mesh.set_surface_override_material(surface, material)


func _box(parent: Node3D, label: String, position_value: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position_value
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
