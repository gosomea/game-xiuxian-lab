extends SceneTree
## 实际六招的近景动作、连续位姿与手部渲染验收；不改变正式镜头。
const SCENE := "res://levels/experiments/sword_combat/sword_workbench.tscn"
var _scene: Node3D
var _actor: Swordsman
var _cast: SwordCastComponent
var _body: Skeleton3D
var _view: SubViewport
var _camera: Camera3D
var _out := ""
var _rows: Array = []
var _checks: Array = []
var _offscreen := false
var _forms: Array[String] = SwordCastComponent.FORMS
var _failed := 0
var _recording := false
var _record_form := ""
var _serial := 0
var _record_serial := -1
var _previous_wrist := Vector3.ZERO
var _previous_rotation := Quaternion.IDENTITY
var _max_step := 0.0
var _max_turn := 0.0
var _max_weight := 0.0
var _aim_point := Vector3(0,0,-4)
var _observed_wrist := Vector3.ZERO
var _observed_rotation := Quaternion.IDENTITY
func _initialize() -> void:
	Engine.max_fps = 60
	process_frame.connect(_frame_started)
	_out = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("docs/playtest/2026-10-10-sword-finger-gesture/upright105")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="): _out = arg.trim_prefix("--evidence-dir=")
		if arg == "--offscreen": _offscreen = true
		if arg.begins_with("--form="): _forms = [arg.trim_prefix("--form=")]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.always_on_top = false
	if _offscreen: root.mode = Window.MODE_MINIMIZED
	change_scene_to_file(SCENE)
	await scene_changed
	await _frames(20)
	_scene = current_scene
	_actor = _scene.call("actor")
	_cast = _scene.call("cast_component")
	_body = _actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var modifier := _body.get_node("SwordCastPoseModifier") as SwordCastPoseModifier
	modifier.modification_processed.connect(_observe_modified_pose)
	_observe_modified_pose()
	physics_frame.connect(_pin_aim)
	var container := SubViewportContainer.new()
	container.name = "GestureAcceptanceCloseup"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(container)
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 800)
	_view.world_3d = _scene.get_world_3d()
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_view)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.4
	_camera.current = true
	_view.add_child(_camera)
	_camera.global_position = _actor.global_position + Vector3(1.4, 1.55, -3.0)
	_camera.look_at(_actor.global_position + Vector3(0, 1.35, 0), Vector3.UP)
	await _frames(6)
	await _capture("idle")
	for form in _forms:
		await _exercise(form)
	# 取消聚剑与重复切招，收势归零。
	_scene.call("reset_experiment")
	await _frames(30)
	_scene.call("select_form", SwordCastComponent.FORM_RAIN)
	await _aim(Vector3(0,0,-4)); _click(true)
	await _frames(24)
	_scene.call("select_form", SwordCastComponent.FORM_QI)
	_click(false)
	await _frames(45)
	var presentation := _actor.get_node("SwordCastPresentation") as SwordCastPresentation
	_check(presentation.pose_weight() < 0.01 and float(presentation.hand_state()["weight"]) < 0.01, "切招取消后人物与手指完全收势")
	await _capture("cancel_settled")
	_scene.call("reset_experiment")
	await _frames(5)
	_actor.press_flight_toggle()
	await _frames(20)
	_check(_actor.motion().flight_active, "优化后原御剑入口有效")
	_actor.press_flight_toggle()
	await _frames(25)
	var f := FileAccess.open(_out.path_join("acceptance.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":_checks,"samples":_rows,"failed":_failed,"command_pitch_degrees":105,"rendering_method":RenderingServer.get_current_rendering_method()}, "  "))
	print("GESTURE_ACCEPTANCE checks=%d failed=%d" % [_checks.size(),_failed])
	quit(1 if _failed > 0 else 0)
func _exercise(form: String) -> void:
	print("EXERCISE ", form)
	_scene.call("reset_experiment")
	await _frames(40)
	_scene.call("select_form", form)
	await _aim(Vector3(0,0,-4))
	_actor.set_aim_direction(Vector3.FORWARD)
	await _frames(8)
	_click(true)
	_previous_wrist = _wrist()
	_previous_rotation = _hand_rotation()
	_max_step = 0.0; _max_turn = 0.0; _max_weight = 0.0
	_record_form = form; _recording = true; _record_serial = -1
	var sample_start := _rows.size()
	for frame in range(320):
		await _frames(1)
		if frame == 45: _click(false)
		if frame in [0,8,18,35,45,50,58,63,80,105,150,220,319]: await _capture(form+"-%03d"%frame)
		if form == SwordCastComponent.FORM_WHEEL and frame <= 120 and frame % 2 == 0:
			await _capture("sequence-%03d"%frame)
	_recording = false
	var evidence := FileAccess.open(_out.path_join(form+"-motion.json"), FileAccess.WRITE)
	evidence.store_string(JSON.stringify(_rows.slice(sample_start), "  "))
	_check(_max_weight > 0.9, form + "完整结成剑指")
	_check(_max_step < 0.14, form + "手腕无超过十四厘米逐帧跳变 %.3f" % _max_step)
	_check(_max_turn < 0.7, form + "手腕朝向连续 %.3f" % _max_turn)
	await _frames(160)
	await _capture(form+"-settled")
	var presentation := _actor.get_node("SwordCastPresentation") as SwordCastPresentation
	_check(presentation.pose_weight() < 0.01, form + "结束恢复移动动作")
	if form == SwordCastComponent.FORM_WHEEL:
		var saved_transform := _camera.global_transform
		var saved_size := _camera.size
		_camera.size = 0.36
		var point := _wrist()
		_camera.global_position = point + Vector3(.3,.05,-.45)
		_camera.look_at(point + Vector3(0,.07,0), Vector3.UP)
		# 当前招式由真正的输入重新蓄势。
		await _aim(Vector3(0,0,-4)); _click(true); await _frames(38)
		point = _wrist()
		_camera.global_position = point + Vector3(.3,.08,-.45)
		_camera.look_at(point + Vector3(0,.07,0), Vector3.UP)
		await _frames(4); await _capture("finger_detail")
		_click(false); await _frames(170)
		_camera.size = saved_size; _camera.global_transform = saved_transform
func _observe_modified_pose() -> void:
	var pose := _body.global_transform * _body.get_bone_global_pose(_body.find_bone("mixamorig_RightHand"))
	_observed_wrist = pose.origin
	_observed_rotation = pose.basis.orthonormalized().get_rotation_quaternion()
	if _recording and _record_serial != _serial:
		_record_serial = _serial
		_max_step = maxf(_max_step, _previous_wrist.distance_to(_observed_wrist))
		_max_turn = maxf(_max_turn, _previous_rotation.angle_to(_observed_rotation))
		_previous_wrist = _observed_wrist; _previous_rotation = _observed_rotation
		var presentation := _actor.get_node("SwordCastPresentation") as SwordCastPresentation
		_max_weight = maxf(_max_weight, float(presentation.hand_state()["weight"]))
		var basis := pose.basis.orthonormalized()
		_rows.append({"form":_record_form,"render_frame":_serial,"delta":_scene.get_process_delta_time(),"wrist":[pose.origin.x,pose.origin.y,pose.origin.z],"rotation":[_observed_rotation.x,_observed_rotation.y,_observed_rotation.z,_observed_rotation.w],"fingers":[basis.y.x,basis.y.y,basis.y.z],"palm_width":[basis.x.x,basis.x.y,basis.x.z],"phase":_cast.pose_phase,"progress":_cast.pose_progress,"weight":presentation.pose_weight(),"finger_weight":presentation.hand_state()["weight"]})
func _frame_started() -> void:
	_serial += 1

func _wrist() -> Vector3:
	return _observed_wrist
func _hand_rotation() -> Quaternion:
	return _observed_rotation
func _check(ok: bool, label: String) -> void:
	_checks.append({"pass":ok,"label":label})
	if not ok: _failed += 1
	print("PASS " if ok else "FAIL ", label)
func _capture(label: String) -> void:
	if _offscreen:
		RenderingServer.force_draw(false)
	else:
		await RenderingServer.frame_post_draw
	var result := _view.get_texture().get_image().save_png(_out.path_join(label+".png"))
	if result != OK: _check(false, "截图保存失败 "+label)
func _frames(count: int) -> void:
	for i in range(count): await process_frame
func _click(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	_scene.call("_unhandled_input", event)
func _aim(point: Vector3) -> void:
	_aim_point = point
	_pin_aim()
	await _frames(1)
func _pin_aim() -> void:
	if _scene == null: return
	var camera := _scene.get_viewport().get_camera_3d()
	if camera == null: return
	var event := InputEventMouseMotion.new()
	event.position = root.get_stretch_transform() * camera.unproject_position(_aim_point)
	event.global_position = event.position
	_scene.call("_input", event)
