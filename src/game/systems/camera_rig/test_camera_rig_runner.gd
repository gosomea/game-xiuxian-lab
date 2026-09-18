extends Node
## 本包（camera_rig）测试入口：主场景模式运行。
##
## 必须用主场景模式而非 --script 脚本模式：自定义 SceneTree 下 root 的树绑定未完成，
## add_child 的节点 is_inside_tree() 恒为 false，_ready 不触发，依赖组件解析的用例会假失败
## （与 res://tests/test_runner.gd 头注释同一原因，见
## notes/implemented/tech/2026-08-28-test-entry-scene-mode.md）。
##
## 用法：Godot --headless --path src res://game/systems/camera_rig/test_camera_rig_runner.tscn

const TestContext := preload("res://tests/test_context.gd")

const SUITES := [
	"res://game/systems/camera_rig/test_fixed_follow.gd",
	"res://game/systems/camera_rig/test_quarter_turn.gd",
	"res://game/systems/camera_rig/test_orbit.gd",
	"res://game/systems/camera_rig/test_overview.gd",
	"res://game/systems/camera_rig/test_camera_rig_executor.gd",
]


func _ready() -> void:
	var total_passed := 0
	var total_failed := 0
	for path in SUITES:
		var suite: Script = load(path)
		if suite == null:
			print("FAIL 无法加载测试脚本 %s" % path)
			total_failed += 1
			continue
		var container := Node.new()
		add_child(container)
		var context := TestContext.new(container)
		suite.run(context)
		total_passed += context.passed
		total_failed += context.failed
		for message in context.messages:
			print("  %s :: %s" % [path.get_file(), message])
		var mark := "OK  " if context.failed == 0 else "FAIL"
		print("%s %-34s 通过 %d / 失败 %d" % [mark, path.get_file(), context.passed, context.failed])
		context.cleanup()
		remove_child(container)
		container.queue_free()
	print("camera_rig 测试合计：通过 %d，失败 %d" % [total_passed, total_failed])
	get_tree().quit(1 if total_failed > 0 else 0)
