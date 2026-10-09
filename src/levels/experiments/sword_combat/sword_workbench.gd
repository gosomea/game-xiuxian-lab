extends Node3D

## 剑法工作台：共享修士在六招之间切换，对五根木桩与高台比较施法、剑运动和接地。
##
## 依据 notes/implemented/gameplay/2026-10-10-sword-spell-exploration.md。职责边界：
## - 场景只做编排：鼠标地面投影、左键边沿、招式切换、面向转交、命中顿帧、HUD 与返回。
## - 出招行为在独立能力包里，经 SwordCastBundle 装到共享 Swordsman；本场景不写能力内部状态、
##   不 tick 管理器、不提交物理。移动、跳跃、御剑与镜头沿用共享实现。
## - 移动键由角色移动实验的 MovementLabInput 统一解码（本模块依赖 character_movement）。

const HUB_SCENE := "res://levels/lab_hub.tscn"
const SWORDSMAN_SCENE: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
const DUMMY_SCENE: PackedScene = preload("res://game/actors/training_dummy/training_dummy.tscn")
const RIG_SHEET: PackedScene = preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")
const SWORD_QI_SCRIPT := preload("res://game/abilities/sword_qi/sword_qi.gd")
const STRIKE_SCRIPT := preload("res://game/abilities/flying_sword_strike/flying_sword_strike.gd")
const ARRAY_SCRIPT := preload("res://game/abilities/sword_array/sword_array.gd")
const WHEEL_SCRIPT := preload("res://game/abilities/heavenly_sword_wheel/heavenly_sword_wheel.gd")
const GIANT_SCRIPT := preload("res://game/abilities/giant_sword_descent/giant_sword_descent.gd")
const RAIN_SCRIPT := preload("res://game/abilities/heavenly_sword_rain/heavenly_sword_rain.gd")
const WHEEL_DATA := preload("res://game/abilities/heavenly_sword_wheel/heavenly_sword_wheel_component.gd")
const GIANT_DATA := preload("res://game/abilities/giant_sword_descent/giant_sword_descent_component.gd")
const RAIN_DATA := preload("res://game/abilities/heavenly_sword_rain/heavenly_sword_rain_component.gd")
const InputHelper := preload("res://levels/experiments/character_movement/movement_lab_input.gd")

const ARENA_HALF := 16.0
const WALL_HEIGHT := 2.0
const PLAYER_START := Vector3(0.0, 0.02, 4.0)
const DUMMY_POSITIONS: Array[Vector3] = [
	Vector3(0.0, 0.0, -4.0),
	Vector3(-3.5, 0.0, -7.0),
	Vector3(3.5, 0.0, -7.0),
	Vector3(-7.0, 0.0, -2.5),
	Vector3(0.0, 0.0, -12.0),
]
const FORM_LABELS := {
	SwordCastComponent.FORM_QI: "剑气",
	SwordCastComponent.FORM_STRIKE: "飞剑",
	SwordCastComponent.FORM_ARRAY: "扇面剑阵",
	SwordCastComponent.FORM_WHEEL: "天轮剑阵",
	SwordCastComponent.FORM_GIANT: "巨剑镇落",
	SwordCastComponent.FORM_RAIN: "天降剑雨",
}
const FORM_COLORS := {
	SwordCastComponent.FORM_QI: Color(0.45, 0.95, 0.85),
	SwordCastComponent.FORM_STRIKE: Color(0.95, 0.85, 0.45),
	SwordCastComponent.FORM_ARRAY: Color(0.6, 0.8, 1.0),
	SwordCastComponent.FORM_WHEEL: Color(0.36, 0.95, 0.9),
	SwordCastComponent.FORM_GIANT: Color(1.0, 0.81, 0.36),
	SwordCastComponent.FORM_RAIN: Color(0.34, 0.74, 1.0),
}
const KEY_CYCLE_FORM := KEY_C

const CAMERA_YAW_DEGREES := 35.0
const CAMERA_PITCH_DEGREES := 42.0
const CAMERA_DISTANCE := 26.0
const CAMERA_SIZE := 16.0
const GROUND_MASK := 2
## 顿帧：时间缩放、持续（真实秒）与两次顿帧的最短间隔（真实秒）。
const HITSTOP_SCALE := 0.05
const HITSTOP_TIME := 0.06
const HITSTOP_COOLDOWN := 0.22

var _camera: Camera3D
var _viewport: Viewport
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _actor: Swordsman
var _cast: SwordCastComponent
var _bundle := SwordCastBundle.new()
var _rig: CameraRig
var _movement_input: MovementLabInput = InputHelper.new()
var _hud: LabHud
var _reticle: MeshInstance3D
var _reticle_material: StandardMaterial3D
var _dummies: Array[TrainingDummy] = []
var _form_buttons: Dictionary = {}
## 最近一次鼠标移动事件的视口坐标；镜头跟随时每帧仍按它重新投影到地面。
var _mouse_position := Vector2(-1.0, -1.0)
var _press_pending := false
var _release_pending := false
var _release_form_pending := ""
var _held := false
## 木桩序号 → 上次看到的命中数。
var _seen_hits: Dictionary = {}
var _last_hitstop_ms := -100000
var _hitstop_active := false
var _seen_feedback_serial := 0
var _feedback_age := 1.0
var _feedback_power := 0.0
var _auto_frame := true
var _auto_frame_button: Button
var _spell_views: Array[Node3D] = []
var _impact_audio: AudioStreamPlayer3D
var _light_audio: AudioStreamPlayer3D
var _last_light_audio := -1.0
var _stage_hint: Label
var _last_shake := Vector3.ZERO


func _ready() -> void:
	_viewport = get_viewport()
	_previous_msaa = _viewport.msaa_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	assert(ResourceLoader.exists(HUB_SCENE), "sword_workbench: 缺少返回目录 %s" % HUB_SCENE)
	_camera = %Camera3D as Camera3D
	assert(_camera != null, "sword_workbench: 场景必须提供 Camera3D")
	_build_ground()
	_build_dummies()
	_spawn_actor()
	_build_views()
	_build_rig()
	_build_hud()
	_build_audio()
	_select_form(SwordCastComponent.FORM_QI)


func _exit_tree() -> void:
	if _cast != null:
		_cast.request_cancel()
	_end_hitstop()
	if is_instance_valid(_viewport):
		_viewport.msaa_3d = _previous_msaa


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_input()
		if _rig != null:
			_rig.release_capture()


func _input(event: InputEvent) -> void:
	# 指向点不受 HUD 遮挡影响：在 GUI 之前记录位置，但不消费事件。
	if event is InputEventMouseMotion:
		_mouse_position = (event as InputEventMouseMotion).position
	# 在 CameraRig 消费滚轮之前，把缩放归还手动控制。
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and button.pressed:
			_auto_frame = false
			if _auto_frame_button != null:
				_auto_frame_button.button_pressed = false


func _unhandled_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed and not _held:
				_press_pending = true
				_held = true
			elif not button.pressed and _held:
				_release_pending = true
				_release_form_pending = _cast.form
				_held = false
			viewport.set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if _movement_input.track_key(key_event):
		viewport.set_input_as_handled()
		return
	if not InputHelper.is_key_down_edge(key_event):
		return
	match InputHelper.key_code(key_event):
		KEY_CYCLE_FORM:
			viewport.set_input_as_handled()
			cycle_form()
		KEY_R:
			viewport.set_input_as_handled()
			reset_experiment()
		_:
			if event.is_action_pressed("ui_cancel"):
				viewport.set_input_as_handled()
				_return_to_hub()


func _physics_process(_delta: float) -> void:
	if _actor == null:
		return
	_actor.apply_motion_input(_movement_input.consume_motion_input())
	var aim: Variant = _mouse_ground_point()
	if aim != null:
		_cast.aim_point = aim
	var surface := _mouse_surface_hit()
	_cast.aim_surface_valid = not surface.is_empty()
	if _cast.aim_surface_valid:
		_cast.aim_surface_point = surface["position"]
		_cast.aim_surface_normal = surface["normal"]
	_cast.cast_pressed = _press_pending
	_cast.cast_released = _release_pending
	_cast.cast_released_form = _release_form_pending
	_cast.cast_held = _held
	_press_pending = false
	_release_pending = false
	_release_form_pending = ""
	if _cast.facing_requested(_actor.capability_manager().elapsed):
		_actor.set_aim_direction(_cast.face_direction)


func _process(delta: float) -> void:
	if _cast == null:
		return
	_reticle.visible = _cast.aim_surface_valid if _cast.form in [SwordCastComponent.FORM_WHEEL, SwordCastComponent.FORM_GIANT, SwordCastComponent.FORM_RAIN] else true
	_reticle.global_position = _cast.aim_surface_point + _cast.aim_surface_normal * 0.035 if _cast.aim_surface_valid else Vector3(_cast.aim_point.x, 0.03, _cast.aim_point.z)
	_feedback_age += delta
	if _cast.feedback_serial != _seen_feedback_serial:
		_seen_feedback_serial = _cast.feedback_serial
		if _cast.feedback_strength >= 0.75:
			_feedback_age = 0.0
			_feedback_power = _cast.feedback_strength
			_request_hitstop()
			_impact_audio.global_position = _cast.feedback_point
			_impact_audio.play()
		elif _actor.capability_manager().elapsed - _last_light_audio >= 0.13:
			_last_light_audio = _actor.capability_manager().elapsed
			_light_audio.global_position = _cast.feedback_point
			_light_audio.play()
	_update_spell_framing(delta)
	# 剑阵一轮可连中十几下，逐下顿帧会变成持续卡顿；剑阵命中只由木桩闪白与晃动表现。
	var heavy_hit := false
	for index in range(_dummies.size()):
		var target := _dummies[index].target()
		if target.hit_count > int(_seen_hits.get(index, 0)) \
				and target.last_hit_form in [SwordCastComponent.FORM_QI, SwordCastComponent.FORM_STRIKE]:
			heavy_hit = true
		_seen_hits[index] = target.hit_count
	if heavy_hit:
		_request_hitstop()
	_update_status()


## 场景 API：选择招式（HUD 按钮、C 键与验收脚本共用）。
func select_form(form: String) -> void:
	_select_form(form)


func cycle_form() -> void:
	var index := SwordCastComponent.FORMS.find(_cast.form)
	_select_form(SwordCastComponent.FORMS[(index + 1) % SwordCastComponent.FORMS.size()])


## 场景 API：R 重置：人物回出生点、清输入与木桩记录。
func reset_experiment() -> void:
	_clear_input()
	_end_hitstop()
	_seen_feedback_serial = _cast.feedback_serial
	_feedback_age = 1.0
	_last_shake = Vector3.ZERO
	_actor.global_position = PLAYER_START
	_actor.reset_motion()
	_actor.set_aim_direction(Vector3.FORWARD)
	for dummy in _dummies:
		dummy.target().reset_hits()
	_seen_hits.clear()
	_rig.reset_state()
	_rig.request_mode("orbit")


## 只读：全部木桩命中数之和。
func total_hits() -> int:
	var total := 0
	for dummy in _dummies:
		total += dummy.target().hit_count
	return total


func actor() -> Swordsman:
	return _actor


func cast_component() -> SwordCastComponent:
	return _cast


func dummies() -> Array[TrainingDummy]:
	return _dummies


func rig() -> CameraRig:
	return _rig


func _select_form(form: String) -> void:
	if not FORM_LABELS.has(form):
		return
	if _cast.form != form:
		# 同一物理帧先松手再切招时，保留已产生的释放边沿。
		var released_before_switch := _release_pending
		_held = false
		_press_pending = false
		_cast.clear_input()
		_release_pending = released_before_switch
		_cast.pose_weight = 0.0
	_cast.form = form
	for key in _form_buttons:
		(_form_buttons[key] as Button).button_pressed = key == form
	_reticle_material.albedo_color = Color(FORM_COLORS[form], 0.75)


func _clear_input() -> void:
	_movement_input.clear()
	_press_pending = false
	_release_pending = false
	_release_form_pending = ""
	_held = false
	if _cast != null:
		_cast.request_cancel()
		_cast.pose_weight = 0.0
	if _actor != null:
		_actor.clear_input()


func _return_to_hub() -> void:
	_clear_input()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	if result != OK:
		push_error("sword_workbench: 返回实验目录失败，错误码 %d" % result)


func _mouse_ground_point() -> Variant:
	if _camera == null or _mouse_position.x < 0.0:
		return null
	var origin := _camera.project_ray_origin(_mouse_position)
	var normal := _camera.project_ray_normal(_mouse_position)
	return Plane(Vector3.UP, _actor.global_position.y).intersects_ray(origin, normal)


func _request_hitstop() -> void:
	var now := Time.get_ticks_msec()
	if _hitstop_active or now - _last_hitstop_ms < int(HITSTOP_COOLDOWN * 1000.0):
		return
	_last_hitstop_ms = now
	_hitstop_active = true
	TimeKeeper.request(self, HITSTOP_SCALE)
	get_tree().create_timer(HITSTOP_TIME, true, false, true).timeout.connect(_end_hitstop)


func _end_hitstop() -> void:
	if _hitstop_active:
		_hitstop_active = false
		TimeKeeper.release(self)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(ARENA_HALF * 2.0, ARENA_HALF * 2.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.072, 0.078)
	material.roughness = 0.95
	ground.material_override = material
	add_child(ground)
	var rings := MeshInstance3D.new()
	rings.name = "RangeMarks"
	rings.mesh = _range_marks()
	var mark_material := StandardMaterial3D.new()
	mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark_material.albedo_color = Color(0.16, 0.30, 0.31)
	rings.material_override = mark_material
	add_child(rings)
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.collision_layer = 3
	add_child(body)
	_add_box(body, Vector3(0.0, -0.25, 0.0), Vector3(ARENA_HALF * 2.0, 0.5, ARENA_HALF * 2.0))
	_build_stage_details()
	var walls := StaticBody3D.new()
	walls.name = "BoundaryCollision"
	walls.collision_layer = 1
	add_child(walls)
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var center: Vector3 = side * (ARENA_HALF + 0.5) + Vector3.UP * WALL_HEIGHT * 0.5
		var size := Vector3(1.0, WALL_HEIGHT, ARENA_HALF * 2.0 + 2.0)
		if side.x == 0:
			size = Vector3(ARENA_HALF * 2.0 + 2.0, WALL_HEIGHT, 1.0)
		_add_box(walls, center, size)
	_reticle = MeshInstance3D.new()
	_reticle.name = "AimReticle"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.36
	_reticle.mesh = torus
	_reticle.scale = Vector3(1.0, 0.15, 1.0)
	_reticle_material = StandardMaterial3D.new()
	_reticle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_reticle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_reticle.material_override = _reticle_material
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_reticle)


## 以出生点为圆心、每 4 米一圈的射程刻度（细线环）。
func _range_marks() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(1, 5):
		var radius := ring * 4.0
		for index in range(96):
			var a0 := TAU * index / 96.0
			var a1 := TAU * (index + 1) / 96.0
			var p0 := PLAYER_START + Vector3(cos(a0), 0.0, sin(a0)) * radius
			var p1 := PLAYER_START + Vector3(cos(a1), 0.0, sin(a1)) * radius
			var q0 := PLAYER_START + Vector3(cos(a0), 0.0, sin(a0)) * (radius + 0.05)
			var q1 := PLAYER_START + Vector3(cos(a1), 0.0, sin(a1)) * (radius + 0.05)
			for point in [p0, p1, q1, p0, q1, q0]:
				mesh.surface_add_vertex(Vector3(point.x, 0.01, point.z))
	mesh.surface_end()
	return mesh


func _add_box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)


func _build_dummies() -> void:
	for index in range(DUMMY_POSITIONS.size()):
		var dummy := DUMMY_SCENE.instantiate() as TrainingDummy
		dummy.name = "TrainingDummy%d" % (index + 1)
		dummy.position = DUMMY_POSITIONS[index]
		add_child(dummy)
		_dummies.append(dummy)


func _spawn_actor() -> void:
	_actor = SWORDSMAN_SCENE.instantiate() as Swordsman
	assert(_actor != null, "sword_workbench: swordsman.tscn 根节点必须是 Swordsman")
	_actor.name = "Swordsman"
	_actor.position = PLAYER_START
	add_child(_actor)
	var scripts: Array[Script] = [SWORD_QI_SCRIPT, STRIKE_SCRIPT, ARRAY_SCRIPT, WHEEL_SCRIPT, GIANT_SCRIPT, RAIN_SCRIPT]
	var data_scripts: Array[Script] = [WHEEL_DATA, GIANT_DATA, RAIN_DATA]
	var error := _bundle.install(_actor, scripts, data_scripts)
	assert(error == "", "sword_workbench: 剑法装配失败：%s" % error)
	_cast = _bundle.component()


func _build_views() -> void:
	var qi_view := SwordQiView.new()
	qi_view.name = "SwordQiView"
	add_child(qi_view)
	qi_view.bind(_cast)
	var array_view := SwordArrayView.new()
	array_view.name = "SwordArrayView"
	add_child(array_view)
	array_view.bind(_cast)
	var wheel_view := HeavenlySwordWheelView.new()
	add_child(wheel_view)
	wheel_view.bind(spell_component(SwordCastComponent.FORM_WHEEL) as HeavenlySwordWheelComponent)
	_spell_views.append(wheel_view)
	var giant_view := GiantSwordDescentView.new()
	add_child(giant_view)
	giant_view.bind(spell_component(SwordCastComponent.FORM_GIANT) as GiantSwordDescentComponent)
	_spell_views.append(giant_view)
	var rain_view := HeavenlySwordRainView.new()
	add_child(rain_view)
	rain_view.bind(spell_component(SwordCastComponent.FORM_RAIN) as HeavenlySwordRainComponent)
	_spell_views.append(rain_view)


func _build_rig() -> void:
	_rig = RIG_SHEET.instantiate() as CameraRig
	assert(_rig != null, "sword_workbench: camera_rig_sheet.tscn 根节点必须是 CameraRig")
	_rig.name = "CameraRig"
	add_child(_rig)
	var config := CameraRigConfig.new()
	config.start_mode = "orbit"
	config.follow_preset = "smooth"
	config.yaw_degrees = CAMERA_YAW_DEGREES
	config.pitch_degrees = CAMERA_PITCH_DEGREES
	config.distance = CAMERA_DISTANCE
	config.size = CAMERA_SIZE
	config.focus_offset = Vector3(0.0, 1.5, -1.0)
	config.size_min = 8.0
	config.size_max = 34.0
	config.near = 0.1
	config.far = 140.0
	config.focus_clamp_enabled = true
	config.focus_clamp_y_enabled = false
	config.focus_clamp_min = Vector3(-ARENA_HALF + 4.0, 0.0, -ARENA_HALF + 4.0)
	config.focus_clamp_max = Vector3(ARENA_HALF - 4.0, 0.0, ARENA_HALF - 4.0)
	config.mode_choices = PackedStringArray(["orbit", "fixed_follow"])
	config.enable_mode_selection_keys = false
	config.enable_preset_key = false
	config.enable_zoom_keys = false
	config.enable_yaw_keys = true
	config.consume_unowned_rmb = true
	_rig.bind(_camera, _actor, config)


func _build_hud() -> void:
	_hud = LabHud.new()
	add_child(_hud)
	_hud.configure("剑法战斗", "剑法工作台 · 天轮 / 巨剑 / 剑雨", "按住凝聚 · 松开释放 · C 换招 · R 重置")
	_hud.set_controls("天轮 / 巨剑 / 剑雨：按住左键凝聚、松开释放；松开后换招仍完成，蓄势换招取消 · 滚轮退出自动取景 · 左键 出剑（剑阵：按住蓄势、松开齐射）· C 或按钮 切换剑气 / 飞剑 / 剑阵 · 鼠标指向地面决定方向 · WASD / 方向键 移动 · Shift 疾跑 · Space 跳跃 / 上升 · Ctrl 下降 · F 御剑（飞剑在外时不可）· Q/E 旋转 · 滚轮缩放 · 按住右键拖动视角 · R 重置 · Esc 返回实验目录")
	_hud.set_question("天轮的弧线齐射、巨剑的镇落、剑雨的分批降剑，哪一种节奏与剑运动值得继续探索？")
	_hud.set_return_text("返回实验目录")
	_hud.return_pressed.connect(_return_to_hub)
	for form in SwordCastComponent.FORMS:
		var button := Button.new()
		button.name = "Form_%s" % form
		button.text = FORM_LABELS[form]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_form.bind(form))
		_hud.add_button(button)
		_form_buttons[form] = button
	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(reset_experiment)
	_hud.add_button(reset_button)
	_auto_frame_button = Button.new()
	_auto_frame_button.text = "自动取景"
	_auto_frame_button.focus_mode = Control.FOCUS_NONE
	_auto_frame_button.toggle_mode = true
	_auto_frame_button.button_pressed = true
	_auto_frame_button.toggled.connect(func(value: bool) -> void: _auto_frame = value)
	_hud.add_button(_auto_frame_button)


func _update_status() -> void:
	if _hud == null:
		return
	_hud.set_status("%s · %s · 命中 %d" % [FORM_LABELS[_cast.form], _selected_phase(), total_hits()])
	var lines := PackedStringArray()
	for dummy in _dummies:
		var target := dummy.target()
		lines.append("%s 命中 %d（最近：%s）" % [dummy.name, target.hit_count,
			FORM_LABELS.get(target.last_hit_form, "—")])
	lines.append("指向点 (%.1f, %.1f) · 御剑=%s" % [_cast.aim_point.x, _cast.aim_point.z,
		"是" if _actor.motion().flight_active else "否"])
	_hud.set_debug_lines(lines)


## 独立招式数据访问，仅供场景编排与验收；能力之间不互相引用。
func spell_component(form: String) -> Component:
	var names := {
		SwordCastComponent.FORM_WHEEL: "HeavenlySwordWheelComponent",
		SwordCastComponent.FORM_GIANT: "GiantSwordDescentComponent",
		SwordCastComponent.FORM_RAIN: "HeavenlySwordRainComponent",
	}
	return _actor.get_node_or_null(names.get(form, "")) as Component if names.has(form) else null


func _mouse_surface_hit() -> Dictionary:
	if _camera == null or _mouse_position.x < 0.0:
		return {}
	var origin := _camera.project_ray_origin(_mouse_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(_mouse_position) * 250.0, GROUND_MASK, [_actor.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# 可镇落的表面必须朝上；高台和边坡侧面不是地面落点。
	if not hit.is_empty() and (hit["normal"] as Vector3).y >= 0.6:
		return hit
	return {}


func _selected_phase() -> String:
	var data := spell_component(_cast.form)
	if data == null:
		return "左键出剑" if _cast.form != SwordCastComponent.FORM_ARRAY else "按住蓄剑 · 松开齐射"
	var phase: Variant = data.get("phase")
	return {"idle":"待命", "gather":"凝聚", "turn":"转剑", "volley":"齐射", "hover":"悬停", "descent":"镇落", "impact":"震击", "fade":"收势", "rain":"落剑", "dissipate":"散阵"}.get(str(phase), str(phase))


## 场景声明取景意图，CameraRig 保持唯一相机写入者；滚轮可交回手动缩放。
func _update_spell_framing(delta: float) -> void:
	if _rig == null:
		return
	var state := _rig.component()
	state.focus_offset -= _last_shake
	_last_shake = Vector3.ZERO
	var wanted_offset := Vector3(0.0, 1.5, -1.0)
	var wanted_size := CAMERA_SIZE
	if _auto_frame:
		var points: Array[Vector3] = [_actor.global_position, _actor.global_position + Vector3.UP * 2.0]
		for view in _spell_views:
			for child in view.find_children("*", "GeometryInstance3D", true, false):
				var geometry := child as GeometryInstance3D
				if not geometry.is_visible_in_tree():
					continue
				if geometry is MultiMeshInstance3D:
					var multi := geometry as MultiMeshInstance3D
					if multi.multimesh == null:
						continue
					var count := multi.multimesh.visible_instance_count
					if count < 0:
						count = multi.multimesh.instance_count
					var bounds := multi.multimesh.mesh.get_aabb()
					for i in range(count):
						var transform := multi.global_transform * multi.multimesh.get_instance_transform(i)
						for corner in range(8):
							points.append(transform * bounds.get_endpoint(corner))
				elif geometry is MeshInstance3D:
					var single := geometry as MeshInstance3D
					if single.mesh == null:
						continue
					var bounds := single.mesh.get_aabb()
					for corner in range(8):
						points.append(single.global_transform * bounds.get_endpoint(corner))
		if points.size() > 2:
			var right := _camera.global_basis.x
			var up := _camera.global_basis.y
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			var center := Vector3.ZERO
			for point in points:
				center += point
				var projected := Vector2(point.dot(right), point.dot(up))
				low = low.min(projected)
				high = high.max(projected)
			var middle := (low + high) * 0.5
			center = _actor.global_position + right * (middle.x - _actor.global_position.dot(right)) + up * (middle.y - _actor.global_position.dot(up))
			wanted_offset = center - _actor.global_position + up * 0.8
			var aspect := float(get_viewport().get_visible_rect().size.x) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
			wanted_size = clampf(maxf((high.y - low.y + 3.0) / 0.86, (high.x - low.x + 3.0) / aspect), CAMERA_SIZE, 32.0)
		state.size = lerpf(state.size, wanted_size, 1.0 - exp(-delta * 4.0))
		state.focus_offset = state.focus_offset.lerp(wanted_offset, 1.0 - exp(-delta * 4.0))
	# 短暂平滑衰减的取景偏移，反馈只影响视觉焦点，不改变人物/剑轨迹。
	if _feedback_age < 0.4:
		var envelope := pow(1.0 - _feedback_age / 0.4, 2.0) * _feedback_power * 0.13
		_last_shake = Vector3(sin(_feedback_age * 57.0), sin(_feedback_age * 43.0), 0.0) * envelope
		state.focus_offset += _last_shake


func _build_stage_details() -> void:
	for radius in [6.0, 10.0, 14.0]:
		var ring := MeshInstance3D.new()
		ring.mesh = SwordSpellVisual.ring_mesh(radius, 0.045)
		ring.material_override = SwordSpellVisual.glow_material(Color(0.23, 0.38, 0.36, 0.55))
		ring.position = Vector3(0.0, 0.018, -2.0)
		add_child(ring)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(48):
		var angle := float(i) * TAU / 48.0
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		SwordSpellVisual.append_line(mesh, radial * 13.4, radial * 13.85, 0.05, Color(0.45, 0.44, 0.26, 0.45), Color(0.45, 0.44, 0.26, 0.45))
	mesh.surface_end()
	var marks := MeshInstance3D.new()
	marks.mesh = mesh
	marks.material_override = SwordSpellVisual.glow_material(Color.WHITE)
	marks.position = Vector3(0.0, 0.025, -2.0)
	add_child(marks)
	# 独立低高台用于地形选点验收，保留旧五木桩布局与导航空间。
	var platform := StaticBody3D.new()
	platform.name = "TargetPlatform"
	platform.collision_layer = 3
	add_child(platform)
	_add_box(platform, Vector3(10.0, 0.75, -5.0), Vector3(4.0, 1.5, 4.0))
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 1.5, 4.0)
	visual.mesh = box
	visual.position = Vector3(10.0, 0.75, -5.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.16, 0.17)
	visual.material_override = material
	add_child(visual)


func _build_audio() -> void:
	_impact_audio = AudioStreamPlayer3D.new()
	_impact_audio.stream = load("res://game/shared/sword_cast/audio/giant_impact.wav")
	_impact_audio.volume_db = -10.0
	_impact_audio.max_distance = 90.0
	add_child(_impact_audio)
	_light_audio = AudioStreamPlayer3D.new()
	_light_audio.stream = load("res://game/shared/sword_cast/audio/light_sword.wav")
	_light_audio.volume_db = -20.0
	_light_audio.max_distance = 80.0
	add_child(_light_audio)
