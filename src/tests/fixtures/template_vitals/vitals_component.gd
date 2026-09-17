class_name VitalsComponent
extends Component

## 生命数值（纯数据）：当前值、上限、以及伤害减免来源账本。
##
## 这是模板的通用示例组件。任何游戏都需要某种「可被消耗、可被恢复、可被保护」的数值——
## 血量、耐久、护盾、燃料、理智值都是它的变体。实例化项目时可直接复用或改名。
##
## 解耦要点：造成伤害的能力、恢复的能力、提供减免的能力三者互不认识，
## 都只读写本组件。减免方往 _mitigations 写记录，受伤方现算实际伤害。

signal value_changed(current: float, maximum: float)
signal depleted

@export var maximum: float = 100.0
@export var current: float = 100.0

## 低于此比例时视为危急（供其他能力作为触发条件读取，不在此处做决策）
@export var critical_ratio: float = 0.25

## instigator_id -> 减免比例（0.0–1.0）
var _mitigations: Dictionary = {}


func ratio() -> float:
	if maximum <= 0.0:
		return 0.0
	return current / maximum


func is_critical() -> bool:
	return ratio() <= critical_ratio


func is_depleted() -> bool:
	return current <= 0.0


## 全部减免叠加后的实际承伤系数（0.0 = 完全免伤，1.0 = 无减免）。
## 多个减免源相乘而非相加——相加会在多源叠加时轻易溢出为负伤害。
func damage_multiplier() -> float:
	var multiplier := 1.0
	for reduction in _mitigations.values():
		multiplier *= clampf(1.0 - reduction, 0.0, 1.0)
	return multiplier


func apply_damage(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var actual := amount * damage_multiplier()
	current = maxf(0.0, current - actual)
	value_changed.emit(current, maximum)
	if is_depleted():
		depleted.emit()
	return actual


func restore(amount: float) -> float:
	if amount <= 0.0 or is_depleted():
		return 0.0
	var before := current
	current = minf(maximum, current + amount)
	if current != before:
		value_changed.emit(current, maximum)
	return current - before


func add_mitigation(instigator_id: int, reduction: float) -> void:
	var clamped := clampf(reduction, 0.0, 1.0)
	if _mitigations.get(instigator_id) == clamped:
		return
	_mitigations[instigator_id] = clamped
	value_changed.emit(current, maximum)


func remove_mitigation(instigator_id: int) -> void:
	if not _mitigations.has(instigator_id):
		return
	_mitigations.erase(instigator_id)
	value_changed.emit(current, maximum)


func mitigation_count() -> int:
	return _mitigations.size()
