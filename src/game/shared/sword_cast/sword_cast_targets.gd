class_name SwordCastTargets
extends RefCounted

## 剑法命中判定（无状态静态设施）：投射物本帧位移线段对 sword_target 分组里的竖直圆柱求交。
##
## 不依赖物理帧与碰撞层，无头测试可逐 tick 精确推进。目标宿主须是 Node3D，
## 其直系子节点中有 SwordTargetComponent。


## 本帧位移 from→to、半宽 radius 扫过的目标；跳过 skip 中已命中的实例 id。
## 返回 [{target: SwordTargetComponent, point: Vector3, id: int}]，按沿线段先后排序。
static func sweep(tree: SceneTree, from: Vector3, to: Vector3, radius: float,
		skip: Dictionary = {}) -> Array:
	var hits: Array = []
	if tree == null:
		return hits
	for node in tree.get_nodes_in_group(&"sword_target"):
		var host := node as Node3D
		if host == null or not host.is_inside_tree() or skip.has(host.get_instance_id()):
			continue
		var target := component_of(host)
		if target == null:
			continue
		var t := _segment_cylinder(from, to, radius, host.global_position, target.radius, target.height)
		if t < 0.0:
			continue
		hits.append({"target": target, "point": from.lerp(to, t), "id": host.get_instance_id(), "t": t})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	return hits


static func component_of(host: Node) -> SwordTargetComponent:
	for child in host.get_children():
		if child is SwordTargetComponent:
			return child
	return null


## 线段与竖直圆柱（膨胀 radius）是否相交；相交返回线段上最近点参数 t∈[0,1]，否则 -1。
static func _segment_cylinder(from: Vector3, to: Vector3, radius: float, base: Vector3,
		cylinder_radius: float, height: float) -> float:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var c := Vector2(base.x, base.z)
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.000001:
		t = clampf((c - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	if (a + ab * t).distance_to(c) > cylinder_radius + radius:
		return -1.0
	var y := lerpf(from.y, to.y, t)
	if y < base.y - radius or y > base.y + height + radius:
		return -1.0
	return t
