class_name SwordArrayView
extends MultiMeshInstance3D

## 剑阵视图（纯表现）：一次绘制 SwordCastComponent.array_swords 里的全部飞剑。
##
## 剑模型局部 -Z 为剑尖，按每项 forward 摆正；只读组件，不写任何数据。
## 俯视镜头下 0.9 m 的剑只有几个像素宽，绘制时整体放大；命中判定仍按组件参数。

const SWORD_SCENE: PackedScene = preload("res://game/abilities/sword_array/models/array_sword.glb")
const DISPLAY_SCALE := 1.4

var _cast: SwordCastComponent = null


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var source := SWORD_SCENE.instantiate()
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 1, "SwordArrayView: array_sword.glb 应恰好一个网格")
	var sword_mesh := (meshes[0] as MeshInstance3D).mesh
	source.free()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sword_mesh
	multimesh.instance_count = 64
	multimesh.visible_instance_count = 0


func bind(cast: SwordCastComponent) -> void:
	_cast = cast
	if multimesh != null and cast.array_max > multimesh.instance_count:
		multimesh.instance_count = cast.array_max


func _process(_delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	if _cast == null or not is_instance_valid(_cast):
		multimesh.visible_instance_count = 0
		return
	var count := mini(_cast.array_swords.size(), multimesh.instance_count)
	for index in range(count):
		var sword: Dictionary = _cast.array_swords[index]
		multimesh.set_instance_transform(index,
			Transform3D(_basis(sword["forward"]).scaled_local(Vector3.ONE * DISPLAY_SCALE), sword["position"]))
	multimesh.visible_instance_count = count


static func _basis(forward: Vector3) -> Basis:
	if forward.length_squared() <= 0.000001:
		return Basis.IDENTITY
	var up := Vector3.UP if absf(forward.normalized().y) < 0.98 else Vector3.BACK
	return Basis.looking_at(forward, up)
