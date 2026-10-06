extends RefCounted

const SCENE := "res://levels/experiments/character_movement/west_lake_sunset.tscn"


static func run(t) -> void:
	t.begin_case()
	var scene := (load(SCENE) as PackedScene).instantiate()
	t.track(scene)
	await _frames(scene, 30)
	var actor := scene.find_child("Swordsman", true, false) as Swordsman
	t.assert_true(actor.motion().on_floor, "西湖出生点落地")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/experiments/character_movement/west_lake_sunset_layout.json"))
	var space := actor.get_world_3d().direct_space_state
	for p: Array in layout["ray_points"]:
		var point := Vector3(float(p[0]),float(p[1]),float(p[2]))
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point+Vector3.DOWN*2)
		ray.exclude = [actor.get_rid()]
		t.assert_true(not space.intersect_ray(ray).is_empty(), "环岸、苏堤、断桥、三岛落脚碰撞：%s" % point)
	var water := PhysicsRayQueryParameters3D.create(Vector3(25,2,30),Vector3(25,-2,30))
	t.assert_true(space.intersect_ray(water).is_empty(), "西湖水面无隐形地面")
	for pair: Array in [[KEY_2,"fixed_follow"],[KEY_3,"quarter_turn"],[KEY_4,"overview"],[KEY_1,"orbit"]]:
		_key(pair[0], true)
		_key(pair[0], false)
		await _frames(scene, 25)
		t.assert_eq(scene.rig().mode_id(), pair[1], "数字键切换共享镜头 %s" % pair[1])
	_key(KEY_V,true); _key(KEY_V,false)
	await _frames(scene, 30)
	t.assert_eq(scene.rig().component().projection, Camera3D.PROJECTION_ORTHOGONAL, "V 切正交由共享镜头执行")
	_key(KEY_V,true); _key(KEY_V,false)
	await _frames(scene, 30)
	t.assert_eq(scene.rig().component().projection, Camera3D.PROJECTION_PERSPECTIVE, "V 切回透视")
	_key(KEY_F,true); _key(KEY_F,false)
	await _frames(scene, 20)
	_key(KEY_SPACE,true)
	await _frames(scene, 300)
	t.assert_true(actor.global_position.y > 32 and actor.global_position.y < 43, "连续上升真实进入世界云层")
	t.assert_true(scene.cloud_density(actor.global_position.y) > .8, "云中遮蔽达到峰值")
	await _frames(scene, 190)
	_key(KEY_SPACE,false)
	await _frames(scene, 10)
	t.assert_true(actor.global_position.y > 48, "地面连续直飞越过云顶")
	t.assert_true(actor.motion().flight_active and actor.flight_visual_node().visible, "云顶仍使用共享御剑状态和飞剑")
	t.assert_eq(scene.cloud_density(actor.global_position.y), 0.0, "离开云顶恢复清晰天空")
	t.assert_true(scene.rig().snapshot()["focus"].y > 48, "镜头焦点跟随到云上")
	# Shared flight off must physically land on the three separate islands and sloped bridge.
	for p: Array in layout["landings"]:
		_key(KEY_R,true); _key(KEY_R,false)
		await _frames(scene, 20)
		_key(KEY_F,true); _key(KEY_F,false)
		await _frames(scene, 20)
		var landing := Vector3(float(p[0]),float(p[1]),float(p[2]))
		actor.global_position = landing + Vector3.UP * 2.0
		_key(KEY_F,true); _key(KEY_F,false)
		await _frames(scene, 65)
		t.assert_true(actor.motion().on_floor and absf(actor.global_position.y-landing.y)<.08,
			"实际降落堤桥、岛台、塔前：%s" % landing)
	_key(KEY_R,true); _key(KEY_R,false)
	await _frames(scene, 20)
	actor.global_position = Vector3(25,-2.6,30)
	await _frames(scene, 30)
	t.assert_true(actor.motion().on_floor and actor.global_position.distance_to(Vector3(82,.0,20))<.2, "落水回湖滨并恢复站立")
	_key(KEY_M,true); _key(KEY_M,false)
	await _frames(scene, 30)
	t.assert_eq(scene.rig().mode_id(), "overview", "M 进入共享俯览")
	t.assert_eq(scene.rig().component().size, 210.0, "全景范围覆盖压缩西湖")
	_key(KEY_R,true); _key(KEY_R,false)
	await _frames(scene, 30)
	t.assert_eq(scene.rig().mode_id(), "orbit", "复位恢复环绕和默认投影")
	t.assert_eq(scene.rig().component().projection, Camera3D.PROJECTION_PERSPECTIVE, "复位恢复默认透视状态")


static func _frames(scene: Node, count: int) -> void:
	for _i in range(count):
		await scene.get_tree().physics_frame
		await scene.get_tree().process_frame


static func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
