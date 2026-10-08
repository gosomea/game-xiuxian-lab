# 人物步态重心校正 · 2026-10-06

## 来源与现役装配

以[aligned 可编辑源](../cultivator_aligned_motion_20260927/asset_ledger.md)继续修改动作，人物没有重新建模。本目录 `.blend` 内含同一人物网格、22 骨蒙皮、三张内嵌贴图与七段动作。源网格坐标、拓扑、UV、蒙皮权重和骨架 rest 矩阵的散列完全相同，见 [mesh_comparison.json](mesh_comparison.json)。GLB 重导出后的属性顶点数从 432708 到 432724（多 16 个拆分顶点），不可宣称导出二进制逐字节相同。

- 可编辑源：`cultivator_balanced_motion_20261006.blend`。
- 游戏导出：`src/game/actors/swordsman/models/cultivator_balanced_motion_20261006.glb`；Godot 拆出的三张贴图及 `.import` 同时跟踪。
- 现役入口继续为 `cultivator_aligned_motion_20260927_visual.tscn`，模型子节点名保持兼容；默认人物、工作台、动作预览和所有三维移动场景共用。
- 原 aligned 源、GLB、贴图和预览继续保留用于对比。
- 普通 `idle`、`run/jump/idle_guarded/meditate/sword_ride` 保留原有动作。只对 walk 烘焙腿链与支撑高度校正；run 的运行时播放参考重新测量。

## 步行修正与测量

`build_balanced_motion_20261006.py` 先捕获原始逐帧骨骼和 armature 对象变换，再把左右大腿的摆动中心绕世界 X 旋转约 9.09°。脚掌保留原有朝向和跟趾滚动，不随腿链额外翻转。根据实际蒙皮最低点校正骨盆高度，密集线性关键帧并对齐循环首尾。对象级地面偏移也写入新动作，否则切换其它 clip 后会让 walk 继承错误的 root 高度。

| 指标 | 原 aligned | 本版本 |
|---|---:|---:|
| 全周期双踝在骨盆前的平均偏移（121 次采样） | 12.69 cm | 0.76 cm |
| walk 上身平均前后倾斜 | 约 -1.94° | -1.96° |
| walk 上身平均侧倾 | 约 1.02° | 1.02° |
| walk 逐帧蒙皮鞋底最低高度 | -0.3 mm | 约 0 mm |
| walk 全周期亚帧鞋底高度范围 | 约 0–106 mm | -3.1–3.5 mm |
| walk 循环首尾最大骨骼角差 / 位置差 | 接近 0 | 0° / 0 mm |

[balance_before.json](balance_before.json)、[balance_after.json](balance_after.json)、[ground_contact.json](ground_contact.json)、[posture.json](posture.json)、[geometry.json](geometry.json) 均针对导出 GLB 测量。关节摆动不会每帧强行对齐骨盆，保留正常重心变化。前/侧面五阶段对比图上排为原版本、下排为本版本；两者采样周期位置相近，不是完全相同的关键帧。

## 共享速度与播放参考

共享运动 Component：步行 2.0、Shift 疾跑 4.2、御剑水平 22、升降 12 m/s。起跳初速 6、重力 18 保持。跑档阈值为 3.0，普通走路不误进 run。

依据较低脚踝在相邻支撑阶段向后运动的速度估计参考：walk 中位数 1.659 m/s、run 均值 4.224 m/s，见 [build_report.json](build_report.json)。这是一项动画步幅估计，并非逐接触点足部锁定；跟趾滚动与支撑阶段边界会造成瞬时差异。实际播放 walk 约 1.206 倍、run 约 0.994 倍，限制在已有播放护栏内。提高全场景移动效率的同时保持人体节奏。

## 复现

在仓库根运行（`Blender` / `Godot` 替换为本机可执行文件）：

```sh
Blender --background --factory-startup --python-exit-code 1 --python tools/art/build_balanced_motion_20261006.py
Blender --background --factory-startup --python-exit-code 1 --python tools/art/export_cultivator_aligned_motion_20260927.py -- --source docs/art/cultivator_balanced_motion_20261006/cultivator_balanced_motion_20261006.blend --output src/game/actors/swordsman/models/cultivator_balanced_motion_20261006.glb
Godot --headless --path src --import
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_locomotion_balance.py -- --glb src/game/actors/swordsman/models/cultivator_balanced_motion_20261006.glb --report docs/art/cultivator_balanced_motion_20261006/balance_after.json --check
python3 tools/verify/run_all.py --with-tests
```

建造器从保留的 aligned 源重建动作，会覆盖本版本正在编辑的源；手工编辑本版本后，使用带 `--source` 的独立导出命令即可。已将保存后的 Blender 源重新打开并独立导出，确认七段动作、22 骨和贴地测量仍通过。

依据：[决策](../../../notes/implemented/art/2026-09-27-human-locomotion-on-v9.md)、[实机记录](../../playtest/2026-10-06-motion-balance/report.md)。

2026-10-08 起，现役步行改用[收臂版本](../cultivator_balanced_motion_20261008/asset_ledger.md)。本目录的源、导出和预览保留作比较。
