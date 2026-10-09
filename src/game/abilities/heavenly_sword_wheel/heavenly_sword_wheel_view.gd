class_name HeavenlySwordWheelView
extends Node3D

## 纯表现：金色双法轮、反转刻度、青色剑刃、轨迹和接地冲击。
## 所有动画进度来自 Component.logic_time；不模拟、不写数据、不控制镜头。

var _data: HeavenlySwordWheelComponent
var _swords: MultiMeshInstance3D
var _rings: Array[MeshInstance3D] = []
var _ring_materials: Array[StandardMaterial3D] = []
var _trail_mesh := ImmediateMesh.new()
var _trails: MeshInstance3D
var _orientations: Dictionary = {}


func bind(data: HeavenlySwordWheelComponent) -> void:
	assert(data != null, "HeavenlySwordWheelView 需要独立组件")
	_data = data
	if is_inside_tree():
		_build()


func _ready() -> void:
	top_level = true
	if _data != null:
		_build()


func _build() -> void:
	assert(_swords == null, "HeavenlySwordWheelView 只装配一次")
	_swords = SwordSpellVisual.create_swords(_data.max_swords, _data.sword_color)
	_swords.name = "WheelSwords"
	add_child(_swords)
	for radius in [_data.inner_radius - 0.13, _data.inner_radius + 0.13,
		_data.outer_radius - 0.15, _data.outer_radius + 0.15]:
		_add_ring(SwordSpellVisual.ring_mesh(radius, _data.ring_width), _data.ring_color)
	_add_ring(_runes(_data.inner_radius, 12), _data.ring_color)
	_add_ring(_runes(_data.outer_radius, 24), _data.ring_color)
	_add_ring(_spokes(_data.inner_radius * 0.64, _data.inner_radius - 0.15),
		Color(_data.sword_color.r, _data.sword_color.g, _data.sword_color.b, 0.34))
	_trails = MeshInstance3D.new()
	_trails.name = "WheelTrailsAndImpacts"
	_trails.mesh = _trail_mesh
	_trails.material_override = SwordSpellVisual.glow_material(Color.WHITE)
	_trails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trails)


func _add_ring(mesh: ImmediateMesh, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = "WheelRing%d" % _rings.size()
	node.mesh = mesh
	var material := SwordSpellVisual.glow_material(color)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_rings.append(node)
	_ring_materials.append(material)


func _process(_delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	if _swords == null:
		return
	if _data == null or not is_instance_valid(_data):
		_swords.multimesh.visible_instance_count = 0
		_trail_mesh.clear_surfaces()
		for ring in _rings:
			ring.visible = false
		return
	if _data.max_swords > _swords.multimesh.instance_count:
		_swords.multimesh.instance_count = _data.max_swords
	var count := mini(_data.swords.size(), _swords.multimesh.instance_count)
	for index in range(count):
		var sword: Dictionary = _data.swords[index]
		var color := Color(1.0, 1.0, 1.0, float(sword["alpha"]))
		var key := str(sword["ring"]) + ":" + str(sword["angle"])
		var unit := SwordSpellVisual.sword_transform(sword["position"], sword["forward"])
		if _orientations.has(key):
			unit = SwordSpellVisual.continuous_sword_transform(sword["position"], sword["forward"], Vector3.ONE, _orientations[key])
		_orientations[key] = unit.basis
		_swords.multimesh.set_instance_transform(index, Transform3D(unit.basis.scaled_local(sword["scale"]), unit.origin))
		_swords.multimesh.set_instance_color(index, color)
	_swords.multimesh.visible_instance_count = count
	if count == 0:
		_orientations.clear()
	var right := _data.direction.cross(Vector3.UP).normalized()
	var wheel_basis := Basis(right, _data.direction, Vector3.UP)
	for index in range(_rings.size()):
		var ring := _rings[index]
		var turn := _data.ring_angle * (1.0 if index in [0, 1, 4] else -1.0)
		ring.global_transform = Transform3D(wheel_basis * Basis(Vector3.UP, turn),
			_data.center - _data.direction * 0.04)
		ring.visible = _data.ring_alpha > 0.001
		var color := _data.ring_color if index < 6 else _data.sword_color
		color.a *= _data.ring_alpha * (0.25 if index == 6 else 1.0)
		_ring_materials[index].albedo_color = color
	_draw_trails()


func _draw_trails() -> void:
	_trail_mesh.clear_surfaces()
	var has_geometry := not _data.impacts.is_empty()
	for sword in _data.swords:
		has_geometry = has_geometry or (sword["trail"] as Array).size() > 1
	if not has_geometry:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for sword in _data.swords:
		var trail: Array = sword["trail"]
		for index in range(1, trail.size()):
			var along := float(index) / float(trail.size())
			var color := _data.sword_color
			color.a = along * float(sword["alpha"]) * 0.5
			var previous := color
			previous.a *= 0.45
			SwordSpellVisual.append_line(_trail_mesh, trail[index - 1], trail[index],
				_data.ring_width * (1.0 + along * 2.5), previous, color)
	for impact in _data.impacts:
		var age := clampf((_data.logic_time - float(impact["started_at"])) / _data.impact_time, 0.0, 1.0)
		var normal: Vector3 = impact["normal"]
		var right := normal.cross(Vector3.FORWARD).normalized()
		if right.length_squared() < 0.001:
			right = Vector3.RIGHT
		var forward := normal.cross(right).normalized()
		var point: Vector3 = impact["point"] + normal * 0.015
		var radius := lerpf(0.08, 0.6, age)
		var color := _data.sword_color
		color.a = (1.0 - age) * 0.5
		for index in range(16):
			var a := float(index) * TAU / 16.0
			var b := float(index + 1) * TAU / 16.0
			SwordSpellVisual.append_line(_trail_mesh, point + (right * cos(a) + forward * sin(a)) * radius,
				point + (right * cos(b) + forward * sin(b)) * radius, _data.ring_width, color, color)
	_trail_mesh.surface_end()


func _runes(radius: float, count: int) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(count):
		var angle := float(index) * TAU / float(count)
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		var center := radial * radius
		var a := center - radial * 0.07 - tangent * 0.035
		var b := center + radial * 0.07 - tangent * 0.035
		var c := center + radial * 0.07 + tangent * 0.035
		var d := center - radial * 0.07 + tangent * 0.035
		for pair in [[a, b], [b, c], [c, d], [d, a]]:
			SwordSpellVisual.append_line(mesh, pair[0], pair[1], _data.rune_width, Color.WHITE, Color.WHITE)
		SwordSpellVisual.append_line(mesh, center - radial * 0.045, center + radial * 0.045,
			_data.rune_width, Color.WHITE, Color.WHITE)
	mesh.surface_end()
	return mesh


func _spokes(inner: float, outer: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(6):
		var a := float(index) * TAU / 6.0
		var b := float(index + 2) * TAU / 6.0
		var from := Vector3(cos(a), 0.0, sin(a)) * outer
		var to := Vector3(cos(b), 0.0, sin(b)) * inner
		SwordSpellVisual.append_line(mesh, from, to, _data.rune_width, Color.WHITE, Color.WHITE)
	mesh.surface_end()
	return mesh
