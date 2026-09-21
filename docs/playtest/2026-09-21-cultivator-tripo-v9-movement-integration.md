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
| 行走 | `walk` | 是 | +0.00 | 4.00 m/s | `v9-walk.png` |
| 御剑 | `idle` @0.6 | 否 | +3.00 | 12.00 m/s | `v9-flight.png` |
| 腾空 | `jump` | 否 | +6.00 | 0.00 m/s | `v9-jump.png` |

每个状态都额外断言「表现层快照的 `current_clip` == `AnimationPlayer.current_animation`」，
确保画面里看到的动作与 HUD/验收读到的读数来自同一处，不存在两套状态。

截图可见：人物双脚踩在网格地面上（不再是 v9 源模型下沉 1 m 的状态），待机与行走姿态自然，
腾空有收腿，御剑有前倾并可见飞剑。

## 一个如实记录的既有问题：`run` 在真实玩法中不可达

- 地面 `move_speed = 4.0 m/s`，低于表现层 `RUN_SPEED_MPS = 5.5`，因此**着地状态永远选不到 run**。
- 御剑 `flight_speed = 12.0 m/s` 确实超过阈值，但表现层的分支顺序是 `flying` 优先于速度，
  于是映射到 `idle @0.6` 而不是 `run`。
- 两者叠加的结果：`run` clip 已正确打进运行时资产（0.767 s、线性循环、已被
  `test_cultivator_tripo_v9_visual.gd` 断言存在且可播放），但在真实玩法里当前**无法被触发**。
- 这是**从 v7 就存在的阈值/常量关系，不是 v9 引入的**：`git show HEAD` 显示
  `cultivator_skeleton_presentation.gd` 的 `WALK_SPEED_MPS=0.3 / RUN_SPEED_MPS=5.5` 与
  `swordsman_motion_component.gd` 的 `move_speed=4.0 / flight_speed=12.0` 在换人前后完全一致。

本报告不把它算作 v9 的失败，也**没有**用伪造速度去凑一张 run 截图。该用例改为断言
「着地全速仍映射到 walk」+「御剑速度确实超过阈值但被 flying 分支抢先」，把事实固定下来。
是否要调整阈值或让地面奔跑可达，属于独立的玩法决策，不在本次换人范围内。

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
