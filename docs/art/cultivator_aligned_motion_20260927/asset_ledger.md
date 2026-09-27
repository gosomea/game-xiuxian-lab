# v9 收臂与正向跳跃资产台账

## 来源与保存

- 人物网格、材质、22 骨与蒙皮：保留的 `src/game/actors/swordsman/models/cultivator_motion_20260927.glb`。没有重新建模。
- 步行、疾跑关节运动：项目内 `docs/art/cultivator_jade/cultivator_rigged.blend` 的早期 Mixamo 人体动作；按绑定姿态映射到 v9 骨架，保留原地根运动。跳跃使用 v9 底座的正向双脚跳跃轨道，并加双臂对称的小幅上摆。原 Mixamo `jump` 的偏航和盘坐收腿未进入本版。
- 构建脚本：`tools/art/build_cultivator_aligned_motion_20260927.py`；可编辑源：`cultivator_aligned_motion_20260927.blend`；运行时导出：`src/game/actors/swordsman/models/cultivator_aligned_motion_20260927.glb`。`build_manifest.json` 记录输入与输出 SHA-256、逐 clip 来源和构建数值。
- 新视觉入口：`src/game/actors/swordsman/cultivator_aligned_motion_20260927_visual.tscn`，由默认 `Swordsman`、动作预览和青玉纸样板共享。旧 `cultivator_human_motion_20260927` 的源、GLB、预览和视觉场景全部保留，供前后对照。
- GLB 导入生成的三张贴图及其 `.import` 边车与该版本一同保存。Blender 构建后须运行 `godot --headless --path src --import`。

## 改动与逐帧证据

| 动作 | 变化 | 导出后实测 |
|---|---|---|
| `walk` | 保留前后摆臂相位，肩肘向身体收，手腕恢复普通站姿方向 | 手肘最大外展 0.066 m、手腕 0.120 m；左右手腕前后摆幅 0.228 / 0.264 m |
| `run` | 保留较大的前后摆臂，限制肩肘手腕横向张开 | 手肘最大外展 0.099 m、手腕 0.152 m；左右手腕前后摆幅 0.469 / 0.444 m |
| `jump` | 弃用偏航约 55°、末段盘坐的旧源动作；从 v9 正向双脚竖直跳跃动作加对称上摆 | 双肩最大偏航 0.008°、骨盆 0.985°、头部 0.019°；双脚横向间距最大 0.222 m；手肘最大外展 0.080 m、手腕 0.133 m |

量化依据：[动作朝向和摆臂逐帧报告](geometry.json)、[髋→头姿态报告](posture.json)、[蒙皮最低顶点报告](ground_contact.json)。走路 / 疾跑的鞋底最低点分别为 -0.0003 / +0.0009 m；跳跃鞋底最低 +0.0129 m。

[正面五相位图](front_contact_sheet.png)和[侧面五相位图](side_contact_sheet.png)从最终 GLB 渲染，行顺序为走路、疾跑、跳跃，列为时间从前到后；`frames/` 保存全部 30 张单帧 PNG。渲染脚本为 `tools/art/render_cultivator_aligned_motion.py`，拼图脚本为 `tools/art/make_aligned_motion_sheets.py`。

## 当前边界

新跳跃已解决侧向起跳、转头和盘坐收腿；起跳时膝部预备仍偏轻，动画自身的升高幅度也小。真实跳高由 Jump 能力产生，动作最终节奏和落地缓冲仍需使用者在工作台连续试玩判断。本轮没有改变移动速度、物理根、御剑或其它三段状态。
