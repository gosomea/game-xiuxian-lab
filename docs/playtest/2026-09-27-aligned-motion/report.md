# 收臂与正向跳跃验收

## 验收范围

默认角色、动作预览与青玉纸样板接入 `cultivator_aligned_motion_20260927_visual.tscn`。人物外形和骨架维持 v9；走路与疾跑收窄摆臂，跳跃改为双脚正向起跳。旧动画资产保留。

| 验收点 | 结果 |
|---|---|
| 正侧面连续帧 | [正面](../../art/cultivator_aligned_motion_20260927/front_contact_sheet.png)与[侧面](../../art/cultivator_aligned_motion_20260927/side_contact_sheet.png)五相位图显示：走跑手臂靠近身体且仍前后摆动；跳跃面朝前，双脚没有盘坐收腿。 |
| 导出 GLB 逐帧朝向与摆臂 | [报告](../../art/cultivator_aligned_motion_20260927/geometry.json)：跳跃双肩最大偏航 0.008°、骨盆 0.985°、头部 0.019°，双脚横向间距最大 0.222 m；走路 / 疾跑手腕最大外展 0.120 / 0.152 m。 |
| 姿态与鞋底 | [姿态](../../art/cultivator_aligned_motion_20260927/posture.json)和[鞋底](../../art/cultivator_aligned_motion_20260927/ground_contact.json)量具通过；跳跃髋→头平均后仰 2.84°、侧倾约 0.03°，走跑仍贴地。 |
| Godot 导入 | `Godot --headless --path src --import` 成功，新 GLB 及三张贴图已导入。 |
| 项目门禁与测试 | `python3 tools/verify/run_all.py --with-tests`：门禁和 27 项负向控制通过；运行时测试 1226 通过、0 失败。 |
| 工作台物理与状态 | `motion_stage_playtest.gd --batch=assembly,idle,run,jump,landing`：失败 0；跳跃有 41 个非着地物理帧、约 1.05 m 实际升高、落地恢复 `idle`。 |
| 真实按键切换 | `xianxia_motion_playtest.gd`：W 为 `walk` 1.25 m/s，W+Shift 为 `run` 2.25 m/s；空中为 `jump`，御剑为 `sword_ride`；状态快照与 AnimationPlayer 实际 clip 一致，失败 0。 |
| 窗口截图 | [站立](aligned-idle.png)、[走路](aligned-walk.png)、[疾跑](aligned-run.png)、[跳跃](aligned-jump.png)、[御剑](aligned-flight.png)来自 Godot 窗口模式真实输入。工作台角色较小，局部动作以上述连续帧为主要视觉证据。 |

**仍需人工体验：** 跳跃的膝部预备比较轻，主观起跳力度与落地缓冲尚未得到使用者认可。此次验收证明原来的斜向、盘坐姿势已经从现役资产移除，并没有把“自然度”视为自动测试可完全判定的结论。
