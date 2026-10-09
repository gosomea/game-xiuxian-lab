class_name HeavenlySwordRain
extends Capability

## 选区→上空聚剑→停悬→三批加速落剑→尖端接地→散阵。
## 数值全部由独立 Component 提供；实际剑尖轨迹直接输出给视图并参与 sweep。
## 松手立即锁区，即使快速点击仍完成聚剑。释放后换招可继续，后台不写人物姿势。

const GOLDEN_ANGLE := 2.3999632297

enum Phase { GATHER, HOVER, RAIN, DISSIPATE, DONE }
enum State { HOVER, FALL, LANDED }

var _phase: Phase = Phase.DONE
var _swords: Array = []
var _impacts: Array = []
var _started_at: float = 0.0
var _phase_at: float = 0.0
var _rain_at: float = 0.0
var _ready_at: float = 0.0
var _generation: int = 0
var _cast_ref: SwordCastComponent = null
var _rain_ref: HeavenlySwordRainComponent = null


func _init() -> void:
	priority = 40


func _should_activate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var rain := component(&"HeavenlySwordRainComponent") as HeavenlySwordRainComponent
	return cast != null and rain != null and cast.form == SwordCastComponent.FORM_RAIN \
		and cast.cast_pressed and cast.aim_surface_valid and manager_time() >= _ready_at


func _on_activated() -> void:
	_cast_ref = component(&"SwordCastComponent") as SwordCastComponent
	_rain_ref = component(&"HeavenlySwordRainComponent") as HeavenlySwordRainComponent
	var host := game_object() as Node3D
	assert(_cast_ref != null and _rain_ref != null and host != null, "天降剑雨需要三维宿主与两项组件")
	var rain := _rain_ref
	_generation = _cast_ref.cancel_generation
	_started_at = manager_time()
	_phase_at = _started_at
	_phase = Phase.GATHER
	_swords = []
	_impacts = []
	rain.released = false
	rain.batches_launched = 0
	rain.swords_landed = 0
	rain.ground_center = _cast_ref.aim_surface_point
	rain.ground_normal = _normal(_cast_ref.aim_surface_normal)
	rain.ceiling_center = rain.ground_center + Vector3.UP * rain.ceiling_height
	var count := maxi(3, rain.sword_count)
	var batches := mini(count, maxi(3, rain.batch_count))
	for slot in range(count):
		var batch := slot % batches
		var offset := _slot_offset(slot, count, rain.region_radius)
		var tip := rain.ceiling_center + offset * 0.82
		_swords.append({"slot": slot, "batch": batch, "rank": slot / batches,
			"offset": offset, "tip": tip, "start": tip, "forward": Vector3.DOWN,
			"state": State.HOVER, "target": rain.ground_center + offset,
			"normal": rain.ground_normal, "launch_at": 0.0, "landed_at": 0.0,
			"trail": [], "hit": {}, "alpha": 0.0, "scale": rain.sword_scale})
	_cast_ref.record_cast(SwordCastComponent.FORM_RAIN, _direction(host), manager_time(),
		SwordCastComponent.POSE_RAIN)
	_publish(manager_time())


func _tick_active(delta: float) -> void:
	if _cast_ref == null or _rain_ref == null or _phase == Phase.DONE:
		return
	var cast := _cast_ref
	var rain := _rain_ref
	var host := game_object() as Node3D
	if cast.cancel_generation != _generation or host == null:
		_finish()
		return
	var now := manager_time()
	if _phase == Phase.GATHER:
		if not rain.released:
			if cast.form != SwordCastComponent.FORM_RAIN:
				_finish()
				return
			if cast.aim_surface_valid:
				var alpha := 1.0 - exp(-rain.follow_rate * delta)
				rain.ground_center = rain.ground_center.lerp(cast.aim_surface_point, alpha)
				rain.ground_normal = _normal(rain.ground_normal.lerp(cast.aim_surface_normal, alpha))
			if cast.cast_released or not cast.cast_held:
				_lock_targets(host)
		_update_hover(now)
		if rain.released and now - _started_at >= rain.gather_time:
			_phase = Phase.HOVER
			_phase_at = now
	elif _phase == Phase.HOVER:
		_update_hover(now)
		if now - _phase_at >= rain.hover_time:
			_phase = Phase.RAIN
			_phase_at = now
			_rain_at = now
			for sword in _swords:
				sword["start"] = sword["tip"]
				sword["launch_at"] = now + int(sword["batch"]) * rain.batch_interval \
					+ int(sword["rank"]) * rain.sword_stagger
	if _phase == Phase.RAIN:
		_advance_rain(now, host)
		if _swords.is_empty():
			_phase = Phase.DISSIPATE
			_phase_at = now
	elif _phase == Phase.DISSIPATE and now - _phase_at >= rain.fade_time:
		_finish()
	_update_impacts(now)
	_update_pose(host, now)
	_publish(now)


func _should_deactivate() -> bool:
	return _phase == Phase.DONE or component(&"SwordCastComponent") == null \
		or component(&"HeavenlySwordRainComponent") == null


func _on_deactivated() -> void:
	_ready_at = manager_time() + (_rain_ref.cooldown if is_instance_valid(_rain_ref) else 0.0)
	_clear()


func _exit_tree() -> void:
	_clear()


func _update_hover(now: float) -> void:
	var rain := _rain_ref
	var age := now - _started_at
	rain.ceiling_center = rain.ground_center + Vector3.UP * rain.ceiling_height
	for sword in _swords:
		var offset: Vector3 = sword["offset"]
		var bob := sin(age * 2.0 + int(sword["slot"]) * 0.7) * 0.045
		# 剑尖围绕既定落区聚齐，向下略内倾。只有悬停段有轻微浮动。
		var rise := 0.30 * (1.0 - _smooth(clampf(age / maxf(rain.gather_time, 0.001), 0.0, 1.0)))
		sword["tip"] = rain.ceiling_center + offset * 0.82 + Vector3.UP * (bob + rise)
		var target: Vector3 = sword["target"] if rain.released else rain.ground_center + offset
		sword["forward"] = (target - (sword["tip"] as Vector3)).normalized()
		var stagger := float(sword["slot"]) / maxf(float(_swords.size()), 1.0) * 0.30
		sword["alpha"] = _smooth(clampf((age - stagger) / maxf(rain.gather_time - 0.30, 0.05), 0.0, 1.0))


func _lock_targets(host: Node3D) -> void:
	var rain := _rain_ref
	rain.released = true
	# 锁定当前可见选区，避免指针快速移动时落区突然跳变。
	for sword in _swords:
		var flat := rain.ground_center + (sword["offset"] as Vector3)
		var contact := _ground_contact(host, flat, rain.ground_center, rain.ground_normal)
		sword["target"] = contact["point"]
		sword["normal"] = contact["normal"]


func _ground_contact(host: Node3D, flat: Vector3, center: Vector3, normal: Vector3) -> Dictionary:
	# 一次锁区采样，不逐帧查询物理。无碰撞的无头夹具使用所选地面平面。
	var point := flat
	if absf(normal.y) > 0.0001:
		point.y = center.y - (normal.x * (flat.x - center.x) + normal.z * (flat.z - center.z)) / normal.y
	var world := host.get_world_3d()
	if world != null:
		var ray := PhysicsRayQueryParameters3D.create(flat + Vector3.UP * (_rain_ref.ceiling_height + 8.0),
			flat + Vector3.DOWN * 24.0, 2)
		if host is CollisionObject3D:
			ray.exclude = [(host as CollisionObject3D).get_rid()]
		var hit := world.direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			return {"point": hit["position"], "normal": _normal(hit["normal"])}
	return {"point": point, "normal": normal}


func _advance_rain(now: float, host: Node3D) -> void:
	var rain := _rain_ref
	var alive: Array = []
	for sword in _swords:
		var state: State = sword["state"]
		if state == State.HOVER and now >= float(sword["launch_at"]):
			sword["state"] = State.FALL
			state = State.FALL
			rain.batches_launched = maxi(rain.batches_launched, int(sword["batch"]) + 1)
		if state == State.FALL:
			var from: Vector3 = sword["tip"]
			var u := clampf((now - float(sword["launch_at"])) / maxf(rain.fall_time, 0.001), 0.0, 1.0)
			var start: Vector3 = sword["start"]
			var target: Vector3 = sword["target"]
			var side := (sword["offset"] as Vector3).normalized() * rain.bend_distance
			var to := start.lerp(target, u * u) + side * (4.0 * u * u * (1.0 - u) * (1.0 - u))
			var tangent := (target - start) * (2.0 * maxf(u, 0.0001)) \
				+ side * (8.0 * u * (1.0 - u) * (1.0 - 2.0 * u))
			sword["forward"] = tangent.normalized()
			for hit in SwordCastTargets.sweep(host.get_tree(), from, to, rain.hit_radius, sword["hit"]):
				(hit["target"] as SwordTargetComponent).record_hit(SwordCastComponent.FORM_RAIN, hit["point"])
				(sword["hit"] as Dictionary)[hit["id"]] = true
			sword["tip"] = to
			sword["alpha"] = 1.0
			var trail: Array = sword["trail"]
			trail.append(to)
			if trail.size() > 8:
				trail.pop_front()
			if u >= 1.0:
				sword["state"] = State.LANDED
				sword["landed_at"] = now
				sword["tip"] = target
				rain.swords_landed += 1
				_impacts.append({"position": target, "normal": sword["normal"], "time": now})
				# 每批一次轻反馈；没有 TimeKeeper 顿帧请求。
				if int(sword["rank"]) == 0:
					_cast_ref.record_feedback(target, 0.12)
		elif state == State.LANDED:
			var age := now - float(sword["landed_at"])
			sword["alpha"] = 1.0 - _smooth(clampf((age - rain.linger_time) / maxf(rain.fade_time, 0.001), 0.0, 1.0))
			if age > 0.10:
				sword["trail"] = []
			if age >= rain.linger_time + rain.fade_time:
				continue
		alive.append(sword)
	_swords = alive


func _update_impacts(now: float) -> void:
	var alive: Array = []
	for impact in _impacts:
		if now - float(impact["time"]) <= _rain_ref.fade_time:
			alive.append(impact)
	_impacts = alive


func _update_pose(host: Node3D, now: float) -> void:
	if _phase == Phase.DONE or _cast_ref.form != SwordCastComponent.FORM_RAIN:
		return
	var cast := _cast_ref
	cast.face_direction = _direction(host)
	cast.face_until = now + cast.pose_time
	cast.pose_kind = SwordCastComponent.POSE_RAIN
	# 停悬不提前下压；释放进度跨收势保持单调，避免每次阶段切换手臂重新举起。
	cast.pose_phase = "gather" if _phase in [Phase.GATHER, Phase.HOVER] else "release"
	cast.pose_progress = 1.0 if _phase == Phase.DISSIPATE else _phase_progress(now)
	cast.pose_weight = 1.0 - _phase_progress(now) if _phase == Phase.DISSIPATE else 1.0


func _publish(now: float) -> void:
	if not is_instance_valid(_rain_ref) or _phase == Phase.DONE:
		return
	var rain := _rain_ref
	rain.phase = ["gather", "hover", "rain", "dissipate", "idle"][_phase]
	rain.progress = _phase_progress(now)
	rain.ring_angle = (now - _started_at) * 0.34
	rain.ring_alpha = _smooth(clampf((now - _started_at) / maxf(rain.gather_time * 0.6, 0.001), 0.0, 1.0))
	if _phase == Phase.DISSIPATE:
		rain.ring_alpha *= 1.0 - _smooth(rain.progress)
	var view: Array = []
	for sword in _swords:
		view.append({"slot": sword["slot"], "batch": sword["batch"], "tip": sword["tip"],
			"forward": sword["forward"], "scale": sword["scale"], "alpha": sword["alpha"],
			"state": ["hover", "fall", "landed"][int(sword["state"])],
			"trail": (sword["trail"] as Array).duplicate(), "target": sword["target"]})
	rain.swords = view
	var impacts: Array = []
	for impact in _impacts:
		var u := clampf((now - float(impact["time"])) / maxf(rain.fade_time, 0.001), 0.0, 1.0)
		impacts.append({"position": impact["position"], "normal": impact["normal"],
			"progress": u, "alpha": 1.0 - u})
	rain.impacts = impacts


func _phase_progress(now: float) -> float:
	var rain := _rain_ref
	if _phase == Phase.GATHER:
		return clampf((now - _started_at) / maxf(rain.gather_time, 0.001), 0.0, 1.0)
	if _phase == Phase.HOVER:
		return clampf((now - _phase_at) / maxf(rain.hover_time, 0.001), 0.0, 1.0)
	if _phase == Phase.RAIN:
		var batches := mini(maxi(3, rain.sword_count), maxi(3, rain.batch_count))
		return clampf((now - _rain_at) / maxf((batches - 1) * rain.batch_interval + rain.fall_time, 0.001), 0.0, 1.0)
	return clampf((now - _phase_at) / maxf(rain.fade_time, 0.001), 0.0, 1.0)


func _direction(host: Node3D) -> Vector3:
	var flat := _rain_ref.ground_center - host.global_position
	flat.y = 0.0
	return flat.normalized() if flat.length_squared() > 0.001 else Vector3.FORWARD


func _slot_offset(slot: int, count: int, radius: float) -> Vector3:
	if slot == 0:
		return Vector3.ZERO
	var r := radius * sqrt(float(slot) / maxf(float(count - 1), 1.0))
	var angle := slot * GOLDEN_ANGLE
	return Vector3(cos(angle), 0.0, sin(angle)) * r


func _normal(normal: Vector3) -> Vector3:
	return normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP


func _smooth(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


func _finish() -> void:
	_phase = Phase.DONE
	_clear_view()


func _clear_view() -> void:
	_swords = []
	_impacts = []
	if is_instance_valid(_cast_ref) and _cast_ref.form == SwordCastComponent.FORM_RAIN \
			and _cast_ref.pose_kind == SwordCastComponent.POSE_RAIN:
		_cast_ref.pose_weight = 0.0
		_cast_ref.face_until = manager_time()
	if is_instance_valid(_rain_ref):
		_rain_ref.swords = []
		_rain_ref.impacts = []
		_rain_ref.phase = "idle"
		_rain_ref.progress = 0.0
		_rain_ref.ring_alpha = 0.0
		_rain_ref.released = false


func _clear() -> void:
	_phase = Phase.DONE
	_clear_view()
	_cast_ref = null
	_rain_ref = null
