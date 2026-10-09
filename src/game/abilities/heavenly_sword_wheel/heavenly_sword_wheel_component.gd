class_name HeavenlySwordWheelComponent
extends Component

## 天轮独立数据；阶段、时刻、逐剑状态和调参都属于本包。
## View 只读；公共输入、姿势和轻反馈仍通过 SwordCastComponent。
var phase: String = "idle"
var started_at: float = 0.0
var phase_started_at: float = 0.0
var logic_time: float = 0.0
var next_spawn_at: float = 0.0
var release_requested: bool = false
var cancel_generation_seen: int = 0
var ready_at: float = 0.0
var center: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.FORWARD
var locked_target: Vector3 = Vector3.ZERO
var locked_normal: Vector3 = Vector3.UP
var ring_angle: float = 0.0
var ring_alpha: float = 0.0
var swords: Array = []
var impacts: Array = []
var casts_total: int = 0
var launched_total: int = 0
var completed_total: int = 0

@export var max_swords: int = 36
@export var min_swords: int = 6
@export var inner_swords: int = 12
@export var inner_radius: float = 1.15
@export var outer_radius: float = 1.9
@export var center_height: float = 3.05
@export var center_back: float = 1.15
@export var gather_interval: float = 0.025
@export var entry_time: float = 0.42
@export var entry_radius: float = 0.65
@export var entry_back: float = 0.7
@export var entry_turn: float = 0.65
@export var wheel_spin: float = 0.22
@export var follow_rate: float = 9.0
@export var turn_time: float = 0.22
@export var group_size: int = 6
@export var group_interval: float = 0.11
@export var flight_speed: float = 28.0
@export var min_flight_time: float = 0.72
@export var acceleration_power: float = 1.55
@export var curve_lift: float = 0.55
@export var curve_outward: float = 0.65
@export var curve_forward: float = 1.6
@export var curve_approach: float = 2.8
@export var terminal_drop: float = 0.85
@export var landing_spread: float = 0.7
@export var ground_probe_height: float = 8.0
@export var ground_probe_depth: float = 12.0
@export var hit_radius: float = 0.28
@export var settle_time: float = 0.38
@export var cooldown: float = 0.38
@export var display_scale: float = 1.3
@export var feedback_strength: float = 0.09
@export var trail_samples: int = 14
@export var trail_step: float = 0.08
@export var impact_time: float = 0.35
@export var ring_width: float = 0.025
@export var rune_width: float = 0.015
@export var sword_color: Color = Color(0.24, 0.98, 0.79, 1.0)
@export var ring_color: Color = Color(1.0, 0.76, 0.25, 0.9)
