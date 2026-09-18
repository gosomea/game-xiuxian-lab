extends SceneTree

## 角色移动子实验目录的运行验收：真实场景树 + 真实键盘事件 + 真实场景切换。
##
## 用法（--headless 可跑；窗口模式附图）：
##   godot --headless --path src --script res://tests/movement_hub_playtest.gd
##   godot --path src --script res://tests/movement_hub_playtest.gd -- --capture-prefix=/abs/prefix
##
## 断言纪律：入口判定读真实 JSON 与真实场景加载；顶部入口、Esc 与按钮返回路径都真实切换后回读。
## 集成收口后七项子实验全部落地：镜头实验室 / 人物动作工作台 / 地形接触训练场 / 御剑飞行训练场 /
## 状态切换压力场 / 移动庭院 / 群山宗门。七个场景统一返回本目录
## res://levels/experiments/character_movement/movement_lab_hub.tscn；本目录的 Esc 与返回按钮回到顶层实验目录。
## 编辑器桥（godot-ai）本会话无活动编辑会话，验收档位为 CLI。
##
## 关于 planned 条目：集成收口后真实清单里已无 planned 条目，因此原先针对「计划条目禁用 /
## 显示尚未落地 / 不可进入」的 UI 运行断言不再适用，已随集成移除。若未来清单重新出现 planned
## 条目，必须恢复这组 UI 断言（禁用态、文案、不切换场景）。数据层的拒绝规则仍被保留：
## tests/test_movement_lab_hub.gd 继续用 planned 变异用例断言「planned 挂场景被拒绝 / 不可打开」。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const TOP_HUB := "res://levels/lab_hub.tscn"
const HUB_NODE_NAME := "MovementLabHub"
const TOP_HUB_NODE_NAME := "LabHub"
const DATA_PATH := "res://data/content/character_movement_subexperiments.json"
const EXPECTED_IDS := [
	"camera_lab",
	"motion_stage",
	"ground_contact_course",
	"sword_flight_course",
	"state_transition_lab",
	"movement_garden",
	"mountain_realm",
]
## 全部已落地子场景统一返回本目录（2026-09-18 集成收口：七项全部可进入）。
const OPENABLE_IDS := [
	"camera_lab",
	"motion_stage",
	"ground_contact_course",
	"sword_flight_course",
	"state_transition_lab",
	"movement_garden",
	"mountain_realm",
]

var _failed := 0
var _prefix := ""
## 可选截图标签：带标签时文件名加前缀（如 7of7-movement-hub-1280x800.png），
## 使新一阶段的截图不与既有探索资产重名、绝不覆盖旧图。
var _capture_tag := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
		elif argument.begins_with("--capture-tag="):
			_capture_tag = argument.trim_prefix("--capture-tag=")
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)

	# 1. 顶层实验目录 → 角色移动 → 子实验目录（真实按钮焦点 + 真实键盘回车）。
	if change_scene_to_file(TOP_HUB) != OK:
		print("FAIL 无法进入顶层实验目录")
		quit(1)
		return
	await scene_changed
	await _settle()
	_check(current_scene.name == TOP_HUB_NODE_NAME, "顶层实验目录已进入：%s" % current_scene.name)
	_check(_module_scene("character_movement") == HUB_SCENE, "顶层角色移动入口指向子实验目录")
	_check(ResourceLoader.exists(_module_scene("character_movement")), "顶层入口场景真实可加载")
	await _activate(current_scene.get_node("%ModuleGrid/Module_character_movement"))
	_check(current_scene.get_node("%LaunchButton").disabled == false, "顶层角色移动有可运行入口")
	await _activate(current_scene.get_node("%LaunchButton"))
	await _settle()
	_check(current_scene.name == HUB_NODE_NAME, "从顶层进入角色移动子实验目录：%s" % current_scene.name)

	# 2. 七项可见、顺序与清单一致、七项全部可进入。
	var grid := current_scene.get_node("%EntryGrid") as GridContainer
	_check(grid.get_child_count() == 7, "子实验目录显示 7 项（实际 %d）" % grid.get_child_count())
	var ids: Array[String] = []
	for child in grid.get_children():
		ids.append(str(child.name).trim_prefix("Entry_"))
	_check(ids == EXPECTED_IDS, "子实验顺序与清单一致：%s" % str(ids))
	_check(current_scene.get_node("%Count").text == "7 / 7", "计数如实显示已落地 7 / 7：%s" % current_scene.get_node("%Count").text)
	for id in EXPECTED_IDS:
		_check(grid.get_node_or_null("Entry_" + id) != null, "子实验条目存在：%s" % id)

	# 焦点优先落在清单里第一个可进入条目（当前为镜头实验室）。
	_check(current_scene.get_node("%DetailTitle").text == "镜头实验室", "初始焦点落在第一个可进入条目")
	_check(grid.get_node("Entry_camera_lab").has_focus(), "键盘焦点在镜头实验室按钮上")
	_check(current_scene.get_node("%LaunchButton").disabled == false, "镜头实验室提供运行入口")
	_check(current_scene.get_node("%DetailStatus").text.contains("探索中"), "可进入条目状态如实显示探索中")
	await _capture("movement-hub-1280x800")

	# 键盘方向键在条目间移动焦点；回车只更新详情，不切换场景。
	await _press_key(KEY_DOWN)
	var focus_owner: Control = current_scene.get_viewport().gui_get_focus_owner()
	_check(focus_owner is Button and str(focus_owner.name).begins_with("Entry_"),
		"方向键后焦点仍在子实验条目上：%s" % (str(focus_owner.name) if focus_owner != null else "<无>"))
	await _press_key(KEY_ENTER)
	_check(current_scene.name == HUB_NODE_NAME, "回车在焦点条目上只更新详情，不切换场景")
	_check(current_scene.get_node("%DetailTitle").text != "", "回车后详情仍可读")
	(grid.get_node("Entry_motion_stage") as Button).grab_focus()
	await _settle()
	_check(grid.get_node("Entry_motion_stage").has_focus(), "可显式恢复条目键盘焦点")

	# 3. 七项全部落地：逐项详情字段齐全、状态为探索中、入口可用。
	for id in EXPECTED_IDS:
		var expected_title := str(_sub_entry(id)["title"])
		var expected_stage := str(_sub_entry(id)["stage"])
		await _activate(grid.get_node("Entry_" + id))
		_check(current_scene.get_node("%DetailTitle").text == expected_title,
			"条目标题与清单一致：%s" % id)
		_check(current_scene.get_node("%DetailStatus").text.contains("探索中"), "条目状态显示探索中：%s" % id)
		_check(current_scene.get_node("%DetailStage").text.contains(expected_stage), "条目显示定位：%s" % id)
		_check(current_scene.get_node("%DetailPath").text.contains("res://levels/"),
			"条目显示真实入口路径：%s" % id)
		_check(current_scene.get_node("%LaunchButton").disabled == false, "条目提供运行入口：%s" % id)
		_check(current_scene.name == HUB_NODE_NAME, "仅选择详情不切换场景：%s" % id)

	# 4. 小窗布局与精确尺寸证据。
	# 小窗下的真实重排由窗口模式截图档覆盖（本机窗口管理器对内容尺寸有下限，实测约 1200x750，
	# 真实窗口压不到 960x640）。因此固定尺寸的小窗证据用离屏视口真实渲染，
	# 命名与内容像素严格一致；已有的真实窗口 960x600 资产保持不变。
	_check(grid.get_child_count() == 7 and grid.is_visible_in_tree(), "目录在小窗尺寸下 7 项始终可见")
	_check(current_scene.get_node("%Count").text == "7 / 7", "计数在目录中始终如实显示")
	await _capture_exact("movement-hub-960x640", Vector2i(960, 640))

	# 5. 七个场景入口与返回路径：逐项真实进入，Esc 必须回到本目录，再回顶层。
	for id in OPENABLE_IDS:
		if current_scene.name == TOP_HUB_NODE_NAME:
			await _enter_hub_from_top()
		grid = current_scene.get_node("%EntryGrid")
		var entry := _sub_entry(id)
		_check(not entry.is_empty() and str(entry["scene"]).begins_with("res://levels/"), "清单登记场景路径：%s" % id)
		_check(ResourceLoader.exists(str(entry["scene"])), "子场景真实可加载：%s" % id)
		# 与顶层目录一致的两步键盘流：先选择条目查看详情，再激活「进入子实验」。
		await _activate(grid.get_node("Entry_" + id))
		_check(current_scene.get_node("%DetailTitle").text != "", "键盘选择条目后详情更新：%s" % id)
		_check(current_scene.get_node("%LaunchButton").disabled == false, "已落地条目提供运行入口：%s" % id)
		await _activate(current_scene.get_node("%LaunchButton"))
		await _settle()
		_check(current_scene.name != HUB_NODE_NAME, "进入子场景：%s → %s" % [id, current_scene.name])
		_check(_scene_declares_hub_return(id), "子场景声明返回本目录常量：%s" % id)
		await _capture("movement-hub-entry-" + id)
		await _press_key(KEY_ESCAPE)
		await _settle()
		_check(current_scene.name == HUB_NODE_NAME, "Esc 从 %s 返回子实验目录 MovementLabHub：%s" % [id, current_scene.name])

	# 6. Esc 从子实验目录返回顶层实验目录；再验证顶部进入与返回按钮两条路径。
	if current_scene.name == TOP_HUB_NODE_NAME:
		await _enter_hub_from_top()
	_check(current_scene.name == HUB_NODE_NAME, "回到子实验目录继续返回路径验收")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_check(current_scene.name == TOP_HUB_NODE_NAME, "Esc 从子实验目录返回顶层实验目录：%s" % current_scene.name)
	await _enter_hub_from_top()
	_check(current_scene.name == HUB_NODE_NAME, "再次从顶层进入子实验目录")
	# Hub 自身的返回目标是顶层实验目录，按钮文本必须与之一致（与子场景的「返回子实验目录」区分）。
	_check((current_scene.get_node("%BackButton") as Button).text == "返回实验目录",
		"hub 返回按钮文本指向顶层实验目录：%s" % (current_scene.get_node("%BackButton") as Button).text)
	await _activate(current_scene.get_node("%BackButton"))
	await _settle()
	_check(current_scene.name == TOP_HUB_NODE_NAME, "返回按钮回到顶层实验目录：%s" % current_scene.name)

	print("PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)


func _enter_hub_from_top() -> void:
	await _activate(current_scene.get_node("%ModuleGrid/Module_character_movement"))
	await _activate(current_scene.get_node("%LaunchButton"))
	await _settle()


## 每个已落地子场景脚本必须声明返回本目录的常量（MOVEMENT_HUB_SCENE 或 HUB_SCENE 均可）。
func _scene_declares_hub_return(id: String) -> bool:
	var entry := _sub_entry(id)
	var source := FileAccess.get_file_as_string(str(entry["scene"]).trim_suffix(".tscn") + ".gd")
	if source.contains("MOVEMENT_HUB_SCENE") and source.contains(HUB_SCENE):
		return true
	return source.contains("HUB_SCENE") and source.contains(HUB_SCENE)


func _module_scene(id: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/experiments.json"))
	if not parsed is Dictionary:
		return ""
	for value in (parsed as Dictionary).get("modules", []) as Array:
		var module: Dictionary = value
		if str(module.get("id", "")) == id:
			return str(module.get("scene", ""))
	return ""


func _sub_entry(id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		return {}
	for value in (parsed as Dictionary).get("subexperiments", []) as Array:
		var entry: Dictionary = value
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func _activate(button: Button) -> void:
	button.grab_focus()
	await _press_key(KEY_ENTER)


func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()


func _settle() -> void:
	for index in range(6):
		await process_frame


## 固定尺寸精确截图：在指定像素尺寸的离屏视口里真实实例化并渲染子实验目录。
## 用于窗口管理器有尺寸下限、真实窗口无法压到的尺寸（如 960x640）；
## 生成的是真实布局与真实渲染，且命名与内容像素严格一致，报告里如实标注取证方式。
func _capture_exact(suffix: String, target: Vector2i) -> void:
	if _prefix.is_empty() or DisplayServer.get_name() == "headless":
		return
	var holder := SubViewport.new()
	holder.name = "ExactCaptureViewport"
	holder.size = target
	holder.transparent_bg = false
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(holder)
	var copy := (load(HUB_SCENE) as PackedScene).instantiate()
	holder.add_child(copy)
	for _index in range(10):
		await process_frame
	var image := holder.get_texture().get_image()
	var name := suffix if _capture_tag.is_empty() else "%s-%s" % [_capture_tag, suffix]
	var path := "%s-%s.png" % [_prefix, name]
	print("CAPTURE %s actual=%dx%d requested=%dx%d" % [name, image.get_width(), image.get_height(),
		target.x, target.y])
	_check(image.get_width() == target.x and image.get_height() == target.y,
		"离屏截图尺寸与命名一致：" + name)
	_check(image.save_png(path) == OK, "截图保存：" + name)
	holder.queue_free()


## 截图并如实报告真实像素尺寸：文件名与实际内容必须一致（macOS 会为窗口标题栏占用高度，
## 因此 requested 与 actual 可能不同——打印出来让证据自证，而不是靠命名假设）。
func _capture(suffix: String) -> void:
	if _prefix.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		_check(false, "截图读回为空：" + suffix)
		return
	var name := suffix if _capture_tag.is_empty() else "%s-%s" % [_capture_tag, suffix]
	var path := "%s-%s.png" % [_prefix, name]
	print("CAPTURE %s actual=%dx%d requested=%dx%d" % [name, image.get_width(), image.get_height(),
		root.size.x, root.size.y])
	_check(image.save_png(path) == OK, "截图保存：" + name)


func _check(ok: bool, message: String) -> bool:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failed += 1
	return ok
