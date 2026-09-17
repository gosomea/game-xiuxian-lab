class_name TimeKeeper
extends RefCounted

## 时停/变速请求登记（静态类，见 notes/implemented/tech/2026-08-28-static-globals-over-autoload.md）。
##
## 本类是 Engine.time_scale 的唯一写入者。禁止任何系统直接改 Engine.time_scale
## 或 get_tree().paused——否则「神识时停」与未来的「顿悟时刻」会互相取消。
## 最终缩放取所有请求的最小值（最强的减速胜出）。

static var _requests: Dictionary = {}


static func request(instigator: Object, scale: float = 0.0) -> void:
	_requests[instigator.get_instance_id()] = scale
	_apply()


static func release(instigator: Object) -> void:
	_requests.erase(instigator.get_instance_id())
	_apply()


static func request_count() -> int:
	return _requests.size()


static func current_scale() -> float:
	var scale := 1.0
	for requested in _requests.values():
		scale = minf(scale, requested)
	return scale


static func clear_all() -> void:
	_requests.clear()
	_apply()


static func _apply() -> void:
	Engine.time_scale = current_scale()
