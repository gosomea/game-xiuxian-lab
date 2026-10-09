extends RefCounted

const ACTOR := preload("res://game/actors/swordsman/swordsman.tscn")
const RIG := preload("res://game/systems/camera_rig/camera_rig_sheet.tscn")
const WORKBENCH := preload("res://levels/experiments/character_movement/movement_workbench.tscn")


static func run(t) -> void:
	_test_schema_and_validation(t)
	_test_live_owned_lifecycle(t)
	_test_adjustable_motion(t)
	_test_camera_and_sparse_parameters(t)
	_test_persistence(t)
	await _test_scene_inheritance(t)
	await _test_workbench_controls(t)


static func _actor(t) -> Swordsman:
	var actor := ACTOR.instantiate() as Swordsman
	t.track(actor)
	actor.set_physics_process(false)
	return actor


static func _test_schema_and_validation(t) -> void:
	t.begin_case()
	var groups := LabParameterSchema.component_groups()
	t.assert_true(groups.has("SwordsmanMotionComponent"), "发现运动组件导出参数")
	t.assert_true(groups.has("SwordCastComponent"), "发现剑法组件导出参数")
	t.assert_true(groups.has("SwordTargetComponent"), "发现目标组件导出参数")
	t.assert_false(groups.has("VitalsComponent"), "模板测试夹具不进入参数工作台")
	t.assert_true(LabParameterSchema.find(groups["SwordsmanMotionComponent"], "move_input").is_empty(),
		"瞬态输入不是可持久化参数")
	t.assert_false(LabDefaults.set_component_value("SwordsmanMotionComponent", "jump_pressed", true).is_empty(),
		"拒绝修改瞬态输入字段")
	t.assert_false(LabDefaults.set_component_value("SwordsmanMotionComponent", "gravity", 0.0).is_empty(),
		"拒绝使重力公式失效的零值")
	t.assert_false(LabDefaults.set_component_value("SwordCastComponent", "array_spawn_interval", 0.0).is_empty(),
		"拒绝剑阵零间隔")
	t.assert_false(LabDefaults.set_camera_value("start_mode", "missing").is_empty(), "拒绝未知镜头模式")
	t.assert_false(LabDefaults.set_camera_value("size_min", 60.0).is_empty(), "拒绝镜头缩放上下限倒置")
	t.assert_false(LabDefaults.set_ability("missing", false).is_empty(), "拒绝未知行为开关")
	t.assert_false(LabDefaults.is_dirty(), "非法输入不改动设置")
	t.assert_eq(LabDefaults.set_component_value("SwordCastComponent", "sword_rest_offset", [1.0, 2.0, 3.0]),
		"", "三维参数可以持久化")
	var component := SwordCastComponent.new()
	t.track(component)
	LabDefaults.apply_component(component)
	t.assert_eq(component.sword_rest_offset, Vector3(1, 2, 3), "JSON 坐标还原成真实 Vector3")


static func _test_live_owned_lifecycle(t) -> void:
	t.begin_case()
	var actor := _actor(t)
	var assembly := actor.get_node("ActorAssembly") as ActorAssembly
	var manager := actor.capability_manager()
	var flight := manager.get_node("SwordFlight")
	var movement := manager.get_node("SwordsmanMovement")
	actor.press_flight_toggle()
	actor.call("_physics_process", 0.016)
	t.assert_true(actor.motion().flight_active, "单项卸载前已御剑")
	t.assert_eq(LabDefaults.set_ability("jump", false), "", "全局撤销跳跃")
	t.assert_true(manager.get_node_or_null("Jump") == null, "跳跃节点实际移出调度器")
	t.assert_eq(manager.get_node("SwordFlight"), flight, "撤销跳跃保留原御剑实例")
	t.assert_eq(manager.get_node("SwordsmanMovement"), movement, "撤销跳跃保留原移动实例")
	t.assert_true(actor.motion().flight_active, "撤销跳跃不结束御剑")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 1, "御剑阻塞仍由原实例持有")
	t.assert_eq(LabDefaults.set_ability("jump", true), "", "运行中恢复跳跃")
	t.assert_true(manager.get_node_or_null("Jump") != null, "跳跃能力实际恢复")
	t.assert_eq(manager.get_node("SwordFlight"), flight, "恢复跳跃仍不重建御剑")
	t.assert_eq(LabDefaults.set_ability("flight", false), "", "运行中卸载御剑")
	t.assert_false(actor.motion().flight_active, "卸载御剑清飞行状态")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "卸载御剑清自身阻塞")
	t.assert_true(actor.flight_visual_node() == null, "卸载御剑清表现绑定")
	t.assert_eq(assembly.set_capability_enabled("move", false), "", "卸载平面移动")
	t.assert_eq(assembly.set_capability_enabled("jump", false), "", "允许运行中全部行为卸下")
	t.assert_eq(manager.get_child_count(), 0, "空装配没有残留行为")
	actor.velocity = Vector3(0, 2, 0)
	actor.call("_physics_process", 0.1)
	t.assert_true(actor.velocity.y < 2.0, "无行为时基础重力继续执行")
	t.assert_eq(assembly.set_capability_enabled("jump", true), "", "空装配仍可恢复单项")
	t.assert_eq(manager.get_child_count(), 1, "恢复跳跃没有捎带其他能力")


static func _test_adjustable_motion(t) -> void:
	t.begin_case()
	var actor := _actor(t)
	var motion := actor.motion()
	actor.set_move_input(Vector2.RIGHT)
	actor.set_sprint_input(true)
	motion.on_floor = true
	LabDefaults.set_component_value("SwordsmanMotionComponent", "sprint_speed", 7.0)
	actor.capability_manager().tick(0.016)
	t.assert_true(absf(motion.desired_horizontal.length() - 7.0) < 0.001, "疾跑参数改变真实速度意图")
	LabDefaults.set_component_value("SwordsmanMotionComponent", "sprint_enabled", false)
	actor.capability_manager().tick(0.016)
	t.assert_true(absf(motion.desired_horizontal.length() - 2.0) < 0.001, "取消疾跑后 Shift 使用步行速度")
	LabDefaults.set_component_value("SwordsmanMotionComponent", "air_move_speed", 3.5)
	motion.on_floor = false
	actor.capability_manager().tick(0.016)
	t.assert_true(absf(motion.desired_horizontal.length() - 3.5) < 0.001, "空中水平速度可独立于步行与疾跑")
	LabDefaults.set_component_value("SwordsmanMotionComponent", "air_move_speed", 0.0)
	actor.capability_manager().tick(0.016)
	t.assert_true(absf(motion.desired_horizontal.length() - 2.0) < 0.001, "空中零值恢复地面速度规则")
	LabDefaults.set_ability("jump", false)
	var foreign := (load("res://game/abilities/jump/jump.gd") as Script).new() as Capability
	foreign.name = "Jump"
	actor.capability_manager().add_child(foreign)
	t.assert_false(LabDefaults.set_ability("jump", true).is_empty(), "外部能力冲突如实返回应用错误")
	t.assert_eq(actor.capability_manager().get_node("Jump"), foreign, "冲突不认领或删除外部能力")
	t.assert_false(LabDefaults.save().is_empty(), "应用失败不得误报保存成功")
	actor.capability_manager().remove_child(foreign)
	foreign.free()
	t.assert_eq(LabDefaults.set_ability("jump", true), "", "解决冲突后可以重新应用")


static func _test_camera_and_sparse_parameters(t) -> void:
	t.begin_case()
	var actor := _actor(t)
	var camera := Camera3D.new()
	t.track(camera)
	var rig := RIG.instantiate() as CameraRig
	t.track(rig)
	rig.set_physics_process(false)
	var base := CameraRigConfig.new()
	base.start_mode = "orbit"
	base.mode_choices = PackedStringArray(LabParameterSchema.MODE_CHOICES)
	base.focus_clamp_min = Vector3(-23, 0, -15)
	rig.bind(camera, actor, base)
	var inactive := RIG.instantiate() as CameraRig
	inactive.active = false
	t.track(inactive)
	inactive.set_physics_process(false)
	inactive.bind(camera, actor, base)
	rig.component().yaw_degrees = 17.0
	t.assert_eq(LabDefaults.set_component_value("SwordsmanMotionComponent", "sprint_speed", 7.5), "", "实时调整疾跑速度")
	t.assert_eq(actor.motion().sprint_speed, 7.5, "已存在角色立即取得新参数")
	t.assert_eq(rig.component().yaw_degrees, 17.0, "改角色参数不重置当前镜头")
	t.assert_eq(LabDefaults.set_camera_value("start_mode", "overview"), "", "全局选择全景模式")
	rig.advance(0.016)
	t.assert_eq(rig.component().mode_id, "overview", "运行中镜头切换生效")
	t.assert_eq(rig.component().focus_clamp_min, base.focus_clamp_min, "稀疏覆盖保留场景地理边界")
	t.assert_eq(LabDefaults.set_ability("camera", false), "", "卸载镜头行为")
	t.assert_false(rig.is_active(), "卸载后镜头停止执行")
	t.assert_eq(rig.get_node("CapabilityManager").get_child_count(), 0, "镜头模式实际移出调度器")
	t.assert_false(rig.is_captured(), "卸载后无鼠标捕获")
	t.assert_eq(LabDefaults.set_ability("camera", true), "", "恢复镜头行为")
	t.assert_eq(rig.get_node("CapabilityManager").get_child_count(), 4, "恢复原四种镜头能力")
	t.assert_false(inactive.is_active(), "全局恢复不抢占另一个 rig 的相机写入权")
	t.assert_eq(LabDefaults.set_camera_value("mode_choices", ["orbit"]), "", "镜头子集可以只留环绕")
	t.assert_eq(LabDefaults.snapshot()["camera"]["start_mode"], "orbit", "移除默认模式后选择剩余模式")
	t.assert_eq(LabDefaults.set_camera_value("start_mode", "quarter_turn"), "", "替换默认模式自动纳入可用项")
	t.assert_true(LabDefaults.snapshot()["camera"]["mode_choices"].has("quarter_turn"), "新默认模式可由按键选择")
	LabDefaults.restore_original()
	t.assert_eq(actor.motion().sprint_speed, 4.2, "恢复原始运动参数")
	rig.advance(0.016)
	t.assert_eq(rig.component().mode_id, "orbit", "恢复该场景原始镜头模式")


static func _test_persistence(t) -> void:
	t.begin_case()
	var path := LabDefaults.storage_path
	t.assert_false(path == LabDefaults.DEFAULT_PATH, "测试不写真实用户默认")
	t.assert_eq(LabDefaults.set_component_value("SwordsmanMotionComponent", "move_speed", 3.25), "", "创建速度覆盖")
	t.assert_eq(LabDefaults.set_component_value("SwordsmanMotionComponent", "jump_speed", 8.0), "", "创建起跳覆盖")
	t.assert_eq(LabDefaults.set_ability("jump", false), "", "创建跳跃卸载默认")
	t.assert_eq(LabDefaults.set_camera_value("start_mode", "overview"), "", "创建镜头默认")
	t.assert_true(LabDefaults.is_dirty(), "未保存设置有明确状态")
	t.assert_eq(LabDefaults.save(), "", "原子保存用户默认")
	t.assert_false(LabDefaults.is_dirty(), "保存后没有未保存修改")
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tests/workbench_settings_reload_probe.gd",
		"--", "--settings-path=" + path], output, true)
	t.assert_eq(result, 0, "新 Godot 进程继承速度、能力与镜头默认：%s" % str(output))
	LabDefaults.configure_storage(path)
	var actor := _actor(t)
	t.assert_eq(actor.motion().move_speed, 3.25, "重新加载设置后新角色继承速度")
	t.assert_true(actor.capability_manager().get_node_or_null("Jump") == null, "新角色继承跳跃卸载")
	LabDefaults.set_component_value("SwordsmanMotionComponent", "move_speed", 9.0)
	LabDefaults.revert()
	t.assert_eq(actor.motion().move_speed, 3.25, "撤销未保存恢复已保存默认")
	LabDefaults.restore_original()
	t.assert_eq(actor.motion().move_speed, 2.0, "恢复原始默认保留本场原始数值")
	t.assert_true(actor.capability_manager().get_node_or_null("Jump") != null, "恢复原始默认重新挂载跳跃")
	t.assert_eq(LabDefaults.save(), "", "再次保存覆盖已有设置文件")
	DirAccess.remove_absolute(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	LabDefaults.configure_storage(path)
	LabDefaults.ensure_loaded()
	t.assert_false(LabDefaults.load_error.is_empty(), "损坏设置有明确错误")
	t.assert_true(LabDefaults.snapshot()["components"].is_empty(), "损坏设置不会污染组件")
	DirAccess.remove_absolute(path)
	LabDefaults.configure_storage("user://missing_workbench_directory_%s/settings.json" % OS.get_process_id())
	LabDefaults.set_component_value("SwordsmanMotionComponent", "move_speed", 3.0)
	t.assert_false(LabDefaults.save().is_empty(), "写入失败如实返回错误")
	t.assert_true(LabDefaults.is_dirty(), "写入失败不会误报已保存")


static func _test_scene_inheritance(t) -> void:
	t.begin_case()
	LabDefaults.set_component_value("SwordsmanMotionComponent", "sprint_speed", 6.5)
	LabDefaults.set_component_value("SwordCastComponent", "qi_speed", 25.0)
	LabDefaults.set_component_value("SwordTargetComponent", "radius", 1.25)
	LabDefaults.set_camera_value("start_mode", "overview")
	for path in ["res://levels/experiments/character_movement/movement_garden.tscn",
		"res://levels/experiments/character_movement/west_lake_sunset.tscn",
		"res://levels/experiments/sword_combat/sword_workbench.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		t.track(scene)
		await t.root().get_tree().physics_frame
		await t.root().get_tree().process_frame
		var actor := scene.find_child("Swordsman", true, false) as Swordsman
		var rig := scene.find_child("CameraRig", true, false) as CameraRig
		t.assert_eq(actor.motion().sprint_speed, 6.5, "%s 继承全局疾跑" % path.get_file())
		t.assert_eq(rig.component().mode_id, "overview", "%s 继承全局默认镜头" % path.get_file())
		if path.ends_with("sword_workbench.tscn"):
			t.assert_eq(actor.get_node("SwordCastComponent").qi_speed, 25.0, "剑法装配读取全局组件参数")
			t.assert_eq(scene.find_child("SwordTargetComponent", true, false).radius, 1.25,
				"木桩读取全局命中参数")
		t.root().remove_child(scene)
		scene.queue_free()
		await t.root().get_tree().process_frame


static func _test_workbench_controls(t) -> void:
	t.begin_case()
	var scene := WORKBENCH.instantiate()
	t.track(scene)
	await t.root().get_tree().physics_frame
	await t.root().get_tree().process_frame
	var actor := scene.actor() as Swordsman
	var speed := scene.editor("SwordsmanMotionComponent", "sprint_speed") as SpinBox
	t.assert_eq((scene.editor("SwordsmanMotionComponent", "gravity") as SpinBox).value,
		18.0, "参数输入框不因步长舍入显示错误默认")
	t.assert_true(speed != null, "综合工作台有真实疾跑数值控件")
	speed.value = 5.5
	t.assert_eq(actor.motion().sprint_speed, 5.5, "数值控件连到真实组件与全局设置")
	var jump := scene.editor("", "jump") as CheckButton
	jump.button_pressed = false
	t.assert_true(actor.capability_manager().get_node_or_null("Jump") == null, "卸载按钮连到真实装配器")
	jump.button_pressed = true
	t.assert_true(actor.capability_manager().get_node_or_null("Jump") != null, "恢复按钮重新装跳跃")
	scene.save_defaults()
	t.assert_false(LabDefaults.is_dirty(), "工作台保存动作落到持久化设施")
	var tabs := scene.get("_tabs") as TabContainer
	tabs.current_tab = 1
	await t.root().get_tree().process_frame
	await t.root().get_tree().process_frame
	t.assert_true(tabs.get_global_rect().end.x <= 421, "三维坐标编辑器不撑宽镜头侧栏")
	DirAccess.remove_absolute(LabDefaults.storage_path)
