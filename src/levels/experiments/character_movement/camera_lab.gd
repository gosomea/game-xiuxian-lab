extends Node3D

## 镜头实验室（character_movement 子实验）。
##
## 唯一目标：在同一灰盒里比较两个可操作镜头模式与 fixed_follow 的参数预设，
## 并观察旋转 / 缩放 / 捕获对屏幕相对移动的影响。不修改角色与三项 Capability。
##
## 边界：
## - 镜头行为归 res://game/systems/camera_rig/ 的 CameraRig（唯一 executor）与模式 Capability，
##   本场景只做编排：装配 rig、HUD 与重置；地面基由 rig 桥接直接写给角色。
## - 本场景不写 Camera3D 的姿态（只读 rig 快照），不引用任何模式 Capability 类名。
## - 灰盒几何在 CameraLabGraybox（同目录）；Esc 返回角色移动子实验目录。
## - 旧的 camera_lab_rig.gd 作为已验收探索资产保留，本场景不再运行引用它。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const RIG_SHEET: PackedScene = preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")
const GRAYBOX_SCRIPT: GDScript = preload("res://levels/experiments/character_movement/camera_lab_graybox.gd")

const SPAWN_POSITION := Vector3(0.0, 0.1, -10.0)
const SPAWN_AIM := Vector3.FORWARD

## 四个可操作模式（长期语义名；数字键 1..4 按此顺序，与 rig.mode_cycle 一致）。
const MODE_ORDER: Array[String] = ["fixed_follow", "quarter_turn", "orbit", "overview"]
## 本实验的默认模式：组合环绕/自由跟随。reset_state 会回到 mode_cycle[0]，因此 R 重置后显式请求它。
const DEFAULT_MODE := "orbit"
const MODE_LABELS: Dictionary = {
	"fixed_follow": "1 固定跟随",
	"quarter_turn": "2 四向切换",
	"orbit": "3 组合环绕/自由跟随",
	"overview": "4 总览平移",
}
## 提示文案用的短名（按钮用长标签，短提示按模式顺序拼接，避免手写文案与模式列表漂移）。
const MODE_SHORT: Dictionary = {
	"fixed_follow": "固定跟随",
	"quarter_turn": "四向",
	"orbit": "组合环绕",
	"overview": "总览",
}
## 组合环绕（orbit）的常显提示：四组输入必须完整写出，玩家无需查文档即可发现。
const ORBIT_HINT := "WASD 移动 · Q/E 连续旋转 · 滚轮缩放 · 按住右键拖动 · 1-4 换模式 · H 详情"

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _player: Swordsman
var _motion: SwordsmanMotionComponent
var _rig: CameraRig
var _input := MovementLabInput.new()
var _hud: LabHud
var _mode_buttons: Dictionary = {}
var _status_line := ""


func _ready() -> void:
	# 与其他实验场景一致：进入开 4x MSAA，离开恢复，不把状态泄漏给目录。
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "camera_lab: 场景必须提供 Camera3D")
	_build_graybox()
	_spawn_player()
	_build_rig()
	_build_hud()
	_update_status()


func _exit_tree() -> void:
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	# 失焦只清输入与捕获；不改变镜头模式、不改变角色能力状态。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_input.clear()
		if _player != null:
			_player.clear_input()
		if _rig != null:
			_rig.release_capture()


func _unhandled_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		# 移动键只是"按住状态"；模式 / 缩放 / 偏航 / 捕获由 CameraRig 自己处理。
		# 注意：子节点 CameraRig 的 _unhandled_input 先于本根脚本收到同一事件，
		# 所以这里看到的事件都是 rig 未消费的。
		if _input.track_key(key_event, []):
			viewport.set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and MovementLabInput.key_code(key_event) == KEY_R:
			viewport.set_input_as_handled()
			_reset_experiment()
		elif event.is_action_pressed("ui_cancel"):
			# Esc 到达这里说明 rig 未处于捕获态（捕获态由 rig 在 _input 先消费）。
			viewport.set_input_as_handled()
			_return_to_hub()


func _physics_process(delta: float) -> void:
	if _player == null or _motion == null or _rig == null:
		return
	# 相机地面基由 CameraRig 在写相机后直接发布给角色（桥接层），本场景不重复转交。
	# 次序由 process_physics_priority 保证：CameraRig(-10) 先写相机并发布地面基，
	# 本节点(0) 取输入，角色(0, 子节点) 最后物理提交——三者同帧一致。
	var move := _input.move_input()
	_player.set_move_input(move)
	if move != Vector2.ZERO:
		var direction := _rig.right_axis() * move.x - _rig.forward_axis() * move.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			_player.set_aim_direction(direction.normalized())


func _process(_delta: float) -> void:
	_update_status()


func _reset_experiment() -> void:
	_input.clear()
	_player.global_position = SPAWN_POSITION
	_player.reset_motion()
	_player.set_aim_direction(SPAWN_AIM)
	_rig.reset_state()
	# reset_state 按 mode_cycle[0] 复位（fixed_follow）；R 重置后回到本实验默认的组合环绕。
	_rig.request_mode(DEFAULT_MODE)


func _return_to_hub() -> void:
	_input.clear()
	if _player != null:
		_player.clear_input()
	if _rig != null:
		_rig.release_capture()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	if result != OK:
		push_error("camera_lab: 返回角色移动子实验目录失败，错误码 %d" % result)


# --- 装配 ---------------------------------------------------------------


func _build_graybox() -> void:
	GRAYBOX_SCRIPT.build(self)


func _spawn_player() -> void:
	var actor := SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(actor != null, "camera_lab: swordsman.tscn 根节点必须是 Swordsman")
	actor.name = "Swordsman"
	actor.position = SPAWN_POSITION
	add_child(actor)
	_player = actor
	_motion = actor.motion()
	assert(_motion != null, "camera_lab: 角色缺少 SwordsmanMotionComponent")
	assert(actor.capability_manager() != null, "camera_lab: 角色缺少唯一 CapabilityManager")


func _build_rig() -> void:
	var rig := RIG_SHEET.instantiate() as CameraRig
	assert(rig != null, "camera_lab: camera_rig_sheet.tscn 根节点必须是 CameraRig")
	rig.name = "CameraRig"
	add_child(rig)
	_rig = rig
	_rig.bind(_camera, _player, _lab_config())


## 本实验的投影与参数配置：代码构造，避免为单一场景新增资源文件。
func _lab_config() -> CameraRigConfig:
	var config := CameraRigConfig.new()
	# 默认进入组合环绕（WASD + Q/E 连续旋转 + 滚轮缩放 + 按住右键拖动），
	# 其余三模式仍可经 1-4 / 按钮切回（见 MODE_ORDER）。
	config.start_mode = DEFAULT_MODE
	config.follow_preset = "hard"
	config.yaw_degrees = -35.0
	config.pitch_degrees = 42.0
	config.distance = 16.0
	config.size = 22.0
	config.size_min = 8.0
	config.size_max = 44.0
	config.near = 0.1
	config.far = 220.0
	# 只有本实验场景显式打开模式选择键与预设键；其它场景保持默认（不抢按键）。
	config.mode_choices = PackedStringArray(MODE_ORDER)
	config.enable_mode_selection_keys = true
	config.enable_preset_key = true
	config.enable_zoom_keys = true
	config.turn_step_degrees = 90.0
	# 未归属 RMB：非 orbit 模式下消费世界区域右键但不捕获，避免右键泄漏到宿主视图。
	config.consume_unowned_rmb = true
	return config


# --- HUD ----------------------------------------------------------------


func _build_hud() -> void:
	_hud = LabHud.new()
	add_child(_hud)
	# 短 kicker + 按当前模式的一句话核心操作；完整按键表进详情 tooltip（H 展开）。
	_hud.configure("镜头实验室", "角色移动 · 镜头实验室", _mode_hint())
	_hud.set_controls("WASD 移动 · 1-%d 切换模式（%s）· Q/E 连续旋转（3 组合环绕）或 90° 步进（2 四向）· RMB（3）按住拖动 yaw/pitch · MMB（4）平移 · Home（4）回中 · 滚轮 / Z / X 缩放 · Tab 切预设 · R 重置 · Esc 返回" % [
		MODE_ORDER.size(), _mode_short_list()
	])
	_hud.set_question("四个镜头模式与 fixed_follow 的四种预设，怎样影响构图、旋转换向与屏幕相对移动？")
	_hud.return_pressed.connect(_return_to_hub)
	_hud.set_return_text("返回子实验目录")
	for mode in MODE_ORDER:
		var button := Button.new()
		button.name = "%sButton" % mode.to_pascal_case()
		button.text = str(MODE_LABELS[mode])
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_mode_button.bind(mode))
		_hud.add_button(button)
		_mode_buttons[mode] = button
	var preset_button := Button.new()
	preset_button.name = "PresetButton"
	preset_button.text = "预设"
	preset_button.focus_mode = Control.FOCUS_NONE
	preset_button.pressed.connect(_on_preset_button)
	_hud.add_button(preset_button)
	# overview 回中的可视入口（与 Home 键等价）。
	var recenter_button := Button.new()
	recenter_button.name = "RecenterButton"
	recenter_button.text = "回中 (Home)"
	recenter_button.focus_mode = Control.FOCUS_NONE
	recenter_button.pressed.connect(_on_recenter_button)
	_hud.add_button(recenter_button)
	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_experiment)
	_hud.add_button(reset_button)


## 当前模式的一句话核心操作（其余按键在 set_controls 的详情提示里）。
func _mode_hint() -> String:
	match _rig.mode_id() if _rig != null else "orbit":
		"quarter_turn":
			return "Q / E 每次转 90° · 1-4 换模式 · 滚轮缩放 · H 详情"
		"orbit":
			return ORBIT_HINT
		"overview":
			return "中键拖动平移 · Home 回中 · 滚轮缩放 · H 详情"
		_:
			return "WASD 移动 · 1-4 换模式 · 滚轮缩放 · H 详情"


## 模式短名的拼接文本（与 MODE_ORDER 同源，增删模式时提示自动跟上）。
func _mode_short_list() -> String:
	var names := PackedStringArray()
	for mode in MODE_ORDER:
		names.append(str(MODE_SHORT.get(mode, mode)))
	return " / ".join(names)


func _on_mode_button(mode: String) -> void:
	_rig.request_mode(mode)
	_update_status()


## overview 回中：请求交给 rig，由 overview 模式按时间常数收敛。
func _on_recenter_button() -> void:
	if _rig != null:
		_rig.request_recenter()
	_update_status()


func _on_preset_button() -> void:
	if _rig.mode_id() == "fixed_follow":
		_rig.cycle_preset()
	_update_status()


func _update_status() -> void:
	if _hud == null or _rig == null or _player == null:
		return
	var snapshot := _rig.snapshot()
	var focus: Vector3 = snapshot["focus"]
	var lookahead: Vector3 = snapshot["lookahead"]
	var focus_offset := Vector2(focus.x - _player.global_position.x, focus.z - _player.global_position.z).length()
	var mode_name := str(MODE_SHORT.get(str(snapshot["mode"]), str(snapshot["mode"])))
	# 常显只放模式中文名 + 比较所需核心数字（焦点偏移 / 前视 / 倍率），其余进详情。
	_status_line = "%s%s · 偏航 %d° · 缩放 %.1f · 焦点偏移 %.2f m · 前视 %.2f m" % [
		mode_name,
		"（%s）" % str(snapshot["preset"]) if snapshot["mode"] == "fixed_follow" else "",
		int(round(float(snapshot["yaw_degrees"]))),
		float(snapshot["zoom_size"]),
		focus_offset,
		Vector2(lookahead.x, lookahead.z).length(),
	]
	_hud.set_status(_status_line)
	_hud.set_debug_lines(PackedStringArray([
		"物理次序：CameraRig(-10) 先写相机 → 本节点(0) 取地面基 → 角色(0) 物理提交",
		"相机位置 (%.2f, %.2f, %.2f)" % [
			_camera.global_position.x, _camera.global_position.y, _camera.global_position.z],
		"角色位置 (%.2f, %.2f, %.2f)" % [
			_player.global_position.x, _player.global_position.y, _player.global_position.z],
		"捕获 %s · 遮挡 %s · 平移 %.2f m" % [
			"是" if bool(snapshot["capture_active"]) else "否",
			"是" if bool(snapshot["occlusion"]) else "否",
			Vector2((snapshot["pan_offset"] as Vector3).x, (snapshot["pan_offset"] as Vector3).z).length(),
		],
		"预设循环：hard / smooth / deadzone / lookahead（含前视）",
	]))
	# 提示随模式更新：常显文案只保留当前模式的核心操作。
	_hud.configure("镜头实验室", "角色移动 · 镜头实验室", _mode_hint())
	for mode in _mode_buttons:
		(_mode_buttons[mode] as Button).button_pressed = str(snapshot["mode"]) == str(mode)


# --- 只读访问（测试与外部观察用；不暴露写入口） --------------------------


func rig() -> CameraRig:
	return _rig


func actor() -> Swordsman:
	return _player


func camera() -> Camera3D:
	return _camera


## 相机 → 角色视线是否被灰盒几何挡住（只读观察项，由 rig 写入）。
func is_occluded() -> bool:
	return _rig.is_occluded() if _rig != null else false


## 只读：该键是否被本场景的任一输入消费者登记（移动 helper 或 rig 的按住跟踪）。
## 用于验证"不吞与本场景无关的键"。
func input_held(code: Key) -> bool:
	if _input.is_down(code):
		return true
	return _rig != null and _rig.is_key_held(code)