class_name TrainingDummy
extends Node3D

## 剑法木桩：竖直圆柱目标 + 阻挡人物的碰撞 + 命中表现。
##
## 命中数据在直系子节点 SwordTargetComponent；本节点只读 hit_count 的变化来闪白与晃动，
## 不做命中判定、不计血量。入树时加入 sword_target 分组供出招能力查询。

const WOOD := Color(0.55, 0.40, 0.25)
const STRAW := Color(0.80, 0.70, 0.42)
const FLASH := Color(1.0, 0.98, 0.9)
## 晃动：每次命中的角速度冲量（弧度/秒）、倾角上限（弧度）、阻尼弹簧刚度与阻尼。
## 剑阵一次可连中多下，倾角必须封顶，否则木桩会被推倒。
const WOBBLE_KICK := 1.6
const WOBBLE_MAX := 0.28
const WOBBLE_STIFFNESS := 120.0
const WOBBLE_DAMPING := 9.0
const FLASH_DECAY := 6.0

var _target: SwordTargetComponent = null
var _pivot: Node3D = null
var _materials: Array[StandardMaterial3D] = []
var _seen_hits := 0
var _flash := 0.0
var _tilt := Vector2.ZERO
var _tilt_velocity := Vector2.ZERO


func _ready() -> void:
	add_to_group(&"sword_target")
	_target = get_node("SwordTargetComponent") as SwordTargetComponent
	assert(_target != null, "TrainingDummy: 缺少 SwordTargetComponent")
	_build_visual()


func target() -> SwordTargetComponent:
	return _target


func flash_amount() -> float:
	return _flash


func _process(delta: float) -> void:
	if _target.hit_count != _seen_hits:
		if _target.hit_count > _seen_hits:
			_kick(_target.last_hit_point)
		_seen_hits = _target.hit_count
	_flash = maxf(_flash - FLASH_DECAY * delta, 0.0)
	for material in _materials:
		material.emission_energy_multiplier = _flash * 1.6
	var accel := -_tilt * WOBBLE_STIFFNESS - _tilt_velocity * WOBBLE_DAMPING
	_tilt_velocity += accel * delta
	_tilt += _tilt_velocity * delta
	if _tilt.length() > WOBBLE_MAX:
		_tilt = _tilt.limit_length(WOBBLE_MAX)
		_tilt_velocity *= 0.5
	_pivot.rotation = Vector3(_tilt.y, 0.0, -_tilt.x)


func _kick(point: Vector3) -> void:
	_flash = 1.0
	var away := global_position - point
	away.y = 0.0
	var push := Vector2(away.x, away.z).normalized() if away.length_squared() > 0.0001 else Vector2(0.0, 1.0)
	_tilt_velocity += push * WOBBLE_KICK


func _build_visual() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var height := _target.height
	_add_part(_cylinder(0.12, height), Vector3(0.0, height * 0.5, 0.0), WOOD)
	_add_part(_cylinder(_target.radius, height * 0.45), Vector3(0.0, height * 0.58, 0.0), STRAW)
	var arm := BoxMesh.new()
	arm.size = Vector3(1.1, 0.1, 0.1)
	_add_part(arm, Vector3(0.0, height * 0.82, 0.0), WOOD)
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.36
	_add_part(head, Vector3(0.0, height + 0.12, 0.0), STRAW)
	var base := CylinderMesh.new()
	base.top_radius = 0.45
	base.bottom_radius = 0.5
	base.height = 0.08
	var base_node := MeshInstance3D.new()
	base_node.name = "Base"
	base_node.mesh = base
	base_node.position = Vector3(0.0, 0.04, 0.0)
	base_node.material_override = _material(WOOD.darkened(0.3))
	add_child(base_node)


func _add_part(mesh: Mesh, offset: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = offset
	var material := _material(color)
	material.emission_enabled = true
	material.emission = FLASH
	material.emission_energy_multiplier = 0.0
	_materials.append(material)
	node.material_override = material
	_pivot.add_child(node)


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	return mesh


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
