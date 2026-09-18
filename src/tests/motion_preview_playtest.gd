extends SceneTree

## 动作预览专项测试入口（S2 P0）：不依赖 tests/test_runner.gd 的套件登记，
## 供本专项单独运行与交接给整合者按需登记。
##
## 用法：
##   Godot --headless --path src --script res://tests/motion_preview_playtest.gd
##
## 退出码：0 = 全部通过，1 = 有失败（失败即 1，不吞错）。

const TestContext := preload("res://tests/test_context.gd")
const SUITE := preload("res://game/systems/motion_preview/test_motion_preview.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var container := Node.new()
	root.add_child(container)
	var context := TestContext.new(container)
	Suite_run(context)
	context.cleanup()
	container.queue_free()
	print("MOTION_PREVIEW_PLAYTEST 通过 %d / 失败 %d" % [context.passed, context.failed])
	for message in context.messages:
		print("  " + message)
	quit(1 if context.failed > 0 else 0)


## 显式包装一层，避免与套件的静态方法名混淆。
func Suite_run(context) -> void:
	SUITE.run(context)
