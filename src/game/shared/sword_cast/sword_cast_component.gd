class_name SwordCastComponent
extends Component

## 剑法出招共享数据（纯数据）。
##
## 场景每物理帧写入鼠标指向与左键输入；SwordQi / FlyingSwordStrike / SwordArray 只在
## form 与自己匹配时读输入，并写出招请求、本命剑位置与投射物渲染数据；
## 悬浮本命剑、出招姿势与投射物视图只读。
## 没有自然所有者：任何一招删除，其余两招与表现仍读写它。
## 契约登记在 res://data/vocabulary/sword_cast.json；
## 决策见 notes/implemented/gameplay/2026-10-09-sword-workbench.md。

const FORM_QI := "sword_qi"
const FORM_STRIKE := "flying_sword"
const FORM_ARRAY := "sword_array"
const FORMS: Array[String] = [FORM_QI, FORM_STRIKE, FORM_ARRAY]
const POSE_THRUST := "thrust"
const POSE_RAISE := "raise"

## 输入：鼠标在地面的指向点（世界坐标）。
var aim_point: Vector3 = Vector3.ZERO
## 输入：左键按下边沿（仅一帧）。
var cast_pressed: bool = false
## 输入：左键是否按住。
var cast_held: bool = false
## 输入：左键松开边沿（仅一帧）。
var cast_released: bool = false
## 输入：当前选中的招式。
var form: String = FORM_QI

## 请求：出招时希望角色面向的世界水平方向；截止时刻为 face_until（manager_time）。
var face_direction: Vector3 = Vector3.ZERO
var face_until: float = -1.0
## 请求：出招姿势目标权重与种类，表现层平滑过渡。
var pose_weight: float = 0.0
var pose_kind: String = POSE_THRUST

## 状态：本命剑是否离开悬浮位，以及离开时的世界位置与剑尖方向。
var sword_away: bool = false
var sword_position: Vector3 = Vector3.ZERO
var sword_forward: Vector3 = Vector3.FORWARD

## 渲染数据：飞行中的剑气，每项 {position, direction, travelled}。
var qi_shots: Array = []
## 渲染数据：剑阵中的剑，每项 {position, forward}。
var array_swords: Array = []

## 统计。
var casts_total: int = 0
var last_cast_form: String = ""

## 参数：悬浮位相对角色根的局部偏移；角色局部 +Z 为正面，-X 为右手侧。
@export var sword_rest_offset: Vector3 = Vector3(-0.42, 1.72, -0.28)
## 参数：出招后面向与姿势保持的时长（秒）。
@export var pose_time: float = 0.35

## 参数：剑气。
@export var qi_speed: float = 18.0
@export var qi_range: float = 14.0
@export var qi_radius: float = 0.7
@export var qi_height: float = 1.0
@export var qi_cooldown: float = 0.3

## 参数：飞剑出击。
@export var strike_speed: float = 26.0
@export var strike_range: float = 16.0
@export var strike_return_speed: float = 22.0
@export var strike_radius: float = 0.35

## 参数：剑阵。
@export var array_max: int = 36
@export var array_spawn_interval: float = 0.05
@export var array_fire_interval: float = 0.03
@export var array_speed: float = 30.0
@export var array_radius: float = 0.3
@export var array_spread: float = 1.6
@export var array_cooldown: float = 0.4


## 派生：角色根在 origin、面向 facing 时本命剑悬浮位的世界坐标（不含表现层浮动）。
func rest_position(origin: Vector3, facing: Vector3) -> Vector3:
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() <= 0.000001:
		flat = Vector3.FORWARD
	return origin + Basis(Vector3.UP, atan2(flat.x, flat.z)) * sword_rest_offset


## 派生：面向请求在给定逻辑时刻是否仍有效。
func facing_requested(now: float) -> bool:
	return now <= face_until and face_direction.length_squared() > 0.000001


## 数据存取：登记一次出招。
func record_cast(cast_form: String, direction: Vector3, now: float, kind: String) -> void:
	casts_total += 1
	last_cast_form = cast_form
	face_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	face_until = now + pose_time
	pose_kind = kind
	pose_weight = 1.0


## 数据存取：清空本帧输入（失焦、重置时由场景调用）。
func clear_input() -> void:
	cast_pressed = false
	cast_held = false
	cast_released = false
