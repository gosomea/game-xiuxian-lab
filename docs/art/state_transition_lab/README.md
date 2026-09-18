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
| 断桥 | +X 方向两段，缺口 X ∈ [9.5, 11.5] | +X 方向两段，缺口 x ∈ [9.5, 11.5] |
| 边缘低台 | （由 Godot 侧装配） | 西南侧 2×2 m、高 0.5 m |

**碰撞不在 GLB 内**：`state_transition_lab.gd` 用 BoxShape3D 精确装配，保证数值可控可测。
GLB 只负责观感；两者尺寸一致，改几何时必须同步两侧。

## 复现命令

macOS（Blender 5.2.1 LTS）；其他平台把可执行文件换成 PATH 中的小写 `blender`：

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_state_transition_lab.py
```

**重跑会覆盖 .blend 与 GLB 导出文件**（导出前会重新生成同名几何，属原模型上的继续修改）。

| 文件 | 字节 | sha256 |
|---|---|---|
| `state_transition_lab.blend` | 195965 | `f00fe206f07ec7ec4450960b30df0667007b8affb8e3f3ae4cc85c56377ac6d4` |
| `state_transition_lab.glb` | 2311704 | `43f77a9c37979be81f799a3add3451f16170a1ea3d1fe0d3667e777aec6daa4a` |
| `trial_preview.png` | 1042749 | `33f50173deb348bf21795db3beafc141c3e71788cab34edeaf77da39d1fdb949` |

## 未完成

- 手感与配色审美待使用者实机判断；无骨骼、无动画。
- 预览渲染偏暗的照明已调整（新增侧向补光与日光），如仍不满意可在脚本末段调灯后重跑。
