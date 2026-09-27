# 普通站姿默认值验收

2026-09-27；Godot 4.6 窗口运行 `motion_stage.tscn`，真实渲染截图为 `normal-idle.png`。

- 正式角色与暂停动作预览均双臂自然下垂，未背手；普通静止由 `idle` 驱动。
- `CultivatorSkeletonPresentation.prefer_guarded_idle` 默认关闭；`reset_pose()` 与速度归零后的自动状态统一选择 `idle`。`idle_guarded` 仍可在工作台显式预览，未被移动逻辑自动选用。
- `python3 tools/verify/run_all.py --with-tests`：Tier 0 与 27 项负向控制通过，运行时测试 1220 通过、0 失败。
- `motion_stage_playtest.gd` 窗口截图模式：失败 0，图片 1280×800。
- `xianxia_motion_playtest.gd` 真实输入状态链：静止读回 `clip=idle`、速度 0；静止按 Shift 仍为 `idle`，整轮失败 0。

这轮只调整静止默认动作，不评价步行品质；步行采用现成动作片段的对比仍需单独实施。
