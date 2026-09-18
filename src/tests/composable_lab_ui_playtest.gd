extends SceneTree

## 生产 UI 真实配置复核（2026-09-18）。
##
## 口径：
## - **不改** project.godot 的 content_scale_mode/size/aspect（生产 canvas_items + 1280x800 + keep 等比），
##   只设 root.size（请求窗口）；四个量分开记录：窗口 / 逻辑画布 / PNG 实际像素 / letterbox。
## - HUD 控件矩形与 Camera3D.unproject_position() **都在逻辑画布坐标系**，直接比较。
## - 统计范围 = LabHud 常显矩形 **加** 场景自有常显面板（TimelinePanel/LedgerPanel/PreviewPanel），
##   去重包含关系后分别报「LabHud」与「总量」。压力场账本常显是已批准例外，可豁免 15%，但不漏算。
## - 角色/相机缺失、角色在相机后方或出画布都是**失败**，不跳过（避免假绿）。
##
## 用法：
##   Godot --path src --script res://tests/composable_lab_ui_playtest.gd -- --capture-prefix=<前缀>
##   --no-capture：只验证矩阵、不落图（回归用，不产生新 PNG）。

const SCENES := [
	["camera_lab", "res://levels/experiments/character_movement/camera_lab.tscn"],
	["motion_stage", "res://levels/experiments/character_movement/motion_stage.tscn"],
	["ground_contact_course", "res://levels/experiments/character_movement/ground_contact_course.tscn"],
	["sword_flight_course", "res://levels/experiments/character_movement/sword_flight_course.tscn"],
	["state_transition_lab", "res://levels/experiments/character_movement/state_transition_lab.tscn"],
	["movement_garden", "res://levels/experiments/character_movement/movement_garden.tscn"],
	["mountain_realm", "res://levels/experiments/character_movement/mountain_realm.tscn"],
]
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]
const BASE_CANVAS := Vector2i(1280, 800)
const SCENE_PANELS: Array[String] = ["TimelinePanel", "LedgerPanel", "PreviewPanel"]
const COVERAGE_LIMIT := 0.15
## 压力场账本常显属已批准例外：豁免总量上限，但报告仍给出实际总量。
const PANEL_EXEMPT_SCENES: Array[String] = ["state_transition_lab"]
const CAPTURE_TIMEOUT_MSEC := 6000

var _failed := 0
var _prefix := ""
var _no_capture := false
var _frame_drawn := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
		elif argument == "--no-capture":
			_no_capture = true
	_run.call_deferred()


func _run() -> void:
	if _prefix.is_empty() and not _no_capture:
		print("FAIL 需要 -- --capture-prefix=<前缀> 或 --no-capture")
		quit(1)
		return
	if root.content_scale_size != BASE_CANVAS or root.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		_check(false, "生产 stretch 配置被改动（size=%s mode=%d）；要求 canvas_items/%s" % [
			root.content_scale_size, root.content_scale_mode, BASE_CANVAS])
		_finish()
		return
	for size in WINDOW_SIZES:
		root.size = size
		for pair in SCENES:
			await _verify_scene(str(pair[0]), str(pair[1]), size)
		if size == WINDOW_SIZES[0]:
			await _verify_preview_controls()
	_finish()


func _verify_scene(id: String, scene_path: String, size: Vector2i) -> void:
	if change_scene_to_file(scene_path) != OK:
		_check(false, "%s：场景可加载" % id)
		return
	await scene_changed
	await _frames(12)
	var scene := current_scene
	if scene == null:
		_check(false, "%s：场景进入树" % id)
		return
	var logical := root.get_visible_rect().size
	var scale := root.get_final_transform().get_scale().x
	var letterbox := (Vector2(size) - Vector2(logical) * scale) * 0.5
	print("  METRIC %s window=%s logical=%s scale=%.3f png=%s letterbox=(%.0f,%.0f)" % [
		id, str(size), str(logical), scale, str(Vector2i(Vector2(logical) * scale)), letterbox.x, letterbox.y])
	await _check_ui(scene, id, size, logical)
	await _capture("%s-window%dx%d" % [id, size.x, size.y])


## LabHud + 场景自有可见面板的合并统计（去重包含关系）。
func _gather_ui(scene: Node, hud: Node) -> Dictionary:
	var rects: Array[Rect2] = []
	if hud != null:
		for rect in hud.call("occlusion_rects"):
			rects.append(rect as Rect2)
	var panel_names := PackedStringArray()
	for panel_name in SCENE_PANELS:
		var panel := scene.find_child(panel_name, true, false) as Control
		if panel != null and panel.is_visible_in_tree():
			rects.append(panel.get_global_rect())
			panel_names.append(panel_name)
	return {"all": _dedupe(rects), "panels": panel_names}


func _check_ui(scene: Node, id: String, size: Vector2i, logical: Vector2) -> void:
	var canvas_area := logical.x * logical.y
	var hud := scene.find_child("LabHud", true, false)
	_check(hud != null, "%s：装配共享 LabHud" % id)
	if hud == null:
		return
	var gathered := _gather_ui(scene, hud)
	var all_rects: Array[Rect2] = gathered["all"]
	var panel_names: PackedStringArray = gathered["panels"]
	_check(not all_rects.is_empty(), "%s：有可读常显 UI 矩形" % id)
	# 1) 全部常显 UI 在逻辑画布内（不裁切）。
	var out := 0
	for rect in all_rects:
		if not Rect2(Vector2.ZERO, logical).encloses(rect):
			out += 1
	_check(out == 0, "%s @%s：常显 UI %d 个矩形全在逻辑画布 %s 内（越界 %d）" % [
		id, str(size), all_rects.size(), str(logical), out])
	# 2) 覆盖率：LabHud / 总量分别报告；压力场豁免上限但计入。
	var hud_area := _area_of(_dedupe(_hud_rects(hud)))
	var total_area := _area_of(all_rects)
	print("  UI %s @%s hud=%.2f%% panels=%s total=%.2f%%" % [
		id, str(size), hud_area / canvas_area * 100.0,
		"none" if panel_names.is_empty() else "+".join(panel_names),
		total_area / canvas_area * 100.0])
	_check(hud_area / canvas_area <= COVERAGE_LIMIT,
		"%s @%s：LabHud 覆盖率 %.2f%% ≤ 15%%" % [id, str(size), hud_area / canvas_area * 100.0])
	var exempt := id in PANEL_EXEMPT_SCENES
	_check(total_area / canvas_area <= COVERAGE_LIMIT or exempt,
		"%s @%s：常显 UI 总量 %.2f%% ≤ 15%%%s" % [
			id, str(size), total_area / canvas_area * 100.0, "（压力场已批准例外，仍如实计入）" if exempt else ""])
	# 3) 可见按钮无空文字（is_visible_in_tree）。
	var visible_buttons := 0
	var blank := 0
	for node in _buttons(scene):
		var button := node as Button
		if not button.is_visible_in_tree():
			continue
		visible_buttons += 1
		if button.text.strip_edges().is_empty():
			blank += 1
	_check(blank == 0, "%s @%s：%d 个可见按钮无空文字（空 %d）" % [id, str(size), visible_buttons, blank])
	# 4) 主要角色必须真在画面且不被遮（缺相机/角色即失败）。
	var actor := _actor_of(scene)
	_check(actor != null, "%s @%s：场景含主要角色" % [id, str(size)])
	var camera := root.get_camera_3d()
	_check(camera != null, "%s @%s：场景有当前 Camera3D（遮人物检查前提）" % [id, str(size)])
	if actor != null and camera != null:
		_check_uncovered(id, size, logical, camera, actor.global_position + Vector3(0.0, 0.9, 0.0), all_rects, "主要角色")
	# 5) 详情开闭不抢控件。
	_check(not bool(hud.call("details_visible")), "%s：详情默认折叠" % id)
	_push_key(KEY_F1)
	await _frames(3)
	_check(bool(hud.call("details_visible")), "%s：F1 展开详情" % id)
	_push_key(KEY_F1)
	await _frames(3)
	_check(not bool(hud.call("details_visible")), "%s：F1 再按折叠详情" % id)
	_check(current_scene == scene, "%s：详情开闭不切场景、不抢控件" % id)


## 点必须在相机前方、在画布内、且不落在任何常显 UI 矩形里；任一不成立即失败。
func _check_uncovered(id: String, size: Vector2i, logical: Vector2, camera: Camera3D,
		world_point: Vector3, rects: Array[Rect2], label: String) -> void:
	_check(not camera.is_position_behind(world_point), "%s @%s：%s 不在相机后方" % [id, str(size), label])
	if camera.is_position_behind(world_point):
		return
	var point := camera.unproject_position(world_point)
	_check(Rect2(Vector2.ZERO, logical).has_point(point),
		"%s @%s：%s 在逻辑画布内（点 %s）" % [id, str(size), label, str(point.round())])
	if not Rect2(Vector2.ZERO, logical).has_point(point):
		return
	var hit := ""
	for rect in rects:
		if rect.has_point(point):
			hit = str(rect)
	_check(hit.is_empty(), "%s @%s：%s 不被常显 UI 遮（点 %s）%s" % [
		id, str(size), label, str(point.round()), "" if hit.is_empty() else "，命中 %s" % hit])


## motion_stage 最小档：真实 M 键切预览，量总 UI 面积、面板在画布内、不遮预览展示实例。
func _verify_preview_controls() -> void:
	if change_scene_to_file("res://levels/experiments/character_movement/motion_stage.tscn") != OK:
		_check(false, "motion_stage：可重新加载以验证预览")
		return
	await scene_changed
	await _frames(12)
	_push_key(KEY_M)
	await _frames(12)
	var scene := current_scene
	_check(str(scene.call("mode_name")) == "程序动作预览", "motion_stage @960：M 真实切入预览模式（%s）" % str(scene.call("mode_name")))
	var panel: Variant = scene.call("preview_panel")
	_check(panel != null and (panel as Control).is_visible_in_tree(), "motion_stage @960：预览面板可见")
	var logical := root.get_visible_rect().size
	var gathered := _gather_ui(scene, scene.find_child("LabHud", true, false))
	var all_rects: Array[Rect2] = gathered["all"]
	var panel_names: PackedStringArray = gathered["panels"]
	var total := _area_of(all_rects) / (logical.x * logical.y) * 100.0
	print("  UI motion_stage @960 preview total=%.2f%% panels=%s" % [total, "none" if panel_names.is_empty() else "+".join(panel_names)])
	_check(not panel_names.is_empty(), "motion_stage @960：预览态操作面板已计入总量（%s）" % "+".join(panel_names))
	var out := 0
	for rect in all_rects:
		if not Rect2(Vector2.ZERO, logical).encloses(rect):
			out += 1
	_check(out == 0, "motion_stage @960：预览态 UI %d 个矩形全在画布内（越界 %d）" % [all_rects.size(), out])
	var display := scene.call("preview") as Node3D
	_check(display != null, "motion_stage @960：可取得预览展示节点")
	var camera := root.get_camera_3d()
	_check(camera != null, "motion_stage @960：有当前 Camera3D（预览检查前提）")
	if display != null and camera != null:
		_check_uncovered("motion_stage", Vector2i(960, 640), logical, camera,
			display.global_position + Vector3(0.0, 0.9, 0.0), all_rects, "预览展示")
	var blank := 0
	var shown := 0
	for node in _buttons(scene):
		var button := node as Button
		if button.is_visible_in_tree():
			shown += 1
			if button.text.strip_edges().is_empty():
				blank += 1
	_check(blank == 0 and shown > 0, "motion_stage @960：预览控件 %d 个可见且无空文字（空 %d）" % [shown, blank])
	await _capture("motion_stage-preview-window960x640")


func _hud_rects(hud: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if hud != null:
		for rect in hud.call("occlusion_rects"):
			out.append(rect as Rect2)
	return out


## 去掉被其它矩形完全包含的项，避免嵌套面板重复计面积。
func _dedupe(rects: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in rects:
		var contained := false
		for other in rects:
			if other != rect and other.encloses(rect) and other.get_area() > rect.get_area():
				contained = true
				break
		if not contained:
			out.append(rect)
	return out


func _area_of(rects: Array[Rect2]) -> float:
	var area := 0.0
	for rect in rects:
		area += rect.get_area()
	return area


func _actor_of(scene: Node) -> CharacterBody3D:
	for child in scene.find_children("*", "CharacterBody3D", true, false):
		return child as CharacterBody3D
	return null


func _buttons(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


func _push_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame


## 取证：按 PNG 实际像素命名；--no-capture 时只做像素读回校验、不落盘。
func _capture(prefix: String) -> void:
	_frame_drawn = false
	RenderingServer.frame_post_draw.connect(_on_frame_drawn, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + CAPTURE_TIMEOUT_MSEC
	while not _frame_drawn and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _frame_drawn:
		_check(false, "等待渲染帧超时：%s" % prefix)
		return
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_check(false, "%s：截图像素真实读回" % prefix)
		return
	if _no_capture:
		print("  SKIP 保存 %s（--no-capture；实际像素 %s）" % [prefix, str(image.get_size())])
		return
	var pixels := image.get_size()
	var path := "%s-production-ui-%s-png%dx%d.png" % [_prefix, prefix, pixels.x, pixels.y]
	var error := image.save_png(path)
	_check(error == OK, "%s：保存 %s（实际像素 %s，错误 %d）" % [prefix, path, str(pixels), error])


func _on_frame_drawn() -> void:
	_frame_drawn = true


func _check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failed += 1


func _finish() -> void:
	print("COMPOSABLE_LAB_UI_PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)
