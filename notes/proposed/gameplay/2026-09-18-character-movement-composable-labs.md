# Note: 角色移动实验组——可组合实验室的统一提案

Status: proposed

## 问题

**本轮只记录研究与提案；不包含运行时修复。** 角色移动七个子实验已全部可运行（基线 `99e4894`）。四路只读研究（入口/导航、镜头、UI、装配复用、御剑表现、动作）显示问题不是单点缺陷，而是**同一批「每场各写一遍」的工程债**；证据与行号见 [审计](../../../docs/research/2026-09-18-character-movement-lab-audit.md)。

1. **导航多一步**：首页卡片与子目录卡片都只「选中」，各需再点一次「进入」，实际链为 4 击。
2. **镜头模式语义混杂**：`camera_lab_rig.gd` 的 HARD/SMOOTH/DEADZONE/LOOKAHEAD 是同一「固定正交跟随」下的参数比较预设，却缺少可区分交互的四模式实现；RMB 环绕、四向切换、总览平移都还只是候选。
3. **HUD 重复且信息层级失衡**：底衬/读数 helper 手写 5 份、字号 override 20+ 处；压力场账本+面板与动作工作台读数面板的占屏数据是**源码常量/旧截图估算**，非当前实测。
4. **御剑表现装配不完整**：逻辑与模型复用已存在，但四场可进御剑中只有 sword_flight_course 漏绑飞剑；现有测试不看剑，是验收缺口（不是「七份模型」，也不是用户观察错误）。
5. **动作工作台缺区别的根本原因是缺动作库与操控预览**：`cultivator.glb` 0 skin / 0 animation，现有动作只是程序摆动；工作台既没有可选动作/播放控制，也没有预览时钟，仅靠显示一段问题文字无法补上这一区别。
6. **解耦挂载无落地边界**：跟随逻辑六份复制、输入映射两份；嵌套 Sheet 不能共享宿主组件，缺可安装包与挂载/卸载契约。
7. **统一角色文档漂移**：七场已共享 `swordsman.tscn` → `cultivator.glb`，但模型来源生成器与网格统计文档过期；「统一」指同一装配，不是重造七份。

依据：[character-movement-subexperiments](../../implemented/gameplay/2026-09-18-character-movement-subexperiments.md)、[sheet-format](../../implemented/tech/2026-08-28-sheet-format.md)、[capabilities-architecture](../../implemented/tech/2026-08-28-capabilities-architecture.md)、[traversal-contract](../../../docs/experiments/traversal-contract.md)。

## 提案

### 1. 入口与 HUD（S0 先行）

- **两级卡片一次点击直达**：模块卡（可进入）→ 子目录 → 实验，共 **2 击**；`planned` 卡片只查看说明，不进入；详情改为独立 `i`/hover/键盘可达，不常驻侧栏。
- **GUI 复用 Control + Theme**，不包成 Capability：`src/ui/` 增 `HudTitle`/`HudReadout`/`HudHint`/`HudPanel` 变体，七场删除本地字号 override 与底衬复制。
- **信息密度优先于纯缩字**：默认只放标题 + 核心状态 + 短提示；**实验问题统一折叠/tooltip**（含动作工作台），不常显。**压力场核心账本指标常显**，明细收进 `H`/F1 折叠面板。字号初值为试验值：标题 18–20、正文 13–14、命中区 ≥32×32。
- **返回记忆**：首页/子目录各记 last selected + 滚动可见；实验内记视角/模式；独立启动场景各有明确返回目标。
- **尺寸验收**：960×640（真实 min）、1280×720、1920×1080 各取图；旧的 960×600 截图是历史批，不代表当前 min。

### 2. 镜头：四模式 + modifier，单 executor（S1）

- **A 固定俯视软区跟随**（现有 hard/smooth/deadzone/lookahead 是 A 的参数与比较预设，不是四种交互模式）；**B 固定俯角，偏航每次 90° 的四向切换**（Q/E 及按钮）；**C 受限俯角 RMB 连续环绕 + 滚轮**；**D 总览平移**（中键拖拽 / 可选边缘平移 / 回中）——**D 是本 demo 适配建议，不虚构商业游戏先例**。
- 初推荐 **A 为基准、C 为主要新增探索**；B、D 为比较项。**鼠标位置前瞻**是新候选，与现有「速度前视」不同；**点击地面移动**属另一输入能力候选，不默认新增。
- **高度/速度自适应是叠加 modifier**（数据项），不是第 5 个模式；**正交/有限透视是 projection Resource 配置**，不做组合爆炸。
- **业界参考仅作参考实现**（Cinemachine 3.1.7 Brain/Orbital Follow 思想、Phantom Camera host 独占写入），不接 Unity 包、不照搬 API。

### 3. 装配、挂载与输入契约（S0）

**装配树（同一 actor 唯一 motion component / manager；CameraRig 独立宿主同形状）**：

```
Swordsman (actor)                    CameraRig (独立宿主)
├── SwordsmanMotionComponent  # 唯一    ├── CameraRigComponent        # 唯一
├── CapabilityManager         # 唯一    ├── CapabilityManager         # 唯一
│   └── Movement/Jump/Flight  # 直系子  │   ├── CameraModeA/B/C/D     # 直系子
└── Visual/Cultivator ...              │   ├── CameraExecutor        # 单写 Camera3D
                                       │   └── modifier caps（高度等）
```

- 角色与相机组件之间**通过已登记数据 + 注入目标状态同步（桥接层）**，Capability 之间不互引。
- **「能挂」验收**：新场景只需标准角色 + 相机包 + 配置，不修改 scene 脚本、不复制 bind。
- **飞行表现统一**：把「实例化 `flying_sword.glb` → 命名 `FlyingSword` → 挂 `Visual` → `bind_flight_visual()`」抽成可安装包；可安装御剑 bundle 默认行为 + 剑 visual + 姿态 provider 一体（裸 cap 服务 headless 允许无 visual，完整可玩 bundle 必须有视觉依赖）。四个可进御剑场景统一接入。
- **局部装配适配器（提案待验证）**：嵌套 Sheet 不能共享 actor 组件；不采用「每个包新 manager」（破坏全 cap 优先级）。适配器把能力注册为既有宿主 manager 直系子、复用宿主唯一 component、按 owner 登记卸载；挂载幂等/原子回滚，manager 唯一调度，物理仅 actor 根一次提交。**core 改动另开 owning tech note，本轮不改 core。**
- **输入上下文**：RMB down 仅在 viewport 未被 UI 消费时捕获；up/失焦/退场释放并清累积 delta；**Esc 先退捕获/面板、后返回**（当前 camera 无此功能）。GUI 上滚轮只滚 GUI。连续旋转时 WASD 按**同帧一致 control yaw 地面基**解释，明确 simulation→presentation 顺序；键鼠可映射；**逐帧 delta 不乘 dt**；切模式平滑，混合期 delta 丢弃或显式接管。

### 4. 动作工作台与动作库（S2）

**展示哪些动作 / 怎么对比（4 组，现有程序近似 vs 新骨骼 clip，明确优先级）**：

| 组 | 动作 | 现有程序近似 | 新骨骼 clip（P1/P2） | 优先级 |
|---|---|---|---|---|
| G1 基础步态 | idle / walk / run / start·stop | gait 相位 + `gait_attack/release` 软启停 | idle/walk/run/start/stop（BlendSpace1D 按速度） | P1 |
| G2 转身 | 90° / 180° | turn 点积脉冲，无量化转身 | turn_90 / turn_180 | P2 |
| G3 跳跃 | 起跳/上升/顶点/下落/着地 | rise 收腿 + fall 伸腿 + landing squash | jump_start/rise/apex/fall/land | P2 |
| G4 御剑 | 上剑/悬停/加速/转向/刹停/落剑 | `_flight` 增益 + climb/dive 俯仰 + 微起伏 | mount/hover/accel/turn/brake/dismount | P2–P3 |

- **操控与观察**：动作库选择、播放/暂停/单步/循环/倍率（.25 / .5 / 1）、A–B 混合过渡、侧/正/斜视角与脚接触观察。**控件不是空壳**：P0 用现有程序化动作即能真播、真停、单步；P1/P2 分批接骨骼库。
- **真预览**：同 `Visual` 子场景（建议抽共享 Visual scene）+ 局部预览时钟 + 显式 preview state provider；真实输入模式用 physical snapshot。**不操纵全局 `TimeKeeper`、不写真实 actor 意图**。
- **职责边界**：`AnimationTree`/状态机负责姿态选择与过渡，**不取代 Capability 的并发行为**；读数只经 `stage_state()/pose_state()`，测试不再抓私有 `_legs/_arms`；步幅匹配与真足滑分开度量，socket 未建立前足滑标「待建立」。
- **后续骨骼化**：Blender 在庭院同形象上重建 Armature/蒙皮，另存新目录与新 `.blend`/`.glb`/`Action`，保留旧源与导出；AnimationLibrary/Tree 是表现资源，不一 clip 一 Capability。in-place 是迁移成本选择、非架构禁止；root motion 可经唯一 executor 消费。

### 5. 七场职责（只布局/测试参数/装配清单，核心行为不得复制；布局保留、用户满意）

| 场景 | 只回答 | 职责边界 |
|---|---|---|
| 镜头实验室 | 同一路径下 A/B 对比 | 模式参数与装配清单；不复制跟随行为 |
| 人物动作工作台 | 同模型动作与过渡 | 预览布局、动作选择与播放参数；不复制姿态系统 |
| 地形接触训练场 | 接触、碰撞 | 测试场地与碰撞代理 |
| 御剑飞行训练场 | 空间操控 + 可见飞剑 | 航线与表现装配 |
| 状态切换压力场 | 边沿、装卸、输入失焦清账 | 事件账本与调度边界 |
| 移动庭院 | 小场景标准组合回归 | 保留既有布局 |
| 群山宗门 | 大空间综合 | 保留既有布局 |

### 6. 分阶段

| 阶段 | 产物 | 验收 | 依赖 |
|---|---|---|---|
| **S0** | 2 击导航 + HUD Theme 变体 + 装配适配器契约 + 飞剑完整接入 | 点击链 2 击；7 场 HUD 一致；4 场剑可见与位置/朝向/帧内尺寸截屏 | 本 note 通过评审；core 改动另 note |
| **S1** | 镜头 A/C 两真实消费者，再 B/D；CameraRigComponent + 单 executor | 模式可区分；切换无跳变；失焦/卸载无残留；A/B 同角色同路径对比 | S0 装配契约 |
| **S2** | 动作预览（P0）+ 庭院角色骨骼动作库（P1→P2 小批） | 播放/暂停/单步/循环/倍率可复算；物理零回归；旧资产保留 | S0 契约 + 骨骼资产目录决策 |
| **S3** | 七场迁移与组合回归 | Movement / +Jump / +Flight / all 四组合全通过 | S0–S2 |

## 备选方案

- **把 UI/导航包成 Capability**：否决。Capability 是行为单元，菜单不是；塞进去会让调度器轮询 UI。
- **统一把字号压到 12px**：否决。可读性与缩放受损；应先解决信息层级与重复。
- **把实验对象全部隐藏以省空间**：否决。压力场账本、动作读数就是被测对象；只折叠明细、常显核心指标。
- **每个包自带 CapabilityManager 的嵌套 Sheet**：否决。`game_object()/component()` 只认直系宿主，会破坏 actor 全能力优先级与共享，见 [sheet-format](../../implemented/tech/2026-08-28-sheet-format.md)。
- **每 mode 一个 executor 轮流直写 Camera3D**：否决。写入者不唯一会每帧竞争；只允许一个 executor。
- **把投影做成 Capability 组合**：否决。投影是 Resource 数据，与跟随行为正交。
- **一 clip 一 Capability / 重造七份角色**：否决。动作是表现资源，角色是同一 prefab。
- **仅靠常显问题文字区分动作工作台**：否决。根本缺口是动作库与操控预览，文字不能替代可播动作。
- **退出二次确认流**：未在需求内，不采用。

## 验收标准

1. **入口**：模块卡与子实验卡各一次点击进入（2 击）；`planned` 仅说明；详情 `i`/hover/键盘可达；返回后两级选中项/滚动可见、实验内模式/视角保留。
2. **HUD**：960×640 / 1280×720 / 1920×1080 按 UI 缩放逐档验证；**默认非展开状态 HUD/操作面板总遮盖目标 ≤15% viewport**（压力场因核心账本常显可标例外或另定更宽目标）；目标区域不挡、零重叠/裁切。**该 15% 与字号/命中区均为建议目标、未实测**，须实拍校准。
3. **镜头**：A/B/C/D 可操作区分；`mode_id` 互斥；同一时刻仅一个 executor 写 `Camera3D`；切换平滑；RMB 释放/失焦/退场清 delta；UI 上滚轮不推动镜头；A/B 同角色同路径对比截图。
4. **御剑**：四场可见，截屏含脚下位置、朝向、frame 内可见尺寸；模型统一以引用/标识 + 实际轮廓验证，不锁死 23 mesh；组合至少 Movement / +Jump / +Flight / all 四组，切换/失焦/卸载无残留。
5. **动作**：P0 预览真播/可停/单步；`move_and_slide` 仍仅 actor 一处；`Engine.time_scale` 不被预览改写；旧 GLB/.blend 在库并记录替代；同角色同路径动作对比截图。
6. **装配**：新场景凭标准角色 + 相机包 + 配置即能挂载，无复制 bind；七场可启动；庭院/群山布局不变。

## 风险

- **装配适配器是提案、未验证**：幂等/回滚/卸载顺序都触碰 Capability 生命周期；落地前需单独 tech note 与运行验证，含任何 core 改动。
- **镜头 C 连续环绕持续改变 WASD 地面基**，是否晕眩需试玩；正交下 orbit 需重新定义距离/pitch 语义。
- **旧截图与真实 min 不一致**：960×600/1200×800 小窗图早于 `960×640` 参数，不能当现状；UI 结论须重拍。
- **SystemFont 跨机器差异**是风险（回退字形），不是已发生乱码；稳定需自带字体资产，属新决策。
- **catalog 漏记 SwordFlight tag**：本轮只记录。后续先改生成器常量标签提取（或显式声明契约），配负向控制与回归，再重跑生成 catalog；不在本轮实现。
- **模型文档归属过期**（生成器/网格统计）需在 S0 同步；**当前模型无骨骼**，骨骼化新增资产与表现断代，旧资产必须保留并登记替代关系。
