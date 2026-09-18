class_name LabHud
extends Control

## 共享紧凑 HUD（S0）：七个实验场景共用的 Control + Theme 变体骨架。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md
## 「入口与 HUD」与 notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md。
##
## 默认紧凑：一行标题块（标题 + 类目小字，同行） + 核心状态行 + 可选核心指标行 + 短提示，
## 长控制说明进详情 tooltip / 折叠面板；实验问题与调试读数默认折叠，H / F1 展开，
## Esc 先关详情再交给场景返回。压力场等以核心账本为观测对象的场景用 set_core_summary() 常显。
##
## 布局约束（响应 960x640 起）：
## - 标题块与按钮在同一个 HFlowContainer 里：宽窗一行放得下，窄窗自动换行，不会撑宽；
## - 详情面板是下方独立限宽行，展开只向下长，不参与按钮行宽度计算；
## - 详情内只有一层滚动（RichTextLabel 自身），并有明确最小尺寸，不会塌成 0；
## - 根 Control 与所有容器 mouse_filter = IGNORE，HUD 不拦截 3D 视口的鼠标操作；
## - 遮挡按真实 panel / button 矩形并集计算，不把透明容器整行算作遮挡。
##
## 用法（七场集成）：
##   var hud := LabHud.new()
##   add_child(hud)
##   hud.configure("CHARACTER MOVEMENT · MOTION STAGE", "人物动作工作台", "Esc 返回 · H 详情")
##   hud.set_controls("WASD 移动 · Space 跳跃 · Ctrl 下降 · F 御剑 · 1/2/3 视角 · 滚轮缩放 · R 重置")
##   hud.set_status("着地=是  御剑=否  水平 0.00 m/s")
##   hud.set_question("待机、起步、跑动、转身、跳跃、御剑、降落及其过渡是否清楚？")
##   hud.return_pressed.connect(_return_to_hub)
##
## 边界：本组件不读游戏状态、不认识任何 Capability / Component；状态文本由场景写入。

signal return_pressed
## 详情面板可见性变化：场景据此联动自己的细节层（时间线 / 逐条账本等）。
signal details_ui_changed(visible_now: bool)

const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")
## 命中区与字号是批准 note 的试验初值：标题 18-20 / 正文 13-14 / 按钮高 >= 32。
const TITLE_VARIATION := "HudTitle"
const READOUT_VARIATION := "HudReadout"
const HINT_VARIATION := "HudHint"
const PANEL_VARIATION := "HudPanel"
const BUTTON_VARIATION := "HudButton"
const MIN_HIT_HEIGHT := 34.0
## 详情面板的限宽与最小高度：不随标题/按钮行变宽，内部文字在此宽度内换行。
const DETAILS_WIDTH := 380.0
const DETAILS_MIN_HEIGHT := 104.0

const TOGGLE_KEYS: Array[Key] = [KEY_H, KEY_F1]

var _layer: CanvasLayer
var _interface: Control
var _title_panel: PanelContainer
var _kicker: Label
var _title: Label
var _status: Label
var _core: Label
var _hint: Label
var _question: Label
var _debug_view: RichTextLabel
var _details_panel: PanelContainer
var _details_toggle: Button
var _return_button: Button
var _header_flow: HFlowContainer
var _details_visible := false

var _debug_lines := PackedStringArray()
var _question_text := ""
var _controls_text := ""


func _ready() -> void:
	# 根 Control 不接收鼠标：HUD 只占视觉层，不挡 3D 视口的拖拽/滚轮。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	if code in TOGGLE_KEYS:
		toggle_details()
		get_viewport().set_input_as_handled()
	elif code == KEY_ESCAPE and _details_visible:
		# Esc 先关详情；详情已关时不消费，交回场景的返回路径。
		hide_details()
		get_viewport().set_input_as_handled()


# --- 场景写入 API -----------------------------------------------------------


## 紧凑默认内容：类目小字（与标题同行）、标题、短提示。
func configure(kicker: String, title: String, hint: String) -> void:
	_kicker.text = kicker
	_kicker.visible = not kicker.strip_edges().is_empty()
	_title.text = title
	_hint.text = hint


## 完整控制说明：不常显，进详情按钮 tooltip（必要时也进折叠面板）。
func set_controls(text: String) -> void:
	_controls_text = text
	var tip := text
	if tip.is_empty():
		tip = "H / F1 展开本场问题与调试读数"
	_details_toggle.tooltip_text = tip


## 核心状态行：常显，保持一行，不自动换行撑高。
func set_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


## 核心账本指标：常显的紧凑摘要（压力场等以账本为观测对象的场景使用）。
func set_core_summary(text: String) -> void:
	_core.text = text
	_core.visible = not text.is_empty()


## 本实验回答的问题：默认折叠，只在详情面板与 tooltip 中出现。
func set_question(text: String) -> void:
	_question_text = text
	_question.text = "本场问题：" + text
	_question.visible = not text.strip_edges().is_empty()
	_refresh_details_visibility()


## 折叠面板正文：每行一条调试读数（帧计、姿态、账本明细等）。
func set_debug_lines(lines: PackedStringArray) -> void:
	_debug_lines = lines
	_debug_view.text = "\n".join(lines)
	_refresh_details_visibility()


func append_debug_line(text: String) -> void:
	_debug_lines.append(text)
	_debug_view.text = "\n".join(_debug_lines)
	_refresh_details_visibility()


func details_visible() -> bool:
	return _details_visible


func show_details() -> void:
	_details_visible = true
	_details_toggle.text = "详情 (H) ▾"
	_refresh_details_visibility()
	details_ui_changed.emit(true)


func hide_details() -> void:
	_details_visible = false
	_details_toggle.text = "详情 (H) ▸"
	_details_panel.visible = false
	details_ui_changed.emit(false)


func toggle_details() -> void:
	if _details_visible:
		hide_details()
	else:
		show_details()


# --- 只读访问（HUD 集成与运行验收读回；不暴露内部节点） -----------------------


func title_text() -> String:
	return _title.text


func status_text() -> String:
	return _status.text


func core_summary_text() -> String:
	return _core.text


func debug_text() -> String:
	return _debug_view.text


func question_text() -> String:
	return _question.text


func hint_text() -> String:
	return _hint.text


func return_text() -> String:
	return _return_button.text


func controls_tooltip() -> String:
	return _details_toggle.tooltip_text


func set_return_text(text: String) -> void:
	_return_button.text = text


func set_return_visible(value: bool) -> void:
	_return_button.visible = value


## 场景可把自己的按钮（重置 / 视角等）挂进自动换行按钮区，共用主题变体与命中区下限。
func add_button(button: Button) -> Button:
	if String(button.theme_type_variation).is_empty():
		button.theme_type_variation = BUTTON_VARIATION
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, MIN_HIT_HEIGHT)
	# 关键：按钮在 flow 行里默认会被拉满到行高（标题块 ~110px）。
	# 明确 SHRINK_BEGIN，让按钮保持自身命中高度（约 34-38px）。
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.focus_mode = Control.FOCUS_ALL
	_header_flow.add_child(button)
	return button


func button_row() -> HFlowContainer:
	return _header_flow


## 实际被 HUD 遮挡的矩形高度并集面积（除详情外）：供遮挡率验收使用，不把透明容器整行算入。
func occlusion_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if _title_panel != null and _title_panel.visible:
		rects.append(_title_panel.get_global_rect())
	# 只遍历 flow 的按钮子节点一次，避免与具名按钮重复计数。
	for child in _header_flow.get_children():
		if child is Button and (child as Button).visible:
			rects.append((child as Button).get_global_rect())
	return rects


# --- 构建 -------------------------------------------------------------------


func _build() -> void:
	if _layer != null:
		return
	name = "LabHud"
	_layer = CanvasLayer.new()
	_layer.name = "HudLayer"
	add_child(_layer)

	_interface = Control.new()
	_interface.name = "Interface"
	_interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interface.theme = LAB_THEME
	_layer.add_child(_interface)
	_interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	_interface.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	# 单行头部流：标题块 + 按钮；宽窗一行，窄窗自动换行（不靠多行硬拆）。
	_header_flow = HFlowContainer.new()
	_header_flow.name = "HeaderFlow"
	_header_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_flow.add_theme_constant_override("h_separation", 10)
	_header_flow.add_theme_constant_override("v_separation", 6)
	layout.add_child(_header_flow)

	_title_panel = PanelContainer.new()
	_title_panel.name = "TitlePanel"
	_title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_panel.theme_type_variation = PANEL_VARIATION
	_title_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_header_flow.add_child(_title_panel)

	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_theme_constant_override("separation", 2)
	_title_panel.add_child(titles)

	# 标题与类目同一行：类目是 13px 小字，整块保持 2-3 行高。
	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", 8)
	titles.add_child(title_row)

	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = TITLE_VARIATION
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_title)

	_kicker = Label.new()
	_kicker.name = "Kicker"
	_kicker.theme_type_variation = HINT_VARIATION
	_kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(_kicker)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = READOUT_VARIATION
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	titles.add_child(_status)

	_core = Label.new()
	_core.name = "CoreSummary"
	_core.theme_type_variation = READOUT_VARIATION
	_core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_core.visible = false
	titles.add_child(_core)

	# 短提示并入标题块作第三行：不再单占一块底衬，遮挡面积更小。
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = HINT_VARIATION
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(_hint)

	_details_toggle = Button.new()
	_details_toggle.name = "DetailsToggle"
	_details_toggle.text = "详情 (H) ▸"
	_details_toggle.theme_type_variation = BUTTON_VARIATION
	_details_toggle.focus_mode = Control.FOCUS_ALL
	_details_toggle.custom_minimum_size = Vector2(84, MIN_HIT_HEIGHT)
	_details_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_details_toggle.tooltip_text = "H / F1 展开本场问题与调试读数"
	_details_toggle.pressed.connect(toggle_details)
	_header_flow.add_child(_details_toggle)

	_return_button = Button.new()
	_return_button.name = "ReturnButton"
	_return_button.text = "返回"
	_return_button.theme_type_variation = BUTTON_VARIATION
	_return_button.focus_mode = Control.FOCUS_ALL
	_return_button.custom_minimum_size = Vector2(64, MIN_HIT_HEIGHT)
	_return_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_return_button.pressed.connect(func() -> void: return_pressed.emit())
	_header_flow.add_child(_return_button)

	# 详情面板：下方独立限宽行，展开只向下长。
	_details_panel = PanelContainer.new()
	_details_panel.name = "DetailsPanel"
	_details_panel.theme_type_variation = PANEL_VARIATION
	_details_panel.visible = false
	_details_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_details_panel.custom_minimum_size = Vector2(DETAILS_WIDTH, 0)
	layout.add_child(_details_panel)

	var details_box := VBoxContainer.new()
	details_box.name = "Details"
	details_box.add_theme_constant_override("separation", 4)
	_details_panel.add_child(details_box)

	_question = Label.new()
	_question.name = "Question"
	_question.theme_type_variation = HINT_VARIATION
	# 中文没有词间空格：任意位置换行，避免把整句当长词撑宽面板。
	_question.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_question.custom_minimum_size = Vector2(DETAILS_WIDTH, 0)
	details_box.add_child(_question)

	# 单层滚动：RichTextLabel 自身滚动并带明确最小尺寸，不再套 ScrollContainer。
	_debug_view = RichTextLabel.new()
	_debug_view.name = "DebugReadout"
	_debug_view.bbcode_enabled = false
	_debug_view.fit_content = false
	_debug_view.scroll_active = true
	_debug_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_view.theme_type_variation = HINT_VARIATION
	# RichTextLabel 不继承 Label 的字体色（既有场景同一坑）：显式给墨色与正文字号。
	_debug_view.add_theme_color_override("default_color", Color(0.145098, 0.239216, 0.211765, 1.0))
	_debug_view.add_theme_font_size_override("normal_font_size", 13)
	_debug_view.add_theme_font_size_override("bold_font_size", 13)
	_debug_view.custom_minimum_size = Vector2(DETAILS_WIDTH, DETAILS_MIN_HEIGHT)
	_debug_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_box.add_child(_debug_view)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)


## 详情可见性 = 已展开 且有内容（问题或调试读数任一条即可读）。
func _refresh_details_visibility() -> void:
	var has_content := not _question_text.strip_edges().is_empty() or not _debug_lines.is_empty()
	_details_panel.visible = _details_visible and has_content
