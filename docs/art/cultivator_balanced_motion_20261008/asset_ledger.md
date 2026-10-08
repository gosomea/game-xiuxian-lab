# 步行前臂内收 · 2026-10-08

## 来源与现役装配

在[20261006 重心校正版](../cultivator_balanced_motion_20261006/asset_ledger.md)上只改 walk 的前臂。人物网格、蒙皮、其余六段动作和腿链校正保持原样。20261006 的源、导出和预览保留作比较。

- 可编辑源：`cultivator_balanced_motion_20261008.blend`。
- 游戏导出：`src/game/actors/swordsman/models/cultivator_balanced_motion_20261008.glb`。
- 现役入口仍是 `cultivator_aligned_motion_20260927_visual.tscn`，模型子节点名不变。

## 步行前臂

站立手腕在肩外侧左手 8.5 cm、右手 7.7 cm。20261006 的走路后摆把同一距离推到约 12.8 cm，肘却几乎钉在 6.5 cm。本版绕肘把超过站立值的前臂沿最短弧收回，手掌世界朝向保持不变。上臂、腿和根运动不改。

| 指标 | 20261006 | 本版本 |
|---|---:|---:|
| walk 手腕最大外展 | 0.120 m | 0.090 m |
| walk 手肘最大外展 | 0.066 m | 0.066 m |
| walk 左右手腕前后摆幅 | 0.228 / 0.264 m | 0.223 / 0.258 m |
| run 手腕最大外展 | 0.152 m | 0.152 m |
| 走路双踝相对骨盆平均前移 | 0.76 cm | 0.76 cm |
| 走路循环接缝 | 0° / 0 mm | 0° / 0 mm |

前臂最大转角左手 9.7°、右手 11.5°。正侧面五相位在 `frames/`。导出测量见 [geometry.json](geometry.json)、[balance_after.json](balance_after.json)、[ground_contact.json](ground_contact.json)、[build_report.json](build_report.json)。

## 复现

在仓库根运行（`Blender` 替换为本机可执行文件）：

```sh
Blender --background --factory-startup --python-exit-code 1 --python tools/art/build_walk_arm_inward_20261008.py
Godot --headless --path src --import
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_aligned_motion_geometry.py -- --glb src/game/actors/swordsman/models/cultivator_balanced_motion_20261008.glb --report docs/art/cultivator_balanced_motion_20261008/geometry.json
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_locomotion_balance.py -- --glb src/game/actors/swordsman/models/cultivator_balanced_motion_20261008.glb --report docs/art/cultivator_balanced_motion_20261008/balance_after.json --check
```

建造器从 20261006 源重建，会覆盖本版本正在编辑的源。

依据：[决策](../../../notes/implemented/art/2026-09-27-human-locomotion-on-v9.md)。

同日后续：现役步行改为[前摆版本](../cultivator_balanced_motion_20261008_swing/asset_ledger.md)。本目录保留收臂、前摆仍停在胯边的比较版本。
