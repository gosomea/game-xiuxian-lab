# state_transition_lab 美术资产

2026-09-18 由 AI 代理编写脚本、经本地 Blender 5.2.1 LTS 独立后台进程程序建模，
**全部为程序原创几何**：没有下载资产、没有素材库、没有贴图，未调用图像/3D 生成服务，
没有骨骼与动画。唯一外部依赖是 Blender 自带 Python（`bpy` / `mathutils`）。

决策依据：[character-movement-subexperiments](../../../notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md)。

资产定位：**心境 / 身法试炼阵**——阴阳玉盘、石门（北）、断桥（东）、悬浮阵纹柱与外围阵环，
为「状态切换压力场」子实验提供可读的修仙场景与三块**功能性**地形（墙 / 断桥缺口 / 边缘低台）。

## 源文件与生成物

| 文件 | 角色 | 生成方式 |
|---|---|---|
| `state_transition_lab.blend` | 阵盘源文件（含预览相机/灯光，不导出） | `tools/art/generate_state_transition_lab.py` |
| `trial_preview.png` | 预览渲染（Cycles 24 采样，1200×900，非运行时素材） | 同上脚本末尾渲染 |
| `src/levels/experiments/character_movement/state_transition_lab.glb` | 运行时视觉资源（**只含几何，不含碰撞**） | 同上脚本导出 |

本目录是这批资产的**唯一真源**；`src/` 下的 GLB 是导出产物，不要手改。

## 几何契约（场景物理按此本地装配）

| 元素 | Blender 坐标 | Godot 坐标（Y-up 导出后） |
|---|---|---|
| 玉盘主平台 | 半径 9 m，顶面 Z=0 | 半径 9 m，顶面 Y=0 |
| 石门北墙 | Y=-5.5，面宽约 10 m | Z=-5.5；门洞 x ∈ [-1.5, 1.5] |
| 断桥 | +X 方向两段，缺口 X ∈ [9.1, 11.5] | +X 方向两段，缺口 x ∈ [9.1, 11.5] |
| 边缘低台 | （由 Godot 侧装配） | 西南侧 2×2 m、高 0.5 m |

**碰撞不在 GLB 内**：`state_transition_lab.gd` 用 BoxShape3D 精确装配，保证数值可控可测。
GLB 只负责观感；两者尺寸一致，改几何时必须同步两侧。

## 复现命令

macOS（Blender 5.2.1 LTS）；其他平台把可执行文件换成 PATH 中的小写 `blender`：

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_state_transition_lab.py
```

**重跑会覆盖 .blend 与 GLB 导出文件**（导出前会重新生成同名几何，属原模型上的继续修改）。

2026-09-18 共面闪烁修复（rim 环带 + 装饰面脱开）后重导，见 `asset_ledger.md`「共面修复」小节。

| 文件 | 字节 | sha256 |
|---|---|---|
| `state_transition_lab.blend` | 205314 | `8e5996d98129c4d090fcb9246b06cceeb69383ca128979e9a61f75215085c40c` |
| `state_transition_lab.glb` | 2373848 | `47a2d754bd724ba29a3057669a828edf4670f31e5cc54e309f4429d6304a8cc3` |
| `trial_preview.png` | 1121430 | `da9fa644854988b6480f039be2fc7c0c612c3505aa7711e59fa83e4074623ece` |
| `trial_preview_surface_clearance.png`（修复后预览，保留） | 1121430 | `da9fa644854988b6480f039be2fc7c0c612c3505aa7711e59fa83e4074623ece` |
| `trial_preview_pre_surface_clearance.png`（修复前旧预览，保留） | 1042749 | `33f50173deb348bf21795db3beafc141c3e71788cab34edeaf77da39d1fdb949` |
| `state_transition_lab.blend1`（自动备份的中间态，非修复前源，保留） | 205559 | `7605faf5f88fd90bc84ed43e3b3ec940b7d7e8c3c1629187c789ea9645fba6d3` |
| `pre_surface_clearance_state_transition_lab.blend`（修复前源归档，= HEAD 旧字节） | 195965 | `f00fe206f07ec7ec4450960b30df0667007b8affb8e3f3ae4cc85c56377ac6d4` |
| `pre_surface_clearance_state_transition_lab.glb`（修复前导出归档，= HEAD 旧字节） | 2311704 | `43f77a9c37979be81f799a3add3451f16170a1ea3d1fe0d3667e777aec6daa4a` |

### 共面闪烁修复（2026-09-18）

根因：`Jade disc rim band` 原为与盘顶严格同高（Blender Z=0，即 Godot y=0）的实心圆盘，
与 `Jade disc body` 顶面共面 322.56 m²，运行帧 2–22 近景变化像素约 20%（隐藏 rim 后降至约 1.09%）。

| 件 | 修法 | 修后关键高度 |
|---|---|---|
| `Jade disc rim band` | 实心圆盘 → **真环带**（`ring()`，内外半径 8.40/8.98） | 顶 +0.012（高出盘顶 12 mm），底 −0.108 埋入 |
| `Gate threshold` | 下沉 10 mm 埋入盘体 | 底 −0.010 |
| `Gate wall slab` / `Gate pillar` | 下沉 10 mm | 底 −0.010 |
| `Bridge near/far span` | **可走面顶面下沉 5 mm**（不抬高） | 可见顶 −0.005；碰撞盒顶仍 y=0 |
| `Bridge rail post` | 下沉 10 mm | 底 −0.01 |
| `Pillar cap` | 下沉 10 mm | 底 = 柱顶 −0.01 |

**未改**：碰撞常量、角色站立高度、断桥缺口 x ∈ [9.1, 11.5]（与 `state_transition_lab.gd` 的 `GAP_MIN_X` / `GAP_MAX_X` 一致）与状态切换语义。
碰撞仍在 `state_transition_lab.gd` 本地装配，GLB 只做视觉。

## 未完成

- 手感与配色审美待使用者实机判断；无骨骼、无动画。
- 预览渲染偏暗的照明已调整（新增侧向补光与日光），如仍不满意可在脚本末段调灯后重跑。
