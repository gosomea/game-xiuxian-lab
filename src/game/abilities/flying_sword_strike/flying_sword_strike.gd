class_name FlyingSwordStrike
extends Capability

## 飞剑出击：选中 flying_sword 时左键按下边沿，本命剑离开悬浮位，沿上拱的弧线飞向指向点，
## 到达后折返飞回悬浮位；去程与回程各对沿途木桩命中一次。
##
## 剑在外期间登记 sword_away_block（御剑读它不起飞）；御剑期间（sword_flight_block）不能出击。
## 剑的位置与剑尖方向写进 SwordCastComponent，悬浮本命剑表现只读。参数全部在组件。
## 阻塞清账三条路径：飞回失活 / 组件缺失 / 节点退出场景树。

enum Phase { OUT, BACK, DONE }

## 飞剑落点离地高度（米），约在木桩腰部。
const TARGET_HEIGHT := 0.9

var _phase: Phase = Phase.DONE
var _start := Vector3.ZERO
var _control := Vector3.ZERO
var _target := Vector3.ZERO
var _progress := 0.0
var _length := 1.0
var _hit_out: Dictionary = {}
var _hit_back: Dictionary = {}
var _host_ref: Node = null
var _cast_ref: SwordCastComponent = null


func _init() -> void:
	priority = 45


func _should_activate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var host := game_object()
	if cast == null or host == null:
		return false
	if cast.form != SwordCastComponent.FORM_STRIKE or not cast.cast_pressed or cast.sword_away:
		return false
	return not TagRegistry.is_blocked(host, &"sword_flight_block")


func _on_activated() -> void:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var host := game_object() as Node3D
	if cast == null or host == null:
		_phase = Phase.DONE
		return
	_host_ref = host
	_cast_ref = cast
	var origin := host.global_position
	var flat := cast.aim_point - origin
	flat.y = 0.0
	if flat.length_squared() < 0.09:
		var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
		flat = (motion.aim_direction if motion != null else Vector3.FORWARD) * 3.0
		flat.y = 0.0
	var direction := flat.normalized()
	var reach := clampf(flat.length(), 2.0, cast.strike_range)
	_start = cast.rest_position(origin, direction)
	_target = origin + direction * reach + Vector3.UP * TARGET_HEIGHT
	# 弧线略微上拱并偏向右手侧，飞出时能看出离手的弧度；拱高须让中途仍穿过木桩高度。
	var side := Vector3.UP.cross(direction).normalized()
	_control = (_start + _target) * 0.5 + Vector3.UP * (0.6 + reach * 0.04) - side * reach * 0.12
	_length = maxf(_start.distance_to(_control) + _control.distance_to(_target), 0.01)
	_progress = 0.0
	_hit_out = {}
	_hit_back = {}
	_phase = Phase.OUT
	cast.sword_away = true
	cast.sword_position = _start
	cast.sword_forward = (_control - _start).normalized()
	cast.record_cast(SwordCastComponent.FORM_STRIKE, direction, manager_time(), SwordCastComponent.POSE_THRUST)
	TagRegistry.add_block(host, &"sword_away_block", self)


func _tick_active(delta: float) -> void:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var host := game_object() as Node3D
	if cast == null or host == null or _phase == Phase.DONE:
		return
	var from := cast.sword_position
	var to := from
	if _phase == Phase.OUT:
		_progress = minf(_progress + cast.strike_speed * delta / _length, 1.0)
		to = _bezier(_progress)
		_strike(host, cast, from, to, _hit_out)
		if _progress >= 1.0:
			_phase = Phase.BACK
	else:
		var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
		var facing := motion.aim_direction if motion != null else cast.face_direction
		var home := cast.rest_position(host.global_position, facing)
		var offset := home - from
		var step := cast.strike_return_speed * delta
		if offset.length() <= step:
			to = home
			_phase = Phase.DONE
		else:
			to = from + offset.normalized() * step
		_strike(host, cast, from, to, _hit_back)
	if to.distance_squared_to(from) > 0.000001:
		cast.sword_forward = (to - from).normalized()
	cast.sword_position = to


func _should_deactivate() -> bool:
	return _phase == Phase.DONE or component(&"SwordCastComponent") == null


func _on_deactivated() -> void:
	_release()


func _exit_tree() -> void:
	_release()


func _strike(host: Node3D, cast: SwordCastComponent, from: Vector3, to: Vector3, already: Dictionary) -> void:
	for hit in SwordCastTargets.sweep(host.get_tree(), from, to, cast.strike_radius, already):
		(hit["target"] as SwordTargetComponent).record_hit(SwordCastComponent.FORM_STRIKE, hit["point"])
		already[hit["id"]] = true


func _bezier(t: float) -> Vector3:
	var a := _start.lerp(_control, t)
	var b := _control.lerp(_target, t)
	return a.lerp(b, t)


func _release() -> void:
	var cast := _cast_ref
	if cast == null or not is_instance_valid(cast):
		cast = component(&"SwordCastComponent") as SwordCastComponent
	if cast != null:
		cast.sword_away = false
	var host := _host_ref
	if host == null or not is_instance_valid(host):
		host = game_object()
	if host != null and is_instance_valid(host):
		TagRegistry.remove_block(host, &"sword_away_block", self)
	_phase = Phase.DONE
	_host_ref = null
	_cast_ref = null
