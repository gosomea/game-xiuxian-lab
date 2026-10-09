# 上身扶正与站立手臂中立位 · 运行记录

日期：2026-10-09。Godot 4.6 stable，Blender 5.2.1，macOS / Apple M4 Pro，Compatibility / OpenGL。资产与数值见[台账](../../art/cultivator_upright_motion_20261009/asset_ledger.md)，决策见[人体动作 note](../../../notes/implemented/art/2026-09-27-human-locomotion-on-v9.md)。

| 检查 | 结果 | 依据 |
|---|---|---|
| 构建器自检（上身、手腕、走路前摆、外展、接缝） | PASS | `build_report.json` 的 `problems` 为空 |
| 摆臂与朝向量具 | PASS | `geometry.json` |
| 走路骨盆 / 双踝平衡、鞋底、接缝（`--check`） | PASS | `balance_after.json` |
| 七段逐帧贴地 | PASS | `ground_contact.json` |
| 头相对骨盆倾角（≤ 4°） | PASS，idle +2.66°、walk +2.76°、run +3.36° | `posture.json` |
| Tier 0 静态门禁与负向控制 | PASS，27/27 | `python3 tools/verify/run_all.py` |
| 全量运行时测试 | PASS，1686 通过 / 0 失败 | `godot --headless --path src tests/test_runner.tscn` |
| 新增 idle 矢状面判据的负向控制 | PASS | 临时把现役模型常量指向 swing 版，该套件 6 项失败：颈 −0.049 m、肩线 −0.064 m、倾角 −5.37°、手腕 −0.164 / −0.158 m，以及模型路径；随后恢复 |
| 真实窗口移动输入 | PASS，38 项 | [window_input.txt](window_input.txt)：`tests/motion_balance_playtest.gd` |

## 实际画面

- [站立](motion-idle.png)、[步行](motion-walk.png)、[疾跑](motion-run.png)、[跳跃](motion-jump.png)、[御剑](motion-flight.png)：人物动作工作台真实窗口截图，人物在默认俯视镜头下较小。
- 姿态细节以台账的 `compare_standing.png`、`compare_walk.png` 为准，它们是 Blender 正交渲染，不是游戏内镜头。

## 边界

静修时手随肩前移约 4 cm，仍落在膝上，未做逐帧接触检查。`run` 与 `jump` 的手臂中立位未改。走路前摆的高度与幅度、站立手的位置是否自然，仍需使用者在动作工作台看过后判断。
