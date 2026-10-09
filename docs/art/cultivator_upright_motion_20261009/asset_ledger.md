# 上身扶正与站立手臂中立位 · 2026-10-09

## 来源与现役装配

从[收臂版本](../cultivator_balanced_motion_20261008/asset_ledger.md)的源重建，不叠加[前摆版本](../cultivator_balanced_motion_20261008_swing/asset_ledger.md)的前屈层。网格、UV、蒙皮权重、rest 骨架、腿链、根运动与节奏不变；两个旧版本的源、导出与预览保留作比较。

- 可编辑源：`cultivator_upright_motion_20261009.blend`。
- 游戏导出：`src/game/actors/swordsman/models/cultivator_upright_motion_20261009.glb`。
- 现役入口仍是 `cultivator_aligned_motion_20260927_visual.tscn`，模型子节点名不变。

2026-10-10 起，本文件的完整 GLB/Blender 源作为共享几何、材质、贴图、rest 与蒙皮依赖保留；现役动作改为独立库，可编辑动作源使用相对链接的轻量版本，见[拆分台账](../cultivator_motion_library_20261010/asset_ledger.md)。本版本的完整七段动作继续保留作逐关键帧回归，不覆盖它们来保存新的纯动作版本。

## 问题与修法

旧版站立时颈在骨盆后 4.9 cm、肩线在后 6.4 cm，骨盆到颈后仰 5.4°（胸椎到颈约 8°，头再前探约 16° 掩盖了它），上臂与前臂又各向后摆约 11°，手腕落在骨盆后约 16 cm。`idle_guarded`、`meditate` 上身相同，`sword_ride`、`jump` 相近，`run` 本来直立。

1. 除 `run` 外，每段在 Spine / Spine1 / Spine2 按 0.2 / 0.35 / 0.45 分摊一个恒定前倾，使骨盆到颈平均为 0°；Neck 保持原世界朝向，头不额外前探。
2. `idle`、`idle_guarded`、`sword_ride`：上臂中立位设为身前 2°，前臂前屈使手腕在骨盆前 3 cm。`meditate`、`jump`、`run` 的手臂保持原世界朝向，只随肩平移。
3. `walk`：按每只手原有前后相位，把上臂摆动线性重映射到身后 16° 至身前 20°；摆动平面跟随逐帧肩线，横向外展不变。前摆顶点已达肩前 0.22 m 以上，肘屈补偿求解结果为 0°。

每段恒定量见 [build_report.json](build_report.json) 的 `plan`：上身前倾 idle / idle_guarded 9.83°、walk 10.34°、jump 11.38°、meditate 9.84°、sword_ride 7.57°（分摊到三节脊柱，骨盆到颈的实际改变约为一半）。

| 指标（clip 平均，骨盆为原点） | swing 版 | 本版本 |
|---|---:|---:|
| idle 颈 / 肩线 | −4.9 / −6.4 cm | 0.0 / −2.3 cm |
| idle 骨盆到颈倾角 | −5.4° | 0.0° |
| idle 左 / 右手腕 | −16.4 / −15.8 cm | +3.0 / +3.0 cm |
| sword_ride 左 / 右手腕 | −14.1 / −13.5 cm | +3.0 / +3.0 cm |
| walk 骨盆到颈倾角 | −5.6° | 0.0° |
| walk 左 / 右上臂摆动范围 | 收臂版 −25..−1 / −26..+3°，swing 版前半段再加至多 26° | −18..+20 / −17..+22° |
| walk 左 / 右手腕最远（肩前） | 0.277 / 0.277 m | 0.234 / 0.221 m |
| walk 左 / 右手腕最后（肩后） | 0.163 / 0.200 m | 0.103 / 0.121 m |
| walk 手腕最大外展 | 0.089 m | 0.089 / 0.080 m |
| meditate 手腕前移（随肩） | — | 约 +4 cm |
| 头相对骨盆倾角（posture 量具，idle / walk / run） | — | +2.7 / +2.8 / +3.4° |

接缝与源一致：walk 0°，idle / idle_guarded / sword_ride / meditate ≤ 0.13°；run 8.9° 与 jump 5.0° 是源文件既有差异，本版未改变。

## 证据

- `compare_standing.png`：上排 swing 版、下排本版本；列依次为侧面 idle、正面 idle、侧面 sword_ride、侧面 meditate（侧面人物朝左）。
- `compare_walk.png`：第一排 swing 版侧面 walk 五相位，第二排本版本侧面，第三排本版本正面。
- `frames/`：七段动作正侧面各五相位。
- 量具输出：[geometry.json](geometry.json)、[balance_after.json](balance_after.json)、[ground_contact.json](ground_contact.json)、[posture.json](posture.json)，均无 problems。
- 运行时：`src/tests/test_cultivator_motion_20260927_visual.gd` 新增 idle 矢状面判据，并以 swing 版作负向控制；运行记录见 [2026-10-09 上身扶正](../../playtest/2026-10-09-upright-motion/report.md)。

## 复现

在仓库根运行（`Blender`、`Godot` 替换为本机可执行文件）：

```sh
Blender --background --factory-startup --python-exit-code 1 --python tools/art/build_upright_motion_20261009.py
Godot --headless --path src --import
M=src/game/actors/swordsman/models/cultivator_upright_motion_20261009.glb
D=docs/art/cultivator_upright_motion_20261009
Blender -b --factory-startup --python-exit-code 1 --python tools/art/measure_aligned_motion_geometry.py -- --glb $M --report $D/geometry.json
Blender -b --factory-startup --python-exit-code 1 --python tools/art/measure_locomotion_balance.py -- --glb $M --report $D/balance_after.json --check
Blender -b --factory-startup --python-exit-code 1 --python tools/art/measure_glb_ground_contact.py -- --glb $M --report $D/ground_contact.json
Blender -b --factory-startup --python-exit-code 1 --python tools/art/measure_human_motion_posture.py -- --glb $M --report $D/posture.json
Blender -b --factory-startup --python-exit-code 1 --python tools/art/render_cultivator_aligned_motion.py -- --glb $M --out $D/frames --clips idle,walk,idle_guarded,sword_ride,meditate,run,jump
```

建造器从收臂版源重建，会覆盖本版本正在编辑的源与导出。

依据：[决策](../../../notes/implemented/art/2026-09-27-human-locomotion-on-v9.md)。
