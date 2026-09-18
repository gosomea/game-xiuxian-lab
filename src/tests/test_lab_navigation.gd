extends RefCounted

## 两级导航的数据与可达性契约（S0）。
##
## 真实交互（点击直达、焦点更新详情、详情折叠、返回记忆与滚动恢复）由运行验收覆盖：
## src/tests/lab_playtest.gd 与 src/tests/movement_hub_playtest.gd。
## 本套件只断言「不依赖场景树即可判定」的部分：可进入性、计划项只有说明、场景真实存在。
## 刻意不镜像字号 / 颜色 / 尺寸常量，也不提供生产代码里的测试专用 setter。

const Catalog := preload("res://game/systems/lab_catalog/lab_catalog.gd")
const MovementHub := preload("res://levels/experiments/character_movement/movement_lab_hub.gd")


static func run(t) -> void:
	t.begin_case()
	_assert_top_hub(t)
	t.begin_case()
	_assert_movement_hub(t)


## 顶层：可进入模块直接指向真实场景；planned 模块没有场景但仍有可读问题说明。
static func _assert_top_hub(t) -> void:
	var result := Catalog.read()
	t.assert_true(result["errors"].is_empty(), "顶层清单满足契约：%s" % str(result["errors"]))
	var openable: Array[String] = []
	var planned: Array[String] = []
	for value in result["modules"]:
		var entry: Dictionary = value
		if Catalog.can_open(entry):
			openable.append(str(entry["id"]))
			t.assert_true(ResourceLoader.exists(str(entry["scene"])), "可进入模块场景真实存在：%s" % entry["id"])
			t.assert_true(str(entry["scene"]).begins_with("res://levels/"), "可进入模块场景在 levels：%s" % entry["id"])
		else:
			planned.append(str(entry["id"]))
			t.assert_eq(str(entry.get("scene", "")), "", "计划模块不挂场景：%s" % entry["id"])
			t.assert_false(str(entry.get("question", "")).strip_edges().is_empty(),
				"计划模块只查看说明但说明必须真实存在：%s" % entry["id"])
	t.assert_true(openable.size() >= 1, "至少一个模块可一次点击进入：%s" % str(openable))
	t.assert_true(planned.size() >= 1, "仍有计划模块（只查看说明）：%s" % str(planned))


## 子目录：每条都有问题与定位；可进入条目指向真实 levels 场景，且恰好覆盖 REQUIRED_IDS。
static func _assert_movement_hub(t) -> void:
	var result := MovementHub.read()
	t.assert_true(result["errors"].is_empty(), "子实验清单满足契约：%s" % str(result["errors"]))
	t.assert_eq(str(result["parent_scene"]), "res://levels/lab_hub.tscn", "子目录返回顶层实验目录")
	var entries: Array = result["subexperiments"]
	t.assert_eq(entries.size(), MovementHub.REQUIRED_IDS.size(), "子实验条目数与契约一致")
	for value in entries:
		var entry: Dictionary = value
		t.assert_true(str(entry["id"]) in MovementHub.REQUIRED_IDS, "条目 id 在契约集合内：%s" % entry["id"])
		t.assert_false(str(entry.get("question", "")).strip_edges().is_empty(), "条目有问题说明：%s" % entry["id"])
		t.assert_false(str(entry.get("stage", "")).strip_edges().is_empty(), "条目有定位：%s" % entry["id"])
		if MovementHub.can_open(entry):
			t.assert_true(ResourceLoader.exists(str(entry["scene"])), "可进入条目场景真实存在：%s" % entry["id"])
