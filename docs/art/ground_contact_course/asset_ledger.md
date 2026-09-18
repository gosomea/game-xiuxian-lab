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
> 唯一差别只在**事实**而非规则：那边当前尚未产生 `.blend1`（首次以 `save_as_mainfile` 写出，
> 未发生覆盖保存），本资产已产生一份，故在本节逐项登记。

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
