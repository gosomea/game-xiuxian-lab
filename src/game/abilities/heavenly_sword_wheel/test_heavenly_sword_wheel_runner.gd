extends Node

const TEST = preload("res://game/abilities/heavenly_sword_wheel/test_heavenly_sword_wheel.gd")
const CONTEXT = preload("res://tests/test_context.gd")


func _ready() -> void:
	var context = CONTEXT.new(self)
	TEST.run(context)
	for message in context.messages:
		print(message)
	print("HeavenlySwordWheel: %d passed, %d failed" % [context.passed, context.failed])
	var code := 1 if context.failed > 0 else 0
	context.cleanup()
	get_tree().quit(code)
