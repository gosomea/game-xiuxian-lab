class_name Vocabulary
extends RefCounted

## 词汇表的运行时读取端（见 notes/implemented/process/2026-08-28-first-audit-gaps.md）。
##
## src/data/vocabulary/ 是全项目唯一公共 API。Python 门禁在提交前拒绝未登记的词汇；
## 本类让运行时也能读同一份契约，使词汇表成为双向而非单向的约定。
##
## 用法（调试期自检，发布构建可通过 OS.is_debug_build() 短路）：
##   Vocabulary.assert_tag(&"shenshi_block")
##   Vocabulary.describe_tag(&"shenshi_block")

const INDEX_PATH := "res://data/vocabulary/index.json"

static var _index: Dictionary = {}
static var _loaded: bool = false


static func index() -> Dictionary:
	if not _loaded:
		_load()
	return _index


static func has_tag(tag: StringName) -> bool:
	return (index().get("tags") as Dictionary).has(String(tag))


static func has_group(group: StringName) -> bool:
	return (index().get("groups") as Dictionary).has(String(group))


static func has_component(component_class: StringName) -> bool:
	return (index().get("components") as Dictionary).has(String(component_class))


func _init() -> void:
	push_error("Vocabulary 是静态工具类，不应实例化")


## 调试期断言：tag 未登记时报错并返回 false。发布构建中不中断执行。
static func assert_tag(tag: StringName) -> bool:
	if has_tag(tag):
		return true
	push_error("Vocabulary: tag &\"%s\" 未在 src/data/vocabulary/tags/ 登记" % tag)
	return false


static func describe_tag(tag: StringName) -> String:
	var tags := index().get("tags") as Dictionary
	if not tags.has(String(tag)):
		return "(未登记)"
	var entry: Variant = tags[String(tag)]
	if not (entry is Dictionary):
		return "(未登记)"
	return str((entry as Dictionary).get("description", ""))


## 全部已登记的 tag，供调试面板或编辑器工具枚举。
static func all_tags() -> Array:
	return (index().get("tags") as Dictionary).keys()


static func reload() -> void:
	_loaded = false
	_load()


static func _load() -> void:
	_loaded = true
	_index = {"tags": {}, "groups": {}, "events": {}, "components": {}, "meta": {}}

	if not FileAccess.file_exists(INDEX_PATH):
		push_error("Vocabulary: 缺少 %s，请运行 python tools/gen/gen_vocabulary_index.py" % INDEX_PATH)
		return

	var text := FileAccess.get_file_as_string(INDEX_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("Vocabulary: %s 解析失败" % INDEX_PATH)
		return

	for section in _index.keys():
		if (parsed as Dictionary).has(section):
			_index[section] = (parsed as Dictionary)[section]
