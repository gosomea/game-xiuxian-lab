# Note: 角色移动实验组——可组合实验室的统一决策

Status: implemented

> 决策批准：**2026-09-18 用户批准本统一提案**。Status 为 implemented 表示**决策已采纳**。
>
> **实现状态（2026-09-18 更新）**：S0 局部装配适配器（ActorAssembly + ActorAssemblyConfig + FlightBundle）、
> S1 镜头包（CameraRig 唯一 executor + 四模式 Capability + CameraRigConfig）、S2 程序动作预览 P0、
> 两级导航与共享 HUD 已落地并进 `tests/test_runner.tscn`；逐项通过/未通过证据与最新计数见
> [可组合移动实验最终报告](../../../docs/playtest/2026-09-18-composable-movement-labs.md)。
> **已完成**：七场统一迁移收口、四场飞剑视觉取证与全场回归均已实测（全场 `SCRIPT ERROR = 0`，主入口 921/0）。
> **未做**：骨骼 clip 库 / 蒙皮（P1/P2）、骨骼重映射与镜头遮挡规避。具体口径与未达项见上述报告。
>
> **补充实现状态（2026-09-18 第二轮，已落地）**：本轮采纳并实现「orbit 正式定义为组合环绕 / 自由跟随」、
> 「镜头实验室与移动庭院默认进入 orbit 并在 HUD 写出四组输入」、「提交器可配置的未归属 RMB 消费策略」
> 与「镜头输入组合测试契约」。`camera_lab.gd` / `movement_garden.gd` 默认 `orbit`，常显提示与详情键表
> 完整写出 WASD / Q-E / 滚轮 / 右键四组输入（`ORBIT_HINT`）；`CameraRigConfig.consume_unowned_rmb`
> 默认关闭、两场显式开启，非 orbit 世界区域 RMB 只消费不捕获、不改 `mouse_mode`、不写 `look_delta`。
> 实现、测试命令与逐项证据见 [镜头组合与 RMB 归属验收](../../../docs/playtest/2026-09-18-camera-combo-rmb.md)。
> **未完成**：编辑器嵌入 Game 视图的人工验收仍待主代理执行（决策中的双形态要求只完成独立窗口一侧）。
>
> **待修复缺陷（2026-09-18 第三轮，先决策后实现）**：人物动作工作台预览面板根 `MOUSE_FILTER_IGNORE` 使整棵按钮子树退出 GUI hit test，右下角播放 / 单步 / 循环 / A–B / 倍率 / 动作按钮的真实鼠标点击零响应；
> 修复决策与回归判据见 §4「右下控件命中」。**`src/` 修复与运行证据尚未落地**，实现前不得把本 note 当作已修复事实引用。

## 问题

角色移动七个子实验已全部可运行（基线 `99e4894`）。四路只读研究（入口/导航、镜头、UI、装配复用、御剑表现、动作）显示问题不是单点缺陷，而是**同一批「每场各写一遍」的工程债**；证据与行号见 [审计](../../../docs/research/2026-09-18-character-movement-lab-audit.md)。

1. **导航多一步**：首页卡片与子目录卡片都只「选中」，各需再点一次「进入」，实际链为 4 击。
2. **镜头模式语义混杂**：`camera_lab_rig.gd` 的 HARD/SMOOTH/DEADZONE/LOOKAHEAD 是同一「固定正交跟随」下的参数比较预设，却缺少可区分交互的四模式实现；RMB 环绕、四向切换、总览平移都还只是候选。
3. **HUD 重复且信息层级失衡**：底衬/读数 helper 手写 5 份、字号 override 20+ 处；压力场账本+面板与动作工作台读数面板的占屏数据是**源码常量/旧截图估算**，非当前实测。
4. **御剑表现装配不完整**：逻辑与模型复用已存在，但四场可进御剑中只有 sword_flight_course 漏绑飞剑；现有测试不看剑，是验收缺口（不是「七份模型」，也不是用户观察错误）。
5. **动作工作台缺区别的根本原因是缺动作库与操控预览**：`cultivator.glb` 0 skin / 0 animation，现有动作只是程序摆动；工作台既没有可选动作/播放控制，也没有预览时钟，仅靠显示一段问题文字无法补上这一区别。
6. **解耦挂载无落地边界**：跟随逻辑六份复制、输入映射两份；嵌套 Sheet 不能共享宿主组件，缺可安装包与挂载/卸载契约。
7. **统一角色文档漂移**：七场已共享 `swordsman.tscn` → `cultivator.glb`，但模型来源生成器与网格统计文档过期；「统一」指同一装配，不是重造七份。

依据：[character-movement-subexperiments](2026-09-18-character-movement-subexperiments.md)、[sheet-format](../tech/2026-08-28-sheet-format.md)、[capabilities-architecture](../tech/2026-08-28-capabilities-architecture.md)、[traversal-contract](../../../docs/experiments/traversal-contract.md)、**局部装配与镜头契约** [composable-lab-assembly-contract](../tech/2026-09-18-composable-lab-assembly-contract.md)。

## 决策

### 1. 入口与 HUD（S0 先行）

- **两级卡片一次点击直达**：模块卡（可进入）→ 子目录 → 实验，共 **2 击**；`planned` 卡片只查看说明，不进入；详情改为独立 `i`/hover/键盘可达，不常驻侧栏。
- **GUI 复用 Control + Theme**：走可复用 Control + Theme，`src/ui/` 增 `HudTitle`/`HudReadout`/`HudHint`/`HudPanel` 变体，七场删除本地字号 override 与底衬复制；**不包成 Capability**。
- **信息密度优先于纯缩字**：默认只放标题 + 核心状态 + 短提示；**实验问题统一折叠/tooltip**（含动作工作台），不常显。**压力场核心账本指标常显**，明细收进 `H`/F1 折叠面板。字号为试验初值：标题 18–20、正文 13–14、命中区 ≥32×32。
- **返回记忆**：首页/子目录各记 last selected + 滚动可见；实验内记视角/模式；独立启动场景各有明确返回目标。
- **尺寸验收**：960×640（真实 min）、1280×720、1920×1080 三分辨率各取图；旧的 960×600 截图是历史批，不代表当前 min。
- **HUD 遮盖与布局目标（试验值，需实拍校准，未证实）**：默认非展开状态下 HUD / 操作面板总遮盖目标 **≤15% viewport**；**压力场因核心账本常显为例外**，可另定更宽目标。要求目标区域无裁切、面板零重叠、操作区不遮实验目标；验收按 UI 缩放逐档截图判定，不只看占屏读数回落。
- **组合模式可发现（2026-09-18 第二轮）**：`camera_lab` 与 `movement_garden` **默认进入 `orbit`（组合环绕 / 自由跟随）**，且 HUD 必须**完整写出四组输入**——WASD 移动、Q/E 连续偏航、滚轮 / Z / X 缩放、RMB 拖动 yaw/pitch（受限俯角）。四组是玩家进入场景后不查文档即可读到的常显 / 详情文案，不得只写其中一两项。`fixed_follow` / `quarter_turn` / `overview` 仍可切回（按钮与数字键按各场景现有归属），组合模式不吞并其余模式的单一交互。

### 2. 镜头：四模式 + modifier，单 executor（S1）

- 四模式（括号内为**长期命名**，脚本必须用语义名，A–D 仅本文档例图简称）：**A `fixed_follow` 固定俯视软区跟随**（现有 hard/smooth/deadzone/lookahead 是它的参数与比较预设，不是四种交互模式）；**B `quarter_turn` 固定俯角、偏航每次 90° 的四向切换**（Q/E 及按钮）；**C `orbit` 组合环绕 / 自由跟随**（WASD + Q/E 连续偏航 + 滚轮缩放 + RMB 拖动 yaw/pitch，见下）；**D `overview` 总览平移**（中键拖拽 / 可选边缘平移 / 回中）。**D 是本 demo 适配建议，不虚构商业游戏先例**；初推荐 **A 为基准、C 为主要新增探索**，B/D 为比较项。
- **组合环绕（2026-09-18 第二轮正式定义）**：`orbit` 不再只是「受限 RMB 环绕」，正式定义为**组合环绕 / 自由跟随**——同一模式内同时支持 **WASD 屏幕相对移动**（仍归 actor / 场景输入，rig 只发布相机地面基）、**Q/E 连续偏航**、**滚轮 / Z / X 缩放**、**RMB 拖动 yaw + pitch（受限俯角）**。**不新增第 5 个相机 Capability**（4-cap 预算见装配契约 note §3）；输入组合是模式内行为组合，`camera_lab` / `movement_garden` 默认进入该模式并完整广告四组输入。§3 的「能挂」边界不变：场景仍需自己的输入 adapter 与一次 `bind()`。
- **未归属 RMB 消费策略（2026-09-18 第二轮）**：`CameraRigConfig` 新增可配置开关（默认关闭 = 现状：镜头包不抢场景按键）。实验场景显式启用后，**非 `orbit` 模式**在 **UI 未占用**的世界区域消费 RMB press/release，但**不捕获、不改 `mouse_mode`、不写拖动 delta**，避免未消费的右键泄漏为 Godot 编辑器嵌入 Game 视图的上下文操作；`orbit` 的 RMB press 在 UI 未占用时**同一输入事件内尽早捕获**，release / Esc / 失焦 / 离树 / 切模式必须释放并恢复进入前的 `mouse_mode`；**UI 上方右键由 GUI 优先，镜头包不劫持**。
- **鼠标位置前瞻**是独立于现有「速度前视」的新候选；**点击地面移动**属另一输入能力候选，不默认新增。
- **高度/速度自适应是叠加 modifier**，作为**数据配置**由 executor 读取，**不是第 5 个 Capability**；**正交/有限透视是 projection Resource 配置**，不做模式组合爆炸。
- 业界参考仅供思想（Cinemachine 3.1.7 Brain/Orbital Follow、Phantom Camera host 独占写入），不接 Unity 包、不照搬 API。

### 3. 装配、挂载与输入契约（S0）

**装配树（同一 actor 唯一 motion component / manager；CameraRig 独立宿主同形状）**：

```
Swordsman (actor)                    CameraRig (独立宿主，普通 Node3D)
├── SwordsmanMotionComponent  # 唯一    ├── CameraRigComponent        # 唯一
├── CapabilityManager         # 唯一    ├── CapabilityManager         # 唯一
│   └── Movement/Jump/Flight  # 直系子  │   └── fixed_follow / quarter_turn / orbit / overview  # 4 模式 Cap
└── Visual/Cultivator ...              └── CameraRig 根节点自身即提交器  # 非 Capability
                                           （modifier 为数据配置，不新增 cap）
```

> **实现修正**：CameraRig 落地为「普通 Node3D 根 + `CameraRigComponent` 直系子 + `CapabilityManager` 直系子，
> 四模式 Capability 为 manager 直系子；提交器就是 `CameraRig` 根节点自身（`_physics_process` → `advance()`）」，
> 不存在名为 `CameraExecutor` 的独立节点。契约 note 的原始措辞「一个普通宿主提交器」保留其意图，此处按实现写明。

- 角色与相机组件之间**通过已登记数据 + 注入目标状态同步（桥接层）**，Capability 之间不互引；`CameraRig` 对角色只读**目标 snapshot**。
- **「能挂」验收**：新场景只需标准角色 + 相机包 + 配置即可获得跟随/模式行为与飞剑视觉；**仍需场景侧最小编排**——
  输入 adapter（按键 → 公开 API）与一次 `rig.bind(camera, target, config)`。不复制跟随行为、不复制绑剑逻辑是硬要求，
  但「不修改 scene 脚本」不等于「零场景代码」，本节按此边界执行。
- **飞行表现统一（可选/可组合，不是 helper）**：`src/game/actors/swordsman/` 的 ActorAssembly 作为装配 root（持有 movement/jump/flight 依赖与显式配置），**FlightBundle 是独立的可选装配包**，自带剑 visual 与姿态 provider。禁止把它降级为「检查既有三能力 + 挂一把剑」的 helper。裸 cap 服务 headless 允许无 visual；完整可玩 bundle 必须有视觉依赖。四个可进御剑场景统一接入。
- **局部装配适配器**：嵌套 Sheet 不能共享 actor 组件；不采用「每个包新 manager」（破坏全 cap 优先级）。适配器把能力注册为既有宿主 manager 直系子、复用宿主唯一 component、按 owner 登记卸载；挂载幂等、原子回滚，manager 唯一调度，物理仍仅 actor 根一次提交。具体约束见 [composable-lab-assembly-contract](../tech/2026-09-18-composable-lab-assembly-contract.md)。**除非必要不改 `core/`；任何 core 改动另开 owning tech note。**
- **输入上下文**：RMB down 仅在 viewport 未被 UI 消费时捕获；up/失焦/退场释放并清累积 delta；**Esc 先退捕获/面板、后返回**（当前 camera 无此功能）。GUI 上滚轮只滚 GUI。连续旋转时 WASD 按**同帧一致 control yaw 地面基**解释，明确 simulation→presentation 顺序；键鼠可映射；**鼠标像素位移 `screen_relative` 不再乘 dt；键盘角速度 / 连续平移速度仍乘帧时长**；切模式平滑，混合期 delta 丢弃或显式接管。
- **RMB 归属的追加规则（2026-09-18 第二轮）**：未启用新开关时保持本 bullet 原文语义（默认不抢按键）。启用后，非 `orbit` 模式消费世界区域 RMB 但不捕获（不改 `mouse_mode`）；`orbit` 在 UI 未占用时同一事件内尽早捕获，release / Esc / 失焦 / 离树 / 切模式恢复；UI 上方右键不劫持。四模式与两个真实消费者的输入矩阵、实现落点与测试契约见装配契约 note §2/§4。

### 4. 动作工作台与动作库（S2）

**展示哪些动作 / 怎么对比（4 组，现有程序近似 vs 新骨骼 clip，明确优先级）**：

| 组 | 动作 | 现有程序近似 | 新骨骼 clip（P1/P2） | 优先级 |
|---|---|---|---|---|
| G1 基础步态 | idle / walk / run / start·stop | gait 相位 + `gait_attack/release` 软启停 | idle/walk/run/start/stop（BlendSpace1D 按速度） | P1 |
| G2 转身 | 90° / 180° | turn 点积脉冲，无量化转身 | turn_90 / turn_180 | P2 |
| G3 跳跃 | 起跳/上升/顶点/下落/着地 | rise 收腿 + fall 伸腿 + landing squash | jump_start/rise/apex/fall/land | P2 |
| G4 御剑 | 上剑/悬停/加速/转向/刹停/落剑 | `_flight` 增益 + climb/dive 俯仰 + 微起伏 | mount/hover/accel/turn/brake/dismount | P2–P3 |

- **操控与观察**：动作库选择、播放/暂停/单步/循环/倍率（.25 / .5 / 1）、A–B 混合过渡、侧/正/斜视角与脚接触观察。**控件不是空壳**：P0 用现有程序化动作即能真播、真停、单步；P1/P2 分批接骨骼库，**本轮不承诺完成**。
- **右下控件命中（2026-09-18 第三轮：缺陷、根因与修复决策；`src/` 修复尚未落地）**：
  - **缺陷事实**：`src/game/systems/motion_preview/motion_preview_panel.gd` 的根节点（`MotionPreviewPanel`，extends `PanelContainer`）自身设置 `mouse_filter = Control.MOUSE_FILTER_IGNORE`，导致 `ActionRow` / `PlaybackRow` / `RateRow` 的整棵按钮子树不参与 GUI hit test——真实探针测得按钮中心 `gui_get_hovered_control() == null`，播放 / 单步 / 循环 / A–B / 倍率 / 动作按钮的**真实鼠标点击零状态变化**。
  - **验收缺口（为何此前全绿）**：现有自动化只经 `state.playing = …`、`step_once()`、`grab_focus()` 等**旁路命中测试**的路径，没有一条真实鼠标点击用例，因此该缺陷未在 953/0 中被暴露。
  - **修复决策**：面板根**必须参与命中测试**（`MOUSE_FILTER_PASS`，必要时对按钮交互区改 `STOP`），不得以 `IGNORE` 让自身及按钮子树整体退出 hit test；**外围透明容器**（`PreviewOverlay` / `PreviewMargin` / `PreviewColumn` / `PreviewRow`）保持 `IGNORE`，使面板矩形之外仍可操作 3D 视口。命中面积仍受 §1「命中区 ≥32×32」约束。
  - **回归判据（必须真实鼠标，不得用 `pressed.emit()` 或直接改状态代替）**：经 `Viewport.push_input()` 把含位置的真实鼠标事件送到按钮中心，先断言 `gui_get_hovered_control()` 解析到该按钮，再断言 `preview_snapshot()` 的 `playing` / `local_time` / `looping` / `rate` / `action_id` / `transitioning` 至少一项按预期变化；反向用例：面板矩形外点击不得改变预览状态。
- **真预览**：同 `Visual` 子场景（建议抽共享 Visual scene）+ 局部预览时钟 + 显式 preview state provider；真实输入模式用 physical snapshot。**不操纵全局 `TimeKeeper`、不写真实 actor 意图**。
- **职责边界**：`AnimationTree`/状态机负责姿态选择与过渡，**不取代 Capability 的并发行为**；读数只经 `stage_state()/pose_state()`，测试不再抓私有 `_legs/_arms`；步幅匹配与真足滑分开度量，socket 未建立前足滑标「待建立」。
- **后续骨骼化（P1/P2，另立资产切片）**：Blender 在庭院同形象上重建 Armature/蒙皮，另存新目录与新 `.blend`/`.glb`/`Action`，保留旧源与导出；AnimationLibrary/Tree 是表现资源，不一 clip 一 Capability。in-place 是迁移成本选择、非架构禁止；root motion 可经唯一 executor 消费。

### 5. 七场职责（只布局/测试参数/装配清单，核心行为不得复制；布局保留、用户满意）

| 场景 | 只回答 | 职责边界 |
|---|---|---|
| 镜头实验室 | 同一路径下 `fixed_follow` / `orbit` 对比 | 模式参数与装配清单；不复制跟随行为 |
| 人物动作工作台 | 同模型动作与过渡 | 预览布局、动作选择与播放参数；不复制姿态系统 |
| 地形接触训练场 | 接触、碰撞 | 测试场地与碰撞代理 |
| 御剑飞行训练场 | 空间操控 + 可见飞剑 | 航线与表现装配 |
| 状态切换压力场 | 边沿、装卸、输入失焦清账 | 事件账本与调度边界 |
| 移动庭院 | 小场景标准组合回归 | 保留既有布局 |
| 群山宗门 | 大空间综合 | 保留既有布局 |

### 6. 分阶段与最小可交付

**本次实施（S0–S2 的 P0 范围）最小可交付 = 2 击导航 + 轻量 HUD + 飞剑统一装配 + 四模式镜头 + 可实际播放的程序动作预览 + 七场组合回归**。**Blender 骨骼 clip 库（P1/P2）不在本次交付内**，需单独的资产切片与后续决策，本 note 不承诺本轮完成。**不增加与用户诉求无关的玩法。**

| 阶段 | 产物 | 依赖 | 可观察验收 |
|---|---|---|---|
| **S0** | 2 击导航 + HUD Theme 变体 + 局部装配适配器 + 飞剑完整接入 | 本 note 决策；契约 note；core 改动另 note | 点击链 2 击（已由 `test_lab_navigation.gd` 覆盖）；7 场 HUD 一致；三分辨率截图，默认遮盖 ≤15%（压力场例外）：**生产 stretch 口径七场全达**（最接近为动作工作台预览态 14.93%），1:1 画布压力口径下窄屏超限已如实记录；4 场剑可见已完成（定性图审 + 正式 actor mesh 断言）；新场景凭标准角色 + 相机包 + 配置即能挂。**边界**：「能挂」指装配（能力/视觉/相机求值）已由包完成，场景仍需自己的输入编排（把按键映射为 `set_move_input` / `press_flight_toggle` 等公开 API）与 `bind()` 调用——不存在「零场景代码」的全自动装配 |
| **S1** | 镜头 `fixed_follow`/`orbit` 两真实消费者，再 `quarter_turn`/`overview`；CameraRigComponent + 单 executor | S0 装配契约 | 四模式可操作区分（脚本用语义名）；`mode_id` 互斥；同一时刻仅一个 executor 写 `Camera3D`；切换无跳变；RMB up/失焦/退场清 delta；同角色同路径对比 |
| **S1-b（2026-09-18 第二轮，已实现）** | `orbit` 组合环绕（WASD + Q/E 连续 + 滚轮 + RMB）、未归属 RMB 消费策略、两场景默认可发现 | S1 | **已完成**：五条测试契约全绿（`test_camera_rig_executor.gd` 83/0、`camera_lab_playtest.gd` 152/0、`character_movement_playtest.gd` 58/0，见 [验收报告](../../../docs/playtest/2026-09-18-camera-combo-rmb.md)）；`camera_lab` 与 `movement_garden` 默认 orbit 且 HUD 完整写出四组输入；未新增 Capability（仍 4）。**未完成**：编辑器嵌入 Game 视图人工验收待主代理 |
| **S2** | 动作预览 P0（程序动作真播）+ 动作库选择/播放/暂停/单步/循环/倍率/A–B 过渡 | S0 契约 | **右下控件必须可被真实鼠标命中**：按钮中心 `gui_get_hovered_control()` 解析到该按钮，真实点击产生可观察状态变化（见 §4「右下控件命中」；`pressed.emit()` / 直接改状态不算）；播放/暂停/单步可复算；`move_and_slide` 仍仅 actor 一处；`Engine.time_scale` 不被预览改写；旧 GLB/.blend 在库并记录替代；侧/正/斜与脚接触观察 |
| **S3** | 七场迁移与组合回归 | S0–S2 | **真实实例化** Move / Move+Jump / Move+Flight / all 四子集；未启用能力静默不触发；切换/失焦/卸载无残留且不 `reset_motion()` 清无关状态；七场可启动；庭院/群山布局不变 |

## 备选方案

- **把 UI/导航包成 Capability**：否决。Capability 是行为单元，菜单不是；塞进去会让调度器轮询 UI。
- **统一把字号压到 12px**：否决。可读性与缩放受损；应先解决信息层级与重复。
- **把实验对象全部隐藏以省空间**：否决。压力场账本、动作读数就是被测对象；只折叠明细、常显核心指标。
- **每个包自带 CapabilityManager 的嵌套 Sheet**：否决。`game_object()/component()` 只认直系宿主，会破坏 actor 全能力优先级与共享，见 [sheet-format](../tech/2026-08-28-sheet-format.md)。
- **每 mode 一个 executor 轮流直写 Camera3D**：否决。写入者不唯一会每帧竞争；只允许一个普通宿主提交器。
- **把投影做成 Capability 组合 / modifier 做成第五个 cap**：否决。投影是 Resource 数据、modifier 是配置叠加，都与跟随行为正交，且会撞上叶子包 4 Capability 上限。
- **一 clip 一 Capability / 重造七份角色**：否决。动作是表现资源，角色是同一 prefab。
- **仅靠常显问题文字区分动作工作台**：否决。根本缺口是动作库与操控预览，文字不能替代可播动作。
- **退出二次确认流**：未在需求内，不采用。

## 后果

- **决策已生效**：`notes/proposed/` 中的同名提案已迁移到本 note；[审计](../../../docs/research/2026-09-18-character-movement-lab-audit.md) 的链接已指向本路径。
- **实现已落地（部分）**：`src/` 已新增 `game/actors/swordsman/actor_assembly{, _config}.gd` + `actor_assembly_all.tres`、
  `game/abilities/sword_flight/flight_bundle.gd`、`game/systems/camera_rig/`、`game/systems/motion_preview/`、
  `ui/lab_hud.gd`、`tests/test_lab_navigation.gd`，并改写 `swordsman.tscn` 的装配方式与两级 hub 的导航。
  `AGENTS.md` 与 `README.md` 已更新为当前实现的事实描述；`experiments.json` 的 `exploring` 状态与 `ready` 标签**未改**（不扩玩法）。
- **已知未做**：骨骼 clip 库与蒙皮（P1/P2）未做——`cultivator.glb` 实测 0 skin / 0 animation，动作仍为程序近似；
  骨骼重映射（retarget）与镜头遮挡规避/推近均未实现；HUD「默认非展开遮盖 ≤15%」在**生产 stretch 口径已达成**
  （七场全部 ≤15%，最接近为动作工作台预览态 14.93%），仅 **1:1 画布布局压力口径**下动作工作台窄屏超限
  （960×640 = 24.9%、1280×720 = 16.6%、1920×1080 = 7.4%，见
  [生产 UI 复核](../../../docs/playtest/2026-09-18-production-ui.md) 与 [动作预览专项报告](../../../docs/playtest/2026-09-18-motion-preview.md)）。
- **已知待办**：catalog 漏记 SwordFlight tag **已用最小改法解决**——`src/game/abilities/sword_flight/sword_flight.gd` 的
  `TagRegistry.add_block/remove_block` 改用字面量 `&"sword_flight_block"`，使现有生成器的字面量提取可识别
  （重生成后 `SwordFlight.uses_tags=["sword_flight_block"]`），因此**未改 `tools/gen/`，也无需负向控制**；
  若将来要支持常量传参提取，另开 tools 变更。模型文档来源与统计过期已在
  `docs/art/movement_garden/` 与 `docs/art/cultivator_refined/` 同步；SystemFont 跨机器回退风险与旧截图不代表当前 min 仍为已知限制。
- **风险保留**：镜头 C 连续环绕下 WASD 地面基漂移是否可接受、正交 orbit 的距离/pitch 语义仍需人工试玩；
  装配适配器的幂等/回滚/四子集已由 `test_actor_assembly.gd`（142 项）与 `test_flight_bundle.gd`（83 项）覆盖。
  本轮实现**未改 `core/`**；将来若有 core 改动必须另开 owning tech note。
- **待修复缺陷（2026-09-18 第三轮，已记录未实现）**：动作工作台右下 `PreviewPanel` 的按钮真实鼠标点击无响应，根因与修复决策见 §4「右下控件命中」；
  `src/game/systems/motion_preview/motion_preview_panel.gd` 的修复、真实鼠标回归用例与运行证据**尚未落地**，落地前不得在状态报告与 README 中声称该缺陷已修复。
- **追加风险（2026-09-18 第二轮，实现后仍保留）**：嵌入 Game 视图下「世界区域右键消费 vs 编辑器上下文操作」的边界
  与组合环绕的操作舒适度仍需真实宿主验收与人工试玩；独立窗口侧的自动证据已落地（见验收报告），
  编辑器嵌入 Game 视图一侧**未验收**，不得据本 note 声称双形态已通过。
