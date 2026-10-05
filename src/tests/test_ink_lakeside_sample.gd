extends RefCounted

const SCENE := "res://levels/experiments/character_movement/ink_lakeside_sample.tscn"


static func run(t) -> void:
	t.begin_case()
	var scene := (load(SCENE) as PackedScene).instantiate()
	t.track(scene)
	await _frames(scene, 30)
	var actor := scene.find_child("Swordsman", true, false) as Swordsman
	t.assert_true(actor.motion().on_floor, "湖岸出生点实际落地")
	for _i in range(8):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		Input.parse_input_event(wheel)
	await _frames(scene, 60)
	var camera := scene.get_node("Camera3D") as Camera3D
	var safe_frame := scene.get_viewport().get_visible_rect().grow(-30)
	t.assert_true(safe_frame.has_point(camera.unproject_position(actor.global_position)), "滚轮近景保留人物脚底")
	t.assert_true(safe_frame.has_point(camera.unproject_position(actor.global_position + Vector3.UP * 1.8)), "滚轮近景保留人物头部")
	_key(KEY_R)
	await _frames(scene, 30)
	var space := actor.get_world_3d().direct_space_state
	for point: Vector3 in [Vector3(0, 0, 10), Vector3(9, 0, -5), Vector3(9, 0, -13), Vector3(-9, 0, -4.7)]:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point + Vector3.DOWN * 2)
		query.exclude = [actor.get_rid()]
		t.assert_true(not space.intersect_ray(query).is_empty(), "岸、桥、岛、塔前平台有落脚碰撞：%s" % point)
	var water := PhysicsRayQueryParameters3D.create(Vector3(0, 1, -20), Vector3(0, -1, -20))
	t.assert_true(space.intersect_ray(water).is_empty(), "湖水没有隐形可步行地面")
	actor.global_position = Vector3(0, -1.8, -20)
	await _frames(scene, 30)
	t.assert_true(actor.motion().on_floor and actor.global_position.distance_to(Vector3(0, 0, 10)) < 0.1,
		"落水自动回出生点并恢复站立")
	_key(KEY_F)
	await _frames(scene, 20)
	actor.global_position = Vector3(9, 2.5, -13)
	_key(KEY_F)
	await _frames(scene, 60)
	t.assert_true(actor.motion().on_floor and absf(actor.global_position.y - 0.05) < 0.03,
		"御剑收剑实际降落小岛")
	t.assert_false(actor.motion().flight_active, "岛上降落解除御剑")
	t.assert_false(actor.flight_visual_node().visible, "岛上降落收起飞剑")
	_key(KEY_R)
	await _frames(scene, 30)
	_key(KEY_F)
	await _frames(scene, 20)
	actor.global_position = Vector3(-9, 2.5, -4.7)
	_key(KEY_F)
	await _frames(scene, 60)
	t.assert_true(actor.motion().on_floor and absf(actor.global_position.y - 0.6) < 0.03,
		"御剑收剑实际降落塔前高台")
	# Scene-only material overrides must not mutate the imported shared character mesh.
	var source := (load("res://game/actors/swordsman/swordsman.tscn") as PackedScene).instantiate()
	var meshes := source.get_node("Visual").find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		for surface in range(mesh.mesh.get_surface_count()):
			t.assert_true(mesh.get_active_material(surface) is StandardMaterial3D, "共享角色源材质未被样板覆盖")
	source.free()


static func _frames(scene: Node, count: int) -> void:
	for _i in range(count):
		await scene.get_tree().physics_frame
		await scene.get_tree().process_frame


static func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
