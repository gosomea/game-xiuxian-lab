extends SceneTree

## 群山宗门视觉/环境取证脚本（环境集成代理所有）。
##
## 职责：以真实默认镜头取证 + 曝光/阴影诊断。生产场景 mountain_realm.gd 不含任何截图或性能钩子。
##
## 用法（窗口模式，单次运行 <45s）：
##   Godot --path src --script res://tests/mountain_visual_playtest.gd -- \
##     --capture-prefix=<绝对前缀> [--shot=default|vista|summit] [--diag=<name>]
##
## shot 三种模式：
##   default  生产相机原样（跟随角色），默认近景 —— 用于"普通游玩镜头"取证。
##   vista    独立取证相机（make_current）从远处看五峰全貌；生产相机不受影响。
##   summit   角色置于主峰落点，仍用生产跟随相机取景。
## diag 只做运行期诊断，不写回场景文件。

const SCENE := "res://levels/experiments/character_movement/mountain_realm.tscn"
const LAYOUT_PATH := "res://levels/experiments/character_movement/mountain_realm_layout.json"
const CAPTURE_TIMEOUT_MSEC := 15000

var _prefix := ""
var _diag := ""
## 取景模式：default（生产相机）/ vista（独立取证相机）/ summit（主峰落点）。
var _shot := "default"
## 可选数值覆盖（仅本脚本运行期，不写回场景）：--sun= --ambient-energy= --exposure= --sky-energy=
var _sun := -1.0
var _ambient := -1.0
var _exposure := -1.0
var _sky_energy := -1.0
var _frames := 0
var _seconds := 0.0
var _frame_drawn := false
## 非空时执行角色表现验证（rig）而不是取景截图。
var _verify := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
		elif argument.begins_with("--shot="):
			_shot = argument.trim_prefix("--shot=")
		elif argument.begins_with("--diag="):
			_diag = argument.trim_prefix("--diag=")
		elif argument.begins_with("--verify="):
			_verify = argument.trim_prefix("--verify=")
		elif argument.begins_with("--sun="):
			_sun = float(argument.trim_prefix("--sun="))
		elif argument.begins_with("--ambient-energy="):
			_ambient = float(argument.trim_prefix("--ambient-energy="))
		elif argument.begins_with("--exposure="):
			_exposure = float(argument.trim_prefix("--exposure="))
		elif argument.begins_with("--sky-energy="):
			_sky_energy = float(argument.trim_prefix("--sky-energy="))
	_run.call_deferred()


func _process(delta: float) -> bool:
	_frames += 1
	_seconds += delta
	return false


func _run() -> void:
	root.size = Vector2i(1280, 800)
	if change_scene_to_file(SCENE) != OK:
		push_error("mountain_visual_playtest: 无法加载场景 %s" % SCENE)
		quit(1)
		return
	await scene_changed
	await _frames_wait(10)
	var world_env := current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := current_scene.get_node_or_null("Sun") as DirectionalLight3D
	if world_env == null or sun == null:
		push_error("mountain_visual_playtest: 场景缺少 WorldEnvironment 或 Sun")
		quit(1)
		return
	if _verify == "rig":
		await _verify_rig()
		quit(0)
		return
	_apply_diag(world_env, sun)
	_apply_overrides(world_env, sun)
	var requested := _apply_shot()
	# 等字体上传与真实绘制帧，避免截到无字画面；期间生产脚本仍在跑自己的物理与跟随。
	await _wait_render_frames(48)
	root.get_texture().get_image()
	await _frames_wait(60)
	if not await _capture(requested):
		quit(1)
		return
	_report(world_env, sun)
	quit(0)


## 角色表现验证：真实按键行走，分两个时刻采样分件枢轴的 transform。
## 只读枢轴、只看表现层；不写任何玩法字段，不替代 QA 的物理矩阵。
func _verify_rig() -> void:
	var actor := current_scene.find_children("*", "CharacterBody3D", true, false)
	if actor.is_empty():
		push_error("RIGCHECK 场景缺少角色")
		return
	var presentation := _find_presentation(current_scene)
	if presentation == null:
		push_error("RIGCHECK 未找到 CultivatorPresentation 节点")
		return
	var legs: Array = [presentation.get("_legs")[0], presentation.get("_legs")[1]]
	var arms: Array = [presentation.get("_arms")[0], presentation.get("_arms")[1]]
	print("RIGCHECK pivots legs=%d arms=%d" % [legs.size(), arms.size()])
	var before_leg: Array[Transform3D] = []
	var before_arm: Array[Transform3D] = []
	for index in range(2):
		before_leg.append((legs[index] as Node3D).transform)
		before_arm.append((arms[index] as Node3D).transform)
	print("RIGCHECK t0 leg0=%s leg1=%s" % [_fmt(before_leg[0]), _fmt(before_leg[1])])
	print("RIGCHECK t0 arm0=%s arm1=%s" % [_fmt(before_arm[0]), _fmt(before_arm[1])])
	# 真实按键前进：走起来才能推进步态相位。
	_key(KEY_D, true)
	await _frames_wait(30)
	var moved := ((actor[0] as Node3D).global_position)
	_key(KEY_D, false)
	var after_leg: Array[Transform3D] = []
	var after_arm: Array[Transform3D] = []
	for index in range(2):
		after_leg.append((legs[index] as Node3D).transform)
		after_arm.append((arms[index] as Node3D).transform)
	print("RIGCHECK t1 leg0=%s leg1=%s" % [_fmt(after_leg[0]), _fmt(after_leg[1])])
	print("RIGCHECK t1 arm0=%s arm1=%s" % [_fmt(after_arm[0]), _fmt(after_arm[1])])
	var leg0_delta := before_leg[0].origin.distance_to(after_leg[0].origin) + absf(before_leg[0].basis.get_euler().x - after_leg[0].basis.get_euler().x)
	var leg1_delta := before_leg[1].origin.distance_to(after_leg[1].origin) + absf(before_leg[1].basis.get_euler().x - after_leg[1].basis.get_euler().x)
	var arm0_delta := before_arm[0].origin.distance_to(after_arm[0].origin) + absf(before_arm[0].basis.get_euler().x - after_arm[0].basis.get_euler().x)
	var arm1_delta := before_arm[1].origin.distance_to(after_arm[1].origin) + absf(before_arm[1].basis.get_euler().x - after_arm[1].basis.get_euler().x)
	print("RIGCHECK delta leg0=%.5f leg1=%.5f arm0=%.5f arm1=%.5f" % [leg0_delta, leg1_delta, arm0_delta, arm1_delta])
	# 两腿必须反相，否则是同一份枢轴被复制而不是真实步态。
	var leg0_rot: float = (legs[0] as Node3D).rotation.x
	var leg1_rot: float = (legs[1] as Node3D).rotation.x
	var opposite := signf(leg0_rot) != signf(leg1_rot) or absf(leg0_rot + leg1_rot) < 0.02
	print("RIGCHECK opposite=%s (leg0=%.4f leg1=%.4f)" % [str(opposite), leg0_rot, leg1_rot])
	var ok := leg0_delta > 0.0005 and leg1_delta > 0.0005 and arm0_delta > 0.0005 and arm1_delta > 0.0005 and opposite
	print("RIGCHECK RESULT %s" % ("PASS" if ok else "FAIL"))
	# 手/脚必须在角色附近：枢轴世界位置与角色根的水平距离不应出现离体漂移。
	for group in [legs, arms]:
		for node in group:
			var offset := (node as Node3D).global_position - (actor[0] as Node3D).global_position
			if offset.length() > 3.0:
				print("RIGCHECK FAIL detached pivot %s offset=%.2f" % [(node as Node3D).name, offset.length()])


func _find_presentation(root_node: Node) -> Node:
	for node in root_node.find_children("*", "Node3D", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("cultivator_presentation.gd"):
			return node
	return null


func _fmt(xform: Transform3D) -> String:
	return "(%.3f,%.3f,%.3f)" % [xform.origin.x, xform.origin.y, xform.origin.z]


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


## 取景：返回本次请求的相机参数（位置 / 正交尺寸），供捕获后与实际值比对。
## vista 用独立 Camera3D 并 make_current：生产 _follow_camera 每帧写它自己的相机，
## 不会覆盖取证相机，因此远景构图稳定可复现。
func _apply_shot() -> Dictionary:
	if _shot == "vista":
		var camera := Camera3D.new()
		camera.name = "VistaCamera"
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.near = 0.1
		camera.far = 1400.0
		camera.size = 190.0
		# 正交投影下取景只由 size 决定，距离只影响雾。沿用与生产相同的三分之四俯角、
		# 保持与游玩相近的近距离，避免整幅被远距离雾洗白（远景靠雾色而非重雾衔接）。
		var target := Vector3(-2.0, 20.0, -8.0)
		var direction := Vector3(0.62, 0.95, 1.0).normalized()
		camera.position = target + direction * 70.0
		current_scene.add_child(camera)
		camera.look_at(target, Vector3.UP)
		camera.make_current()
		return {"camera": camera, "position": camera.position, "size": camera.size}
	if _shot == "summit":
		var actor := current_scene.find_children("*", "CharacterBody3D", true, false)
		var point := _landing_point("summit_sect")
		if not actor.is_empty() and not point.is_empty():
			(actor[0] as Node3D).global_position = Vector3(
				point["center"][0], float(point["top_y"]) + 0.05, point["center"][1])
		var follow := root.get_camera_3d()
		if follow != null:
			follow.size = 70.0
		return {"camera": follow, "size": 70.0}
	return {"camera": root.get_camera_3d(), "size": -1.0}


func _landing_point(name: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	for value in (parsed as Dictionary).get("landing_points", []):
		var point: Dictionary = value
		if str(point.get("name", "")) == name:
			return point
	return {}


## 诊断开关只改运行期实例，不写回场景文件。
func _apply_diag(world_env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if _diag.is_empty():
		return
	var env := world_env.environment
	match _diag:
		"lights-off":
			sun.light_energy = 0.0
			env.ambient_light_energy = 0.0
		"sun-only":
			env.ambient_light_energy = 0.0
		"ambient-only":
			sun.light_energy = 0.0
		"no-fog":
			env.fog_enabled = false
		"no-shadow":
			sun.shadow_enabled = false
		"no-tonemap":
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_:
			push_error("mountain_visual_playtest: 未知 diag %s" % _diag)
	print("DIAG %s" % _diag)


func _apply_overrides(world_env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var env := world_env.environment
	if _sun >= 0.0:
		sun.light_energy = _sun
	if _ambient >= 0.0:
		env.ambient_light_energy = _ambient
	if _exposure >= 0.0:
		env.tonemap_exposure = _exposure
	var sky_mat := env.sky.sky_material if env.sky != null else null
	if _sky_energy >= 0.0 and sky_mat is ProceduralSkyMaterial:
		(sky_mat as ProceduralSkyMaterial).sky_energy_multiplier = _sky_energy


func _report(world_env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var env := world_env.environment
	var fps := float(_frames) / maxf(_seconds, 0.001)
	print("PERF shot=%s avg_fps=%.1f avg_frame_ms=%.2f samples=%d" % [
		_shot, fps, 1000.0 / maxf(fps, 0.001), _frames])
	print("ENV sun=%.2f ambient=%.2f exposure=%.2f fog=%s tonemap=%d bg=%d" % [
		sun.light_energy, env.ambient_light_energy, env.tonemap_exposure,
		str(env.fog_enabled), env.tonemap_mode, env.background_mode])


func _capture(requested: Dictionary) -> bool:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_visual_playtest: 截图需要窗口模式（dummy 渲染器不出帧）")
		return false
	_frame_drawn = false
	RenderingServer.frame_post_draw.connect(_on_frame_drawn, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + CAPTURE_TIMEOUT_MSEC
	while not _frame_drawn and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _frame_drawn:
		push_error("mountain_visual_playtest: 等待渲染帧超时")
		return false
	# 捕获时打印实际生效的相机参数，并与请求值比对：只打印 _apply 前的值等于没有证据。
	var camera := root.get_camera_3d()
	var actual_position := camera.global_position if camera != null else Vector3.ZERO
	var actual_size := camera.size if camera != null else -1.0
	print("CAMERA actual pos=%s size=%.2f current=%s" % [
		str(actual_position), actual_size, str(camera.name) if camera != null else "<null>"])
	if requested.has("size") and float(requested["size"]) > 0.0:
		var want_size := float(requested["size"])
		var size_ok := absf(actual_size - want_size) < 0.01
		print("CAMERA assert size_ok=%s" % str(size_ok))
		if not size_ok:
			push_error("mountain_visual_playtest: 相机尺寸未按请求生效")
			return false
	# 独立取证相机必须确认没有被生产跟随覆盖。
	if requested.has("position") and requested["position"] is Vector3:
		var want_position: Vector3 = requested["position"]
		var pos_ok := actual_position.distance_to(want_position) < 0.01
		print("CAMERA assert pos_ok=%s" % str(pos_ok))
		if not pos_ok:
			push_error("mountain_visual_playtest: 取证相机被场景跟随覆盖")
			return false
	if requested.has("camera") and requested["camera"] is Camera3D and _shot == "vista":
		var wanted: Camera3D = requested["camera"]
		if root.get_camera_3d() != wanted:
			push_error("mountain_visual_playtest: 当前相机不是取证相机")
			return false
	var suffix := _shot if _diag.is_empty() else "%s-%s" % [_shot, _diag]
	var path := "%s-%s.png" % [_prefix, suffix]
	var error := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s (error %d)" % [path, error])
	return error == OK


func _wait_render_frames(count: int) -> void:
	var drawn: Array[int] = [0]
	var on_draw := func() -> void: drawn[0] += 1
	RenderingServer.frame_post_draw.connect(on_draw)
	var deadline := Time.get_ticks_msec() + CAPTURE_TIMEOUT_MSEC
	while drawn[0] < count and Time.get_ticks_msec() < deadline:
		await process_frame
	RenderingServer.frame_post_draw.disconnect(on_draw)


func _frames_wait(count: int) -> void:
	for index in range(count):
		await physics_frame


func _on_frame_drawn() -> void:
	_frame_drawn = true