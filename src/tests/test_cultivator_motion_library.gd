extends RefCounted
## 独立动作库与保留的完整导出逐关键帧等价；共享视觉确实消费该库。

const MODEL := "res://game/actors/swordsman/models/cultivator_upright_motion_20261009.glb"
const MOTION := "res://game/actors/swordsman/models/motions/cultivator_upright_motion_20261010.glb"
const VISUAL := "res://game/actors/swordsman/cultivator_aligned_motion_20260927_visual.tscn"
const ROUNDTRIP := "res://game/actors/swordsman/models/motions/cultivator_upright_motion_20261010_blender_roundtrip.glb"


static func run(t) -> void:
	t.begin_case()
	var library := load(MOTION) as AnimationLibrary
	t.assert_true(library != null, "动作 GLB 原生导入为 AnimationLibrary")
	if library == null:
		return
	var model := (load(MODEL) as PackedScene).instantiate()
	t.track(model)
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	t.assert_eq(PackedStringArray(library.get_animation_list()), player.get_animation_list(), "独立库保留精确七段动作")
	for clip in library.get_animation_list():
		var split := library.get_animation(clip)
		var original := player.get_animation(clip)
		t.assert_eq(split.length, original.length, "%s 动作时长不变" % clip)
		t.assert_eq(split.get_track_count(), original.get_track_count(), "%s 轨道数不变" % clip)
		var equal := split.get_track_count() == original.get_track_count()
		for track in range(mini(split.get_track_count(), original.get_track_count())):
			equal = equal and split.track_get_path(track) == original.track_get_path(track)
			equal = equal and split.track_get_type(track) == original.track_get_type(track)
			equal = equal and split.track_get_interpolation_type(track) == original.track_get_interpolation_type(track)
			equal = equal and split.track_get_key_count(track) == original.track_get_key_count(track)
			for key in range(mini(split.track_get_key_count(track), original.track_get_key_count(track))):
				equal = equal and split.track_get_key_time(track, key) == original.track_get_key_time(track, key)
				equal = equal and split.track_get_key_value(track, key) == original.track_get_key_value(track, key)
			t.assert_true(player.get_node_or_null(player.root_node).has_node(
				NodePath(str(split.track_get_path(track)).get_slice(":", 0))),
				"%s 轨道 %d 的目标节点存在" % [clip, track])
		t.assert_true(equal, "%s 全部关键帧、轨道路径与插值逐项等价" % clip)
	var visual := (load(VISUAL) as PackedScene).instantiate()
	var presentation := visual.get_node("CultivatorSkeletonPresentation")
	t.assert_eq(presentation.get("animation_library"), library, "共享视觉显式挂载独立动作库")
	presentation.set("auto_read_actor", false)
	t.track(visual)
	var active := visual.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	t.assert_eq(active.get_animation_library(""), library, "入树后的播放器消费独立库")
	var rebuilt := load(ROUNDTRIP) as AnimationLibrary
	t.assert_true(rebuilt != null, "轻量 Blender 源重导出可原生导入为动作库")
	if rebuilt == null:
		return
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	player.remove_animation_library("")
	player.add_animation_library("", library)
	for clip in library.get_animation_list():
		rebuilt.get_animation(clip).loop_mode = library.get_animation(clip).loop_mode
		var samples: Array[Transform3D] = []
		player.play(clip)
		for phase in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
			player.seek(player.get_animation(clip).length * phase, true)
			for bone in range(skeleton.get_bone_count()):
				samples.append(skeleton.get_bone_global_pose(bone))
		player.remove_animation_library("")
		player.add_animation_library("", rebuilt)
		player.play(clip)
		var sample := 0
		var equivalent := true
		for phase in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
			player.seek(player.get_animation(clip).length * phase, true)
			for bone in range(skeleton.get_bone_count()):
				var pose := skeleton.get_bone_global_pose(bone)
				var reference := samples[sample]
				equivalent = equivalent and pose.origin.distance_to(reference.origin) < 0.00001
				equivalent = equivalent and absf(pose.basis.get_rotation_quaternion().dot(
					reference.basis.get_rotation_quaternion())) > 0.99999
				sample += 1
		t.assert_true(equivalent, "%s 轻量源重导出在六个相位的 22 骨姿态等价" % clip)
		player.remove_animation_library("")
		player.add_animation_library("", library)
