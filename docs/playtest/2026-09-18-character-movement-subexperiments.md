# 角色移动子实验套件 · 集成权威报告（2026-09-18）

场景：`res://levels/experiments/character_movement/movement_lab_hub.tscn`（角色移动顶层入口 → 子实验目录）。
决策依据：[character-movement-subexperiments](../../notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md)（**implemented**）。
数据真相源：`res://data/content/character_movement_subexperiments.json`（七项全部 `exploring` + 真实场景，计数 **7 / 7**）。
验收档位：**CLI 档**（`godot --headless` + 真实场景树 + 真实键盘事件 + 窗口模式截图）。
编辑器桥状态：godot-ai MCP 在本会话多次查询均为 `PLUGIN_DISCONNECTED / sessions count=0`，全部证据来自 CLI；MCP 不是本改动依赖。

> **本文件是角色移动子实验的权威报告。** 七个子实验各自的报告保留其落地阶段的实测数字与结论，属**阶段快照**；
> 与本文件的计数不一致时，以本文件为准。本文件的数值全部来自集成提交状态下的重新运行，不复制旧阶段计数。

## 范围（集成收口）

把七个叶子场景统一进一个可导航的子实验目录：数据清单七项全部登记为可运行；hub 只读数据、不硬编码入口；
七个场景统一返回子实验目录、再由目录返回顶层；note 迁移 implemented；文档与报告更新为 7/7。

七个场景与本轮之前相比新增可进入的三项：**地形接触训练场**、**御剑飞行训练场**、**状态切换压力场**。

## 七项子实验（全部可运行）

| # | 子实验 | 场景 | 定位 |
|---|---|---|---|
| 01 | 镜头实验室 | `camera_lab.tscn` | 灰盒对比场 |
| 02 | 人物动作工作台 | `motion_stage.tscn` | 空白动作棚 |
| 03 | 地形接触训练场 | `ground_contact_course.tscn` | 物理训练场 |
| 04 | 御剑飞行训练场 | `sword_flight_course.tscn` | 立体路线场 |
| 05 | 状态切换压力场 | `state_transition_lab.tscn` | 可视化压力场 |
| 06 | 移动庭院 | `movement_garden.tscn` | 已有基线 |
| 07 | 群山宗门 | `mountain_realm.tscn` | 已有综合场景 |

## 精确计数（本次集成运行）

| 检查 | 命令 | 结果 | stderr |
|---|---|---|---|
| Tier 0 门禁 + 负向控制 + 单元套件 | `python3 tools/verify/run_all.py --with-tests` | 12 项门禁全通过；负向控制 27/27；单元 **260 通过 / 0 失败** | 0 |
| 子实验目录 | `--script res://tests/movement_hub_playtest.gd` | **121 PASS / 0 FAIL** | 0 |
| 顶层目录 | `--script res://tests/lab_playtest.gd` | 13 PASS / 0 FAIL | 0 |
| 镜头实验室 | `--script res://tests/camera_lab_playtest.gd` | 101 PASS / 0 FAIL | 0 |
| 人物动作工作台 | `--script res://tests/motion_stage_playtest.gd` | 154 PASS / 0 FAIL | 0 |
| 地形接触训练场 | `--script res://tests/ground_contact_course_playtest.gd` | 178 PASS / 0 FAIL | 5 行（预期 warning，见下） |
| 御剑飞行训练场 | `--script res://tests/sword_flight_course_playtest.gd` | 109 PASS / 0 FAIL | 5 行（预期 warning，见下） |
| 状态切换压力场 | `--script res://tests/state_transition_lab_playtest.gd` | 133 PASS / 0 FAIL | 0 |
| 移动庭院（回归） | `--script res://tests/character_movement_playtest.gd` | 39 PASS / 0 FAIL | 0 |
| 群山宗门（回归） | `--script res://tests/mountain_traversal_playtest.gd` | 220 PASS / 0 FAIL | 5 行（预期 warning，见下） |
| 九个运行验收合计 | 上列九项 | **1068 PASS / 0 FAIL** | — |
| diff 卫生 | `git diff --check` | clean | — |

**三个 standalone playtest 未注册进 `test_runner.gd`**：它们是 `SceneTree` 运行验收脚本（真实窗口 / 真实输入 / 场景切换），
不是零依赖的 `static run(t)` 单元套件；按仓库既有惯例独立运行，命令见上表。

### 预期 warning（逐项记录）

| 场景 | warning | 为何是预期 |
|---|---|---|
| 地形接触训练场 | `角色掉出训练场（y=-5.02），回收至 spawn` | 掉出回收用例主动把角色放到下沿之外，验证回收路径 |
| 御剑飞行训练场 | `角色掉出航路（y=-15.00 < -12.00），回收至起飞坪（第 1 次）` | 同上，验证航路低落点回收 |
| 群山宗门 | `角色掉出探索区（y=-10.00），回收至 spawn` | 同上，验证 bounds 下沿回收 |

除这三处主动触发的回收 warning 外，其余六个 standalone 与整套门禁的 stderr 均为 0 行。

## hub 导航与返回链（逐项实测）

`movement_hub_playtest.gd` 对七项逐条真实进入并返回，全部 PASS：

```
计数如实显示已落地 7 / 7：7 / 7
进入子场景：camera_lab → CameraLab            Esc 返回 MovementLabHub
进入子场景：motion_stage → MotionStage        Esc 返回 MovementLabHub
进入子场景：ground_contact_course → GroundContactCourse   Esc 返回 MovementLabHub
进入子场景：sword_flight_course → SwordFlightCourse       Esc 返回 MovementLabHub
进入子场景：state_transition_lab → StateTransitionLab     Esc 返回 MovementLabHub
进入子场景：movement_garden → MovementGarden  Esc 返回 MovementLabHub
进入子场景：mountain_realm → MountainRealm    Esc 返回 MovementLabHub
```

返回路径契约：

- 顶层 `LabHub` →「角色移动」→ `MovementLabHub` → 七个子场景之一。
- 任一子场景 Esc / 返回按钮 → `MovementLabHub`（按钮与提示文案均为「返回子实验目录」，运行断言读回文本防漂移）。
- `MovementLabHub` Esc / 返回按钮 → 顶层 `LabHub`。
- 每个场景都可直接启动；直接启动后的第一跳仍回到子实验目录，返回链不依赖从顶层进入。

## 结构检查

| 检查 | 结果 |
|---|---|
| 目录清单 | 7 / 7 可进入（`status != planned` 且场景文件真实存在） |
| 三项 Capability | 恰为 `SwordsmanMovement` / `Jump` / `SwordFlight`，未新增第四项 |
| 唯一物理提交点 | `swordsman.gd` 一处 `move_and_slide`；三个能力与七个场景脚本均为 0 处 |
| Capability 解耦 | 每个能力只出现自身类名，无跨能力引用 |
| 共享输入 helper | `MovementLabInput` 由 **5 个生产场景**消费并实例化：`camera_lab` / `motion_stage` / `ground_contact_course` / `sword_flight_course` / `state_transition_lab`；**1 个单元套件** `test_movement_lab_input.gd` 直接实例化它做契约测试；`ground_contact_course` / `sword_flight_course` / `state_transition_lab` 三个 playtest 只对**场景源码做静态扫描**（断言使用关系），不实例化该 helper |
| hub 数据来源 | hub 只读清单、按 `status` + 场景可加载性推导入口，无硬编码路径 |
| 场景返回契约 | 七个场景脚本均声明返回 `movement_lab_hub.tscn` |

## 截图（窗口模式，真实输入驱动）

**本阶段新拍（`7of7-` 前缀，10 张入仓）**：

| 截图（实际像素） | 取证方式 | 内容 |
|---|---|---|
| `...-7of7-movement-hub-1280x800.png`（1280×800） | 真实窗口 | 七项、计数 **7 / 7**、镜头实验室选中 |
| `...-7of7-movement-hub-960x600.png`（960×600） | 真实窗口（早于 `CAPTURE` 尺寸打印的一批，无 CAPTURE 行；尺寸由 PNG IHDR 与内容独立核验） | 小窗真实重排：七项完整可见，群山宗门选中 |
| `...-7of7-movement-hub-960x640.png`（960×640） | 离屏精确渲染（保存前有 `CAPTURE` 尺寸打印与断言） | 960×640 像素下的目录：清单与 7 / 7 计数，第 07 项在滚动区下方 |
| `...-7of7-movement-hub-entry-ground_contact_course.png`（1280×800） | 真实窗口 | 从 hub 真实进入**地形接触训练场**（新入口） |
| `...-7of7-movement-hub-entry-sword_flight_course.png`（1280×800） | 真实窗口 | 从 hub 真实进入**御剑飞行训练场**（新入口） |
| `...-7of7-movement-hub-entry-state_transition_lab.png`（1280×800） | 真实窗口 | 从 hub 真实进入**状态切换压力场**（新入口） |
| `...-7of7-movement-hub-entry-camera_lab.png`（1280×800） | 真实窗口 | 从 hub 真实进入镜头实验室 |
| `...-7of7-movement-hub-entry-motion_stage.png`（1280×800） | 真实窗口 | 从 hub 真实进入人物动作工作台 |
| `...-7of7-movement-hub-entry-movement_garden.png`（1280×800） | 真实窗口 | 从 hub 真实进入移动庭院 |
| `...-7of7-movement-hub-entry-mountain_realm.png`（1280×800） | 真实窗口 | 从 hub 真实进入群山宗门 |

**尺寸与取证方式说明（如实记录）**：本机窗口管理器对内容尺寸有下限（实测约 1200×750），真实窗口无法压到
960×640；因此 960×640 那张由 **离屏视口精确渲染**取得（真实实例化同一 `movement_lab_hub.tscn` 并渲染），
文件名与实际像素严格一致，脚本保存前有 `CAPTURE … actual=960x640` 打印与 `离屏截图尺寸与命名一致` 断言。

`7of7-960x600.png` 的取证链与前者不同，如实说明：它出自**早于 `CAPTURE` 打印功能的真实窗口批次**，
其日志中**没有** `CAPTURE` 尺寸行，因此不声称有打印尺寸自证；尺寸 960×600 由 **PNG 头（IHDR）与图像内容
独立核验**（`file` 读数为 `PNG image data, 960 x 600`），本报告据此标注。

它是本阶段**另拍的独立新图**，与旧 4 / 7 的 `...-movement-hub-960x640.png` 是不同文件、字节不同
（sha256 分别为 `190b1c93…` 与 `b0359f0c…`），**并非改名而来**。

旧 4 / 7 的 `...-movement-hub-960x640.png` **命名与实际像素不符**（文件名为 960x640，实测内容 960×600）：
该图按**原路径、原文件名原样保留**，本阶段未移动、未改名、未删除、未覆盖任何旧图；
正确尺寸的记录以本报告为准。

人工读图确认：1280×800 与 960×600 下七个条目完整显示（无裁切、无重叠），计数区显示 `7 / 7`，
七个条目状态全部为「探索中」，详情面板显示真实入口路径与可用的「进入子实验」按钮；
离屏 960×640 图显示同一目录在更矮画布下的清单与 `7 / 7` 计数，第 07 项位于滚动区内需滚动查看
（`ScrollContainer` 的真实行为，非缺项）。

**旧 4 / 7 截图属探索资产，全部保留、未被覆盖**：`...-movement-hub-1280x800.png` 等 6 张仍在仓中；
新图通过 `--capture-tag=7of7` 加前缀避免重名。

子实验各自的截图（镜头 9 张、动作 7 张、地形 7 张、飞行、状态 11 张等）同样保留在各阶段报告中。

## 已知边界

- **玩法细节不在本报告范围**：集成只确认七项可进入、返回链正确、清单与文档一致；各场景的镜头策略、
  动作表现、接触判据、飞行路线与清账细节由各自报告负责，本报告只引用其运行结论。
- **审美与手感待人工评价**：七个场景的观感、节奏与手感均需使用者试玩判断，自动检查不替代审美。
- **子报告为阶段快照**：各子实验报告记录的是其落地时的数字；本报告为集成快照，冲突时以本报告为准。
- **旧场景返回路径已统一**：移动庭院与群山宗门的返回目标由顶层目录改为子实验目录（它们的第一跳返回变了）。
- **已提交**：本文件的集成改动已随最终集成轮的本地提交保存（此前各子实验的落地改动亦已随本地提交保存）；未 push。
