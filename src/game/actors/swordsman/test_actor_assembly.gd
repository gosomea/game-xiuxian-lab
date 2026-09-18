extends RefCounted
## test_actor_assembly：ActorAssembly 装配适配器配对测试（S0）。
##
## 覆盖（对应装配契约与评审修正项）：
## - 四个真实子集 Move / Move+Jump / Move+Flight / all 各自只装配置请求的能力；
## - 同一配置重复 install 幂等，不产生重复节点；
## - 不同配置拒绝原地重构（要求先 uninstall），失败不破坏既有装配（all 仍 all）；
## - 配置快照：外部修改原 Resource 不会静默改变安装结果；installed_config() 返回副本；
## - 卸载只清本装配创建的能力/视觉，不碰外部能力、组件输入与速度，不调用 reset_motion()；
## - 外部先装 flight bundle 时本装配预检失败且不认领；随后卸载不动外部资源；
## - 无效配置与缺依赖（无 Visual / 已有同名能力）失败后无半装配残留。

const SCENE := "res://game/actors/swordsman/swordsman.tscn"


static func run(t) -> void:
	_test_subset_move_only(t)
	_test_subset_move_jump(t)
	_test_subset_move_flight(t)
	_test_subset_all(t)
	# 真实行为：grounded + 真实物理帧，验证子集「能做什么 / 不能做什么」，不只查节点名。
	await _test_behavior_move_only(t)
	await _test_behavior_move_jump(t)
	await _test_behavior_move_flight(t)
	await _test_behavior_all(t)
	_test_install_idempotent(t)
	_test_reconfigure_refused_preserves_existing(t)
	_test_config_snapshot_is_isolated(t)
	_test_uninstall_only_owned(t)
	_test_uninstall_preserves_borrowed_flight(t)
	_test_invalid_config_rejected(t)
	_test_failure_leaves_no_partial_state(t)
	_test_removing_assembly_cleans_up(t)
	_test_install_without_motion_component_rejected(t)
	await _test_externally_freed_owned_capability(t)


## 真实角色实例 + 默认 all 装配；先卸载默认装配，得到「组件/管理器/Visual 齐备但无能力」的宿主。
static func _fresh_actor(t) -> Swordsman:
	var actor: Swordsman = load(SCENE).instantiate()
	t.track(actor)
	var assembly := actor.get_node("ActorAssembly") as ActorAssembly
	var error := assembly.uninstall()
	t.assert_eq(error, "", "默认装配卸载成功")
	return actor


static func _assembly(actor: Swordsman) -> ActorAssembly:
	return actor.get_node("ActorAssembly") as ActorAssembly


static func _config(move: bool, jump: bool, flight: bool, visual: bool = false) -> ActorAssemblyConfig:
	var config := ActorAssemblyConfig.new()
	config.move_enabled = move
	config.jump_enabled = jump
	config.flight_enabled = flight
	config.flight_visual = visual
	return config


static func _test_subset_move_only(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var error := assembly.install(_config(true, false, false))
	t.assert_eq(error, "", "Move 子集安装成功（%s）" % error)
	t.assert_eq(str(assembly.capability_names()), str(PackedStringArray(["SwordsmanMovement"])), "Move 子集只装移动能力")
	t.assert_true(assembly.is_installed(), "Move 子集记录为已安装")
	t.assert_false(actor.get_node_or_null("Visual/FlyingSword") != null, "Move 子集不产生御剑视觉")


static func _test_subset_move_jump(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var error := assembly.install(_config(true, true, false))
	t.assert_eq(error, "", "Move+Jump 子集安装成功（%s）" % error)
	var names := assembly.capability_names()
	t.assert_true(names.has("SwordsmanMovement") and names.has("Jump"), "Move+Jump 子集含两项能力（%s）" % str(names))
	t.assert_eq(names.size(), 2, "Move+Jump 子集恰好两项（%s）" % str(names))
	t.assert_false(names.has("SwordFlight"), "Move+Jump 子集不装御剑")
	t.assert_false(actor.get_node_or_null("Visual/FlyingSword") != null, "Move+Jump 子集不产生御剑视觉")


static func _test_subset_move_flight(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var error := assembly.install(_config(true, false, true, true))
	t.assert_eq(error, "", "Move+Flight 子集安装成功（%s）" % error)
	var names := assembly.capability_names()
	t.assert_true(names.has("SwordsmanMovement") and names.has("SwordFlight"), "Move+Flight 子集含移动与御剑（%s）" % str(names))
	t.assert_eq(names.size(), 2, "Move+Flight 子集恰好两项（%s）" % str(names))
	t.assert_false(names.has("Jump"), "Move+Flight 子集不装跳跃")
	# 行为+视觉一起装：剑存在且初始隐藏，F 开启后可见。
	var sword := actor.get_node_or_null("Visual/FlyingSword") as Node3D
	t.assert_true(sword != null and not sword.visible, "Move+Flight 子集装好御剑视觉且初始隐藏")
	# 走真实 actor 帧：边沿在帧末由 actor 清零；手动只 tick 管理器会让边沿残留并被误判为关闭。
	actor.motion().on_floor = true
	actor.press_flight_toggle()
	actor.call("_physics_process", 0.016)
	t.assert_true(actor.motion().flight_active, "Move+Flight 子集御剑可激活")
	t.assert_true(sword != null and sword.visible, "御剑激活后剑可见（actor 统一显隐）")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 1, "御剑登记一条 sword_flight_block")


static func _test_subset_all(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var error := assembly.install(_config(true, true, true, true))
	t.assert_eq(error, "", "all 子集安装成功（%s）" % error)
	var names := assembly.capability_names()
	names.sort()
	t.assert_eq(str(names), str(PackedStringArray(["Jump", "SwordFlight", "SwordsmanMovement"])), "all 子集三能力齐备")
	t.assert_true(actor.get_node_or_null("Visual/FlyingSword") != null, "all 子集同时装好御剑视觉")


static func _test_install_idempotent(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var config := _config(true, true, true, true)
	t.assert_eq(assembly.install(config), "", "首次 all 安装成功")
	var manager := actor.get_node("CapabilityManager")
	var count := manager.get_child_count()
	t.assert_eq(assembly.install(config), "", "重复安装同一配置幂等返回成功")
	t.assert_eq(manager.get_child_count(), count, "重复安装不产生重复能力节点（%d）" % count)
	t.assert_eq(assembly.capability_names().size(), 3, "重复安装后仍恰好三能力")


static func _test_reconfigure_refused_preserves_existing(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var all_config := _config(true, true, true, true)
	t.assert_eq(assembly.install(all_config), "", "先安装 all")
	var other := _config(true, false, false)
	var error := assembly.install(other)
	t.assert_true(error != "", "不同配置被拒绝（要求先 uninstall）：%s" % error)
	# 关键：失败不得破坏既有装配。
	var names := assembly.capability_names()
	names.sort()
	t.assert_eq(str(names), str(PackedStringArray(["Jump", "SwordFlight", "SwordsmanMovement"])), "拒绝重构后 all 仍 all")
	t.assert_true(assembly.is_installed(), "拒绝重构后仍记录为已安装")
	t.assert_true(actor.get_node_or_null("Visual/FlyingSword") != null, "拒绝重构后御剑视觉仍在")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "拒绝重构不产生 tag 残留")


static func _test_config_snapshot_is_isolated(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var config := _config(true, true, true, true)
	t.assert_eq(assembly.install(config), "", "按 all 配置安装")
	# 外部篡改原 Resource：不得静默改变安装结果。
	config.jump_enabled = false
	var names := assembly.capability_names()
	t.assert_true(names.has("Jump"), "外部修改原 config 后装配不变（仍含 Jump）")
	var stored := assembly.installed_config()
	t.assert_true(stored != null and stored.jump_enabled, "installed_config() 返回安装时快照（jump=true）")
	# 返回值是副本：修改它不影响内部状态。
	stored.jump_enabled = false
	var again := assembly.installed_config()
	t.assert_true(again != null and again.jump_enabled, "修改 installed_config() 返回值不影响内部状态")
	# 被篡改的原对象再 install：与快照不同，必须显式拒绝而不是静默改装配。
	var error := assembly.install(config)
	t.assert_true(error != "", "再安装被篡改的 config 被显式拒绝：%s" % error)
	t.assert_true(assembly.capability_names().has("Jump"), "拒绝后装配仍未改变")


## 真实物理宿主：一块 StaticBody3D 地板 + 真实 actor，按 config 装配子集，并等到真正着地。
## 只走物理帧推进；返回已着地的 actor。装不上/没接住都断言失败。
static func _grounded_actor(t, config: ActorAssemblyConfig) -> Swordsman:
	var floor_body := StaticBody3D.new()
	floor_body.name = "ProbeFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	t.track(floor_body)
	var actor: Swordsman = load(SCENE).instantiate()
	t.track(actor)
	actor.global_position = Vector3(0.0, 0.05, 0.0)
	var assembly := actor.get_node("ActorAssembly") as ActorAssembly
	t.assert_eq(assembly.uninstall(), "", "行为用例：先卸默认装配")
	t.assert_eq(assembly.install(config), "", "行为用例：子集装配成功")
	actor.set_camera_ground_basis(Vector3.RIGHT, Vector3.FORWARD)
	var tree: SceneTree = t.root().get_tree()
	for index in range(30):
		await tree.physics_frame
		if actor.motion().on_floor:
			break
	t.assert_true(actor.motion().on_floor, "真实物理地面接住角色（y=%.3f）" % actor.global_position.y)
	return actor


## 推进 frames 个真实物理帧，返回期间竖直速度绝对值峰值（区分「有跳跃/起飞」与「静默」）。
static func _max_vertical_speed(t, actor: Swordsman, frames: int) -> float:
	var peak := 0.0
	var tree: SceneTree = t.root().get_tree()
	for index in range(frames):
		await tree.physics_frame
		peak = maxf(peak, absf(actor.motion().actual_velocity.y))
	return peak


static func _await_landing(t, actor: Swordsman, frames: int = 150) -> bool:
	var tree: SceneTree = t.root().get_tree()
	for index in range(frames):
		await tree.physics_frame
		if actor.motion().on_floor:
			return true
	return false


## Move-only：真实移动可用；空格不跳、F 不飞（未启用能力静默）。
static func _test_behavior_move_only(t) -> void:
	t.begin_case()
	var actor := await _grounded_actor(t, _config(true, false, false))
	var motion := actor.motion()
	var start_y := actor.global_position.y
	var start_x := actor.global_position.x
	actor.set_move_input(Vector2(1.0, 0.0))
	var tree: SceneTree = t.root().get_tree()
	for index in range(12):
		await tree.physics_frame
	t.assert_true(actor.global_position.x - start_x > 0.2, "Move-only 产生真实水平位移（%.2f m）" % (actor.global_position.x - start_x))
	t.assert_true(absf(motion.actual_velocity.x - motion.move_speed) < 0.3,
		"Move-only 水平速度达到 move_speed（%.2f m/s）" % motion.actual_velocity.x)
	actor.set_move_input(Vector2.ZERO)
	await tree.physics_frame
	# 未装 Jump：按空格不得产生任何竖直速度（装了 Jump 会到 ~jump_speed）。
	actor.press_jump()
	var jump_peak := await _max_vertical_speed(t, actor, 8)
	t.assert_true(jump_peak < 0.5, "Move-only 空格无竖直速度（峰值 %.2f m/s，jump_speed=%.1f）" % [jump_peak, motion.jump_speed])
	t.assert_true(actor.global_position.y - start_y < 0.05, "Move-only 空格不跳起（Δy=%.3f m）" % (actor.global_position.y - start_y))
	# 未装 Flight：按 F 不得进入御剑、不得起飞。
	actor.press_flight_toggle()
	var flight_peak := await _max_vertical_speed(t, actor, 8)
	t.assert_false(motion.flight_active, "Move-only 按 F 不进入御剑")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "Move-only 无御剑阻塞登记")
	t.assert_true(flight_peak < 0.5, "Move-only 按 F 不起飞（竖直峰值 %.2f m/s）" % flight_peak)


## Move+Jump：空格真实跳起并回落着地；F 仍静默不起飞。
static func _test_behavior_move_jump(t) -> void:
	t.begin_case()
	var actor := await _grounded_actor(t, _config(true, true, false))
	var motion := actor.motion()
	var start_y := actor.global_position.y
	actor.press_jump()
	var jump_peak := await _max_vertical_speed(t, actor, 6)
	var apex := actor.global_position.y
	var tree: SceneTree = t.root().get_tree()
	for index in range(60):
		await tree.physics_frame
		apex = maxf(apex, actor.global_position.y)
	t.assert_true(jump_peak > motion.jump_speed * 0.7, "Move+Jump 空格产生跳跃速度（峰值 %.2f m/s）" % jump_peak)
	t.assert_true(apex - start_y > 0.5, "Move+Jump 产生真实跳起高度（Δy=%.2f m）" % (apex - start_y))
	t.assert_true(await _await_landing(t, actor), "Move+Jump 跳起后重新着地")
	# 未装 Flight：F 不得起飞（着地状态下按 F）。
	actor.press_flight_toggle()
	var flight_peak := await _max_vertical_speed(t, actor, 10)
	t.assert_false(motion.flight_active, "Move+Jump 按 F 不进入御剑")
	t.assert_true(flight_peak < 0.5, "Move+Jump 按 F 不起飞（竖直峰值 %.2f m/s）" % flight_peak)


## Move+Flight：地面空格不得产生 Jump 冲量（Jump 未装）；F 起飞、剑可见、阻塞登记。
static func _test_behavior_move_flight(t) -> void:
	t.begin_case()
	var actor := await _grounded_actor(t, _config(true, false, true, true))
	var motion := actor.motion()
	var start_y := actor.global_position.y
	# Jump 未装：地面按空格不得产生跳跃速度。
	actor.press_jump()
	var space_peak := await _max_vertical_speed(t, actor, 8)
	t.assert_true(space_peak < 0.5, "Move+Flight 地面空格无跳跃冲量（竖直峰值 %.2f m/s）" % space_peak)
	t.assert_true(actor.global_position.y - start_y < 0.05, "Move+Flight 地面空格不跳起（Δy=%.3f m）" % (actor.global_position.y - start_y))
	# Flight 已装：F 起飞并点亮飞剑；空格此时是升降输入而不是跳跃。
	actor.press_flight_toggle()
	var takeoff_peak := await _max_vertical_speed(t, actor, 12)
	t.assert_true(motion.flight_active, "Move+Flight 按 F 进入御剑")
	t.assert_true(takeoff_peak > 1.0, "Move+Flight 御剑产生真实上升（竖直峰值 %.2f m/s）" % takeoff_peak)
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 1, "Move+Flight 御剑登记一条阻塞")
	var sword := actor.get_node_or_null("Visual/FlyingSword") as Node3D
	t.assert_true(sword != null and sword.visible, "Move+Flight 御剑期间飞剑可见")
	actor.press_flight_toggle()


## all：跳跃与飞行都真实可用；飞行期间地面移动被阻塞（速度由 flight_speed 决定，而非 move_speed）。
static func _test_behavior_all(t) -> void:
	t.begin_case()
	var actor := await _grounded_actor(t, _config(true, true, true, true))
	var motion := actor.motion()
	var start_y := actor.global_position.y
	actor.press_jump()
	var jump_peak := await _max_vertical_speed(t, actor, 6)
	t.assert_true(jump_peak > motion.jump_speed * 0.7, "all 空格真实跳跃（峰值 %.2f m/s）" % jump_peak)
	t.assert_true(await _await_landing(t, actor), "all 跳起后重新着地")
	# 飞行阻塞地面移动：飞行中水平速度应是 flight_speed 而不是 move_speed。
	actor.press_flight_toggle()
	var tree: SceneTree = t.root().get_tree()
	for index in range(6):
		await tree.physics_frame
	t.assert_true(motion.flight_active, "all 按 F 进入御剑")
	actor.set_move_input(Vector2(1.0, 0.0))
	for index in range(14):
		await tree.physics_frame
	var horizontal := Vector2(motion.actual_velocity.x, motion.actual_velocity.z).length()
	t.assert_true(absf(horizontal - motion.flight_speed) < 0.6,
		"all 御剑期间水平速度由 flight_speed 接管（%.2f m/s，move_speed=%.1f）" % [horizontal, motion.move_speed])
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 1, "all 御剑期间阻塞登记存在")
	actor.set_move_input(Vector2.ZERO)
	actor.press_flight_toggle()
	t.assert_true(actor.global_position.y - start_y > 0.0, "all 御剑确实改变了高度（Δy=%.2f m）" % (actor.global_position.y - start_y))


static func _test_uninstall_only_owned(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	t.assert_eq(assembly.install(_config(true, true, true, true)), "", "安装 all")
	var motion := actor.motion()
	# 卸载不得触碰组件输入与速度（借用原则，禁用 reset_motion 作为卸载手段）。
	motion.actual_velocity = Vector3(3.0, -1.0, 2.0)
	motion.move_input = Vector2(0.5, -0.5)
	motion.vertical_input = 1.0
	t.assert_eq(assembly.uninstall(), "", "卸载成功")
	t.assert_eq(actor.motion().actual_velocity, Vector3(3.0, -1.0, 2.0), "卸载不改写宿主速度")
	t.assert_eq(actor.motion().move_input, Vector2(0.5, -0.5), "卸载不清空移动输入")
	t.assert_eq(actor.motion().vertical_input, 1.0, "卸载不清空升降输入")
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "卸载移除本装配的全部能力")
	t.assert_false(actor.get_node_or_null("Visual/FlyingSword") != null, "卸载移除本装配的御剑视觉")
	t.assert_true(actor.flight_visual_node() == null, "卸载解除御剑视觉绑定")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "卸载后无 tag 残留")
	t.assert_false(assembly.is_installed(), "卸载后状态为未安装")
	t.assert_eq(assembly.uninstall(), "", "重复卸载幂等成功")


static func _test_uninstall_preserves_borrowed_flight(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	# 外部先装 flight bundle（借用场景）。
	var external := FlightBundle.new()
	t.assert_eq(external.install(actor, false), "", "外部 bundle 先安装成功")
	var external_cap := external.installed_capability()
	t.assert_true(external_cap != null, "外部 bundle 创建了能力节点")
	# 本装配再装 all：预检发现同名能力，拒绝且不认领。
	var error := assembly.install(_config(true, true, true, true))
	t.assert_true(error != "", "外部已有 SwordFlight 时本装配预检失败：%s" % error)
	t.assert_false(assembly.is_installed(), "预检失败后本装配未记录安装")
	t.assert_true(is_instance_valid(external_cap), "预检失败不删除外部能力")
	# 本装配卸载：不得误删外部资源。
	t.assert_eq(assembly.uninstall(), "", "本装配卸载成功")
	t.assert_true(is_instance_valid(external.installed_capability()), "本装配卸载后外部能力仍在")
	t.assert_eq(external.uninstall(), "", "外部 bundle 自行卸载成功")


static func _test_invalid_config_rejected(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var none := _config(false, false, false)
	t.assert_true(assembly.install(none) != "", "三项全关的配置被拒绝")
	t.assert_true(none.validate() != "", "配置自检也报告非法")
	var visual_without_flight := _config(true, false, false, true)
	t.assert_true(assembly.install(visual_without_flight) != "", "flight_visual=true 但 flight=false 被拒绝")
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "非法配置不产生任何能力")
	t.assert_false(assembly.is_installed(), "非法配置后状态仍为未安装")


static func _test_failure_leaves_no_partial_state(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	# 缺依赖：宿主没有 Visual 节点时请求装视觉，预检失败且不得留下半装配。
	var visual := actor.get_node("Visual")
	actor.remove_child(visual)
	visual.queue_free()
	var error := assembly.install(_config(true, true, true, true))
	t.assert_true(error != "", "缺少 Visual 时安装失败：%s" % error)
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "失败后无半装配能力残留")
	t.assert_false(assembly.is_installed(), "失败后状态仍为未安装")
	# 同名冲突：外部已有 SwordsmanMovement 时拒绝，且不认领、不删除。
	var manager := actor.get_node("CapabilityManager") as CapabilityManager
	var foreign := SwordsmanMovement.new()
	foreign.name = "SwordsmanMovement"
	manager.add_child(foreign)
	var conflict_error := assembly.install(_config(true, true, true, true))
	t.assert_true(conflict_error != "", "宿主已有同名能力时安装被拒绝：%s" % conflict_error)
	t.assert_true(is_instance_valid(foreign) and foreign.get_parent() == manager, "外部能力未被删除或认领")
	t.assert_eq(manager.get_child_count(), 1, "冲突失败后管理器仍只有外部那一个能力")


## 装配根被移除（host 仍存活）时不得留下孤儿能力/视觉：_exit_tree 负责清理。
static func _test_removing_assembly_cleans_up(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	t.assert_eq(assembly.install(_config(true, true, true, true)), "", "安装 all")
	actor.motion().on_floor = true
	actor.press_flight_toggle()
	actor.call("_physics_process", 0.016)
	t.assert_true(actor.motion().flight_active, "移除前御剑已开")
	# 关键：把装配节点本身移出树，宿主仍存活。
	actor.remove_child(assembly)
	assembly.queue_free()
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "装配根移除后不留孤儿能力")
	t.assert_false(actor.get_node_or_null("Visual/FlyingSword") != null, "装配根移除后不留御剑视觉")
	t.assert_true(actor.flight_visual_node() == null, "装配根移除后绑定已解除")
	t.assert_false(actor.motion().flight_active, "装配根移除后 flight_active 已清")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "装配根移除后无 tag 残留")
	t.assert_false(assembly.is_installed(), "装配根移除后记录为未安装")


## 集成场景可能自行移除本装配拥有的能力（mountain_traversal 的 Jump/Movement removal 批）。
## 此时 _owned 里留着已释放句柄；卸载必须不在 typed 参数校验处抛 freed-instance 错误，
## 且不得因此漏清其它 owned 能力与 tag。回归点：真实先删 move/jump，再 assembly.uninstall() 与 host 离树。
static func _test_externally_freed_owned_capability(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	t.assert_eq(assembly.install(_config(true, true, true, true)), "", "安装 all")
	var manager := actor.get_node("CapabilityManager") as CapabilityManager
	var motion := actor.motion()
	motion.on_floor = true
	actor.press_flight_toggle()
	actor.call("_physics_process", 0.016)
	t.assert_true(motion.flight_active, "删除前御剑已开（用于验证 tag 回归）")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 1, "删除前有阻塞登记")
	# 真实复刻集成方写法：remove_child + queue_free，绕开 assembly 的句柄。
	for capability_name in ["Jump", "SwordsmanMovement"]:
		var owned := manager.get_node_or_null(capability_name)
		t.assert_true(owned != null, "删除前 %s 存在" % capability_name)
		manager.remove_child(owned)
		owned.queue_free()
	# 让 queue_free 真正生效，制造 previously-freed 句柄。
	var tree: SceneTree = t.root().get_tree()
	await tree.process_frame
	await tree.physics_frame
	# 关键断言：卸载不得产生 SCRIPT ERROR，也不得漏清剩余 owned（flight）与 tag。
	t.assert_eq(assembly.uninstall(), "", "owned 能力被外部删除后卸载仍返回成功（无 freed-instance 错误）")
	t.assert_eq(manager.get_child_count(), 0, "卸载清空剩余 owned 能力（flight）")
	t.assert_false(actor.get_node_or_null("Visual/FlyingSword") != null, "卸载移除御剑视觉")
	t.assert_false(motion.flight_active, "卸载后 flight_active 已清")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "卸载后 sword_flight_block 无残留")
	t.assert_eq(assembly.uninstall(), "", "重复卸载仍幂等成功")
	# 第二种触发路径：owned 已被外部删除后直接让装配节点离树（host 仍存活）。
	t.begin_case()
	var actor2 := _fresh_actor(t)
	var assembly2 := _assembly(actor2)
	t.assert_eq(assembly2.install(_config(true, true, false)), "", "再装 Move+Jump")
	var manager2 := actor2.get_node("CapabilityManager") as CapabilityManager
	var jump2 := manager2.get_node_or_null("Jump")
	t.assert_true(jump2 != null, "离树路径：Jump 存在")
	manager2.remove_child(jump2)
	jump2.queue_free()
	var tree2: SceneTree = t.root().get_tree()
	await tree2.process_frame
	actor2.remove_child(assembly2)
	assembly2.queue_free()
	await tree2.process_frame
	t.assert_eq(manager2.get_child_count(), 0, "装配根离树后不留孤儿能力（含已失效句柄场景）")


## 缺共享组件时必须显式失败，不得静默装出一个没有行为的空能力。
static func _test_install_without_motion_component_rejected(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var assembly := _assembly(actor)
	var component := actor.get_node("SwordsmanMotionComponent")
	actor.remove_child(component)
	component.queue_free()
	var error := assembly.install(_config(true, true, true, false))
	t.assert_true(error != "", "缺少 SwordsmanMotionComponent 时安装失败：%s" % error)
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "缺组件失败后无半装配残留")
	t.assert_false(assembly.is_installed(), "缺组件失败后状态仍为未安装")
