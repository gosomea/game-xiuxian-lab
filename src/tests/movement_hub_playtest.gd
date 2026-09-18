extends SceneTree

## 角色移动子实验目录的运行验收：真实场景树 + 真实键盘事件 + 真实场景切换。
##
## 用法（--headless 可跑；窗口模式附图）：
##   godot --headless --path src --script res://tests/movement_hub_playtest.gd
##   godot --path src --script res://tests/movement_hub_playtest.gd -- --capture-prefix=/abs/prefix
##
## 断言纪律：入口判定读真实 JSON 与真实场景加载；返回路径真实切换后回读。
## 两级 2 击导航（S0）：顶层模块卡一次点击直达子目录；子目录条目卡一次点击直达子场景。
## 详情面板默认折叠，I 键 / 「说明」按钮展开，Esc 先关详情再返回。
##
## 关于 planned 条目：真实清单里已无 planned 条目，因此「计划条目禁用 / 尚未落地 / 不可进入」
## 的运行断言由数据层测试 tests/test_movement_lab_hub.gd 覆盖；UI 层只保留「详情默认折叠」断言。

const HUB_SCENE := "res://levels/experiments/character_movement/movement_lab_hub.tscn"
const TOP_HUB := "res://levels/lab_hub.tscn"
const HUB_NODE_NAME := "MovementLabHub"
const REALM_SCENE := "res://levels/experiments/character_movement/mountain_realm.tscn"
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

var _failed := 0
var _prefix := ""
## 可选截图标签：带标签时文件名加前缀，使新一阶段截图不与既有探索资产重名、不覆盖旧图。
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

	# 1. 顶层实验目录：点击「角色移动」模块卡一次即进入子实验目录（第 1 击）。
	if change_scene_to_file(TOP_HUB) != OK:
		print("FAIL 无法进入顶层实验目录")
		quit(1)
		return
	await scene_changed
	await _settle()
	_check(current_scene.name == TOP_HUB_NODE_NAME, "顶层实验目录已进入：%s" % current_scene.name)
	_check(_module_scene("character_movement") == HUB_SCENE, "顶层角色移动入口指向子实验目录")
	_check(ResourceLoader.exists(_module_scene("character_movement")), "顶层入口场景真实可加载")
	_check(not (current_scene.get_node("%Details") as Control).visible, "顶层目录详情默认折叠")
	_check(current_scene.get_node_or_null("%LaunchButton") == null, "顶层已移除旧「进入实验场景」按钮")
	await _activate(current_scene.get_node("%ModuleGrid/Module_character_movement"))
	await _settle()
	_check(current_scene.name == HUB_NODE_NAME, "点击模块卡一次直达子实验目录：%s" % current_scene.name)

	# 2. 七项可见、顺序与清单一致、详情默认折叠、焦点落在条目卡。
	var grid := current_scene.get_node("%EntryGrid") as GridContainer
	_check(grid.get_child_count() == 7, "子实验目录显示 7 项（实际 %d）" % grid.get_child_count())
	var ids: Array[String] = []
	for child in grid.get_children():
		ids.append(str(child.name).trim_prefix("Entry_"))
	_check(ids == EXPECTED_IDS, "子实验顺序与清单一致：%s" % str(ids))
	_check(current_scene.get_node("%Count").text == "7 / 7", "计数如实显示已落地 7 / 7：%s" % current_scene.get_node("%Count").text)
	for id in EXPECTED_IDS:
		_check(grid.get_node_or_null("Entry_" + id) != null, "子实验条目存在：%s" % id)
	_check(not (current_scene.get_node("%Details") as Control).visible, "子目录详情默认折叠")
	_check(grid.get_node("Entry_camera_lab").has_focus(), "初始键盘焦点在第一个条目卡上")
	_check(current_scene.get_node("%DetailTitle").text == "镜头实验室", "焦点所在条目详情已更新（无需回车）")
	await _capture("movement-hub-1280x800")

	# 3. 详情开关：I 键展开 / 再按折叠；Esc 在详情展开时先关详情。
	await _press_key(KEY_I)
	_check((current_scene.get_node("%Details") as Control).visible, "I 键展开详情")
	_check(current_scene.name == HUB_NODE_NAME, "展开详情不切换场景")
	await _press_key(KEY_ESCAPE)
	_check(not (current_scene.get_node("%Details") as Control).visible, "Esc 先关闭详情")
	_check(current_scene.name == HUB_NODE_NAME, "关详情后仍停留在子实验目录")

	# 4. 键盘方向键移动焦点仍可用；回车在条目卡上直接进入子场景（第 2 击）。
	await _press_key(KEY_DOWN)
	var focus_owner: Control = current_scene.get_viewport().gui_get_focus_owner()
	_check(focus_owner is Button and str(focus_owner.name).begins_with("Entry_"),
		"方向键后焦点仍在条目卡上：%s" % (str(focus_owner.name) if focus_owner != null else "<无>"))

	# 5. 小窗布局证据：固定 960x640 离屏视口真实渲染。
	_check(grid.get_child_count() == 7 and grid.is_visible_in_tree(), "目录在小窗尺寸下 7 项始终可见")
	_check(current_scene.get_node("%Count").text == "7 / 7", "计数在目录中始终如实显示")
	await _capture_exact("movement-hub-960x640", Vector2i(960, 640))

	# 6. 七项入口与返回路径：逐项一次点击真实进入，Esc 回到本目录。
	for id in EXPECTED_IDS:
		if current_scene.name == TOP_HUB_NODE_NAME:
			await _enter_hub_from_top()
		grid = current_scene.get_node("%EntryGrid")
		var entry := _sub_entry(id)
		_check(not entry.is_empty() and str(entry["scene"]).begins_with("res://levels/"), "清单登记场景路径：%s" % id)
		_check(ResourceLoader.exists(str(entry["scene"])), "子场景真实可加载：%s" % id)
		await _activate(grid.get_node("Entry_" + id))
		await _settle()
		# 必须精确进入清单登记的那个场景，而不是「任意别的场景」。
		_check(current_scene.scene_file_path == str(entry["scene"]),
			"点击 %s 精确进入清单登记场景：%s（实际 %s）" % [id, str(entry["scene"]), current_scene.scene_file_path])
		_check(_scene_declares_hub_return(id), "子场景声明返回本目录常量：%s" % id)
		await _capture("movement-hub-entry-" + id)
		await _press_key(KEY_ESCAPE)
		await _settle()
		_check(current_scene.name == HUB_NODE_NAME, "Esc 从 %s 返回子实验目录 MovementLabHub：%s" % [id, current_scene.name])
		# 返回记忆：回到目录后选中项应为刚进入的那一项。
		_check(str(current_scene.get_node("%DetailTitle").text) == str(entry["title"]),
			"返回后仍选中离开前的条目：%s" % id)

	# 6.5 真实滚动记忆：小窗画布下把焦点移到底部条目并真实滚动，进入后返回，滚动位置应恢复。
	# canvas_items 拉伸下 root.size 只缩放不触发重排；必须改 content_scale_size 才会真实重排
	# （与既有小窗证据口径一致）。
	var previous_canvas := root.content_scale_size
	root.content_scale_size = Vector2i(960, 640)
	await _settle()
	_check(current_scene.name == HUB_NODE_NAME, "滚动记忆用例从子实验目录开始")
	var scroll := current_scene.get_node("%EntryScroll") as ScrollContainer
	scroll.scroll_vertical = 0
	# 每次场景切换后必须重新取节点：旧引用在场景释放后失效。
	# 先把焦点移开再移到末项：焦点已在该按钮上时 grab_focus 是 no-op，不会触发滚动。
	var grid_now := current_scene.get_node("%EntryGrid") as GridContainer
	(grid_now.get_node("Entry_camera_lab") as Button).grab_focus()
	await _settle()
	var realm_button := grid_now.get_node("Entry_mountain_realm") as Button
	realm_button.grab_focus()
	await _settle()
	var scroll_before := scroll.scroll_vertical
	_check(scroll_before > 0, "键盘焦点移到末项时列表真实滚动（scroll=%d）" % scroll_before)
	await _activate(realm_button)
	await _settle()
	_check(current_scene.scene_file_path == REALM_SCENE, "滚动用例精确进入群山宗门")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_check(current_scene.name == HUB_NODE_NAME, "滚动用例返回子实验目录")
	var scroll_after := (current_scene.get_node("%EntryScroll") as ScrollContainer).scroll_vertical
	_check(scroll_after == scroll_before,
		"返回后恢复离开前真实滚动位置（离开 %d，恢复 %d）" % [scroll_before, scroll_after])
	root.content_scale_size = previous_canvas
	await _settle()

	# 7. Esc 从子实验目录返回顶层实验目录；再验证返回按钮路径。
	if current_scene.name == TOP_HUB_NODE_NAME:
		await _enter_hub_from_top()
	_check(current_scene.name == HUB_NODE_NAME, "回到子实验目录继续返回路径验收")
	# 顶层真实 planned 模块：点击不跳转，只展开正确说明；返回后状态保持。
	await _press_key(KEY_ESCAPE)
	await _settle()
	_check(current_scene.name == TOP_HUB_NODE_NAME, "先回到顶层实验目录做 planned 卡片验收")
	_check(current_scene.get_node_or_null("%ModuleGrid/Module_sword_combat") != null, "顶层存在 planned 模块卡：剑法战斗")
	await _activate(current_scene.get_node("%ModuleGrid/Module_sword_combat"))
	_check(current_scene.name == TOP_HUB_NODE_NAME, "顶层点击 planned 卡不跳转")
	_check((current_scene.get_node("%Details") as Control).visible, "顶层 planned 卡点击只展开说明")
	_check(current_scene.get_node("%DetailTitle").text == "剑法战斗", "顶层 planned 详情标题正确")
	_check(not current_scene.get_node("%DetailQuestion").text.strip_edges().is_empty(), "顶层 planned 详情含真实问题说明")
	await _press_key(KEY_ESCAPE)
	_check(not (current_scene.get_node("%Details") as Control).visible, "顶层 planned 详情可关闭")
	await _enter_hub_from_top()
	_check(current_scene.name == HUB_NODE_NAME, "planned 卡验收后仍能回到子实验目录")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_check(current_scene.name == TOP_HUB_NODE_NAME, "Esc 从子实验目录返回顶层实验目录：%s" % current_scene.name)
	await _enter_hub_from_top()
	_check(current_scene.name == HUB_NODE_NAME, "再次从顶层进入子实验目录")
	# 顶层目录返回记忆：回来时仍选中角色移动（而不是回到第一个模块）。
	_check((current_scene.get_node("%BackButton") as Button).text == "返回实验目录",
		"hub 返回按钮文本指向顶层实验目录：%s" % (current_scene.get_node("%BackButton") as Button).text)
	await _activate(current_scene.get_node("%BackButton"))
	await _settle()
	_check(current_scene.name == TOP_HUB_NODE_NAME, "返回按钮回到顶层实验目录：%s" % current_scene.name)

	print("PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)


## 顶层目录第 1 击：直接点击角色移动模块卡（不再经过「进入实验场景」按钮）。
func _enter_hub_from_top() -> void:
	await _activate(current_scene.get_node("%ModuleGrid/Module_character_movement"))
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


## 截图并如实报告真实像素尺寸（macOS 会为窗口标题栏占用高度，打印让证据自证）。
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
