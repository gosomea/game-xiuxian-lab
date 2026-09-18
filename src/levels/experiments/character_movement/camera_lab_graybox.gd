class_name CameraLabGraybox
extends RefCounted

## 镜头实验室的灰盒几何装配（纯实验资产，只在镜头实验里使用）。
##
## 目标：用最小几何让「跟随策略差异」和「遮挡」在同一画面里可比，
## 不做完整地图、不做美术。所有块体同时生成可见网格与静态碰撞盒。
##
## 场地（米）：x ∈ [-20, 20]，z ∈ [-16, 16]，地面 y = 0。
## 布局要点：中央空地留出推进距离；墙/门洞、遮挡板、高低柱、坡、
## 高台沿 +x 方向依次排开，便于一次推进观察全部跟随行为。

const PALETTE_GROUND := Color(0.62, 0.64, 0.60, 1.0)
const PALETTE_BLOCK := Color(0.78, 0.76, 0.70, 1.0)
const PALETTE_WALL := Color(0.74, 0.71, 0.66, 1.0)
const PALETTE_PILLAR_TALL := Color(0.68, 0.72, 0.76, 1.0)
const PALETTE_PILLAR_LOW := Color(0.76, 0.72, 0.62, 1.0)
const PALETTE_OCCLUDER := Color(0.55, 0.58, 0.55, 1.0)
const PALETTE_SLOPE := Color(0.70, 0.66, 0.58, 1.0)
const PALETTE_PLATFORM := Color(0.66, 0.70, 0.66, 1.0)
const PALETTE_GRID := Color(0.44, 0.47, 0.45, 0.55)
const PALETTE_RULER := Color(0.36, 0.40, 0.38, 0.85)

const COLLISION_LAYER := 1


## 建整个灰盒：地面、墙与门洞、遮挡板、高低柱、坡、高台、网格与距离标尺。
static func build(parent: Node3D) -> void:
	var materials := _build_materials()
	_build_ground(parent, materials)
	_build_axis_ruler(parent, materials)
	_build_wall_with_door(parent, materials)
	_build_occluders(parent, materials)
	_build_pillars(parent, materials)
	_build_slope(parent, materials)
	_build_high_platform(parent, materials)


## 地面：一块可碰撞大板，顶面 y = 0。
static func _build_ground(parent: Node3D, materials: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Ground"
	parent.add_child(root)
	add_box(root, materials["ground"], "GroundSlab", Vector3(0.0, -0.25, 0.0), Vector3(40.0, 0.5, 32.0))
	# 网格：每 2 m 一条细线，帮助读数位移与相机基方向。
	var index := 0
	for x in range(-20, 21, 2):
		index += 1
		add_box(root, materials["grid"], "GridX%d" % index, Vector3(float(x), 0.005, 0.0), Vector3(0.05, 0.01, 32.0), false)
	for z in range(-16, 17, 2):
		index += 1
		add_box(root, materials["grid"], "GridZ%d" % index, Vector3(0.0, 0.005, float(z)), Vector3(40.0, 0.01, 0.05), false)


## 距离标尺：沿 +x 每 5 m 一个宽条，用来目测相机与角色的相对推进。
static func _build_axis_ruler(parent: Node3D, materials: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Ruler"
	parent.add_child(root)
	for step in range(1, 5):
		var x := float(step) * 5.0
		add_box(root, materials["ruler"], "TickX%d" % step, Vector3(x, 0.01, 0.0), Vector3(0.5, 0.02, 1.4), false)
		add_box(root, materials["ruler"], "TickX%dSide" % step, Vector3(x, 0.01, 8.0), Vector3(0.5, 0.02, 1.4), false)
	# 距离读数柱：每 10 m 一根细高柱，遮挡无关但让远近可判。
	for step in range(1, 3):
		var x := float(step) * 10.0
		add_box(root, materials["pillar_low"], "RulerPost%d" % step, Vector3(x, 1.0, -14.0), Vector3(0.25, 2.0, 0.25))


## 墙与门洞：z = +4 处一道墙，中央留 3 m 门洞，用来观察穿门时的遮挡与跟随。
static func _build_wall_with_door(parent: Node3D, materials: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "WallWithDoor"
	parent.add_child(root)
	var height := 2.2
	var thickness := 0.4
	# 门洞 x ∈ [-1.5, 1.5]；两侧墙段各延伸到 x = ±11。
	add_box(root, materials["wall"], "WallWest", Vector3(-6.25, height * 0.5, 4.0), Vector3(9.5, height, thickness))
	add_box(root, materials["wall"], "WallEast", Vector3(6.25, height * 0.5, 4.0), Vector3(9.5, height, thickness))
	add_box(root, materials["wall"], "DoorLintel", Vector3(0.0, height - 0.25, 4.0), Vector3(3.0, 0.5, thickness))


## 遮挡物：一组高低错落的窄板与方块，制造相机与角色之间的视线遮挡。
static func _build_occluders(parent: Node3D, materials: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Occluders"
	parent.add_child(root)
	add_box(root, materials["occluder"], "OccluderTall", Vector3(6.0, 2.0, -2.0), Vector3(3.0, 4.0, 0.35))
	add_box(root, materials["occluder"], "OccluderShort", Vector3(10.5, 0.9, 1.5), Vector3(2.4, 1.8, 0.35))
	add_box(root, materials["occluder"], "OccluderCube", Vector3(13.5, 1.2, -4.5), Vector3(2.0, 2.4, 2.0))
	add_box(root, materials["occluder"], "OccluderWedge", Vector3(3.0, 1.0, -8.0), Vector3(2.2, 2.0, 2.2))


## 高低柱：4 根高度递减的柱子，观察目标垂直移动时的跟随差。
static func _build_pillars(parent: Node3D, materials: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Pillars"
	parent.add_child(root)
	add_box(root, materials["pillar_tall"], "PillarTall", Vector3(-8.0, 2.0, -6.0), Vector3(1.6, 4.0, 1.6))
	add_box(root, materials["pillar_tall"], "PillarMid", Vector3(-11.0, 1.25, -2.0), Vector3(1.6, 2.5, 1.6))
	add_box(root, materials["pillar_low"], "PillarLow", Vector3(-8.0, 0.5, 2.0), Vector3(1.6, 1.0, 1.6))
	add_box(root, materials["pillar_low"], "PillarStub", Vector3(-13.0, 0.2, 5.0), Vector3(1.6, 0.4, 1.6))


## 坡：从 y = 0 升到 y = 1.5 的连续斜面，验证跟随在斜坡上不抖。
static func _build_slope(parent: Node3D, materials: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Slope"
	parent.add_child(root)
	var length := 8.0
	var rise := 1.5
	var center := Vector3(-16.0, rise * 0.5, -10.0)
	var angle := atan2(rise, length)
	add_box(root, materials["slope"], "SlopeRamp", center, Vector3(length, 0.3, 5.0), true, Vector3(0.0, 0.0, angle))


## 高台：y = 2.4 的方形平台，供观察高落差时的焦点与遮挡关系。
static func _build_high_platform(parent: Node3D, materials: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "HighPlatform"
	parent.add_child(root)
	add_box(root, materials["platform"], "PlatformTop", Vector3(16.0, 2.3, -8.0), Vector3(7.0, 0.4, 7.0))
	add_box(root, materials["platform"], "PlatformBase", Vector3(16.0, 1.1, -8.0), Vector3(5.0, 2.2, 5.0))
	add_box(root, materials["platform"], "PlatformStep1", Vector3(11.0, 0.3, -8.0), Vector3(2.0, 0.6, 3.0))
	add_box(root, materials["platform"], "PlatformStep2", Vector3(12.5, 0.9, -8.0), Vector3(1.6, 1.8, 3.0))


## 生成一个块体：网格 + 碰撞盒 + 材质，可选绕自身旋转（坡用）。
static func add_box(parent: Node3D, material: Material, block_name: String, position: Vector3, size: Vector3, solid: bool = true, rotation: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = position
	body.rotation = rotation
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = COLLISION_LAYER
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material
	mesh_instance.mesh = box_mesh
	body.add_child(mesh_instance)
	if solid:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
	parent.add_child(body)
	return body


static func _build_materials() -> Dictionary:
	return {
		"ground": _material(PALETTE_GROUND),
		"block": _material(PALETTE_BLOCK),
		"wall": _material(PALETTE_WALL),
		"pillar_tall": _material(PALETTE_PILLAR_TALL),
		"pillar_low": _material(PALETTE_PILLAR_LOW),
		"occluder": _material(PALETTE_OCCLUDER),
		"slope": _material(PALETTE_SLOPE),
		"platform": _material(PALETTE_PLATFORM),
		"grid": _unshaded(PALETTE_GRID),
		"ruler": _unshaded(PALETTE_RULER),
	}


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material


static func _unshaded(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
