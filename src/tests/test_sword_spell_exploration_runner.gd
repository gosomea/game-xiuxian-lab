extends Node
## 快速组合回归入口；完整验收仍使用中央 test_runner。
const CONTEXT := preload("res://tests/test_context.gd")
func _ready() -> void:
	var container := Node.new()
	add_child(container)
	var context := CONTEXT.new(container)
	for path in ["res://tests/test_sword_workbench.gd", "res://tests/test_sword_spell_exploration.gd"]:
		await (load(path) as Script).run(context)
	for message in context.messages:
		print(message)
	print("SUMMARY passed=%d failed=%d" % [context.passed,context.failed])
	context.cleanup()
	get_tree().quit(1 if context.failed else 0)
