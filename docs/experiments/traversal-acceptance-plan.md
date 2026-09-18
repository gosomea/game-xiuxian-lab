# 群山宗门移动探索 · 独立验收矩阵

- 日期：2026-09-18
- 验收执行：独立验收代理（forever-subagents）。最终所有 Godot 运行、门禁、集成与视觉验收由本代理独占执行；父代理只审计，不跑测试。
- 依据：`notes/implemented/gameplay/2026-09-18-mountain-traversal.md` 的验收标准；已读 AGENTS.md、src/game/AGENTS.md、现有测试（test_runner、character_movement_playtest、lab_playtest）与 flow-playtest-verify / godot-physics / flow-add-capability。
- 本轮状态：**历史前置验收矩阵（已执行）**。父修正已并入（D4 装配移除口径、V7 不硬性纯白为零、R5/E6 失焦保留悬停、U1 行为覆盖取代固定条数）。契约与美术资产均已冻结，`src/tests/mountain_traversal_playtest.gd` 的真实物理矩阵已跑通；最终结果、限制与五问见 `docs/playtest/2026-09-18-mountain-traversal.md`。

证据分类（最终报告按五问逐行标注）：已实现 / 已运行通过（命令+日志）/ 静态检查（只读代码或门禁，未运行）/ 未验证 / 外部阻塞。

断言纪律（不吞错）：

1. 碰撞断言必须命中**指定碰撞体本体**（比较节点路径）并断言行程被截断；只断言「发生了碰撞」视为无效断言。
2. 落点断言必须核对布局 JSON 的 landing_points 高度，误差只允许物理容差（测试顶部常量声明并给理由）。
3. Tag 断言核对 `block_count` 精确值并覆盖每条退出路径；不得只查 `is_blocked` 布尔。
4. 任何 FAIL 计数导致 `quit(1)`；禁止 catch 后继续、禁止 `or true`、禁止事后放宽阈值。
5. 返回码不作为通过证据；必须检查日志逐项 PASS/FAIL。
6. 集成测试必须使用真实场景、真实 CharacterBody3D 与真实静态碰撞体；只测 Component 常量/字段的单元断言不得替代集成。
7. 每个外部 Godot 运行加 45s 超时；原始日志写 `~/.cache/game-xiuxian-lab/`。

## 1. 契约前置（未落地即阻塞对应矩阵行）

| 编号 | 必须冻结的内容 | 来源 | 状态 |
|---|---|---|---|
| C1 | 三 Capability 类名、叶子包路径、priority 数值与调度顺序（Flight 先于 Jump、Movement） | traversal-contract.md | 已冻结 |
| C2 | 共享 Component 名与全部新增字段（单位、初始值、写入者/读取者） | traversal-contract.md + vocabulary | 已冻结 |
| C3 | 阻塞 Tag 名（普通移动/跳跃）与 instigator 语义、退场清账口径 | traversal-contract.md + src/data/vocabulary/tags/ | 已冻结 |
| C4 | 同帧 F+Space、起跳后开飞行、空中关飞行的确定结果 | traversal-contract.md | 已冻结 |
| C5 | 飞行水平/垂直速度、升降加速度、悬停条件、离地升起量、高度上限、世界边界、掉出复活 | traversal-contract.md | 已冻结 |
| C6 | 着地/离地判定口径（is_on_floor / 射线）与单帧唯一 move_and_slide 提交点 | traversal-contract.md | 已冻结 |
| C7 | mountain_realm_layout.json 字段与坐标口径：Y-up 米、spawn、bounds、landing_points（起点庭院/主峰宗门/侧峰庭院，峰顶约 12/24/36 m）、可碰撞代理与视觉网格的节点路径 | 美术 layout-contract.md | 已冻结 |
| C8 | HUD 状态字段与步行/空中/御剑文本映射 | 场景代理 + contract | 已冻结 |

（历史说明）契约冻结前，C 相关行保持阻塞状态，不据现有代码猜参验收；现已全部冻结并实施，最终结果见 `docs/playtest/2026-09-18-mountain-traversal.md`。

## 2. 门禁与静态矩阵

| ID | 验收点 | 方法 | 缺陷可暴露判据 | 状态 |
|---|---|---|---|---|
| G1 | Tier 0 全门禁 + 负向控制 | 实跑 `python3 tools/verify/run_all.py` | 全部 OK；负向控制每个非法样例被真实拒绝，数量不低于当前基线 | 见最终报告 |
| G2 | 运行时套件 | 实跑 `run_all.py --with-tests` | 已知基线 87 通过不下降；三组新配对测试在 SUITES 中且全绿；失败数必须为 0 | 见最终报告 |
| G3 | 能力目录恰有三项 | 实跑 `gen_capability_catalog.py --check` + 读 `design/capability_catalog.json` | 恰为 Movement/Jump/SwordFlight；包为 actors/swordsman、abilities/jump、abilities/sword_flight；count 与 packages 一致；无战斗能力混入 | 见最终报告 |
| G4 | 词汇登记与生成物新鲜 | 实跑 `gen_vocabulary_index.py --check`、`verify_vocabulary.py` | 全部新 Tag/字段已登记；索引与目录均新鲜；无未登记词汇字面量 | 见最终报告 |
| G5 | 组件纯度与跨能力解耦 | 实跑 `verify_component_purity.py` + 静态检查 | 组件无 `_process`/行为分支/全局写入；三能力源码互不出现对方类名，也不 `get_node` 抓对方 | 见最终报告 |
| G6 | 场景引用完整性 | 实跑 `verify_scenes.py`、`verify_notes_format.py` | mountain_realm.tscn 无悬空 ext_resource；note 状态与 experiments.json 入口自洽 | 见最终报告 |
| G7 | 目录与旧场景回归 | 实跑 lab_playtest.gd 与更新后的 character_movement_playtest.gd | hub 仍 8 模块、空白台/滚轮/R/Esc 不变；character_movement 入口指向 mountain_realm 且可启动；movement_garden 仍可加载 | 见最终报告 |

## 3. 单元测试矩阵（仍必须实跑，但不作为集成替代）

| ID | 验收点 | 判据 | 状态 |
|---|---|---|---|
| U1 | test_swordsman_movement.gd | 允许因 actor 职责改变更新断言载体（不再以固定「17 条」数量绑架实现）；**行为覆盖不减**：移动方向、斜向限速、停止、输入映射与意图写入约束仍逐项断言 | 见最终报告 |
| U2 | test_jump.gd | 按下边沿才起跳；按住不连跳；空中不起跳；失活清冲量；失活清账 | 见最终报告 |
| U3 | test_sword_flight.gd | F 切换状态；升降输入；无输入悬停；阻塞 add/remove 带 instigator；deactivate 与 exit_tree 都清账；priority 顺序正确 | 见最终报告 |

## 4. 真实物理集成矩阵（src/tests/mountain_traversal_playtest.gd，无头）

| ID | 验收点 | 缺陷可暴露判据 | 状态 |
|---|---|---|---|
| P1 | 场景装配 | mountain_realm.tscn 加载成功；角色 3 个能力齐备且无战斗语义节点；布局加载；Blender 网格数量 > 阈值 | 见最终报告 |
| P2 | 屏幕相对移动与键位等价 | WASD 与方向键分别实按产生对应方向的真实世界位移；松键停止（速度 ≈ 0） | 见最终报告 |
| P3 | 斜向限速 | W+D 同按水平速度 ≤ move_speed 且 > 0.9×move_speed（证明真在动，只是未超速） | 见最终报告 |
| P4 | 地面起跳与落地 | 空格边沿 → velocity.y > 0 且离地；重力关回；N 帧内 is_on_floor 且世界 y 回到地面高度（容差内） | 见最终报告 |
| P5 | 按住不连跳 | 按住空格跨越一次完整起落后，起跳次数恰为 1（按 y 轨迹/离地事件计数） | 见最终报告 |
| P6 | 空中不重复起跳 | 空中再按空格，竖直速度无新增冲量、最高点不高于单跳预期 | 见最终报告 |
| P7 | 低台阶真实站立 | 跳上布局中的低台阶后静止若干帧，y 稳定在台阶顶面 | 见最终报告 |
| P8 | 飞行开关与恢复重力 | F 开启 → 离地升起；F 关闭 → 重力恢复、y 下降、可在平台落地；状态字段同步 | 见最终报告 |
| P9 | 升降与悬停 | Space 连续上升、Ctrl 连续下降；松键 N 帧内竖直位移 ≤ 容差且 velocity.y ≈ 0 | 见最终报告 |
| P10 | 飞行快于步行 | 同帧数飞行水平位移显著大于步行，且不超过契约上限（防穿模） | 见最终报告 |
| P11 | 撞山 | 从已知安全点向指定山体代理真实移动/扫掠：命中体必须等于该山体碰撞体路径，行程被截断，y 不穿透 | 见最终报告 |
| P12 | 撞楼 | 同上，针对宗门建筑碰撞体本体；不得被背后山体或边界兜底顶替 | 见最终报告 |
| P13 | 两处不同高度平台降落 | 飞往主峰/侧峰两个 landing_point，分别在各自 y 高度真实落地并静止；两点高度差与 layout 一致 | 见最终报告 |
| P14 | 边界与高度上限 | 向界外飞：世界边界生效且不越界；超过高度上限时被约束；镜头不脱离场景 | 见最终报告 |
| P15 | 掉出探索区复活 | 掉出后自动回到 spawn，速度清零、状态一致 | 见最终报告 |
| P16 | 单物理提交点 | 自由落体竖直加速度等于契约重力（排除双重重力）；能力源码中无自身 move_and_slide（静态+运行时双向核对） | 见最终报告 |

## 5. 互斥、边界与清账矩阵

| ID | 验收点 | 缺陷可暴露判据 | 状态 |
|---|---|---|---|
| E1 | 同帧 F+Space | 行为与契约 C4 完全一致；只有一次竖直效应；状态字段与标签一致 | 见最终报告 |
| E2 | 起跳后开飞行 | 飞行接管竖直与水平；无跳冲量叠加造成的异常跃升 | 见最终报告 |
| E3 | 空中关飞行 | 重力立即恢复；无残余悬停；可正常落地 | 见最终报告 |
| E4 | 飞行阻塞移动/跳跃 | 飞行中跳跃不激活、水平速度不被地面移动逻辑改写；关飞行后两者恢复 | 见最终报告 |
| E5 | Tag 清账 | 关闭飞行、能力移除、R 重置、Esc 切场景、能力 exit_tree 后，每个相关 Tag 的 block_count 均为 0；instigator 无残留；用例间 `TagRegistry.clear_all()` | 见最终报告 |
| E6 | 失焦悬停 | 御剑中失焦：四类输入被清、水平停止，但 `flight_active=true`、竖直速度 ≈ 0、高度稳定；R 才关闭飞行并清账 | 见最终报告 |

## 6. 拆装矩阵（从装配移除，不删包）

拆装口径（修正）：从**角色装配**里移除对应 Capability 节点 / 资源引用后其余仍工作。不物理删除共享工作区中的包目录、不制造「未编辑的 .tscn 引用已删文件却要求继续加载」的负向实验。

| ID | 操作 | 判据 | 状态 |
|---|---|---|---|
| D1 | 装配中移除 Jump 节点 | 真实场景中 Movement + Flight 仍完整工作；空格不再起跳；无残留 Tag；场景本身可加载 | 见最终报告 |
| D2 | 装配中移除 Flight 节点 | Movement + Jump 仍完整工作；F 无效果；`flight_active=false` 且 `sword_flight_block` 清账；场景本身可加载 | 见最终报告 |
| D3 | 装配中移除 Movement 节点 | Jump + Flight 仍工作（飞行自带水平位移，可移动与降落） | 见最终报告 |
| D4 | 静态解耦（不删包） | 静态检查：各能力源码互不引用对方类名；被移除能力不留下全局状态；`verify-packages` 在现有包结构上通过。不要求删除包目录后未编辑场景仍能加载 | 见最终报告 |

## 7. 重置、退出与恢复矩阵

| ID | 验收点 | 判据 | 状态 |
|---|---|---|---|
| R1 | R 重置 | 位置回 spawn、速度清零、飞行关闭、Tag 清账、相机复位、HUD 状态回步行 | 见最终报告 |
| R2 | Esc 返回 hub | 进入 LabHub；共享根视口 msaa 恢复进入前值；hub 模块状态不伪造 | 见最终报告 |
| R3 | 旧庭院恢复 | movement_garden.tscn 可加载；旧测试仅更新入口指针断言，其余物理断言不减 | 见最终报告 |
| R4 | hub/空白台回归 | lab_playtest 全 PASS（8 模块、剑法无入口、滚轮缩放、R、Esc） | 见最终报告 |
| R5 | 失焦（修正） | 失焦清除四类输入（水平/升降/跳跃边沿/切飞边沿）并停止水平漂移；**已开启的御剑保留悬停，不自动关飞、不突然坠落**；只有 R 关闭飞行并清账。判据：失焦后 `flight_active` 仍为 true、竖直速度 ≈ 0、y 稳定 | 见最终报告 |
| R6 | 场景切换静态状态 | 切换后 TagRegistry 等静态设施无跨场景残留 | 见最终报告 |

## 8. 视觉与截图矩阵（窗口模式，必须真实经过输入飞行）

硬规则：截图对应的运行里，飞行状态必须由 `Input.parse_input_event`（F / Space / WASD）真实触发，捕获前脚本打印状态快照（is_flying、y、ground_y、最近输入帧、velocity）。禁止直接设 `global_position` / 状态字段后截图；禁止只摆角色假称飞行通过。违反即 FAIL 并记为缺陷。

| ID | 验收点 | 判据 | 状态 |
|---|---|---|---|
| V1 | 输入飞行取证 | 飞行截图时 is_flying == true 且 y - ground_y ≥ 契约最小离地高度；输入历史连续；非传送 | 见最终报告 |
| V2 | 群山全貌 | 含群山轮廓与纵深、远山/云雾；不过曝 | 见最终报告 |
| V3 | 地面宗门庭院 | 山门/主殿/青瓦/廊道台阶/石栏/松竹可辨 | 见最终报告 |
| V4 | 空中御剑 | 足下剑可辨认；HUD 显示御剑状态；角色不在画面外 | 见最终报告 |
| V5 | 另一山顶降落 | 真实飞行后落在非起点平台，截图与落点高度可核对 | 见最终报告 |
| V6 | 两窗口尺寸 | 1280x800 与 960x640（项目固定 16:10 视口）HUD 可读、不遮主要区域 | 见最终报告 |
| V7 | 曝光与画面审计（修正） | **不硬要求纯白像素为 0**：云雾与高光允许纯白。判据：非高光地表/角色区域可辨、无大片细节丢失、无整体过曝或死黑；像素统计仅作辅助记录，最终以人工检查截图为准 | 见最终报告 |
| V8 | 手感/审美 | 标注「需使用者试玩」，不由自动化下结论 | 见最终报告 |

## 9. 交付物与命令（本代理独占）

产出：

- src/tests/mountain_traversal_playtest.gd（新建，含无头物理与窗口截图两种模式）
- src/tests/character_movement_playtest.gd（仅必要更新：入口指针断言等，不减旧断言）
- docs/playtest/2026-09-18-mountain-traversal.md（五问报告）
- docs/playtest/2026-09-18-mountain-traversal-*.png（全貌/庭院/飞行/山顶/小窗）

命令模板（每条 ≤45s 超时，日志落 ~/.cache/game-xiuxian-lab/）：

- `/Applications/Godot.app/Contents/MacOS/Godot --headless --path src tests/test_runner.tscn`
- `/Applications/Godot.app/Contents/MacOS/Godot --headless --path src --script res://tests/mountain_traversal_playtest.gd`
- `/Applications/Godot.app/Contents/MacOS/Godot --path src --script res://tests/mountain_traversal_playtest.gd -- --capture-prefix=<abs>`
- `python3 tools/verify/run_all.py --with-tests`
- `git diff --check`（只读，不 commit/push）

## 10. 五问报告模板（docs/playtest/2026-09-18-mountain-traversal.md）

| 矩阵 ID | 1 已实现 | 2 已运行通过（命令+日志） | 3 静态检查 | 4 未验证 | 5 外部阻塞 |
|---|---|---|---|---|---|
| G1 |  |  |  |  |  |
| … |  |  |  |  |  |

规则：每行只有一个主状态，交叉证据写备注；未跑但读了代码写「静态检查」；无证据写「未验证」；环境/依赖缺失写「外部阻塞」；返回码不替代日志检查。报告末尾给未通过项归属层（机制实现 / 数值 / 表现 / 疑似引擎）与已知限制。

## 11. 下一步（已进入）

1. ~~等待契约~~ 已审计/已交付：`traversal-contract.md`（父审计通过）+ `layout-contract.md`（父已给四点修正：主殿分墙盒不得整盒堵空腔、节点名 PascalCase、jump_step 0.55 m 高、场景四墙+天花限制 bounds、fall_y 才回收）。
2. 正在写 `src/tests/mountain_traversal_playtest.gd`：无头物理矩阵（P/E/D/R 可运行子集）+ 窗口截图模式（V）；旧 `character_movement_playtest.gd` 仅做入口指针必要适配。
3. 等能力代理释放 Godot 且美术 GLB/场景就绪：统一 import → Tier 0 → 运行时单测 → 真实物理（可分批 ≤45s）→ 窗口截图 → 五问报告 `docs/playtest/2026-09-18-mountain-traversal.md`。
4. 任何真实缺陷报对应 owner 并抄父；父只审计日志/源码/图片。
