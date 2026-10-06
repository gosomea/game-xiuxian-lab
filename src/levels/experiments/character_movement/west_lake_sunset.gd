extends Node3D

## 西湖综合场景仅装配共享移动/镜头与本地环境表现；不复制角色行为。
const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const ACTOR: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const WORLD: PackedScene = preload("res://levels/experiments/character_movement/west_lake_sunset_world.glb")
const RIG: PackedScene = preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")
const PAPER := preload("res://levels/experiments/character_movement/west_lake_sunset_paper.gdshader")
const WATER := preload("res://levels/experiments/character_movement/west_lake_sunset_water.gdshader")
const SKY := preload("res://levels/experiments/character_movement/west_lake_sunset_sky.gdshader")
const BANK := preload("res://levels/experiments/character_movement/west_lake_sunset_cloud_bank.gdshader")
const CLOUD := preload("res://levels/experiments/character_movement/west_lake_sunset_cloud.gdshader")
const LAYOUT := "res://levels/experiments/character_movement/west_lake_sunset_layout.json"

var _player: Swordsman
var _camera: Camera3D
var _rig: CameraRig
var _input := MovementLabInput.new()
var _hud: LabHud
var _layout: Dictionary
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA
var _cloud_veil: ColorRect
var _boat: Node3D
var _elapsed := 0.0
var _cloud_banks: Array[MeshInstance3D] = []
var _cloud_sheet_opacity := -1.0
var _environment_materials: Array[Material] = []
var _projection_button: Button


func _ready() -> void:
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	assert(_layout["schema"] == "west_lake_sunset/1", "西湖布局版本错误")
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
	_build_atmosphere()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_pressed()
		if is_instance_valid(_rig):
			_rig.release_capture()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if _input.track_key(key):
			get_viewport().set_input_as_handled()
		elif MovementLabInput.is_key_down_edge(key):
			var code := MovementLabInput.key_code(key)
			if code in [KEY_R, KEY_V, KEY_M] or key.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				if code == KEY_R:
					_reset_experiment()
				elif code == KEY_V:
					_toggle_projection()
				elif code == KEY_M:
					_panorama()
				else:
					_return_to_hub()


func _physics_process(_delta: float) -> void:
	var camera_data := _rig.component()
	if _rig.mode_id() == "overview" and camera_data.size > 200.0:
		camera_data.focus_offset = Vector3(-_player.global_position.x, 1.2, -_player.global_position.z)
	else:
		camera_data.focus_offset = Vector3(0,1.2,0)
	_player.apply_motion_input(_input.consume_motion_input())
	if _player.global_position.y < -2.5:
		_reset_experiment()


func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(_boat):
		_boat.position = Vector3(30 + sin(_elapsed * .045) * 14, -.55, 10 + cos(_elapsed * .045) * 10)
		_boat.rotation.y = -_elapsed * .045
	if _hud == null:
		return
	var pos := _player.global_position
	var cloud := cloud_density(pos.y)
	_cloud_veil.color.a = cloud * .60
	var desired_opacity := lerpf(.16,.55,smoothstep(22.0,32.0,pos.y))
	for sheet: Node in get_children():
		if sheet is MeshInstance3D and str(sheet.name).begins_with("CloudLayer"):
			sheet.visible = _rig.mode_id() != "overview" or pos.y >= 32.0
			if not is_equal_approx(_cloud_sheet_opacity, desired_opacity):
				(sheet.material_override as ShaderMaterial).set_shader_parameter("opacity", desired_opacity)
	_cloud_sheet_opacity = desired_opacity
	for bank: MeshInstance3D in _cloud_banks:
		bank.visible = _rig.mode_id() != "overview" or pos.y >= 32.0
	var state := "御剑" if _player.motion().flight_active else ("疾跑" if _player.motion().sprint_input else "步行")
	_hud.set_status("%s · %s · 高度 %.0f m" % [_place_name(pos), state, maxf(0, pos.y)])
	_projection_button.text = "视角：透视" if _rig.component().projection == Camera3D.PROJECTION_PERSPECTIVE else "视角：正交"


func rig() -> CameraRig:
	return _rig


## 纯读回接口供运行验收；角色高度跨越的是世界固定云层。
func cloud_density(height: float) -> float:
	return smoothstep(32.0, 37.0, height) * (1.0 - smoothstep(43.0, 48.0, height))


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
	_rig.request_mode("orbit")


func _return_to_hub() -> void:
	_clear_pressed()
	_rig.release_capture()
	assert(get_tree().change_scene_to_file(HUB_SCENE) == OK, "返回移动目录失败")


func _toggle_projection() -> void:
	var data := _rig.component()
	data.projection = Camera3D.PROJECTION_PERSPECTIVE if data.projection == Camera3D.PROJECTION_ORTHOGONAL else Camera3D.PROJECTION_ORTHOGONAL
	data.distance = 15.0 if data.projection == Camera3D.PROJECTION_PERSPECTIVE else 70.0
	data.pitch_degrees = 20.0
	data.size = 30.0
	_rig.request_mode("orbit")


func _panorama() -> void:
	var data := _rig.component()
	data.projection = Camera3D.PROJECTION_ORTHOGONAL
	data.distance = 240.0
	data.size = 210.0
	data.yaw_degrees = 80.0
	data.pitch_degrees = 55.0
	_rig.request_mode("overview")


func _build_rig() -> void:
	_rig = RIG.instantiate() as CameraRig
	_rig.name = "CameraRig"
	add_child(_rig)
	var config := CameraRigConfig.new()
	config.start_mode = "orbit"
	config.projection = Camera3D.PROJECTION_PERSPECTIVE
	config.fov = 55.0
	config.follow_preset = "smooth"
	config.yaw_degrees = 80.0
	config.pitch_degrees = 10.0
	config.pitch_min_degrees = -12.0
	config.pitch_max_degrees = 78.0
	config.distance = 16.0
	config.size = 30.0
	config.size_min = 10.0
	config.size_max = 230.0
	config.zoom_step = 6.0
	config.distance_min = 6.0
	config.distance_max = 280.0
	config.distance_step = 3.0
	config.focus_offset = Vector3(0, 1.2, 0)
	config.near = .1
	config.far = 1200.0
	config.smooth_time = .20
	config.mode_choices = PackedStringArray(["orbit", "fixed_follow", "quarter_turn", "overview"])
	config.enable_mode_selection_keys = true
	config.enable_preset_key = true
	config.enable_zoom_keys = true
	config.enable_yaw_keys = true
	config.consume_unowned_rmb = true
	_rig.bind(_camera, _player, config)


func _build_hud() -> void:
	_hud = LabHud.new()
	add_child(_hud)
	_hud.configure("综合游览", "杭州西湖 · 夕照入云", "WASD 移动 · Shift 疾跑 · Space 跳跃 / 上升 · F 御剑 · 右键环绕 · H 详情")
	_hud.set_question("沿湖滨与堤桥步行，御剑到雷峰塔与三潭印月；按住 Space 直飞穿云，云顶约 48 m。")
	_hud.set_controls("WASD / 方向键移动 · Shift 疾跑 · Space 跳跃 / 上升 · Ctrl 下降 · F 起飞 / 收剑\n右键拖动环绕 · Q/E 转向 · 滚轮 / Z/X 缩放 · 1 环绕 / 2 跟随 / 3 四向 / 4 俯览\nV 切正交 / 透视 · M 西湖全景 · Tab 跟随方式 · R 回湖滨 · Esc 返回")
	_hud.set_return_text("返回移动目录")
	_hud.return_pressed.connect(_return_to_hub)
	_projection_button = _button("视角：正交", _toggle_projection)
	_button("西湖全景 M", _panorama)
	_button("回湖滨 R", _reset_experiment)


func _button(title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	_hud.add_button(button)
	return button


func _place_name(pos: Vector3) -> String:
	if pos.y > 48:
		return "云上 · 夕照"
	if pos.y >= 32:
		return "穿云"
	var best := "西湖"
	var distance := 22.0
	for place: Dictionary in _layout["landmarks"]:
		var target := _vector(place["position"])
		var current := Vector2(pos.x-target.x, pos.z-target.z).length()
		if current < distance:
			distance = current
			best = str(place["title"])
	return best


func _build_world() -> void:
	var world := WORLD.instantiate() as Node3D
	world.name = "World"
	add_child(world)
	var materials := {}
	var palette: Dictionary = _layout["palette"]
	for mesh: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("CloudBank"):
			_cloud_banks.append(mesh)
			if DisplayServer.get_name() != "headless":
				var bank := ShaderMaterial.new()
				bank.shader = BANK
				mesh.material_override = bank
				_environment_materials.append(bank)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var label := mesh.mesh.surface_get_material(surface).resource_name
			assert(palette.has(label), "未知西湖材质：" + label)
			if not materials.has(label):
				if DisplayServer.get_name() == "headless":
					var flat := StandardMaterial3D.new()
					flat.albedo_color = Color(str(palette[label]))
					flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					materials[label] = flat
				else:
					var paper := ShaderMaterial.new()
					paper.shader = PAPER
					paper.set_shader_parameter("tint", Color(str(palette[label])))
					paper.set_shader_parameter("flutter", label == "Bird")
					if label in ["Far", "Middle", "Near"]:
						paper.set_shader_parameter("grain_strength", 0.0)
					materials[label] = paper
			mesh.set_surface_override_material(surface, materials[label])
			if not _environment_materials.has(materials[label]):
				_environment_materials.append(materials[label])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if str(mesh.name) in _layout["walk_meshes"]:
			mesh.create_trimesh_collision()
	_boat = world.find_child("TourBoat", true, false) as Node3D
	assert(_boat != null, "西湖缺少游船")
	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000, 1000)
	lake.mesh = plane
	lake.position.y = -1.0
	if DisplayServer.get_name() == "headless":
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(.31,.43,.43)
		lake.material_override = flat
	else:
		var water := ShaderMaterial.new()
		water.shader = WATER
		lake.material_override = water
	_environment_materials.append(lake.material_override)
	world.add_child(lake)
	for spec: Dictionary in _layout["boxes"]:
		_box(world, str(spec["name"]), _vector(spec["position"]), _vector(spec["size"]))
	var bounds: Array = _layout["bounds"]
	_box(world, "WestBoundary", Vector3(float(bounds[0])-1, 90, 0), Vector3(2, 190, 302))
	_box(world, "EastBoundary", Vector3(float(bounds[1])+1, 90, 0), Vector3(2, 190, 302))
	_box(world, "NorthBoundary", Vector3(-11,90,float(bounds[2])-1), Vector3(340,190,2))
	_box(world, "SouthBoundary", Vector3(-11,90,float(bounds[3])+1), Vector3(340,190,2))
	_box(world, "SkyBoundary", Vector3(-11,181,0), Vector3(340,2,302))


func _build_atmosphere() -> void:
	var environment := $WorldEnvironment.environment as Environment
	environment = environment.duplicate() as Environment
	environment.fog_sky_affect = 0.0
	$WorldEnvironment.environment = environment
	if DisplayServer.get_name() == "headless":
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(.92,.74,.56)
	else:
		var sky := Sky.new()
		var paint := ShaderMaterial.new()
		paint.shader = SKY
		sky.sky_material = paint
		environment.sky = sky
		environment.background_mode = Environment.BG_SKY
		for height in [32.0, 38.0, 43.0, 48.0]:
			var cloud := MeshInstance3D.new()
			cloud.name = "CloudLayer%d" % int(height)
			var plane := PlaneMesh.new()
			plane.size = Vector2(950, 950)
			cloud.mesh = plane
			cloud.position = Vector3((height-32)*7, height, (height-32)*11)
			var material := ShaderMaterial.new()
			material.shader = CLOUD
			material.set_shader_parameter("drift", .30+(height-32)*.013)
			material.set_shader_parameter("opacity", .55)
			_environment_materials.append(material)
			cloud.material_override = material
			cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(cloud)
	var layer := CanvasLayer.new()
	layer.name = "CloudVeil"
	layer.layer = -1
	add_child(layer)
	_cloud_veil = ColorRect.new()
	_cloud_veil.color = Color(.87,.86,.79,0)
	_cloud_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cloud_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_cloud_veil)


func _style_character() -> void:
	for mesh: MeshInstance3D in _player.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as StandardMaterial3D
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color *= Color(.9,.92,.86)
			material.metallic = 0
			material.roughness = 1
			material.normal_enabled = false
			mesh.set_surface_override_material(surface, material)


func _box(parent: Node3D, label: String, pos: Vector3, size_value: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_value
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
