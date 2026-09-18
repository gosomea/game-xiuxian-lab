class_name SwordsmanMotionComponent
extends Component

## 修士运动数据组件（纯数据）。
##
## 实验场景每物理帧写入输入与相机地面基；SwordsmanMovement / Jump / SwordFlight
## 读取它们并只写意图字段；Swordsman 根节点是唯一物理提交点。
## 本组件不读取键鼠，也不认识相机节点或实验场景。
## 契约见 docs/experiments/traversal-contract.md。

## 输入：屏幕相对输入（x = 右，y = 下，长度不超过 1）。
var move_input: Vector2 = Vector2.ZERO

## 输入：升降意图（+1 空格上升，-1 Ctrl 下降，0 悬停）；由场景写入。
var vertical_input: float = 0.0

## 输入：空格 key-down 边沿，仅按下那一帧为 true；actor 帧末清零。
var jump_pressed: bool = false

## 输入：F key-down 边沿，仅按下那一帧为 true；actor 帧末清零。
var flight_toggle_pressed: bool = false

## 输入：世界地面朝向单位向量（由鼠标地面投影写入），初始朝 -Z。
var aim_direction: Vector3 = Vector3.FORWARD

## 输入：相机右方向在地面的投影（单位向量）。
var camera_right: Vector3 = Vector3.RIGHT

## 输入：相机前方在地面的投影（单位向量）。
var camera_forward: Vector3 = Vector3.FORWARD

## 状态：上一帧物理结果的着地状态；能力 tick 中读到的是该值。
var on_floor: bool = false

## 状态：御剑状态唯一真源；SwordFlight 与 reset_motion() 写入。
var flight_active: bool = false

## 状态：最近一次物理 tick 后的完整速度（含竖直），供表现层读取。
var actual_velocity: Vector3 = Vector3.ZERO

## 意图：水平速度意图（y 恒为 0）；Movement 或 SwordFlight 写入，actor 消费。
var desired_horizontal: Vector3 = Vector3.ZERO

## 意图：竖直速度意图（米/秒，正上）；仅 SwordFlight 写入，actor 消费。
var desired_vertical: float = 0.0

## 意图：竖直冲量（米/秒，正上）；仅 Jump 写入，actor 覆盖 velocity.y 且不累加。
var vertical_impulse: float = 0.0

## 参数：步行水平最大速度（米/秒）。
@export var move_speed: float = 4.0

## 参数：起跳初速（米/秒）。
@export var jump_speed: float = 6.0

## 参数：非御剑时的重力加速度（米/秒^2），由 actor 统一施加。
@export var gravity: float = 18.0

## 参数：御剑水平最大速度（米/秒）。
@export var flight_speed: float = 12.0

## 参数：御剑上升速度（米/秒）。
@export var flight_lift_speed: float = 7.0

## 参数：御剑下降速度（米/秒）。
@export var flight_sink_speed: float = 7.0

## 参数：地面启动御剑的短促升起速度（米/秒）。
@export var flight_launch_speed: float = 3.0

## 参数：地面启动御剑的升起窗口（秒）。
@export var flight_launch_time: float = 0.25
