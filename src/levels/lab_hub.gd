extends Control

## 顶层实验目录：卡片一次点击直达（本目录 → 子目录 → 实验，共 2 击）。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md「入口与 HUD」：
## - 可进入模块：点击卡片直接进入其 scene（不再有「先选中 → 再点进入」的中间步）。
## - planned 模块：点击只展开说明（详情面板 / 说明按钮 / hover tooltip），不进入。
## - 详情默认隐藏，I 按钮或 I 键展开，Esc 先关详情。
## - 返回记忆：离开本目录时记录最后选中项与滚动位置，回来时恢复；初始化阶段不写记忆，
##   避免用初始 scroll=0 覆盖上次离开时保存的值。

const Catalog := preload("res://game/systems/lab_catalog/lab_catalog.gd")
const EMPTY_STAGE := "res://levels/empty_stage.tscn"

## 跨场景记忆：仅在本次运行内有效，不写用户配置。
static var _remembered_id := ""
static var _remembered_scroll := 0

var _entries: Array = []
var _buttons: Dictionary = {}
var _selected: Dictionary = {}
## 本次进入时要从静态记忆恢复的滚动值；进入后即被真实滚动值接管。
var _pending_scroll := 0

@onready var _grid: GridContainer = %ModuleGrid
@onready var _details: PanelContainer = %Details
@onready var _scroll: ScrollContainer = %ModuleScroll
@onready var _details_button: Button = %DetailsButton


func _ready() -> void:
	%StageButton.pressed.connect(_open_scene.bind(EMPTY_STAGE))
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	_details_button.pressed.connect(_toggle_details)
	_details.visible = false
	# 先取走记忆，再允许任何写入；恢复在布局完成后执行。
	_pending_scroll = _remembered_scroll
	_restore_scroll.call_deferred()
	var result := Catalog.read()
	if not result["errors"].is_empty():
		%DetailTitle.text = "清单需要修复"
		%DetailQuestion.text = "\n".join(result["errors"])
		%Count.text = "—"
		_details.visible = true
		return
	_entries = result["modules"]
	var scene_count := 0
	for index in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		_add_entry(entry, index)
		if Catalog.can_open(entry):
			scene_count += 1
	%Count.text = "%d / %d" % [scene_count, _entries.size()]
	if _entries.is_empty():
		%DetailTitle.text = "从一个模块开始"
		%DetailQuestion.text = "清单中还没有实验条目。"
		return
	var focus_entry := _entry_by_id(_remembered_id)
	if focus_entry.is_empty():
		focus_entry = _entries[0]
	select_module(str(focus_entry["id"]))
	(_buttons[focus_entry["id"]] as Button).grab_focus()


## 卡片点击：可进入 → 直接进入；planned → 只展开说明。
func activate_entry(id: String) -> void:
	var entry := _entry_by_id(id)
	if entry.is_empty():
		return
	if Catalog.can_open(entry):
		_remember(str(entry["id"]))
		_open_scene(str(entry["scene"]))
	else:
		select_module(str(entry["id"]))
		_details.visible = true


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


func _toggle_details() -> void:
	_details.visible = not _details.visible


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	if code == KEY_I:
		_toggle_details()
		get_viewport().set_input_as_handled()
	elif code == KEY_ESCAPE and _details.visible:
		# Esc 先关详情；详情已关时本目录没有上级返回目标，不消费事件。
		_details.visible = false
		get_viewport().set_input_as_handled()


func _add_entry(entry: Dictionary, index: int) -> void:
	var button := Button.new()
	button.name = "Module_" + entry["id"]
	button.custom_minimum_size = Vector2(0, 112)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = entry["summary"]
	# 键盘可达：焦点移动即更新详情；回车才是「进入 / 展开」动作。
	button.focus_entered.connect(select_module.bind(entry["id"]))
	button.pressed.connect(activate_entry.bind(entry["id"]))
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


func _open_scene(path: String) -> void:
	# 离开目录前记录当前选中项与滚动位置：无论经卡片、空白工作台还是后续返回按钮离开。
	if not _selected.is_empty():
		_remember(str(_selected["id"]))
	# 先缓存 viewport 并处理事件，切换场景后本节点可能已离树，不能再访问 get_viewport()。
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		_show_error("无法打开场景（错误 %d）：%s" % [result, path])


## 失败必须让用户看见：展开详情面板并写入错误信息。
func _show_error(message: String) -> void:
	_details.visible = true
	%DetailStatus.text = "打开失败"
	%DetailTitle.text = "无法进入场景"
	%DetailQuestion.text = message


func _entry_by_id(id: String) -> Dictionary:
	for entry in _entries:
		if entry["id"] == id:
			return entry
	return {}


func _remember(id: String) -> void:
	_remembered_id = id
	if _scroll != null:
		_remembered_scroll = _scroll.scroll_vertical


func _restore_scroll() -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical = _pending_scroll


## 测试用：只读暴露记忆值（生产代码不写测试专用 setter）。
static func remembered_selection() -> String:
	return _remembered_id


static func remembered_scroll() -> int:
	return _remembered_scroll
