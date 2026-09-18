extends RefCounted
## test_flight_bundle：FlightBundle 装配包配对测试（S0）。
##
## 覆盖（对应装配契约与评审修正项）：
## - 行为+视觉一起安装：剑节点、绑定、flight_active 显隐联动；
## - 卸载按 own 句柄清理：capability 与其 _exit_tree 清 tag/flight_active、视觉解绑释放；
## - 不借用/不认领：外部已有同名能力或同名视觉时拒绝，不改名、不覆盖绑定、不删除；
## - 本次新增失败只回滚本次新增：先 headless 安装（无视觉）后再请求视觉被拒绝，原能力保留；
## - 配置不可变：重复同配置幂等；不同配置要求先 uninstall；
## - 重复卸载幂等，不触碰组件输入与速度。

const SCENE := "res://game/actors/swordsman/swordsman.tscn"


static func run(t) -> void:
	_test_install_pairs_behavior_and_visual(t)
	_test_uninstall_clears_state_and_tag(t)
	_test_install_without_visual_is_allowed(t)
	_test_reinstall_same_config_idempotent(t)
	_test_config_change_requires_uninstall(t)
	_test_refuses_foreign_capability(t)
	_test_refuses_foreign_visual_without_claiming(t)
	_test_refuses_when_visual_already_bound(t)
	_test_missing_visual_root_fails_cleanly(t)
	_test_missing_manager_rejected(t)
	_test_second_host_rejected_while_installed(t)
	_test_uninstall_after_host_freed(t)
	_test_missing_motion_component_rejected(t)
	_test_duplicate_manager_rejected(t)


## 真实角色，但卸掉默认装配，得到空管理器宿主。
static func _fresh_actor(t) -> Swordsman:
	var actor: Swordsman = load(SCENE).instantiate()
	t.track(actor)
	var assembly := actor.get_node("ActorAssembly") as ActorAssembly
	t.assert_eq(assembly.uninstall(), "", "默认装配卸载成功")
	return actor


static func _test_install_pairs_behavior_and_visual(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var bundle := FlightBundle.new()
	t.assert_eq(bundle.install(actor, true), "", "行为+视觉安装成功")
	t.assert_true(bundle.is_installed(), "bundle 记录为已安装")
	var capability := bundle.installed_capability()
	t.assert_true(capability != null and capability.name == "SwordFlight", "创建 SwordFlight 直系子能力")
	t.assert_eq(capability.get_parent(), actor.get_node("CapabilityManager"), "能力挂在宿主唯一管理器下")
	var sword := bundle.installed_visual()
	t.assert_true(sword != null and sword.name == "FlyingSword", "创建 FlyingSword 视觉")
	t.assert_eq(sword.get_parent(), actor.get_node("Visual"), "视觉挂在宿主 Visual 下")
	t.assert_false(sword.visible, "初始隐藏（跟随 flight_active）")
	t.assert_eq(actor.flight_visual_node(), sword, "宿主已绑定该视觉")
	# 经真实 actor 帧开飞：tick → 合成 → 提交 → 帧末清边沿 → 表现同步，一次走完。
	actor.motion().on_floor = true
	actor.press_flight_toggle()
	actor.call("_physics_process", 0.016)
	t.assert_true(actor.motion().flight_active, "御剑激活")
	t.assert_true(sword.visible, "御剑期间剑可见")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 1, "激活期间登记一条阻塞")


static func _test_uninstall_clears_state_and_tag(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var bundle := FlightBundle.new()
	t.assert_eq(bundle.install(actor, true), "", "安装成功")
	actor.motion().on_floor = true
	actor.press_flight_toggle()
	actor.call("_physics_process", 0.016)
	t.assert_true(actor.motion().flight_active, "卸载前处于御剑")
	var motion := actor.motion()
	motion.move_input = Vector2(0.3, -0.2)
	motion.actual_velocity = Vector3(1.0, 2.0, 3.0)
	t.assert_eq(bundle.uninstall(), "", "卸载成功")
	t.assert_false(actor.motion().flight_active, "卸载清 flight_active（_exit_tree 兜底）")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "卸载清 sword_flight_block")
	t.assert_true(actor.flight_visual_node() == null, "卸载解除视觉绑定")
	t.assert_false(actor.get_node_or_null("Visual/FlyingSword") != null, "卸载移除视觉节点")
	t.assert_eq(actor.motion().move_input, Vector2(0.3, -0.2), "卸载不碰借用组件的输入")
	t.assert_eq(actor.motion().actual_velocity, Vector3(1.0, 2.0, 3.0), "卸载不碰借用组件的速度")
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "卸载移除能力节点")
	t.assert_eq(bundle.uninstall(), "", "重复卸载幂等")


static func _test_install_without_visual_is_allowed(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var bundle := FlightBundle.new()
	t.assert_eq(bundle.install(actor, false), "", "headless 裸装（无视觉）允许")
	t.assert_true(bundle.installed_capability() != null, "裸装仍提供行为")
	t.assert_true(bundle.installed_visual() == null, "裸装不产生视觉")
	t.assert_false(actor.get_node_or_null("Visual/FlyingSword") != null, "裸装不产生剑节点")


static func _test_reinstall_same_config_idempotent(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var bundle := FlightBundle.new()
	t.assert_eq(bundle.install(actor, true), "", "首次安装")
	var manager := actor.get_node("CapabilityManager")
	var count := manager.get_child_count()
	t.assert_eq(bundle.install(actor, true), "", "同配置重复安装幂等")
	t.assert_eq(manager.get_child_count(), count, "重复安装不新增能力节点")


static func _test_config_change_requires_uninstall(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var bundle := FlightBundle.new()
	# 先裸装，再请求补视觉：必须显式拒绝，且保留原能力（不得删除调用前已有的 cap）。
	t.assert_eq(bundle.install(actor, false), "", "先裸装")
	var capability := bundle.installed_capability()
	var error := bundle.install(actor, true)
	t.assert_true(error != "", "已装无视觉时请求视觉被拒绝：%s" % error)
	t.assert_true(is_instance_valid(capability) and capability.get_parent() != null, "拒绝补视觉后原能力保留")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "拒绝路径不产生 tag 残留")
	# 显式卸载后按新配置装。
	t.assert_eq(bundle.uninstall(), "", "显式卸载成功")
	t.assert_eq(bundle.install(actor, true), "", "卸载后按新配置装成功")
	t.assert_true(bundle.installed_visual() != null, "新配置确实带上了视觉")


static func _test_refuses_foreign_capability(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var manager := actor.get_node("CapabilityManager") as CapabilityManager
	var foreign := SwordFlight.new()
	foreign.name = "SwordFlight"
	manager.add_child(foreign)
	var bundle := FlightBundle.new()
	var error := bundle.install(actor, true)
	t.assert_true(error != "", "外部已有 SwordFlight 时拒绝安装：%s" % error)
	t.assert_true(is_instance_valid(foreign) and foreign.get_parent() == manager, "外部能力未被删除")
	t.assert_false(bundle.is_installed(), "拒绝后未记录安装")
	t.assert_true(actor.get_node_or_null("Visual/FlyingSword") == null, "拒绝后不留下视觉")
	t.assert_eq(TagRegistry.block_count(actor, &"sword_flight_block"), 0, "拒绝路径不产生 tag")


static func _test_refuses_foreign_visual_without_claiming(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var visual_root := actor.get_node("Visual") as Node3D
	var foreign := Node3D.new()
	foreign.name = "FlyingSword"
	visual_root.add_child(foreign)
	var bundle := FlightBundle.new()
	var error := bundle.install(actor, true)
	t.assert_true(error != "", "外部已有 FlyingSword 时拒绝覆盖：%s" % error)
	t.assert_true(is_instance_valid(foreign) and foreign.get_parent() == visual_root, "外部视觉未被删除或改名")
	t.assert_eq(foreign.name, "FlyingSword", "外部视觉名字未被改写")
	t.assert_true(actor.get_node("CapabilityManager").get_child_count() == 0, "拒绝后能力也未安装")


static func _test_refuses_when_visual_already_bound(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var other := Node3D.new()
	t.track(other)
	actor.bind_flight_visual(other)
	var bundle := FlightBundle.new()
	var error := bundle.install(actor, true)
	t.assert_true(error != "", "宿主已绑定其它御剑视觉时拒绝：%s" % error)
	t.assert_eq(actor.flight_visual_node(), other, "拒绝后不覆盖原绑定")
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "拒绝后不留下能力")


static func _test_missing_visual_root_fails_cleanly(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var visual := actor.get_node("Visual")
	actor.remove_child(visual)
	visual.queue_free()
	var bundle := FlightBundle.new()
	var error := bundle.install(actor, true)
	t.assert_true(error != "", "缺少 Visual 时安装失败：%s" % error)
	t.assert_false(bundle.is_installed(), "失败后未记录安装")
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "失败后无半装配能力残留")


static func _test_missing_manager_rejected(t) -> void:
	t.begin_case()
	var actor: Swordsman = load(SCENE).instantiate()
	t.track(actor)
	var assembly := actor.get_node("ActorAssembly") as ActorAssembly
	t.assert_eq(assembly.uninstall(), "", "默认装配卸载成功")
	var manager := actor.get_node("CapabilityManager")
	actor.remove_child(manager)
	manager.queue_free()
	var bundle := FlightBundle.new()
	var error := bundle.install(actor, true)
	t.assert_true(error != "", "缺少直系管理器时拒绝：%s" % error)
	t.assert_false(bundle.is_installed(), "拒绝后未记录安装")


## 同一 bundle 实例已装在 host A 时，传 host B 必须报错且 B 保持未装。
static func _test_second_host_rejected_while_installed(t) -> void:
	t.begin_case()
	var actor_a := _fresh_actor(t)
	var actor_b := _fresh_actor(t)
	var bundle := FlightBundle.new()
	t.assert_eq(bundle.install(actor_a, false), "", "先装在 host A")
	var error := bundle.install(actor_b, false)
	t.assert_true(error != "", "同实例改挂 host B 被拒绝：%s" % error)
	t.assert_eq(actor_b.get_node("CapabilityManager").get_child_count(), 0, "host B 保持未装（无能力）")
	t.assert_eq(actor_a.get_node("CapabilityManager").get_child_count(), 1, "host A 的安装不受影响")
	t.assert_true(is_instance_valid(bundle.installed_capability()), "host A 能力仍有效")


## host 先被释放后卸载：不得访问已释放对象，且不报错、不崩溃。
static func _test_uninstall_after_host_freed(t) -> void:
	t.begin_case()
	var actor: Swordsman = load(SCENE).instantiate()
	var holder := Node.new()
	t.track(holder)
	holder.add_child(actor)
	var assembly := actor.get_node("ActorAssembly") as ActorAssembly
	t.assert_eq(assembly.uninstall(), "", "默认装配卸载成功")
	var bundle := FlightBundle.new()
	t.assert_eq(bundle.install(actor, true), "", "安装到宿主")
	# 释放宿主（连同 bundle 创建的节点）。
	holder.remove_child(actor)
	actor.free()
	t.assert_eq(bundle.uninstall(), "", "宿主已释放后卸载安全返回成功")
	t.assert_eq(bundle.uninstall(), "", "重复卸载仍幂等成功")


## 缺 SwordsmanMotionComponent：能力会静默无行为，必须显式失败。
static func _test_missing_motion_component_rejected(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var component := actor.get_node("SwordsmanMotionComponent")
	actor.remove_child(component)
	component.queue_free()
	var bundle := FlightBundle.new()
	var error := bundle.install(actor, false)
	t.assert_true(error != "", "缺少 SwordsmanMotionComponent 时拒绝：%s" % error)
	t.assert_false(bundle.is_installed(), "拒绝后未记录安装")
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "拒绝后无能力残留")


## 宿主存在多个 CapabilityManager：装配契约要求唯一，必须显式失败。
static func _test_duplicate_manager_rejected(t) -> void:
	t.begin_case()
	var actor := _fresh_actor(t)
	var extra := CapabilityManager.new()
	extra.name = "SecondManager"
	extra.set_process(false)
	actor.add_child(extra)
	var bundle := FlightBundle.new()
	var error := bundle.install(actor, false)
	t.assert_true(error != "", "存在多个 CapabilityManager 时拒绝：%s" % error)
	t.assert_false(bundle.is_installed(), "拒绝后未记录安装")
	t.assert_eq(actor.get_node("CapabilityManager").get_child_count(), 0, "拒绝后无能力残留")
	t.assert_eq(extra.get_child_count(), 0, "拒绝后第二个管理器也未被写入")
