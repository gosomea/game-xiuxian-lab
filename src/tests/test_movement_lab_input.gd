extends RefCounted

## MovementLabInput 契约单测（角色移动子实验套件专用输入 helper）。
##
## 覆盖：WASD/方向键等价、斜向限速、按住与释放、echo 重复事件安全、边沿判据、
## 升降输入、失焦清账、scene 专有键透传，以及"不得越界"的结构约束。
## 两场景的真实输入回归在 camera_lab_playtest.gd / motion_stage_playtest.gd。

const HELPER_PATH := "res://levels/experiments/character_movement/movement_lab_input.gd"
const HelperScript := preload("res://levels/experiments/character_movement/movement_lab_input.gd")


static func run(t) -> void:
	_run_key_mapping(t)
	_run_diagonal_limit(t)
	_run_hold_release_and_echo(t)
	_run_vertical(t)
	_run_scene_specific_keys(t)
	_run_clear(t)
	_run_structure(t)


static func _helper() -> MovementLabInput:
	return HelperScript.new()


static func _key(code: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


static func _run_key_mapping(t) -> void:
	t.begin_case()
	# WASD 与方向键完全等价：同一方向、同一结果。
	var equivalents := [
		[KEY_W, KEY_UP], [KEY_S, KEY_DOWN], [KEY_A, KEY_LEFT], [KEY_D, KEY_RIGHT],
	]
	for pair in equivalents:
		var wasd := _helper()
		wasd.track_key(_key(pair[0], true))
		var arrow := _helper()
		arrow.track_key(_key(pair[1], true))
		t.assert_eq(wasd.move_input(), arrow.move_input(),
			"%s 与 %s 等价" % [OS.get_keycode_string(pair[0]), OS.get_keycode_string(pair[1])])

	t.begin_case()
	var up := _helper()
	up.track_key(_key(KEY_W, true))
	t.assert_eq(up.move_input(), Vector2(0.0, -1.0), "W = 屏幕上方")
	var down := _helper()
	down.track_key(_key(KEY_S, true))
	t.assert_eq(down.move_input(), Vector2(0.0, 1.0), "S = 屏幕下方")
	var left := _helper()
	left.track_key(_key(KEY_A, true))
	t.assert_eq(left.move_input(), Vector2(-1.0, 0.0), "A = 屏幕左方")
	var right := _helper()
	right.track_key(_key(KEY_D, true))
	t.assert_eq(right.move_input(), Vector2(1.0, 0.0), "D = 屏幕右方")


static func _run_diagonal_limit(t) -> void:
	t.begin_case()
	var diagonal := _helper()
	diagonal.track_key(_key(KEY_W, true))
	diagonal.track_key(_key(KEY_D, true))
	t.assert_true(is_equal_approx(diagonal.move_input().length(), 1.0),
		"斜向两键输入长度收敛到 1（实际 %.4f）" % diagonal.move_input().length())
	t.assert_true(diagonal.move_input().x > 0.0 and diagonal.move_input().y < 0.0, "W+D 指向右上")

	t.begin_case()
	# 同向重复键（W + Up）不得叠加成两倍速度。
	var twin := _helper()
	twin.track_key(_key(KEY_W, true))
	twin.track_key(_key(KEY_UP, true))
	t.assert_eq(twin.move_input(), Vector2(0.0, -1.0), "同向两键不叠加")

	t.begin_case()
	# 四键同按仍不得超过单位长度。
	var all_four := _helper()
	for code in [KEY_W, KEY_A, KEY_S, KEY_D]:
		all_four.track_key(_key(code, true))
	t.assert_true(all_four.move_input().length() <= 1.0 + 0.0001,
		"四键同按不超过单位长度（实际 %.4f）" % all_four.move_input().length())


static func _run_hold_release_and_echo(t) -> void:
	t.begin_case()
	var held := _helper()
	held.track_key(_key(KEY_W, true))
	t.assert_true(held.is_down(KEY_W), "按下后状态为按住")
	held.track_key(_key(KEY_W, false))
	t.assert_false(held.is_down(KEY_W), "释放后状态清除")
	t.assert_eq(held.move_input(), Vector2.ZERO, "释放后输入归零")

	t.begin_case()
	# echo（按住重复）不得被当成新的按下边沿，但按住状态必须保持。
	var echoed := _helper()
	var down := _key(KEY_W, true)
	t.assert_true(echoed.track_key(down), "跟踪的按下事件返回 true")
	t.assert_true(HelperScript.is_key_down_edge(down), "首次按下是边沿")
	t.assert_false(HelperScript.is_key_down_edge(_key(KEY_W, true, true)), "echo 重复事件不是新边沿")
	t.assert_false(HelperScript.is_key_down_edge(_key(KEY_W, false)), "释放事件不是按下边沿")
	echoed.track_key(_key(KEY_W, true, true))
	t.assert_true(echoed.is_down(KEY_W), "echo 输入期间仍保持按住")
	t.assert_eq(echoed.move_input(), Vector2(0.0, -1.0), "echo 期间输入不抖")

	t.begin_case()
	var idle := _helper()
	t.assert_false(idle.is_down(KEY_W), "未按键时 is_down 为 false")
	t.assert_eq(idle.move_input(), Vector2.ZERO, "未按键时输入为零")
	t.assert_eq(idle.held_count(), 0, "未按键时按住计数为零")

	t.begin_case()
	# 释放一个键不误清另一个键。
	var two_keys := _helper()
	two_keys.track_key(_key(KEY_W, true))
	two_keys.track_key(_key(KEY_D, true))
	two_keys.track_key(_key(KEY_W, false))
	t.assert_eq(two_keys.move_input(), Vector2(1.0, 0.0), "松开 W 后仅剩 D 的输入")


static func _run_vertical(t) -> void:
	t.begin_case()
	var both := _helper()
	both.track_key(_key(MovementLabInput.KEY_VERTICAL_UP, true), MovementLabInput.VERTICAL_KEYS)
	t.assert_eq(both.vertical_input(), 1.0, "空格 = +1 上升")
	both.track_key(_key(MovementLabInput.KEY_VERTICAL_DOWN, true), MovementLabInput.VERTICAL_KEYS)
	t.assert_eq(both.vertical_input(), 0.0, "空格 + Ctrl 同按相互抵消为 0")

	t.begin_case()
	var sinking := _helper()
	sinking.track_key(_key(MovementLabInput.KEY_VERTICAL_DOWN, true), MovementLabInput.VERTICAL_KEYS)
	t.assert_eq(sinking.vertical_input(), -1.0, "Ctrl = -1 下降")

	t.begin_case()
	var released := _helper()
	released.track_key(_key(MovementLabInput.KEY_VERTICAL_UP, true), MovementLabInput.VERTICAL_KEYS)
	released.track_key(_key(MovementLabInput.KEY_VERTICAL_UP, false), MovementLabInput.VERTICAL_KEYS)
	t.assert_eq(released.vertical_input(), 0.0, "松开空格回到悬停 0")

	t.begin_case()
	# 升降键不得污染移动输入（两者是同一次按键的两个语义出口）。
	var separate := _helper()
	separate.track_key(_key(MovementLabInput.KEY_VERTICAL_UP, true), MovementLabInput.VERTICAL_KEYS)
	t.assert_eq(separate.move_input(), Vector2.ZERO, "空格不产生水平输入")

	t.begin_case()
	# 升降键必须由场景显式声明：未声明的场景不应把它变成"已处理"（保持原有事件传播）。
	var camera_like := _helper()
	t.assert_false(camera_like.track_key(_key(MovementLabInput.KEY_VERTICAL_UP, true)),
		"未声明升降键时不被跟踪（镜头实验室不消费空格）")
	t.assert_false(HelperScript.is_tracked(MovementLabInput.KEY_VERTICAL_DOWN),
		"未声明时 is_tracked 对升降键为 false")
	t.assert_true(HelperScript.is_tracked(MovementLabInput.KEY_VERTICAL_UP, MovementLabInput.VERTICAL_KEYS),
		"声明后升降键被跟踪")
	t.assert_eq(camera_like.vertical_input(), 0.0, "未声明时升降输入恒为 0")


static func _run_scene_specific_keys(t) -> void:
	t.begin_case()
	# 场景专有"按住"键（如镜头实验的 Q/E）：只记状态，不进入移动向量。
	var yaw := _helper()
	t.assert_true(yaw.track_key(_key(KEY_Q, true), [KEY_Q, KEY_E]), "声明的附加键被跟踪")
	t.assert_true(yaw.is_down(KEY_Q), "附加键状态可读回")
	t.assert_eq(yaw.move_input(), Vector2.ZERO, "附加键不污染移动输入")
	t.assert_eq(yaw.vertical_input(), 0.0, "附加键不污染升降输入")

	t.begin_case()
	var undeclared := _helper()
	t.assert_false(undeclared.track_key(_key(KEY_Q, true)), "未声明的附加键不被跟踪")
	t.assert_false(undeclared.is_down(KEY_Q), "未声明的附加键不记状态")
	t.assert_false(undeclared.track_key(_key(KEY_R, true)), "任意其它键不被跟踪")
	t.assert_false(HelperScript.is_tracked(KEY_ESCAPE), "Esc 不属于输入 helper")

	t.begin_case()
	var mixed := _helper()
	mixed.track_key(_key(KEY_D, true), [KEY_Q])
	t.assert_true(mixed.is_down(KEY_D), "附加键存在时移动键仍被跟踪")


static func _run_clear(t) -> void:
	t.begin_case()
	# 升降键必须带 VERTICAL_KEYS 才会进入 _held；clear 前的断言用来证明这一点，
	# 否则 clear 后的 0 无法区分"被清掉"和"从来没进去"。
	var cleared := _helper()
	cleared.track_key(_key(KEY_W, true))
	cleared.track_key(_key(KEY_A, true))
	cleared.track_key(_key(MovementLabInput.KEY_VERTICAL_UP, true), MovementLabInput.VERTICAL_KEYS)
	cleared.track_key(_key(KEY_Q, true), [KEY_Q])
	t.assert_eq(cleared.held_count(), 4, "clear 前按住集合含移动 / 升降 / 附加共 4 键")
	t.assert_true(cleared.is_down(MovementLabInput.KEY_VERTICAL_UP), "clear 前升降键确实按住")
	t.assert_eq(cleared.vertical_input(), 1.0, "clear 前升降输入为 +1")
	cleared.clear()
	t.assert_eq(cleared.held_count(), 0, "clear 后按住集合为空")
	t.assert_eq(cleared.move_input(), Vector2.ZERO, "clear 后移动输入归零")
	t.assert_eq(cleared.vertical_input(), 0.0, "clear 后升降归零")
	t.assert_false(cleared.is_down(KEY_Q), "clear 连附加键一起清")
	t.assert_false(cleared.is_down(MovementLabInput.KEY_VERTICAL_UP), "clear 连升降键一起清")

	t.begin_case()
	# clear 后仍可继续接收输入（失焦恢复不需要重建对象）。
	var reused := _helper()
	reused.track_key(_key(KEY_D, true))
	reused.clear()
	reused.track_key(_key(KEY_D, true))
	t.assert_eq(reused.move_input(), Vector2(1.0, 0.0), "clear 后仍可重新接收输入")


## 结构约束：helper 必须保持"纯状态对象"，不得成为通用框架或耦合运行时。
static func _run_structure(t) -> void:
	t.begin_case()
	var source := FileAccess.get_file_as_string(HELPER_PATH)
	t.assert_true(not source.is_empty(), "helper 源码可读取")

	var code := _strip_comments(source)
	t.assert_true(code.contains("extends RefCounted"), "helper 是 RefCounted（无节点生命周期）")
	t.assert_false(code.contains("extends Node"), "helper 不是 Node")
	t.assert_false(code.contains("_process"), "helper 无 _process")
	t.assert_false(code.contains("_physics_process"), "helper 无 _physics_process")
	t.assert_false(code.contains("_ready"), "helper 无 _ready")

	# 不得引用运行时角色 / 架构设施 / 场景设施。
	for forbidden in ["Swordsman", "Capability", "Component", "TagRegistry",
			"Camera3D", "change_scene", "CanvasLayer", "Theme"]:
		t.assert_false(code.contains(forbidden), "helper 不引用 %s" % forbidden)

	# 不得写物理或组件字段。
	for forbidden in ["velocity", "desired_horizontal", "desired_vertical",
			"vertical_impulse", "move_and_slide", "add_block"]:
		t.assert_false(code.contains(forbidden), "helper 不触碰 %s" % forbidden)

	# 不得调用角色公开 API：调用时机由各场景决定。
	for forbidden in ["set_move_input", "set_vertical_input", "press_jump", "press_flight_toggle"]:
		t.assert_false(code.contains(forbidden), "helper 不自行调用 %s" % forbidden)

	t.begin_case()
	# 两个消费者都必须真的用上它，否则共享是空谈。
	for scene_path in ["res://levels/experiments/character_movement/camera_lab.gd",
			"res://levels/experiments/character_movement/motion_stage.gd"]:
		var scene := FileAccess.get_file_as_string(scene_path)
		t.assert_true(scene.contains("MovementLabInput.new()"),
			"%s 使用 MovementLabInput" % scene_path.get_file())
		t.assert_false(scene.contains("KEY_UP:"), "%s 不再自带方向键映射" % scene_path.get_file())
		t.assert_false(scene.contains("func _read_move_input"),
			"%s 不再重复实现移动输入读取" % scene_path.get_file())


static func _strip_comments(source: String) -> String:
	var kept := PackedStringArray()
	for line in source.split("\n"):
		var text: String = line
		var cut := text.find("#")
		if cut >= 0:
			text = text.substr(0, cut)
		var trimmed := text.strip_edges()
		if not trimmed.is_empty():
			kept.append(trimmed)
	return "\n".join(kept)
