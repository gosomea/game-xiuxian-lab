# 资产台账 · peak_courtyards（庭院建筑）

按 [mcp-blender skill](../../../skills/mcp-blender/SKILL.md) 的登记纪律：来源、许可结论、日期。
生成方式：**AI 代理编写脚本，经 Blender 5.2.1 LTS 程序建模**；未调用图像/3D 生成服务，无下载资产。

| 字段 | 值 |
|---|---|
| 资产名 | `peak_courtyards`（五峰庭院建筑：门楼、主殿、廊台、亭、敞轩、台阶、石灯、竹丛、铺装） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS（2026-08-25 构建）程序建模；无第三方素材 |
| 生成脚本 | `tools/art/generate_peak_courtyards.py` |
| 源文件 | `docs/art/peak_courtyards/mountain_realm_courtyards.blend`（833 个可编辑分件） |
| 运行输出 | `src/.../mountain_realm_courtyards.glb`、`..._collision.json` |
| 预览 | `courtyards_preview_{spawn,summit,north,west,east,hall_front}.png`（Cycles 16 采样 + 降噪，900×600） |
| 生成日期 | 2026-09-18 |
| 第三方素材 / 许可依赖 | 无；唯一外部依赖是 Blender 自带 Python |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明。 |
| 生成方式声明 | AI 代理编写脚本，Blender 程序建模；未调用图像/3D 生成服务。 |
| 导出器 | Khronos glTF Blender I/O（Blender 5.2.1 自带），`export_yup=True` |
| 可复现性 | 固定种子（`random.Random(20260918)`、`stable_seed()`）；同一 Blender 版本可复现 |

## 导出合并（性能）

- 源装配 **833 个网格零件**（.blend 中全部保留、可继续编辑）；导出副本按**主材质**烘焙修改器后合并成 **17 个网格节点**，
  即 17 个 drawcall 量级；节点名为 `courtyards_<material>`（如 `courtyards_jade_roof_tiles`）。
- 合并前后机械核对：`MERGE ok objects 833 -> 17 tris=86196 bbox_delta=0.000008 materials=17`，
  三角形数与包围盒必须完全一致，否则退出码 4。世界坐标、几何、附加碰撞 JSON 均未改变。
- **语义取舍（如实报告）**：GLB 里不再保留逐构件节点名（`main_hall_wall_north` 等），
  只剩按材质命名的合并节点。材质 17 个全部保留、无材质丢失；覆盖校验与落点净空校验都在**合并前**对源零件执行，
  所以「无盒不显形」的保证不受影响。若场景需要逐构件节点语义（例如单独开关某栋建筑），应改读 .blend 或另开分组合并参数，
  本轮按性能优先选择了材质合并。

## 数值（2026-09-18 最终读数）

| 产物 | 字节 | sha256 |
|---|---|---|
| `mountain_realm_courtyards.glb` | 5638908 | `971984a5629b4d631aab9d0f068c49281595b7c7ba3dcc8fe109529f050344bd` |
| `..._collision.json` | 4828 | `277052feded0ece10fb09ed00ce3d1d4862856e78c8faeb5a3308f66b4474a98` |
| `mountain_realm_courtyards.blend` | 499966 | `8927d190688955ebf34fe45032fcce381bd3fcb176752b72fa6d16ea68917887` |
| `courtyards_preview_spawn.png` | 682215 | `e221ad587e365f4c2276ca08e6c561b51ebed345c9c32360f1bd76f75a50e5a4` |
| `courtyards_preview_summit.png` | 684792 | `dbf3ba5861ee017c3535e2e79772a32e7f16600892cfc5315f188e5d639daf34` |
| `courtyards_preview_north.png` | 600867 | `56cfeb2a83111de9252019c3c3da55af73cf1880a0346bd2a24c877441e1a9bb` |
| `courtyards_preview_west.png` | 625519 | `3db7a404724ba3a0cea9defcdf3bb3d91eb57c21f1212f1bf72230deed13c6c9` |
| `courtyards_preview_east.png` | 615346 | `9a26af39a5ac36a47d5c1b9cca7ca2ff8a60c82a22d8938f9c7eb5d48c808bc5` |
| `courtyards_preview_hall_front.png` | 729336 | `dd88b8c8e46429b1df49dd8b8aecfb6ebd78eee4b733e8865c0f1e66fc378204` |

| 指标 | 值 |
|---|---|
| 源零件（.blend） | 833 |
| 导出节点（GLB） | 17（按材质合并） |
| 三角形 | 86196 |
| 材质 | 17（纯色 PBR） |
| 图片 / 贴图 / 动画 / 骨骼 | 0 / 0 / 0 / 0 |
| GLB 内 `PREVIEW` 节点 | 0 |
| 附加碰撞 | 33 盒，`peak_courtyards_collision/1` |

## 三项构建期机械校验（失败即非零退出）

1. `COVERAGE ok owned=58 presented=58 roles={'ground': 2, 'stairs': 8, 'building': 28, 'roof': 9, 'prop': 11}`：每个属于本文件的既有盒都有可见几何，杜绝隐形墙。
2. `LANDING_CLEARANCE ok landing_points=3 new_colliders=33`：新增实体不得侵入落点净空。曾拦下起点门楼柱基侵入 `spawn_courtyard`。
3. `MERGE ok`：合并导出不得改变三角形数或包围盒。

## 本轮收尾修复（父指出的两处 + 铺装）

- **侧窗曾埋在墙里**：原侧窗贴在 x=−3.48 / 11.48，而西墙 x∈[−4,−3]、东墙 x∈[11,12]，窗完全在墙体内部。
  现改为墙外侧贴面（西 x=−4.12、东 x=12.12）+ 木框 + 竖向窗棂（`main_hall_side_window_frame_*` / `_mullion_*`）；
  并在正面门洞两侧（x=−0.5 / 8.5）新增带框窗格，主殿近景可读。
- **台基/地板/檐柱碰撞缺失**：台基与地板改为贴合原 36 m 站立面（地板视觉顶 36.02、台基顶 35.97），
  因此**不需要**门槛台阶、门洞 4 m 全宽可走、不侵入 `summit_sect` 落点净空；檐柱四根移到门洞之外
  （x = −0.6 / 1.5 / 6.5 / 8.6）并登记柱础碰撞（`main_hall_front_column_base_*`，4 条）。
- **主峰大院曾整片黑土**：新增同源灰米/石灰岩/青苔三色**薄板铺装**（6 cm 厚、顶面 36.02，高出承载面 2 cm 不共面），
  避开主殿占地、8 级台阶与门口通道，另加 2.6 m 宽中轴石道；**不登记碰撞**（行走面仍由 36 m 平台盒承担）。
- 顺带按 mountain_realm 台账的已知根因，对所有生成网格统一 `recalc_face_normals`（`NORMALS recalculated on 833 meshes`）。

## 归属边界

- `building` / `roof` / `stairs` 全归本文件；prop 取 `stone_lantern_*` 与 `bamboo_clump_*`；
  ground 取 `jump_step` 与 `north_plinth`。大型承载面（含 `shanmen_terrace`）与 9 棵松归地形代理。
- 附加碰撞 33 盒覆盖：起点门楼柱基/院墙/石灯基座；北峰两灯；西峰望亭四柱/屏墙/两灯；
  东岭敞轩柱基/石凳/石桌/短墙/两灯；主殿前檐四柱础。

## 未完成 / 未验证

- 未在 Godot 中导入与实机渲染（Godot 由 realm_scene 独占）；**真实走进主殿检验脚底与门口通行由恢复后的 QA 执行**，
  本台账只保证几何高度与碰撞登记，不替代实机走动。
- 装饰件（檐角、瓦面、竹叶、苔石、灯罩）无碰撞；石灯只登记基座足印。
- 五峰庭院规模分级：主峰最完整，起点与北峰二级，西峰望亭与东岭敞轩为歇脚点。
- 手感与配色审美由使用者实机判断。

登记人：庭院建筑资产代理；日期 2026-09-18。接口见 [README.md](README.md)。
