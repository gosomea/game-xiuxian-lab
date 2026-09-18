extends Node
## 测试入口：godot --headless --path . tests/test_runner.tscn
##
## 必须用主场景模式而非 -s 脚本模式：自定义 SceneTree 下 root 的树绑定未完成，
## add_child 的节点 is_inside_tree() 恒为 false，依赖分组查询的断言会假绿。
## 见 notes/implemented/tech/2026-08-28-test-entry-scene-mode.md

const TestContext := preload("res://tests/test_context.gd")

const SUITES := [
	"res://tests/test_core.gd",
	"res://game/actors/swordsman/test_swordsman_movement.gd",
	"res://game/abilities/jump/test_jump.gd",
	"res://game/abilities/sword_flight/test_sword_flight.gd",
	"res://tests/test_vocabulary.gd",
	"res://tests/fixtures/template_vitals/test_vitals_regeneration.gd",
	"res://tests/fixtures/template_vitals/test_vitals_guard.gd",
	"res://game/systems/lab_catalog/test_lab_catalog.gd",
	"res://tests/test_movement_lab_hub.gd",
	"res://tests/test_movement_lab_input.gd",
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

		suite.run(context)

		total_passed += context.passed
		total_failed += context.failed
		for message in context.messages:
			all_messages.append("%s :: %s" % [path.get_file(), message])

		context.cleanup()
		remove_child(container)
		container.queue_free()

		var mark := "OK  " if context.failed == 0 else "FAIL"
		print("%s %-38s 通过 %d / 失败 %d" % [mark, path.get_file(), context.passed, context.failed])

	print("")
	for message in all_messages:
		print("  " + message)
	print("")
	print("测试合计：通过 %d，失败 %d" % [total_passed, total_failed])

	get_tree().quit(1 if total_failed > 0 else 0)
