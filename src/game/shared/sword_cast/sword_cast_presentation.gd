class_name SwordCastPresentation
extends Node3D

## 悬浮本命剑与出招姿势（纯表现）：只读 SwordCastComponent 与角色 motion()，不写任何数据。
##
## 平时本命剑悬在右肩后上方、剑尖朝上并轻微浮动；sword_away 时直接放到组件给出的位置，
## 剑尖朝 sword_forward。飞回时从飞行位置平滑过渡到悬浮位，避免最后一帧跳变。
## 同时在角色骨架下挂 SwordCastPoseModifier，按出招请求平滑抬臂。

const SWORD_SCENE: PackedScene = preload("res://game/shared/sword_cast/models/bound_sword.glb")
## 悬浮时的上下浮动幅度（米）与角频率。
const BOB_HEIGHT := 0.05
const BOB_SPEED := 2.2
## 回到悬浮位与出招姿势的平滑速率（1/秒）。
const SETTLE_RATE := 10.0
const POSE_RATE := 9.0
## 俯视镜头下的可读性放大；不影响组件里的位置与命中参数。
const DISPLAY_SCALE := 1.4

var _host: Swordsman = null
var _cast: SwordCastComponent = null
var _sword: Node3D = null
var _modifier: SwordCastPoseModifier = null
var _hand: SwordCastHandPresentation = null
var _pose_age := 0.0
var _release_age := 0.0
var _last_cast := -1
var _clock := 0.0


## 由 SwordCastBundle 在入树后调用。
func bind(host: Swordsman, cast: SwordCastComponent) -> void:
	_host = host
	_cast = cast
	_sword = SWORD_SCENE.instantiate() as Node3D
	_sword.name = "BoundSword"
	_sword.top_level = true
	add_child(_sword)
	var skeletons := host.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() == 1:
		_modifier = SwordCastPoseModifier.new()
		_modifier.name = "SwordCastPoseModifier"
		(skeletons[0] as Skeleton3D).add_child(_modifier)
		_hand = SwordCastHandPresentation.new()
		_hand.name = "SwordCastHandPresentation"
		add_child(_hand)
		_hand.bind(skeletons[0] as Skeleton3D)
	_place(_rest_transform())


func _exit_tree() -> void:
	if _modifier != null and is_instance_valid(_modifier):
		if _modifier.get_parent() != null:
			_modifier.get_parent().remove_child(_modifier)
		_modifier.queue_free()
	_modifier = null


func sword_node() -> Node3D:
	return _sword


func pose_weight() -> float:
	return _modifier.weight if _modifier != null else 0.0


func hand_state() -> Dictionary:
	return _hand.sample_state() if _hand != null else {}


func _process(delta: float) -> void:
	if _host == null or _cast == null or not is_instance_valid(_cast) or _sword == null:
		return
	_clock += delta
	if _cast.sword_away:
		_place(Transform3D(_tip_basis(_cast.sword_forward), _cast.sword_position))
	else:
		var rest := _rest_transform()
		var alpha := 1.0 - exp(-SETTLE_RATE * delta)
		var current := _sword.global_transform
		_place(Transform3D(current.basis.orthonormalized().slerp(rest.basis, alpha),
			current.origin.lerp(rest.origin, alpha)))
	if _modifier != null:
		if _last_cast != _cast.casts_total:
			_pose_age = 0.0
			_release_age = 0.0
			_last_cast = _cast.casts_total
		var visual_delta := minf(delta, 1.0 / 30.0)
		_pose_age += visual_delta
		_release_age = 0.0 if _cast.cast_held else _release_age + visual_delta
		var now := _host.capability_manager().elapsed
		var target := _cast.pose_weight if _cast.facing_requested(now) else 0.0
		# 长帧也不在一次更新中跳到出手或待机；只限制视觉混合。
		_modifier.weight = move_toward(_modifier.weight, target, POSE_RATE * minf(delta, 1.0 / 60.0))
		_modifier.kind = _cast.pose_kind
		_modifier.phase = _cast.pose_phase
		_modifier.progress = _cast.pose_progress
		if _cast.pose_kind == SwordCastComponent.POSE_RAISE:
			_modifier.phase = "gather" if _cast.cast_held else "release"
			_modifier.progress = clampf(_release_age / 0.22, 0.0, 1.0)
		_modifier.facing = _facing()
		_modifier.age = _pose_age
		if _hand != null:
			_hand.set_gesture(smoothstep(0.0, 0.8, _modifier.weight))


func _place(transform: Transform3D) -> void:
	_sword.global_transform = Transform3D(transform.basis.orthonormalized().scaled_local(
		Vector3.ONE * DISPLAY_SCALE), transform.origin)


func _rest_transform() -> Transform3D:
	var facing := _facing()
	var position := _cast.rest_position(_host.global_position, facing) \
		+ Vector3.UP * sin(_clock * BOB_SPEED) * BOB_HEIGHT
	var side := Vector3.UP.cross(facing).normalized()
	# 剑尖朝上，略向外、向前倾。
	var tip := (Vector3.UP * 0.92 + facing * 0.18 - side * 0.22).normalized()
	return Transform3D(_tip_basis(tip), position)


func _facing() -> Vector3:
	var aim := _host.motion().aim_direction
	var flat := Vector3(aim.x, 0.0, aim.z)
	return flat.normalized() if flat.length_squared() > 0.000001 else Vector3.FORWARD


static func _tip_basis(forward: Vector3) -> Basis:
	if forward.length_squared() <= 0.000001:
		return Basis.IDENTITY
	var up := Vector3.UP if absf(forward.normalized().y) < 0.98 else Vector3.BACK
	return Basis.looking_at(forward, up)
