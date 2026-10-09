class_name GiantSwordDescent
extends Capability

## 巨剑镇落：凝剑→锁点悬停/上提→加速镇落→一次冲击→残影消散。
## 蓄势换招取消，释放后换招仍继续；所有时序读 manager_time()。
## 贯穿与落地范围共用同一命中账本，不重复登记同次镇落。

const HISTORY_LIMIT := 18

var _phase := "idle"
var _started_at := 0.0
var _phase_at := 0.0
var _impact_at := -1.0
var _ready_at := 0.0
var _cancel_generation := 0
var _release_pending := false
var _locked_point := Vector3.ZERO
var _locked_normal := Vector3.UP
var _hover_from := Vector3.ZERO
var _hover_forward := Vector3.DOWN
var _rune_from := Vector3.ZERO
var _rune_normal_from := Vector3.UP
var _descent_from := Vector3.ZERO
var _hit: Dictionary = {}
var _cast_ref: SwordCastComponent
var _data_ref: GiantSwordDescentComponent


func _init() -> void:
	priority = 40


func _should_activate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var data := component(&"GiantSwordDescentComponent") as GiantSwordDescentComponent
	return cast != null and data != null and cast.form == SwordCastComponent.FORM_GIANT \
		and cast.cast_pressed and cast.aim_surface_valid and manager_time() >= _ready_at


func _on_activated() -> void:
	_cast_ref = component(&"SwordCastComponent") as SwordCastComponent
	_data_ref = component(&"GiantSwordDescentComponent") as GiantSwordDescentComponent
	assert(_cast_ref != null and _data_ref != null and game_object() is Node3D,
		"GiantSwordDescent 需要地面选点契约、独立组件和 Node3D 宿主")
	var data := _data_ref
	assert(data.min_gather_time > 0.0 and data.hover_time > 0.0 and data.descent_time > 0.0 \
		and data.fade_time > 0.0 and data.sword_length_m > 0.0,
		"GiantSwordDescent 阶段时长和剑长必须为正数")
	data.clear_visual()
	_phase = "gather"
	_started_at = manager_time()
	_phase_at = _started_at
	_impact_at = -1.0
	_cancel_generation = _cast_ref.cancel_generation
	_release_pending = false
	_hit = {}
	data.target_point = _cast_ref.aim_surface_point
	data.target_normal = _normal(_cast_ref.aim_surface_normal)
	data.rune_point = data.target_point
	data.rune_normal = data.target_normal
	data.sword_tip = data.rune_point + Vector3.UP * data.hover_tip_height
	_cast_ref.record_cast(SwordCastComponent.FORM_GIANT, _aim_direction(), _started_at,
		SwordCastComponent.POSE_GIANT)


func _tick_active(delta: float) -> void:
	if not _dependencies_valid():
		_phase = "idle"
		return
	var cast := _cast_ref
	var data := _data_ref
	var now := manager_time()
	if cast.cancel_generation != _cancel_generation \
		or (_phase == "gather" and not _release_pending and not cast.released_for(SwordCastComponent.FORM_GIANT) and cast.form != SwordCastComponent.FORM_GIANT):
		_clear()
		return
	data.visual_time = now
	data.phase_elapsed = maxf(now - _phase_at, 0.0)
	match _phase:
		"gather":
			_gather(data, cast, now, delta)
		"hover":
			_hover(data, now)
		"descent":
			_descend(data, now)
		"impact":
			data.phase_progress = clampf(data.phase_elapsed / maxf(data.impact_hold_time, 0.001), 0.0, 1.0)
			data.impact_age = now - _impact_at
			if data.phase_progress >= 1.0:
				_set_phase("fade", now)
		"fade":
			var progress := clampf(data.phase_elapsed / data.fade_time, 0.0, 1.0)
			data.phase_progress = progress
			data.impact_age = now - _impact_at
			data.sword_alpha = pow(1.0 - progress, 1.6)
			data.rune_alpha = (1.0 - progress) * 0.5
			if progress >= 1.0:
				_phase = "idle"
	data.phase = _phase
	if cast.form == SwordCastComponent.FORM_GIANT and _phase != "idle":
		_write_pose(cast, data, now)


func _should_deactivate() -> bool:
	return _phase == "idle" or not _dependencies_valid()


func _on_deactivated() -> void:
	_ready_at = manager_time() + (_data_ref.cooldown if is_instance_valid(_data_ref) else 0.0)
	_clear()


func _exit_tree() -> void:
	_clear()


func _gather(data: GiantSwordDescentComponent, cast: SwordCastComponent,
		now: float, delta: float) -> void:
	var elapsed := now - _started_at
	var build := clampf(elapsed / data.min_gather_time, 0.0, 1.0)
	data.phase_progress = build
	data.charge = clampf(elapsed / maxf(data.full_charge_time, data.min_gather_time), 0.0, 1.0)
	if not _release_pending and cast.aim_surface_valid:
		data.target_point = cast.aim_surface_point
		data.target_normal = _normal(cast.aim_surface_normal)
		var follow := 1.0 - exp(-data.preview_follow_rate * delta)
		data.rune_point = data.rune_point.lerp(data.target_point, follow)
		data.rune_normal = _normal(data.rune_normal.lerp(data.target_normal, follow))
	data.sword_length = data.sword_length_m * lerpf(0.045, 1.0, _smooth(build))
	data.sword_alpha = _smooth(clampf(build * 1.7, 0.0, 1.0))
	data.rune_alpha = lerpf(0.25, 1.0, _smooth(build))
	var bob := sin(elapsed * 2.4) * 0.06 * build
	data.sword_tip = data.rune_point + Vector3.UP * (data.hover_tip_height + bob)
	data.sword_forward = Vector3(sin(elapsed * 1.1) * 0.025, -1.0,
		cos(elapsed * 1.3) * 0.018).normalized()
	if not _release_pending and (cast.released_for(SwordCastComponent.FORM_GIANT) or not cast.cast_held):
		_release_pending = true
		_locked_point = cast.aim_surface_point if cast.aim_surface_valid else data.target_point
		_locked_normal = _normal(cast.aim_surface_normal) if cast.aim_surface_valid else data.target_normal
		data.locked = true
		data.target_point = _locked_point
		data.target_normal = _locked_normal
	if _release_pending and build >= 1.0:
		_hover_from = data.sword_tip
		_hover_forward = data.sword_forward
		_rune_from = data.rune_point
		_rune_normal_from = data.rune_normal
		_set_phase("hover", now)


func _hover(data: GiantSwordDescentComponent, now: float) -> void:
	var progress := clampf((now - _phase_at) / data.hover_time, 0.0, 1.0)
	var ease := _smooth(progress)
	data.phase_progress = progress
	data.sword_length = data.sword_length_m
	data.sword_alpha = 1.0
	data.rune_alpha = 1.0
	data.rune_point = _rune_from.lerp(_locked_point, ease)
	data.rune_normal = _normal(_rune_normal_from.lerp(_locked_normal, ease))
	data.sword_tip = _hover_from.lerp(_locked_point + Vector3.UP *
		(data.hover_tip_height + data.hover_lift), ease)
	data.sword_forward = _hover_forward.lerp(Vector3.DOWN, ease).normalized()
	if progress >= 1.0:
		_descent_from = data.sword_tip
		data.tip_history = PackedVector3Array([data.sword_tip])
		_set_phase("descent", now)


func _descend(data: GiantSwordDescentComponent, now: float) -> void:
	var progress := clampf((now - _phase_at) / data.descent_time, 0.0, 1.0)
	var from := data.sword_tip
	var to := _descent_from.lerp(_locked_point, pow(progress, 3.0))
	data.phase_progress = progress
	data.sword_forward = Vector3.DOWN
	data.rune_alpha = lerpf(1.0, 0.5, progress)
	data.sword_tip = to
	data.tip_history.append(to)
	if data.tip_history.size() > HISTORY_LIMIT:
		data.tip_history.remove_at(0)
	_record_hits(SwordCastTargets.sweep((game_object() as Node3D).get_tree(), from, to,
		data.hit_radius, _hit))
	if progress >= 1.0:
		data.sword_tip = _locked_point
		_impact_at = now
		data.impact_age = 0.0
		data.impact_serial += 1
		_record_hits(SwordCastTargets.burst((game_object() as Node3D).get_tree(), _locked_point,
			data.shock_radius, data.shock_height, _hit))
		_cast_ref.record_feedback(_locked_point, 1.0)
		_set_phase("impact", now)


func _record_hits(hits: Array) -> void:
	for hit in hits:
		(hit["target"] as SwordTargetComponent).record_hit(SwordCastComponent.FORM_GIANT, hit["point"])
		_hit[hit["id"]] = true


func _write_pose(cast: SwordCastComponent, data: GiantSwordDescentComponent, now: float) -> void:
	cast.face_direction = _aim_direction()
	cast.face_until = now + cast.pose_time
	cast.pose_kind = SwordCastComponent.POSE_GIANT
	cast.pose_phase = _phase
	cast.pose_progress = data.phase_progress
	cast.pose_weight = 1.0 if _phase in ["gather", "hover", "descent"] else data.sword_alpha * 0.5


func _aim_direction() -> Vector3:
	var host := game_object() as Node3D
	var flat := _data_ref.target_point - host.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.001:
		var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
		flat = motion.aim_direction if motion != null else Vector3.FORWARD
		flat.y = 0.0
	return flat.normalized()


func _set_phase(next: String, now: float) -> void:
	_phase = next
	_phase_at = now
	_data_ref.phase_elapsed = 0.0
	_data_ref.phase_progress = 0.0


func _dependencies_valid() -> bool:
	return is_instance_valid(_cast_ref) and is_instance_valid(_data_ref) \
		and _cast_ref.get_parent() == game_object() and _data_ref.get_parent() == game_object()


func _clear() -> void:
	if is_instance_valid(_data_ref):
		_data_ref.clear_visual()
	if is_instance_valid(_cast_ref) and _cast_ref.form == SwordCastComponent.FORM_GIANT:
		_cast_ref.pose_weight = 0.0
		_cast_ref.face_until = -1.0
	_phase = "idle"
	_hit = {}
	_release_pending = false


static func _normal(value: Vector3) -> Vector3:
	return value.normalized() if value.length_squared() > 0.000001 else Vector3.UP


static func _smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
