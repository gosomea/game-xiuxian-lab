extends Node3D

## 移动综合工作台：只编排场地、共享宿主、参数 UI 与全局设置操作。
const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const ACTOR := preload("res://game/actors/swordsman/swordsman.tscn")
const RIG := preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")
const LAB_THEME := preload("res://ui/lab_theme.tres")
const SPAWN := Vector3(-2.0, 0.15, 3.0)

var _actor: Swordsman
var _rig: CameraRig
var _camera: Camera3D
var _input := MovementLabInput.new()
var _tabs: TabContainer
var _status: Label
var _readout: Label
var _panels: Array[LabParameterEditor] = []
var _message := ""
var save_button: Button
var revert_button: Button
var restore_button: Button
var return_button: Button


func _ready() -> void:
	_build_stage()
	_actor = ACTOR.instantiate() as Swordsman
	_actor.name = "Swordsman"
	_actor.position = SPAWN
	add_child(_actor)
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_rig = RIG.instantiate() as CameraRig
	_rig.name = "CameraRig"
	add_child(_rig)
	var config := CameraRigConfig.new()
	config.start_mode = "orbit"
	config.mode_choices = PackedStringArray(LabParameterSchema.MODE_CHOICES)
	config.enable_mode_selection_keys = true
	config.consume_unowned_rmb = true
	config.size = 18.0
	config.distance = 22.0
	config.pitch_degrees = 45.0
	config.focus_offset = Vector3(0.0, 0.8, 0.0)
	_rig.bind(_camera, _actor, config)
	_rig.advance(0.0)
	_build_ui()
	_build_editors()
	_message = LabDefaults.load_error


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
	if event is InputEventKey:
		var key := event as InputEventKey
		if _input.track_key(key):
			get_viewport().set_input_as_handled()
		elif MovementLabInput.is_key_down_edge(key):
			var code := MovementLabInput.key_code(key)
			if code == KEY_R:
				reset_actor()
				get_viewport().set_input_as_handled()
			elif code == KEY_ESCAPE:
				_return_to_hub()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_input.clear()
		if is_instance_valid(_actor):
			_actor.clear_input()


func _physics_process(_delta: float) -> void:
	if _actor == null:
		return
	_actor.apply_motion_input(_input.consume_motion_input())
	if _actor.position.y < -8.0 or absf(_actor.position.x) > 90.0 or absf(_actor.position.z) > 90.0:
		reset_actor()


func _process(_delta: float) -> void:
	if _readout == null or _actor == null:
		return
	var motion := _actor.motion()
	var state := "御剑" if motion.flight_active else ("地面" if motion.on_floor else "空中")
	_readout.text = "%s  ·  水平 %.2f m/s  ·  高度 %.2f m\nWASD 移动 · Shift 疾跑 · Space 跳跃/上升 · Ctrl 下降\nF 御剑 · 右键环绕 · 1–4 换镜头 · R 复位 · Esc 返回" % [
		state, Vector2(_actor.velocity.x, _actor.velocity.z).length(), _actor.position.y]
	_status.text = ("实时预览 · 尚未保存" if LabDefaults.is_dirty() else "全局默认 · 已保存") \
		+ ("\n" + _message if not _message.is_empty() else "")


func actor() -> Swordsman:
	return _actor


func rig() -> CameraRig:
	return _rig


func reset_actor() -> void:
	_input.clear()
	_actor.reset_motion()
	_actor.position = SPAWN


func editor(group: String, field: String) -> Control:
	for panel in _panels:
		var key := group + "." + field if not group.is_empty() else field
		if panel.editors.has(key):
			return panel.editors[key]
	return null


func save_defaults() -> void:
	var error := LabDefaults.save()
	_message = "已保存，其他三维实验与下次启动会沿用" if error.is_empty() else error


func _parameter_changed(group: String, field: String, value: Variant) -> void:
	var error := LabDefaults.set_camera_value(field, value) if group == "camera" \
		else LabDefaults.set_component_value(group, field, value)
	_message = "参数已实时应用" if error.is_empty() else error
	if not error.is_empty() or (group == "camera" and field in ["start_mode", "mode_choices"]):
		_build_editors()


func _ability_changed(kind: String, enabled: bool) -> void:
	var error := LabDefaults.set_ability(kind, enabled)
	_message = ("行为已恢复" if enabled else "行为已卸载") if error.is_empty() else error
	if not error.is_empty():
		_build_editors()


func _revert() -> void:
	LabDefaults.revert()
	_message = "已撤销未保存的修改"
	_build_editors()


func _restore() -> void:
	LabDefaults.restore_original()
	var error := LabDefaults.save()
	_message = "已恢复各场景原始默认" if error.is_empty() else error
	_build_editors()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _editor_theme()
	var margin := MarginContainer.new()
	root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.offset_left = 18.0
	margin.offset_top = 18.0
	margin.offset_right = 420.0
	margin.offset_bottom = -18.0
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var padding := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(padding)
	var column := VBoxContainer.new()
	padding.add_child(column)
	var title := Label.new()
	title.text = "移动综合工作台"
	title.add_theme_font_size_override("font_size", 23)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "参数与行为装卸 · 全实验室三维默认"
	subtitle.add_theme_font_size_override("font_size", 14)
	column.add_child(subtitle)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 14)
	column.add_child(_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	save_button = _button(actions, "保存为全局默认", save_defaults)
	save_button.theme_type_variation = "PrimaryButton"
	revert_button = _button(actions, "撤销未保存", _revert)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	column.add_child(footer)
	restore_button = _button(footer, "恢复原始默认", _restore)
	return_button = _button(footer, "返回移动目录", _return_to_hub)
	_readout = Label.new()
	root.add_child(_readout)
	_readout.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_readout.offset_left = -510.0
	_readout.offset_top = -105.0
	_readout.offset_right = -20.0
	_readout.offset_bottom = -20.0
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.add_theme_font_size_override("font_size", 14)
	_readout.add_theme_color_override("font_color", Color(0.12, 0.25, 0.23))


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 14)
	button.custom_minimum_size.y = 42
	parent.add_child(button)
	button.pressed.connect(callback)
	return button


func _editor_theme() -> Theme:
	var theme := LAB_THEME.duplicate() as Theme
	var ink := Color(0.145, 0.239, 0.212)
	for type in ["TabContainer", "TabBar", "LineEdit", "OptionButton", "CheckButton", "CheckBox"]:
		for color in ["font_color", "font_selected_color", "font_unselected_color", "font_hover_color", "font_pressed_color"]:
			theme.set_color(color, type, ink)
	for type in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, LAB_THEME.get_stylebox("pressed", "Button"))
		theme.set_stylebox("tab_unselected", type, LAB_THEME.get_stylebox("normal", "Button"))
		theme.set_stylebox("tab_hovered", type, LAB_THEME.get_stylebox("hover", "Button"))
	theme.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	var input_style := LAB_THEME.get_stylebox("normal", "Button").duplicate() as StyleBox
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	input_style.content_margin_top = 8
	input_style.content_margin_bottom = 8
	theme.set_stylebox("normal", "LineEdit", input_style)
	theme.set_stylebox("focus", "LineEdit", LAB_THEME.get_stylebox("focus", "Button"))
	return theme


func _build_editors() -> void:
	var selected := _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_panels.clear()
	var motion_panel := _new_panel("移动")
	motion_panel.add_heading("行为装卸")
	var installed := (_actor.get_node("ActorAssembly") as ActorAssembly).installed_config()
	for kind in ["move", "jump", "flight"]:
		var text: String = {"move": "平面移动", "jump": "跳跃", "flight": "御剑"}[kind]
		var enabled := LabDefaults.ability_enabled(kind, bool(installed.get(kind + "_enabled")))
		motion_panel.add_toggle(kind, text, enabled,
			func(active: bool): _ability_changed(kind, active))
	motion_panel.add_heading("运动参数")
	var groups := LabParameterSchema.component_groups()
	var motion_values: Dictionary = {}
	for parameter in groups["SwordsmanMotionComponent"]:
		motion_values[parameter["key"]] = LabParameterSchema.encode(_actor.motion().get(parameter["key"]))
	motion_panel.add_parameters("SwordsmanMotionComponent", groups["SwordsmanMotionComponent"], motion_values)
	var camera_panel := _new_panel("镜头")
	camera_panel.add_toggle("camera", "镜头行为", _rig.is_active(),
		func(enabled: bool): _ability_changed("camera", enabled))
	var camera_values: Dictionary = {}
	var camera_config := _rig.configuration()
	for parameter in LabParameterSchema.camera_parameters():
		camera_values[parameter["key"]] = LabParameterSchema.encode(camera_config.get(parameter["key"]))
	camera_panel.add_parameters("camera", LabParameterSchema.camera_parameters(), camera_values)
	var other_panel := _new_panel("其他组件")
	for group in groups:
		if group == "SwordsmanMotionComponent":
			continue
		other_panel.add_heading(LabParameterSchema.GROUP_LABELS.get(group, group))
		other_panel.add_parameters(group, groups[group], LabDefaults.snapshot()["components"].get(group, {}))
	_tabs.current_tab = clampi(selected, 0, 2)
	if save_button != null:
		save_button.grab_focus()


func _new_panel(title: String) -> LabParameterEditor:
	var panel := LabParameterEditor.new()
	panel.name = title
	_tabs.add_child(panel)
	panel.parameter_changed.connect(_parameter_changed)
	_panels.append(panel)
	return panel


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color(0.83, 0.88, 0.86)
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color(0.8, 0.85, 0.8)
	resource.ambient_light_energy = 0.5
	environment.environment = resource
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	add_child(sun)
	_box("Ground", Vector3(0, -0.2, 0), Vector3(36, 0.4, 30), Color(0.7, 0.76, 0.69))
	_box("LandingPlatform", Vector3(4, 0.6, -3), Vector3(3, 1.2, 3), Color(0.48, 0.63, 0.55))
	_box("HighPlatform", Vector3(8, 2, -8), Vector3(3, 4, 3), Color(0.38, 0.53, 0.48))
	_box("Wall", Vector3(-7, 1, -4), Vector3(0.6, 2, 7), Color(0.63, 0.62, 0.51))
	for index in range(-3, 4):
		_box("Marker%d" % index, Vector3(float(index * 4), 0.015, 5), Vector3(0.08, 0.03, 4), Color(0.9, 0.91, 0.78), false)


func _box(label: String, position_value: Vector3, dimensions: Vector3, color: Color, solid := true) -> void:
	var node := StaticBody3D.new() if solid else Node3D.new()
	node.name = label
	node.position = position_value
	add_child(node)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
	node.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = dimensions
		collision.shape = shape
		node.add_child(collision)


func _return_to_hub() -> void:
	_input.clear()
	_actor.clear_input()
	_rig.release_capture()
	get_tree().change_scene_to_file(HUB_SCENE)
