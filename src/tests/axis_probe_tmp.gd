extends SceneTree
## 直接量：角色在场景里是否真的倾斜（不靠肉眼、不靠相机推测）。
## 对每个场景读骨骼/模型的世界基，算 up 与世界 UP 的夹角（roll/pitch）与 yaw。
const SCENES := {
	"movement_garden": "res://levels/experiments/character_movement/movement_garden.tscn",
	"motion_stage": "res://levels/experiments/character_movement/motion_stage.tscn",
}
var _n := 0
var _cur := ""
var _names: Array = []
var _idx := 0
var _scene: Node
var _results: Array[String] = []

func _initialize() -> void:
	_names = SCENES.keys()
	_load_next()

func _load_next() -> void:
	if _idx >= _names.size():
		print("\n=== 结果 ===")
		for r in _results: print("  " + r)
		quit(0); return
	_cur = _names[_idx]
	if _scene != null: _scene.queue_free()
	_scene = (load(SCENES[_cur]) as PackedScene).instantiate()
	get_root().add_child(_scene)
	_n = 0

func _process(_d: float) -> bool:
	if _scene == null: return false
	_n += 1
	if _n < 20: return false
	var actor := _find_actor(_scene)
	if actor == null:
		_results.append("%-18s 未找到 actor" % _cur); _idx += 1; _load_next(); return false
	var model := actor.get_node_or_null("Visual/CultivatorTripoV9") as Node3D
	var visual := actor.get_node_or_null("Visual") as Node3D
	_results.append("%-18s actor.basis.y 与 UP 夹角=%6.2f°  actor.yaw=%+7.2f°  模型 rot=(%.3f,%.3f,%.3f)"
		% [_cur, rad_to_deg(actor.global_transform.basis.y.angle_to(Vector3.UP)),
		   rad_to_deg(actor.global_transform.basis.get_euler().y),
		   model.rotation.x if model else 0.0, model.rotation.y if model else 0.0, model.rotation.z if model else 0.0])
	if visual != null:
		_results.append("%-18s   Visual rot=(%.3f,%.3f,%.3f)  scale=%s"
			% ["", visual.rotation.x, visual.rotation.y, visual.rotation.z, str(visual.scale)])
	if model != null:
		var sk := _find_skel(model)
		if sk != null:
			var gb := sk.global_transform.basis
			var up := gb.y.normalized()
			_results.append("%-18s   Skeleton up 与世界UP夹角=%6.2f°  forward(模型+Z)=%s"
				% ["", rad_to_deg(up.angle_to(Vector3.UP)), str((gb.z.normalized() * 100).round() / 100)])
	_idx += 1
	_load_next()
	return false

func _find_actor(n: Node) -> CharacterBody3D:
	if n is CharacterBody3D and n.get_script() != null: return n
	for c in n.get_children():
		var r := _find_actor(c)
		if r != null: return r
	return null

func _find_skel(n: Node) -> Skeleton3D:
	var s := n.find_children("*", "Skeleton3D", true, false)
	return (s[0] as Skeleton3D) if not s.is_empty() else null
