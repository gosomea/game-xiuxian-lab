class_name GiantSwordDescentComponent
extends Component

## 巨剑镇落参数和只读表现快照。阶段与命中全部由能力推进。
## owning note：2026-10-10-sword-spell-exploration；词汇：giant_sword_descent.json。

@export var min_gather_time: float = 0.42
@export var full_charge_time: float = 0.9
@export var hover_time: float = 0.26
@export var descent_time: float = 0.48
@export var impact_hold_time: float = 0.2
@export var fade_time: float = 0.62
@export var cooldown: float = 0.38
@export var hover_tip_height: float = 6.3
@export var sword_length_m: float = 5.6
@export var hover_lift: float = 0.35
@export var preview_follow_rate: float = 10.0
@export var hit_radius: float = 0.52
@export var shock_radius: float = 3.2
@export var shock_height: float = 2.0
@export var rune_radius: float = 2.4

var phase: String = "idle"
var phase_progress: float = 0.0
var phase_elapsed: float = 0.0
var visual_time: float = 0.0
var charge: float = 0.0
var locked: bool = false
var target_point: Vector3 = Vector3.ZERO
var target_normal: Vector3 = Vector3.UP
var rune_point: Vector3 = Vector3.ZERO
var rune_normal: Vector3 = Vector3.UP
var rune_alpha: float = 0.0
var sword_tip: Vector3 = Vector3.ZERO
var sword_forward: Vector3 = Vector3.DOWN
var sword_length: float = 0.0
var sword_alpha: float = 0.0
var tip_history: PackedVector3Array = PackedVector3Array()
var impact_age: float = -1.0
var impact_serial: int = 0


## 纯数据存取：保留累计 impact_serial，撤销本次表现。
func clear_visual() -> void:
	phase = "idle"
	phase_progress = 0.0
	phase_elapsed = 0.0
	visual_time = 0.0
	charge = 0.0
	locked = false
	target_point = Vector3.ZERO
	target_normal = Vector3.UP
	rune_point = Vector3.ZERO
	rune_normal = Vector3.UP
	rune_alpha = 0.0
	sword_tip = Vector3.ZERO
	sword_forward = Vector3.DOWN
	sword_length = 0.0
	sword_alpha = 0.0
	tip_history = PackedVector3Array()
	impact_age = -1.0
