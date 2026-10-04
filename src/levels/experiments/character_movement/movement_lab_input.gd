class_name MovementLabInput
extends RefCounted

## 角色移动子实验套件专用的输入状态对象（纯数据 + 归一化，无节点、无生命周期）。
##
## 存在理由：camera_lab 与 motion_stage 已成为两个真实消费者，重复维护同一套
## WASD / 方向键映射、按住状态、二维单位输入、升降输入、动作边沿与失焦清理。
## 依据 [character-movement-subexperiments](../../../../notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md)
## 「重复且语义稳定的实验 UI 或输入编排才抽成移动实验专属组合节点」——两个场景验证后再抽取。
##
## 边界（不得越界）：
## - 只服务本套件，位于 levels/experiments/character_movement/，不进 core/ 或 game/，不是通用框架。
## - 不 preload / 不引用 Swordsman、Capability、Component、TagRegistry、Camera、场景跳转与 HUD。
## - 不调用任何角色方法：仅提供完整输入帧，由场景在物理阶段交付给角色公开入口。
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

## 疾行键：Shift。所有共享修士场景默认跟踪，速度选择由角色共享移动能力执行。
const KEY_SPRINT := KEY_SHIFT

## 升降键：空格 +1（跳跃 / 上升），Ctrl -1（下降）。
## 全部共享修士场景默认跟踪跳跃、升降与御剑操作。
const KEY_VERTICAL_UP := KEY_SPACE
const KEY_VERTICAL_DOWN := KEY_CTRL
const VERTICAL_KEYS: Array[Key] = [KEY_SPACE, KEY_CTRL]
const KEY_FLIGHT := KEY_F

## 按住状态：物理键码 → bool。默认记录完整移动操作，另记录场景声明的附加键。
var _held: Dictionary = {}
var _jump_pending := false
var _flight_pending := false


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
## 方向 / Shift / Space / Ctrl / F 默认统一跟踪；相机与实验控制键仍由各场景处理。
## record_edges=false 用于预览等禁用角色操作的模式，避免积攒稍后误触发的动作。
func track_key(event: InputEventKey, extra_codes: Array = [], record_edges: bool = true) -> bool:
	var code := key_code(event)
	if not is_tracked(code, extra_codes):
		return false
	_held[code] = event.pressed
	if record_edges and is_key_down_edge(event):
		if code == KEY_VERTICAL_UP:
			_jump_pending = true
		elif code == KEY_FLIGHT:
			_flight_pending = true
	return true


## 该物理键码是否由本 helper 跟踪（全部移动操作 + 场景声明的附加键）。
static func is_tracked(code: Key, extra_codes: Array = []) -> bool:
	return MOVE_KEYS.has(code) or code == KEY_SPRINT or VERTICAL_KEYS.has(code) \
		or code == KEY_FLIGHT or extra_codes.has(code)


func is_down(code: Key) -> bool:
	return _held.get(code, false)


## 二维屏幕相对输入（x = 右，y = 下）；斜向输入先归一到单位长度，避免两键同按加速。
func move_input() -> Vector2:
	var input_vector := Vector2.ZERO
	for code in MOVE_KEYS:
		if _held.get(code, false):
			input_vector += MOVE_KEYS[code] as Vector2
	return (input_vector as Vector2).limit_length(1.0)


## 疾跑意图：按住 Shift 且有移动方向；仅按 Shift 不产生移动。
func sprint_input() -> bool:
	return is_down(KEY_SPRINT) and move_input() != Vector2.ZERO


## 升降意图：+1 上升 / -1 下降 / 0 悬停（两键同按时相互抵消）。
func vertical_input() -> float:
	var value := 0.0
	if _held.get(KEY_VERTICAL_UP, false):
		value += 1.0
	if _held.get(KEY_VERTICAL_DOWN, false):
		value -= 1.0
	return clampf(value, -1.0, 1.0)


## 完整的一帧输入，供角色公开入口消费；保持按住状态，跳跃与御剑边沿只交付一次。
func consume_motion_input() -> Dictionary:
	var frame := {
		"move": move_input(), "sprint": sprint_input(), "vertical": vertical_input(),
		"jump": _jump_pending, "flight": _flight_pending,
	}
	_jump_pending = false
	_flight_pending = false
	return frame


## 失焦 / 重置清账：只清本对象状态，是否清角色输入由场景决定。
func clear() -> void:
	_held.clear()
	_jump_pending = false
	_flight_pending = false


## 只读诊断：当前按住的键数（测试与 HUD 读回用，不暴露可变集合）。
func held_count() -> int:
	return _held.size()
