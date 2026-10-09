class_name SwordArray
extends Capability

## 剑阵：选中 sword_array 时按住左键，飞剑一把把在身后排成扇面悬停（剑尖朝指向方向）；
## 松开后按间隔逐把射向松开时的指向点，落点按黄金角散布；每把剑对沿途木桩各命中一次，
## 落地后短暂停留再消散。全部消散后进入冷却。
##
## 剑是本能力持有的数据，位置与朝向写进 SwordCastComponent.array_swords；视图只读它绘制。
## 时序全部读 manager_time()；参数全部在组件。

enum Phase { GATHER, FIRE, DONE }
enum State { HOVER, FLY, STUCK }

## 扇面每排的剑数、排距与离身距离（米）。
const ROW_SIZE := 12
const FAN_HALF_WIDTH := 1.5
const ROW_LIFT := 0.42
const ROW_BACK := 0.28
const FAN_HEIGHT := 1.95
const FAN_BACK := 0.85
## 落地后停留的时长（秒）。
const STUCK_TIME := 0.6
const GOLDEN_ANGLE := 2.39996323

var _cancel_generation := 0
var _phase: Phase = Phase.DONE
var _swords: Array = []
var _next_spawn := 0.0
var _next_fire := 0.0
var _volley_target := Vector3.ZERO
var _ready_at := 0.0
var _cast_ref: SwordCastComponent = null


func _init() -> void:
	priority = 40


func _should_activate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	return cast != null and cast.form == SwordCastComponent.FORM_ARRAY and cast.cast_pressed \
		and manager_time() >= _ready_at


func _on_activated() -> void:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var host := game_object() as Node3D
	if cast == null or host == null:
		_phase = Phase.DONE
		return
	_cast_ref = cast
	_cancel_generation = cast.cancel_generation
	_swords = []
	_phase = Phase.GATHER
	_next_spawn = manager_time()
	cast.record_cast(SwordCastComponent.FORM_ARRAY, _aim_direction(cast, host), manager_time(),
		SwordCastComponent.POSE_RAISE)


func _tick_active(delta: float) -> void:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	var host := game_object() as Node3D
	if cast == null or host == null or _phase == Phase.DONE:
		return
	var now := manager_time()
	var direction := _aim_direction(cast, host)
	if _phase == Phase.GATHER:
		while _swords.size() < cast.array_max and now >= _next_spawn:
			_swords.append({"state": State.HOVER, "slot": _swords.size(), "position": Vector3.ZERO,
				"forward": direction, "hit": {}, "stuck_until": 0.0, "target": Vector3.ZERO})
			_next_spawn += cast.array_spawn_interval
		if cast.form == SwordCastComponent.FORM_ARRAY:
			cast.face_direction = direction
			cast.face_until = now + cast.pose_time
			cast.pose_kind = SwordCastComponent.POSE_RAISE
			cast.pose_weight = 1.0
		if cast.released_for(SwordCastComponent.FORM_ARRAY) or not cast.cast_held:
			_phase = Phase.FIRE
			_next_fire = now
			_volley_target = Vector3(cast.aim_point.x, host.global_position.y, cast.aim_point.z)
	_advance(cast, host, direction, now, delta)
	var view: Array = []
	for sword in _swords:
		view.append({"position": sword["position"], "forward": sword["forward"]})
	cast.array_swords = view
	if _phase == Phase.FIRE and _swords.is_empty():
		_phase = Phase.DONE


func _should_deactivate() -> bool:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	return _phase == Phase.DONE or cast == null or cast.cancel_generation != _cancel_generation \
		or (_phase == Phase.GATHER and cast.form != SwordCastComponent.FORM_ARRAY and not cast.released_for(SwordCastComponent.FORM_ARRAY))


func _on_deactivated() -> void:
	var cast := component(&"SwordCastComponent") as SwordCastComponent
	_ready_at = manager_time() + (cast.array_cooldown if cast != null else 0.0)
	_clear()


func _exit_tree() -> void:
	_clear()


func _advance(cast: SwordCastComponent, host: Node3D, direction: Vector3, now: float, delta: float) -> void:
	var alive: Array = []
	var basis := Basis(Vector3.UP, atan2(direction.x, direction.z))
	var launched := 0
	for sword in _swords:
		var state: State = sword["state"]
		if state == State.HOVER:
			var slot := int(sword["slot"])
			var bob := sin(now * 3.0 + slot * 0.7) * 0.05
			sword["position"] = host.global_position + basis * (_slot_offset(slot) + Vector3.UP * bob)
			sword["forward"] = direction
			if _phase == Phase.FIRE and launched == 0 and now >= _next_fire:
				var count := maxi(_swords.size(), 1)
				var radius := cast.array_spread * sqrt((slot + 0.5) / count)
				var angle := slot * GOLDEN_ANGLE
				sword["target"] = _volley_target + Vector3(cos(angle), 0.0, sin(angle)) * radius
				sword["state"] = State.FLY
				_next_fire = now + cast.array_fire_interval
				launched += 1
		elif state == State.FLY:
			var from: Vector3 = sword["position"]
			var offset: Vector3 = (sword["target"] as Vector3) - from
			var step := cast.array_speed * delta
			var target: Vector3 = sword["target"]
			var to := target if offset.length() <= step else from + offset.normalized() * step
			for hit in SwordCastTargets.sweep(host.get_tree(), from, to, cast.array_radius, sword["hit"]):
				(hit["target"] as SwordTargetComponent).record_hit(SwordCastComponent.FORM_ARRAY, hit["point"])
				(sword["hit"] as Dictionary)[hit["id"]] = true
			if offset.length_squared() > 0.000001:
				sword["forward"] = offset.normalized()
			sword["position"] = to
			if to == target:
				sword["state"] = State.STUCK
				sword["stuck_until"] = now + STUCK_TIME
		elif now >= float(sword["stuck_until"]):
			continue
		alive.append(sword)
	_swords = alive


## 扇面槽位（角色局部坐标，+Z 为正面）：中间低、两侧高，后排更高更远。
func _slot_offset(slot: int) -> Vector3:
	var row := slot / ROW_SIZE
	var column := slot % ROW_SIZE
	var u := (float(column) / float(ROW_SIZE - 1)) * 2.0 - 1.0
	var x := u * FAN_HALF_WIDTH * (1.0 + row * 0.15)
	var y := FAN_HEIGHT + row * ROW_LIFT + absf(u) * 0.35
	var z := -FAN_BACK - row * ROW_BACK - (1.0 - absf(u)) * 0.15
	return Vector3(x, y, z)


func _aim_direction(cast: SwordCastComponent, host: Node3D) -> Vector3:
	var flat := cast.aim_point - host.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.09:
		var motion := component(&"SwordsmanMotionComponent") as SwordsmanMotionComponent
		flat = motion.aim_direction if motion != null else Vector3.FORWARD
		flat.y = 0.0
	return flat.normalized()


func _clear() -> void:
	_swords = []
	_phase = Phase.DONE
	var cast := _cast_ref
	if cast == null or not is_instance_valid(cast):
		cast = component(&"SwordCastComponent") as SwordCastComponent
	if cast != null:
		cast.array_swords = []
	_cast_ref = null
