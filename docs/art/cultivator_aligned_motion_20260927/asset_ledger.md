# v9 收臂与正向跳跃资产台账

## 来源与保存

- 人物网格、材质、22 骨与蒙皮来自先前的 v9 人物；步行和疾跑来自早期人体动作重定向，跳跃来自正向双脚跳跃轨道。`build_manifest.json` 保留首次构建时的输入 SHA-256 和逐 clip 数值记录；其中的旧输入路径已按使用者本次明确要求清理，不再是现役构建依赖。
- 当前可编辑源 `cultivator_aligned_motion_20260927.blend` 从已验收的现役 GLB 重新导入，七段 action 均设为持久保存，三张贴图内嵌。运行时导出仍为 `src/game/actors/swordsman/models/cultivator_aligned_motion_20260927.glb`。独立重导出使用 `tools/art/export_cultivator_aligned_motion_20260927.py`，脚本会拒绝缺失动作、贴图未打包或骨架数量变化。
- 视觉入口 `src/game/actors/swordsman/cultivator_aligned_motion_20260927_visual.tscn` 由默认 `Swordsman`、动作预览和青玉纸样板共享。旧人物源、GLB、预览和旧视觉场景已按[清理决策](../../../notes/implemented/art/2026-09-27-unused-character-asset-cleanup.md)移除。
- GLB 导入生成的三张贴图及其 `.import` 边车与该版本一同保存。Blender 重导出后须运行 `godot --headless --path src --import`，再复测七段动作、姿态和贴地。临时重导出与当前 GLB 在这些检查上结果一致；字节 SHA 不相同，故本次清理未覆盖已经验收的运行时 GLB。

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
