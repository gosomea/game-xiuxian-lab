# 资产台账 · jade_paper_sample

## 一句话

青玉纸白样板（第一轮实施）美术资产：**亭 / 松 / 岩为腾讯混元 3D（hy-3d 文生 3D）生成 + 本地 Blender 5.2.1 归一与调色**，
**台基 / 台阶 / 铺装 / 收边为 AI 代理脚本 + Blender 程序建模**。逐资产的生成 job_id、复现脚本与本目录源文件见下表。
依据：[实施 note](../../../notes/proposed/art/2026-09-19-jade-paper-sample-implementation.md)。

## 条目

| 字段 | 值 |
|---|---|
| 资产名 | `jade_pavilion`（六角亭）/ `jade_pine`（松）/ `jade_rock`（山岩）/ `jade_sample_terrain`（台基+台阶+铺装+收边） |
| 来源 | 亭/松/岩：混元 3D 生成（几何 + 烘焙贴图），Blender 内仅缩放归一、Decimate 减面、贴图乘法调色；地形：AI 代理脚本 + Blender 程序建模。无素材库下载 |
| 混元 job_id | 亭 `1492584116846845952` · 松 `1492582230114689024` · 岩 `1492582225773854720`（腾讯云 hy-3d，2026-09-19） |
| 生成/处理脚本 | `tools/art/build_jade_sample_terrain.py`（地形）；`tools/art/process_jade_hunyuan.py`（混元后处理，含色卡与分段规则） |
| 原始产物 | `hunyuan_raw/{pavilion,pine,rock}_raw.glb` + `*_preview.png`（混元原样，只读对照） |
| 源文件 | 本目录 `jade_{pavilion,pine,rock}.blend`、`jade_sample_terrain.blend` |
| 运行输出 | `src/levels/experiments/character_movement/jade_{pavilion,pine,rock}.glb`、`jade_sample_terrain.glb`（新文件名，未覆盖任何旧资产） |
| 生成日期 | 2026-09-19 |
| 生成方式声明 | 亭/松/岩含 AI 生成几何与贴图（腾讯混元 3D）；地形为程序原创。不在台账内做平台政策结论 |
| 导出器 | Khronos glTF Blender I/O（Blender 5.2.1 自带），`export_yup` |
| 轴向 | 正面朝 Blender +Y 建模，export_yup 后为 Godot -Z/-Z 语义（地形台阶朝 Godot +Z 为刻意，见脚本头注释） |

## 数值（2026-09-19 读数，GLB JSON 直读）

| 产物 | 网格 | 三角形 | 材质 | 贴图 | 字节 | sha256 |
|---|---|---|---|---|---|---|
| `jade_pavilion.glb` | 1 | 79,999 | 3（瓦/木/石） | 3 | 7,012,192 | `d7c1be574a7f0dbcee021dd438f0c6b1f5deb7e88988d6649badaada6eb9e338` |
| `jade_pine.glb` | 1 | 39,994 | 2（冠/干） | 2 | 4,616,456 | `b32455a7aa0c2bd8040195917cc2e75ede65bb2521f91cf6d21f6390d9cc1d51` |
| `jade_rock.glb` | 1 | 30,000 | 1（青灰） | 1 | 1,638,424 | `5f741ea67dc06e210545750f72712502a229a33f647aa4d833406e6bc9d63ed0` |
| `jade_sample_terrain.glb` | 11 | 696 | 5（压顶/立面/砖/收边/踏面） | 0 | 44,888 | `25274ec95ea37375491e20553c6f5a4fcca61e7d86b69684505e035f64ae8c06` |

尺寸归一：松高 6.0 m、岩高 2.2 m、亭高 4.6 m（置于 0.6 m 台基上顶约 5.2 m）；底面 z=0、xy 居中。

## 调色（线性值，混元件为贴图乘法系数目标）

| 段 | Godot albedo（显示口径） | 说明 |
|---|---|---|
| 青玉瓦 tile | (0.013, 0.147, 0.102) 线性 | 亭顶 |
| 暖棕木 wood | (0.132, 0.060, 0.020) 线性 | 亭柱/松干 |
| 深松绿 foliage | (0.024, 0.085, 0.045) 线性 | 松冠（比 #1F3D2B 提亮一档保冠内可读） |
| 青灰岩 stone | (0.112, 0.144, 0.162) 线性 | 岩石/亭基座 |
| 地形五段 | 见 `build_jade_sample_terrain.py` TARGETS_DISPLAY | Godot albedo 显示口径，导出前 srgb_to_linear 预补偿 |

## 关键约束（本轮实测踩坑，后续必读）

- **glTF 导出器不导出 MixRGB 乘法节点**：材质调色必须烘进贴图像素（`_bake_tinted_image`），否则 `baseColorFactor` 丢失、回退原始贴图色。
- **Godot 导入器把 glTF `baseColorFactor` 做 linear→sRGB 转换后写入 albedo**（实测 0.434→0.690，精确吻合 `linear_to_srgb`）：程序建模色卡必须按"Godot albedo 显示口径 → srgb_to_linear 预补偿"导出，否则整体曝光洗白一档（上一轮"纸白被洗白"的机制层根因）。
- **Godot 从 GLB 抽取的 `*_tex.png` 是运行时依赖不是垃圾**：删掉会让 `.scn` 加载失败（本轮实测）；必须入 Git。
- **远景盘 CylinderMesh 中心 vs 顶面**：1 m 高圆柱中心放 y=-0.2 → 顶面 +0.3，会盖住地面与铺装；必须保证顶面低于地面（现 -0.71 → 顶 -0.21）。
- **`from_pydata` 手排顶点两次踩坑**（蝴蝶结面 / 法线异常）：铺装改用 `bmesh.ops.create_cube` 逐砖生成再合并。

## 与旧资产的替代关系

| 新资产 | 替代/关系 | 旧资产状态 |
|---|---|---|
| `jade_pavilion/pine/rock/sample_terrain.glb` | 样板场景专用，不替代任何旧资产 | `mountain_realm*.glb`、`cultivator.glb`、`flying_sword.glb` 原样保留，sha256 未变 |

## 未完成 / 未验证项

- 审美结论归使用者：样板状态 exploring，使用者视觉确认前不宣称方向通过。
- 亭的生成件为六角攒尖（非四角），方向 note 未限定角数，样板阶段接受。
- 人物与飞剑本轮零改动（核对已合规），实机观感随样板一并交使用者确认。
