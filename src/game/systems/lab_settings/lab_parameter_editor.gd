class_name LabParameterEditor
extends ScrollContainer

signal parameter_changed(group: String, field: String, value: Variant)

const CHOICE_LABELS := {
	"fixed_follow": "固定跟随", "quarter_turn": "四向切换", "orbit": "环绕跟随",
	"overview": "全景平移", "hard": "直接跟随", "smooth": "平滑跟随",
	"deadzone": "死区跟随", "lookahead": "前视跟随",
}
var editors: Dictionary = {}
var _content: VBoxContainer


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	follow_focus = true
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 9)
	add_child(_content)


func add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "AccentLabel"
	label.add_theme_font_size_override("font_size", 18)
	_content.add_child(label)


func add_toggle(key: String, text: String, value: bool, callback: Callable) -> CheckButton:
	var button := CheckButton.new()
	button.name = key
	button.text = text
	button.button_pressed = value
	button.custom_minimum_size.y = 38
	_content.add_child(button)
	button.toggled.connect(callback)
	editors[key] = button
	return button


func add_parameters(group: String, parameters: Array, values: Dictionary) -> void:
	for parameter in parameters:
		_add_parameter(group, parameter, values.get(parameter["key"], parameter["default"]))


func _add_parameter(group: String, parameter: Dictionary, value: Variant) -> void:
	var field := str(parameter["key"])
	var editor_key := group + "." + field
	var type := int(parameter["type"])
	var row: BoxContainer = VBoxContainer.new() if type == TYPE_VECTOR3 else HBoxContainer.new()
	row.custom_minimum_size.y = 38
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	var label := Label.new()
	label.text = parameter["label"]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 150
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	if type == TYPE_BOOL:
		var toggle := CheckButton.new()
		toggle.name = field
		toggle.button_pressed = value
		row.add_child(toggle)
		toggle.toggled.connect(func(enabled: bool): parameter_changed.emit(group, field, enabled))
		editors[editor_key] = toggle
	elif not parameter["choices"].is_empty() and type in [TYPE_INT, TYPE_STRING]:
		var choice := OptionButton.new()
		choice.name = field
		choice.custom_minimum_size.x = 132
		for option in parameter["choices"]:
			var text := str(CHOICE_LABELS.get(option, option))
			if field == "projection":
				text = "透视" if option == Camera3D.PROJECTION_PERSPECTIVE else "正交"
			choice.add_item(text)
		choice.select(parameter["choices"].find(value))
		row.add_child(choice)
		choice.item_selected.connect(func(index: int):
			parameter_changed.emit(group, field, parameter["choices"][index]))
		editors[editor_key] = choice
	elif type in [TYPE_FLOAT, TYPE_INT]:
		var spin := _spin(parameter, float(value))
		spin.name = field
		spin.custom_minimum_size.x = 112
		row.add_child(spin)
		spin.value_changed.connect(func(number: float):
			parameter_changed.emit(group, field, int(number) if type == TYPE_INT else number))
		editors[editor_key] = spin
	elif type == TYPE_VECTOR3:
		var coordinates: Array = value.duplicate()
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(box)
		for axis in range(3):
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(column)
			var axis_label := Label.new()
			axis_label.text = ["X", "Y", "Z"][axis]
			axis_label.add_theme_font_size_override("font_size", 12)
			column.add_child(axis_label)
			var spin := _spin(parameter, float(coordinates[axis]))
			spin.custom_minimum_size.x = 57
			spin.tooltip_text = ["X", "Y", "Z"][axis]
			column.add_child(spin)
			spin.value_changed.connect(func(number: float):
				coordinates[axis] = number
				parameter_changed.emit(group, field, coordinates.duplicate()))
		editors[editor_key] = box
	elif type == TYPE_PACKED_STRING_ARRAY:
		var box := VBoxContainer.new()
		row.add_child(box)
		var selected: Array = value.duplicate()
		for option in parameter["choices"]:
			var toggle := CheckBox.new()
			toggle.text = CHOICE_LABELS.get(option, option)
			toggle.button_pressed = selected.has(option)
			box.add_child(toggle)
			toggle.toggled.connect(func(enabled: bool):
				if enabled and not selected.has(option):
					selected.append(option)
				elif not enabled:
					selected.erase(option)
				parameter_changed.emit(group, field, selected.duplicate()))
		editors[editor_key] = box
	elif type == TYPE_STRING:
		var line := LineEdit.new()
		line.text = value
		line.custom_minimum_size.x = 132
		row.add_child(line)
		line.text_submitted.connect(func(text: String): parameter_changed.emit(group, field, text))
		editors[editor_key] = line


func _spin(parameter: Dictionary, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = parameter["min"]
	spin.max_value = parameter["max"]
	spin.step = parameter["step"]
	spin.value = value
	spin.get_line_edit().select_all_on_focus = true
	return spin
