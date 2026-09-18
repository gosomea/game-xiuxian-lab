class_name MotionPreviewPanel
extends PanelContainer

## 动作工作台的紧凑播放控件面板（S2 P0）。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md「动作工作台与动作库」。
## 与共享 LabHud 的分工：LabHud 负责标题/状态/返回与通用按钮行；本面板只承载
## **动作选择与播放专用控件**，不塞进 LabHud 的按钮行，窄窗自动换行。
##
## 面板不读游戏状态、不认识 Capability / Component：它只把用户意图转成 signal，
## 由工作台场景决定怎么落到预览 display 与真实 actor 上。
## 空间键（空格）语义由工作台统一裁决：面板控件获得焦点时空格必须只作用于控件本身，
## 不得同时触发角色跳跃（工作台在输入路由里放行/拦截，见 motion_stage.gd）。

signal action_selected(action_id: StringName)
signal play_toggled()
signal step_requested()
signal loop_toggled(enabled: bool)
signal rate_selected(rate: float)
signal ab_requested()

const LAB_THEME: Theme = preload("res://ui/lab_theme.tres")
## 倍率档位（P0 需求：.25 / .5 / 1 倍）。
const RATES: Array[float] = [0.25, 0.5, 1.0]
const MIN_HIT_HEIGHT := 34.0

var _action_row: HBoxContainer
var _action_buttons: Dictionary = {}
var _play_button: Button
var _step_button: Button
var _loop_button: Button
var _ab_button: Button
var _rate_row: HBoxContainer
var _rate_buttons: Dictionary = {}
var _progress: ProgressBar
var _source: Label
var _transition: ProgressBar


func _ready() -> void:
	theme = LAB_THEME
	theme_type_variation = "HudPanel"
	name = "PreviewPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_source = Label.new()
	_source.name = "Source"
	_source.theme_type_variation = "HudHint"
	_source.text = "程序动作预览（无骨骼 clip）"
	_source.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	box.add_child(_source)

	_action_row = HBoxContainer.new()
	_action_row.name = "ActionRow"
	_action_row.add_theme_constant_override("separation", 4)
	box.add_child(_action_row)

	var playback := HBoxContainer.new()
	playback.name = "PlaybackRow"
	playback.add_theme_constant_override("separation", 4)
	box.add_child(playback)

	_play_button = _make_button("播放", 64)
	_play_button.name = "PlayButton"
	_play_button.pressed.connect(func() -> void: play_toggled.emit())
	playback.add_child(_play_button)

	_step_button = _make_button("单步", 56)
	_step_button.name = "StepButton"
	_step_button.pressed.connect(func() -> void: step_requested.emit())
	playback.add_child(_step_button)

	_loop_button = _make_button("循环", 56)
	_loop_button.name = "LoopButton"
	_loop_button.toggle_mode = true
	_loop_button.button_pressed = true
	_loop_button.toggled.connect(func(enabled: bool) -> void: loop_toggled.emit(enabled))
	playback.add_child(_loop_button)

	_ab_button = _make_button("A-B 过渡", 84)
	_ab_button.name = "AbButton"
	_ab_button.tooltip_text = "在当前动作与上一动作之间再做一次 A→B 过渡"
	_ab_button.pressed.connect(func() -> void: ab_requested.emit())
	playback.add_child(_ab_button)

	_rate_row = HBoxContainer.new()
	_rate_row.name = "RateRow"
	_rate_row.add_theme_constant_override("separation", 4)
	box.add_child(_rate_row)
	for value in RATES:
		var rate_label := str(value) + "x"
		var rate_button := _make_button(rate_label, 52)
		rate_button.name = "Rate" + rate_label
		rate_button.toggle_mode = true
		rate_button.button_pressed = is_equal_approx(value, 1.0)
		rate_button.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_rate_selected(value))
		_rate_row.add_child(rate_button)
		_rate_buttons[value] = rate_button

	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(220, 10)
	box.add_child(_progress)

	_transition = ProgressBar.new()
	_transition.name = "Transition"
	_transition.min_value = 0.0
	_transition.max_value = 1.0
	_transition.show_percentage = false
	_transition.custom_minimum_size = Vector2(220, 6)
	box.add_child(_transition)


func _rate_selected(value: float) -> void:
	for key in _rate_buttons:
		var button := _rate_buttons[key] as Button
		button.button_pressed = is_equal_approx(key, value)
	rate_selected.emit(value)


## 动作按钮：由工作台按动作注册表构建，不在面板里硬编码动作列表。
## 父级由工作台提供（HBoxContainer），窄窗换行交给外层容器。
func add_action_button(label: String, action_id: StringName) -> Button:
	var button := _make_button(label, 72)
	button.name = "Action_%s" % action_id
	button.toggle_mode = true
	button.pressed.connect(func() -> void: action_selected.emit(action_id))
	_action_row.add_child(button)
	_action_buttons[action_id] = button
	return button


func action_button(action_id: StringName) -> Button:
	return _action_buttons.get(action_id) as Button


## 只读刷新：全部数值都由工作台写入，面板不反向读场景。
func refresh(snapshot: Dictionary) -> void:
	var playing: bool = snapshot.get("playing", false)
	_play_button.text = "暂停" if playing else "播放"
	_play_button.button_pressed = playing
	var title := str(snapshot.get("action_title", ""))
	var source := str(snapshot.get("source", "program"))
	# 文案如实：当前全部动作都是程序近似，绝不显示成骨骼 clip。
	var source_text := "程序动作预览（无骨骼 clip）" if source == "program" else "骨骼 clip（尚未接入）"
	# 面板常显一行用户可读摘要；带参数名的技术说明（jump_speed / gravity / lift_speed 等）进 tooltip。
	_source.text = "%s · %s · %s" % [title, source_text, str(snapshot.get("summary", ""))]
	_source.tooltip_text = str(snapshot.get("note", ""))
	_progress.value = float(snapshot.get("progress", 0.0))
	_transition.value = float(snapshot.get("transition", 1.0))
	_transition.visible = bool(snapshot.get("transitioning", false))
	_loop_button.button_pressed = bool(snapshot.get("looping", true))
	for key in _rate_buttons:
		(_rate_buttons[key] as Button).button_pressed = is_equal_approx(float(key), float(snapshot.get("rate", 1.0)))
	var current_id: StringName = snapshot.get("action_id", "")
	for key in _action_buttons:
		(_action_buttons[key] as Button).button_pressed = key == current_id


func _make_button(label: String, min_width: float) -> Button:
	var button := Button.new()
	button.text = label
	button.theme_type_variation = "HudButton"
	button.custom_minimum_size = Vector2(min_width, MIN_HIT_HEIGHT)
	# 面板控件必须能获得键盘焦点：空格/回车作用于按钮时，工作台不再把该事件当作角色跳跃。
	button.focus_mode = Control.FOCUS_ALL
	return button
