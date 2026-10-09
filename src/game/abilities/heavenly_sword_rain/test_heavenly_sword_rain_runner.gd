extends Node
## 主场景模式的分支验收入口，避免 --script 自定义 SceneTree 的树绑定边界。

const TestContext := preload("res://tests/test_context.gd")
const SUITE := preload("res://game/abilities/heavenly_sword_rain/test_heavenly_sword_rain.gd")


func _ready() -> void:
	var container := Node.new()
	add_child(container)
	var context := TestContext.new(container)
	await SUITE.run(context)
	for message in context.messages:
		print(message)
	print("heavenly_sword_rain 配对测试：通过 %d，失败 %d" % [context.passed, context.failed])
	var failed := context.failed
	context.cleanup()
	remove_child(container)
	container.queue_free()
	get_tree().quit(1 if failed > 0 else 0)
