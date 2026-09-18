# 状态切换压力场验收（2026-09-18）

场景：`res://levels/experiments/character_movement/state_transition_lab.tscn`（心境 / 身法试炼阵）。
决策依据：[character-movement-subexperiments](../../notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md)。
只读设计：本轮实现即上一轮只读方案的收敛版（少量可重复序列，不建通用状态机）。
验收档位：**CLI 档**（headless 真实输入 + 窗口模式截图）。godot-ai 编辑器桥在本会话始终无活动会话。

## 这一场回答什么

只回答「能力切换、失焦、重置、碰撞与边缘时机是否正确清账」。不新增第四项 Capability，
不实现战斗，不实现通用状态机；账本只记录场景**实际观察到**的读数。

## 五问分类

| 项 | 1 已实现 | 2 已运行通过（命令 + 结果） | 3 静态检查 | 4 未验证 | 5 外部阻塞 |
|---|---|---|---|---|---|
| 三能力 + 无第四能力 |  | ✔ assembly 批次：sorted_capabilities == [SwordFlight, Jump, SwordsmanMovement] | ✔ 场景不实例化能力类 |  |  |
| 唯一物理提交点 |  | ✔ assembly 批次通过 | ✔ actor 一处 move_and_slide；三能力与场景各 0 处 |  |  |
| 只调公开输入 API |  | ✔ 全部批次经真实 InputEventKey → `_unhandled_input` → 公开 API | ✔ 场景源码不含 desired_* / vertical_impulse / velocity 赋值 / add_block / .tick( |  |  |
| 跑动 → 跳跃 → 落地 |  | ✔ runjump 14/14（跑动 4.00 m/s，顶点 1.05 m，真实落回） |  |  |  |
| 地面 → 御剑 → 升降 → 关飞 → 恢复重力 |  | ✔ flight 20/20（升起 3.00、升 7.00、悬停 vy≈0、Ctrl −7.00、关飞当帧速度下降、落回 y=0） |  |  |  |
| 撞墙期间切御剑 |  | ✔ collision 11/11（滑动接触命中 GateWallEast、0 穿透帧、飞行平移被墙截断、仍可垂直升起、关飞清账） |  |  |  |
| 边缘离地时跳跃 / 御剑优先级 |  | ✔ edge 10/10（离地后空格无冲量；同帧 F+Space 御剑接管、Jump 未激活、竖直限幅） |  |  |  |
| 按住 + 失焦 → 输入清零、飞行保留悬停 |  | ✔ focus 11/11（flight 保留、block=1、vy≈0、Δy 稳定；输入缓存清零经只读快照核对；重新按键仍生效） |  |  |  |
| R → 位置 / 运动 / 阻塞统一清账 |  | ✔ reset 10/10（回起点、flight=false、block=0、速度与输入归零、输入缓存清零、5 帧后仍无阻塞） |  |  |  |
| 事件账本来自实际读数 |  | ✔ ledger 9/9（字段全为真实布尔 / 计数；flight=true 必带 block≥1；能力列仅 -1/0/1） | ✔ 账本模块不引用 TagRegistry / Swordsman / Capability，不写运动量 |  |  |
| 序列可重复 |  | ✔ repeat 7/7（跳跃弧线与御剑开关各跑两遍，读数一致；结束无残留） |  |  |  |
| echo 不重复触发 |  | ✔ repeat 内含按住 + 每帧 echo：两遍均只起跳一次 |  |  |  |
| 返回链 |  | ✔ hub 4/4（Esc 回 MovementLabHub、按钮文案、切场景无阻塞残留） | ✔ 场景声明 HUB_SCENE 指向子实验目录 |  |  |
| Tier 0 门禁 |  | ✔ 全通过 + 负向控制 27/27 |  |  |  |
| 运行时单元套件 |  | ✔ **260 通过 / 0 失败** |  |  |  |
| 窗口模式截图 |  | ✔ 11 张入仓，SNAPSHOT 行齐全 | ✔ 人工读图 |  |  |

## 精确计数

| 检查 | 命令 | 结果 |
|---|---|---|
| 完整 playtest | `--script res://tests/state_transition_lab_playtest.gd` | **133 PASS / 0 FAIL，stderr 0 行** |
| 分批（10 批） | `--batch=assembly,runjump,flight,collision,edge,focus,reset,ledger,repeat,hub` | 37 / 14 / 20 / 11 / 10 / 11 / 10 / 9 / 7 / 4 |
| 单元套件 | `godot --headless --path src tests/test_runner.tscn` | 260 通过 / 0 失败 |
| Tier 0 | `python3 tools/verify/run_all.py` | 全部通过，负向控制 27/27 |
| 窗口截图 | `--capture-prefix=... state_transition_lab` | 11 张，0 FAIL |
| diff 卫生 | `git diff --check` | clean |

原始日志（不入 Git）：`~/.cache/game-xiuxian-lab/state-transition-lab/`
（`final.log` / `final.err` / 十个批次日志 / `capture-final3.log` / `gates.log` / `test-runner.log`）。

## 关键实测读数（事实）

- 起跳顶点 **1.05 m**（地面 y=0）；跑动水平速度 **4.00 m/s**。
- 御剑升起 **3.00 m/s**、上升 **7.00 m/s**、下降 **−7.00 m/s**、悬停 vy ≈ 0；关飞当帧竖直速度转负（恢复重力）。
- 撞墙：石门东墙面 z = −4.95，角色停在 **z = −4.583**（胶囊半径 0.35 + 余量），真实滑动接触、
  **0 穿透帧**（阈值 0.05 m）。
- 同帧 F+Space（空中）：`flight_active=true`、`block_count=1`、`Jump.active=false`、竖直速度被限幅 ≤ 7.0。
- 失焦后：`move_input=ZERO`、`vertical_input=0`、`flight_active` 保留、`block_count=1`、Δy < 0.8 m。
- R 后：位置回 (0, 0.05, 2.6)、`flight_active=false`、`block_count=0`、`velocity≈0`，5 帧后仍为 0。
- 账本一致性：所有事件字段均为真实读数；凡 `flight=true` 的行 `block ≥ 1`。

## 事件账本与时间线（现场可视化）

- **账本**（左下，`RichTextLabel`，BBCode）：逐条列出相对帧、事件、着地/御剑/block 读数、三能力诊断列
  （● 激活 / ○ 未激活 / · 节点缺失）与判定说明。只在内容变化时重建文本（脏标记）。
- **时间线**（右上，自绘 `Control._draw()`）：状态色带（步行 / 空中 / 御剑）+ block lane +
  两条能力 lane + 事件标记 + 播放头，只在新事件或帧推进时 `queue_redraw()`。
- **只记观察到的事实**：能力激活态按节点名读取，取不到记 −1（时间线画灰），不猜测、不补默认值；
  边沿事件延迟到 actor tick 之后入账，因此记录的是「边沿被消费后的同帧事实」。

## 截图（窗口模式，真实输入驱动）

| 截图 | 内容 |
|---|---|
| `-overview.png` | 全景：阴阳玉盘、石门、断桥、阵纹柱、账本与时间线 |
| `-jump-transition.png` | 跳跃转换（起跳后约 18 帧，on_floor=false、y=1.04） |
| `-flight-transition.png` | 御剑转换（flight=true、block=1、离地） |
| `-edge-leave.png` | 边缘离地（走出低台，仍在阵盘内） |
| `-edge-flight-priority.png` | 边缘同帧 F+Space：御剑接管 |
| `-wall-contact.png` | 撞墙（真实滑动接触，位置 (3.0, 0.0, −5.0)） |
| `-focus-hover.png` | 失焦后悬停（flight=true、block=1） |
| `-before-reset.png` / `-after-reset.png` | R 前后清账对比 |
| `-ledger-timeline.png` | 账本与时间线近观（多类事件） |
| `-small.png` | 960×600 最小窗口 |

## hub 集成状态（2026-09-18 集成收口后）

本轮落地时该条目尚未登记；集成阶段已把它改为 `exploring` 并填入本场景路径，hub 现显示为可进入。
集成前的独立运行证据（上表计数与读数）保持为当时的实测快照，未改动。
集成验证与最终计数见 [集成权威报告](2026-09-18-character-movement-subexperiments.md)。
场景满足 hub 契约：`HUB_SCENE` 指向 `movement_lab_hub.tscn`、Esc 返回、按钮文案「返回子实验目录」。

## 事实 vs 待人工评价

**事实（自动验证）**：上表全部计数与关键读数，含转换顺序、echo、失焦、重置、阻塞清账、撞墙、边缘优先级。
**待人工评价**：阵盘配色与造型观感；账本/时间线在真实游玩中的可读性；转换时的画面节奏是否好看。
自动检查不替代审美与手感判断。

## 只读访问器（2026-09-18 审查收口）

- 场景新增 `ledger()`、`input_held_count()`、`input_state()` 三个**公开只读**访问器：
  验收脚本经它们读取账本与输入状态，不再读私有字段 `_ledger` / `_input_helper`；
  `input_state()` 返回值拷贝，不暴露可变内部集合。**未增加任何写入钩子。**
- 常量收口：删除死常量 `SWORD_PATH`（与 `FLYING_SWORD_SCENE` 重复的路径字符串）；
  `WALL_HALF_X`、`GAP_MIN_X`、`GAP_MAX_X` 接入碰撞装配，成为断桥与石门墙的唯一真源——
  碰撞段位置与跨度全部由它们推导，并加两条 `assert` 把碰撞边缘钉死在对齐 GLB 的 6.1 / 14.7，
  防止再次静默漂移。修此问题时发现碰撞缺口曾被手写成 9.1–11.9 而 GLB 残端为 9.35 / 11.75，
  现已对齐为 9.1–11.5。

## 已知限制

- 未做战斗 / 通用状态机（刻意不做，见任务边界）；无第四能力。
- `edge-flight-priority` 截图里角色恰在低台附近，御剑接管瞬间的**竖直限幅**由断言而非画面证明。
- 阵盘 GLB 只含视觉；物理由场景 BoxShape3D 精确装配，改几何需同步两侧（见美术 README）。
- 未 commit（按任务约定）；未改任何共享文件与 hub 集成文件。
