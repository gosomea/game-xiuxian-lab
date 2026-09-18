class_name MovementLabInput
extends RefCounted

## 角色移动子实验套件专用的输入状态对象（纯数据 + 归一化，无节点、无生命周期）。
##
## 存在理由：camera_lab 与 motion_stage 已成为两个真实消费者，重复维护同一套
## WASD / 方向键映射、按住状态、二维单位输入、升降输入与失焦清理。
## 依据 [character-movement-subexperiments](../../../../notes/proposed/gameplay/2026-09-18-character-movement-subexperiments.md)
## 「重复且语义稳定的实验 UI 或输入编排才抽成移动实验专属组合节点」——两个场景验证后再抽取。
##
## 边界（不得越界）：
## - 只服务本套件，位于 levels/experiments/character_movement/，不进 core/ 或 game/，不是通用框架。
## - 不 preload / 不引用 Swordsman、Capability、Component、TagRegistry、Camera、场景跳转与 HUD。
## - 不调用任何角色方法：何时 set_move_input / set_vertical_input / press_jump /
##   press_flight_toggle 由场景决定。
## - 不写 velocity 或组件字段；不含 _process / _physics_process（RefCounted 无节点生命周期）。
## - 镜头基向量、视角、策略与模式键等实验差异全部留在各自场景。

## 物理键 → 屏幕输入（x = 右，y = 下）；WASD 与方向键等价。
const MOVE_KEYS := {
	KEY_W: Vector2(0.0, -1.0),
	KEY_UP: Vector2(0.0, -1.0),
	KEY_S: Vector2(0.0, 1.0),
	KEY_DOWN: Vector2(0.0, 1.0),
	KEY_A: Vector2(-1.0, 0.0),
	KEY_LEFT: Vector2(-1.0, 0.0),
	KEY_D: Vector2(1.0, 0.0),
	KEY_RIGHT: Vector2(1.0, 0.0),
}

## 升降键：空格 +1（跳跃 / 上升），Ctrl -1（下降）。
## 升降键是**可选**跟踪项：只有真正使用升降输入的场景才通过 track_key 的
## extra_codes 传入，避免把不相关的键变成"已处理"、改变原有事件传播。
const KEY_VERTICAL_UP := KEY_SPACE
const KEY_VERTICAL_DOWN := KEY_CTRL
const VERTICAL_KEYS: Array[Key] = [KEY_SPACE, KEY_CTRL]

## 按住状态：物理键码 → bool。只记录本 helper 认得的键与场景显式声明的附加键。
var _held: Dictionary = {}


## 物理键码归一化：优先物理键码（不看键盘布局），个别平台修饰键只填逻辑键码时回退。
static func key_code(event: InputEventKey) -> Key:
	if event == null:
		return KEY_NONE
	return event.physical_keycode if event.physical_keycode != 0 else event.keycode


## 非 echo 的按下边沿：按住重复事件不算新的一按（跳跃 / 御剑 / 切模式共用此判据）。
static func is_key_down_edge(event: InputEventKey) -> bool:
	return event != null and event.pressed and not event.echo


## 记录一次按键事件，返回该事件是否属于本 helper 跟踪的键。
## 返回 true 时场景可 set_input_as_handled；返回 false 说明是场景专有键，由场景自行处理。
## extra_codes 声明场景要跟踪的附加键，只记状态不懂语义：
## - 镜头实验室传 YAW_KEYS（Q / E 按住转镜头），不使用升降输入；
## - 人物动作工作台传 VERTICAL_KEYS（空格 / Ctrl 跳跃与升降）。
## 由场景声明而非 helper 写死，是为了不把场景用不到的键变成"已处理"。
func track_key(event: InputEventKey, extra_codes: Array = []) -> bool:
	var code := key_code(event)
	if not is_tracked(code, extra_codes):
		return false
	_held[code] = event.pressed
	return true


## 该物理键码是否由本 helper 跟踪（移动键 + 场景声明的附加键）。
static func is_tracked(code: Key, extra_codes: Array = []) -> bool:
	return MOVE_KEYS.has(code) or extra_codes.has(code)


func is_down(code: Key) -> bool:
	return _held.get(code, false)


## 二维屏幕相对输入（x = 右，y = 下）；斜向输入先归一到单位长度，避免两键同按加速。
func move_input() -> Vector2:
	var input_vector := Vector2.ZERO
	for code in MOVE_KEYS:
		if _held.get(code, false):
			input_vector += MOVE_KEYS[code] as Vector2
	return (input_vector as Vector2).limit_length(1.0)


## 升降意图：+1 上升 / -1 下降 / 0 悬停（两键同按时相互抵消）。
func vertical_input() -> float:
	var value := 0.0
	if _held.get(KEY_VERTICAL_UP, false):
		value += 1.0
	if _held.get(KEY_VERTICAL_DOWN, false):
		value -= 1.0
	return clampf(value, -1.0, 1.0)


## 失焦 / 重置清账：只清本对象状态，是否清角色输入由场景决定。
func clear() -> void:
	_held.clear()


## 只读诊断：当前按住的键数（测试与 HUD 读回用，不暴露可变集合）。
func held_count() -> int:
	return _held.size()
