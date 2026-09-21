# 实机验收：v9 人物（cultivator_tripo_v9）接入全移动链

日期：2026-09-21
依据：notes/implemented/art/2026-09-19-cultivator-tripo-v9-runtime.md
证据目录：`docs/playtest/evidence/`
执行方式：`godot --path src --script res://tests/v9_visual_playtest.gd -- --capture-prefix=...`
（**窗口模式**；无头不出帧，`get_image()` 取不到内容，因此截图必须走窗口渲染。）

## 结论

v9 人物已接入全移动链，四个可驱动状态在真实场景中与实时读数同源，实机 0 失败。

| 状态 | 实时 `current_clip` | 落地 | 竖直速度 | 速度 | 截图 |
|---|---|---|---|---|---|
| 待机 | `idle` | 是 | +0.00 | 0.00 m/s | `v9-idle.png` |
| 行走 | `walk` | 是 | +0.00 | 1.55 m/s | `v9-walk.png` |
| **疾行（W+Shift）** | **`run`** | 是 | +0.00 | 3.45 m/s | `v9-run.png` |
| 御剑 | `idle` @0.6 | 否 | +0.00 | 12.00 m/s | `v9-flight.png` |
| 腾空 | `jump` | 否 | +5.70 | 0.00 m/s | `v9-jump.png` |

每个状态都额外断言「表现层快照的 `current_clip` == `AnimationPlayer.current_animation`」，
确保画面里看到的动作与 HUD/验收读到的读数来自同一处，不存在两套状态。

截图可见：人物双脚踩在网格地面上（不再是 v9 源模型下沉 1 m 的状态），待机与行走姿态自然，
腾空有收腿，御剑有前倾并可见飞剑。

## `run` 可达性：已修复（原为死分支）

原状况：地面 `move_speed = 4.0 m/s` 低于 `RUN_SPEED_MPS = 5.5`，御剑 12.0 m/s 又被 `flying`
分支抢先映射到 `idle`，两者叠加使 `run` clip 在真实玩法中**永远不可触发**。

修复依据是实测步幅而非估计值（`tools/art/measure_clip_stride.py`：原地 clip 的步长 = 支撑期
脚相对身体的后移量）：

| 项 | 修复前 | 修复后 | 依据 |
|---|---|---|---|
| `move_speed` | 4.0 | **1.55** | 贴近 walk 自然速度 1.288 → 速率 1.20 而非 2.5 |
| `sprint_speed` | 无 | **3.45** | 贴近 run 自然速度 3.426 → 速率 1.01 |
| `RUN_SPEED_MPS` | 5.5 | **2.2** | 取两档之间，Shift 真的切换 clip |
| 速率夹取 | 0.5–2.5 | **0.6–1.8** | 步幅已正确，过宽上限只会变成快放 |

实机证据：W+Shift **3 帧**内进入 `run`（3.45 m/s），松开 **2 帧**退回 `walk`，
静立按 Shift 仍为 `idle`（不误触发）。截图 `v9-run.png`。

## 覆盖范围

| 场景 / 路径 | 验证方式 | 结果 |
|---|---|---|
| 默认 `swordsman.tscn` | 单测 + 实机 | v9 视觉，1 Skeleton3D / 1 AnimationPlayer / 4 clip |
| motion preview | 单测 `test_motion_preview.gd` 132 断言 | 与正式角色同源 v9 |
| 青玉纸样板 | 单测 + `jade_paper_sample.gd` 启动断言 | 不再做 v7 视觉替换，飞剑仍装配 |
| 动作工作台 | 实机四状态 + `motion_stage_playtest.gd` 14 批次 | 0 失败 |
| 移动庭院 | `character_movement_playtest.gd` | 0 失败 |
| 群山宗门 | `mountain_traversal_playtest.gd --batch=presentation` | 0 失败 |
| 群山视觉 | `mountain_visual_playtest.gd --verify=rig` | PASS（负向控制改为 exit 1） |
| 旧三条视觉链 | `test_cultivator_tripo_v9_visual.gd` | 仍可独立加载（回退资产保留） |

## 未做

- 编辑器嵌入 Game 视图的人工验收（与 2026-09-18 镜头验收同一条遗留项）。
- 3 × 4096² 贴图在 `gl_compatibility` 下的实机内存/帧率测量。
- `run` 可达性调整（见上，属玩法决策）。
