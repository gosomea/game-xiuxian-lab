class_name StateTransitionLedger
extends RefCounted

## 状态切换压力场的事件账本（纯数据 + 格式化，无节点、无场景依赖、无能力引用）。
##
## 职责：记录场景**通过公开 / 只读状态实际观察到**的转换，供现场时间线与验收读回。
## 边界：
## - 不采信推测：只有调用方（场景）传入的读数才进账本；缺字段记为 "?" 而不是补默认值。
## - 不是 Component：不参与能力调度，不注册进词汇表，不被任何能力引用。
## - 不注入测试钩子到能力：本对象只被场景写、被场景与 HUD 读。
## - 环形上限保护长跑：超出后丢弃最旧事件并在摘要中如实标注丢弃数。

## 默认容量：约 3 分钟 60Hz 的边沿事件量级，足够压力场代表序列。
const DEFAULT_CAPACITY := 240

var _capacity: int
var _events: Array[Dictionary] = []
var _dropped: int = 0
var _last_frame: int = 0
var _last_observed: Dictionary = {}


func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	assert(capacity > 0, "StateTransitionLedger: capacity 必须为正")
	_capacity = capacity


## 追加一条事件。snapshot 为场景读到的只读快照；只提取已知字段，缺项记 "?"。
func record(frame: int, tag: String, note: String, snapshot: Dictionary, verdict: String = "") -> void:
	_last_frame = maxi(_last_frame, frame)
	_events.append({
		"frame": frame,
		"tag": tag,
		"note": note,
		"verdict": verdict,
		"on_floor": _value(snapshot, "on_floor"),
		"flight": _value(snapshot, "flight"),
		"block": _int_text(snapshot.get("block")),
		"jump_cap": _int_value(snapshot, "jump_active"),
		"flight_cap": _int_value(snapshot, "flight_cap_active"),
		"move_cap": _int_value(snapshot, "move_active"),
		"pos": _vector_text(snapshot.get("pos")),
		"velocity": _vector_text(snapshot.get("velocity")),
		"move_input": _input_text(snapshot.get("move_input")),
		"vertical_input": _float_text(snapshot.get("vertical_input")),
		"jump_edge": _value(snapshot, "jump_edge"),
		"flight_edge": _value(snapshot, "flight_edge"),
	})
	if _events.size() > _capacity:
		_events.remove_at(0)
		_dropped += 1


## 每秒对当前帧的持续读数做一次采样（无状态变化时不追加），用于时间线连续性。
## 只在读数与上一次采样不同时追加，避免长跑刷屏。
func observe(frame: int, snapshot: Dictionary) -> bool:
	var key := "%s/%s/%s" % [_value(snapshot, "on_floor"), _value(snapshot, "flight"), _value(snapshot, "block")]
	if key == _last_observed.get("key", ""):
		return false
	_last_observed = {"key": key, "frame": frame}
	record(frame, "state", "状态变化", snapshot, "")
	return true


func events() -> Array[Dictionary]:
	return _events


func event_count() -> int:
	return _events.size()


func dropped_count() -> int:
	return _dropped


func last_frame() -> int:
	return _last_frame


func clear() -> void:
	_events.clear()
	_last_observed.clear()
	_dropped = 0
	_last_frame = 0


## 摘要：只统计真实记录到的内容；丢弃数非零时如实显示。
func summary_text() -> String:
	if _events.is_empty():
		return "尚无事件"
	if _dropped > 0:
		return "%d 条（丢弃最旧 %d 条）" % [_events.size(), _dropped]
	return "%d 条" % _events.size()


## 账本文本（BBCode）：每条事件一行；判定列只回显调用方给出的 verdict，不自造结论。
func ledger_text() -> String:
	var lines := PackedStringArray()
	lines.append("[b]相对帧   事件            读数（着地/御剑/block/能力）        记录[/b]")
	for event in _events:
		var state := "空" if str(event["on_floor"]) == "?" else ("地" if str(event["on_floor"]) == "true" else "空")
		var flight := "御" if str(event["flight"]) == "true" else "步"
		var caps := "%s%s%s" % [
			_cap_mark(int(event["flight_cap"])), _cap_mark(int(event["jump_cap"])), _cap_mark(int(event["move_cap"])),
		]
		var verdict := str(event["verdict"])
		var tail := "" if verdict.is_empty() else "  [color=#3a6f5c]%s[/color]" % verdict
		lines.append("%6d   %-14s  %s/%s/blk=%s  %s%s" % [
			int(event["frame"]), str(event["note"]).substr(0, 14),
			state, flight, str(event["block"]), caps, tail,
		])
	return "\n".join(lines)


func _cap_mark(value: int) -> String:
	if value == 1:
		return "●"
	if value == 0:
		return "○"
	return "·"


func _value(snapshot: Dictionary, key: String) -> String:
	if not snapshot.has(key):
		return "?"
	return "true" if bool(snapshot[key]) else "false"


## 计数读数（block 数量）。缺项记 "?"——不补 0，避免把未观察显示成「无阻塞」。
func _int_text(value: Variant) -> String:
	if value == null:
		return "?"
	return "%d" % int(value)


func _int_value(snapshot: Dictionary, key: String) -> int:
	if not snapshot.has(key):
		return -1
	return int(snapshot[key])


func _vector_text(value: Variant) -> String:
	if value == null or not value is Vector3:
		return "?"
	var vector := value as Vector3
	return "(%.2f, %.2f, %.2f)" % [vector.x, vector.y, vector.z]


func _input_text(value: Variant) -> String:
	if value == null or not value is Vector2:
		return "?"
	var vector := value as Vector2
	return "(%.2f, %.2f)" % [vector.x, vector.y]


func _float_text(value: Variant) -> String:
	if value == null:
		return "?"
	return "%.2f" % float(value)
