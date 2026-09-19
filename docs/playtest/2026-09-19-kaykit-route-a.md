# 路线 A 代表链验收（KayKit 原生骨架直接接 Godot）

日期：2026-09-19

范围：`src/game/actors/swordsman/kaykit_route_a/**`、`models/kaykit_rogue_hooded_route_a*`、`tests/test_kaykit_route_a_visual.gd`。**独立可复用视觉链**，不改 `jade_paper_sample`。

结论：KayKit `Rogue_Hooded` 原生 GLB（41 骨 / 76 clips）**不经重定向**直接接入 Godot，五态动作映射经公开 API 验证通过；结构与状态自动证据齐备。**观感与审美未验收**——headless 自动截图未能完成，须由主代理或使用者实机确认。

依据：[KayKit 同模型双路线 A/B note](../../notes/proposed/art/2026-09-19-character-model-animation-route-comparison.md) §2「路线 A」、§7 阶段 2。

## 交付物

| 文件 | 作用 |
|---|---|
| `src/game/actors/swordsman/kaykit_route_a/kaykit_route_a_presentation.gd` | 表现层：公开 API + 五态映射 + 武器隐藏 |
| `src/game/actors/swordsman/kaykit_route_a/kaykit_route_a_visual.tscn` | 可复用视觉子树（模型实例 + 表现层） |
| `src/game/actors/swordsman/kaykit_route_a/kaykit_route_a_stage.tscn` | 独立演示台（相机 / 光 / 地面 + 键盘驱动） |
| `src/game/actors/swordsman/kaykit_route_a/kaykit_route_a_stage.gd` | 演示台键盘驱动（1/2/3/4/5/0/Esc） |
| `src/tests/test_kaykit_route_a_visual.gd` | 回归测试 98 断言 |
| `src/game/actors/swordsman/models/kaykit_rogue_hooded_route_a.glb` | 原生 GLB（3,597,652 bytes，与上游逐字节一致） |

`src/tests/test_runner.gd` 仅在 `SUITES` 末尾追加一行注册；未改其它套件。

## 动作映射（受控 A/B）

阈值与步幅与 `CultivatorSkeletonPresentation` **逐字相同**，测试直接跨脚本比对常量，禁止只为一条路线调参。

| 状态 | clip（原生名） | 播放率 | 前倾 |
|---|---|---|---|
| idle | `Unarmed_Idle` | 1.0 | 0 |
| walk（> 0.3 m/s） | `Walking_A` | 速度 / 1.6，钳制 [0.5, 2.5] | 0 |
| run（> 5.5 m/s） | `Running_A` | 速度 / 3.2，钳制 [0.5, 2.5] | 0 |
| airborne（非着地） | `Jump_Idle` 循环 | 1.0 | 0 |
| flight（御剑） | **优先 `Jump_Idle`**，缺失回退 `Unarmed_Idle` | 0.6 | `deg_to_rad(21)` ≈ 0.366519 rad |

常量：`WALK_SPEED_MPS = 0.3`、`RUN_SPEED_MPS = 5.5`、`BLEND = 0.15`、`walk_stride = 1.6`、`run_stride = 3.2`、`FLIGHT_RATE = 0.6`。

阈值判定为**严格大于**：恰好 0.3 仍 idle、恰好 5.5 仍 walk（测试已锁）。

## 公共 API

本轮要求的 `set_motion_state(motion_mode, speed, is_grounded)` 已实现；`motion_mode ∈ {"ground", "air", "flight"}`，未知值按 `ground` 处理。

同时保留与既有骨骼表现层**同形状**的 `advance_state` / `sample_state` / `pose_state` / `reset_pose`，便于与路线 B/C 同位互换。另有只读 `hidden_parts()` 供验收核对。

`auto_read_actor`：`visual.tscn` 中默认 `false`（可单独实例化并由外部驱动）；挂到正式 `Swordsman` 下时置 `true`，即每帧读宿主 `motion()`。

## 武器与披风

- **隐藏 5 件武器**：`Knife`、`Knife_Offhand`、`1H_Crossbow`、`2H_Crossbow`、`Throwable`（上游自带展示挂件，会随攻击动作摆动并干扰 A/B 观感与 draw call 对照）。**只置 `visible = false`，不删除资源**。表现层在 `_ready` 断言必须恰好匹配 5 件，少一件即失败。
- **保留披风** `Rogue_Cape`（84 tris，刚体挂 `chest`）且**断言其可见**——它是路线 B 袍片对照的锚点。
- 材质与内嵌贴图随 GLB 导入，全部 12 个 mesh 均带贴图材质；合计 6,035 tris（与台账读数一致，测试锁定）。

## 自动证据

冻结场景结构（Godot 4.6 headless 导入读数）：

```
ROOT=kaykit_rogue_hooded_route_a cls=Node3D
  Rig [Node3D]
    Skeleton3D [Skeleton3D]      bones=41
      handslot_l / handslot_r / chest [BoneAttachment3D]
      Rogue_ArmLeft / Rogue_ArmRight / Rogue_Body /
      Rogue_Head_Hooded / Rogue_LegLeft / Rogue_LegRight
  AnimationPlayer                 clips=76
```

| 检查 | 结果 |
|---|---|
| `godot --headless --path src --import` | 通过，无错误 |
| `godot --headless --path src --quit-after 10 game/actors/swordsman/kaykit_route_a/kaykit_route_a_stage.tscn` | 独立舞台正常启动并打印五态键位，0 脚本错误 |
| `test_kaykit_route_a_visual.gd` | **98 断言通过 / 0 失败** |
| 全套运行测试 | **1,079 通过 / 0 失败**，0 `SCRIPT ERROR` |
| `verify_scenes.py` | 20 个目标全部合规 |
| `verify_packages.py` | 6 个目标全部合规 |
| `run_all.py --with-tests` | 门禁全绿 + 负向控制 27/27 |
| 能力目录重生成 | 无内容漂移 |

测试覆盖：场景实例化、原生骨架 41 骨、76 clips、映射所需 4 条 clip 可达、4 条持续状态 clip 显式线性循环、walk 推进超过两个周期仍播放且播放位置回绕、5 件武器隐藏、披风保留可见、12 mesh 贴图材质、6,035 tris、公开 API 形状、A/C 常量逐字一致、五态映射与播放率、阈值边界、`advance_state` 快照路径、`reset_pose` 归零、演示台结构与真实驱动。

## 未完成 / 未验证

**自动截图未完成，需主代理或使用者实机审美验收。**

- Godot AI 会话列表为空，无法使用编辑器内截图档；headless 下 `await RenderingServer.frame_post_draw` 在无渲染帧时不触发，截图脚本会挂住（本轮两次尝试均被主代理终止）。**已放弃 headless 截图路径，不再重试**。
- 因此以下均**未验收**：剪影与轮廓、配色与青玉纸白色卡的接近度、动作姿态观感、御剑 21 度前倾是否好看、走跑节奏与脚滑、披风随动的视觉合理性。
- 上述项目**不能由自动门禁代替**，须实机确认。
- 未做：draw call 实机统计、Godot 实机 60fps 性能、与路线 B/C 的同机位对照（B 尚在等人工 marker）。
- 未改 `jade_paper_sample`、未改共享 `asset_ledger`、未改 proposed note。

## 实机验收方式（建议）

1. 用 Godot 打开 `src/`，运行 `res://game/actors/swordsman/kaykit_route_a/kaykit_route_a_stage.tscn`。
2. 键位：`1`=idle `2`=walk `3`=run `4`=airborne `5`=flight `0`=reset `Esc`=退出；控制台会打印当前 clip / 播放率 / 前倾 / 隐藏件。
3. 重点观察：武器是否全程不可见、披风是否随胸骨合理摆动、五态切换有无姿态跳变、御剑前倾是否自然。

## 与其它资产的关系

- **基线 C**（`cultivator_rigged.glb` + `cultivator_skeleton_presentation.gd`）零改动，仍是对照基线。
- 路线 B（Mixamo）本轮**未参与**：其 marker 人工步骤尚未进行。
- 上游 GLB 未改动（sha256 不变）；本目录全部为新文件，零删除、零覆盖。
- 临时诊断文件 `src/tests/_probe_tmp.gd` / `.tscn` 与截图探针 `_route_a_shots.gd` / `.tscn` **已删除**；它们不是探索资产。
