class_name SwordCastPoseModifier
extends SkeletonModifier3D

## 出招姿势（纯表现）：在动画之后把右上臂与前臂转向出招方向。
##
## weight 0..1 与 kind 由 SwordCastPresentation 每帧写入；不读写任何 Component。
## thrust 为向前略向下平指，raise 为斜上举。骨架没有手指骨，手型不变。

const ARM := "mixamorig_RightArm"
const FOREARM := "mixamorig_RightForeArm"
const HAND := "mixamorig_RightHand"
const THRUST_DROP := 0.14

var weight: float = 0.0
var kind: String = SwordCastComponent.POSE_THRUST
## 角色面向的世界水平方向。
var facing: Vector3 = Vector3.FORWARD
var phase: String = "gather"
var progress: float = 0.0

var _bones := PackedInt32Array()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or weight <= 0.001:
		return
	if _bones.is_empty():
		_bones = PackedInt32Array([skeleton.find_bone(ARM), skeleton.find_bone(FOREARM), skeleton.find_bone(HAND)])
	if _bones.has(-1):
		return
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() <= 0.000001:
		return
	flat = flat.normalized()
	var world := (flat - Vector3.UP * THRUST_DROP).normalized()
	if kind == SwordCastComponent.POSE_RAISE:
		world = (flat * 0.45 + Vector3.UP * 0.9).normalized()
	if kind in [SwordCastComponent.POSE_WHEEL, SwordCastComponent.POSE_GIANT, SwordCastComponent.POSE_RAIN]:
		var side := Vector3.UP.cross(flat).normalized()
		var command := smoothstep(0.0, 1.0, progress) if phase in ["release", "fall", "fire"] else 0.0
		var right := (flat * 0.22 - side * 0.68 + Vector3.UP * 0.5).normalized()
		var left := (flat * 0.22 + side * 0.68 + Vector3.UP * 0.5).normalized()
		if kind == SwordCastComponent.POSE_GIANT:
			right = (flat * 0.2 - side * 0.26 + Vector3.UP).normalized()
			left = (flat * 0.2 + side * 0.26 + Vector3.UP).normalized()
		elif kind == SwordCastComponent.POSE_RAIN:
			right = (flat * 0.28 - side * 0.16 + Vector3.UP).normalized()
			left = (flat * 0.75 + side * 0.45 + Vector3.UP * 0.1).normalized()
		var finish := (flat * 0.9 - Vector3.UP * 0.25).normalized()
		right = right.lerp(finish, command).normalized()
		left = left.lerp((finish + side * 0.25).normalized(), command).normalized()
		_aim_named_chain(skeleton, "mixamorig_Right", right)
		_aim_named_chain(skeleton, "mixamorig_Left", left)
		return
	var desired := (skeleton.global_transform.basis.inverse() * world).normalized()
	_aim_bone(skeleton, _bones[0], _bones[1], desired)
	_aim_bone(skeleton, _bones[1], _bones[2], desired)


## 绕骨骼头转动，使骨骼头→子骨骼头的方向按 weight 转向 desired（骨架空间）。
func _aim_bone(skeleton: Skeleton3D, bone: int, child: int, desired: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := skeleton.get_bone_global_pose(child).origin - pose.origin
	if current.length_squared() <= 0.0000001:
		return
	var turn := Quaternion.IDENTITY.slerp(Quaternion(current.normalized(), desired), weight)
	skeleton.set_bone_global_pose(bone, Transform3D(Basis(turn) * pose.basis, pose.origin))


func _aim_named_chain(skeleton: Skeleton3D, prefix: String, world: Vector3) -> void:
	var arm := skeleton.find_bone(prefix + "Arm")
	var forearm := skeleton.find_bone(prefix + "ForeArm")
	var hand := skeleton.find_bone(prefix + "Hand")
	if arm < 0 or forearm < 0 or hand < 0:
		return
	var desired := (skeleton.global_transform.basis.inverse() * world).normalized()
	_aim_bone(skeleton, arm, forearm, desired)
	_aim_bone(skeleton, forearm, hand, desired)
