extends RefCounted

const Catalog := preload("res://game/systems/lab_catalog/lab_catalog.gd")


static func run(t) -> void:
	t.begin_case()
	var result := Catalog.read()
	t.assert_true(result["errors"].is_empty(), "实际清单必须满足契约")
	t.assert_true(result["modules"].size() > 0, "实际清单能够读取模块")

	t.begin_case()
	var planned := _entry("map")
	t.assert_false(Catalog.can_open(planned), "计划不得提供运行入口")
	var false_ready := planned.duplicate(true)
	false_ready["status"] = "ready"
	t.assert_false(_valid([false_ready]), "ready 缺场景必须被拒绝")
	false_ready["scene"] = "res://levels/missing_experiment.tscn"
	t.assert_false(_valid([false_ready]), "ready 指向缺失场景必须被拒绝")
	t.assert_false(Catalog.can_open(false_ready), "缺失场景不得启动")

	t.begin_case()
	var exploring := _entry("map")
	exploring["status"] = "exploring"
	t.assert_true(_valid([exploring]), "探索中允许尚未产生场景")
	exploring["scene"] = "res://levels/empty_stage.tscn"
	t.assert_true(_valid([exploring]), "探索中可登记已有独立场景")
	t.assert_true(Catalog.can_open(exploring), "有效探索场景可进入")
	exploring["status"] = "ready"
	t.assert_true(_valid([exploring]), "ready 的有效场景通过")
	exploring["status"] = "planned"
	t.assert_false(_valid([exploring]), "planned 不得携带场景冒充入口")
	t.assert_false(Catalog.can_open(exploring), "即使路径存在，planned 也不可启动")

	t.begin_case()
	var character := _entry("character")
	var sword := _entry("sword", ["character"])
	t.assert_true(_valid([character, sword]), "已知无环依赖通过，未要求依赖 ready")
	t.assert_false(_valid([sword]), "未知依赖被拒绝")
	t.assert_false(_valid([character, character]), "重复模块 ID 被拒绝")
	character["depends_on"] = ["sword"]
	t.assert_false(_valid([character, sword]), "模块依赖循环被拒绝")
	t.assert_false(_valid([_entry("self", ["self"])]), "自身依赖被拒绝")

	t.begin_case()
	t.assert_false(Catalog.validate({"schema_version": 2, "modules": []}).is_empty(), "不支持的 schema 被拒绝")
	t.assert_false(Catalog.validate([]).is_empty(), "错误顶层类型被拒绝")
	t.assert_false(_valid([42]), "错误模块类型被拒绝")
	var malformed := _entry("bad")
	malformed["depends_on"] = [42]
	t.assert_false(_valid([malformed]), "非文本依赖被拒绝而不崩溃")
	malformed = _entry("bad")
	malformed["status"] = "completed"
	t.assert_false(_valid([malformed]), "未知状态被拒绝")
	malformed["status"] = "ready"
	malformed["scene"] = "res://tests/fixtures/template_vitals/vitals_sheet.tscn"
	t.assert_false(_valid([malformed]), "测试夹具不得作为实验入口")


static func _entry(id: String, dependencies: Array = []) -> Dictionary:
	return {"id": id, "title": id, "category": "test", "summary": "fixture", "question": "fixture", "scope": [], "depends_on": dependencies, "status": "planned", "scene": ""}


static func _valid(entries: Array) -> bool:
	return Catalog.validate({"schema_version": 1, "modules": entries}).is_empty()
