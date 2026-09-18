extends Node
## 测试入口：godot --headless --path src tests/test_runner.tscn
##
## 必须用主场景模式而非 -s 脚本模式：自定义 SceneTree 下 root 的树绑定未完成，
## add_child 的节点 is_inside_tree() 恒为 false，依赖分组查询的断言会假绿。
## 见 notes/implemented/tech/2026-08-28-test-entry-scene-mode.md
##
## 本轮集成（S0 收口）登记的套件：
## - actors/swordsman 的 ActorAssembly 装配适配器（run 是协程：内含真实物理帧推进，必须 await）；
## - abilities/sword_flight 的 FlightBundle（行为+视觉装配包）；
## - systems/camera_rig 的五个模式 / executor 套件；
## - systems/motion_preview 的程序动作预览单测；
## - tests/test_lab_navigation 的两级导航单测。
## camera_rig 仍有包内自跑入口 test_camera_rig_runner.tscn；此处登记后两处结果应一致。

const TestContext := preload("res://tests/test_context.gd")

const SUITES := [
	"res://tests/test_core.gd",
	"res://game/actors/swordsman/test_swordsman_movement.gd",
	"res://game/actors/swordsman/test_actor_assembly.gd",
	"res://game/abilities/jump/test_jump.gd",
	"res://game/abilities/sword_flight/test_sword_flight.gd",
	"res://game/abilities/sword_flight/test_flight_bundle.gd",
	"res://tests/test_vocabulary.gd",
	"res://tests/fixtures/template_vitals/test_vitals_regeneration.gd",
	"res://tests/fixtures/template_vitals/test_vitals_guard.gd",
	"res://game/systems/lab_catalog/test_lab_catalog.gd",
	"res://game/systems/camera_rig/test_fixed_follow.gd",
	"res://game/systems/camera_rig/test_quarter_turn.gd",
	"res://game/systems/camera_rig/test_orbit.gd",
	"res://game/systems/camera_rig/test_overview.gd",
	"res://game/systems/camera_rig/test_camera_rig_executor.gd",
	"res://game/systems/motion_preview/test_motion_preview.gd",
	"res://tests/test_movement_lab_hub.gd",
	"res://tests/test_movement_lab_input.gd",
	"res://tests/test_lab_navigation.gd",
	"res://tests/test_motion_stage_geometry.gd",
]


func _ready() -> void:
	var total_passed := 0
	var total_failed := 0
	var all_messages: Array[String] = []

	for path in SUITES:
		var suite: Script = load(path)
		if suite == null:
			all_messages.append("FAIL 无法加载测试脚本 %s" % path)
			total_failed += 1
			continue

		var container := Node.new()
		add_child(container)
		var context := TestContext.new(container)

		# await：部分套件（ActorAssembly 真实物理帧）的 run() 是协程；
		# 不 await 会在推进到首个 await 前就统计，把它们误报成通过（假绿）。
		await suite.run(context)

		total_passed += context.passed
		total_failed += context.failed
		for message in context.messages:
			all_messages.append("%s :: %s" % [path.get_file(), message])

		context.cleanup()
		remove_child(container)
		container.queue_free()

		var mark := "OK  " if context.failed == 0 else "FAIL"
		print("%s %-42s 通过 %d / 失败 %d" % [mark, path.get_file(), context.passed, context.failed])

	print("")
	for message in all_messages:
		print("  " + message)
	print("")
	print("测试合计：通过 %d，失败 %d" % [total_passed, total_failed])

	get_tree().quit(1 if total_failed > 0 else 0)
