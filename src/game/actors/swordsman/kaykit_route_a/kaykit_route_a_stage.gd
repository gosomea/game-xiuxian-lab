extends Node3D
## 路线 A 独立演示台：可单独启动，直接观察 KayKit 原生骨架 + 76 clips 的动作映射。
##
## 本节点是表现层的**显式驱动方**（不读物理、不接 Swordsman），用键盘切换 motion_mode，
## 从而在一次运行内目视对照 idle / walk / run / airborne / flight 五态与御剑前倾。
##
## 键位：1=idle  2=walk  3=run  4=airborne  5=flight  0=reset  Esc=退出

@export var walk_speed: float = 2.0
@export var run_speed: float = 7.0
@export var flight_speed: float = 12.0

var _presentation: KaykitRouteAPresentation


func _ready() -> void:
	_presentation = get_node_or_null(
		"KaykitRouteAVisual/KaykitRouteAPresentation") as KaykitRouteAPresentation
	assert(_presentation != null, "演示台缺少 KaykitRouteAPresentation")
	_presentation.reset_pose()
	_print_help()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: _drive(KaykitRouteAPresentation.MODE_GROUND, 0.0, true)
			KEY_2: _drive(KaykitRouteAPresentation.MODE_GROUND, walk_speed, true)
			KEY_3: _drive(KaykitRouteAPresentation.MODE_GROUND, run_speed, true)
			KEY_4: _drive(KaykitRouteAPresentation.MODE_AIR, 0.0, false)
			KEY_5: _drive(KaykitRouteAPresentation.MODE_FLIGHT, flight_speed, false)
			KEY_0:
				_presentation.reset_pose()
				print("ROUTE_A_DEMO reset")
			KEY_ESCAPE: get_tree().quit()


func _drive(mode: String, speed: float, grounded: bool) -> void:
	_presentation.set_motion_state(mode, speed, grounded)
	var pose := _presentation.pose_state()
	print("ROUTE_A_DEMO mode=%s speed=%.2f clip=%s rate=%.2f lean=%.3f hidden=%s" % [
		mode, speed, pose.get("current_clip", "?"), float(pose.get("play_rate", 0.0)),
		float(pose.get("lean_target", 0.0)), str(pose.get("hidden_parts", []))])


func _print_help() -> void:
	print("ROUTE_A_DEMO 键位：1=idle  2=walk  3=run  4=airborne  5=flight  0=reset  Esc=退出")
