extends SceneTree

## 地形接触训练场 · 共面修复的「移动中」像素对照（**experimental / 非门禁**）。
##
## 状态声明（2026-09-18）：
## - 本脚本是实验性探针，**不是门禁**，不参与 Tier 0，也不作为验收或放行依据。
## - **当前未建立有效量化结论**：冻结组残余帧间差异实测 3.687%–9.762%，说明相机链与
##   渲染仍在变化，控制组未生效；移动组读数因此不可归因，不能证明共面闪烁已消除。
## - 共面修复的依据是静态共面扫描（121 → 8，未允许 A 类 = 0），不是本脚本的像素读数。
## - 保留本文件待下轮修严控制组；不得据本脚本声称验收通过。
##
## 依据 notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md 的运行时证据口径：
## 只用单张静止截图会得到假阴性，必须同时给出「移动中」与「冻结静止」两组对照。
##
## 用法（需窗口渲染器，无头无法截图）：
##   Godot --path src --script res://tests/ground_contact_course_surface_clearance_capture.gd -- \
##       --out=<abs dir> [--label=prefix]
##
## 输出：<out>/<label>_moving_<i>.png（移动帧）、<out>/<label>_frozen_<i>.png（冻结对照）、
##       <out>/<label>_report.txt（逐帧 changed-ish px / maxdelta / 采样点）

const SCENE := "res://levels/experiments/character_movement/ground_contact_course.tscn"
const FRAMES := 6
## 通道差 ≥ 该值即算「变了」；用于滤掉渲染噪声。
const CHANNEL_THRESHOLD := 12

var _out := ""
var _label := "surface_clearance"
var _actor: CharacterBody3D
var _camera: Camera3D
var _lines: PackedStringArray = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL 无头渲染器无法截图，请用窗口模式运行")
		quit(1)
		return
	if change_scene_to_file(SCENE) != OK:
		print("FAIL 无法加载 %s" % SCENE)
		quit(1)
		return
	await scene_changed
	await _frames(20)
	_bind()
	if _actor == null:
		print("FAIL 场景缺少角色根")
		quit(1)
		return
	var dir := DirAccess.open(_out)
	if dir == null:
		print("FAIL 输出目录不存在：%s" % _out)
		quit(1)
		return

	# 台阶区是本轮 A 类热点（step_*_top 的共面就在此处），把镜头固定在该区。
	_camera.size = 17.0
	_camera.global_position = Vector3(-4.0, 14.0, 12.0)

	# --- 移动组：真实按键推进，角色走过 0.25 / 0.50 / 0.75 m 三级台阶 ---
	_place(Vector3(-1.6, 0.05, -3.4))
	await _frames(12)
	Input.parse_input_event(_key(KEY_D, true))
	await _frames(10)
	await _measure("moving", FRAMES, true)
	Input.parse_input_event(_key(KEY_D, false))
	await _frames(4)

	# --- 冻结对照：同一构图、同一材质，物理暂停后连续取帧 ---
	_place(Vector3(-1.6, 0.05, -3.4))
	await _frames(12)
	await _measure("frozen", FRAMES, false)
	_write_report()
	print("SURFACE_CLEARANCE_CAPTURE 完成 -> %s" % _out)


func _bind() -> void:
	for child in current_scene.find_children("*", "CharacterBody3D", true, false):
		_actor = child as CharacterBody3D
		break
	_camera = root.get_camera_3d()


func _place(position: Vector3) -> void:
	_actor.global_position = position
	_actor.velocity = Vector3.ZERO


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


## 连续取 FRAMES 帧，与前一帧做全画面像素差；冻结组同时暂停物理以排除自然位移。
func _measure(tag: String, count: int, physics_running: bool) -> void:
	var previous: Image = null
	var frozen_camera_xform := Transform3D()
	if not physics_running:
		PhysicsServer3D.set_active(false)
		frozen_camera_xform = _camera.global_transform
		_set_follow_enabled(false)
		await _frames(2)
	for index in range(count):
		await _frames(3)
		if not physics_running:
			# 冻结相机链：跟随脚本仍会缓动，必须每帧把相机钉回起始位姿。
			_camera.global_transform = frozen_camera_xform
		var image := root.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		if previous != null:
			var stats := _diff(previous, image)
			var line := "%s frame %d changed-ish px=%d (%.3f%%) maxdelta=%d samples=%d" % [
				tag, index, stats[0], stats[1], stats[2], stats[3]]
			_lines.append(line)
			print(line)
		previous = image
		image.save_png("%s/%s_%s_%d.png" % [_out, _label, tag, index])
	if not physics_running:
		_set_follow_enabled(true)
		PhysicsServer3D.set_active(true)


## 关闭/恢复相机自身与其祖先（场景跟随脚本所在节点）的处理，形成真正的静止对照。
func _set_follow_enabled(enabled: bool) -> void:
	var node: Node = _camera
	while node != null and node != current_scene:
		node.set_process(enabled)
		node.set_physics_process(enabled)
		node = node.get_parent()


## 返回 [changed-ish 像素数, 占比百分数, 最大通道差, 采样点数]。
func _diff(a: Image, b: Image) -> Array:
	var width := a.get_width()
	var height := a.get_height()
	var changed := 0
	var maxdelta := 0
	var samples := 0
	var da := a.get_data()
	var db := b.get_data()
	var total := width * height * 4
	var index := 0
	while index < total:
		samples += 1
		var delta := absi(int(da[index]) - int(db[index]))
		if delta > maxdelta:
			maxdelta = delta
		if delta >= CHANNEL_THRESHOLD:
			changed += 1
		index += 4
	return [changed, 100.0 * float(changed) / float(max(samples, 1)), maxdelta, samples]


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _write_report() -> void:
	var file := FileAccess.open("%s/%s_report.txt" % [_out, _label], FileAccess.WRITE)
	if file == null:
		return
	file.store_line("scene=%s frames=%d threshold=%d" % [SCENE, FRAMES, CHANNEL_THRESHOLD])
	for line in _lines:
		file.store_line(line)
