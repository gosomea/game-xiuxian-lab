class_name SwordQi
extends Capability

## 剑气：选中 sword_qi 时左键按下边沿，从身前朝指向点放出一道剑气；沿地面水平飞行，
## 穿过沿途木桩各命中一次，飞满射程后消散。
##
## 剑气是本能力持有的数据，逐 tick 推进并写进 SwordCastComponent.qi_shots；视图只读它绘制。
## 有剑气在飞或刚按下时保持激活；冷却读 manager_time()。参数全部在 SwordCastComponent。

## 下一次可出剑气的逻辑时刻。
var _ready_at: float = 0.0
var _cancel_generation := 0
var _cast_ref: SwordCastComponent = null


func _init() -> void:
	priority = 40


func _should_activate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	return cast != null and (_wants_cast(cast) or not cast.qi_shots.is_empty())


func _on_activated() -> void:
	_cast_ref = component(&"SwordCastComponent") as SwordCastComponent


func _tick_active(delta: float) -> void:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var host := game_object() as Node3D
	if cast == null or host == null:
		return
	if not cast.qi_shots.is_empty() and _cancel_generation != cast.cancel_generation:
		cast.qi_shots = []
		return
	if _wants_cast(cast):
		_cancel_generation = cast.cancel_generation
		_spawn(cast, host)
	var alive: Array = []
	for value in cast.qi_shots:
		var shot: Dictionary = value
		var from: Vector3 = shot["position"]
		var step := minf(cast.qi_speed * delta, cast.qi_range - float(shot["travelled"]))
		var to: Vector3 = from + (shot["direction"] as Vector3) * step
		var already: Dictionary = shot["hit"]
		for hit in SwordCastTargets.sweep(host.get_tree(), from, to, cast.qi_radius, already):
			(hit["target"] as SwordTargetComponent).record_hit(SwordCastComponent.FORM_QI, hit["point"])
			already[hit["id"]] = true
		shot["position"] = to
		shot["travelled"] = float(shot["travelled"]) + step
		if float(shot["travelled"]) < cast.qi_range - 0.0001:
			alive.append(shot)
	cast.qi_shots = alive


func _should_deactivate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	return cast == null or cast.qi_shots.is_empty()


func _on_deactivated() -> void:
	_cast_ref = null


func _exit_tree() -> void:
	var cast := _cast_ref
	if cast != null and is_instance_valid(cast):
		cast.qi_shots = []


func _wants_cast(cast: SwordCastComponent) -> bool:
	return cast.form == SwordCastComponent.FORM_QI and cast.cast_pressed and manager_time() >= _ready_at


func _spawn(cast: SwordCastComponent, host: Node3D) -> void:
	var origin := host.global_position
	var direction := cast.aim_point - origin
	direction.y = 0.0
	if direction.length_squared() < 0.09:
		var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
		direction = motion.aim_direction if motion != null else Vector3.FORWARD
		direction.y = 0.0
	direction = direction.normalized()
	cast.qi_shots.append({
		"position": origin + Vector3.UP * cast.qi_height + direction * 0.5,
		"direction": direction,
		"travelled": 0.0,
		"hit": {},
	})
	cast.record_cast(SwordCastComponent.FORM_QI, direction, manager_time(), SwordCastComponent.POSE_THRUST)
	_ready_at = manager_time() + cast.qi_cooldown
