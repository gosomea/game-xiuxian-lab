# 资产台账 · kaykit_route_ab

一句话：**路线 A/B 的共同上游源与派生物台账**——KayKit Adventurers 免费仓库固定 commit 里的 `Rogue_Hooded` 单角色原样入库；路线 B 另保存人工 marker 前的静态单网格 T-pose、Blender 源工程与真 T-pose 预览。

依据：[KayKit 同模型双路线 A/B note](../../../notes/proposed/art/2026-09-19-character-model-animation-route-comparison.md)。
上游源件只增不改；派生物按路线分目录保存。运行资产与 Godot 接线仍放在 `src/`，不与本目录混放。

## 1. 来源与获取

| 字段 | 值 |
|---|---|
| 作者 | Kay Lousberg（KayKit）· <https://www.kaylousberg.com> |
| 资产包 | KayKit — Adventurers Character Pack 1.0 |
| repo | <https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0> |
| commit（固定） | `672074b73ba276876a19e8816ecdc5241817ab47`（2023-09-16） |
| archive URL | `https://codeload.github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/tar.gz/672074b73ba276876a19e8816ecdc5241817ab47` |
| archive sha256 | `491cc136e9cd3a205c6d43bb16029d7dd4335906add718cb69300cc5755ab713`（6,095,702 bytes，`tar.gz`） |
| 下载日期 | 2026-09-19 |
| 下载方式 | `curl` 到 `mktemp` 临时目录，解包后只复制 2 个文件入库；临时目录不留在仓库 |
| Godot 资产库交叉核对 | asset 2129 的 `download_commit` 与本 commit 完全一致（`cost=CC0` / `godot_version=4.1` / `modify_date=2024-04-26`） |

> **archive 格式归一说明**：同一 commit 的 **zip** 端点返回 sha256 `00777a7b9811a7c7f8dd3fda4e56604f6a93b33673d64557153f354d677b47af`（6,147,593 bytes）；上文校验通过的 `491cc136…` 是 **tar.gz** 端点。两者内容等价、按格式取不同哈希，**不是**同一文件的两种说法。本台账只认已校验通过的 tar.gz 值。

## 2. 入库文件（逐文件）

目录含版本与 commit 短号，未来版本另起目录、不覆盖。

| 文件 | 来源路径（archive 内） | bytes | sha256 |
|---|---|---:|---|
| `upstream/kaykit-adventurers-1.0-672074b/Rogue_Hooded.glb` | `addons/kaykit_character_pack_adventures/Characters/gltf/Rogue_Hooded.glb` | 3,597,652 | `93e6e25213009952276d9cf34f5d96a243767334c66f280db0433ddfabb91545` |
| `upstream/kaykit-adventurers-1.0-672074b/LICENSE.txt` | `addons/kaykit_character_pack_adventures/LICENSE.txt` | 891 | `ae322141814056dda0deea7540d74c41d87aee1da319977cd1bd84ee5a923629` |

两个 sha256 与本轮任务给定的目标值**逐字一致**。

**预览（本仓生成，非上游）——中性静止预览，非 T-pose 验收证据**

| 文件 | 内容 | bytes | sha256 |
|---|---|---:|---|
| `previews/rogue_hooded_rest_3q_front.png` | 选中角色的**中性静止姿态**（双臂自然下垂，**不是水平 T-pose**），正面偏侧 3/4（方位角 35°、俯仰 6°），透明背景，1024×1024 RGBA | 499,652 | `5c31ed41c943bb631fc46463a480011435123bbf0cdad4baef942ba8231018fc` |

> **这张 PNG 的用途与边界**：它**只用于选角辨识**（确认轮廓、兜帽与披风形态、配色）。图中双臂下垂，**不得把它当作 T-pose 或 rest pose 的视觉证据**，也不得据此判断 rest 姿态手臂是否水平。
>
> **真正的 T-pose 结论来自只读结构核验**，即 §3「骨架与姿态」表中由 GLB JSON 直接读出的骨架 rest 坐标（`upperarm.l` → `hand.l` 的 **ΔY = 0.0000**，手臂水平），与本文中名为 `T-Pose` 的 clip。渲染图与该结论无关。
>
> **文件名保留说明**：文件名中的 `rest` 字样是产出时的既有命名。按探索资产保留纪律，**文件名不得删除或覆盖或重命名**；以本条文字描述为准。

生成方式：Blender 5.2.1（`/Applications/Blender.app`）无头，`--factory-startup`，临时工程与输出全部在 `/tmp`，**源 GLB 只读、未被改写**（入库 GLB 的 sha256 与上游一致即为证据）。渲染时隐藏 5 个武器网格（`Knife` / `Knife_Offhand` / `1H_Crossbow` / `2H_Crossbow` / `Throwable`），只留角色本体；`film_transparent` + RGBA 输出。

## 3. 只读核验读数（GLB JSON 直读 + Blender 导入交叉核对）

全量解析 `Rogue_Hooded.glb` 的 JSON chunk 与 BIN chunk，逐 accessor 统计。

| 指标 | 读数 | 核验方式 |
|---|---|---|
| 三角形 | **6,035** | 12 个 mesh 的 `indices` count / 3 求和 |
| 顶点 | **5,586** | 12 个 mesh 的 `POSITION` accessor count 求和 |
| mesh 数 | **12** | `meshes.length` |
| 骨骼数 | **41** | `skins[0].joints.length`；Blender 独立导入为 41 根（一致） |
| clip 数 | **76** | `animations.length`；Blender 导入 76 个 action（一致） |
| 材质数 | **1** | `materials.length` = `rogue_texture`，`metallicFactor=0` / `roughnessFactor=0.5` / `doubleSided=true` |
| 贴图数 | **1**（内嵌） | `images[0]` = `rogue_texture`，PNG 1024×1024，16,670 bytes，`bufferView=6`（**内嵌在 GLB 内，无外部依赖**） |
| 文件字节 | 3,597,652 | 与 `buffers[0].byteLength`=1,628,204 + JSON chunk 自洽 |
| glTF 版本 | 2.0 | `asset.version`；生成器 `Khronos glTF Blender I/O v1.7.33` |
| 场景根 | 1 个节点 `Rig` | `scenes[0].nodes` |

**骨架与姿态**

| 项 | 读数 |
|---|---|
| skin 名 | `Rig`（`skins[0].name`） |
| 变形骨 | 23 根：`root / hips / spine / chest / upperarm.l·r / lowerarm.l·r / wrist.l·r / hand.l·r / handslot.l·r / head / upperleg.l·r / lowerleg.l·r / foot.l·r / toes.l·r` |
| 控制/IK 骨 | 18 根：`kneeIK.* / control-toe-roll.* / control-heel-roll.* / control-foot-roll.* / heelIK.* / IK-foot.* / IK-toe.* / elbowIK.* / handIK.*`（**不含手指**） |
| rest 姿态 | **T-pose**：`upperarm.l`(0.2120, 1.1068, 0) → `hand.l`(0.7870, 1.1068, 0)，ΔX=0.5750 / **ΔY=0.0000**（手臂水平）；文件中另有名为 `T-Pose` 的 clip（123 通道） |
| 朝向轴 | 脚尖朝 glTF **+Z**：`toes.l` Z − `foot.l` Z = **+0.1150**；即 Blender 制作者的 **−Y 为正面**约定 |
| 足底 | `min Y = −0.000027` ≈ **0**（角色本体，不含武器） |
| 单位/比例 | 米制；`Rig` 节点无缩放变换 |

**长袍/披风（本轮选角的关键项）**

| 项 | 读数 |
|---|---|
| `Rogue_Cape` 三角形 | **84**（`Plane.007`） |
| 父节点 | `chest` → `spine` → `hips` → `root` → `Rig` |
| 蒙皮 | **无**（`skin` 未设置）；顶点属性只有 `POSITION / NORMAL / TEXCOORD_0`，**没有 `JOINTS_0`/`WEIGHTS_0`** → 刚体片，整体跟随 `chest` |
| 单片几何范围（rest，世界） | min [−0.485, 0.094, −0.386] → max [0.485, 1.236, −0.044] |
| 判定 | 反向印证选角门槛：**无超大袍片**——披风仅 84 tris、单片、无次级骨、无布料，与"人物与衣服分开"的既有近似同源，不会引入新的蒙皮变量 |

**12 个 mesh 明细（verts / tris）**

| # | 名称 | verts | tris | 绑定 |
|---:|---|---:|---:|---|
| 0 | `Cube.199`（= `Rogue_ArmLeft`） | 440 | 580 | skinned |
| 1 | `Cylinder.002`（= `Knife_Offhand`） | 207 | 172 | 刚体，手部挂点 |
| 2 | `Cube.015`（= `1H_Crossbow`） | 678 | 584 | 刚体，手部挂点 |
| 3 | `Cube.004`（= `2H_Crossbow`） | 942 | 792 | 刚体，手部挂点 |
| 4 | `Cylinder.008`（= `Knife`） | 207 | 172 | 刚体，手部挂点 |
| 5 | `Cylinder.006`（= `Throwable`） | 300 | 310 | 刚体，手部挂点 |
| 6 | `Plane.007`（= `Rogue_Cape`） | 56 | 84 | 刚体，挂 `chest` |
| 7 | `Cube.202`（= `Rogue_ArmRight`） | 440 | 580 | skinned |
| 8 | `PrototypePete_body.025`（= `Rogue_Body`） | 1,124 | 1,172 | skinned |
| 9 | `Cube.12634`（= `Rogue_Head_Hooded`） | 592 | 773 | skinned |
| 10 | `Cube.194`（= `Rogue_LegLeft`） | 300 | 408 | skinned |
| 11 | `Cube.187`（= `Rogue_LegRight`） | 300 | 408 | skinned |

> 12 个 mesh 中 **5 个是武器挂件**（mesh 1–5，合计 2,030 tris），角色本体为 7 个 mesh / **4,005 tris**。武器是文件自带的展示用挂件，本仓未单独入库、未修改。

**76 个 clip 中与路线 A 直接相关的动作**（完整 76 条以 GLB `animations[].name` 为准）

| 类别 | clip |
|---|---|
| Idle | `Idle` / `Unarmed_Idle` / `2H_Melee_Idle` / `Jump_Idle` / `Sit_Chair_Idle` / `Sit_Floor_Idle` / `Lie_Idle` |
| 走 | `Walking_A` / `Walking_B` / `Walking_C` / `Walking_Backwards` |
| 跑 | `Running_A` / `Running_B` / `Running_Strafe_Left` / `Running_Strafe_Right` |
| 跳 | `Jump_Start` / `Jump_Idle` / `Jump_Land` / `Jump_Full_Short` / `Jump_Full_Long` |
| 受击（路线 A 白拿的扩展项） | **`Hit_A` / `Hit_B`** |
| 死亡 | `Death_A` / `Death_A_Pose` / `Death_B` / `Death_B_Pose` |
| 攻击 | `1H_Melee_Attack_Chop` / `_Slice_Diagonal` / `_Slice_Horizontal` / `_Stab`；`2H_Melee_Attack_*`；`Dualwield_Melee_Attack_*`；`Unarmed_Melee_Attack_*` |
| 法术 | `Spellcast_Long` / `Spellcast_Raise` / `Spellcast_Shoot` / `Spellcasting` |
| 防御/位移 | `Block` / `Blocking` / `Block_Attack` / `Block_Hit`；`Dodge_Forward/Backward/Left/Right` |
| 基准 | `T-Pose` |

对照既有运行契约 `clips=[idle, walk, run, jump]`（[cultivator_skeleton_presentation.gd](../../../src/game/actors/swordsman/cultivator_skeleton_presentation.gd)）：名为 `Idle` 的 clip 存在；**Route A 需要一个"名字映射"到 `idle/walk/run/jump`，并需在四类里各选一条**（`Walking_A/B/C`、`Running_A/B`、`Jump_*` 共 5 条候选）。这属于阶段 2 的接线决策，本阶段不做。

## 4. 许可证

**原件**：`upstream/kaykit-adventurers-1.0-672074b/LICENSE.txt`（891 bytes，sha256 见 §2）。

原文摘要（逐句照录该文件）：

> `KayKit : Adventurers Character Pack (1.0)`
> `Created/distributed by Kay Lousberg (www.kaylousberg.com)`
> `Creation date: 13/03/2023 09:00`
> `License: (Creative Commons Zero, CC0)`
> `http://creativecommons.org/publicdomain/zero/1.0/`
> `This content is free to use in personal, educational and commercial projects.`
> `Support me by using a brand resource provided in this pack or by crediting Kay Lousberg, www.kaylousberg.com (this is not mandatory)`

| 边界 | 结论 |
|---|---|
| 商用 | **允许**（原文 "commercial projects"） |
| 修改 | **允许**——CC0 授予全部权利，含改造与再发布 |
| 署名 | **非强制**（原文 "not mandatory"）；本仓仍保留 LICENSE.txt 与作者信息 |
| 再分发 | **CC0 不禁**（含以资产形式）；因此与本仓"所有资产必须进入 Git"不冲突 |
| 与本 note 的口径一致性 | 与 proposed note §5「KayKit 官方 `LICENSE.txt`：CC0，个人/教育/商业可用，署名非强制」完全一致 |

> 上游还有 EXTRA / SOURCE 付费档；本目录**只含免费档文件**，未混入任何付费档内容。`kaylousberg.itch.io` 本轮未访问（历史访问返回 403 Cloudflare 挑战页），付费档边界仍未核验。

## 5. 未核验项（不得当作已确认）

1. **角色总高**：两种只读算法结果不一致——GLB JSON 的逐顶点蒙皮 AABB 给出 2.2513 m，Blender 无头导入的求值包围盒给出 3.2357 m。渲染目视为正常 Q 版比例。**总高未定案**，需要主代理用一次干净的测量确认；已确认的只有"足底 y≈0"与"直立"。
2. **`Rogue_Hooded` 与其他 4 个免费角色是否共用同一骨架**：未核验（关系到能否直接复用同包的其他角色做换装或敌役）。
3. **本工程 Godot 4.x 的实际导入结果**：未做导入测试（`src/` 阶段 1 零改动）。朝向、轴向、材质导入转换、`baseColorFactor` 行为均未实测。历史台账里"Godot 导入器把 glTF `baseColorFactor` 做 linear→sRGB 转换"的坑对本文件是否成立，未验证。
4. **76 个 clip 的时长/首尾姿态/是否 in-place**：只读了名称与通道数（123/123 常见），未逐条检查位移轨道与循环性。**脚滑验收依赖这一项**。
5. **draw call 实测**：结构上 1 材质 + 12 mesh（角色本体 7 mesh），但 Godot 实际合批结果未实测。proposed note 的 `≤2 draw calls` 目标未验证。
6. **`Hit_A`/`Hit_B` 是否与 `Idle`/`Walking_*` 同一骨架、能否直接混用**：未核验（同文件同 skin，推断可混用，但未实测）。
7. **贴图色彩空间与色卡适配**：`rogue_texture` 是绿色系渐变图集，与青玉纸白色卡的距离未评估（属阶段 2 美术判断）。

## 6. 与旧资产的关系

| 本目录资产 | 关系 | 旧资产状态 |
|---|---|---|
| `upstream/kaykit-adventurers-1.0-672074b/*` | 全新上游源件，**不替代任何现有资产** | `cultivator.glb` / `cultivator_jade.glb` / `cultivator_rigged.glb` 及其 .blend/.obj 原样保留，sha256 未变 |
| `previews/rogue_hooded_rest_3q_front.png` | 本仓生成的新预览 | 无替代关系 |

依据[探索资产保留](../../../notes/implemented/process/2026-09-18-exploration-asset-retention.md)：本轮零删除、零覆盖，新资产全部新文件名/新目录。

## 7. 阶段状态

- **阶段 1（本台账覆盖）**：上游最小集入库 + 只读核验 + 预览 → **已完成**。
- **阶段 2（进行中）**：路线 B 的 Mixamo 人工 marker 前准备已完成（见 §8）；路线 A 的运行资产/表现层、路线 B 的上传绑骨、A/B 对照场景及实机观感验收仍未完成。
- proposed note 的 Status 保持 **proposed**：准备资产就位不等于双路线运行时与人工验收已落地。

## 8. 路线 B：Mixamo 人工 marker 前准备（2026-09-19）

路线 B 使用与 A 完全相同的 `Rogue_Hooded.glb`，先在 Blender 中清除 76 个 action/NLA、原骨架、武器与权重，再把 6 个人体分件合并为静态单网格真 T-pose。该阶段**停在 Mixamo 上传/人工 marker 之前**，没有启动浏览器、上传角色或下载动作。

| 项 | 结果 |
|---|---|
| 脚本 | `mcp/mixamo/kaykit_route_b_prepare.py` |
| 输出目录 | `route_b/`；完整逐文件 bytes/sha256 见 `route_b/prepare_manifest.json` |
| 上传首选 | `route_b/rogue_hooded_static.fbx`，1 mesh / 0 armature / 0 action，3,196 verts / 3,921 tris |
| 上传备选 | `route_b/rogue_hooded_static.obj` + `.mtl` + 1024² PNG |
| 源工程 | `route_b/rogue_hooded_route_b_source.blend` |
| 姿势与尺度 | `upperarm.l` 距水平 0.000°；高 2.2513 m；足底 z≈0；面向 −Y |
| 二次导入 | FBX 与 OBJ 均复核为 1 mesh / 0 armature / 0 action、3,921 tris、1 UV、1 material |
| 披风 | 不进入自动绑骨网格；84 tris 原件保存在 `.blend` 的 `cape_preserved/Rogue_Cape_PRESERVED`，解除父子关系前后世界包围盒最大漂移 0.0 m；绑骨后人工映射并刚性挂到 Mixamo 等效胸骨 |
| 武器 | 5 件、合计 2,030 tris，从上传网格移除；上游 GLB 原件未改 |

人工 marker 为硬门：下巴、双腕、胯部、双踝必须由使用者在 Mixamo 页面拖放；胯部因衣摆遮挡是唯一高风险点，应从侧/后方确认双腿真实间隙。详见 `route_b/README.md`。

本阶段新增文件均为新路径；上游 GLB、既有中性预览与 `cultivator*` 基线资产均未覆盖或删除。Blender 的 FBX、`.blend` 与 PNG 写出会携带会话级元数据，因此跨会话 sha256 不作为稳定生成契约；**本轮提交中每个派生物的精确哈希以 `route_b/prepare_manifest.json` 为准**。
