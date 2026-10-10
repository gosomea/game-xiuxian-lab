class_name SwordCastPoseModifier
extends SkeletonModifier3D
## 共享剑指施法：胸前屈肘结诀、各招发令、收势。只修改视觉骨架。
## 依据 notes/implemented/art/2026-10-10-sword-finger-gesture.md。
const COMMAND_PITCH := deg_to_rad(105.0)
var weight: float = 0.0
var kind: String = SwordCastComponent.POSE_THRUST
var facing: Vector3 = Vector3.FORWARD
var phase: String = "gather"
var progress: float = 0.0
## 短招的表现时间轴，由表现层推进，独立于命中规则。
var age: float = 0.0
var _right_target := Vector3.ZERO
var _left_target := Vector3.ZERO
var _hand_rotation := Quaternion.IDENTITY
var _left_weight := 0.0
var _prepared := false
var _last_frame := Transform3D.IDENTITY

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null: return
	var flat := Vector3(facing.x, 0.0, facing.z).normalized()
	if flat.is_zero_approx(): return
	var right := flat.cross(Vector3.UP).normalized()
	var shoulder_center := (_point(skeleton, "mixamorig_RightArm") + _point(skeleton, "mixamorig_LeftArm")) * 0.5
	# 起势：手在胸前，肘在身侧向下，剑指正上。
	var chest := shoulder_center + flat * 0.22 + right * 0.025 - Vector3.UP * 0.16
	var target := chest
	var left := shoulder_center + right * -0.18 + flat * 0.10 - Vector3.UP * 0.43
	var left_influence := 0.0
	var command := smoothstep(0.0, 1.0, progress) if phase in ["release", "fall", "fire", "descent"] else 0.0
	if phase in ["impact", "fade", "dissipate"]: command = 1.0
	if kind == SwordCastComponent.POSE_THRUST:
		command = smoothstep(0.06, 0.23, age)
		target = chest.lerp(shoulder_center + right * 0.07 + flat * 0.44 - Vector3.UP * 0.14, command)
	elif kind == SwordCastComponent.POSE_RAISE:
		var raised := chest.lerp(shoulder_center + right * 0.025 + flat * 0.24 + Vector3.UP * 0.03, smoothstep(0.0, 0.22, age))
		target = raised.lerp(shoulder_center + flat * 0.44 + right * 0.06 - Vector3.UP * 0.12, command)
	elif kind == SwordCastComponent.POSE_WHEEL:
		target = chest.lerp(shoulder_center + flat * 0.45 + right * 0.06 - Vector3.UP * 0.12, command)
		left = shoulder_center - right * 0.26 + flat * 0.16 - Vector3.UP * 0.18
		left_influence = 0.65
	elif kind in [SwordCastComponent.POSE_GIANT, SwordCastComponent.POSE_RAIN]:
		# 上举仍保持屈肘，释放时以剑诀引剑下压。
		var lift := smoothstep(0.15, 0.8, age)
		var raised := chest.lerp(shoulder_center + flat * 0.22 + right * 0.025 + Vector3.UP * 0.17, lift)
		target = raised.lerp(shoulder_center + flat * 0.41 + right * 0.035 - Vector3.UP * 0.28, command)
		left = shoulder_center - right * 0.24 + flat * 0.19 - Vector3.UP * 0.21
		left_influence = 0.5
	var visual_delta := minf(delta, 1.0 / 30.0)
	var blend := 1.0 - exp(-visual_delta * 16.0)
	var hand_index := skeleton.find_bone("mixamorig_RightHand")
	# 必须在手臂 IK 之前读取基础动画，避免把肘部转向再次混进手腕。
	var base_fingers := (skeleton.global_transform.basis * skeleton.get_bone_global_pose(hand_index).basis).y.normalized()
	# 独立手部原生 -Z 为掌心；垂手和施法都保持朝角色左侧。
	var base_rotation := _palm_left_basis(flat, base_fingers).get_rotation_quaternion()
	var commanded_rotation := _gesture_basis(flat, command).get_rotation_quaternion()
	var desired_rotation := base_rotation.slerp(commanded_rotation, weight)
	if not _prepared:
		_right_target = _point(skeleton, "mixamorig_RightHand")
		_left_target = _point(skeleton, "mixamorig_LeftHand")
		_hand_rotation = base_rotation
		_prepared = true
	else:
		# 缓存跟随身体平移、升降与转向，不能把移动速度算成施法手臂的滞后。
		var body_motion := skeleton.global_transform * _last_frame.affine_inverse()
		_right_target = body_motion * _right_target
		_left_target = body_motion * _left_target
		_hand_rotation = (body_motion.basis.orthonormalized().get_rotation_quaternion() * _hand_rotation).normalized()
		_hand_rotation = _palm_left_basis(flat, Basis(_hand_rotation).y).get_rotation_quaternion()
	_last_frame = skeleton.global_transform
	_right_target = _right_target.move_toward(target, minf(_right_target.distance_to(target) * blend, 0.045))
	_left_target = _left_target.move_toward(left, minf(_left_target.distance_to(left) * blend, 0.045))
	var turn_blend := minf(blend, 0.32 / maxf(_hand_rotation.angle_to(desired_rotation), 0.00001))
	_hand_rotation = _hand_rotation.slerp(desired_rotation, turn_blend).normalized()
	_left_weight = move_toward(_left_weight, left_influence * weight, visual_delta * 4.0)
	_solve_arm(skeleton, "mixamorig_Right", _right_target, right * 0.85 - Vector3.UP * 0.6, weight)
	_orient_hand(skeleton, hand_index, _hand_rotation)
	if _left_weight > 0.001:
		_solve_arm(skeleton, "mixamorig_Left", _left_target, -right - Vector3.UP * 0.5, _left_weight)
	# 权重归零后逐步垂手，掌心仍向左，避免收势时翻掌朝天。
	if weight <= 0.001 and _hand_rotation.angle_to(base_rotation) < 0.02:
		_prepared = false
		_left_weight = 0.0

static func _point(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin

static func _solve_arm(skeleton: Skeleton3D, prefix: String, target: Vector3, pole: Vector3, influence: float) -> void:
	var arm := skeleton.find_bone(prefix + "Arm")
	var forearm := skeleton.find_bone(prefix + "ForeArm")
	var hand := skeleton.find_bone(prefix + "Hand")
	if arm < 0 or forearm < 0 or hand < 0: return
	var shoulder := _point(skeleton, prefix + "Arm")
	var elbow := _point(skeleton, prefix + "ForeArm")
	var wrist := _point(skeleton, prefix + "Hand")
	var upper_length := shoulder.distance_to(elbow)
	var lower_length := elbow.distance_to(wrist)
	var direction := (target - shoulder).normalized()
	var distance := clampf(shoulder.distance_to(target), absf(upper_length - lower_length) + 0.01, upper_length + lower_length - 0.025)
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var bend := (pole - direction * pole.dot(direction)).normalized()
	var desired_elbow := shoulder + direction * along + bend * height
	var to_skeleton := skeleton.global_transform.basis.inverse()
	_aim_bone(skeleton, arm, forearm, (to_skeleton * (desired_elbow - shoulder)).normalized(), influence)
	elbow = _point(skeleton, prefix + "ForeArm")
	var desired_wrist := shoulder + direction * distance
	_aim_bone(skeleton, forearm, hand, (to_skeleton * (desired_wrist - elbow)).normalized(), influence)

static func _aim_bone(skeleton: Skeleton3D, bone: int, child: int, desired: Vector3, influence: float) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := skeleton.get_bone_global_pose(child).origin - pose.origin
	if current.length_squared() < 0.0000001: return
	var turn := Quaternion.IDENTITY.slerp(Quaternion(current.normalized(), desired), influence)
	skeleton.set_bone_global_pose(bone, Transform3D(Basis(turn) * pose.basis, pose.origin))

static func _gesture_basis(flat: Vector3, command: float) -> Basis:
	var left := -flat.cross(Vector3.UP).normalized()
	var fingers := Vector3.UP.rotated(left, clampf(command, 0.0, 1.0) * COMMAND_PITCH)
	return _palm_left_basis(flat, fingers)

static func _palm_left_basis(flat: Vector3, fingers: Vector3) -> Basis:
	var back_of_hand := flat.cross(Vector3.UP).normalized()
	var along := fingers - back_of_hand * fingers.dot(back_of_hand)
	if along.length_squared() < 0.000001: along = Vector3.DOWN
	along = along.normalized()
	return Basis(along.cross(back_of_hand), along, back_of_hand).orthonormalized()

static func _orient_hand(skeleton: Skeleton3D, index: int, world_rotation: Quaternion) -> void:
	var pose := skeleton.get_bone_global_pose(index)
	var desired := (skeleton.global_transform.basis.inverse() * Basis(world_rotation)).orthonormalized()
	var scale := pose.basis.get_scale()
	skeleton.set_bone_global_pose(index, Transform3D(desired.scaled_local(scale), pose.origin))
