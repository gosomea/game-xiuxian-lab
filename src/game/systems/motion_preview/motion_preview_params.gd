class_name MotionPreviewParams
extends RefCounted

## 动作预览剖面的物理参数（纯数据，无节点、无生命周期）。
##
## 依据 notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md「动作工作台与动作库（S2）」。
##
## 存在理由：跳跃抛物线 v = jump_speed − gravity·t 与御剑升 / 降速度如果写死在预览包里，
## 组件导出参数（SwordsmanMotionComponent.jump_speed / gravity / flight_lift_speed / flight_sink_speed）
## 一旦调整，预览剖面就会与真实运动分叉——预览会显示一个游戏里不存在的手感。
## 因此由工作台在装配预览实例时**一次性注入**这些参数；独立单测使用这里的默认值。
##
## 默认值与 docs/experiments/traversal-contract.md 的组件默认值一致：
## jump_speed=6.0、gravity=18.0、flight_lift_speed=7.0、flight_sink_speed=7.0、move_speed=4.0。

## 起跳初速（米/秒）。对应组件 jump_speed。
var jump_speed: float = 6.0
## 非御剑重力（米/秒²）。对应组件 gravity。
var gravity: float = 18.0
## 御剑上升速度（米/秒）。对应组件 flight_lift_speed。
var lift_speed: float = 7.0
## 御剑下降速度（米/秒）。对应组件 flight_sink_speed。
var sink_speed: float = 7.0
## 水平速度参考（米/秒）。对应组件 move_speed；动作 speed_factor 是它的倍率。
var move_speed: float = 4.0


## 从组件导出参数构造：工作台用它把真实运动参数注入预览，避免两套数值。
static func from_motion(motion: SwordsmanMotionComponent) -> MotionPreviewParams:
	var params := MotionPreviewParams.new()
	if motion == null:
		return params
	params.jump_speed = motion.jump_speed
	params.gravity = motion.gravity
	params.lift_speed = motion.flight_lift_speed
	params.sink_speed = motion.flight_sink_speed
	params.move_speed = motion.move_speed
	return params


## 跳跃剖面的理论飞行时长（秒）：v 从 +jump_speed 落到 −jump_speed 所需时间 2j/g。
func jump_flight_seconds() -> float:
	return 2.0 * jump_speed / maxf(gravity, 0.001)
