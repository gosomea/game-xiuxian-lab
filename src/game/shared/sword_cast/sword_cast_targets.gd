class_name SwordCastTargets
extends RefCounted

## 无状态几何查询：只读 sword_target 圆柱数据。三维区间相交避免垂直高速贯穿漏判。
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
		if t >= 0.0:
			hits.append({"target": target, "point": from.lerp(to, t), "id": host.get_instance_id(), "t": t})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	return hits


## 圆形落地冲击，Y 范围 center.y..center.y+height；与目标实际高度重叠才命中。
static func burst(tree: SceneTree, center: Vector3, radius: float, height: float,
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
		var delta := Vector2(host.global_position.x - center.x, host.global_position.z - center.z)
		if delta.length() > radius + target.radius:
			continue
		if host.global_position.y > center.y + height or host.global_position.y + target.height < center.y:
			continue
		var point := Vector3(host.global_position.x, clampf(center.y, host.global_position.y,
			host.global_position.y + target.height), host.global_position.z)
		hits.append({"target": target, "point": point, "id": host.get_instance_id()})
	return hits


static func component_of(host: Node) -> SwordTargetComponent:
	for child in host.get_children():
		if child is SwordTargetComponent:
			return child
	return null


## 膨胀圆柱的水平二次方程区间与竖直 slab 区间求交，返回最早交叉 t。
static func _segment_cylinder(from: Vector3, to: Vector3, radius: float, base: Vector3,
		cylinder_radius: float, height: float) -> float:
	var a := Vector2(from.x - base.x, from.z - base.z)
	var d := Vector2(to.x - from.x, to.z - from.z)
	var reach := cylinder_radius + radius
	var lo := 0.0
	var hi := 1.0
	var aa := d.length_squared()
	var cc := a.length_squared() - reach * reach
	if aa < 0.00000001:
		if cc > 0.0:
			return -1.0
	else:
		var bb := 2.0 * a.dot(d)
		var discriminant := bb * bb - 4.0 * aa * cc
		if discriminant < 0.0:
			return -1.0
		var root := sqrt(discriminant)
		lo = maxf(lo, (-bb - root) / (2.0 * aa))
		hi = minf(hi, (-bb + root) / (2.0 * aa))
	var dy := to.y - from.y
	var bottom := base.y - radius
	var top := base.y + height + radius
	if absf(dy) < 0.00000001:
		if from.y < bottom or from.y > top:
			return -1.0
	else:
		var t0 := (bottom - from.y) / dy
		var t1 := (top - from.y) / dy
		lo = maxf(lo, minf(t0, t1))
		hi = minf(hi, maxf(t0, t1))
	return lo if lo <= hi and hi >= 0.0 and lo <= 1.0 else -1.0
