class_name LabCatalog
extends RefCounted

## 实验目录的数据契约。planned 是计划，只有实际可加载的场景才提供运行入口。

const PATH := "res://data/content/experiments.json"
const STATUSES := ["planned", "exploring", "ready"]
const STATUS_LABELS := {"planned": "待探索", "exploring": "探索中", "ready": "当前可用"}


static func read() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {"modules": [], "errors": PackedStringArray(["无法读取实验清单：%s" % PATH])}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"modules": [], "errors": PackedStringArray(["实验清单 JSON 错误：%s" % parser.get_error_message()])}
	var errors := validate(parser.data)
	if not errors.is_empty():
		return {"modules": [], "errors": errors}
	return {"modules": parser.data["modules"], "errors": errors}


static func can_open(entry: Dictionary) -> bool:
	var scene := str(entry.get("scene", ""))
	return entry.get("status", "planned") in ["exploring", "ready"] and _valid_scene(scene)


static func validate(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("modules") is Array:
		return PackedStringArray(["实验清单需要 schema_version: 1 和 modules 数组"])
	var entries: Array = data["modules"]
	var ids: Dictionary = {}
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-z][a-z0-9_]*$")
	for value in entries:
		if not value is Dictionary:
			errors.append("每个模块必须是对象")
			continue
		var entry: Dictionary = value
		for key in ["id", "title", "category", "summary", "question", "status", "scene"]:
			if not entry.get(key) is String:
				errors.append("模块字段 %s 必须是文本" % key)
		var id := str(entry.get("id", ""))
		if id_pattern.search(id) == null:
			errors.append("模块 ID 必须为 snake_case：%s" % id)
		if ids.has(id):
			errors.append("重复模块 ID：%s" % id)
		ids[id] = entry
		if str(entry.get("title", "")).strip_edges().is_empty():
			errors.append("模块标题不能为空：%s" % id)
		for key in ["scope", "depends_on"]:
			if not entry.get(key) is Array:
				errors.append("%s 的 %s 必须是数组" % [id, key])
				continue
			for item in entry[key]:
				if not item is String:
					errors.append("%s 的 %s 只能包含文本" % [id, key])
		var status := str(entry.get("status", ""))
		var scene := str(entry.get("scene", ""))
		if status not in STATUSES:
			errors.append("未知模块状态：%s / %s" % [id, status])
		if status == "planned" and not scene.is_empty():
			errors.append("待探索模块不得挂载场景：%s" % id)
		if status == "ready" and scene.is_empty():
			errors.append("当前可用模块必须有独立场景：%s" % id)
		if not scene.is_empty() and not _valid_scene(scene):
			errors.append("模块场景无法加载或不在 levels 内：%s / %s" % [id, scene])
	if not errors.is_empty():
		return errors
	for entry in entries:
		for dependency in entry["depends_on"]:
			if not ids.has(dependency):
				errors.append("%s 引用了不存在的模块：%s" % [entry["id"], dependency])
	if errors.is_empty() and _has_dependency_cycle(ids):
		errors.append("模块依赖存在循环，请明确共享方向")
	return errors


static func _valid_scene(scene: String) -> bool:
	if not scene.begins_with("res://levels/") or not scene.ends_with(".tscn") or ".." in scene:
		return false
	return ResourceLoader.exists(scene, "PackedScene") and load(scene) is PackedScene


static func _has_dependency_cycle(entries: Dictionary) -> bool:
	var remaining := entries.keys()
	var resolved: Dictionary = {}
	while not remaining.is_empty():
		var progressed := false
		for id in remaining.duplicate():
			var dependencies_resolved := true
			for dependency in entries[id]["depends_on"]:
				if not resolved.has(dependency):
					dependencies_resolved = false
					break
			if dependencies_resolved:
				resolved[id] = true
				remaining.erase(id)
				progressed = true
		if not progressed:
			return true
	return false
