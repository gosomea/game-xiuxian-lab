class_name SwordSpellVisual
extends RefCounted

## 三个法术实际复用的纯视觉几何；不读取输入、不模拟法术、不修改组件。
const SWORD_SCENE: PackedScene = preload("res://game/shared/sword_cast/models/spirit_sword_20261010.glb")
const TIP_LENGTH := 0.702
const TOTAL_LENGTH := 0.857
static var _mesh: Mesh

static func sword_mesh() -> Mesh:
	if _mesh == null:
		var source := SWORD_SCENE.instantiate()
		var meshes := source.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == 1, "共享灵剑必须恰好一个网格")
		_mesh = (meshes[0] as MeshInstance3D).mesh
		source.free()
	return _mesh


static func sword_transform(position: Vector3, forward: Vector3, scale: Vector3 = Vector3.ONE) -> Transform3D:
	var direction := forward.normalized() if forward.length_squared() > 0.000001 else Vector3.FORWARD
	var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.BACK
	return Transform3D(Basis.looking_at(direction, up).scaled_local(scale), position)


## 延续上一帧的剑身朝向，只转动剑尖方向需要的最小角度。
## 穿过竖直方向时不切换参考上轴，避免剑身突然滚转；不会滞后实际剑尖。
static func continuous_sword_transform(position: Vector3, forward: Vector3,
		scale: Vector3, previous: Basis) -> Transform3D:
	var basis := previous.orthonormalized()
	var old_direction := -basis.z
	var direction := forward.normalized() if forward.length_squared() > 0.000001 else old_direction
	basis = Basis(Quaternion(old_direction, direction)) * basis
	return Transform3D(basis.orthonormalized().scaled_local(scale), position)


static func glow_material(color: Color, transparent: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 0.65
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func create_swords(capacity: int, color: Color) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_colors = true
	node.multimesh.mesh = sword_mesh()
	node.multimesh.instance_count = capacity
	node.multimesh.visible_instance_count = 0
	node.material_override = glow_material(color)
	return node


static func set_sword(mm: MultiMesh, index: int, position: Vector3, forward: Vector3,
		scale: Vector3, color: Color) -> void:
	mm.set_instance_transform(index, sword_transform(position, forward, scale))
	mm.set_instance_color(index, color)


## XZ 平面圆环；节点可旋转到竖直轮面。
static func ring_mesh(radius: float, width: float, segments: int = 96) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a := float(i) * TAU / segments
		var b := float(i + 1) * TAU / segments
		var p := Vector3(cos(a), 0.0, sin(a))
		var q := Vector3(cos(b), 0.0, sin(b))
		for point in [p * (radius - width * 0.5), q * (radius - width * 0.5),
			q * (radius + width * 0.5), p * (radius - width * 0.5),
			q * (radius + width * 0.5), p * (radius + width * 0.5)]:
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	return mesh


## 一段渐隐、双面网格带；调用方批量 begin/end，避免每剑一个节点。
static func append_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, width: float,
		color: Color, end_color: Color) -> void:
	var direction := to - from
	if direction.length_squared() < 0.0000001:
		return
	var side := direction.normalized().cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized() * width * 0.5
	var vertices := [from - side, to - side, to + side, from - side, to + side, from + side]
	for i in range(6):
		mesh.surface_set_color(color if i in [0, 3, 5] else end_color)
		mesh.surface_add_vertex(vertices[i])
