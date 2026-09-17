extends RefCounted
## 测试断言与夹具管理（零外部依赖，替代 GUT）。
##
## 启用 GUT 的条件见 notes/implemented/process/2026-08-28-gate-tiers.md（Tier 2）：
## 测试文件超过 50 个，或团队要求标准断言体验时另行决策。

var passed: int = 0
var failed: int = 0
var messages: Array[String] = []

var _root: Node


func _init(root: Node) -> void:
	_root = root


func root() -> Node:
	return _root


## 每个用例第一行必须调用：清场景 + 重置全局静态状态。
## 静态设施（TagRegistry / TimeKeeper）跨用例存活，不重置会造成串扰
## （见 notes/implemented/tech/2026-08-28-static-globals-over-autoload.md）。
func begin_case() -> void:
	for child in _root.get_children():
		_root.remove_child(child)
		child.queue_free()
	TagRegistry.clear_all()
	TimeKeeper.clear_all()


## 登记节点：未挂载的自动挂到测试根。
func track(node: Node) -> Node:
	if node.get_parent() == null:
		_root.add_child(node)
	return node


func cleanup() -> void:
	begin_case()


func assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		messages.append("FAIL %s（期望为真）" % message)


func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)


func assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		messages.append("FAIL %s（期望 %s，实际 %s）" % [message, str(expected), str(actual)])
