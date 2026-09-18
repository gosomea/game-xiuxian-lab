# 资产台账 · ground_contact_course（地形接触训练场）

按 [mcp-blender skill](../../../skills/mcp-blender/SKILL.md) 的登记纪律：来源、许可结论、日期。
生成方式：**AI 代理编写脚本，经 Blender 5.2.1 LTS 程序建模**；未调用图像/3D 生成服务，无下载资产。

| 字段 | 值 |
|---|---|
| 资产名 | `ground_contact_course`（地形接触训练场：坡道、台阶、墙角、窄路、边缘台与山门轮廓） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS（2026-08-25 构建）程序建模；无第三方素材 |
| 生成脚本 | `tools/art/generate_ground_contact_course.py` |
| 尺寸真源 | `src/levels/experiments/character_movement/ground_contact_course_layout.json` |
| 源文件 | `docs/art/ground_contact_course/ground_contact_course.blend`（218 个可编辑分件） |
| 源文件 · 上一版自动备份 | `docs/art/ground_contact_course/ground_contact_course.blend1`（Blender 自动备份，218 个可编辑分件；**必须保留，不得清理**，见下节） |
| 运行输出 | `src/levels/experiments/character_movement/ground_contact_course.glb` |
| 预览 | `preview_{overview,ramps,steps,corner_narrow,edge_void}.png`（Cycles 16 采样 + 降噪，960×620） |
| 生成日期 | 2026-09-18 |
| 第三方素材 / 许可依赖 | 无；唯一外部依赖是 Blender 自带 Python |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明。 |
| 生成方式声明 | AI 代理编写脚本，Blender 程序建模；未调用图像/3D 生成服务。 |
| 导出器 | Khronos glTF Blender I/O（Blender 5.2.1 自带），`export_yup=True` |
| 可复现性 | 完全确定性：无随机种子依赖（竹丛用 `random.Random(1709 + 名字字符和)`），同一 Blender 版本可复现 |

## 源资产的保留：`.blend` 与 `.blend1`（**不得清理**）

`ground_contact_course.blend1` 是 Blender 在保存时自动生成的**上一版源文件备份**，不是临时文件、
不是缓存、也不可从 `.blend` 重新导出得到——它保存的是**另一时刻的可编辑源状态**。
因此按仓库的探索资产保留规则，它与主 `.blend` 一样属于必须进入 Git 并长期保留的源资产。

| 文件 | 角色 | 字节 | sha256 |
|---|---|---|---|
| `ground_contact_course.blend` | 当前源（218 分件） | 210123 | `f2e226f4b720566c9dcd519ac0c4187c37628e4350e29ad94c3c3809786a98d7` |
| `ground_contact_course.blend1` | **上一版自动备份 / 探索版本**（218 分件） | 209915 | `6c33087982126dfda61b2e77a1ee398392d74aa350cb324548dff7b23e10c32a` |

两者哈希不同，差异经实测已定位为**一处**：铺装主件的命名。
`.blend1` 里基线台主体网格仍叫 `flat_pad_paving`，主 `.blend` 里已改为装置 id 原名 `flat_pad`
（即上文「命名契约缺失」那次修正的前一版）。其余可核对项完全一致：分件数同为 218、
`ramp_gentle` 的竖直跨度同为 2.384 m（滚转修正已含在两者中）、`mist_00` 的 X 跨度同为 7.133 m。

处置要求：

- **不清理、不删除、不覆盖**，不得因「看起来是备份文件」而加入忽略规则或移出仓库。
- 不要用 Blender 重新保存主 `.blend` 来「顺带刷新」它；每次保存都会把当前 `.blend` 轮转进
  `.blend1`，会静默替换掉这份历史源状态。
- 台账在此登记其哈希与大小；若将来因继续在原模型上修改而生成新的上一版备份，
  按同一规则更新本表并保留旧记录可追溯的替代关系。

> 跨台账口径：[sword_flight_course 台账](../sword_flight_course/asset_ledger.md) 的「版本与保留规则」
> 与本节一致——`*.blend1` 保存覆盖前那一刻的可编辑源状态，属于探索资产，必须保留并纳入 Git、
> 不得当作缓存删除或用忽略规则排除。两份台账对 `.blend1` 的处置口径现已统一，无分歧。
>
> 该「尚未产生 `.blend1`」的说法已过期（2026-09-18 surface clearance 修复后）：
> sword 目录现存在 `sword_flight_course.blend1`（154219 字节 / `b8075afb…`），按同一规则保留、入库、
> 登记；本资产同样已产生 `.blend1`。两份台账口径一致，均按探索资产保留。

## 与物理的对应关系（本资产的核心契约）

训练场不追求「好看的场景」，而是**让看得见的装置就是走得上去的装置**。为此做了三件事：

1. **单一尺寸真源**：`ground_contact_course_layout.json` 的 `devices` 同时驱动
   Blender 可见几何与 Godot 碰撞盒。斜面用**同一套公式**推导
   （`run = slope_length·cosθ` 或直接给 `run_m/rise_m`；`rise = slope_length·sinθ`；
   斜面中心 = `base + (run/2, rise/2) − (t/2)·法线`），因此两面不是「照着做」而是同一个数学对象。
2. **同名节点**：每个装置的**主体可见网格用装置 id 原名**（如 `ramp_critical`、`step_050`），
   装饰件才带后缀（`_landing`、`_cap`、`_edge_1`）。碰撞体也用 id 命名。
   运行时 `find_child(id)` 能直接对上「那个装置」。
3. **机械对齐校验**：playtest 在装配批次里逐个装置比较「GLB 网格世界 AABB」与
   「碰撞盒世界 AABB」的关键尺寸（承重装置比顶面，墙比中心与高度量级），29 / 29 项通过。
   文字说明无法替代这一步——见下「本轮修掉的真缺陷」。

## 本轮修掉的真缺陷（记录根因，供后续资产复用）

1. **Blender 旋转轴换算写错**：`cbox(rotation_z=…)` 原本写成 `rotation_euler.z`，
   那是绕 Blender Z（= Godot Y 的**偏航**）而不是绕 Godot Z 的**滚转**。
   后果：四条斜面在 GLB 里全是「平放的斜纹板」，物理却按真斜面走——
   人能在看不见的坡上走上去。轴向换算正确写法是
   `Godot (x,y,z) → Blender (x,−z,y)`，故绕 Godot Z 转 θ ⇒ `rotation_euler.y = −θ`。
   **是 playtest 的可视/碰撞对齐检查抓到的**，不是靠看图。
2. **椭球尺寸当半长用**：`cblob` 里 ico_sphere 半径 1 对应全长 2，初版按全长写 scale，
   云雾与苔石整体放大一倍（云雾从 36.7 m 处伸出场外才暴露）。已改为 `size * 0.5` 并写明注释。
3. **命名契约缺失**：铺装主体最初叫 `flat_pad_paving`，导致 `find_child(id)` 找不到装置本体。
   已让主件直接用 id。

## 数值（2026-09-18 最终读数）

| 产物 | 字节 | sha256 |
|---|---|---|
| `ground_contact_course.glb` | 1254736 | `b823b141e04f0739f840d774e24d1cb0bf14e3c88376d621b245b4a46bb003a4` |
| `ground_contact_course.blend` | 210123 | `f2e226f4b720566c9dcd519ac0c4187c37628e4350e29ad94c3c3809786a98d7` |
| `ground_contact_course.blend1`（上一版源） | 209915 | `6c33087982126dfda61b2e77a1ee398392d74aa350cb324548dff7b23e10c32a` |
| `ground_contact_course_layout.json` | 11875 | `2031097455bfecf43bece8ec8f819818739470fabe5442bd81e7a19d3fc5ae7d` |
| `tools/art/generate_ground_contact_course.py` | 28217 | `4840d16ad83e96a8b3c80cd09954fef17effb1f7d75e1331741b3bcb0f4ddb9b` |
| `ground_contact_course.glb.import`（Godot 导入元数据） | 1106 | `1b32e069c385485caaa3f535a3aab4867dff3491b6773c29983fb96db260f846` |
| `preview_overview.png` | 701413 | `dc6f5b8d7180b26351afc68a9c59895a9d6961fdba09745a02353306f9db2d2e` |
| `preview_ramps.png` | 390807 | `5a5b324be8f6cd3b25b38dad84824edb7675bbba336547f38ad64d8d9f46aa1d` |
| `preview_steps.png` | 525250 | `2443347a2801775079d9231be985b3e08bc98befd247e7fac2b16ad9e20b7fff` |
| `preview_corner_narrow.png` | 674535 | `af37767ebef5f829396cd6589af4c974c9b972c12918a842cd08960e992f86b6` |
| `preview_edge_void.png` | 736667 | `5c35f45f14f26356c2a49287e019266e656a0b883283870d1b222d02a7f80e4a` |

上表哈希与大小于 2026-09-18 逐个实测复核；`.blend` 与 `.blend1` 均按当时字节原样保留，未重新保存。

| 指标 | 值 |
|---|---|
| 源零件（.blend） | 218 |
| 导出网格（GLB） | 218 |
| 三角形 | 22992 |
| 坐标范围（Godot 世界，m） | x −23.48…33.85，y −3.45…5.46，z −22.5…22.5 |
| 装置数（layout devices） | 29（含 4 条斜面、3 级台阶、20 面墙、1 台地、1 基线台） |

说明：本资产**不做材质合并**（与庭院不同）。训练场需要「装置名 = 网格名」这一命名契约
来支撑可视/碰撞逐项对齐断言，按材质合并会把节点名压成 `<材质名>` 而丢掉这层语义。
代价是 drawcall 偏高，但本场景是实验场不是量产关卡，命名可验证性优先。

## 共面修复（surface clearance，2026-09-18）

依据 [装饰面共面与透明穿叠导致的跨场景地面闪烁](../../../notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md)
的 A/B 分类，本轮在**原模型上继续修改**：只改可见几何的高度关系，**碰撞 JSON 数值一字未动**
（`ground_contact_course_layout.json` 哈希仍为 `2031097455bfecf43bece8ec8f819818739470fabe5442bd81e7a19d3fc5ae7d`，
0.25/0.5/0.75 m 台阶、28/42/52° 斜坡、0.6 m 窄路与全部碰撞盒均不变）。

### 修法（`tools/art/generate_ground_contact_course.py`）

新增 `SURFACE_CLEARANCE = 0.02` 与 `buried()` 两个约定件，沿用 mountain_realm / peak_courtyards 已验证的 2 cm 量级：

- **A 类（水平装饰面）**：抬到承托面上方 ≥2 cm。涉及 `step_*_top`（本次的核心漏改点）、
  `step_*_band`、`step_*_plinth`、`*_cap`（墙 / 窄路 / 坡顶平台 / 台地压顶）、`ramp_*_nose`、`terrace_deck`、
  `terrace_warning`、`flat_tick_*`、`ground_moss_*`。台阶压面原本只埋 1.5 cm 仍与台面共面，现改为底面高出台面 2 cm；
  玉色边条整层埋进压面、只露顶面，避免「压面顶面 = 边条顶面」。
- **B 类（竖直件端盖落地）**：`buried()` 保持**顶面不动**、向下多埋 2 cm。
  涉及 `bamboo_*_stem_*`、`lantern_*_base`、`step_*` 主体与底座、`ramp_*_landing`、
  `ramp_*_rail_post_*`、墙身与墙脚（墙脚多埋 1 cm）、`lane_*_post_*`（多埋 1 cm）、`terrace` 主体。
  **不存在粗暴抬高**：可走面高度全部保持。
- **同高度重叠件**：墙角压顶按装置序号错开 0/4/8/12 mm，台阶底座收窄 0.2 m，
  窄路门柱与墙脚下沉量比墙身多 1 cm——这些重叠原本是「顶面 = 压面顶面」或「底面同深度」。

`ground_contact_course.blend1` 是本次 Blender 保存时轮转出的新备份，**已用归档副本还原为原始字节**，
因此下表 `.blend1` 哈希与修复前一致，历史源状态未丢失。

### 修复前归档（`pre_surface_clearance_*`，必须保留）

覆盖旧预览与旧源之前先复制归档；`pre_surface_clearance_ground_contact_course.blend` 即修复前的
`ground_contact_course.blend`。

| 归档文件 | 字节 | sha256 |
|---|---|---|
| `pre_surface_clearance_ground_contact_course.blend` | 210123 | `f2e226f4b720566c9dcd519ac0c4187c37628e4350e29ad94c3c3809786a98d7` |
| `pre_surface_clearance_ground_contact_course.blend1` | 209915 | `6c33087982126dfda61b2e77a1ee398392d74aa350cb324548dff7b23e10c32a` |
| `pre_surface_clearance_ground_contact_course.glb`（修复前导出，逐字节 = `0d1dc64` 旧 GLB） | 1254736 | `b823b141e04f0739f840d774e24d1cb0bf14e3c88376d621b245b4a46bb003a4` |
| `pre_surface_clearance_overview.png` | 701413 | `dc6f5b8d7180b26351afc68a9c59895a9d6961fdba09745a02353306f9db2d2e` |
| `pre_surface_clearance_ramps.png` | 390807 | `5a5b324be8f6cd3b25b38dad84824edb7675bbba336547f38ad64d8d9f46aa1d` |
| `pre_surface_clearance_steps.png` | 525250 | `2443347a2801775079d9231be985b3e08bc98befd247e7fac2b16ad9e20b7fff` |
| `pre_surface_clearance_corner_narrow.png` | 674535 | `af37767ebef5f829396cd6589af4c974c9b972c12918a842cd08960e992f86b6` |
| `pre_surface_clearance_edge_void.png` | 736667 | `5c35f45f14f26356c2a49287e019266e656a0b883283870d1b222d02a7f80e4a` |

### 修复后数值（2026-09-18 重导）

| 产物 | 字节 | sha256 |
|---|---|---|
| `ground_contact_course.glb` | 1264820 | `e5e1bdaa0b3f60570d4a82a79e5d50f4fbc853a3e6f34194f509292b7ce6fcfd` |
| `ground_contact_course.blend` | 212361 | `4f7aa603df82ba41b9e5adcc620cd7463cd453059fbd6ab8a9f78f120415df27` |
| `ground_contact_course.blend1`（原始字节，未轮转） | 209915 | `6c33087982126dfda61b2e77a1ee398392d74aa350cb324548dff7b23e10c32a` |
| `ground_contact_course.glb.import` | 1106 | `1b32e069c385485caaa3f535a3aab4867dff3491b6773c29983fb96db260f846` |
| `tools/art/generate_ground_contact_course.py`（修复后，含最终集成轮对本 note 路径引用的更新） | 31473 | `37f29ae98d2a0b6f06b873a23c32e6c69c18453ed5c265a553eeddc62d2cd1d4` |
| `preview_overview.png` | 697054 | `c4eb3b08659762acecf85bdd3ec2aa3d05a2edb79146a299f4307d48841dece0` |
| `preview_ramps.png` | 383742 | `9eda9d6548a9bf7481701586c345ecd3e9a620d6df0ccd82caec2b79a07faa87` |
| `preview_steps.png` | 528433 | `1961f87a4439371a7da1c9eda20c6bcb5d9d1a62f131d440a48b18367c3891a1` |
| `preview_corner_narrow.png` | 671463 | `32b506102a85f2e70855e1b7e3f281c7af47034fdda6ae70936ade3e91f92ff3` |
| `preview_edge_void.png` | 735676 | `d66eda2dcc2c59bd84bd23e48da5d2513f7ebeba41e13960085d425a69d6bc7e` |

几何不变量：源零件 218、导出网格 218、三角形 22992、坐标范围 x −23.48…33.85 / y −3.45…5.46 / z −22.5…22.5
均与修复前一致（仅底面按 2 cm 下沉，包围盒下沿不变）。

### 共面命中对照（阈值口径必须逐条对照，不可混称）

三个数字来自**三套不同阈值**，不能互相替代或混称为同一口径：

| 数字 | 扫描器/阈值口径 | 含义 |
|---|---|---|
| **121** | footprint **> 0.01 m²**、垂直重合 ≤1.5 mm、水平三角面片真实相交面积 | 本节修复前主口径命中组数（修复后 8） |
| **174** | 同一份修复前数据、footprint 阈值放宽到 **≥0.001 m²** | 修复前命中组数（阈值更松所以更多），不是另一轮修复的读数 |
| **128** | note 的独立扫描：水平重叠 **≥0.05 m²** 且垂直重合 ≤1.5 mm | `notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md` 记录的独立复现值，与 121 不是同一阈值 |

| | 修复前 | 修复后 |
|---|---|---|
| 命中组数（121 口径） | 121（≥0.001 m² 时 174） | **8，全部为 B 类已批准埋入端盖** |
| 未允许 A 类 | — | **0** |
| 128（note 口径） | 128 组独立扫描命中，属同一缺陷族的独立复现 | 未按该口径重扫；本表修复后数字来自 121 口径 |

修复后仅存的 8 组均为「两个已下沉端盖底面同深度」：3 组 `step_*_plinth ↔ step_*`、2 组墙角墙脚互对、
2 组台地栏杆墙脚互对、1 组院墙互对。都埋在实体内部、不产生可见面竞争，按 B 类「列出有理由允许」保留。

**B 类允许项（不可见重合约定的统一口径）**：本资产与 `state_transition_lab` 的**埋入底面同高**
一律归为**不可见 B 类允许项**——端盖/底面被实体包住，不参与可见面竞争，只在扫描里作为
bottom/bottom 重合出现；它们既不是 A 类缺陷，也不代表顶面已无共面。判据是「是否可见竞争」，
不是「是否出现在扫描命中里」。

### 验证状态

- `godot --headless --path src --script res://tests/ground_contact_course_playtest.gd -- --batch=assembly,flat,ramp,step,corner,narrow,edge,recovery,hud,exit`：
  **失败 0，退出码 0**（178 项断言，含逐装置可视-碰撞对齐、台阶 0.25/0.5/0.75、斜坡 28/42/52°、窄路 0.6 m、边缘台与落下回收）。
- `godot --headless --path src --import`：退出码 0。
- 移动/冻结像素对照：`src/tests/ground_contact_course_surface_clearance_capture.gd`（experimental、非门禁）。
  **脚本运行成功，但控制无效**：冻结组残余帧间差异 **3.687%–9.762%**（`post_report.txt`，
  `~/.cache/game-xiuxian-lab/surface-clearance/ground-contact/post/`），说明相机链/渲染未真正冻结，
  移动组读数不可归因。该项**未验证、非门禁，不可证明修复**；**不声称验收通过**。
  脚本保留待下轮修严（含 `.gd.uid`，随 Git 入库），不删除。
  本轮修复依据只是静态共面扫描（121 → 8，未允许 A 类 = 0），不是像素读数。
