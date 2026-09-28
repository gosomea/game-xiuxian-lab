# 共享疾跑全场景验收 · 2026-09-28

## 修复与范围

共享 `SwordsmanMovement` 已拥有疾跑速度选择。镜头实验室和青玉纸白样板遗漏了 Shift 意图传递；移动庭院还使用独立按键表。
本轮将八个现役修士场景统一到 `MovementLabInput` 的默认 Shift 跟踪和 `sprint_input()` 读口，补充缺失的 HUD 提示。
能力仍从组件取输入，场景不维护独立的速度逻辑。
依据：[共享疾跑接入决策](../../notes/implemented/gameplay/2026-09-28-shared-sprint-scene-input.md)。

## 环境与方法

- Godot 4.6.stable.official.89cea1439，CLI 无头运行。
- Godot AI 会话列表为空，采用独立 CLI 进程验收。
- `test_all_scene_sprint.gd` 从真实子实验清单逐项加载场景，通过 `Input.parse_input_event` 注入按键，推进真实物理与处理帧，读取共享组件的实际速度和表现层 clip。
- 不直接赋值角色输入、不手工调用能力 tick。每场景 15 项断言，八场景共 120 项。
- 全量测试通过后，另以临时 CLI 包装入口单独执行该场景验收套件，结果 120 通过、0 失败；现有动作 playtest 也另行验证角色完整状态链。

## 场景结果

下表为独立场景验收运行的实际读回，速度单位为 m/s。

| 场景 | W 步行 | W + Shift 疾跑 | 松开 Shift | 失焦 | 结果 |
|---|---:|---:|---:|---:|---|
| 镜头实验室 | 1.25 | 2.25 | 1.25 | 0.00 | PASS |
| 人物动作工作台（实时模式） | 1.25 | 2.25 | 1.25 | 0.00 | PASS |
| 地形接触训练场 | 1.25 | 2.25 | 1.25 | 0.00 | PASS |
| 御剑飞行训练场（地面） | 1.25 | 2.25 | 1.25 | 0.00 | PASS |
| 状态切换压力场 | 1.25 | 2.25 | 1.25 | 0.00 | PASS |
| 移动庭院 | 1.25 | 2.25 | 1.25 | 0.00 | PASS |
| 群山宗门 | 1.25 | 2.25 | 1.25 | 0.00 | PASS |
| 青玉纸白样板 | 1.25 | 2.25 | 1.25 | 0.00 | PASS |

全部场景均验证：步行时 `walk`、疾跑时 `run`、松开 Shift 恢复 `walk`；只按 Shift 时速度为零且保持 `idle`；失焦清疾跑意图与移动速度。

## 检查与运行证据

```text
python3 tools/verify/run_all.py --with-tests
负向控制全部通过（27/27）
test_all_scene_sprint.gd：通过 120 / 失败 0
测试合计：通过 1224，失败 0
门禁全部通过（Tier <= 0）

Godot --headless --path src --script res://tests/xianxia_motion_playtest.gd
idle: clip=idle grounded=true speed=0.00
walk: clip=walk grounded=true speed=1.25
run: clip=run grounded=true speed=2.25
W+Shift 进入 run 档：2 帧；松开 Shift 退回 walk：2 帧
flight: clip=sword_ride grounded=false speed=12.00
jump: clip=jump grounded=false vspd=+5.70 speed=0.00
XIANXIA_MOTION_PLAYTEST 完成：失败 0
```

复验八场景完整读回可直接运行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path src tests/test_runner.tscn
```

输出中的 `SPRINT_SCENE` 行记录每场景实际速度，场景验收套件已登记在默认测试入口。

## 验证边界

本轮验收证明八个场景的键盘输入、共享能力执行及动画状态切换一致。未进行窗口画面或主观手感的新验收，也未测遍场地每个位置。
独立二维坊市使用另一套二维角色，本轮未将三维修士能力移植到该探索路线。
