class_name GiantSwordDescentView
extends Node3D

## 只读 GiantSwordDescentComponent：暗刃/青玉光芯、金色冠环、地面符环、尾迹与冲击。
## 剑格原点由共享几何的实际 TIP_LENGTH 换算，剑尖就是能力快照 sword_tip。
## 不写组件、不驱动命中、不修改镜头，全部动画消费确定性逻辑快照。

const BLADE_SHADER: Shader = preload("res://game/abilities/giant_sword_descent/giant_sword_descent_blade.gdshader")
const JADE := Color(0.24, 0.9, 0.77, 1.0)
const GOLD := Color(0.91, 0.71, 0.26, 1.0)

var _data: GiantSwordDescentComponent
var _blade: MeshInstance3D
var _aura: MeshInstance3D
var _ground_outer: MeshInstance3D
var _ground_inner: MeshInstance3D
var _ground_marks: MeshInstance3D
var _crown_outer: MeshInstance3D
var _crown_inner: MeshInstance3D
var _crown_marks: MeshInstance3D
var _shock_outer: MeshInstance3D
var _shock_inner: MeshInstance3D
var _lines: MeshInstance3D
var _line_mesh: ImmediateMesh
var _blade_material: ShaderMaterial


func bind(data: GiantSwordDescentComponent) -> void:
	assert(data != null, "GiantSwordDescentView 需要自己的独立 Component")
	_data = data


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_blade_material = ShaderMaterial.new()
	_blade_material.shader = BLADE_SHADER
	_blade = _mesh_node("GiantBlade", SwordSpellVisual.sword_mesh(), _blade_material)
	_blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_aura = _mesh_node("JadeSheath", SwordSpellVisual.sword_mesh(),
		SwordSpellVisual.glow_material(JADE))
	_ground_outer = _ring("GroundOuter", 1.0, 0.022, GOLD)
	_ground_inner = _ring("GroundInner", 0.73, 0.015, JADE)
	_ground_marks = _mesh_node("GroundGlyphs", _glyph_mesh(), SwordSpellVisual.glow_material(GOLD))
	_crown_outer = _ring("CrownOuter", 1.0, 0.028, GOLD)
	_crown_inner = _ring("CrownInner", 0.77, 0.016, JADE)
	_crown_marks = _mesh_node("CrownGlyphs", _glyph_mesh(), SwordSpellVisual.glow_material(GOLD))
	_shock_outer = _ring("ShockOuter", 1.0, 0.025, JADE)
	_shock_inner = _ring("ShockInner", 1.0, 0.014, GOLD)
	_line_mesh = ImmediateMesh.new()
	_lines = _mesh_node("EnergyRibbons", _line_mesh, SwordSpellVisual.glow_material(Color.WHITE))
	render_snapshot()


func _process(_delta: float) -> void:
	render_snapshot()


## 可由验收驱动在一次逻辑 tick 后立即画当前快照。
func render_snapshot() -> void:
	if _blade == null:
		return
	visible = is_instance_valid(_data) and _data.phase != "idle"
	if not visible:
		return
	global_transform = Transform3D.IDENTITY
	var data := _data
	var longitudinal := data.sword_length / SwordSpellVisual.TOTAL_LENGTH
	var scale := Vector3(longitudinal * 0.76, longitudinal * 0.76, longitudinal)
	var origin := data.sword_tip - data.sword_forward * SwordSpellVisual.TIP_LENGTH * longitudinal
	_blade.transform = SwordSpellVisual.sword_transform(origin, data.sword_forward, scale)
	_blade_material.set_shader_parameter("opacity", data.sword_alpha)
	_blade_material.set_shader_parameter("radiance", 0.35 + data.charge * 0.7)
	_aura.transform = SwordSpellVisual.sword_transform(origin, data.sword_forward,
		scale * Vector3(1.045, 1.12, 1.003))
	_color(_aura, JADE, data.sword_alpha * (0.09 + data.charge * 0.035))
	var ground_basis := Basis(Quaternion(Vector3.UP, data.rune_normal))
	var ground_position := data.rune_point + data.rune_normal * 0.045
	var radius := data.rune_radius * (0.82 + 0.18 * data.charge)
	_place_ring(_ground_outer, ground_position, ground_basis, radius, GOLD, data.rune_alpha * 0.65)
	_place_ring(_ground_inner, ground_position + data.rune_normal * 0.006, ground_basis,
		radius, JADE, data.rune_alpha * 0.55)
	_place_ring(_ground_marks, ground_position + data.rune_normal * 0.012,
		ground_basis * Basis(Vector3.UP, data.visual_time * 0.16), radius, GOLD, data.rune_alpha * 0.65)
	var crown_alpha := data.sword_alpha * (1.0 - data.phase_progress if data.phase == "descent" else 1.0)
	if data.phase in ["impact", "fade"]:
		crown_alpha = 0.0
	var crown_position := data.rune_point + Vector3.UP * (data.hover_tip_height +
		data.sword_length_m * SwordSpellVisual.TIP_LENGTH / SwordSpellVisual.TOTAL_LENGTH)
	var crown_radius := data.rune_radius * 0.8
	_place_ring(_crown_outer, crown_position, Basis.IDENTITY, crown_radius, GOLD, crown_alpha * 0.82)
	_place_ring(_crown_inner, crown_position + Vector3.UP * 0.035,
		Basis.IDENTITY, crown_radius, JADE, crown_alpha * 0.67)
	_place_ring(_crown_marks, crown_position + Vector3.UP * 0.07,
		Basis(Vector3.UP, -data.visual_time * 0.24), crown_radius, GOLD, crown_alpha * 0.75)
	_draw_impact(data, ground_basis)
	_draw_lines(data, origin)


func _draw_impact(data: GiantSwordDescentComponent, ground_basis: Basis) -> void:
	var alive := data.impact_age >= 0.0 and data.impact_age < 0.6
	_shock_outer.visible = alive
	_shock_inner.visible = alive
	if not alive:
		return
	var progress := clampf(data.impact_age / 0.6, 0.0, 1.0)
	var radius := data.shock_radius * lerpf(0.12, 1.2, pow(progress, 0.48))
	var center := data.target_point + data.target_normal * 0.07
	_place_ring(_shock_outer, center, ground_basis, radius, JADE, (1.0 - progress) * 0.9)
	_place_ring(_shock_inner, center + data.target_normal * 0.01, ground_basis,
		radius * 0.77, GOLD, (1.0 - progress) * 0.8)


func _draw_lines(data: GiantSwordDescentComponent, origin: Vector3) -> void:
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var alpha := data.sword_alpha
	var tip := data.sword_tip
	# 青玉光芯：细带保留剑身暗轮廓。
	var core_end := origin - data.sword_forward * data.sword_length * 0.04
	SwordSpellVisual.append_line(_line_mesh, tip - data.sword_forward * 0.07, core_end,
		0.06, Color(JADE, alpha * 0.48), Color(JADE, alpha * 0.08))
	# 凝剑时光丝沿剑轴向柄流动，进入悬停后收拢。
	if data.phase in ["gather", "hover"]:
		for index in range(6):
			var angle := float(index) * TAU / 6.0 + data.visual_time * 0.7
			var orbit := Vector3(cos(angle), 0.0, sin(angle)) * (0.24 + 0.14 * (1.0 - data.charge))
			var part := fposmod(data.visual_time * 0.65 + float(index) / 6.0, 1.0)
			var from := tip + Vector3.UP * data.sword_length * part + orbit
			var to := from + Vector3.UP * (0.22 + data.charge * 0.28)
			SwordSpellVisual.append_line(_line_mesh, from, to, 0.024,
				Color(JADE, alpha * 0.05), Color(GOLD, alpha * 0.48))
	# 下降的轨迹历史，越旧越淡；世界数据不受 View 帧率影响。
	for index in range(1, data.tip_history.size()):
		var weight := float(index) / float(data.tip_history.size())
		SwordSpellVisual.append_line(_line_mesh, data.tip_history[index - 1], data.tip_history[index],
			0.1 + weight * 0.13, Color(JADE, weight * alpha * 0.16), Color(JADE, weight * alpha * 0.42))
	if data.phase == "descent":
		for index in range(8):
			var angle := float(index) * TAU / 8.0
			var side := Vector3(cos(angle), 0.0, sin(angle)) * (0.4 + float(index % 2) * 0.18)
			var from := tip + Vector3.UP * (0.7 + float(index % 3) * 0.5) + side
			SwordSpellVisual.append_line(_line_mesh, from, from + Vector3.UP *
				(0.4 + data.phase_progress * 2.4), 0.035,
				Color(JADE, 0.4), Color(JADE, 0.0))
	if data.impact_age >= 0.0:
		var progress := clampf(data.impact_age / 0.75, 0.0, 1.0)
		var fade := pow(1.0 - progress, 1.6)
		var plane := Basis(Quaternion(Vector3.UP, data.target_normal))
		for index in range(24):
			var angle := float(index) * TAU / 24.0 + float(data.impact_serial % 5) * 0.07
			var direction := plane * Vector3(cos(angle), 0.0, sin(angle))
			var reach := data.shock_radius * (0.3 + pow(progress, 0.55) * (0.7 + float(index % 3) * 0.15))
			var lift := data.target_normal * sin(progress * PI) * (0.12 + float(index % 4) * 0.09)
			var from := data.target_point + direction * reach + lift
			SwordSpellVisual.append_line(_line_mesh, from, from + direction * (0.23 + fade * 0.42),
				0.04 * fade, Color(GOLD, fade * 0.65), Color(JADE, 0.0))
	_line_mesh.surface_end()


func _mesh_node(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _ring(node_name: String, radius: float, width: float, color: Color) -> MeshInstance3D:
	return _mesh_node(node_name, SwordSpellVisual.ring_mesh(radius, width), SwordSpellVisual.glow_material(color))


func _place_ring(node: MeshInstance3D, position: Vector3, basis: Basis,
		radius: float, color: Color, alpha: float) -> void:
	node.transform = Transform3D(basis.scaled_local(Vector3.ONE * radius), position)
	_color(node, color, alpha)


func _color(node: MeshInstance3D, color: Color, alpha: float) -> void:
	node.visible = alpha > 0.002
	(node.material_override as StandardMaterial3D).albedo_color = Color(color, alpha)


static func _glyph_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(24):
		var angle := float(index) * TAU / 24.0
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		var mid := radial * 0.88
		SwordSpellVisual.append_line(mesh, mid - radial * 0.05, mid + radial * 0.05,
			0.015, Color.WHITE, Color.WHITE)
		SwordSpellVisual.append_line(mesh, mid, mid + tangent * 0.046 + radial * 0.026,
			0.012, Color.WHITE, Color.WHITE)
		SwordSpellVisual.append_line(mesh, mid + radial * 0.035,
			mid + tangent * 0.038 + radial * 0.035, 0.011, Color.WHITE, Color.WHITE)
	mesh.surface_end()
	return mesh
