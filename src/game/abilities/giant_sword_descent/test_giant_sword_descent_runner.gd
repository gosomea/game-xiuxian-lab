extends Node

const TestContext := preload("res://tests/test_context.gd")
const Suite := preload("res://game/abilities/giant_sword_descent/test_giant_sword_descent.gd")


func _ready() -> void:
	var context := TestContext.new(self)
	await Suite.run(context)
	for message in context.messages:
		print(message)
	print("巨剑镇落：通过 %d，失败 %d" % [context.passed, context.failed])
	context.cleanup()
	get_tree().quit(1 if context.failed > 0 else 0)
