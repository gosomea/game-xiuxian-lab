# 本命剑与剑阵用剑 · 2026-10-09

## 来源

`tools/art/generate_bound_sword_20261009.py` 在本地 Blender 5.2.1 程序生成，无第三方素材。配色沿用现役御剑（`tools/art/generate_mountain_realm.py` 的 sword 阶段）：钢色剑身、青铜剑格、浅褐缠柄。现役御剑 `src/game/abilities/sword_flight/models/flying_sword.glb` 未改动，仍只用于御剑站立。

| 文件 | 用途 | 规格 |
|---|---|---|
| `src/game/shared/sword_cast/models/bound_sword.glb` | 悬浮本命剑、飞剑出击 | 全长 0.99 m（剑尖 −0.78 m、柄尾 +0.21 m），剑格宽 0.15 m；86 三角面，单网格三材质 |
| `src/game/abilities/sword_array/models/array_sword.glb` | 剑阵 | 全长 0.86 m，剑格宽 0.12 m；38 三角面，单网格单材质（青玉钢，带弱自发光），供 MultiMesh 一次绘制 |
| `bound_sword_20261009.blend` | 可编辑源 | 两把剑并排 |
| `preview.png` | 俯视预览 | 上为本命剑，下为剑阵用剑；非运行时素材 |
| `build_report.json` | 生成器自检 | 三角面数、材质与 glTF 坐标包围盒 |

## 约定

导出后（glTF，Y 向上）剑尖朝局部 −Z，原点在剑格中心，剑身宽面朝局部 ±Y，水平放置时俯视镜头看到的是剑面。Godot 中两把剑都以 1.4 倍绘制（`SwordCastPresentation.DISPLAY_SCALE`、`SwordArrayView.DISPLAY_SCALE`），因为 14 m 正交视野下原尺寸只有几像素宽；命中判定仍按 `SwordCastComponent` 的半径参数，不随绘制放大。

## 复现

```sh
Blender --background --factory-startup --python-exit-code 1 --python tools/art/generate_bound_sword_20261009.py
Godot --headless --path src --import
```

生成器会覆盖本目录的源、预览与两份 GLB。

依据：[剑法工作台决策](../../../notes/implemented/gameplay/2026-10-09-sword-workbench.md)。
