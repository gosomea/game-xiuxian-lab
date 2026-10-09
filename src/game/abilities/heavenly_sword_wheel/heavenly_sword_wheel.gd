class_name HeavenlySwordWheel
extends Capability

## 天轮：双层圆轮凝剑，松开后转剑尖，交错分组沿上拱曲线加速齐射。
## 快点也形成六剑小轮；蓄势换招取消，释放后换招继续。全部状态存独立 Component。

const GOLDEN_ANGLE := 2.39996323

var _data_ref: HeavenlySwordWheelComponent


func _init() -> void:
	priority = 40


func _should_activate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var data := component(&"HeavenlySwordWheelComponent") as HeavenlySwordWheelComponent
	return cast != null and data != null and cast.form == SwordCastComponent.FORM_WHEEL \
		and cast.cast_pressed and manager_time() >= data.ready_at


func _on_activated() -> void:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var data := component(&"HeavenlySwordWheelComponent") as HeavenlySwordWheelComponent
	var host := game_object() as Node3D
	assert(cast != null and data != null and host != null, "天轮需要输入、独立数据与三维宿主")
	assert(data.max_swords >= data.inner_swords and data.inner_swords >= data.min_swords \
		and data.min_swords > 0 and data.group_size > 0, "天轮槽位和分组必须有效")
	assert(data.gather_interval > 0.0 and data.entry_time > 0.0 and data.turn_time > 0.0 \
		and data.min_flight_time > 0.0 and data.flight_speed > 0.0, "天轮时间与速度必须为正")
	_data_ref = data
	data.swords = []
	data.impacts = []
	data.phase = "gather"
	data.started_at = manager_time()
	data.phase_started_at = data.started_at
	data.logic_time = data.started_at
	data.release_requested = false
	data.cancel_generation_seen = cast.cancel_generation
	data.direction = _aim_direction(cast, host)
	data.center = host.global_position + Vector3.UP * data.center_height - data.direction * data.center_back
	data.ring_angle = 0.0
	data.ring_alpha = 0.0
	data.launched_total = 0
	data.completed_total = 0
	data.casts_total += 1
	for index in range(data.min_swords):
		_add_sword(data, index, data.started_at + index * data.gather_interval)
	data.next_spawn_at = data.started_at + data.min_swords * data.gather_interval
	cast.record_cast(SwordCastComponent.FORM_WHEEL, data.direction, manager_time(), SwordCastComponent.POSE_WHEEL)


func _tick_active(delta: float) -> void:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var data := component(&"HeavenlySwordWheelComponent") as HeavenlySwordWheelComponent
	var host := game_object() as Node3D
	if cast == null or data == null or host == null:
		return
	var now := manager_time()
	data.logic_time = now
	if data.phase == "gather":
		_gather(cast, data, host, now, delta)
	elif data.phase == "turn":
		_turn(data, now)
	elif data.phase == "volley":
		_volley(cast, data, host, now)
	data.impacts = data.impacts.filter(func(impact: Dictionary) -> bool:
		return now - float(impact["started_at"]) < data.impact_time)
	if cast.form == SwordCastComponent.FORM_WHEEL:
		_request_pose(cast, data, now)


func _should_deactivate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var data := component(&"HeavenlySwordWheelComponent") as HeavenlySwordWheelComponent
	return cast == null or data == null or data.phase == "idle" \
		or cast.cancel_generation != data.cancel_generation_seen \
		or (data.phase == "gather" and not data.release_requested and cast.form != SwordCastComponent.FORM_WHEEL)


func _on_deactivated() -> void:
	var data := _data_ref
	if data != null and is_instance_valid(data):
		if data.release_requested:
			data.ready_at = manager_time() + data.cooldown
		_clear(data)
	_data_ref = null


func _exit_tree() -> void:
	if _data_ref != null and is_instance_valid(_data_ref):
		_clear(_data_ref)
	_data_ref = null


func _gather(cast: SwordCastComponent, data: HeavenlySwordWheelComponent, host: Node3D,
		now: float, delta: float) -> void:
	if not data.release_requested:
		var direction := _aim_direction(cast, host)
		var turn_angle := wrapf(atan2(direction.x, direction.z) - atan2(data.direction.x, data.direction.z), -PI, PI)
		data.direction = data.direction.rotated(Vector3.UP, turn_angle * (1.0 - exp(-data.follow_rate * delta)))
		var desired_center := host.global_position + Vector3.UP * data.center_height - data.direction * data.center_back
		data.center = data.center.lerp(desired_center, 1.0 - exp(-data.follow_rate * delta))
		while data.swords.size() < data.max_swords and now >= data.next_spawn_at and cast.cast_held:
			_add_sword(data, data.swords.size(), data.next_spawn_at)
			data.next_spawn_at += data.gather_interval
		if cast.cast_released or not cast.cast_held:
			data.release_requested = true
			data.locked_target = cast.aim_surface_point if cast.aim_surface_valid else cast.aim_point
			data.locked_normal = cast.aim_surface_normal.normalized() if cast.aim_surface_valid else Vector3.UP
	data.ring_angle = (now - data.started_at) * data.wheel_spin
	data.ring_alpha = _smooth(clampf((now - data.started_at) / data.entry_time, 0.0, 1.0))
	var entry_complete := true
	for sword in data.swords:
		var progress := clampf((now - float(sword["born_at"])) / data.entry_time, 0.0, 1.0)
		_place_in_ring(data, sword, progress)
		entry_complete = entry_complete and progress >= 1.0
	if data.release_requested and entry_complete:
		_begin_turn(data, host, now)


func _add_sword(data: HeavenlySwordWheelComponent, index: int, born_at: float) -> void:
	var inner := index < data.inner_swords
	var slot := index if inner else index - data.inner_swords
	var count := data.inner_swords if inner else maxi(data.max_swords - data.inner_swords, 1)
	# 两两对置，再补间隙；首六剑均匀绕完整内圆，不成为半扇面。
	var half := int(count / 2)
	var ring_slot := slot
	if inner and count % 2 == 0:
		ring_slot = slot * 2 if slot < half else (slot - half) * 2 + 1
	elif not inner and count % data.group_size == 0:
		ring_slot = (slot % data.group_size) * int(count / data.group_size) + int(slot / data.group_size)
	var angle := float(ring_slot) * TAU / float(count)
	var sword := {"ring": 0 if inner else 1, "angle": angle, "born_at": born_at,
		"state": "gather", "position": data.center, "forward": data.direction,
		"scale": Vector3.ZERO, "alpha": 0.0, "hit_ids": {}, "trail": [],
		"curve_from": Vector3.ZERO, "control_a": Vector3.ZERO, "control_b": Vector3.ZERO,
		"curve_to": Vector3.ZERO, "target": Vector3.ZERO, "turn_from": Vector3.ZERO,
		"launch_forward": Vector3.ZERO, "launched_at": 0.0, "flight_time": 0.0, "settled_at": 0.0}
	_place_in_ring(data, sword, 0.0)
	data.swords.append(sword)


func _place_in_ring(data: HeavenlySwordWheelComponent, sword: Dictionary, progress: float) -> void:
	var ease := _smooth(progress)
	var sign_spin := 1.0 if int(sword["ring"]) == 0 else -1.0
	var radius := data.inner_radius if int(sword["ring"]) == 0 else data.outer_radius
	var phi := float(sword["angle"]) + data.ring_angle * sign_spin + data.entry_turn * (1.0 - ease) * sign_spin
	var right := data.direction.cross(Vector3.UP).normalized()
	var radial := right * cos(phi) + Vector3.UP * sin(phi)
	var tangent := (-right * sin(phi) + Vector3.UP * cos(phi)) * sign_spin
	sword["position"] = data.center + radial * (radius + data.entry_radius * (1.0 - ease)) \
		- data.direction * data.entry_back * (1.0 - ease)
	sword["forward"] = tangent.slerp(radial, ease).normalized()
	sword["scale"] = Vector3.ONE * data.display_scale * ease
	sword["alpha"] = ease


func _begin_turn(data: HeavenlySwordWheelComponent, host: Node3D, now: float) -> void:
	data.phase = "turn"
	data.phase_started_at = now
	var normal := data.locked_normal
	var ground_right := data.direction.cross(normal).normalized()
	if ground_right.length_squared() < 0.001:
		ground_right = Vector3.RIGHT
	var ground_forward := normal.cross(ground_right).normalized()
	for index in range(data.swords.size()):
		var sword: Dictionary = data.swords[index]
		var spread := data.landing_spread * sqrt((index + 0.5) / float(data.swords.size()))
		var angle := index * GOLDEN_ANGLE
		var target := data.locked_target + (ground_right * cos(angle) + ground_forward * sin(angle)) * spread
		var query := PhysicsRayQueryParameters3D.create(target + Vector3.UP * data.ground_probe_height,
			target - Vector3.UP * data.ground_probe_depth, 2)
		var ground := host.get_world_3d().direct_space_state.intersect_ray(query)
		var target_normal := data.locked_normal
		if not ground.is_empty():
			target = ground["position"]
			target_normal = ground["normal"]
		var start: Vector3 = sword["position"]
		var radial := (start - data.center).normalized()
		var flat_offset := target - start
		flat_offset.y = 0.0
		var flat_direction := flat_offset.normalized() if flat_offset.length_squared() > 0.001 else data.direction
		var tip_length := SwordSpellVisual.TIP_LENGTH * data.display_scale
		var forward_weight := clampf(flat_offset.length() / (tip_length * 2.0), 0.0, 1.0)
		# 高台也从上方接地；近点按距离缩短控制臂，防止曲线越过落点再反飞。
		var terminal := (flat_direction * forward_weight - target_normal * data.terminal_drop).normalized()
		var endpoint := target - terminal * SwordSpellVisual.TIP_LENGTH * data.display_scale
		var span := maxf((endpoint - start).dot(flat_direction), 0.0)
		var lift := maxf(data.curve_lift, target.y - start.y + data.curve_lift)
		var control_a := start + flat_direction * minf(data.curve_forward, span * 0.35) \
			+ Vector3.UP * lift + radial * minf(data.curve_outward, span * 0.18)
		var approach := minf(data.curve_approach, maxf(0.1, span * 0.45))
		sword["target"] = target
		sword["normal"] = target_normal
		sword["curve_from"] = start
		sword["control_a"] = control_a
		sword["control_b"] = endpoint - terminal * approach
		sword["curve_to"] = endpoint
		sword["turn_from"] = sword["forward"]
		sword["launch_forward"] = (control_a - start).normalized()
		var path_estimate := start.distance_to(control_a) + control_a.distance_to(sword["control_b"]) \
			+ (sword["control_b"] as Vector3).distance_to(endpoint)
		sword["flight_time"] = maxf(data.min_flight_time, path_estimate * data.acceleration_power / data.flight_speed)
		sword["launched_at"] = now + data.turn_time + int(index / data.group_size) * data.group_interval
		sword["state"] = "turn"


func _turn(data: HeavenlySwordWheelComponent, now: float) -> void:
	var progress := clampf((now - data.phase_started_at) / data.turn_time, 0.0, 1.0)
	for sword in data.swords:
		sword["forward"] = (sword["turn_from"] as Vector3).slerp(sword["launch_forward"], _smooth(progress)).normalized()
	if progress >= 1.0:
		data.phase = "volley"
		data.phase_started_at = now


func _volley(cast: SwordCastComponent, data: HeavenlySwordWheelComponent, host: Node3D, now: float) -> void:
	var alive: Array = []
	var waiting := 0
	for sword in data.swords:
		if sword["state"] == "turn":
			if now < float(sword["launched_at"]):
				waiting += 1
				alive.append(sword)
				continue
			sword["state"] = "fly"
			data.launched_total += 1
		if sword["state"] == "fly":
			_fly(cast, data, host, sword, now)
		if sword["state"] == "settle":
			var fade := clampf((now - float(sword["settled_at"])) / data.settle_time, 0.0, 1.0)
			sword["alpha"] = 1.0 - _smooth(fade)
			if fade >= 1.0:
				data.completed_total += 1
				continue
		alive.append(sword)
	data.swords = alive
	data.ring_alpha = _smooth(float(waiting) / float(maxi(data.max_swords, 1)))
	if data.swords.is_empty() and data.impacts.is_empty():
		data.phase = "idle"


func _fly(cast: SwordCastComponent, data: HeavenlySwordWheelComponent, host: Node3D,
		sword: Dictionary, now: float) -> void:
	var progress := clampf((now - float(sword["launched_at"])) / float(sword["flight_time"]), 0.0, 1.0)
	var u := pow(progress, data.acceleration_power)
	var from: Vector3 = sword["position"]
	var to := _curve(sword, u)
	var tangent := _curve_tangent(sword, u).normalized()
	var old_tip := from + (sword["forward"] as Vector3) * SwordSpellVisual.TIP_LENGTH * data.display_scale
	var new_tip := to + tangent * SwordSpellVisual.TIP_LENGTH * data.display_scale
	for hit in SwordCastTargets.sweep(host.get_tree(), old_tip, new_tip, data.hit_radius, sword["hit_ids"]):
		(hit["target"] as SwordTargetComponent).record_hit(SwordCastComponent.FORM_WHEEL, hit["point"])
		(sword["hit_ids"] as Dictionary)[hit["id"]] = true
		cast.record_feedback(hit["point"], data.feedback_strength)
	sword["position"] = to
	sword["forward"] = tangent
	var trail: Array = sword["trail"]
	if trail.is_empty() or (trail[-1] as Vector3).distance_to(to) >= data.trail_step:
		trail.append(to)
		while trail.size() > data.trail_samples:
			trail.pop_front()
	if progress >= 1.0:
		sword["state"] = "settle"
		sword["settled_at"] = now
		data.impacts.append({"point": sword["target"], "normal": sword["normal"], "started_at": now})


func _request_pose(cast: SwordCastComponent, data: HeavenlySwordWheelComponent, now: float) -> void:
	if data.phase == "gather" or data.phase == "turn":
		cast.face_direction = data.direction
		cast.face_until = now + cast.pose_time
		cast.pose_weight = 1.0
		cast.pose_kind = SwordCastComponent.POSE_WHEEL
		cast.pose_phase = "gather" if data.phase == "gather" else "release"
		cast.pose_progress = clampf((now - data.phase_started_at) / data.turn_time, 0.0, 1.0)
	elif data.phase == "volley" and now - data.phase_started_at < cast.pose_time:
		cast.face_direction = data.direction
		cast.face_until = now + cast.pose_time
		cast.pose_weight = 1.0
		cast.pose_kind = SwordCastComponent.POSE_WHEEL
		cast.pose_phase = "release"
		cast.pose_progress = 1.0


func _aim_direction(cast: SwordCastComponent, host: Node3D) -> Vector3:
	var flat := cast.aim_point - host.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.001:
		var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
		flat = motion.aim_direction if motion != null else Vector3.FORWARD
		flat.y = 0.0
	return flat.normalized()


static func _curve(sword: Dictionary, u: float) -> Vector3:
	var v := 1.0 - u
	return (sword["curve_from"] as Vector3) * v * v * v \
		+ (sword["control_a"] as Vector3) * 3.0 * v * v * u \
		+ (sword["control_b"] as Vector3) * 3.0 * v * u * u \
		+ (sword["curve_to"] as Vector3) * u * u * u


static func _curve_tangent(sword: Dictionary, u: float) -> Vector3:
	var v := 1.0 - u
	return ((sword["control_a"] as Vector3) - (sword["curve_from"] as Vector3)) * 3.0 * v * v \
		+ ((sword["control_b"] as Vector3) - (sword["control_a"] as Vector3)) * 6.0 * v * u \
		+ ((sword["curve_to"] as Vector3) - (sword["control_b"] as Vector3)) * 3.0 * u * u


static func _smooth(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


static func _clear(data: HeavenlySwordWheelComponent) -> void:
	data.phase = "idle"
	data.swords = []
	data.impacts = []
	data.ring_alpha = 0.0
