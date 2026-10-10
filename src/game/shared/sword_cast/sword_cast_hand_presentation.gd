class_name SwordCastHandPresentation
extends Node3D
## 剑法专用可变形右手，借用身体手腕并在卸载时恢复原网格。
## 依据 notes/implemented/art/2026-10-10-sword-finger-gesture.md。
const HAND: PackedScene = preload("res://game/shared/sword_cast/models/sword_finger_hand_20261010.glb")
const WRIST := "mixamorig_RightHand"
const SKIN_SHADER: Shader = preload("res://game/shared/sword_cast/sword_finger_skin.gdshader")
static var _mesh_cache: Dictionary = {}
var _attachment: BoneAttachment3D
var _player: AnimationPlayer
var _hand_skeleton: Skeleton3D
var _originals: Array = []
var _gesture := 0.0

func bind(body: Skeleton3D) -> void:
	assert(body.find_bone(WRIST) >= 0, "SwordCastHandPresentation: 缺少右手腕")
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	for node in meshes:
		var instance := node as MeshInstance3D
		if instance.mesh == null or instance.skin == null:
			continue
		var filtered := _without_old_hand(instance, body)
		if filtered != null:
			_originals.append({"node": instance, "mesh": instance.mesh})
			instance.mesh = filtered
	_attachment = BoneAttachment3D.new()
	_attachment.name = "SwordFingerAttachment"
	_attachment.bone_name = WRIST
	body.add_child(_attachment)
	var hand := HAND.instantiate() as Node3D
	hand.name = "SwordFingerHand"
	# GLB 的 -Z 是指尖；原身体手骨的 +Y 是指尖。
	hand.rotation.x = PI * 0.5
	# 身体骨架来自厘米制源文件，独立手部为米制。
	var wrist_scale := (body.global_transform * body.get_bone_global_rest(body.find_bone(WRIST))).basis.get_scale().abs()
	hand.scale = Vector3(1.0 / wrist_scale.x, 1.0 / wrist_scale.y, 1.0 / wrist_scale.z)
	_attachment.add_child(hand)
	# Dummy renderer 无图形资源；保留导出材质而不安装近景填光 Shader。
	if DisplayServer.get_name() != "headless":
		for item in hand.find_children("*", "MeshInstance3D", true, false):
			var hand_mesh := item as MeshInstance3D
			for surface in range(hand_mesh.mesh.get_surface_count()):
				var skin_material := ShaderMaterial.new()
				skin_material.shader = SKIN_SHADER
				var source := hand_mesh.mesh.surface_get_material(surface)
				if source != null and source.resource_name == "Natural nails":
					skin_material.set_shader_parameter("skin_color", Color(0.89, 0.77, 0.70))
				hand_mesh.set_surface_override_material(surface, skin_material)
	var skeletons := hand.find_children("*", "Skeleton3D", true, false)
	var players := hand.find_children("*", "AnimationPlayer", true, false)
	assert(skeletons.size() == 1 and players.size() == 1, "SwordCastHandPresentation: 手部资产结构无效")
	_hand_skeleton = skeletons[0] as Skeleton3D
	_player = players[0] as AnimationPlayer
	assert(_player.has_animation("gesture"), "SwordCastHandPresentation: 缺少结诀动作")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.play("gesture")
	_player.pause()
	set_gesture(0.0)

func set_gesture(amount: float) -> void:
	_gesture = clampf(amount, 0.0, 1.0)
	if _player != null:
		_player.seek(_gesture * _player.get_animation("gesture").length, true)

func sample_state() -> Dictionary:
	return {"weight": _gesture, "bones": _hand_skeleton.get_bone_count() if _hand_skeleton != null else 0,
		"masked_meshes": _originals.size(), "attached": _attachment != null and is_instance_valid(_attachment)}

func _exit_tree() -> void:
	for item in _originals:
		if is_instance_valid(item["node"]):
			item["node"].mesh = item["mesh"]
	_originals.clear()
	if _attachment != null and is_instance_valid(_attachment):
		if _attachment.get_parent() != null:
			_attachment.get_parent().remove_child(_attachment)
		_attachment.queue_free()
	_attachment = null

static func _without_old_hand(instance: MeshInstance3D, body: Skeleton3D) -> ArrayMesh:
	var original := instance.mesh
	var cache_key := original.get_instance_id()
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]["filtered"] as ArrayMesh
	var bind_index := -1
	var wrist_index := body.find_bone(WRIST)
	for index in range(instance.skin.get_bind_count()):
		if instance.skin.get_bind_name(index) == WRIST or instance.skin.get_bind_bone(index) == wrist_index:
			bind_index = index
			break
	if bind_index < 0:
		return null
	# Skin bind pose 已包含 glTF 网格单位转换，不能直接用骨架 rest 乘网格顶点。
	var to_hand := instance.skin.get_bind_pose(bind_index)
	var unit_scale := (body.global_transform * body.get_bone_global_rest(wrist_index)).basis.get_scale().abs().y
	var filtered := ArrayMesh.new()
	var removed := 0
	for surface in range(original.get_surface_count()):
		var arrays := original.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var texture_image: Image = null
		var material := original.surface_get_material(surface) as BaseMaterial3D
		if material != null:
			var texture := material.get_texture(BaseMaterial3D.TEXTURE_ALBEDO)
			if texture != null:
				texture_image = texture.get_image()
				if texture_image.is_compressed(): texture_image.decompress()
		if indices.is_empty():
			for index in range(points.size()): indices.append(index)
		var cut := PackedByteArray()
		cut.resize(points.size())
		var stride := bones.size() / points.size()
		for vertex in range(points.size()):
			var hand_weight := 0.0
			for lane in range(stride):
				if bones[vertex * stride + lane] == bind_index:
					hand_weight += weights[vertex * stride + lane]
			# 腕口保留在原护腕之内，新手部有 2.3 厘米重叠袖口。
			var old_skin := false
			if hand_weight > 0.35 and texture_image != null and not uv.is_empty():
				var texel := uv[vertex].posmod(1.0) * Vector2(texture_image.get_width(), texture_image.get_height())
				var color := texture_image.get_pixel(clampi(int(texel.x), 0, texture_image.get_width() - 1), clampi(int(texel.y), 0, texture_image.get_height() - 1))
				old_skin = color.r > color.b * 1.02 and color.r > color.g * 0.95
			cut[vertex] = int(hand_weight > 0.35 and ((to_hand * points[vertex]).y * unit_scale > 0.008 or (old_skin and (to_hand * points[vertex]).y * unit_scale > -0.015)))
		var kept := PackedInt32Array()
		for triangle in range(0, indices.size(), 3):
			if cut[indices[triangle]] or cut[indices[triangle + 1]] or cut[indices[triangle + 2]]:
				removed += 1
				continue
			kept.append(indices[triangle]); kept.append(indices[triangle + 1]); kept.append(indices[triangle + 2])
		arrays[Mesh.ARRAY_INDEX] = kept
		filtered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		filtered.surface_set_material(surface, original.surface_get_material(surface))
	assert(removed > 0, "SwordCastHandPresentation: 未筛出旧右手")
	_mesh_cache[cache_key] = {"original": original, "filtered": filtered}
	return filtered
