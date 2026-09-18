extends Control

## 角色移动子实验目录（顶层 lab_hub → 本目录 → 子场景）。
##
## 职责边界：
## - 数据契约：res://data/content/character_movement_subexperiments.json 是子实验清单的真相源；
##   本场景只读取、校验、生成入口与显示详情，不复制角色与能力逻辑，不建立通用菜单框架，
##   也不改动 core/。数据读取与本目录的按钮生成都留在本脚本内。
## - 未有可运行场景的条目 scene 为空、状态 planned：界面禁用启动并如实显示「尚未落地」，
##   不为计划条目伪造路径或可运行入口。
## - 返回：Esc 与「返回实验目录」按钮都回到顶层 lab_hub；未来子场景的返回路径由各子场景自理。

const PARENT_SCENE := "res://levels/lab_hub.tscn"
const DATA_PATH := "res://data/content/character_movement_subexperiments.json"
const SCHEMA_VERSION := 1
const MODULE_ID := "character_movement"
## 清单契约：条目集合与顺序由 note 决定（镜头 → 动作 → 地形 → 御剑 → 压力场 → 庭院 → 群山）。
const REQUIRED_IDS := [
	"camera_lab",
	"motion_stage",
	"ground_contact_course",
	"sword_flight_course",
	"state_transition_lab",
	"movement_garden",
	"mountain_realm",
]
const Catalog := preload("res://game/systems/lab_catalog/lab_catalog.gd")

var _entries: Array = []
var _buttons: Dictionary = {}
var _selected: Dictionary = {}
var _parent_scene := PARENT_SCENE

@onready var _grid: GridContainer = %EntryGrid
@onready var _launch: Button = %LaunchButton


func _ready() -> void:
	%BackButton.pressed.connect(_return_to_parent)
	_launch.pressed.connect(_launch_selected)
	var result := read()
	_parent_scene = str(result["parent_scene"])
	if not result["errors"].is_empty():
		%DetailStatus.text = "子实验清单  /  需要修复"
		%DetailTitle.text = "目录不可用"
		%DetailQuestion.text = "\n".join(result["errors"])
		%DetailStage.text = "定位：—"
		%DetailPath.text = "数据：" + DATA_PATH
		%Count.text = "—"
		%Caption.text = "清单存在错误"
		return
	_entries = result["subexperiments"]
	var scene_count := 0
	for index in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		_add_entry(entry, index)
		if can_open(entry):
			scene_count += 1
	%Count.text = "%d / %d" % [scene_count, _entries.size()]
	if _entries.is_empty():
		%DetailTitle.text = "尚无子实验"
		%DetailQuestion.text = "子实验清单为空。"
		return
	# 键盘落点优先给第一个真正可进入的条目，计划条目仍可上下移动查看问题。
	var focus_entry: Dictionary = _entries[0]
	for entry in _entries:
		if can_open(entry):
			focus_entry = entry
			break
	select_entry(focus_entry["id"])
	(_buttons[focus_entry["id"]] as Button).grab_focus()


## 读取并校验子实验清单。返回 {subexperiments, parent_scene, errors}；errors 非空时不提供任何入口。
static func read() -> Dictionary:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return {
			"subexperiments": [],
			"parent_scene": PARENT_SCENE,
			"errors": PackedStringArray(["无法读取子实验清单：%s" % DATA_PATH]),
		}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {
			"subexperiments": [],
			"parent_scene": PARENT_SCENE,
			"errors": PackedStringArray(["子实验清单 JSON 错误：%s" % parser.get_error_message()]),
		}
	var data: Variant = parser.data
	var errors := validate(data)
	if not errors.is_empty():
		return {"subexperiments": [], "parent_scene": PARENT_SCENE, "errors": errors}
	var root: Dictionary = data
	return {
		"subexperiments": root["subexperiments"],
		"parent_scene": str(root.get("parent_scene", PARENT_SCENE)),
		"errors": errors,
	}


## 结构与状态契约：字段类型、ID 唯一、状态受控、planned 不得挂场景、ready 必须有场景、
## 场景必须在 levels 下且真实可加载，并覆盖 REQUIRED_IDS 全集。
static func validate(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary:
		return PackedStringArray(["子实验清单顶层必须是对象"])
	var root: Dictionary = data
	if root.get("schema_version") != SCHEMA_VERSION:
		errors.append("子实验清单需要 schema_version: %d" % SCHEMA_VERSION)
	if str(root.get("module", "")) != MODULE_ID:
		errors.append("子实验清单 module 必须为 %s" % MODULE_ID)
	if str(root.get("parent_scene", "")) != PARENT_SCENE:
		errors.append("子实验清单 parent_scene 必须为 %s" % PARENT_SCENE)
	if not root.get("subexperiments") is Array:
		errors.append("子实验清单需要 subexperiments 数组")
		return errors
	var entries: Array = root["subexperiments"]
	var ids: Array[String] = []
	for value in entries:
		if not value is Dictionary:
			errors.append("每个子实验必须是对象")
			continue
		var entry: Dictionary = value
		var id := str(entry.get("id", ""))
		for key in ["id", "title", "stage", "question", "status", "scene"]:
			if not entry.get(key) is String:
				errors.append("子实验字段 %s 必须是文本：%s" % [key, id])
		if id.is_empty():
			errors.append("子实验 ID 不能为空")
		elif id in ids:
			errors.append("重复子实验 ID：%s" % id)
		else:
			ids.append(id)
		if str(entry.get("title", "")).strip_edges().is_empty():
			errors.append("子实验标题不能为空：%s" % id)
		if str(entry.get("question", "")).strip_edges().is_empty():
			errors.append("子实验问题不能为空：%s" % id)
		var status := str(entry.get("status", ""))
		var scene := str(entry.get("scene", ""))
		if status not in Catalog.STATUSES:
			errors.append("未知子实验状态：%s / %s" % [id, status])
		if status == "planned" and not scene.is_empty():
			errors.append("待探索子实验不得挂载场景：%s" % id)
		if status == "ready" and scene.is_empty():
			errors.append("当前可用子实验必须有独立场景：%s" % id)
		if not scene.is_empty() and not _valid_scene(scene):
			errors.append("子实验场景无法加载或不在 levels 内：%s / %s" % [id, scene])
	for required in REQUIRED_IDS:
		if required not in ids:
			errors.append("子实验清单缺少条目：%s" % required)
	return errors


## 只有真实存在、状态非 planned 且有场景的条目可以进入。
static func can_open(entry: Dictionary) -> bool:
	var scene := str(entry.get("scene", ""))
	return str(entry.get("status", "planned")) in ["exploring", "ready"] and _valid_scene(scene)


static func _valid_scene(scene: String) -> bool:
	if not scene.begins_with("res://levels/") or not scene.ends_with(".tscn") or ".." in scene:
		return false
	return ResourceLoader.exists(scene, "PackedScene") and load(scene) is PackedScene


func select_entry(id: String) -> void:
	for entry in _entries:
		if entry["id"] == id:
			_selected = entry
			break
	if _selected.is_empty():
		return
	for button_id in _buttons:
		(_buttons[button_id] as Button).theme_type_variation = "ModuleSelected" if button_id == id else ""
	var openable := can_open(_selected)
	var status_label: String = Catalog.STATUS_LABELS[_selected["status"]]
	%DetailStatus.text = "子实验  /  %s" % status_label
	%DetailTitle.text = _selected["title"]
	%DetailQuestion.text = _selected["question"]
	%DetailStage.text = "定位：" + _selected["stage"]
	if openable:
		%DetailPath.text = "入口：" + str(_selected["scene"])
	else:
		%DetailPath.text = "入口：尚未落地（scene 为空，状态 %s）" % status_label
	_launch.disabled = not openable
	_launch.text = "进入子实验" if openable else "场景尚未搭建"


func _add_entry(entry: Dictionary, index: int) -> void:
	var button := Button.new()
	button.name = "Entry_" + entry["id"]
	button.custom_minimum_size = Vector2(0, 112)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = entry["question"]
	button.pressed.connect(select_entry.bind(entry["id"]))
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
	caption.text = "%02d  /  %s" % [index + 1, entry["stage"]]
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
	status.text = Catalog.STATUS_LABELS[entry["status"]] if can_open(entry) else "%s · 未落地" % Catalog.STATUS_LABELS[entry["status"]]
	status.add_theme_font_size_override("font_size", 12)
	status.theme_type_variation = "AccentLabel" if can_open(entry) else "GoldLabel"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status)


func _unhandled_input(event: InputEvent) -> void:
	# Esc 返回顶层实验目录；焦点在按钮上时也不拦截（ui_cancel 无按钮消费者）。
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_open_scene(_parent_scene)


func _return_to_parent() -> void:
	_open_scene(_parent_scene)


func _launch_selected() -> void:
	if can_open(_selected):
		_open_scene(str(_selected["scene"]))


func _open_scene(path: String) -> void:
	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		%DetailQuestion.text = "无法打开场景（错误 %d）：%s" % [result, path]
