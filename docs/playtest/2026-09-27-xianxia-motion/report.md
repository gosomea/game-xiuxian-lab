# 修仙移动动作 v1 实机验收

2026-09-27；Godot 4.6 窗口模式，`motion_stage.tscn` 使用共享 `swordsman.tscn` 与动作预览装配。

- `motion-stage-idle/run/jump/flight.png` 来自动作工作台真实输入截图。其旧脚本 `run` 截图分支未按 Shift，HUD 显示 1.55 m/s，故该张只作普通步行的侧面参考，不能证明疾行动画。
- `real-motion-idle/walk/run/flight/jump.png` 来自 `src/tests/xianxia_motion_playtest.gd` 的真实输入。读回：静止 `idle_guarded`、步行 1.55 m/s→`walk`、Shift 疾行 2.25 m/s→`run`、御剑→`sword_ride`、离地→`jump`；每帧的公开快照与 `AnimationPlayer.current_animation` 一致。脚本完成时失败 0。
- 新角色动作在共享工作台和预览之外还通过运行时测试检查共享 `swordsman.tscn`、青玉样板、动作预览的同源路径。局部美术检查见 `docs/art/cultivator_xianxia_motion_v1/renders/`。
- 暂停预览原先出现 T 姿态；`CultivatorSkeletonPresentation.reset_pose()` 现在显式 `advance(0)` 写入骨架。修正后窗口截图 `verified-preview-idle.png` 确认预览与正式角色都处于新版负手待机，截图脚本失败 0。

局限：上述截图的实机角色较小，适合验证场景装配和状态选择；姿态细节以 Blender 近景蒙皮渲染为准。最终画风和正式修仙动作气质仍需使用者审看。
