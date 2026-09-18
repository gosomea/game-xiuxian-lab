# 资产台账 · sword_flight_course（御剑飞行训练场「云路玉环」）

按 [mcp-blender skill](../../../skills/mcp-blender/SKILL.md) 的登记纪律：来源、许可结论、日期。
生成方式：**AI 代理编写脚本，经 Blender 5.2.1 LTS 程序建模**；未调用图像/3D 生成服务，无下载资产。

| 字段 | 值 |
|---|---|
| 资产名 | `sword_flight_course`（浮空玉环门 ×5、云阶 ×3、落剑台 ×2、起飞坪、悬停光柱、悬浮石 ×5、远山剪影 ×4） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS（2026-08-25 构建）程序建模；无第三方素材 |
| 生成脚本 | `tools/art/generate_sword_flight_course.py` |
| 源文件 | `docs/art/sword_flight_course/sword_flight_course.blend`（60 个可编辑分件） |
| 运行输出 | `src/levels/experiments/character_movement/sword_flight_course.glb`、`..._collision.json` |
| 预览 | `course_preview_{overview,takeoff,gates,hover,landing}.png`（Cycles 24 采样 + 降噪，960×640；surface_clearance 修复后重渲） |
| 预览的旧版本（保留） | `course_preview_{overview,takeoff,gates,hover,landing}_pre_surface_clearance.png`（修复前原字节副本，见下节"共面闪烁修复"） |
| 净空报告 | `docs/art/sword_flight_course/surface_clearance_report.json`（生成器导出后自检输出，11 对全部 ok / 0 对未登记共面） |
| 上一版自动备份 | `docs/art/sword_flight_course/sword_flight_course.blend1`（本次生成过程中由 Blender 覆盖保存产生，见下节登记） |
| 生成日期 | 2026-09-18 |
| 第三方素材 / 许可依赖 | 无；唯一外部依赖是 Blender 自带 Python |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明。 |
| 生成方式声明 | AI 代理编写脚本，Blender 程序建模；未调用图像/3D 生成服务。 |
| 导出器 | Khronos glTF Blender I/O（Blender 5.2.1 自带），`export_yup=True` |
| 可复现性 | 固定种子（`random.Random(stable_seed(name))`）；同一 Blender 版本可复现 |

## 单一真源：几何与碰撞同源

生成器在**同一份数值**上同时建几何与写碰撞/路线 JSON（`sword_flight_course_collision.json`，
schema `sword_flight_course_collision/1`），因此不存在"视觉在此、碰撞在彼"的漂移：

| 类别 | 数量 | 说明 |
|---|---|---|
| 可碰撞件（`colliders`） | 86 | 起飞坪 1、云阶 3、落剑台 2、玉环环体 80（5 门 × 16 块） |
| 纯视觉件（`visual_only`） | 49 | 发光带、系挂件、光柱、悬浮石、远山剪影、落点围边与旗 |
| 玉环环体 | 80 块 | 沿圆周排布，块间距 < 角色胶囊直径，**不能从环壁缝隙钻过** |
| 路线判据 | JSON | 门心 / 朝向 / 半径、悬停区中心 / 半径 / 秒数、落点中心 / 台面高 / 半径 |

Godot 侧只读该 JSON 装配 `CourseCollision`，验收脚本逐项核对"每个 collider 都有同名场景节点"
与"纯视觉件未被登记为碰撞体"，两条机械检查都在 playtest 中执行。

## 数值（2026-09-18 surface_clearance 修复后最终读数）

| 产物 | 字节 | sha256 |
|---|---|---|
| `sword_flight_course.glb` | 614448 | `a120cfc7b0d3d6bf79f0fc80f1fb1f99c05538f2e27cc9b53a82456278080880` |
| `sword_flight_course_collision.json` | 20885 | `a59f67f70d025fdb605437974b1965ac2ac968cb00c346173e84eb2101c54cb7`（**未变**，路线契约原样） |
| `sword_flight_course.blend` | 151717 | `dba58e7f328ba03ff5a5a2b398476d12ac5630ed9034c07ef7205ef86f2c1669` |
| `sword_flight_course.blend1` | 154219 | `b8075afb5839a401cdc2648eabfe2354fb0cd5f46bf7cedf3346c2eb38887279` |
| `pre_surface_clearance_sword_flight_course.blend`（修复前源，库内归档） | 151526 | `f93f20667f46864573b69842308dee8894c970461fb9b97d3451a72efbe44ea7` |
| `pre_surface_clearance_sword_flight_course.glb`（修复前导出，库内归档） | 614444 | `befddc04bd06cab254a91cccd1d271b1f8930ef276d9c9f23e87543bba3d6a3e` |
| `surface_clearance_report.json` | 2532 | `126bd196b9cc22582959b6020a38afac2f8556f7320b76ca75d2ee122767cd37` |
| `course_preview_overview_pre_surface_clearance.png` | 635310 | `a102cd00213f76b8e0e19deabd8c0e44fa2ecda371c5abf43c556d4f06f7122f` |
| `course_preview_takeoff_pre_surface_clearance.png` | 611182 | `16bd751160586d549bdcee19525313b05d710f4b19d13cdf10eaf71571b1aa96` |
| `course_preview_gates_pre_surface_clearance.png` | 604212 | `b13c4ab80ff0cf5317e4c784c2b193fbea9095bd0670872d2e901390e7b12a78` |
| `course_preview_hover_pre_surface_clearance.png` | 614504 | `0ab9c799d9667d03f1c293653fbdded95f35463076c62af38b755b8210b6588b` |
| `course_preview_landing_pre_surface_clearance.png` | 592330 | `5d5fc5421db89ff7670c650448ec7ad3db4ac145c251f2ecb7a92b4ef7c0948e` |
| `course_preview_{overview,takeoff,gates,hover,landing}.png`（修复后重渲） | 640646 / 614006 / 597645 / 605358 / 594484 | `0e36f8a1…` / `916f041d…` / `0b4ce6fc…` / `3c5b702a…` / `302b41f1…` |

生成读数：`COURSE ok objects=60 tris=7320 colliders=86 visual_only=49`（网格数与碰撞盒数未变）。
共面复核：`COURSE glb_coplanar_unregistered=0`；净空自检 11 对全部 OK（报告 `result=ok`）。

修复前旧值（对照，已按旧字节另存为库内归档 `pre_surface_clearance_sword_flight_course.blend` /
`.glb`，与 `0d1dc64` 引入的旧字节逐字节一致）：GLB 614444 / `befddc04…`，collision JSON 同上，
.blend 151526 / `f93f2066…`。**基线提交是 `0d1dc64`（Add movement terrain flight and transition courses）**；
`0ba531f` 只是新增 note 的提交，不引入这两个资产，不能用它取回修复前字节。旧 GLB 在修复前扫描出 7 对零间隙共面（`landing_far↔landing_far_rim` 71.34 m²、
`landing_near↔landing_near_rim` 36.03 m²、`step_*↔step_*_lip` 7.95–10.21 m²、`takeoff_mark*` 各 5.20 m²）。

## 共面闪烁修复（surface_clearance，2026-09-18）

**原因**：平台主体与 rim / lip / mark 之间零间隙共面——生成器把装饰层中心写成"承托面顶 + 自身半高"，
使装饰层底面**严格等于**承托面顶面；叠加 9 个材质全部双面（`doubleSided=true`）与正交跟随相机移动时的
深度重采样，产生地面随镜头移动的闪面。决策依据：
`notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md`，并沿用本仓已验证的
mountain_realm「装饰面高出承载面 2 cm」约定（`docs/art/mountain_realm/asset_ledger.md`）。

**变更**（全部在 `tools/art/generate_sword_flight_course.py`，禁止手改 GLB）：

| 类 | 件 | 修复前 | 修复后 |
|---|---|---|---|
| A | `takeoff_mark` / `takeoff_mark_cross` → 坪顶 | 底面 = 坪顶（gap 0） | 底面 = 坪顶 + `CLEARANCE`(0.02)，厚 0.06 |
| A | `step_*_lip` → 云阶顶 | 底面 = 阶顶（gap 0） | 底面 = 阶顶 + 0.02，厚 0.12（外观凸起 `+2 cm`） |
| A | `landing_*_rim` → 台面顶 | 底面 = 台顶（gap 0） | 底面 = 台顶 + 0.02，高 0.16 |
| A | `landing_*_mark` → 围边顶 | 底面 = 围边顶（gap 0） | 底面 = 围边顶 + 0.02（标记与围边不再共面） |
| B | `landing_*_pole`（旗杆，竖向件） | 底面 = 台顶（gap 0） | 底面下沉 `BURY_DEPTH`(0.005) 埋入台面，不抬升 |

路线、碰撞、尺寸与玩法判定**全部未动**：`sword_flight_course_collision.json` 字节与 sha256 与修复前完全一致；
网格数 60、三角面 7320、碰撞盒 86、纯视觉件 49 均未变；A 类抬升只改装饰件可见高度（2 cm 量级），
不改任何可走面与碰撞盒。相机参数、阴影、MSAA 未改。

**生成器自检（机械证据，随每次导出执行）**：导出前对 11 对"装饰件 → 承托件"检查世界高度间隙，
导出后用 `glb_node_spans`（按 glTF Y-up 高度轴、支持 TRS/matrix 变换）复核同一张表，
并对全 GLB 扫描"间隙 ≤1.5 mm 且水平重叠 ≥0.05 m²"的未登记共面。任一不满足即 `SystemExit` 拒绝产物，
失败输出带 `fix=tools/art/generate_sword_flight_course.py ...`。本次结果：11/11 pair gap `+0.0200 m`（旗杆 `-0.0050 m`），
未登记共面 **0 对**，`surface_clearance_report.json` `result=ok`。

**口径限制（不得扩写）**：扫描器 `glb_coplanar_hits` 当前只检 **support 的 top ↔ child 的 bottom**
这一种共面方向；`unregistered=0` 只代表该口径无命中，**不代表 top/top、bottom/bottom 共面全为 0**。
允许项：同材质十字标记 `takeoff_mark` 与 `takeoff_mark_cross` 的 **top/top 交叠**（同为 `Gate glow`
材质、同一水平面、十字交叉处重叠），列为**允许/限制项**，不属未登记冲突；如需覆盖其余方向，
须先扩展扫描器与允许清单，再更新本结论。

**生成命令**（仓库根；原始日志在 `~/.cache/game-xiuxian-lab/surface-clearance/sword-flight/`，不入 Git）：

```
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python tools/art/generate_sword_flight_course.py -- course     # .glb + collision.json + .blend + 报告
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python tools/art/generate_sword_flight_course.py -- preview    # 重渲 5 张预览
```

**旧资产保留**：修复前 5 张预览已按**原字节**另存为 `course_preview_*_pre_surface_clearance.png`
（校验：与修复前 `course_preview_*` 的 sha256 逐一相同，见上表）；修复前的 `.blend` 与 `.glb`
已用 `git show HEAD:<path>` 按旧字节另存为库内归档 `pre_surface_clearance_sword_flight_course.blend`
（151526 字节）与 `.glb`（614444 字节），逐字节等于 `0d1dc64` 引入的修复前资产。
导出后 LLM 又产生过一次覆盖，`.blend1` 因此记录为修复后中间态而非修复前状态——
**修复前源状态以库内 `pre_surface_clearance_*` 归档为准**（`0ba531f` 只是 note 提交，取不到修复前字节）。
未删除任何旧资产。

## 路线（与 JSON 同源，此处仅为可读摘要）

| 玉环门 | 位置 (x, y, z) | 朝向 yaw | 半径 |
|---|---|---|---|
| `gate_1` 初启 | (0.0, 5.0, -2.0) | 0° | 2.40 |
| `gate_2` 升云 | (6.5, 9.0, -12.0) | 35° | 2.30 |
| `gate_3` 揽月 | (16.5, 13.0, -16.5) | 80° | 2.10 |
| `gate_4` 穿隙 | (32.0, 11.0, -10.0) | 130° | 1.80（最窄） |
| `gate_5` 回风 | (34.0, 7.5, 2.0) | 176° | 2.10 |

悬停区：中心 (30.0, 8.0, 7.0)、半径 3.4 m、**2.5 s**（位于末门与落点之间的自然航路上）。
落点：`landing_near` 台面 4.5 m（近而高，需控下降）／`landing_far` 台面 0.8 m（远而稳，低平宽大）。

## 版本与保留规则（探索资产）

本资产当前**只有一个版本**：`sword_flight_course.blend`（主源文件）+ `sword_flight_course.glb`，
二者是同一原模型的源与导出，不存在第二个独立版本。规则：

| 情形 | 处置 |
|---|---|
| **在同一原模型上继续修改**（调形状、挪位置、改材质） | 允许更新主 `*.blend` 与对应 `*.glb`，并在本台账「数值」表更新字节与 sha256，注明修改点。 |
| **另存为新版本或形成独立探索版本**（重做一版航线、换方案、A/B 对比） | 必须**另存文件名或版本目录**（例如 `sword_flight_course_v2.blend` / `docs/art/sword_flight_course_v2/`），并把该版本及其 `.glb` 一并纳入 Git；**不得覆盖**旧版本。 |
| 被替代的旧版本 | 保留在库并可连同依赖归档，维护引用与替代关系；Git 历史不能替代旧源文件与导出资产的保留。 |
| **Blender 覆盖保存产生的 `*.blend1`** | 它保存覆盖前那一刻的**可编辑源状态**，属于探索资产：必须**保留并纳入 Git**，并在本台账登记（文件名 + 产生时机）。**不得当作缓存删除**，也不得用忽略规则排除。 |
| 本次产生的 `sword_flight_course.blend1` | **已保留并入库**：154219 字节 / `b8075afb…`。产生时机为 2026-09-18 surface_clearance 修复的**第二次** `--course` 覆盖保存：它是修复后几何 + 预览相机/灯光的 `.blend` 状态（第一次覆盖保存的上一版 151700 字节状态已被下一次覆盖轮换掉）。 |
| 引擎导入缓存与临时运行日志 | 不属于源资产或交付资产，可不入库。 |

**本节原写"本目录当前不存在任何 `.blend1`"（2026-09-18 首次导出时）；现已不成立**：
surface_clearance 修复过程中发生多次覆盖保存，当前存在 `sword_flight_course.blend1`（见上表第五行），
按规则保留、入库、登记，不得清理。修复前的源状态由库内归档 `pre_surface_clearance_sword_flight_course.blend`（151526 字节）
保留，逐字节等于 `0d1dc64` 引入的旧资产（`0ba531f` 仅新增 note，不含该旧字节）；修复前的导出 GLB
为同目录归档 `pre_surface_clearance_sword_flight_course.glb`（614444 字节）；修复前的预览图另有
`*_pre_surface_clearance.png` 原字节副本。

另存明确版本名（上表第二行）仍然是**独立方案**的正确做法：`.blend1` 只是自动的上一时刻快照，
不能替代"另存文件名或版本目录"所表达的方案分叉；两者并行遵守，不互相替代。

预览图在导出 GLB 之后单独渲染，不进 GLB。远山剪影与悬浮石是**纯视觉、无碰撞**，
不会在航线中制造隐形障碍。既有探索资产（庭院 / 群山 / 角色）未改动、未删除。
