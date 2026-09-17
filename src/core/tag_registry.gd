class_name TagRegistry
extends RefCounted

## Tag 阻塞登记表（静态类，见 notes/implemented/tech/2026-08-28-static-globals-over-autoload.md）。
##
## 每条阻塞记录 instigator，解除时只移除自己的条目——防止 A 解除阻塞时误删 B 的阻塞
## （《逃出生天》踩过的坑，Instigator 机制正为此发明）。
## 所有 tag 必须登记在 src/data/vocabulary/tags/（verify-vocabulary 门禁）。
##
## 静态状态跨场景存活：切换场景或测试用例之间必须调用 clear_all()。

## target_id -> { tag -> [instigator_id, ...] }
static var _blocks: Dictionary = {}


static func add_block(target: Object, tag: StringName, instigator: Object) -> void:
	var target_id := target.get_instance_id()
	if not _blocks.has(target_id):
		_blocks[target_id] = {}
	if not _blocks[target_id].has(tag):
		_blocks[target_id][tag] = []
	var instigators: Array = _blocks[target_id][tag]
	var instigator_id := instigator.get_instance_id()
	if not instigators.has(instigator_id):
		instigators.append(instigator_id)


static func remove_block(target: Object, tag: StringName, instigator: Object) -> void:
	var target_id := target.get_instance_id()
	if not _blocks.has(target_id) or not _blocks[target_id].has(tag):
		return
	(_blocks[target_id][tag] as Array).erase(instigator.get_instance_id())
	_prune(target_id, tag)


static func is_blocked(target: Object, tag: StringName) -> bool:
	var target_id := target.get_instance_id()
	return _blocks.has(target_id) and _blocks[target_id].has(tag)


static func block_count(target: Object, tag: StringName) -> int:
	var target_id := target.get_instance_id()
	if not _blocks.has(target_id) or not _blocks[target_id].has(tag):
		return 0
	return (_blocks[target_id][tag] as Array).size()


## instigator 退场时清理它发起的全部阻塞。
static func remove_all_from(instigator: Object) -> void:
	var instigator_id := instigator.get_instance_id()
	for target_id in _blocks.keys():
		for tag in (_blocks[target_id] as Dictionary).keys():
			(_blocks[target_id][tag] as Array).erase(instigator_id)
			_prune(target_id, tag)


static func clear_all() -> void:
	_blocks.clear()


static func _prune(target_id: int, tag: StringName) -> void:
	if not _blocks.has(target_id):
		return
	if _blocks[target_id].has(tag) and (_blocks[target_id][tag] as Array).is_empty():
		(_blocks[target_id] as Dictionary).erase(tag)
	if (_blocks[target_id] as Dictionary).is_empty():
		_blocks.erase(target_id)
