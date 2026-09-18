# 三能力接口契约：平面移动 / 跳跃 / 御剑

- 状态：已审计（父代理 2026-09-18 通过，含 5 项修正）。决策依据 [mountain-traversal](../../notes/implemented/gameplay/2026-09-18-mountain-traversal.md)；本文件只定接口，实现细节落地时局部细化。
- 归属：角色根 + `SwordsmanMotionComponent` + `SwordsmanMovement` 留在 `game/actors/swordsman/`；新增 `game/abilities/jump/`、`game/abilities/sword_flight/`（含剑视觉子场景）。
- 词汇：`src/data/vocabulary/swordsman.json` 登记下方字段；新建 `src/data/vocabulary/tags/movement.json` 登记 `sword_flight_block`；两者后必跑 `python3 tools/gen/gen_vocabulary_index.py`。
- 默认值一律 `@export` 在组件上，能力不得写死数值。坐标：Godot Y-up，速度 m/s、正 y 向上；屏幕输入 x=右 y=下。

## 组件字段（名 / 类型 / 默认 / 写者）

| 组 | 字段 | 写者 | 语义 |
|---|---|---|---|
| 输入 | `move_input: Vector2 = ZERO` | 场景 | 屏幕相对，`limit_length(1)` |
| 输入 | `vertical_input: float = 0.0` | 场景 | +1 空格升 / -1 Ctrl 降 / 0 悬停 |
| 输入 | `jump_pressed: bool = false` | 场景 `press_jump()` | 空格 key-down 边沿，仅该帧为 true |
| 输入 | `flight_toggle_pressed: bool = false` | 场景 `press_flight_toggle()` | F key-down 边沿，仅该帧为 true |
| 输入 | `camera_right/forward: Vector3` | 场景 | 水平单位向量 |
| 输入 | `aim_direction: Vector3 = FORWARD` | 场景 | 已有字段，继续登记，只影响朝向表现 |
| 状态 | `on_floor: bool = false` | actor 帧末 | 能力读到的是上一帧结果 |
| 状态 | `flight_active: bool = false` | SwordFlight；`reset_motion()` 置 false | 御剑唯一真源 |
| 状态 | `actual_velocity: Vector3 = ZERO` | actor 帧末 velocity（含竖直） | 只读，供表现/HUD |
| 意图 | `desired_horizontal: Vector3 = ZERO`（y=0） | Movement 或 Flight | actor 帧初清零 |
| 意图 | `desired_vertical: float = 0.0` | 仅 Flight | 正上 m/s |
| 意图 | `vertical_impulse: float = 0.0` | 仅 Jump | actor 覆盖 velocity.y，不累加 |
| 参数 | `move_speed=4.0`、`jump_speed=6.0`、`gravity=18.0`、`flight_speed=12.0`、`flight_lift_speed=7.0`、`flight_sink_speed=7.0`、`flight_launch_speed=3.0`、`flight_launch_time=0.25` | 导出 | 单点调参 |

边沿/悬停语义：按住空格不重复触发；能力失活不清意图（由 actor 清，避免踩掉高优先级同帧写入）；松键悬停，`vertical_input=0` 时御剑竖直速度为 0。

## 优先级、Tag 与三能力

CapabilityManager 按 priority 降序同帧轮询：`SwordFlight=100` → `Jump=50` → `SwordsmanMovement=0`（各自 `_init()` 设定，场景属性不参与）。唯一 Tag `sword_flight_block`：target=角色，instigator=SwordFlight 自身；Movement/Jump 只读 `TagRegistry.is_blocked(host, &"sword_flight_block")`。

- **SwordsmanMovement**：`move_input≠0` 且未阻塞时激活，按相机地面基 × `move_speed` 只写 `desired_horizontal`（地面/非御剑空中同规则）。
- **Jump**：`jump_pressed && on_floor && 未阻塞` 激活，写 `vertical_impulse = jump_speed`，下一 tick 即失活（单帧冲量），不做物理。
- **SwordFlight**：`flight_toggle_pressed && !flight_active` 开启，`_on_activated` 里 `flight_active=true` + `add_block(self)`；每 tick 按 `flight_speed` 写水平意图，竖直取值：地面升起窗口（`manager_time() < 激活时刻+``flight_launch_time`）→ `flight_launch_speed`；激活首帧非地面 → `clampf(velocity.y, -flight_sink_speed, flight_lift_speed)`；此后 `vertical_input` 决定 lift / sink / 0。`flight_toggle_pressed && flight_active` 再按 F 关闭；`_on_deactivated` 与 `_exit_tree` 都必须把 `flight_active` 置 false、`remove_block(self)` 并清计时——移除飞行能力后 actor 不得继续御剑；只移除自己的 instigator 阻塞，其他 instigator 的阻塞保留。

## actor 每帧顺序（唯一物理提交点，全帧一次 move_and_slide）

1. `on_floor = is_on_floor()`；2. 三个意图字段归零；3. `_manager.tick(delta)`；4. 合成速度：飞行 → `velocity.xz = desired_horizontal.xz`、`velocity.y = desired_vertical`（不吃重力、忽略冲量）；非飞行 → `velocity.xz = desired_horizontal.xz`，`on_floor ? velocity.y=0 : velocity.y -= gravity*delta`，`vertical_impulse≠0` 时覆盖 `velocity.y`；5. 一次 `move_and_slide()`；6. 回写 `actual_velocity`、`on_floor`；7. 两个边沿置 false、三意图归零；8. `_face_aim()` 与 `flight_visual.visible = flight_active`。actor 不读键鼠、不认识实验场景、不引用任何 Capability 类名；`CapabilityManager.set_process(false)` 保留。

## 场景调用 API 与失焦

`set_move_input(Vector2)`、`set_vertical_input(float)`、`press_jump()`、`press_flight_toggle()`（边沿各调一次）、已有 `set_camera_ground_basis()/set_aim_direction()`、`reset_motion()`（R：清输入、边沿、速度、意图、`flight_active`）、`clear_input()`（清四种输入，不碰飞行）、`motion()` 只读、`bind_flight_visual(node)`。场景先写输入、actor 子节点随后 tick；**失焦必须调用 `clear_input()`；已开启的御剑保留悬停，不自动关飞、不坠落；只有 R 关闭并清账；场景不得用 `reset_motion()` 代替失焦清理**。世界边界与高度上限由场景物理碰撞承担；能力只基于组件参数与意图，不改 core，不自行改 velocity。

## 拆装、阻塞清理与同帧裁决

- 独立拆装＝装配中移除对应 Capability 节点后其余照常：删 Jump → 空格无效；删 Flight → F 无效且无 `sword_flight_block` 残留（`_exit_tree` 清账）；删 Movement → 仍可跳/飞。不物理删包、不制造场景悬空引用。
- 清理路径三条：①再按 F 失活；②R 置 `flight_active=false`，下一 physics tick 的 `_should_deactivate` 清账（可接受，必须实测）；③节点移除 `_exit_tree` 清账。
- 同帧 F+Space（地面）：Flight(100) 先激活并 add_block，Jump(50) 当帧被阻塞、无冲量，两边沿帧末清零、下一帧不补跳，竖直速度 = `flight_launch_speed`。跳跃中按 F：首帧保留 `velocity.y` 限幅后接管。按键同时关 F+按空格：先解除阻塞，再按普通规则评估起跳（上一帧着地则正常跳）。空中关 F：同帧解阻塞，且 actor 当帧流水线就恢复重力（tick 后读 `flight_active=false` 合成速度，不是下一帧）。贴地悬停允许，`on_floor` 照常回写供 HUD。
