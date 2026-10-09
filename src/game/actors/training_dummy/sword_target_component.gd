class_name SwordTargetComponent
extends Component

## 可被剑法命中的竖直圆柱目标（纯数据）。
##
## 宿主加入 sword_target 分组；出招能力用本帧投射物位移线段与本圆柱求交，命中后调用
## record_hit()。木桩表现与场景只读 hit_count 的变化。
## 契约登记在 res://data/vocabulary/training_dummy.json。

## 圆柱半径（米）与高度（米，从宿主原点向上）。
@export var radius: float = 0.35
@export var height: float = 1.8

var hit_count: int = 0
var last_hit_form: String = ""
var last_hit_point: Vector3 = Vector3.ZERO


## 数据存取：登记一次命中。
func record_hit(form: String, point: Vector3) -> void:
	hit_count += 1
	last_hit_form = form
	last_hit_point = point


## 数据存取：重置命中记录。
func reset_hits() -> void:
	hit_count = 0
	last_hit_form = ""
	last_hit_point = Vector3.ZERO
