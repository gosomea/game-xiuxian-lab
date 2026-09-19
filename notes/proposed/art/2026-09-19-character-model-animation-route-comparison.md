# Note: KayKit 同模型双路线 A/B：原生骨架动作与 Mixamo 重定向对照

Status: proposed

授权与归属分两组，必须分开读：**用户明确方向**（使用者授权，本 note 负责解释与落地）与**本轮提案决定**（代理在调研后提出，待评审）。

**用户明确方向（使用者授权）**

1. **交给子 agent 执行**本议题。
2. **两路对比**：两条路线必须做对照比较，不能只做其中一条。
3. **路线一：网上现成完整资产**——采用网上已带骨架与动作的现成资产，并授权其**下载与改造方向**。
4. **路线二：更好模型再生成动作**——先取得更好的模型，再走生成 / 重定向动作的流程。
5. **当前流程跑通即可**：本轮完成标准是现有管线端到端跑通，不追求成品级质量。

使用者授权明确覆盖「两条路线对比」与「资产下载 / 改造方向」。使用者**未逐字指定**任何具体资产来源、作者、commit、许可证条款或验收阈值。

**本轮提案决定（代理提出，待评审）**

以下 9 条均为代理在本轮调研后提出的工程决策，**不是使用者逐条确认的内容**，评审可整体否决或逐条替换：

1. **把路线一落地为路线 A**：来源取 **KayKit Adventurers** 官方 GitHub 仓库的原生骨架 + 原生动画，直接进 Godot。
2. **把路线二落地为路线 B**：从**同一个** KayKit 角色导出静态、单网格、T/A pose 输入，走本仓现有 Mixamo 流程。
3. **同模型控制变量**：A/B 共用同一底层网格，使差异只落在动作管线。
4. **排除 Quaternius**：理由是 pack 页 CC0 与现行 QAL 再分发条款口径冲突（许可口径否决，非质量否决）。
5. **固定 commit** `672074b73ba276876a19e8816ecdc5241817ab47` 作为可复现锚点。
6. **基线 C**：现有自产 `cultivator_rigged` 原样保留作为对照，不覆盖、不删除。
7. **选角门槛**：第一轮优先不带超大袍片、轮廓最接近法师/冒险者的免费角色；实际文件检查不符合则停下报告，不擅自换来源。
8. **验收矩阵与阈值**：A/B 同相机、同速度、同状态映射，比较脚滑、手腕/肘肩、裙/披风穿插、轮廓、材质，并设 `≤40k tris`、`≤2 draw calls`。
9. **人工门**：Mixamo marker 必须人工——这是既有流程的硬约束（见 [mcp-mixamo skill](../../../skills/mcp-mixamo/SKILL.md)），不是本提案的可选项；路线 B 到该步停住等待使用者，禁止假称完成。

本 note 起始为决策前置（仓库铁律「先决策记录，后实现」，见[根 AGENTS.md](../../../AGENTS.md)）。**阶段 1 已于 2026-09-19 执行**：上游最小集入库 `docs/art/kaykit_route_ab/`（证据见[资产台账](../../../docs/art/kaykit_route_ab/asset_ledger.md)），**Status 仍为 proposed**——上游就位不等于运行时落地，`src/` 与 `mcp/` 在本阶段零改动。

## 问题

2.5D（第三人称跟随）修仙模块实验室的玩家角色目前有三份自产资产：[分件刚体](../../../src/game/actors/swordsman/models/cultivator.glb) 与 16 分件版 `cultivator_jade.glb` 走 [分件刚体表现层](../../../src/game/actors/swordsman/cultivator_presentation.gd)，以及 Mixamo 绑骨版 [cultivator_rigged.glb](../../../src/game/actors/swordsman/models/cultivator_rigged.glb) 走 [骨骼表现层](../../../src/game/actors/swordsman/cultivator_skeleton_presentation.gd)（clips = idle/walk/run/jump，映射常量 `WALK_SPEED_MPS=0.3` / `RUN_SPEED_MPS=5.5` / `stride 1.6 / 3.2` / `BLEND=0.15`）。第四轮已把 `jade_paper_sample` 的 Visual 子树换成骨骼版，左右肢体交叉绑定与手指链缺失已在[左右修正验收](../../../docs/playtest/2026-09-19-jade-paper-rigged-side-fix.md)排除。

剩下的问题是**动作与长袍蒙皮不自然**，而当前没有任何证据能回答它来自哪一层：动作库本身、本仓的权重后处理、还是模型在切分时就已无法蒙皮。要回答它，就必须让模型固定、只换动作管线，做一次对照。

### 为何不继续修当前模型

本轮只读审计对 `cultivator_rigged.glb` / 其源 `cultivator_jade.blend` 得到四项读数：

| 读数 | 含义 |
|---|---|
| 89 个网格岛 | 模型由切割产生，岛数远超人形角色的合理蒙皮单元数 |
| 裙主岛 13,032 顶点、权重 100% 挂 `Hips` | 整片裙摆是**单骨刚体**，腿动裙不动，"人物与衣服分开"的近似在此已到极限 |
| 976 个腕高点误挂 `Hips`/`UpLeg` | 高腕位的点被权重锁定规则兜底到了髋/腿骨，是袖手姿态异常的直接来源 |
| 无裙摆骨、无布料 | 骨架里没有可驱动裙摆的次级骨链 |

> **证据分级（必须复核）**：以上四项来自本轮**只读审计**，**未落盘为仓库证据**（仓库内无对应台账或记录）。它需要主代理抽查后才能作为最终验收结论；若抽查不成立，本节"为何不继续修"的论证必须重写。

即便读数成立，继续修的代价也高于换一个自带完整动作的低模角色：需要逐岛重刷权重 + 新增裙摆骨链 + 次级摆动，且**修完仍无法判断动作库本身是否就是问题来源**。因此本轮不把"继续修"作为主线——但它也没有被否决，它只是基线 C 的现状，随时可回退。

### 为什么必须同模型双路线

换来源（换角色/换作者）会把模型与动作管线两个变量一起换掉，得不出可归因的结论。A 与 B 使用**同一个底层网格**，差异只落在"骨骼与动作从哪来"，因此任何观感差异都可归因给动作管线。

## 提案

### 1. 路线 A：KayKit Adventurers 原生骨架 + 原生动画

- 来源：`https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0`，**固定 commit `672074b73ba276876a19e8816ecdc5241817ab47`**（2023-09-16；该 SHA 与 Godot 资产库 asset 2129 记录的 `download_commit` 完全一致）。
- 免费仓库内角色（jsDelivr 文件清单，2026-09-19 读取）：`Characters/gltf/{Barbarian,Knight,Mage,Rogue,Rogue_Hooded}.glb`，各约 3.6 MB；每个角色一张 1024 贴图（`*_texture.png`，14–17 KB）；另有 `Assets/gltf/` 下 25+ 武器/盾/法杖等配件；`addons/kaykit_character_pack_adventures/LICENSE.txt`（891 字节）。
- 原生 GLB 自带骨架与动作，**直接进 Godot，不经 Blender 重定向**；动作清单以第一轮文件级核验为准。
- 优点：一次导入即同时拿到骨架与动作；CC0 无再分发限制；Godot 资产库同一 commit 收录。
- 代价：动作是西幻/冒险者风格而非修仙——**这是唯一剩下的实质代价**。
- **格式澄清（阶段 1 实测纠正）**：创作者官网的商品页写 "Included files are .FBX, .GLTF"，但**固定免费仓库里只有 GLB / glTF（+ .bin + 角色 PNG 贴图），没有任何 .fbx 文件**（阶段 1 清点：27 gltf / 27 bin / 12 png / 5 glb / 1 txt，`.fbx` 计数为 0）。路线 A 要用 FBX 必须自行从 GLTF 导出；路线 B 的单网格 OBJ/FBX 上传源同样需要自行导出。
- **受击/死亡并非缺口（阶段 1 实测纠正）**：此前"免费仓库未见受击包、可能要另找来源"的推断被推翻——角色 GLB **内置** `Hit_A` / `Hit_B` / `Death_A` / `Death_B`（另含 4 条 Pose 变体），无需第二个来源。

### 2. 路线 B：同一角色 → 静态单网格 T/A pose → Mixamo

- 输入：从**同一个** KayKit 角色导出静态、单网格、T/A pose（剥掉原生骨架与动画），走本仓既有流程（[mcp-mixamo skill](../../../skills/mcp-mixamo/SKILL.md)）：`mcp/mixamo/mixamo_driver_phase1.py`（上传 + **人工拖放 marker**）→ `phase2`（下载 walk/idle/run/jump）→ `phase3`（Blender 组装：cm→m、动作重命名、权重锁定）。
- 硬门：marker 拖放**必须人工**（`screens/upload.py` 明确不支持自动化）。到达该步必须停住等待使用者，禁止 select/click 盲拖，禁止在报告里写成已完成。
- 已登记工程坑：Mixamo FBX 骨架是 cm（×100 只对骨架，网格会变 172 m）；不并发（共用同一 browser profile）；Edge 跨域下载会杀死 context（拦截预签名 URL + urllib，每动画独立会话）；动画变体需精确名 + 黑名单过滤。
- 代价：多一次人工环节、多一套 Mixamo 依赖、多一轮单位/左右/权重后处理。

### 3. 基线 C：现有自产 `cultivator_rigged`（只读，不改）

`cultivator_rigged.glb` + `cultivator_visual_rigged.tscn` + `cultivator_skeleton_presentation.gd` 原样保留，作为 A/B 的对照基线。不覆盖、不删除、不改名；A/B 均不达标时，场景引用回滚到 C。

### 4. 第一轮选角门槛

在免费 5 个 GLB 中按顺序选**一个**：

1. **不含超大袍片/披风**（`Mage` 法袍、`Rogue_Hooded` 兜帽是重点检查对象）；
2. **轮廓最接近法师/冒险者**（呼应[美术方向](2026-09-19-jade-paper-art-direction.md)的"剪影可读性优先"）；
3. 单贴图、材质数最少（有利于 ≤2 draw calls 目标）。

**若仓库内实际文件检查（面数/岛数/袍片面积占比/材质数）后没有任何角色符合，停下报告，不擅自换来源。**

**实际结果（阶段 1，已完成）**：选中 **`Rogue_Hooded`**。逐条对照门槛：

| 门槛 | `Rogue_Hooded` 实测 | 判定 |
|---|---|---|
| 不含超大袍片/披风 | 唯一的披风 `Rogue_Cape` = **84 tris、单片、无 skin**（顶点属性无 `JOINTS_0`/`WEIGHTS_0`），刚体挂 `chest` | 通过（`Mage` 的整身法袍风险被避开） |
| 轮廓最接近法师/冒险者 | 兜帽 + 斗篷 + 短打，Q 版比例，剪影干净可辨（预览见 `docs/art/kaykit_route_ab/previews/`） | 通过 |
| 单贴图 / 材质数最少 | **1 材质、1 内嵌 1024×1024 贴图**，无外部依赖 | 通过 |
| 面数预算 | 6,035 tris（含 5 个武器挂件 2,030；角色本体 7 mesh / 4,005 tris） | 通过（≪ 40k 上限） |

选角依据的完整读数、sha256 与来源登记见 [资产台账](../../../docs/art/kaykit_route_ab/asset_ledger.md)。

### 5. 许可边界

- KayKit 官方 `LICENSE.txt`（固定 commit 内文件，本轮已读取原文）：`License: (Creative Commons Zero, CC0)` + `http://creativecommons.org/publicdomain/zero/1.0/` + `This content is free to use in personal, educational and commercial projects.`，并写明署名 `not mandatory`。创建日期 2023-03-13。
- **CC0 允许修改与再分发**（含以资产形式），因此与本仓「所有项目资产必须进入 Git」不冲突；落地时仍必须保存 `LICENSE.txt` 原件 + 仓库 URL + commit SHA + 下载日期。
- **付费档边界**：EXTRA / SOURCE 档内容不在免费档内，不得混入，也不得当作免费资产入库。`kaylousberg.itch.io` 本轮返回 **403（Cloudflare 挑战页）**，EXTRA/SOURCE 档清单与价格**未核验**；免费档与付费档差异只能从官网文字（"5 (+3 in the EXTRA tier)"）推断。
- **路线 B 的第二层许可**：Mixamo 动画与自动绑骨结果。Adobe 官方 FAQ（2021-09-14 版）写明 characters 与 animations 可用于 personal / commercial / non-profit，含 video games；但**"下载的 FBX 能否作为资产随仓库再分发"未核验**。本仓要求资产进 Git，所以在核验该边界之前，路线 B **只允许做对照实验，不得作为最终方案封板**。
- **排除记录**：Quaternius 的 pack 页仍标 "License CC0"，而站点许可证页已是自定义 QAL v1.0（2026-08-28），其 §3(a) 禁止把资产本身（含修改版）再分发——与「资产必须进 Git」口径冲突，本轮排除。这是**许可口径否决，不是质量否决**，口径澄清后可重议。

### 6. 资产目录与命名草案

遵守"源在 `docs/art/`、导出在 `src/`"与 `src/game/AGENTS.md` 的"资源靠近叶子包"：

| 用途 | 草案路径（**阶段 1 已落地项标注实际状态**） |
|---|---|
| 上游原始件（GLB + LICENSE.txt） | **已落地**：`docs/art/kaykit_route_ab/upstream/kaykit-adventurers-1.0-672074b/`，只增不改；目录名含版本 + commit 短号 |
| 预览 | **已落地**：`docs/art/kaykit_route_ab/previews/rogue_hooded_rest_3q_front.png` |
| 路线 A 运行资产 | `src/game/actors/swordsman/models/kaykit_<role>_a.glb` |
| 路线 B 上传源（静态单网格 T/A pose） | `docs/art/kaykit_route_ab/kaykit_<role>_static.obj`（`.fbx` 备用） |
| 路线 B Blender 工程 | `docs/art/kaykit_route_ab/kaykit_<role>_b.blend` |
| 路线 B 运行资产 | `src/game/actors/swordsman/models/kaykit_<role>_b.glb` |
| 表现层场景 | `src/game/actors/swordsman/kaykit_visual_route_{a,b}.tscn`（同节点名、同公开 API） |
| 台账 | `docs/art/kaykit_route_ab/asset_ledger.md`（三角形/骨骼/clip/sha256/来源/下载日期） |

`<role>` = **`rogue_hooded`**（阶段 1 实际选中结果）。**不得覆盖 C 的任何文件**（`cultivator_rigged.glb`、`cultivator_visual_rigged.tscn`、`cultivator_skeleton_presentation.gd` 及其 sha256 均保持不变，依据[探索资产保留](../../implemented/process/2026-09-18-exploration-asset-retention.md)）。

### 7. 两阶段实施边界

**阶段 1（资产落地，零运行时代码）——已完成**

1. 上游：codeload tar.gz 固定 commit 下到 `mktemp`，archive sha256 校验通过（`491cc136e9cd3a205c6d43bb16029d7dd4335906add718cb69300cc5755ab713`）；只把 `Rogue_Hooded.glb` 与 `LICENSE.txt` 原件复制入库，入 `docs/art/kaykit_route_ab/upstream/kaykit-adventurers-1.0-672074b/`（目录带版本 + commit 短号，未来版本不覆盖）。**其余 4 个角色、武器、重复 PNG、addon 包装一律未下载未入库**；未创建任何空运行资产。
2. 逐文件 sha256 与任务给定目标值一致：GLB `93e6e25213009952276d9cf34f5d96a243767334c66f280db0433ddfabb91545`、LICENSE `ae322141814056dda0deea7540d74c41d87aee1da319977cd1bd84ee5a923629`。
3. 只读核验（GLB JSON 直读 + Blender 5.2.1 无头导入交叉核对）：6,035 tris / 5,586 verts / 12 mesh / 41 bones / 76 clips / 1 material / 1 内嵌 1024² 贴图；rest 为 T-pose；足底 y≈0；**无手指骨**；`Rogue_Cape` 84 tris 刚体挂 `chest`。
4. 选角：按第 4 节门槛选中 **`Rogue_Hooded`**（对照表见上）。
5. 产物：台账 + 预览图；**`src/` 零改动、`mcp/` 零改动、现有 cultivator 资产零改动**。
6. **未核验项见台账 §5**（角色总高两种算法不一致待定案、是否与其他角色共用骨架、Godot 实际导入、clip 时长/in-place、draw call 实测）。

**阶段 2（运行时，前置 = 阶段 1 通过 + 使用者确认选角）**

1. 路线 A：`kaykit_visual_route_a.tscn` + 表现层节点，沿用 `CultivatorSkeletonPresentation` 的**公开 API 形状**（`auto_read_actor` / `actor_path` / `advance_state` / `sample_state` / `pose_state` / `reset_pose`），只做 clip 名映射；
2. 路线 B：到达 Mixamo marker 步**停住等人工**；完成后走与 A 相同的接线与验收；
3. 两路线接**同一个独立对照场景**，不覆写 `jade_paper_sample` 的现有引用；现有七项子实验与测试基线不得回归。

阶段 1 与阶段 2 之间不得跳步，也不得用"看起来能跑"代替选角门槛。

### 8. 证据分级（事实 / 推断 / 未核验）

**已核验事实**

- KayKit Adventurers `LICENSE.txt` 存在于固定 commit `672074b…` 内，原文含 CC0 声明、"personal, educational and commercial" 与署名非强制（本轮直接读取该文件）。
- 该 commit 的文件清单（jsDelivr API，72 个文件）：5 个角色 GLB（各约 3.6 MB）+ 4 张角色贴图 + 25+ 配件 gltf + `LICENSE.txt`。
- Godot 资产库 asset 2129：`cost=CC0`、`godot_version=4.1`、`download_provider=GitHub`、`download_commit=672074b73ba276876a19e8816ecdc5241817ab47`、`modify_date=2024-04-26`。
- 本仓现有动作契约与映射常量（`cultivator_skeleton_presentation.gd`）。
- **403 / 访问受阻**：`kaylousberg.itch.io/kaykit-adventurers` 返回 403 Cloudflare 挑战页；GitHub REST API 曾返回速率限制（改用 raw / jsDelivr 完成核验）；Kenney 与 OpenGameArt 的搜索页由前端渲染，HTML 内无结果条目。

**阶段 1 追加的已核验事实（`Rogue_Hooded`，GLB JSON 直读）**

- **76 clips 的口径已定案**：本文件 `animations.length = 76`，与仓库内 `3d-animation.md` 记录一致；Godot 资产库页写的 "75 animations" 是**该页口径**，不适用于本文件。`Idle`、`Walking_A/B/C`、`Running_A/B`、`Jump_*`、**`Hit_A`/`Hit_B`**、`Death_A/B` 均在。
- 骨架：41 bones = **23 变形骨 + 18 控制/IK 骨**；无手指骨。
- 朝向：脚尖朝 glTF **+Z**（作者 −Y 正面约定）；足底 y≈0；`Rig` 无缩放。
- 武器挂件 5 个（2,030 tris）也在文件内，阶段 2 需显式隐藏或忽略。

**推断（有依据但未直接验证）**

- 单张贴图 → 单材质 → ≤2 draw calls 在结构上可行（需实机复核）。
- `Hit_A`/`Hit_B` 与 `Idle`/`Walking_*` 同 skin，推断可直接混用（未实测）。

**未核验**（阶段 1 后仍开放）

- **`Rogue_Hooded` 总高未定案**：GLB JSON 逐顶点蒙皮 AABB 给 2.2513 m，Blender 无头导入求值包围盒给 3.2357 m；两者不一致，需一次干净测量。
- 是否与同包其他 4 个角色共用同一骨架。
- 76 个 clip 的时长 / 首尾姿态 / 是否 in-place（**脚滑验收依赖此项**）。
- draw call 实机实测。
- Mixamo 条款中"下载资产随仓库再分发"的边界。
- 本工程 Godot 对该 GLB 的实际导入结果（含朝向 / 轴向 / 单位 / `baseColorFactor` 转换）。

## 备选方案

- **继续修 `cultivator_rigged`（补裙摆骨 + 重刷 89 岛权重）**：不作为本轮主线。它无法隔离"蒙皮问题 vs 动作库问题"，且难度与不确定性都更高；保留为基线 C，不是被否决。
- **只做路线 A、不做 B**：不采用。缺少同模型对照就无法把差异归因给动作管线，而 B 的全部意义正是隔离这一个变量。
- **直接换 Mixamo 角色库里的角色**：不采用。会把模型与动作管线一起换掉，变量无法隔离；Mixamo 还有独立的可用性边界。
- **换成 Quaternius 模块化三件套（UBC + MCOF + UAL2）**：本轮排除。不是质量否决，是许可口径冲突（pack 页 CC0 vs 现行 QAL v1.0 再分发条款）与本仓资产入 Git 规则冲突；口径澄清后可重议。
- **AI 生成一个新角色再绑骨**：不采用。会引入第三个变量（造型质量），而当前要回答的是动作管线问题。
- **把 5 个免费角色全部导入后逐个试**：不采用。先按门槛选一个，避免资产膨胀与对照歧义。
- **换引擎或换渲染路线**：不采用。与本议题无关，只会扩大变量。

## 验收标准

前置：A 与 B 使用**同一角色（同一底层网格）**、同一相机模式与参数、同一状态映射常量（`WALK_SPEED_MPS=0.3` / `RUN_SPEED_MPS=5.5` / `walk_stride=1.6` / `run_stride=3.2` / `BLEND=0.15`，沿用 [cultivator_skeleton_presentation.gd](../../../src/game/actors/swordsman/cultivator_skeleton_presentation.gd) 现值），**禁止只为其中一条路线调阈值**。

### A/B 可观察验收矩阵

| # | 观察项 | 判定方式（可操作） | 证据 |
|---|---|---|---|
| 1 | 脚滑 | 固定速度直线走/跑各 5 m，侧视录制；脚掌着地相位的水平位移与地面参照物比对，明显滑移判不合格 | 视频 |
| 2 | 手腕/肘肩 | 静止与行走各取正、侧两视角；腕部是否跟随手骨、肘肩转折是否穿模或反折 | 截图 ×2 视角 |
| 3 | 裙/披风穿插 | 跑动 + 急转向；袍摆与腿/躯干是否互穿，是否被拉成长条 | 视频 |
| 4 | 轮廓 | 近/中/远三距离同机位；剪影可辨、无细碎毛刺 | 截图 ×3 |
| 5 | 材质 | 同光照下底色/受光是否接近青玉纸白色卡、是否被导入转换洗白 | 截图 + 线性读数 |
| 6 | 面数 | 单角色 ≤ **40,000 tris**（只读 GLB JSON 读数） | 台账数字 |
| 7 | draw call | 单角色 ≤ **2**（先按网格 primitive 数 × 材质数给基础读数，再用实机渲染统计复核） | 台账 + 实机统计 |

### 其它验收条件

1. `python3 tools/verify/run_all.py --with-tests` 全绿；`verify-notes-format` 对本 note 通过。
2. **资产保留**：C 的 `cultivator_rigged.glb` sha256 不变；旧资产零删除零覆盖（[探索资产保留](../../implemented/process/2026-09-18-exploration-asset-retention.md)）。
3. **许可留证**：KayKit `LICENSE.txt` 原件 + 仓库 URL + commit SHA + 下载日期入 `docs/art/kaykit_route_ab/`。
4. **人工门留痕**：路线 B 的 Mixamo marker 步由使用者完成，报告须明确写出"已停住等待使用者"或"使用者已完成"，禁止代填或假称。
5. **结论归属**：自动化检查通过 ≠ 审美通过；使用者视觉确认前，不得宣称 A 或 B 胜出。

## 风险

- **审计读数未落盘**：89 岛 / 13,032 顶点 / 976 腕高点 / 无裙摆骨四项来自本轮只读审计，需主代理抽查后才是最终结论；若抽查不成立，"为何不继续修当前模型"一节必须重写。
- ~~**选角可能全部不达标**~~：**已解除**（阶段 1 选中 `Rogue_Hooded`，唯一披风仅 84 tris 刚体片）。
- **风格差距**：KayKit 是西幻冒险者，与"国风修仙"的距离只能靠改色与后续改造逼近；剪影不合适属于硬伤，改色救不回来。
- ~~**动作清单口径不一**~~：**已解除**（阶段 1 定案本文件 76 clips，`Hit_A`/`Hit_B`/`Death_A`/`Death_B` 内置，无需外部来源）。
- **路线 B 阻塞**：依赖 Mixamo 的人工环节与持久登录态；登录失效或页面改版会阻塞 B，此时 A 仍可独立推进。
- **B 的许可未闭环**：Mixamo 资产随仓库再分发的边界未核验，可能影响 B 能否最终封板。
- **长袍可能依旧不自然**：两条路线都不含布料模拟，裙摆只能靠骨链或权重近似；A/B 只回答"哪条动作管线的观感更好"，不回答"能否达到布料级"。
- **仓库体量**：单角色 GLB 约 3.6 MB，上游原样保留 + A/B 两份运行资产会推高仓库体积；按保留纪律不得删旧版本。阶段 1 已只拉 1 个角色（未拉其余 4 个、配件与重复 PNG）。
