extends RefCounted
## 有效的手部蒙皮、结诀、屈肘与装卸回归。
const ACTOR: PackedScene = preload("res://game/actors/swordsman/swordsman.tscn")
static func run(t) -> void:
	t.begin_case()
	var actor := ACTOR.instantiate() as Swordsman
	t.track(actor)
	await actor.get_tree().process_frame
	var body := actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mesh := body.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var original := mesh.mesh
	var bundle := SwordCastBundle.new()
	t.assert_eq(bundle.install(actor, []), "", "共享剑指可装在原二十二骨角色上")
	var presentation := actor.get_node("SwordCastPresentation") as SwordCastPresentation
	var hand := presentation.get_node("SwordCastHandPresentation") as SwordCastHandPresentation
	var state := hand.sample_state()
	t.assert_eq(state["bones"], 16, "腕骨与十五根指骨真实导入")
	t.assert_eq(state["masked_meshes"], 1, "原右手局部网格隐藏，避免双手重叠")
	t.assert_true(mesh.mesh != original, "局部重建没有原位修改共享人体资源")
	var hs := body.get_node("SwordFingerAttachment").find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	hand.set_gesture(1.0)
	t.assert_true(hs.get_bone_pose_rotation(hs.find_bone("Ring1")).get_angle() > 0.9, "无名指根真实屈曲")
	t.assert_true(hs.get_bone_pose_rotation(hs.find_bone("Little2")).get_angle() > 1.2, "小指第二关节收拢")
	t.assert_true(hs.get_bone_pose_rotation(hs.find_bone("Index2")).get_angle() < 0.1, "食指保持伸直")
	t.assert_true(hs.get_bone_pose_rotation(hs.find_bone("Middle2")).get_angle() < 0.1, "中指保持伸直")
	hand.set_gesture(0.0)
	t.assert_true(hs.get_bone_pose_rotation(hs.find_bone("Ring1")).get_angle() < 0.3, "收势后手指放松")
	var modifier := body.get_node("SwordCastPoseModifier") as SwordCastPoseModifier
	var player: AnimationPlayer = null
	for candidate in actor.find_children("*", "AnimationPlayer", true, false):
		if candidate.has_animation("idle"):
			player = candidate as AnimationPlayer
			break
	t.assert_true(player != null, "明确找到身体的移动动画播放器")
	modifier.weight = 1.0
	modifier.kind = SwordCastComponent.POSE_WHEEL
	modifier.phase = "gather"
	modifier.age = 0.5
	modifier.facing = Vector3.FORWARD
	for i in range(80):
		player.play("idle"); player.advance(0.0)
		modifier._process_modification_with_delta(1.0 / 60.0)
	var shoulder := _point(body, "mixamorig_RightArm")
	var elbow := _point(body, "mixamorig_RightForeArm")
	var wrist := _point(body, "mixamorig_RightHand")
	var center := (shoulder + _point(body, "mixamorig_LeftArm")) * 0.5
	t.assert_true((wrist - center).dot(Vector3.FORWARD) > 0.12, "结诀手腕在胸前")
	t.assert_true(absf(wrist.y - (center.y - 0.16)) < 0.08, "剑诀落在胸前高度")
	t.assert_true((elbow - shoulder).normalized().dot((wrist - elbow).normalized()) < 0.6, "起势明显屈肘而非整臂伸直")
	modifier.phase = "release"; modifier.progress = 1.0
	var max_step := 0.0
	for i in range(35):
		player.play("idle"); player.advance(0.0)
		modifier._process_modification_with_delta(1.0 / 60.0)
		var next := _point(body, "mixamorig_RightHand")
		max_step = maxf(max_step, next.distance_to(wrist)); wrist = next
	t.assert_true(max_step < 0.07, "发令腕部逐帧位移小于七厘米")
	t.assert_true((wrist - center).dot(Vector3.FORWARD) > 0.3, "剑轮发令时剑指向前")
	# 测量真正修改后的手骨，而不是只检查目标矩阵。
	for pose_kind in [SwordCastComponent.POSE_THRUST, SwordCastComponent.POSE_RAISE, SwordCastComponent.POSE_WHEEL, SwordCastComponent.POSE_GIANT, SwordCastComponent.POSE_RAIN]:
		modifier.kind = pose_kind; modifier.phase = "gather"; modifier.progress = 0.0; modifier.age = 0.03
		for i in range(80):
			player.play("idle"); player.advance(0.0)
			modifier._process_modification_with_delta(1.0 / 60.0)
		var upright := _hand_basis(body)
		t.assert_true(upright.y.dot(Vector3.UP) > 0.9999, pose_kind + "结诀手指严格朝上")
		modifier.phase = "release"; modifier.progress = 1.0; modifier.age = 0.6
		var max_roll := 0.0
		for i in range(80):
			player.play("idle"); player.advance(0.0)
			modifier._process_modification_with_delta(1.0 / 60.0)
			max_roll = maxf(max_roll, _hand_basis(body).x.angle_to(Vector3.LEFT))
		var forward := _hand_basis(body)
		var forward_down := Vector3.UP.rotated(Vector3.LEFT, deg_to_rad(105.0))
		t.assert_true(forward.y.dot(forward_down) > 0.9999, pose_kind + "发令手指朝前方偏下十五度")
		t.assert_true(absf(upright.y.angle_to(forward.y) - deg_to_rad(105.0)) < 0.001, pose_kind + "起势到发令俯转一百零五度")
		t.assert_true(max_roll < 0.001, pose_kind + "转动全程掌宽轴稳定不侧翻")
	# 换一个角色朝向也必须围绕角色自身侧轴前指。
	modifier.kind = SwordCastComponent.POSE_WHEEL
	modifier.facing = Vector3.FORWARD.rotated(Vector3.UP, 1.1)
	for i in range(80):
		player.play("idle"); player.advance(0.0)
		modifier._process_modification_with_delta(1.0 / 60.0)
	var aimed_down := Vector3.UP.rotated(-modifier.facing.cross(Vector3.UP), deg_to_rad(105.0))
	t.assert_true(_hand_basis(body).y.dot(aimed_down) > 0.9999, "改变瞄准方向后手指仍朝角色前下方")
	t.assert_true(_hand_basis(body).x.dot(-modifier.facing.cross(Vector3.UP)) > 0.9999, "改变朝向后掌宽轴仍稳定在角色侧向")
	modifier.facing = Vector3.FORWARD
	for i in range(80):
		player.play("idle"); player.advance(0.0)
		modifier._process_modification_with_delta(1.0 / 60.0)
	var previous_rotation := _hand_basis(body).get_rotation_quaternion()
	var base_rotation := previous_rotation
	var max_return_turn := 0.0
	for i in range(80):
		modifier.weight = maxf(0.0, 1.0 - (i + 1) * 0.15)
		player.play("idle"); player.advance(0.0)
		base_rotation = _hand_basis(body).get_rotation_quaternion()
		modifier._process_modification_with_delta(1.0 / 60.0)
		var next_rotation := _hand_basis(body).get_rotation_quaternion()
		max_return_turn = maxf(max_return_turn, previous_rotation.angle_to(next_rotation))
		previous_rotation = next_rotation
	t.assert_true(max_return_turn < 0.33, "施法权重归零前后手腕持续平滑归位")
	t.assert_true(previous_rotation.angle_to(base_rotation) < 0.025, "收势结束手腕回到基础动画朝向")
	# 人为长帧不能让腕部一次跳回胸前。
	modifier.weight = 1.0
	modifier.phase = "gather"
	wrist = _point(body, "mixamorig_RightHand")
	max_step = 0.0
	for i in range(10):
		player.play("idle"); player.advance(0.0)
		modifier._process_modification_with_delta(0.2)
		var next := _point(body, "mixamorig_RightHand")
		max_step = maxf(max_step, next.distance_to(wrist)); wrist = next
	t.assert_true(max_step < 0.07, "两百毫秒长帧仍逐步结诀")
	modifier.weight = 0.0
	bundle.component().record_cast(SwordCastComponent.FORM_WHEEL, Vector3.FORWARD, actor.capability_manager().elapsed, SwordCastComponent.POSE_WHEEL)
	presentation._process(0.2)
	t.assert_true(presentation.pose_weight() <= 0.151, "长帧的姿势混合单步不超过0.15")
	# 身体移位时，缓存立即随身体走，不产生手臂拖在身后的无限滞后。
	modifier.weight = 1.0
	player.play("idle"); player.advance(0.0)
	modifier._process_modification_with_delta(1.0 / 60.0)
	var before_move := _point(body, "mixamorig_RightHand")
	actor.position.x += 1.0
	player.play("idle"); player.advance(0.0)
	modifier._process_modification_with_delta(1.0 / 60.0)
	t.assert_true((_point(body, "mixamorig_RightHand") - before_move).x > 0.9, "手部目标随身体移动而不是留在原世界坐标")
	bundle.uninstall()
	t.assert_true(body.get_node_or_null("SwordCastPoseModifier") == null, "卸载即时移除借用骨架上的动作节点")
	t.assert_eq(bundle.install(actor, []), "", "同帧重新装配不残留手部与动作节点")
	bundle.uninstall()
	await actor.get_tree().process_frame
	t.assert_true(mesh.mesh == original, "卸载恢复原右手共享网格")
	t.assert_true(body.get_node_or_null("SwordFingerAttachment") == null, "卸载清除借用骨架上的手部节点")
	t.assert_eq(actor.find_children("*", "Skeleton3D", true, false).size(), 1, "卸载后只剩原身体骨架")

static func _point(body: Skeleton3D, name: String) -> Vector3:
	return body.global_transform * body.get_bone_global_pose(body.find_bone(name)).origin

static func _hand_basis(body: Skeleton3D) -> Basis:
	return (body.global_transform.basis * body.get_bone_global_pose(body.find_bone("mixamorig_RightHand")).basis).orthonormalized()
