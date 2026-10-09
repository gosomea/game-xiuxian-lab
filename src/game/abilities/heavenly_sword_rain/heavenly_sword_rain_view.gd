class_name HeavenlySwordRainView
extends Node3D

## 纯表现：金青逆转法环、逐剑几何、连续轨迹尾带与接地小环。
## 剑尖位置来自能力；依据共享网格 TIP_LENGTH 反算剑格，尺寸变化也不穿地。

const JADE := Color(0.25, 0.97, 0.77, 1.0)
const PALE := Color(0.78, 1.0, 0.91, 1.0)
const GOLD := Color(1.0, 0.78, 0.28, 1.0)

var _rain: HeavenlySwordRainComponent = null
var _swords: MultiMeshInstance3D = null
var _upper: Array[MeshInstance3D] = []
var _ground: Array[MeshInstance3D] = []
var _glyphs: MeshInstance3D = null
var _trails: MeshInstance3D = null
var _impact_mesh: MeshInstance3D = null
var _orientations: Dictionary = {}


func bind(rain: HeavenlySwordRainComponent) -> void:
	assert(rain != null, "天降剑雨 View 必须绑定数据组件")
	_rain = rain
	if _swords == null:
		_build()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY


func _build() -> void:
	_swords = SwordSpellVisual.create_swords(maxi(96, _rain.sword_count), PALE)
	_swords.name = "RainSwords"
	add_child(_swords)
	for index in range(3):
		var factor: float = [1.08, 0.84, 0.56][index]
		var ring := _mesh_node(SwordSpellVisual.ring_mesh(_rain.region_radius * factor,
			0.045 if index != 1 else 0.025), GOLD if index != 1 else JADE)
		ring.name = "CeilingRing%d" % index
		_upper.append(ring)
	for index in range(2):
		var ring := _mesh_node(SwordSpellVisual.ring_mesh(_rain.region_radius * (1.0 if index == 0 else 0.90),
			0.035 if index == 0 else 0.017), JADE)
		ring.name = "SelectionRing%d" % index
		_ground.append(ring)
	_glyphs = _mesh_node(_glyph_mesh(_rain.region_radius), GOLD)
	_glyphs.name = "CeilingGlyphs"
	_trails = _mesh_node(ImmediateMesh.new(), Color.WHITE)
	_trails.name = "RainTrails"
	_impact_mesh = _mesh_node(ImmediateMesh.new(), Color.WHITE)
	_impact_mesh.name = "RainImpacts"


func _mesh_node(mesh: Mesh, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = SwordSpellVisual.glow_material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _process(_delta: float) -> void:
	if _rain == null or not is_instance_valid(_rain) or _swords == null:
		return
	global_transform = Transform3D.IDENTITY
	var visible_now := _rain.phase != "idle"
	_swords.visible = visible_now
	_glyphs.visible = visible_now
	_trails.visible = visible_now
	_impact_mesh.visible = visible_now
	for node in _upper + _ground:
		node.visible = visible_now
	if not visible_now:
		_swords.multimesh.visible_instance_count = 0
		_orientations.clear()
		return
	var count := _rain.swords.size()
	if count > _swords.multimesh.instance_count:
		_swords.multimesh.instance_count = count
	for index in range(count):
		var sword: Dictionary = _rain.swords[index]
		var color := PALE.lerp(JADE, float(int(sword["batch"]) % 3) * 0.20)
		color.a = float(sword["alpha"])
		var transform := transform_for_sword(sword)
		var key := int(sword["slot"])
		if _orientations.has(key):
			transform = SwordSpellVisual.continuous_sword_transform(transform.origin, sword["forward"],
				Vector3.ONE * float(sword["scale"]), _orientations[key])
		_orientations[key] = transform.basis.orthonormalized()
		_swords.multimesh.set_instance_transform(index, transform)
		_swords.multimesh.set_instance_color(index, color)
	_swords.multimesh.visible_instance_count = count
	var formed := minf(1.0, _rain.progress) if _rain.phase == "gather" else 1.0
	var grow := lerpf(0.76, 1.0, formed * formed * (3.0 - 2.0 * formed))
	var ceiling := _rain.ceiling_center + Vector3.UP * (_rain.sword_scale * SwordSpellVisual.TOTAL_LENGTH + 0.06)
	for index in range(_upper.size()):
		var angle := _rain.ring_angle * (1.0 if index % 2 == 0 else -1.4)
		_upper[index].global_transform = Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * grow),
			ceiling + Vector3.UP * index * 0.028)
		_set_alpha(_upper[index], _rain.ring_alpha * (0.80 if index == 1 else 1.0))
	_glyphs.global_transform = Transform3D(Basis(Vector3.UP, -_rain.ring_angle * 0.6).scaled(Vector3.ONE * grow),
		ceiling + Vector3.UP * 0.01)
	_set_alpha(_glyphs, _rain.ring_alpha * 0.72)
	var normal := _rain.ground_normal.normalized()
	var ground_basis := Basis(Quaternion(Vector3.UP, normal))
	for index in range(_ground.size()):
		_ground[index].global_transform = Transform3D(ground_basis,
			_rain.ground_center + normal * (0.025 + index * 0.008))
		_set_alpha(_ground[index], _rain.ring_alpha * (0.75 if _rain.released else 0.96))
	_draw_trails()
	_draw_impacts()


## 表现的几何契约；headless dummy renderer 不保存 MultiMesh 变换，直接验证这份实际绘制输入。
static func transform_for_sword(sword: Dictionary) -> Transform3D:
	var size := float(sword["scale"])
	var forward: Vector3 = sword["forward"]
	var tip: Vector3 = sword["tip"]
	# 基于真实网格长度换算，尖端接地时剑身完整悬在地面上方。
	var origin := tip - forward * SwordSpellVisual.TIP_LENGTH * size
	return SwordSpellVisual.sword_transform(origin, forward, Vector3.ONE * size)


func _set_alpha(node: MeshInstance3D, alpha: float) -> void:
	var material := node.material_override as StandardMaterial3D
	var color := material.albedo_color
	color.a = clampf(alpha, 0.0, 1.0)
	material.albedo_color = color


func _draw_trails() -> void:
	var mesh := _trails.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var has_segments := false
	for sword in _rain.swords:
		if (sword["trail"] as Array).size() >= 2:
			has_segments = true
	if not has_segments:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for sword in _rain.swords:
		var points: Array = sword["trail"]
		for index in range(1, points.size()):
			var u := float(index) / maxf(float(points.size() - 1), 1.0)
			var tail := JADE
			tail.a = u * 0.56 * float(sword["alpha"])
			var lead := PALE
			lead.a = (u + 0.1) * 0.65 * float(sword["alpha"])
			SwordSpellVisual.append_line(mesh, points[index - 1], points[index], 0.055 * u, tail, lead)
	mesh.surface_end()


func _draw_impacts() -> void:
	var mesh := _impact_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _rain.impacts.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for impact in _rain.impacts:
		var u := float(impact["progress"])
		var normal: Vector3 = impact["normal"]
		var basis := Basis(Quaternion(Vector3.UP, normal))
		var center: Vector3 = impact["position"] + normal * 0.032
		var radius := lerpf(0.06, 0.48, sqrt(u))
		var color := GOLD.lerp(JADE, u)
		color.a = float(impact["alpha"]) * 0.78
		for index in range(20):
			var a := float(index) * TAU / 20.0
			var b := float(index + 1) * TAU / 20.0
			var from := center + basis * Vector3(cos(a), 0.0, sin(a)) * radius
			var to := center + basis * Vector3(cos(b), 0.0, sin(b)) * radius
			SwordSpellVisual.append_line(mesh, from, to, 0.028 * (1.0 - u * 0.7), color, color)
	mesh.surface_end()


func _glyph_mesh(radius: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(12):
		var a := float(index) * TAU / 12.0
		var b := a + TAU / 12.0
		var inner := Vector3(cos(a), 0.0, sin(a)) * radius * 0.56
		var outer := Vector3(cos(a), 0.0, sin(a)) * radius * 0.98
		var cross := Vector3(cos(a + 0.08), 0.0, sin(a + 0.08)) * radius * 0.92
		var next := Vector3(cos(b), 0.0, sin(b)) * radius * 0.56
		SwordSpellVisual.append_line(mesh, inner, outer, 0.018, GOLD, GOLD)
		SwordSpellVisual.append_line(mesh, outer, cross, 0.038, JADE, JADE)
		SwordSpellVisual.append_line(mesh, outer * 0.84, next, 0.017, GOLD, GOLD)
	mesh.surface_end()
	return mesh
