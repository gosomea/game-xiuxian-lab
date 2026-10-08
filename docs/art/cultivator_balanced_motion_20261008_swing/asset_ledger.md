# 步行前摆送到胸前 · 2026-10-08

## 来源与现役装配

在[收臂版本](../cultivator_balanced_motion_20261008/asset_ledger.md)上只加 walk 上臂的前屈。前臂外收、腿链、网格和其余六段动作保持原样。收臂版本的源、导出和预览保留作比较。

- 可编辑源：`cultivator_balanced_motion_20261008_swing.blend`。
- 游戏导出：`src/game/actors/swordsman/models/cultivator_balanced_motion_20261008_swing.glb`。
- 现役入口仍是 `cultivator_aligned_motion_20260927_visual.tscn`，模型子节点名不变。

## 步行前摆

收臂之后，走路的手最远只到肩前 6.6 cm，上臂只到身前 2°，看起来停在胯边。后摆本身已经到肩后 16–20 cm。本版按每只手原有的前后相位，只在摆向前的半段绕肩线加前屈，顶点 26°。后半段不加。前臂本地旋转不改，所以外展不被重新打开。

| 指标 | 收臂版 | 本版本 |
|---|---:|---:|
| 左 / 右手腕最远（肩前） | 0.066 / 0.062 m | 0.277 / 0.277 m |
| 左 / 右手腕最远（胸口前） | 约 0.08 m | 0.287 / 0.276 m |
| 左 / 右手腕最后（肩后） | 0.163 / 0.200 m | 0.163 / 0.200 m |
| walk 手腕最大外展 | 0.090 m | 0.089 m |
| 走路双踝相对骨盆平均前移 | 0.76 cm | 0.76 cm |
| 走路循环接缝 | 0° / 0 mm | 0° / 0 mm |

正侧面五相位在 `frames/`。导出测量见 [geometry.json](geometry.json)、[balance_after.json](balance_after.json)、[ground_contact.json](ground_contact.json)、[build_report.json](build_report.json)。

## 复现

在仓库根运行（`Blender` 替换为本机可执行文件）：

```sh
Blender --background --factory-startup --python-exit-code 1 --python tools/art/build_walk_forward_swing_20261008.py
Godot --headless --path src --import
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_aligned_motion_geometry.py -- --glb src/game/actors/swordsman/models/cultivator_balanced_motion_20261008_swing.glb --report docs/art/cultivator_balanced_motion_20261008_swing/geometry.json
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_locomotion_balance.py -- --glb src/game/actors/swordsman/models/cultivator_balanced_motion_20261008_swing.glb --report docs/art/cultivator_balanced_motion_20261008_swing/balance_after.json --check
```

建造器从收臂版源重建，会覆盖本版本正在编辑的源。

依据：[决策](../../../notes/implemented/art/2026-09-27-human-locomotion-on-v9.md)。
