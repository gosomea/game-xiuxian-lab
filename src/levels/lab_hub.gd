extends Control

const Catalog := preload("res://game/systems/lab_catalog/lab_catalog.gd")
const EMPTY_STAGE := "res://levels/empty_stage.tscn"

var _entries: Array = []
var _buttons: Dictionary = {}
var _selected: Dictionary = {}

@onready var _grid: GridContainer = %ModuleGrid
@onready var _launch: Button = %LaunchButton


func _ready() -> void:
	%StageButton.pressed.connect(_open_scene.bind(EMPTY_STAGE))
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	_launch.pressed.connect(_launch_selected)
	var result := Catalog.read()
	if not result["errors"].is_empty():
		%DetailTitle.text = "清单需要修复"
		%DetailQuestion.text = "\n".join(result["errors"])
		%Count.text = "—"
		return
	_entries = result["modules"]
	var scene_count := 0
	for index in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		_add_entry(entry, index)
		if Catalog.can_open(entry):
			scene_count += 1
	%Count.text = "%d / %d" % [scene_count, _entries.size()]
	if not _entries.is_empty():
		select_module(_entries[0]["id"])
		(_buttons[_entries[0]["id"]] as Button).grab_focus()
	else:
		%DetailTitle.text = "从一个模块开始"
		%DetailQuestion.text = "清单中还没有实验条目。"


func select_module(id: String) -> void:
	for entry in _entries:
		if entry["id"] == id:
			_selected = entry
			break
	if _selected.is_empty():
		return
	for button_id in _buttons:
		(_buttons[button_id] as Button).theme_type_variation = "ModuleSelected" if button_id == id else ""
	%DetailStatus.text = "%s  /  %s" % [_selected["category"], Catalog.STATUS_LABELS[_selected["status"]]]
	%DetailTitle.text = _selected["title"]
	%DetailQuestion.text = _selected["question"]
	var lines := PackedStringArray()
	for item in _selected["scope"]:
		lines.append("· " + str(item))
	%DetailScope.text = "\n".join(lines)
	var dependencies := PackedStringArray()
	for dependency in _selected["depends_on"]:
		for entry in _entries:
			if entry["id"] == dependency:
				dependencies.append(entry["title"])
	%DetailDependencies.text = "可独立起步" if dependencies.is_empty() else "组合时关联：" + "、".join(dependencies)
	_launch.disabled = not Catalog.can_open(_selected)
	_launch.text = "场景尚未搭建" if _launch.disabled else "进入实验场景"


func _add_entry(entry: Dictionary, index: int) -> void:
	var button := Button.new()
	button.name = "Module_" + entry["id"]
	button.custom_minimum_size = Vector2(0, 112)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = entry["summary"]
	button.pressed.connect(select_module.bind(entry["id"]))
	_grid.add_child(button)
	_buttons[entry["id"]] = button
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var caption := Label.new()
	caption.text = "%02d  /  %s" % [index + 1, entry["category"]]
	caption.add_theme_font_size_override("font_size", 12)
	caption.theme_type_variation = "MutedLabel"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(caption)
	var title := Label.new()
	title.text = entry["title"]
	title.add_theme_font_size_override("font_size", 20)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var status := Label.new()
	status.text = Catalog.STATUS_LABELS[entry["status"]]
	status.add_theme_font_size_override("font_size", 12)
	status.theme_type_variation = "GoldLabel" if entry["status"] == "planned" else "AccentLabel"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status)


func _launch_selected() -> void:
	if Catalog.can_open(_selected):
		_open_scene(_selected["scene"])


func _open_scene(path: String) -> void:
	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		%DetailQuestion.text = "无法打开场景（错误 %d），请检查资源。" % result
