extends Node3D

## 同一人物、地面、镜头和移动速度下的步行动作来源比较。
## 只实例化视觉模型，不改正式 Swordsman、能力或移动场景。

const BASE_MODEL: PackedScene = preload("res://game/actors/swordsman/models/cultivator_xianxia_motion_v1.glb")
const SOURCE_MODEL: PackedScene = preload("res://game/actors/swordsman/models/cultivator_walk_sources_v5.glb")
const WALK_SPEED_MPS := 1.55
const START_X := -2.65
const END_X := 2.65
const CLIPS: Array[String] = ["walk", "walk_kaykit", "walk_cmu"]
const NAMES: Array[String] = ["现役手作步行", "KayKit Walking_A", "CMU 16_47 动捕"]
const DESCRIPTIONS: Array[String] = [
	"五组关键姿态；作为原有动作基线。",
	"公开 CC0 动作；跨步和摆臂较夸张，仅供对照。",
	"CMU 普通步行周期；目前最接近日常修士行走。",
]
const NATURAL_SPEED_MPS: Array[float] = [1.5838, 1.3325, 1.2348]

var _active_index := 0
var _paused := false
var _front_view := false
var _visual_root: Node3D
var _model: Node3D
var _player: AnimationPlayer
var _camera: Camera3D
var _title: Label
var _detail: Label


func _ready() -> void:
	_build_world()
	_build_overlay()
	select_candidate(0)


func _process(delta: float) -> void:
	if _paused or _visual_root == null:
		return
	_visual_root.position.x += WALK_SPEED_MPS * delta
	if _visual_root.position.x > END_X:
		_visual_root.position.x = START_X


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3:
			select_candidate(event.keycode - KEY_1)
		KEY_SPACE:
			_paused = not _paused
			if _player != null:
				_player.speed_scale = 0.0 if _paused else WALK_SPEED_MPS / NATURAL_SPEED_MPS[_active_index]
			_update_overlay()
		KEY_V:
			_front_view = not _front_view
			_update_camera()
		KEY_R:
			_visual_root.position.x = START_X
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://levels/experiments/character_movement/movement_lab_hub.tscn")
	get_viewport().set_input_as_handled()


func select_candidate(index: int) -> void:
	assert(index >= 0 and index < CLIPS.size())
	_active_index = index
	if is_instance_valid(_model):
		_model.queue_free()
	_model = (BASE_MODEL if index == 0 else SOURCE_MODEL).instantiate() as Node3D
	assert(_model != null, "步行对照：GLB 必须实例化为 Node3D")
	_visual_root.add_child(_model)
	# 现役人物以局部 +Z 为正面；三段试验统一朝世界 +X 行进。
	_model.rotation.y = Swordsman.visual_yaw_for_aim(Vector3.RIGHT)
	_visual_root.position.x = START_X
	var players: Array[Node] = _model.find_children("*", "AnimationPlayer", true, false)
	assert(players.size() == 1, "步行对照：每个模型需恰有一个 AnimationPlayer")
	_player = players[0] as AnimationPlayer
	var clip: StringName = _find_clip(_player, CLIPS[index])
	assert(clip != StringName(), "步行对照：缺少动作 %s" % CLIPS[index])
	_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_player.play(clip)
	_player.speed_scale = 0.0 if _paused else WALK_SPEED_MPS / NATURAL_SPEED_MPS[index]
	_update_overlay()


func active_candidate() -> int:
	return _active_index


func active_clip() -> String:
	return CLIPS[_active_index]


func _find_clip(player: AnimationPlayer, requested: String) -> StringName:
	for name in player.get_animation_list():
		var text_name := String(name)
		if text_name == requested or text_name.ends_with("/" + requested):
			return name
	return StringName()


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.89, 0.86, 0.80)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.95, 0.92, 0.87)
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -32, 0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	add_child(light)

	_add_box("地面", Vector3(8.0, 0.1, 2.9), Vector3(0, -0.055, 0), Color(0.86, 0.85, 0.82))
	for step in range(-7, 8):
		_add_box("半米刻度", Vector3(0.012, 0.004, 2.7),
			Vector3(float(step) * 0.5, 0.002, 0), Color(0.50, 0.53, 0.51))
	_add_box("跑道轴", Vector3(7.7, 0.005, 0.018),
		Vector3(0, 0.006, 0), Color(0.34, 0.51, 0.46))

	_visual_root = Node3D.new()
	_visual_root.name = "候选人物"
	add_child(_visual_root)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.0
	_camera.current = true
	add_child(_camera)
	_update_camera()


func _add_box(label: String, dimensions: Vector3, at: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	var box := BoxMesh.new()
	box.size = dimensions
	instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	instance.material_override = material
	instance.position = at
	add_child(instance)


func _update_camera() -> void:
	if _front_view:
		_camera.position = Vector3(5.5, 2.3, 0)
	else:
		_camera.position = Vector3(0, 2.3, 8.0)
	_camera.look_at(Vector3(0, 0.9, 0), Vector3.UP)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 110
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 23)
	box.add_child(_title)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 15)
	box.add_child(_detail)
	var help := Label.new()
	help.text = "1 原版  /  2 KayKit  /  3 CMU    空格 暂停    V 正面/侧面    R 重来    Esc 返回"
	box.add_child(help)
	layer.add_child(panel)


func _update_overlay() -> void:
	_title.text = "步行动作来源对照  ·  %s" % NAMES[_active_index]
	_detail.text = "%s  ·  角色速度 %.2f m/s  ·  动作倍率 %.2f%s" % [
		DESCRIPTIONS[_active_index], WALK_SPEED_MPS,
		WALK_SPEED_MPS / NATURAL_SPEED_MPS[_active_index],
		"  ·  已暂停" if _paused else "",
	]
