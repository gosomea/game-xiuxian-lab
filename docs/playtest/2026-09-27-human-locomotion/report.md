# v9 人物步行、Shift 疾跑与跳跃重做验收

## 范围

默认 `Swordsman`、动作工作台、动作预览和青玉纸样板统一引用 `cultivator_human_motion_20260927_visual.tscn`。该视觉场景仍使用 v9 人物，只把步行、疾跑、跳跃切换为重定向的完整人体动作。旧版 `cultivator_motion_20260927` 源与导出均保留。

## 证据

| 验收点 | 结果 |
|---|---|
| Blender 最终 GLB 五相位侧面与正面检查 | 步行左右交替迈步且正面中轴基本竖直；疾跑有屈膝与腾空；跳跃从屈膝过渡到离地。见[侧面](../../art/cultivator_human_motion_20260927/contact_sheet.png)和[正面](../../art/cultivator_human_motion_20260927/front_contact_sheet.png)。 |
| 固定朝向逐帧姿态检查 | 上次漏检步行侧面持续后仰约 10.4°，这次校正后平均后仰 1.94°；疾跑平均前倾 3.32°；跳跃原最高侧倾 22.8°，校正后各帧不超过 2°。见[逐帧报告](../../art/cultivator_human_motion_20260927/posture.json)。 |
| 导出 GLB 逐帧鞋底检查 | 步行最低 -0.3 毫米、跑步最低 +0.9 毫米，见[报告](../../art/cultivator_human_motion_20260927/ground_contact.json)。 |
| Godot 导入 | `Godot --headless --path src --import` 成功，新 GLB 导入成功。 |
| 单元与装配测试 | `Godot --headless --path src tests/test_runner.tscn`：1226 通过、0 失败。 |
| 动作工作台物理链 | `motion_stage_playtest.gd --batch=assembly,idle,run,jump,landing`：失败 0。普通步行实际 1.25 米/秒，跳跃顶点约 1.05 米并落地。 |
| 移动庭院回归 | `character_movement_playtest.gd`：失败 0；屏幕相对移动、斜向限速、四边障碍、转向、镜头和目录返回通过。 |
| Shift 与动作切换 | `xianxia_motion_playtest.gd` 窗口模式：普通走路 `walk` 1.25 米/秒；W+Shift 进入 `run` 2.25 米/秒用 2 帧，松开 Shift 回 `walk` 用 2 帧；离地为 `jump`。全程状态快照与 AnimationPlayer 当前 clip 一致，失败 0。 |
| 正式场景窗口渲染 | [待机](human-idle.png)、[走路](human-walk.png)、[疾跑](human-run.png)、[跳跃](human-jump.png)与[御剑](human-flight.png)均由同一窗口运行的真实输入截图产生。动作工作台镜头较远，因此姿态细节以上述 Blender 连续帧为主要视觉证据。 |

这次姿态修正后重新导入 Godot，并重新运行全套门禁与测试（1226 通过、0 失败）、真实按键状态链（失败 0）、窗口截图和逐帧鞋底检查（所有接地动作通过）。普通速度仍为 1.25 米/秒，Shift 速度仍为 2.25 米/秒。数值和静帧能验证持续倾斜已消除；完整步态的主观自然度仍需在动作工作台看连续运动。
