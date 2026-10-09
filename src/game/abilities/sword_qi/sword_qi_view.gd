class_name SwordQiView
extends MeshInstance3D

## 剑气视图（纯表现）：每帧把 SwordCastComponent.qi_shots 画成水平的月牙剑光加一段渐隐尾迹。
##
## 只读组件，不写任何数据；Compatibility 渲染器没有官方粒子拖尾，因此用 ImmediateMesh 自建网格。
## 用普通透明混合而非加法：加法剑光在浅色地面上几乎看不见。

const COLOR := Color(0.55, 1.0, 0.88)
const EDGE := Color(0.95, 1.0, 0.98)
const SAMPLES := 12
const TAIL_LENGTH := 1.6

var _cast: SwordCastComponent = null
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material_override = material


func bind(cast: SwordCastComponent) -> void:
	_cast = cast


func _process(_delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	_mesh.clear_surfaces()
	if _cast == null or not is_instance_valid(_cast) or _cast.qi_shots.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for value in _cast.qi_shots:
		var shot: Dictionary = value
		var fade := clampf(1.0 - float(shot["travelled"]) / maxf(_cast.qi_range, 0.01), 0.0, 1.0)
		_draw_shot(shot["position"], shot["direction"], _cast.qi_radius, sqrt(fade))
	_mesh.surface_end()


func _draw_shot(center: Vector3, direction: Vector3, radius: float, alpha: float) -> void:
	var side := Vector3.UP.cross(direction).normalized()
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	var tail: Array[Vector3] = []
	for index in range(SAMPLES + 1):
		var u := float(index) / SAMPLES * 2.0 - 1.0
		var bulge := 1.0 - u * u
		var edge := center + side * u * radius - direction * (u * u) * radius * 0.55
		front.append(edge)
		back.append(edge - direction * (0.06 + bulge * radius * 0.3))
		tail.append(edge - direction * (0.1 + bulge * TAIL_LENGTH))
	var edge := Color(EDGE, alpha)
	var core := Color(COLOR, alpha * 0.9)
	var dim := Color(COLOR, alpha * 0.45)
	var clear := Color(COLOR, 0.0)
	for index in range(SAMPLES):
		_quad(front[index], front[index + 1], back[index + 1], back[index], edge, edge, core, core)
		_quad(back[index], back[index + 1], tail[index + 1], tail[index], dim, dim, clear, clear)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	for pair in [[a, ca], [b, cb], [c, cc], [a, ca], [c, cc], [d, cd]]:
		_mesh.surface_set_color(pair[1])
		_mesh.surface_add_vertex(pair[0])
