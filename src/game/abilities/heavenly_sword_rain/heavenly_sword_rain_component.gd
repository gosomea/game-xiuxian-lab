class_name HeavenlySwordRainComponent
extends Component

## 天降剑雨数据。能力推进规则与轨迹，视图只消费数组；不认识宿主、输入或场景树。
## 契约 res://data/vocabulary/heavenly_sword_rain.json；owning note 为剑术三方向探索。

@export_range(3, 96, 1) var sword_count: int = 24
@export_range(3, 8, 1) var batch_count: int = 3
@export var region_radius: float = 2.7
@export var ceiling_height: float = 6.0
@export var gather_time: float = 0.72
@export var hover_time: float = 0.22
@export var batch_interval: float = 0.30
@export var sword_stagger: float = 0.012
@export var fall_time: float = 0.62
@export var linger_time: float = 0.32
@export var fade_time: float = 0.38
@export var cooldown: float = 0.55
@export var sword_scale: float = 1.55
@export var hit_radius: float = 0.25
@export var follow_rate: float = 12.0
@export var bend_distance: float = 0.22

var phase: String = "idle"
var progress: float = 0.0
var ground_center: Vector3 = Vector3.ZERO
var ground_normal: Vector3 = Vector3.UP
var ceiling_center: Vector3 = Vector3.ZERO
var ring_alpha: float = 0.0
var ring_angle: float = 0.0
var released: bool = false
var swords: Array = []
var impacts: Array = []
var batches_launched: int = 0
var swords_landed: int = 0
