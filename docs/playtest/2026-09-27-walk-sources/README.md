# 2026-09-27 步行动作来源独立验收

场景：`res://levels/experiments/character_movement/walk_source_comparison.tscn`。窗口运行后按 `1 / 2 / 3` 切现役 / KayKit / CMU；三者使用同一人物、镜头、地面和 `1.55 m/s` 角色速度。空格暂停、V 换机位、R 重走、Esc 返回移动目录。

## 运行证据

- `godot --headless --path src --script res://tests/walk_source_comparison_playtest.gd`：三个候选均加载、绑定相应 clip、播放超过一个周期并继续移动；全部 PASS。
- 窗口模式同一脚本另存 [现役基线](compare-loop-v2-candidate-0.png)、[KayKit](compare-loop-v2-candidate-1.png)、[CMU](compare-loop-v2-candidate-2.png)。无头渲染不能截图，窗口模式实际读回 1280×800 画面。
- [鞋底逐帧报告](../../art/cultivator_walk_sources/ground_contact_v5.json)：两个候选最高离地不超过 3 mm；这只验证整体贴地，不表示足掌完全不滑。

## 结论边界

CMU 的普通步态比手作五关键姿态更有真人支撑感，手臂自然垂下；仍能看到些许后仰与足部误差，需人工连续观看。KayKit 角色比例和摆臂幅度映射后，抬膝偏高、手收在身后，不适合直接成为现役。画风最终应随水墨场景共同判断。本轮只建立比较依据，未替换正式人物动作。
