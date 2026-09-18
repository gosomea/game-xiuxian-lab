extends SceneTree

## 群山宗门移动探索集成验收：真实场景 + 真实物理 + 真实输入事件。
## 依据 docs/experiments/traversal-contract.md 与 docs/experiments/traversal-acceptance-plan.md。
##
## 用法（分批，单进程 <45s）：
##   Godot --headless --path src --script res://tests/mountain_traversal_playtest.gd -- --batch=assembly,move,jump,flight,tags,reset,hub
## 窗口截图（真实输入飞行，非传送摆拍）：
##   Godot --path src --script res://tests/mountain_traversal_playtest.gd -- --capture-prefix=/abs/prefix
##
## 断言纪律：坐标全部读布局 JSON，不硬编码早期文档值；碰撞断言必须命中指定碰撞体本体；
## 失败即退出码 1，不吞错、不放宽阈值。

const SCENE := "res://levels/experiments/character_movement/mountain_realm.tscn"
const LAYOUT_PATH := "res://levels/experiments/character_movement/mountain_realm_layout.json"
const COURTYARD_COLLISION_PATH := "res://levels/experiments/character_movement/mountain_realm_courtyards_collision.json"
const SWORD_NODE_PATH := "Visual/FlyingSword"
const HUB_SCENE_NAME := "LabHub"
const MOVE_MODULE := "character_movement"
const SWORD_MODULE := "sword_combat"
const FLIGHT_TAG := &"sword_flight_block"
const GRAVITY := 18.0
const MOVE_SPEED := 4.0
const FLIGHT_SPEED := 12.0
## 物理位置容差：0.08 m 覆盖 60Hz 单步落地修正；只用于位置断言。
const POS_TOL := 0.08
## 竖直速度容差（m/s）。
const VERT_TOL := 0.05
const COMBAT_KEYWORDS := ["slash", "attack", "hitbox", "hurtbox", "damage", "projectile"]
## 截图等待上限：窗口被遮挡时 macOS 会节流渲染，放宽到 15s 并重试一次，避免环境抖动误判。
const CAPTURE_TIMEOUT_MSEC := 15000

var _failed := 0
var _prefix := ""
var _only: PackedStringArray = []
## 截图子集：--shot=overview,sect,flight,landing-summit,landing-north,small（分批保证单进程 <45s）。
var _shots: PackedStringArray = []
var _actor: Swordsman
var _motion: SwordsmanMotionComponent
var _manager: CapabilityManager
var _camera: Camera3D
var _layout: Dictionary = {}
var _spawn := Vector3.ZERO
var _frame_drawn := false
## 巡航诊断：每 120 帧记录一次位置，便于定位真实输入飞行路径问题。
var _cruise_trace: Array[String] = []
var _cruise_step := 0.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
		elif argument.begins_with("--batch="):
			_only = argument.trim_prefix("--batch=").split(",", false)
		elif argument.begins_with("--shot="):
			_shots = argument.trim_prefix("--shot=").split(",", false)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var error := change_scene_to_file(SCENE)
	if error != OK:
		print("FAIL 无法加载场景：%s（错误 %d）" % [SCENE, error])
		quit(1)
		return
	await scene_changed
	await _frames(8)
	_bind()
	if _actor == null:
		_check(false, "场景缺少 Swordsman 角色根")
		_finish()
		return
	if not _prefix.is_empty():
		await _run_capture()
		return
	await _run_batches()
	_finish()


func _run_batches() -> void:
	if _has("assembly"):
		print("--- batch assembly ---")
		await _batch_assembly()
	if _has("move"):
		print("--- batch move ---")
		await _batch_move()
	if _has("jump"):
		print("--- batch jump ---")
		await _batch_jump()
	if _has("flight"):
		print("--- batch flight ---")
		await _batch_flight()
	if _has("tags"):
		print("--- batch tags ---")
		await _batch_tags()
	if _has("reset"):
		print("--- batch reset ---")
		await _batch_reset()
	if _has("mutex"):
		print("--- batch mutex ---")
		await _batch_mutex()
	if _has("focus"):
		print("--- batch focus ---")
		await _batch_focus()
	if _has("collision"):
		print("--- batch collision ---")
		await _batch_collision()
	if _has("landing_summit"):
		print("--- batch landing_summit ---")
		await _batch_landing("summit_sect")
	if _has("landing_north"):
		print("--- batch landing_north ---")
		await _batch_landing("north_pavilion")
	if _has("step"):
		print("--- batch step ---")
		await _batch_step()
	if _has("blocked"):
		print("--- batch blocked ---")
		await _batch_blocked()
	if _has("removal"):
		print("--- batch removal ---")
		await _batch_removal()
	if _has("bounds"):
		print("--- batch bounds ---")
		await _batch_bounds()
	if _has("hall"):
		print("--- batch hall ---")
		await _batch_hall()
	if _has("valley"):
		print("--- batch valley ---")
		await _batch_valley()
	if _has("presentation"):
		print("--- batch presentation ---")
		await _batch_presentation()
	if _has("hub"):
		print("--- batch hub ---")
		await _batch_hub()


func _has(batch: String) -> bool:
	return _only.is_empty() or _only.has(batch)


# --- 装配 -------------------------------------------------------------------


func _batch_assembly() -> void:
	await _reset_via_r()
	_check(_layout.size() > 0, "布局 JSON 解析成功：%s" % LAYOUT_PATH)
	_check(_camera != null and _manager != null and _motion != null, "角色 / 能力管理器 / 组件 / 相机齐备")
	if _actor == null or _manager == null:
		return
	var caps := _manager.sorted_capabilities()
	var names: Array[String] = []
	for cap in caps:
		names.append(str(cap.get_script().get_global_name()))
	_check(names == ["SwordFlight", "Jump", "SwordsmanMovement"], "三能力按调度顺序装配：%s" % str(names))
	_check(caps.size() == 3 and caps[0].priority == 100 and caps[1].priority == 50 and caps[2].priority == 0,
		"priority 为 100 / 50 / 0")

	var box_root := current_scene.get_node_or_null("World/BoxCollision")
	var boxes: Array = _layout["boxes"]
	_check(box_root != null and box_root.get_child_count() == boxes.size(),
		"盒碰撞体数量与布局一致：%d" % boxes.size())

	var shell_root := current_scene.get_node_or_null("World/ShellCollision")
	var expected_nodes: Array[String] = []
	for value in _layout["collision"]["mountains"] as Array:
		var mountain: Dictionary = value
		var node_name := str(mountain["node"])
		expected_nodes.append(node_name)
		var body := shell_root.get_node_or_null(node_name) as StaticBody3D if shell_root != null else null
		_check(body != null, "山体碰撞壳存在且为 StaticBody3D：%s" % node_name)
		if body != null:
			_check_mountain_shell_covers(body, mountain)
	_check(shell_root != null and shell_root.get_child_count() == expected_nodes.size(),
		"每峰恰有一个碰撞壳节点：期望 %d，实际 %d" % [expected_nodes.size(), shell_root.get_child_count() if shell_root != null else -1])

	# 落点承载：平台盒（75 盒之一）必须真实托住每个落点，地形不遮挡。
	await _frames(4)
	var platform_by_landing := {
		"spawn_courtyard": "front_mesa_top",
		"summit_sect": "summit_terrace",
		"north_pavilion": "north_peak_top",
	}
	for value in _layout["landing_points"] as Array:
		var point: Dictionary = value
		var marker := current_scene.get_node_or_null("World/LandingPoints/%s" % str(point["name"])) as Marker3D
		var center: Array = point["center"]
		var want := Vector3(float(center[0]), float(point["top_y"]), float(center[1]))
		_check(marker != null and marker.position.distance_to(want) < 0.001,
			"落点标记与 JSON 一致：%s" % str(point["name"]))
		var platform_name := str(platform_by_landing.get(str(point["name"]), ""))
		var expected_platform := current_scene.get_node_or_null("World/BoxCollision/%s" % platform_name)
		var hit := _ray_down(want + Vector3(0.0, 2.0, 0.0), 30.0)
		_check(expected_platform != null and hit != null and hit["collider"] == expected_platform
			and absf((hit["position"] as Vector3).y - float(point["top_y"])) < 0.06,
			"落点 %s 由平台盒 %s 承载（顶面 %.2f）" % [
				str(point["name"]), platform_name,
				(hit["position"] as Vector3).y if hit != null else -999.0])

	# 庭院附加层：独立容器恰好 33 盒、视觉已装配、与 75 盒无重名。
	var courtyard_root := current_scene.get_node_or_null("World/CourtyardCollision")
	var courtyard_boxes := _read_json_boxes(COURTYARD_COLLISION_PATH)
	_check(courtyard_root != null and courtyard_boxes.size() == 33,
		"庭院附加碰撞盒数量：%d" % courtyard_boxes.size())
	_check(courtyard_root != null and courtyard_root.get_child_count() == courtyard_boxes.size(),
		"庭院碰撞容器与 JSON 一致：%d" % (courtyard_root.get_child_count() if courtyard_root != null else -1))
	var courtyard_names_ok := true
	for box_name in courtyard_boxes:
		if courtyard_root == null or courtyard_root.get_node_or_null(str(box_name)) == null:
			courtyard_names_ok = false
			break
		if box_root != null and box_root.get_node_or_null(str(box_name)) != null:
			courtyard_names_ok = false
			break
	_check(courtyard_names_ok, "庭院盒逐项注册且与 75 盒无重名")
	var courtyard_visual := current_scene.get_node_or_null("World/CourtyardVisual") as Node3D
	_check(courtyard_visual != null
		and courtyard_visual.find_children("*", "MeshInstance3D", true, false).size() >= 17,
		"庭院视觉已装配（材质合并节点 ≥ 17）")

	# 地形阴影：唯一 Terrain 主高度场关投影（消自阴影条纹），树/灌木仍投影。
	var terrain_meshes := current_scene.find_children("Terrain", "MeshInstance3D", true, false)
	_check(terrain_meshes.size() == 1
		and (terrain_meshes[0] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"地形主高度场 Terrain 唯一且关闭投影（实际 %d 个）" % terrain_meshes.size())
	var tree_shadow_on := 0
	for node in current_scene.find_children("pine_*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			tree_shadow_on += 1
	_check(tree_shadow_on > 0, "松树仍保留投影（%d 个节点）" % tree_shadow_on)

	# 主殿分墙盒不得整盒堵空腔：内部 (4,38,-51) 与南门洞 (4,38,-46.5) 必须无碰撞。
	await _frames(4)
	_check_cavity_free(Vector3(4.0, 38.0, -51.0), "主殿内部")
	_check_cavity_free(Vector3(4.0, 38.0, -46.5), "主殿南门洞")
	_check(current_scene.get_node_or_null("World/Boundaries/Ceiling") != null, "按 bounds 建了天花约束高度")
	_check(_actor.global_position.distance_to(_spawn) < 0.25, "角色出生于 JSON spawn（%s）" % str(_spawn))

	var sword := _actor.get_node_or_null(SWORD_NODE_PATH) as Node3D
	_check(sword != null and not sword.visible, "御剑视觉已由场景绑定且初始隐藏")
	_check(sword != null and sword.find_children("*", "MeshInstance3D", true, false).size() > 0, "御剑 GLB 含可见网格")
	var status := current_scene.find_child("Status", true, false) as Label
	_check(status != null and status.text.begins_with("状态：步行"),
		"HUD 初始状态为步行：%s" % (status.text if status != null else "<缺失>"))
	_check_no_combat_rig()
	_check_single_commit_point()


## 高度场重构后：每峰壳必须是有面网格、从谷底（y≤0.5）连续覆盖到该峰台顶，
## 且覆盖自己的台顶中心（回落点由平台盒承载，壳不得缺失对应山体）。
func _check_mountain_shell_covers(body: StaticBody3D, mountain: Dictionary) -> void:
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := shape_node.shape as ConcavePolygonShape3D
	if shape == null:
		_check(false, "山体壳 %s 缺少 ConcavePolygonShape3D" % body.name)
		return
	var faces := shape.get_faces()
	if faces.is_empty():
		_check(false, "山体壳 %s 的面数据为空" % body.name)
		return
	var aabb := AABB(faces[0], Vector3.ZERO)
	for point in faces:
		aabb = aabb.expand(point)
	var top_y := float(mountain["top_y"])
	_check(aabb.position.y <= 0.5 and aabb.end.y >= top_y - 0.5,
		"山体壳 %s 垂直覆盖 0→%.1f（实际 %.2f→%.2f）" % [
			body.name, top_y, aabb.position.y, aabb.end.y])
	# 台顶必须落在本壳水平跨度内（用壳顶附近顶点判断，避免 AABB 被远脊拉大造成假通过）。
	var summit: Variant = mountain.get("landing", null)
	if summit != null:
		for value in _layout["landing_points"] as Array:
			var point: Dictionary = value
			if str(point["name"]) != str(summit):
				continue
			var center: Array = point["center"]
			_check(aabb.position.x <= float(center[0]) and aabb.end.x >= float(center[0])
				and aabb.position.z <= float(center[1]) and aabb.end.z >= float(center[1]),
				"山体壳 %s 覆盖其台顶中心 (%s, %s)" % [body.name, str(center[0]), str(center[1])])


## 用真实物理查询断言指定空间点为空腔（主殿内部与门洞不得被整盒堵死）。
func _check_cavity_free(space_point: Vector3, label: String) -> void:
	var space := _actor.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, space_point)
	query.collision_mask = 1
	var hits := space.intersect_shape(query, 8)
	_check(hits.is_empty(), "%s 保持空腔（命中 %d 个碰撞体）" % [label, hits.size()])


## 统计真实调用，不把注释里的说明文字算作提交点。
func _call_count(source: String, call: String) -> int:
	var count := 0
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		count += stripped.count(call)
	return count


func _check_single_commit_point() -> void:
	var actor_source := FileAccess.get_file_as_string("res://game/actors/swordsman/swordsman.gd")
	_check(_call_count(actor_source, "move_and_slide") == 1, "actor 根只有一处 move_and_slide 调用（唯一物理提交点）")
	for path in [
		"res://game/actors/swordsman/swordsman_movement.gd",
		"res://game/abilities/jump/jump.gd",
		"res://game/abilities/sword_flight/sword_flight.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		_check(_call_count(source, "move_and_slide") == 0, "能力不自行提交物理：" + path.get_file())


# --- 平面移动 -----------------------------------------------------------------


func _batch_move() -> void:
	await _reset_via_r()
	await _frames(4)
	var start := _actor.global_position
	var screen_start := _camera.unproject_position(start)
	_key(KEY_D, true)
	await _frames(14)
	_key(KEY_D, false)
	await _frames(3)
	_check(_camera.unproject_position(_actor.global_position).x > screen_start.x + 5.0, "D 输入产生屏幕向右真实位移")
	_check(_actor.velocity.length() < 0.01, "松开 D 停止")
	_check(_motion.aim_direction.dot(_motion.camera_right) > 0.9, "角色转向相机右方")

	await _reset_via_r()
	await _frames(4)
	start = _actor.global_position
	_key(KEY_RIGHT, true)
	await _frames(14)
	_key(KEY_RIGHT, false)
	await _frames(3)
	_check(_actor.global_position.distance_to(start) > 0.5, "方向键 → 与 WASD 等价地产生位移")
	_check(_motion.aim_direction.dot(_motion.camera_right) > 0.9, "方向键 → 转向相机右方")

	await _reset_via_r()
	await _frames(4)
	_key(KEY_W, true)
	await _frames(6)
	_check(_motion.actual_velocity.dot(_motion.camera_forward) > 3.5, "W 对应相机地面前方速度")
	_key(KEY_D, true)
	await _frames(6)
	var horizontal := Vector2(_actor.velocity.x, _actor.velocity.z).length()
	_check(horizontal <= MOVE_SPEED + 0.001 and horizontal > MOVE_SPEED * 0.8,
		"W+D 斜向不超速（%.2f m/s）" % horizontal)
	_key(KEY_W, false)
	_key(KEY_D, false)
	await _frames(3)
	_key(KEY_S, true)
	await _frames(6)
	_check(_motion.actual_velocity.dot(_motion.camera_forward) < -3.5, "S 对应相机地面后方速度")
	_key(KEY_S, false)
	await _frames(3)
	_check(_actor.velocity.length() < 0.01, "松键后停止")


# --- 跳跃 -------------------------------------------------------------------


func _batch_jump() -> void:
	await _reset_via_r()
	_check(await _wait_floor(90), "起跳前着地")
	var floor_y := _actor.global_position.y

	# 按住空格（含 OS 回显 key-down）跨越完整弧线：必须只起跳一次、顶点约 1.0 m、真实落回。
	_key(KEY_SPACE, true)
	var apex := floor_y
	var takeoffs := 0
	var was_floor := true
	var landed := false
	for _index in range(180):
		_key_echo(KEY_SPACE)
		await physics_frame
		apex = maxf(apex, _actor.global_position.y)
		if was_floor and not _motion.on_floor:
			takeoffs += 1
		was_floor = _motion.on_floor
		if _index > 10 and _motion.on_floor and _actor.global_position.y <= floor_y + POS_TOL:
			landed = true
			break
	_key(KEY_SPACE, false)
	await _frames(3)
	_check(takeoffs == 1, "按住空格不连跳：起跳次数 %d" % takeoffs)
	_check(landed, "跳跃真实落回平台（y=%.2f，平台 %.2f）" % [_actor.global_position.y, floor_y])
	var apex_height := apex - floor_y
	_check(apex_height > 0.7 and apex_height < 1.3, "跳跃顶点约 1.0 m（实际 %.2f）" % apex_height)

	# 空中再按空格：不得产生第二次起跳，也不得在空中补一个落地跳。
	await _reset_via_r()
	_check(await _wait_floor(90), "空中起跳用例着地")
	floor_y = _actor.global_position.y
	takeoffs = 0
	was_floor = true
	apex = floor_y
	_key(KEY_SPACE, true)
	await _frames(8)
	_key(KEY_SPACE, false)
	await _frames(2)
	_key(KEY_SPACE, true)
	await _frames(2)
	_key(KEY_SPACE, false)
	for _index in range(180):
		await physics_frame
		apex = maxf(apex, _actor.global_position.y)
		if was_floor and not _motion.on_floor:
			takeoffs += 1
		was_floor = _motion.on_floor
		if _index > 10 and _motion.on_floor and _actor.global_position.y <= floor_y + POS_TOL:
			break
	_check(takeoffs == 1, "空中按空格不重复起跳：起跳次数 %d" % takeoffs)
	_check(apex - floor_y < 1.3, "空中按键不增加跳跃高度（顶点 %.2f m）" % (apex - floor_y))


# --- 御剑 -------------------------------------------------------------------


func _batch_flight() -> void:
	await _reset_via_r()
	_check(await _wait_floor(90), "起飞前着地")
	var floor_y := _actor.global_position.y
	_key(KEY_F, true)
	await _frames(2)
	_key(KEY_F, false)
	_check(_motion.flight_active, "F 边沿开启御剑")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "御剑登记一条 %s" % FLIGHT_TAG)
	await _frames(25)
	_check(_actor.global_position.y > floor_y + 0.5, "地面开启御剑产生真实升起（y=%.2f）" % _actor.global_position.y)

	await _frames(15)
	var hover_y := _actor.global_position.y
	await _frames(30)
	_check(absf(_actor.velocity.y) < VERT_TOL and absf(_actor.global_position.y - hover_y) < 0.1,
		"松键悬停：竖直速度 ≈ 0 且高度稳定")

	_key(KEY_SPACE, true)
	await _frames(20)
	_check(_actor.velocity.y > 4.0 and _actor.global_position.y > hover_y + 0.5, "空格上升（%.2f m/s）" % _actor.velocity.y)
	_key(KEY_SPACE, false)
	await _frames(10)
	_check(absf(_actor.velocity.y) < VERT_TOL, "松开空格回到悬停")

	var before_sink := _actor.global_position.y
	_key(KEY_CTRL, true)
	await _frames(20)
	_check(_actor.velocity.y < -4.0 and _actor.global_position.y < before_sink - 0.5, "Ctrl 下降（%.2f m/s）" % _actor.velocity.y)
	_key(KEY_CTRL, false)
	await _frames(10)

	# 御剑水平速度明显快于步行，且不超契约上限。
	_key(KEY_W, true)
	await _frames(10)
	var horizontal := Vector2(_actor.velocity.x, _actor.velocity.z).length()
	_check(horizontal > 6.0 and horizontal <= FLIGHT_SPEED + 0.001, "御剑水平速度显著快于步行（%.2f m/s）" % horizontal)
	_key(KEY_W, false)
	await _frames(10)

	var flight_y := _actor.global_position.y
	_key(KEY_F, true)
	await _frames(2)
	_key(KEY_F, false)
	_check(not _motion.flight_active, "再按 F 关闭御剑")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "关闭御剑后阻塞清账")
	await _frames(3)
	_check(_actor.velocity.y < -0.1, "关飞后重力恢复（vy=%.2f）" % _actor.velocity.y)
	var step := _actor.get_physics_process_delta_time()
	var v0 := _actor.velocity.y
	await _frames(1)
	var v1 := _actor.velocity.y
	var accel := (v1 - v0) / step
	# 向下为正的结果为负；比较大小而非方向文字。
	_check(absf(accel + GRAVITY) < 2.0, "关飞后竖直加速度为单份重力（%.1f m/s²，期望 -%.1f）" % [accel, GRAVITY])
	_check(flight_y > floor_y, "关飞点高于地面，落地路径真实")
	_check(await _wait_floor(240), "关飞后真实落地（y=%.2f）" % _actor.global_position.y)


# --- Tag 清账与拆装 -----------------------------------------------------------


func _batch_tags() -> void:
	# 路径 1：再按 F 关闭已由 flight 批次覆盖；这里覆盖 R 与节点移除。
	await _reset_via_r()
	_check(await _wait_floor(90), "标签用例着地")
	await _open_flight()
	_check(_motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "R 前御剑生效且已登记阻塞")
	await _reset_via_r()
	_check(not _motion.flight_active, "R 关闭御剑")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "R 后阻塞清账")
	_check(_actor.global_position.distance_to(_spawn) < 0.25, "R 回到 spawn")

	# 路径 2：从装配移除 SwordFlight 节点（不删包、不动场景文件）。
	await _open_flight()
	_check(_motion.flight_active, "拆装用例先开启御剑")
	var flight_node := _manager.get_node_or_null("SwordFlight")
	_check(flight_node != null, "装配中存在 SwordFlight 节点")
	if flight_node != null:
		_manager.remove_child(flight_node)
		flight_node.queue_free()
		await _frames(4)
	_check(not _motion.flight_active, "移除 SwordFlight 节点后 flight_active 被清")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "移除 SwordFlight 节点后阻塞清账")
	# 其余能力仍工作：移动可用、跳跃可起跳。
	var before := _actor.global_position
	_key(KEY_D, true)
	await _frames(12)
	_key(KEY_D, false)
	await _frames(3)
	_check(_actor.global_position.distance_to(before) > 0.5, "移除 Flight 后 Movement 仍工作")
	# 恢复装配供后续批次使用。
	var restored := SwordFlight.new()
	restored.name = "SwordFlight"
	_manager.add_child(restored)
	await _frames(3)
	await _open_flight()
	_check(_motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "重新装配 SwordFlight 后功能恢复")
	await _reset_via_r()


# --- 重置 -------------------------------------------------------------------


func _batch_reset() -> void:
	await _reset_via_r()
	await _wait_floor(90)
	await _open_flight()
	_key(KEY_SPACE, true)
	await _frames(25)
	_key(KEY_SPACE, false)
	await _frames(5)
	_check(_motion.flight_active and _actor.global_position.y > _spawn.y + 1.0, "重置前：御剑上升中")
	# 断言场景声明的默认缩放，而不是把滚轮后的当前值当默认。
	var default_size := float(_scene_constant("CAMERA_SIZE", 48.0))
	_check(absf(_camera.size - default_size) < 0.01, "进入场景缩放为声明默认（%.1f）" % _camera.size)
	var scroll := InputEventMouseButton.new()
	scroll.button_index = MOUSE_BUTTON_WHEEL_UP
	scroll.position = Vector2(640, 400)
	scroll.pressed = true
	Input.parse_input_event(scroll)
	await _frames(3)
	var zoomed := _camera.size
	_check(zoomed < default_size, "滚轮放大改变视野（%.1f → %.1f）" % [default_size, zoomed])
	_key(KEY_R, true)
	await _frames(2)
	_key(KEY_R, false)
	await _frames(8)
	_check(_actor.global_position.distance_to(_spawn) < 0.3, "R 回到 spawn（y=%.2f）" % _actor.global_position.y)
	_check(_actor.velocity.length() < 0.01, "R 后速度清零")
	_check(not _motion.flight_active, "R 后御剑关闭")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "R 后阻塞清账")
	_check(absf(_camera.size - default_size) < 0.01, "R 恢复场景声明默认缩放（%.1f，期望 %.1f）" % [_camera.size, default_size])
	_check(await _wait_floor(90), "R 后真实落回平台")


# --- 同帧互斥与失焦 ----------------------------------------------------------


func _batch_mutex() -> void:
	# 同帧 F+Space（地面）：Flight 先激活并阻塞 Jump，竖直速度 = 起飞升起速度，不是跳跃冲量。
	await _reset_via_r()
	_check(await _wait_floor(90), "互斥用例着地")
	_key(KEY_F, true)
	_key(KEY_SPACE, true)
	await _frames(1)
	_key(KEY_F, false)
	_key(KEY_SPACE, false)
	await _frames(2)
	_check(_motion.flight_active, "同帧 F+Space：御剑开启")
	_check(_actor.global_position.y > _spawn.y + 0.02, "同帧 F+Space：真实离地")
	_check(_actor.velocity.y > 2.0 and _actor.velocity.y < 5.0,
		"同帧 F+Space：竖直速度是起飞升起（%.2f），未被跳跃冲量覆盖" % _actor.velocity.y)
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "同帧 F+Space：登记一条阻塞")
	# 跳跃边沿当帧被消费，下一帧不得补跳。
	await _frames(6)
	_check(_actor.velocity.y < 5.0, "同帧 F+Space：无边沿补跳（vy=%.2f）" % _actor.velocity.y)
	await _reset_via_r()

	# 起跳后开飞行：空中 F 接管，竖直速度被限幅而不是叠加。
	_check(await _wait_floor(90), "起跳后开飞用例着地")
	_key(KEY_SPACE, true)
	await _frames(6)
	_key(KEY_SPACE, false)
	_check(not _motion.on_floor and _actor.velocity.y > 0.0, "起跳后处于上升段（vy=%.2f）" % _actor.velocity.y)
	await _open_flight()
	_check(_motion.flight_active, "空中按 F 开启御剑")
	_check(_actor.velocity.y <= 7.001, "起飞首帧竖直速度被限幅在 flight_lift_speed 内（%.2f）" % _actor.velocity.y)
	_key(KEY_SPACE, true)
	await _frames(10)
	_check(absf(_actor.velocity.y - 7.0) < 0.01, "空中转御剑后受升降输入控制（vy=%.2f）" % _actor.velocity.y)
	_key(KEY_SPACE, false)
	await _frames(5)
	# 空中关飞行：重力立即恢复并真实落地。
	var air_y := _actor.global_position.y
	_key(KEY_F, true)
	await _frames(1)
	_key(KEY_F, false)
	await _frames(4)
	_check(not _motion.flight_active, "空中关飞关闭状态")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "空中关飞清账")
	_check(_actor.velocity.y < -0.1, "空中关飞重力立即恢复（vy=%.2f）" % _actor.velocity.y)
	_check(await _wait_floor(240), "空中关飞后真实落地（起落高度差 %.2f m）" % (air_y - _actor.global_position.y))


func _batch_focus() -> void:
	await _reset_via_r()
	_check(await _wait_floor(90), "失焦用例着地")
	await _open_flight()
	await _frames(25)
	_key(KEY_W, true)
	await _frames(10)
	var hover_y := _actor.global_position.y
	current_scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(3)
	_check(_motion.flight_active, "失焦不关闭已开启的御剑")
	_check(_motion.move_input == Vector2.ZERO and _motion.vertical_input == 0.0, "失焦清水平与升降输入")
	await _frames(15)
	_check(absf(_actor.velocity.y) < VERT_TOL, "失焦后竖直速度 ≈ 0（悬停，vy=%.2f）" % _actor.velocity.y)
	_check(absf(_actor.global_position.y - hover_y) < 0.6, "失焦后高度稳定（Δ%.2f m）" % (_actor.global_position.y - hover_y))
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "失焦后阻塞仍在（御剑未退出）")
	# R 才关闭飞行并清账。
	await _reset_via_r()
	_check(not _motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "R 关闭御剑并清账")
	_key(KEY_W, false)
	await _frames(3)
	await _reset_via_r()


# --- 真实碰撞：山体 / 建筑 / 低台阶 ------------------------------------------


func _batch_collision() -> void:
	await _reset_via_r()
	# 高度场重构后：起点取可站立的谷底（下方有地面、自身在空腔中），朝指定山面水平推进，
	# 必须先撞到该峰碰撞壳本体且行程被截断（外→内，不降断言）。
	await _check_valley_sweep(Vector3(-70.0, 6.5, 58.0), Vector2(-70.0, -6.0),
		"WestPeakCol", "谷底向北撞西峰山面命中本体")
	await _check_valley_sweep(Vector3(83.5, 3.3, -46.5), Vector2(56.0, 20.0),
		"EastRidgeCol", "谷底向南撞东岭山面命中本体")
	await _check_valley_sweep(Vector3(41.4, 3.6, 43.4), Vector2(-30.0, 34.0),
		"FrontMesaCol", "谷底向西撞前丘山面命中本体")
	# 建筑：宗门主殿南墙（x=0 处为实墙，门洞在 x 2..6）。
	await _check_sweep_hits(Vector3(0.0, 37.0, -44.0), Vector3(0.0, 0.0, -8.0),
		"World/BoxCollision/main_hall_wall_south_a", "撞主殿南墙命中本体")
	# 低台阶侧面：顶面 12.55，抬升 0.55。
	await _check_sweep_hits(Vector3(-32.5, 12.3, 30.0), Vector3(-6.0, 0.0, 0.0),
		"World/BoxCollision/jump_step", "低台阶侧面阻挡命中本体")

	# 真实按键顶墙：先证明角色与指定南墙接触（slide collision 命中本体），
	# 再在被压住期间验证法向不穿透；沿墙滑动是合法结果，不做 Δz=0 断言。
	_set_actor(Vector3(-1.0, 37.0, -44.0))
	_check(await _wait_floor(120, 36.0), "走进建筑前站上宗门台（y=%.2f）" % _actor.global_position.y)
	var wall := current_scene.get_node_or_null("World/BoxCollision/main_hall_wall_south_a")
	_key(KEY_W, true)
	var contact_frames := 0
	var violations := 0
	var deepest := 0.0
	for _index in range(240):
		await physics_frame
		if _slide_contacts(wall):
			contact_frames += 1
		var current := _actor.global_position
		# 南墙面在 z=-46.0（盒中心 -46.5、厚 1.0）；胶囊半径 0.35，中心不得越过 -46.3。
		if current.x > -4.3 and current.x < 2.3 and current.z < -46.3:
			violations += 1
			deepest = maxf(deepest, -46.3 - current.z)
	_key(KEY_W, false)
	await _frames(3)
	_check(contact_frames > 0, "真实按键与 main_hall_wall_south_a 发生滑动接触（%d 帧）" % contact_frames)
	_check(violations == 0, "接触期间不穿透墙面（违规帧 %d，最深 %.2f m）" % [violations, deepest])


## 谷底 → 指定山面的水平 sweep：先落地（证明起点可站），再朝目标水平推进，
## 必须命中指定壳本体且行程被截断。起点若落在新山体内会直接失败，提示换点而不放宽判据。
func _check_valley_sweep(from: Vector3, target: Vector2, shell_name: String, message: String) -> void:
	_set_actor(from)
	_check(await _wait_floor(90, from.y - 0.9), "sweep 起点可站立（%s）" % str(from))
	# 请求长度取完整 from→target 距离 +2 m 余量：起点的实际落地高度与探测点略有差异，
	# 但必须仍然「撞到山面被截断」（travel < 请求长度），不允许直接穿过。
	var span := Vector2(target.x - _actor.global_position.x, target.y - _actor.global_position.z)
	var direction := Vector3(span.x, 0.0, span.y).normalized() * (span.length() + 2.0)
	var hit := _actor.move_and_collide(direction, true)
	if hit == null:
		_check(false, "%s（sweep 未命中任何碰撞体，起点 %s）" % [message, str(_actor.global_position)])
		return
	var expected := current_scene.get_node_or_null("World/ShellCollision/%s" % shell_name)
	var actual := hit.get_collider()
	_check(expected != null and actual == expected and hit.get_travel().length() < direction.length() - 0.01
			and hit.get_travel().length() > 6.0,
		"%s（命中 %s，行程 %.2f / %.2f）" % [message, "<null>" if actual == null else str(actual.get_path()),
			hit.get_travel().length(), direction.length()])


## 上一物理帧 move_and_slide 的滑动碰撞里是否包含指定节点。
func _slide_contacts(node: Node) -> bool:
	if node == null:
		return false
	for index in range(_actor.get_slide_collision_count()):
		if _actor.get_slide_collision(index).get_collider() == node:
			return true
	return false


func _inside_hall(position: Vector3) -> bool:
	return position.x > -3.0 and position.x < 11.0 and position.z < -47.0 and position.z > -55.0


## 用真实角色形状做一次有界 sweep：必须命中指定路径的碰撞体本体且行程被截断。
func _check_sweep_hits(from: Vector3, direction: Vector3, collider_path: String, message: String) -> void:
	_set_actor(from)
	await _frames(1)
	var hit := _actor.move_and_collide(direction, true)
	if hit == null:
		_check(false, "%s（sweep 未命中任何碰撞体）" % message)
		return
	var expected := current_scene.get_node_or_null(collider_path)
	var actual := hit.get_collider()
	_check(expected != null and actual == expected and hit.get_travel().length() < direction.length() - 0.01,
		"%s（命中 %s）" % [message, "<null>" if actual == null else str(actual.get_path())])


func _set_actor(position: Vector3) -> void:
	_actor.global_position = position
	_actor.velocity = Vector3.ZERO
	_motion.actual_velocity = Vector3.ZERO
	_motion.flight_active = false
	TagRegistry.clear_all()


# --- 真实输入飞往两处山顶平台并降落 -------------------------------------------


## 真实输入飞往指定落点并降落，全部由按键驱动：
## ① 升到安全高度（高于沿途峰顶/屋顶，位于 bounds 内）→ ② 平移到平台上空（保持高度）
## → ③ 垂直下降到台面上方 2 m → ④ F 退出御剑、真实重力落体着台。
## 全程不做坐标传送；逐帧位移上限保证不是瞬移。
func _batch_landing(landing_name: String) -> void:
	var target := _landing_point(landing_name)
	if target.is_empty():
		_check(false, "布局缺少落点 %s" % landing_name)
		return
	await _reset_via_r()
	_check(await _wait_floor(120, _spawn.y), "飞往 %s 前着地" % landing_name)
	var top_y := float(target["top_y"])
	var descent := _descent_point(target)
	var safe_y := 50.0
	_key(KEY_F, true)
	await _frames(2)
	_key(KEY_F, false)
	_check(_motion.flight_active, "F 开启御剑，前往 %s" % landing_name)

	_check(await _climb_to(safe_y, 700), "① 真实按键升至安全高度 %.0f m（y=%.2f）" % [safe_y, _actor.global_position.y])
	_check(_actor.global_position.y > top_y + 8.0, "安全高度高于 %s 台顶（%.1f > %.1f）" % [landing_name, _actor.global_position.y, top_y])
	_check(await _cruise_to(descent, safe_y, 900),
		"② 平移到 %s 上空（水平偏移 %.2f m；轨迹 %s）" % [landing_name, _horizontal_distance(descent), " | ".join(_cruise_trace)])
	# 步幅必须证明真的在动（>0）且不超过御剑速度 × dt（防零常量假通过）。
	var flight_step_limit := FLIGHT_SPEED * _actor.get_physics_process_delta_time() + 0.01
	_check(_cruise_step > 0.05 and _cruise_step <= flight_step_limit,
		"巡航步幅真实且不超御剑速度（最大 %.3f m/帧，上限 %.3f）" % [_cruise_step, flight_step_limit])
	_check(_motion.flight_active, "③ 抵达 %s 上空时御剑仍开启" % landing_name)
	_release_all()
	var drift_from := _actor.global_position
	_check(await _descend_to(top_y + 2.0, 400),
		"③ 下降到 %s 台面上方 2 m（y=%.2f）" % [landing_name, _actor.global_position.y])
	var drift := Vector2(_actor.global_position.x - drift_from.x, _actor.global_position.z - drift_from.z).length()
	_check(drift < 1.0, "下降段是垂直下降（水平漂移 %.2f m）" % drift)
	# ④ 关飞行 → 真实重力落体 → 落到该平台顶面。
	var release_y := _actor.global_position.y
	_key(KEY_F, true)
	await _frames(2)
	_key(KEY_F, false)
	var landed := await _wait_floor(300, top_y)
	var landed_y := _actor.global_position.y
	_check(landed, "④ 关闭御剑后真实降落到 %s（y=%.2f）" % [landing_name, landed_y])
	_check(release_y - landed_y > 1.5, "降落由真实重力完成（下落 %.2f m）" % (release_y - landed_y))
	await _frames(12)
	var rest_y := _actor.global_position.y
	_check(absf(rest_y - top_y) < 0.25, "停在 %s 台面高度 %.1f（实际 %.2f）" % [landing_name, top_y, rest_y])
	var horizontal := Vector2(_actor.global_position.x, _actor.global_position.z)
	var want := Vector2(_actor.global_position.x, _actor.global_position.z)
	want = Vector2(float(target["center"][0]), float(target["center"][1]))
	var size: Array = target["size"]
	_check(absf(horizontal.x - want.x) <= float(size[0]) * 0.5 and absf(horizontal.y - want.y) <= float(size[1]) * 0.5,
		"落点在 %s 净空范围内（偏移 %s）" % [landing_name, str(horizontal - want)])
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "%s 降落后阻塞清账" % landing_name)


## 下降点：落点净空中心向 +z（出生点一侧）偏 25% 进深，避开北侧屋顶/亭台等实体。
func _descent_point(target: Dictionary) -> Vector3:
	var size: Array = target["size"]
	return Vector3(float(target["center"][0]), 0.0, float(target["center"][1]) + float(size[1]) * 0.25)


func _horizontal_distance(point: Vector3) -> float:
	return Vector2(_actor.global_position.x - point.x, _actor.global_position.z - point.z).length()


## ① 只按空格上升，直到达到目标高度；返回是否按时到达。
func _climb_to(y_target: float, timeout_frames: int, strict := true) -> bool:
	_release_all()
	var origin := _actor.global_position
	_key(KEY_SPACE, true)
	for _index in range(timeout_frames):
		# 窗口失焦会按产品行为清空输入；持续按住的动作每个短周期重发 key-down。
		if _index % 20 == 0:
			_key(KEY_SPACE, true)
		await physics_frame
		if _index % 60 == 0:
			print("CLIMB f%d y=%.2f xz=(%.2f, %.2f) v=(%.2f, %.2f) move=%s vert=%.1f flight=%s pressed=%s os=%s" % [
				_index, _actor.global_position.y, _actor.global_position.x, _actor.global_position.z,
				_actor.velocity.x, _actor.velocity.z, str(_motion.move_input), _motion.vertical_input,
				str(_motion.flight_active), str(current_scene.get("_pressed")), str(_os_keys_pressed())])
		if _actor.global_position.y >= y_target:
			_key(KEY_SPACE, false)
			await _frames(2)
			return true
		# 纯上升段不应有水平漂移；出现说明有残留按键，直接失败而不是慢慢磨到超时。
		# strict=false 仅用于窗口截图路径（系统可能向聚焦窗口注入真实按键）。
		if strict and Vector2(_actor.global_position.x - origin.x, _actor.global_position.z - origin.z).length() > 2.0:
			_key(KEY_SPACE, false)
			print("FAIL 上升段出现水平漂移（从 %s 到 %s），疑似残留按键" % [str(origin), str(_actor.global_position)])
			return false
	_key(KEY_SPACE, false)
	return false


## ② 按相机基选八方向键平移到目标上空，同时用空格 / Ctrl 保持安全高度。
func _cruise_to(target: Vector3, hold_y: float, timeout_frames: int) -> bool:
	_cruise_step = 0.0
	_cruise_trace.clear()
	for index in range(timeout_frames):
		if index % 4 == 0:
			_drive_cruise_keys(target, hold_y)
		if index % 120 == 0:
			_cruise_trace.append("f%d %s d=%.1f" % [index, str(_actor.global_position.round()), _horizontal_distance(target)])
		var before := _actor.global_position
		await physics_frame
		_cruise_step = maxf(_cruise_step, before.distance_to(_actor.global_position))
		if _horizontal_distance(target) >= 2.0:
			continue
		_release_all()
		await _frames(2)
		return true
	_release_all()
	return false


func _drive_cruise_keys(target: Vector3, hold_y: float) -> void:
	var to_target := target - _actor.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var right := _motion.camera_right
	var forward := _motion.camera_forward
	var x_axis := 0.0
	var y_axis := 0.0
	if flat.length_squared() > 0.01:
		var desired := flat.normalized()
		x_axis = desired.dot(right)
		y_axis = -desired.dot(forward)
	# move_input.y 正方向是屏幕下方（相机后方）= S；负方向 = W。
	for pair in [[KEY_D, x_axis > 0.38], [KEY_A, x_axis < -0.38], [KEY_S, y_axis > 0.38], [KEY_W, y_axis < -0.38]]:
		_key(pair[0], pair[1])
	var dy := hold_y - _actor.global_position.y
	_key(KEY_SPACE, dy > 0.5)
	_key(KEY_CTRL, dy < -0.5)


## ③ 只按 Ctrl 垂直下降，直到达到目标高度。
func _descend_to(y_target: float, timeout_frames: int) -> bool:
	_release_all()
	_key(KEY_CTRL, true)
	for _index in range(timeout_frames):
		if _index % 20 == 0:
			_key(KEY_CTRL, true)
		await physics_frame
		var horizontal := Vector2(_actor.velocity.x, _actor.velocity.z).length()
		if horizontal > 0.5:
			_key(KEY_CTRL, false)
			return false
		if _actor.global_position.y <= y_target:
			_key(KEY_CTRL, false)
			await _frames(2)
			return true
	_key(KEY_CTRL, false)
	return false


func _release_all() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_CTRL, KEY_F]:
		_key(code, false)


## 诊断：列出 OS 层面仍认为按下的相关物理键（区分「测试发键」与「系统真实按键」）。
func _os_keys_pressed() -> PackedStringArray:
	var pressed := PackedStringArray()
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_CTRL, KEY_F]:
		if Input.is_physical_key_pressed(code):
			pressed.append(OS.get_keycode_string(code))
	return pressed


func _landing_point(name: String) -> Dictionary:
	for value in _layout.get("landing_points", []) as Array:
		var point: Dictionary = value
		if str(point.get("name", "")) == name:
			return point
	return {}


# --- 低台阶真实站立 / 飞行阻塞 / 拆装 / 边界与回收 -----------------------------


## P7 低台阶：真实按键助跑起跳登上 jump_step（顶面 12.55，抬升 0.55），并稳定站立。
func _batch_step() -> void:
	var step := current_scene.get_node_or_null("World/BoxCollision/jump_step")
	_check(step != null, "布局存在低台阶 jump_step")
	if step == null:
		return
	var top_y := _box_top_y("jump_step")
	await _reset_via_r()
	_check(await _wait_floor(120, _spawn.y), "低台阶用例着地")
	_set_actor(Vector3(-32.0, 12.02, 30.0))
	_check(await _wait_floor(120, 12.0), "站在低台阶西侧庭院地面")
	var target := Vector3(step.position.x, 0.0, step.position.z)
	_key(KEY_SPACE, true)
	await _frames(1)
	_key(KEY_SPACE, false)
	var on_step := false
	for _index in range(180):
		_drive_move_keys(target)
		await physics_frame
		if _motion.on_floor and absf(_actor.global_position.y - top_y) < 0.12:
			on_step = true
			break
	_release_move_keys()
	await _frames(4)
	_check(on_step, "真实起跳 + 移动后站上低台阶顶面 %.2f（y=%.2f）" % [top_y, _actor.global_position.y])
	_check(_motion.on_floor and absf(_actor.global_position.y - top_y) < 0.12,
		"在低台阶上稳定站立（y=%.2f）" % _actor.global_position.y)
	var resting := _actor.global_position.y
	await _frames(20)
	_check(absf(_actor.global_position.y - resting) < 0.02, "站立 20 帧不下沉不抖动（Δ%.3f）" % (_actor.global_position.y - resting))


## E4 飞行阻塞跳跃：御剑中按空格只上升，不产生跳跃冲量，且阻塞计数不变。
func _batch_blocked() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120, _spawn.y), "阻塞用例着地")
	await _open_flight()
	await _frames(10)
	var jump := _manager.get_node_or_null("Jump")
	_check(jump != null, "装配中存在 Jump 节点")
	_key(KEY_SPACE, true)
	await _frames(1)
	_check(jump == null or not jump.active, "御剑中按空格不激活 Jump")
	_check(TagRegistry.block_count(_actor, FLIGHT_TAG) == 1, "御剑中空格不改变阻塞计数")
	await _frames(8)
	_check(absf(_actor.velocity.y - 7.0) < 0.01, "御剑中空格只产生上升速度（vy=%.2f）" % _actor.velocity.y)
	_key(KEY_SPACE, false)
	await _reset_via_r()


## D1/D3：从装配移除 Jump 或 Movement 后其余能力仍工作（不删包、不动场景文件）。
func _batch_removal() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120, _spawn.y), "拆装用例着地")

	# D1：移除 Jump 后空格无效；Flight 仍可开启并降落。
	var jump := _manager.get_node_or_null("Jump")
	_check(jump != null, "装配中存在 Jump")
	if jump != null:
		_manager.remove_child(jump)
		jump.queue_free()
		await _frames(3)
	var floor_y := _actor.global_position.y
	_key(KEY_SPACE, true)
	await _frames(8)
	_key(KEY_SPACE, false)
	await _frames(8)
	_check(_motion.on_floor and absf(_actor.global_position.y - floor_y) < 0.1,
		"移除 Jump 后空格不再起跳（y=%.2f）" % _actor.global_position.y)
	await _open_flight()
	_check(_motion.flight_active, "移除 Jump 后 Flight 仍可开启")
	await _reset_via_r()
	var restored_jump := Jump.new()
	restored_jump.name = "Jump"
	_manager.add_child(restored_jump)
	await _frames(3)

	# D3：移除 Movement 后 Jump 与 Flight 仍工作。
	var movement := _manager.get_node_or_null("SwordsmanMovement")
	_check(movement != null, "装配中存在 SwordsmanMovement")
	if movement != null:
		_manager.remove_child(movement)
		movement.queue_free()
		await _frames(3)
	_check(await _wait_floor(120, _spawn.y), "移除 Movement 后仍着地")
	_key(KEY_SPACE, true)
	await _frames(8)
	_key(KEY_SPACE, false)
	var jumped := not _motion.on_floor or _actor.global_position.y > _spawn.y + 0.2
	_check(jumped, "移除 Movement 后 Jump 仍能起跳")
	_check(await _wait_floor(180, _spawn.y), "移除 Movement 后跳跃仍能落地")
	await _open_flight()
	_check(_motion.flight_active, "移除 Movement 后 Flight 仍可开启")
	_key(KEY_W, true)
	await _frames(12)
	_key(KEY_W, false)
	_check(Vector2(_actor.velocity.x, _actor.velocity.z).length() > 6.0, "移除 Movement 后自带的飞行水平移动仍工作")
	await _reset_via_r()
	var restored_move := SwordsmanMovement.new()
	restored_move.name = "SwordsmanMovement"
	_manager.add_child(restored_move)
	await _frames(3)
	_key(KEY_D, true)
	await _frames(10)
	_key(KEY_D, false)
	await _frames(3)
	_check(_motion.on_floor, "恢复 Movement 后装配完整可用")


## P14/P15 边界与高度上限（真实输入飞行顶到东西南北与天花）+ 掉出回收路径。
func _batch_bounds() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120, _spawn.y), "边界用例着地")
	await _open_flight()
	_check(await _climb_to(50.0, 700), "升到 50 m 后测试边界")
	# 东界：一直按东向键，撞到 East 墙即视为生效。
	var bounds_max_x := float((_layout["bounds"]["max"] as Array)[0])
	_check(await _cruise_blocked(Vector3(bounds_max_x + 10.0, 0.0, _actor.global_position.z), "World/Boundaries/East"),
		"飞向东界被 East 边界挡住（x=%.2f，界内 %.1f）" % [_actor.global_position.x, bounds_max_x])
	# 天花：一直按空格，撞到 Ceiling。
	var bounds_max_y := float((_layout["bounds"]["max"] as Array)[1])
	_release_all()
	_key(KEY_SPACE, true)
	var ceiling_hit := false
	for _index in range(600):
		await physics_frame
		if _slide_contacts(current_scene.get_node_or_null("World/Boundaries/Ceiling")):
			ceiling_hit = true
			break
	_key(KEY_SPACE, false)
	_check(ceiling_hit, "上升被天花挡住（y=%.2f，上限 %.1f）" % [_actor.global_position.y, bounds_max_y])
	_check(_actor.global_position.y <= bounds_max_y + 0.01, "高度不越 bounds 上沿")
	# P15 掉出回收路径：把角色放到 fall_out_y 之下，下一帧必须回 spawn 并清飞行。
	var fall_y := float((_layout["bounds"] as Dictionary).get("fall_out_y", -6.0))
	_actor.global_position = Vector3(0.0, fall_y - 4.0, 0.0)
	await _frames(4)
	_check(_actor.global_position.distance_to(_spawn) < 0.3, "掉出下沿后回收至 spawn（y=%.2f）" % _actor.global_position.y)
	_check(not _motion.flight_active and TagRegistry.block_count(_actor, FLIGHT_TAG) == 0, "回收后御剑关闭且清账")


## 真实按键飞向目标方向直到被指定边界节点挡住（滑动碰撞命中或速度被压到 0）。
func _cruise_blocked(target: Vector3, boundary_path: String) -> bool:
	var boundary := current_scene.get_node_or_null(boundary_path)
	for index in range(900):
		if index % 4 == 0:
			_drive_move_keys(target)
		await physics_frame
		if _slide_contacts(boundary):
			_release_move_keys()
			await _frames(2)
			return true
	_release_move_keys()
	return false


func _box_top_y(box_name: String) -> float:
	for value in _layout["boxes"] as Array:
		var box: Dictionary = value
		if str(box.get("name", "")) == box_name:
			return float(box["top_y"])
	return NAN


## 按相机地面基把方向转成 WASD 按键（用于真实行走 / 飞行平移）。
func _drive_move_keys(target: Vector3) -> void:
	var to_target := target - _actor.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var x_axis := 0.0
	var y_axis := 0.0
	if flat.length_squared() > 0.01:
		var desired := flat.normalized()
		x_axis = desired.dot(_motion.camera_right)
		y_axis = -desired.dot(_motion.camera_forward)
	# move_input.y 正方向是屏幕下方（相机后方）= S。
	for pair in [[KEY_D, x_axis > 0.38], [KEY_A, x_axis < -0.38], [KEY_S, y_axis > 0.38], [KEY_W, y_axis < -0.38]]:
		_key(pair[0], pair[1])


func _release_move_keys() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key(code, false)


# --- 新几何适配：入殿 / 谷地降落 / 院门 / 纯表现枢轴 -----------------------------


## 真实按键走进主殿再退出：门洞可通、脚底贴合月台 36 面、殿内不穿底板、檐柱不堵门。
func _batch_hall() -> void:
	await _reset_via_r()
	# 真实飞行到月台前（沿用宗门台降落路径，全程按键）。
	_check(await _fly_to_altitude(36.0), "入殿：真实按键升空")
	_check(await _cruise_to(Vector3(4.0, 0.0, -20.0), 48.0, 900), "入殿：真实按键飞到宗门台上空")
	_check(await _descend_to(30.6, 400), "入殿：下降到宗门台上方")
	_key(KEY_F, true)
	await _frames(2)
	_key(KEY_F, false)
	_check(await _wait_floor(240, 30.0), "入殿：降落在宗门台 30 m")
	# 真实走台阶上 36 m 月台（台阶 8 级、每级 0.75 m，需要跳跃）。
	var reached := await _climb_stairs_to(Vector3(4.0, 36.0, -37.0), 900)
	_check(reached, "入殿：真实按键走上 8 级台阶到 36 m 月台（y=%.2f）" % _actor.global_position.y)
	_check(_motion.on_floor and absf(_actor.global_position.y - 36.0) < 0.1,
		"入殿：脚底贴合月台 36 面（y=%.3f）" % _actor.global_position.y)

	# 走向门洞（门洞中心 x=4, 南墙 z=-46）：实时记录是否穿墙。
	var floor_y := _actor.global_position.y
	var entered := false
	var through_door := true
	_key(KEY_S, true)
	for _index in range(300):
		if _index % 4 == 0:
			_walk_step_toward(Vector3(4.0, 0.0, -49.5))
		await physics_frame
		var here := _actor.global_position
		# 墙体 z≈-46.5、厚 1.0；门洞 x∈[2,6]。若在墙外 x 段越墙即为穿墙。
		if here.z < -46.9 and here.z > -47.6 and (here.x < 1.8 or here.x > 6.2):
			through_door = false
		if here.z < -47.4 and absf(here.x - 4.0) < 2.0:
			entered = true
			break
	_release_move_keys()
	await _frames(3)
	_check(through_door, "入殿：只在门洞 x∈[2,6] 内穿过南墙")
	_check(entered, "入殿：真实按键经门洞进入主殿（位置 %s）" % str(_actor.global_position))
	_check(absf(_actor.global_position.y - floor_y) < 0.12,
		"入殿：殿内脚底贴合同一 36 面，不穿底板（Δy=%.3f）" % (_actor.global_position.y - floor_y))

	# 殿内反向走出（S 键退出，验证门口可通且不卡柱）。
	_key(KEY_S, false)
	_release_move_keys()
	var back_out := false
	_key(KEY_W, false)
	for _index in range(300):
		if _index % 4 == 0:
			_walk_step_toward(Vector3(4.0, 0.0, -42.0))
		await physics_frame
		if _actor.global_position.z > -45.6:
			back_out = true
			break
	_release_move_keys()
	await _frames(3)
	_check(back_out, "出殿：真实按键从门洞退出到月台（z=%.2f）" % _actor.global_position.z)


## 台阶爬升：面向目标分级推进，每级用跳跃，直到「平面到达 + 着地 + 高度贴合」才接受。
## 只在跳跃途中满足高度会假通过（随后落地高度不同），因此必须要求 on_floor。
func _climb_stairs_to(target: Vector3, timeout_frames: int) -> bool:
	for _index in range(timeout_frames):
		if _index % 6 == 0:
			_walk_step_toward(target)
			_key(KEY_SPACE, true)
			await physics_frame
			_key(KEY_SPACE, false)
		await physics_frame
		if (_actor.global_position.distance_to(target) < 2.0
				and absf(_actor.global_position.y - target.y) < 0.15
				and _motion.on_floor):
			_release_move_keys()
			await _frames(6)
			if _motion.on_floor and absf(_actor.global_position.y - target.y) < 0.15:
				return true
	_release_move_keys()
	return false


## 一步的方向键（不释放其它键，供连续行走循环使用）。
func _walk_step_toward(target: Vector3) -> void:
	_drive_move_keys(Vector3(target.x, 0.0, target.z))


## 谷地自然降落：真实飞行到谷地上空，关飞行落到同源地面；落点高度必须与
## 视觉地形与碰撞壳一致（射线核验，不是只掉到某个平台盒上）。
func _batch_valley() -> void:
	await _reset_via_r()
	await _wait_floor(120, _spawn.y)
	# 新高度场下谷底高度不均匀（实测同一谷地网格 0.4–18 m），因此不硬编码 0：
	# 先探测目标点正上方的真实地面高度，再飞到该高度上方 4 m 关飞行，落到同源表面。
	var valley := Vector3(-40.0, 0.0, 0.0)
	var probe := _ray_down(valley + Vector3(0.0, 40.0, 0.0), 60.0)
	_check(not probe.is_empty(), "谷地：目标点上方存在地面")
	if probe.is_empty():
		return
	var surface_target := (probe["position"] as Vector3).y
	_check(await _fly_to_altitude(30.0), "谷地：真实按键升空")
	_check(await _cruise_to(valley, surface_target + 24.0, 1200), "谷地：真实按键飞到谷地上空")
	_check(await _descend_to(surface_target + 4.0, 700), "谷地：下降到谷地上方 4 m（目标面 %.2f）" % surface_target)
	_key(KEY_F, true)
	await _frames(2)
	_key(KEY_F, false)
	var landed := await _wait_floor(400)
	_check(landed, "谷地：关飞行后真实落到谷地（y=%.2f）" % _actor.global_position.y)
	await _frames(10)
	var rest := _actor.global_position
	# 同源核验：向下射线必须命中地形碰撞壳（不是平台盒），且脚底贴合同一表面。
	var hit := _ray_down(rest + Vector3(0.0, 2.0, 0.0), 20.0)
	var collider: Node = null
	var surface_y := -999.0
	if not hit.is_empty():
		collider = hit["collider"] as Node
		surface_y = (hit["position"] as Vector3).y
	_check(collider != null and str(collider.name).ends_with("Col"),
		"谷地：脚下是同源地形碰撞壳（%s）" % ("<none>" if collider == null else str(collider.name)))
	_check(absf(rest.y - surface_y) < 0.35,
		"谷地：脚底贴合同源地面（脚 %.2f，面 %.2f）" % [rest.y, surface_y])
	_check(absf(rest.y - surface_target) < 1.5,
		"谷地：落点与探测面一致（落 %.2f，探 %.2f）" % [rest.y, surface_target])
	# 谷地行走：真实按键移动，逐帧核对脚底与「脚下同源表面」的间隙。
	# 不要求每帧 on_floor（斜坡上下行会短暂离地），但间隙必须始终贴合同源地形壳。
	var start := rest
	var max_gap := 0.0
	var off_source := 0
	var moved := 0.0
	_key(KEY_D, true)
	for _index in range(40):
		await physics_frame
		var under := _ray_down(_actor.global_position + Vector3(0.0, 1.5, 0.0), 8.0)
		if under.is_empty():
			off_source += 1
			continue
		var under_collider := under["collider"] as Node
		if under_collider == null or not str(under_collider.name).ends_with("Col"):
			off_source += 1
			continue
		var gap: float = _actor.global_position.y - (under["position"] as Vector3).y
		max_gap = maxf(max_gap, gap)
		moved = maxf(moved, _actor.global_position.distance_to(start))
	_key(KEY_D, false)
	await _frames(4)
	_check(off_source == 0, "谷地：行走全程脚下都是同源地形壳（脱源帧 %d）" % off_source)
	_check(max_gap < 0.6, "谷地：行走中脚底贴合地形（最大间隙 %.2f m）" % max_gap)
	_check(moved > 1.0, "谷地：真实按键可行走（位移 %.2f m）" % moved)


## 纯表现层：真实走动两个时刻，腿/臂枢轴角度必须变化且反相；停步不原地踏步。
func _batch_presentation() -> void:
	await _reset_via_r()
	_check(await _wait_floor(120, _spawn.y), "表现用例着地")
	var presentation := _actor.get_node_or_null("Visual/CultivatorPresentation")
	_check(presentation != null, "角色挂有纯表现层节点")
	if presentation == null:
		return
	var pivots := presentation.get("_legs") as Array
	var arms := presentation.get("_arms") as Array
	_check(pivots != null and pivots.size() == 2 and arms != null and arms.size() == 2,
		"表现层建立 2 腿 + 2 臂枢轴（实际 %s / %s）" % [
			str(pivots.size() if pivots != null else -1), str(arms.size() if arms != null else -1)])
	if pivots == null or pivots.size() < 2 or arms == null or arms.size() < 2:
		return
	_key(KEY_D, true)
	await _frames(10)
	var leg_a: float = (pivots[0] as Node3D).rotation.x
	var arm_a: float = (arms[0] as Node3D).rotation.x
	await _frames(14)
	var leg_b: float = (pivots[0] as Node3D).rotation.x
	var arm_b: float = (arms[0] as Node3D).rotation.x
	_check(absf(leg_a - leg_b) > 0.02, "走动中腿枢轴角度随时间变化（%.3f → %.3f）" % [leg_a, leg_b])
	_check(absf(arm_a - arm_b) > 0.01, "走动中臂枢轴角度随时间变化（%.3f → %.3f）" % [arm_a, arm_b])
	_check(leg_a * arm_a <= 0.0 or absf(leg_a + arm_a) < absf(leg_a - arm_a),
		"腿臂反相摆动（腿 %.3f / 臂 %.3f）" % [leg_a, arm_a])
	_key(KEY_D, false)
	await _frames(30)
	var leg_stop: float = (pivots[0] as Node3D).rotation.x
	await _frames(20)
	_check(absf((pivots[0] as Node3D).rotation.x - leg_stop) < 0.02,
		"停步后不再原地踏步（%.3f → %.3f）" % [leg_stop, (pivots[0] as Node3D).rotation.x])
	# 表现层不改变物理：能力数量与胶囊不变。
	var manager := _actor.get_node("CapabilityManager")
	_check(manager.get_child_count() == 3, "表现层未新增 Capability（仍 3 个）")


# --- hub 回归 ---------------------------------------------------------------


func _batch_hub() -> void:
	await _reset_via_r()
	await _open_flight()
	await _frames(5)
	_key(KEY_ESCAPE, true)
	await _frames(2)
	_key(KEY_ESCAPE, false)
	await _frames(10)
	_check(current_scene != null and current_scene.name == HUB_SCENE_NAME, "Esc 返回实验目录")
	_check(TagRegistry._blocks.is_empty(), "切场景后 TagRegistry 无跨场景残留")
	var entry := _module_entry(MOVE_MODULE)
	_check(not entry.is_empty() and str(entry.get("scene", "")) == SCENE, "目录入口指向 mountain_realm")
	_check(LabCatalog.can_open(entry), "角色移动入口可打开")
	current_scene.select_module(MOVE_MODULE)
	_check(not current_scene.get_node("%LaunchButton").disabled, "角色移动有可运行入口")
	current_scene.select_module(SWORD_MODULE)
	_check(current_scene.get_node("%LaunchButton").disabled, "剑法保持无运行入口")


# --- 截图（窗口模式；飞行画面必须由真实输入产生） -------------------------------


## 截图序列（每个后缀必须唯一，避免父代理审查时命中缓存）：
## 1 mountain-overview 全貌（默认缩放）→ 2 sect-ground 地面宗门 → 3 flight-close 真实按键飞行近景
## → 4 landing-summit 真实按键飞往主峰降落 → 5 landing-north 北峰 → 6 small 小窗。
## 每个飞行相关截图前打印状态快照（flight_active / y / 台面 / 速度），不摆拍、不传送。
func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "无头渲染器无法截图，请用窗口模式运行")
		_finish()
		return
	await _wait_render_frames(48)
	root.get_texture().get_image()

	if _shot("overview"):
		# 全貌：真实按键飞到场地中心上空（不传送），再用真实滚轮缩到 230 装下整个 180×160 场地。
		await _wait_floor(120, _spawn.y)
		_check(await _fly_to_altitude(43.0), "全貌：真实按键升空")
		_check(await _cruise_to(Vector3(0.0, 0.0, -5.0), 55.0, 900), "全貌：真实按键飞到场地中心上空")
		await _zoom_out_to(230.0)
		await _frames(10)
		_capture_snapshot("mountain-overview")
		await _capture("mountain-overview")
		# 全貌截图期间御剑保持真实开启（脚本会打印 SNAPSHOT，供审阅核对）。
		_check(_motion.flight_active and not _motion.on_floor, "全貌截图由真实飞行取得")

	if _shot("sect"):
		# 地面宗门：真实按键飞行到宗门台上空后降落，站定拍地面建筑。
		await _reset_via_r()
		await _wait_floor(120, _spawn.y)
		_check(await _fly_to_altitude(36.0), "截图：真实按键升到 48 m")
		# 山门台 (4,-20) 顶面 30、24×12 净空；下降点再向 +z 偏 3 m 避开山门柱与台阶。
		_check(await _cruise_to(Vector3(4.0, 0.0, -20.0), 48.0, 900), "截图：真实按键飞到宗门台上空")
		_check(await _descend_to(30.6, 400), "截图：下降到宗门台上方")
		_key(KEY_F, true)
		await _frames(2)
		_key(KEY_F, false)
		_check(await _wait_floor(240, 30.0), "截图：关飞后降落在宗门台 30 m")
		# 落地后真实步行到月台东侧开阔处（避开山门屋顶遮挡），不传送人物。
		_check(await _walk_to(Vector3(10.0, 0.0, -21.0), 240), "截图：真实步行到月台开阔处")
		_release_move_keys()
		await _frames(4)
		_camera.size = 55.0
		await _frames(10)
		_capture_snapshot("sect-ground")
		await _capture("sect-ground")

	if _shot("flight"):
		# 御剑近景：真实 F 开启、Space 上升，缩小视野到近景。
		await _reset_via_r()
		await _wait_floor(120, _spawn.y)
		_check(await _open_flight_and_climb(14.0), "截图：真实按键御剑升空")
		_check(_motion.flight_active, "御剑近景截图时御剑状态为真")
		_check(_actor.global_position.y > _spawn.y + 8.0, "御剑近景截图时已明显离地")
		_camera.size = 18.0
		await _frames(8)
		_capture_snapshot("flight-close")
		await _capture("flight-close")

	if _shot("landing-summit"):
		_check(await _landing_shot("landing-summit", "summit_sect", 40.0), "截图：真实飞行降落主峰宗门")

	if _shot("landing-north"):
		_check(await _landing_shot("landing-north", "north_pavilion", 34.0), "截图：真实飞行降落北峰庭院")

	if _shot("small"):
		# 小窗：960x640（项目固定 16:10 视口），在 spawn 庭院取景。
		await _reset_via_r()
		await _wait_floor(120, _spawn.y)
		_camera.size = 60.0
		root.size = Vector2i(960, 640)
		await _frames(10)
		_capture_snapshot("small")
		await _capture("small")
	_finish()


func _shot(name: String) -> bool:
	return _shots.is_empty() or _shots.has(name)


## 真实按键步行到目标点（水平距离足够近即停）；用于把角色走到不被屋顶遮挡的开阔处。
func _walk_to(target: Vector3, timeout_frames: int) -> bool:
	for index in range(timeout_frames):
		if index % 4 == 0:
			_drive_move_keys(target)
		await physics_frame
		var flat := Vector2(_actor.global_position.x - target.x, _actor.global_position.z - target.z)
		if flat.length() < 1.5:
			_release_move_keys()
			await _frames(2)
			return true
	_release_move_keys()
	return false


## 真实滚轮缩小视野到接近目标值（与玩家滚轮缩放同一条输入路径）。
func _zoom_out_to(target_size: float) -> void:
	var guard := 0
	while _camera.size < target_size - 0.01 and guard < 60:
		var scroll := InputEventMouseButton.new()
		scroll.button_index = MOUSE_BUTTON_WHEEL_DOWN
		scroll.position = Vector2(640, 400)
		scroll.pressed = true
		Input.parse_input_event(scroll)
		await _frames(2)
		guard += 1


## 真实按键飞行到指定落点正上方并关闭御剑降落，落台后截图。
func _landing_shot(suffix: String, landing_name: String, camera_size: float) -> bool:
	var target := _landing_point(landing_name)
	if target.is_empty():
		return false
	var top_y := float(target["top_y"])
	var descent := _descent_point(target)
	await _reset_via_r()
	await _wait_floor(120, _spawn.y)
	await _open_flight()
	if not await _climb_to(50.0, 700, false):
		return false
	if not await _cruise_to(descent, 50.0, 900):
		return false
	if not await _descend_to(top_y + 2.0, 400):
		return false
	_key(KEY_F, true)
	await _frames(2)
	_key(KEY_F, false)
	if not await _wait_floor(300, top_y):
		return false
	await _frames(10)
	_camera.size = camera_size
	await _frames(8)
	_capture_snapshot(suffix)
	_check(_motion.on_floor and not _motion.flight_active and absf(_actor.global_position.y - top_y) < 0.25,
		"%s：截图时已真实降落在 %s（y=%.2f）" % [suffix, landing_name, _actor.global_position.y])
	await _capture(suffix)
	return true


func _open_flight_and_climb(height: float) -> bool:
	await _open_flight()
	if not _motion.flight_active:
		return false
	await _stabilize_input()
	# 相对当前站立高度（可能在山顶平台）上升，避免目标低于脚下导致原地悬停。
	# 窗口路径不启用纯垂直严格断言：系统可向聚焦窗口注入真实按键。
	return await _climb_to(_actor.global_position.y + height, 400, false)


## 从当前站立点真实起飞并升到相对高度（用于截图路径）。
func _fly_to_altitude(height: float) -> bool:
	await _open_flight()
	if not _motion.flight_active:
		return false
	await _stabilize_input()
	return await _climb_to(_actor.global_position.y + height, 500, false)


## 上升前清掉残留按键状态：窗口获得系统焦点时可能重发按住的键；
## 连续 60 帧仍清不掉则显式失败，不默默带漂移起飞。
func _stabilize_input() -> bool:
	for _index in range(60):
		_release_all()
		await physics_frame
		if _motion.move_input == Vector2.ZERO and is_zero_approx(_motion.vertical_input):
			await _frames(2)
			return true
	_check(false, "起飞前水平/升降输入无法清零（move=%s vert=%.2f），疑似系统重发按键" % [
		str(_motion.move_input), _motion.vertical_input])
	return false


## 打印状态快照：证明确实经过输入飞行，而不是直接摆放角色。
func _capture_snapshot(suffix: String) -> void:
	print("SNAPSHOT %s flight=%s y=%.2f vy=%.2f xz=(%.2f, %.2f) on_floor=%s block=%d" % [
		suffix, str(_motion.flight_active), _actor.global_position.y, _actor.velocity.y,
		_actor.global_position.x, _actor.global_position.z, str(_motion.on_floor),
		TagRegistry.block_count(_actor, FLIGHT_TAG)])


# --- 基础设施 -----------------------------------------------------------------


func _bind() -> void:
	_actor = current_scene.get_node_or_null("Swordsman") as Swordsman
	_camera = root.get_camera_3d()
	if _actor == null:
		return
	_manager = _actor.get_node_or_null("CapabilityManager") as CapabilityManager
	_motion = _actor.motion()
	_layout = _read_layout()
	_spawn = _spawn_from_layout()


## 从上方垂直射线：返回命中字典（无命中为 null）。必须排除角色自身胶囊，
## 否则出生点/站立点在角色正下方时会误命中 Swordsman。
func _ray_down(origin: Vector3, length: float) -> Dictionary:
	var space := _actor.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0.0, -length, 0.0))
	query.collision_mask = 1
	query.exclude = [_actor.get_rid()]
	var hit := space.intersect_ray(query)
	return hit


## 读附加 JSON 的 boxes 名称列表（不存在时返回空数组）。
func _read_json_boxes(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return []
	var names := []
	for value in (parsed as Dictionary).get("boxes", []) as Array:
		names.append(str((value as Dictionary).get("name", "")))
	return names


func _read_layout() -> Dictionary:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _spawn_from_layout() -> Vector3:
	if _layout.is_empty() or not _layout.has("spawn"):
		return Vector3.ZERO
	var position: Array = (_layout["spawn"] as Dictionary)["position"]
	return Vector3(float(position[0]), float(position[1]), float(position[2]))


func _reset_via_r() -> void:
	_key(KEY_R, true)
	await _frames(2)
	_key(KEY_R, false)
	await _frames(8)
	_bind()


func _open_flight() -> void:
	await _frames(2)
	_key(KEY_F, true)
	await _frames(2)
	_key(KEY_F, false)
	await _frames(3)


## 有界等待着地；给 expected_y 时同时核对台面高度，避免把别的平台当目标。
func _wait_floor(timeout_frames: int, expected_y := NAN) -> bool:
	for _index in range(timeout_frames):
		await physics_frame
		if _motion.on_floor:
			if is_nan(expected_y) or absf(_actor.global_position.y - expected_y) < 0.5:
				await _frames(2)
				return true
	return false


func _check_no_combat_rig() -> void:
	var offenders := PackedStringArray()
	for node in _actor.find_children("*", "", true, false):
		var lower := node.name.to_lower()
		for keyword in COMBAT_KEYWORDS:
			if lower.contains(keyword):
				offenders.append(str(node.get_path()))
				break
	_check(offenders.is_empty(), "角色子树无战斗语义节点：%s" % ", ".join(offenders))


## 读场景脚本声明的常量：R 恢复的是场景默认，不是进入前被滚轮改过的值。
func _scene_constant(name: String, fallback: float) -> float:
	var script: Script = current_scene.get_script()
	if script == null:
		return fallback
	var constants := script.get_script_constant_map()
	if not constants.has(name):
		return fallback
	return float(constants[name])


func _module_entry(id: String) -> Dictionary:
	var result := LabCatalog.read()
	for value in result.get("modules", []):
		var entry: Dictionary = value
		if entry["id"] == id:
			return entry
	return {}


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


## OS 按住键时的重复 key-down；必须被边沿消费方忽略。
func _key_echo(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = true
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
	await process_frame


func _capture(suffix: String) -> void:
	# 把窗口提到前台，降低 macOS 遮挡节流导致的掉帧概率。
	DisplayServer.window_move_to_foreground()
	for attempt in range(2):
		_frame_drawn = false
		RenderingServer.frame_post_draw.connect(_on_frame_drawn, CONNECT_ONE_SHOT)
		var deadline := Time.get_ticks_msec() + CAPTURE_TIMEOUT_MSEC
		while not _frame_drawn and Time.get_ticks_msec() < deadline:
			await process_frame
		if _frame_drawn:
			var path := "%s-%s.png" % [_prefix, suffix]
			_check(root.get_texture().get_image().save_png(path) == OK, "渲染截图保存：%s" % path)
			return
		# 单次超时只记诊断，第二次仍失败才算这项截图失败。
		print("RETRY 渲染帧等待超时（第 %d 次）：%s" % [attempt + 1, suffix])
	_check(false, "等待渲染帧超时，未能截图：" + suffix)


func _wait_render_frames(count: int) -> void:
	var drawn: Array[int] = [0]
	var on_draw := func() -> void: drawn[0] += 1
	RenderingServer.frame_post_draw.connect(on_draw)
	var start := Time.get_ticks_msec()
	var deadline := start + CAPTURE_TIMEOUT_MSEC
	while (drawn[0] < count or Time.get_ticks_msec() - start < 2000) and Time.get_ticks_msec() < deadline:
		await process_frame
	RenderingServer.frame_post_draw.disconnect(on_draw)
	_check(drawn[0] >= count, "字体/渲染预热完成，真实绘制帧 %d/%d" % [drawn[0], count])


func _on_frame_drawn() -> void:
	_frame_drawn = true


func _check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failed += 1


func _finish() -> void:
	print("MOUNTAIN_TRAVERSAL_PLAYTEST 完成：失败 %d" % _failed)
	quit(1 if _failed > 0 else 0)
