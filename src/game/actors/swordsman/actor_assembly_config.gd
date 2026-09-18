class_name ActorAssemblyConfig
extends Resource

## 角色装配配置（S0）：显式声明本次装配启用哪些移动行为、是否同时装御剑视觉。
##
## 依据 notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md「局部装配适配器」：
## 装配由 ActorAssembly 按显式配置执行，支持 Move / Move+Jump / Move+Flight / all 四个子集。
## 本 Resource 只描述「要什么」，不持有节点、不做装配；配置不合法时由调用方显式报错，
## 不静默降级（见 validate()）。

## 启用水平移动（SwordsmanMovement）。
@export var move_enabled: bool = true
## 启用跳跃（Jump）。
@export var jump_enabled: bool = true
## 启用御剑飞行行为（SwordFlight）。
@export var flight_enabled: bool = true
## 御剑视觉随飞行行为一起装配（flying_sword.glb）。视觉是行为的表现，headless 裸装可关闭。
@export var flight_visual: bool = true


## 返回配置问题；合法时返回空字符串。调用方必须原样报错，不得吞掉。
func validate() -> String:
	if not move_enabled and not jump_enabled and not flight_enabled:
		return "move/jump/flight 不能全为 false（没有任何行为可装配）"
	if flight_visual and not flight_enabled:
		return "flight_visual=true 需要 flight_enabled=true（视觉依赖飞行行为）"
	return ""


## 诊断/日志用的一行描述。
func describe() -> String:
	return "move=%s jump=%s flight=%s flight_visual=%s" % [
		move_enabled, jump_enabled, flight_enabled, flight_visual,
	]


## 该配置是否请求了完全相同的启停集合（安装幂等判定用）。
func matches(other: ActorAssemblyConfig) -> bool:
	if other == null:
		return false
	return (
		move_enabled == other.move_enabled
		and jump_enabled == other.jump_enabled
		and flight_enabled == other.flight_enabled
		and flight_visual == other.flight_visual
	)
