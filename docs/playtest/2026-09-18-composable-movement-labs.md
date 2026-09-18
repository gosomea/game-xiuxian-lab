# 可组合移动实验 · 最终报告（2026-09-18）

场景根：`res://levels/experiments/character_movement/movement_lab_hub.tscn`（角色移动子实验目录），
顶层入口 `res://levels/lab_hub.tscn`。
决策依据：[character-movement-composable-labs](../../notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md)、
装配与镜头契约 [composable-lab-assembly-contract](../../notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md)。

> **本文件是 S0–S3 的集成报告。** 七场启动/返回、四场飞剑证据与全场回归均已在第七节填入实测结果；
> 各专项报告只证明其自身范围。全场已无 `SCRIPT ERROR`。
> **未达口径如实列出**：§4 的「1:1 画布布局压力」与「生产 stretch」是两种口径；生产配置下全部场景常显 UI
> 覆盖率 ≤15%（最接近的是 motion_stage 预览态 14.93%），而 1:1 口径下窄屏曾超限，两者不互相替代。

## 1. 版本界限（必须与本报告一起读）

| 项 | 界限 |
|---|---|
| 决策基线 | `b45e453`（`Approve composable movement lab implementation notes`，文档先于 runtime） |
| 本报告记录范围 | S0 装配适配器与飞剑包、S1 镜头包、S2 程序动作预览 P0、两级导航与共享 HUD |
| 未包含 | 骨骼 clip 库 / 蒙皮（P1/P2）、骨骼重映射（retarget）、镜头遮挡规避与推近、手柄与键位重映射 |
| 集成状态 | **已完成**：七场迁移、四场飞剑视觉取证、全场回归与生产 UI 复核均已实测（§2、§7），全场 `SCRIPT ERROR = 0` |
| 历史对照 | `docs/playtest/2026-09-18-character-movement-subexperiments.md` 是上一阶段（七场各自落地/集成）快照，已标注为**历史**并链接本文件；其计数按历史口径保留 |

## 2. 主测试入口实测（`tests/test_runner.tscn`，主场景模式）

命令：`Godot --headless --path src tests/test_runner.tscn`

| 组合 | 套件数 | 通过 | 失败 |
|---|---|---|---|
| 旧基线（本轮之前） | 11 | 395 | 0 |
| 新增：ActorAssembly + FlightBundle | 2 | **225**（142 + 83，含 freed-instance 生命周期回归 16 项） | 0 |
| 新增：camera_rig（fixed_follow / quarter_turn / orbit / overview / executor） | 5 | **128** | 0 |
| 新增：motion_preview | 1 | **123**（107 + 16 动态 duration） | 0 |
| 新增：lab 导航 | 1 | **50** | 0 |
| **合计（主入口实测）** | **20** | **921** | **0** |

- 实测输出末行：`测试合计：通过 921，失败 0`（exit 0）。
- **`await suite.run(context)` 是必需的**：`test_actor_assembly.gd` 的 `run()` 是协程（内含真实物理帧推进）。
  反证实测（当轮版本）：同一套件不 `await` 时只统计到 **26/0** 并报「0 失败」（假绿），正确 `await` 后为 **126/0**；
  该套件其后又补断言，**现为 142/0**（见上表），反证结论不变。
  该改动与结论记于 `src/tests/test_runner.gd` 头注释。
- camera_rig 另有包内入口 `res://game/systems/camera_rig/test_camera_rig_runner.tscn`，实测 **128 / 0**，与主入口一致；
  `docs/playtest/2026-09-18-camera-rig.md` 当前记录同为 **128 / 0**（fixed_follow 25、quarter_turn 13、orbit 25、overview 14、executor 51）。

## 3. 专项报告与证据链接（各自范围，不互替）

| 主题 | 报告 | 覆盖范围 |
|---|---|---|
| 装配适配器（四子集 / 生命周期 / 回滚） | [actor-assembly-audit.md](2026-09-18-actor-assembly-audit.md) | 只读交叉审计：四子集真实行为、owner/borrow 卸载、失败事务性、唯一 manager/component/物理提交；**实锤 0 项** |
| 镜头包与两个消费者 | [2026-09-18-camera-rig.md](2026-09-18-camera-rig.md) | 四模式 + 参数预设、唯一提交器、输入分相与捕获生命周期、两场景接入 |
| 程序动作预览 P0 | [2026-09-18-motion-preview.md](2026-09-18-motion-preview.md) | 动作注册表 / 局部时钟 / 播放控件 / 共享 Visual 同源；HUD 遮盖实测（见第 4 节口径） |
| 移动庭院地表间距（历史轮） | [2026-09-18-movement-garden-surface-clearance.md](2026-09-18-movement-garden-surface-clearance.md) | 庭院资产几何与共面修复，非本决策范围 |
| 七场上一阶段集成快照 | [2026-09-18-character-movement-subexperiments.md](2026-09-18-character-movement-subexperiments.md) | 上一阶段的七场集成范围与导航/截图契约；其计数为历史口径，**本轮不复述，以本报告第 2 节实测为准** |

## 4. UI 证据的两类口径（不做等价替换）

本轮的 `960×640 / 1280×720 / 1920×1080` 版面读数来自**1:1 画布布局压力**，与生产 stretch 不是同一件事：

| 口径 | 机制 | 证明了什么 |
|---|---|---|
| **1:1 画布布局压力**（已有证据） | camera：`--ui-size=WxH` → `content_scale_size = ZERO` + `CONTENT_SCALE_MODE_DISABLED`（1 单位 = 1 像素）；motion：`--canvas=WxH` → `content_scale_size = WxH` 且 `root.size = WxH` | 在这些**精确画布尺寸**下 HUD 矩形不越界、面板不溢出、不遮角色屏幕点；这是布局下界压力，不是玩家默认所见 |
| **生产 stretch 三档**（已完成） | `project.godot`：`window/stretch/mode="canvas_items"`、设计分辨率 1280×800；逻辑画布恒为 1280×800、随窗口等比缩放。实测见 [生产 UI 复核](2026-09-18-production-ui.md) | 默认玩家路径下的真实观感与遮盖率（七场全部 ≤15%） |

- **生产配置最终实测**（[生产 UI 真实配置复核](2026-09-18-production-ui.md)，`--no-capture` **325 / 0**、capture **347 / 0**）：
  逻辑画布恒为 1280×800、随窗口等比缩放，七场常显 UI 覆盖率**全部 ≤15%**——
  motion_stage 预览态 14.93%（最接近上限）、state_transition_lab 13.24%、camera_lab 7.04%、motion_stage 实时 5.80%
  （movement_garden 5.29%、sword_flight_course 4.88%、ground_contact_course 4.50%、mountain_realm 4.42%）。
  生产配置截图 **22（v1）+ 22（v2）= 44 张**全部在库；22/22 配对 SHA-256 逐字节相同，v2 仅作可复现性证据，
  版面结论一律以 v1 为准（见 [生产 UI 复核](2026-09-18-production-ui.md)）。
- **1:1 画布布局压力口径**（camera 的 `--ui-size` / motion 的 `--canvas`，非玩家默认路径）：动作工作台窄屏
  960×640 = 24.9%、1280×720 = 16.6%、1920×1080 = 7.4%（含可见 `PreviewPanel`）。
  该口径下窄屏超过 15%，说明「≤15%」在极限画布下会失守；两套口径分别记录、**不互相替代**。
- **不得用改 `project.godot` 迎合测试**：本轮未改 stretch 设置。

## 5. 关键实现结论（已由测试覆盖）

- **装配**：能力由 `ActorAssembly` 按显式 `ActorAssemblyConfig` 注册为宿主唯一 `CapabilityManager` 的直系子；
  四真实子集（Move / Move+Jump / Move+Flight / all）有真实物理行为断言（能做什么 / 不能做什么），
  不只是节点名。卸载不调用 `reset_motion()`，不碰借用组件的输入与速度。
- **飞剑**：`FlightBundle` 把行为与 `flying_sword.glb` 视觉作为一个包安装/卸载；安装前全量预检、
  失败只回滚本次新增；同名外部资源拒绝认领。
- **镜头**：`CameraRig` 根节点是唯一写 `Camera3D` 的提交器（位置 / look_at / projection / size / near / far），
  四模式只写 `CameraRigComponent` 期望位姿；`mode_id` 互斥，切换混合起点取上一帧真实提交状态。
- **物理提交**：全仓仍仅 `swordsman.gd` 一次 `move_and_slide()`；本轮未改 `core/`。
- **catalog tag**：`sword_flight.gd` 的 `TagRegistry` 调用改用字面量 `&"sword_flight_block"`，
  使现有字面量提取可识别（`SwordFlight.uses_tags=["sword_flight_block"]`）；**未改 `tools/gen/`**。

## 6. 已知限制与未做项

- **骨骼化未做（P1/P2）**：`cultivator.glb` 实测 0 skin / 0 animation；动作是程序近似，脚掌无 IK，
  真足滑指标「待建立」。骨骼重映射（retarget）未实现。
- **遮挡只观测不规避**：`is_occluded()` 是只读射线读数；无自动推近 / 抬升 / 半透明化。
- **HUD 遮盖**：**生产 stretch 口径下七场全部 ≤15%**（最接近的是 motion_stage 预览态 14.93%）；
  仅 **1:1 画布布局压力口径**下动作工作台窄屏 960×640 = 24.9%、1280×720 = 16.6% 超过 15% 试验目标（§4）。
- **手感类**（跟随舒适度、orbit 环绕、overview 回中）需人工试玩，自动化只覆盖可观察量。
- **「能挂」的边界**：新场景仍需自己的输入编排（按键 → `set_move_input` / `press_flight_toggle` 等公开 API）
  与一次 `rig.bind(camera, target, config)`；不复制跟随行为与绑剑逻辑是硬要求，但不是「零场景代码」。

## 7. 集成验收汇总

> 七场迁移、四场飞剑取证、全场回归与生产 UI 口径均已实测；下表为逐项索引，全部已完成。

| # | 验收项 | 证据口径 | 状态 |
|---|---|---|---|
| 1 | 七场启动与返回链 | 逐场启动、Esc / 返回按钮回到子实验目录、再回顶层；如实记录任何失败 | ✅ 已填（见 §7.1） |
| 2 | 四场飞剑可见 | motion_stage / sword_flight_course / state_transition_lab / mountain_realm 各一张飞行中截图 + 正式 actor 的 mesh 断言 | ✅ 已填（§7.2） |
| 3 | 全场回归 | 迁移后完整运行验收（各 playtest）与主入口 `test_runner.tscn` 的最终计数 | ✅ 已填（见 §7.3） |
| 4 | 生产 stretch 三档 UI | `canvas_items` 生产设置下三档实拍与遮盖率：七场全部 ≤15%（§4；[生产 UI 复核](2026-09-18-production-ui.md) 325 / 0） | ✅ 已填（§4） |
| 5 | 历史文档指向 | `2026-09-18-character-movement-subexperiments.md` 已标注为历史快照并链接本文件 | ✅ 已填 |
| 6 | `AGENTS.md` / `README.md` | 已更新为当前实现（2 击导航、共享 CameraRig / LabHud、动作仍是程序近似）；`experiments.json` 的 exploring 状态**不变**，不扩玩法 | ✅ 已填 |

### 7.1 七场启动与返回链（集成者实测）

命令（逐场真实启动 + Esc 返回，真实场景树）：

```
Godot --headless --path src --script res://tests/camera_lab_playtest.gd
Godot --headless --path src --script res://tests/motion_stage_playtest.gd
Godot --headless --path src --script res://tests/ground_contact_course_playtest.gd
Godot --headless --path src --script res://tests/sword_flight_course_playtest.gd
Godot --headless --path src --script res://tests/state_transition_lab_playtest.gd
Godot --headless --path src --script res://tests/character_movement_playtest.gd      # 移动庭院回归
Godot --headless --path src --script res://tests/mountain_traversal_playtest.gd
Godot --headless --path src --script res://tests/movement_hub_playtest.gd            # 子实验目录
Godot --headless --path src --script res://tests/lab_playtest.gd                     # 顶层目录
```

| 场景 | 通过 | 失败 | 返回链 |
|---|---|---|---|
| 镜头实验室 | 113 | 0 | Esc → 子实验目录（playtest 内断言） |
| 人物动作工作台 | 372 | 0 | 同上 |
| 地形接触训练场 | 189 | 0 | 同上 |
| 御剑飞行训练场 | 117 | 0 | 同上 |
| 状态切换压力场 | 156 | 0 | 同上 |
| 移动庭院（回归） | 52 | 0 | 同上 |
| 群山宗门（回归） | 227 | 0 | 同上（`_batch_hub` 覆盖 Esc 两级返回） |
| 子实验目录 | 86 | 0 | 七项逐次进入并 Esc 返回；返回记忆选中项与真实滚动位置 |
| 顶层目录 | 22 | 0 | 模块卡一次点击直达子目录；返回恢复上次选中 |
| **合计** | **1334** | **0** | — |

**退出期 SCRIPT ERROR（已修复）**：群山宗门 playtest 的 `_batch_hub` 段（移除 / 重装 SwordFlight 能力用例）曾打印
`SCRIPT ERROR: Invalid type in function '_remove_node' in base 'Node (ActorAssembly)'`——对已释放的节点句柄调用
**typed 参数会在函数体守卫之前就被类型校验拒绝**。修复：`ActorAssembly` 在 `uninstall` / `_exit_tree` / `_rollback`
的 typed 调用前统一 `_prune_owned()`，并新增 freed-instance 生命周期回归 16 项。
复跑 `Godot --headless --path src --script res://tests/mountain_traversal_playtest.gd` → **227 / 0，SCRIPT ERROR = 0**。

### 7.2 四场飞剑可见（定性证据 + mesh 断言）

| 场景 | 行为断言 | 截图（`docs/playtest/`） |
|---|---|---|
| 御剑飞行训练场 | 真实 F 御剑后 `Visual/FlyingSword` 可见且含 MeshInstance3D；高空 y=30 仍御剑不掉落、角色在视口内 | `2026-09-18-composable-labs-sword-flight-1152x720.png`（1152×720） |
| 状态切换压力场 | 正式 actor：`flight_visual_node()` 绑定 `Visual/FlyingSword`、`flight_active` 为真、`visible` 为真；实测高度 5.18 m、HUD 显示「御剑 是」 | `motion-preview-state-real-actor-flight.png`（1280×720） |
| 群山宗门 | 真实 F 御剑后剑节点可见；高空 y=42 峰顶仍御剑不掉落、角色在视口内 | `2026-09-18-composable-labs-mountain-1152x720.png`（1152×720） |
| 人物动作工作台 | 正式 actor：`flight_visual_node()` 绑定 `Visual/FlyingSword`、`flight_active` 为真、`visible` 为真、10 meshes / 486 tri（非预览实例） | `motion-preview-real-actor-flight.png`（1280×720） |

- 剑的**脚下位置 / 朝向 / 帧内可见尺寸**以父级人工图审 + 上表 mesh 断言**定性**记录，不做像素级数值测量。
- 截图实际像素**逐张不同**：`2026-09-18-composable-labs-{sword-flight,mountain}-*.png` 为 **1152×720**，两张 `motion-preview-*-real-actor-flight.png` 为 **1280×720**；文件名一律等于实际像素，不统称。

### 7.3 全场回归与主入口

- 主入口 `tests/test_runner.tscn`：**20 套件 921 / 0**（详见第 2 节）；`await suite.run(context)` 已生效（actor 套件是协程）。
- 各 playtest 合计（上表）：**1334 / 0**，全场 `SCRIPT ERROR = 0`。
- 四场迁移新增断言：高空焦点跟随（ground y=12、sword y=30、state y=10、mountain y=42）、角色在视口、
  四场缩放只经 `rig.set_zoom_size()`、四场均无 `_camera` pose/size/投影直写。

## 8. 边界声明

- **未改 `core/`、`tools/`、`project.godot`、`src/data/content/`**；`AGENTS.md` 与 `README.md` 只更新了现状描述（导航、共享 HUD / CameraRig、骨骼未做）。
  说明：catalog 的 `SwordFlight.uses_tags` 漏记改用**字面量调用**解决（`sword_flight.gd`），没有改生成器。
- **未删除任何探索资产**：旧 `camera_lab_rig.gd`、旧截图、旧 GLB/blend 与全部历史 PNG 原样保留；本轮新增证据一律用新文件名。
- **未做**（与 §6 一致）：骨骼 clip 库 / 蒙皮（P1/P2）、骨骼重映射、镜头遮挡规避、手柄与键位重映射、点击地面移动、边缘平移。
