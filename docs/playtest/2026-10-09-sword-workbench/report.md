# 剑法工作台 · 运行记录

日期：2026-10-09。Godot 4.6 stable，Blender 5.2.1，macOS / Apple M4 Pro，Compatibility / OpenGL。决策见[剑法工作台 note](../../../notes/implemented/gameplay/2026-10-09-sword-workbench.md)，资产见[本命剑台账](../../art/bound_sword_20261009/asset_ledger.md)。

| 检查 | 结果 | 依据 |
|---|---|---|
| 三项能力配对测试 | PASS：剑气 20、飞剑出击 19、剑阵 14 | `test_sword_qi.gd`、`test_flying_sword_strike.gd`、`test_sword_array.gd` |
| 御剑读剑在外阻塞 | PASS，`test_sword_flight.gd` 32 项 | 新增用例：阻塞时按 F 不起飞，撤销后可起飞 |
| 场景集成（真实物理帧） | PASS，25 项 | `tests/test_sword_workbench.gd`：装配、表现挂载、左键边沿一帧、三招都命中木桩、剑在外 F 被拒、飞回清账、重置、目录登记 |
| 全量运行时测试 | PASS，1766 通过 / 0 失败，无脚本错误 | `godot --headless --path src tests/test_runner.tscn` |
| Tier 0 静态门禁与负向控制 | PASS，27/27；verify-packages 11 个目标合规 | `python3 tools/verify/run_all.py` |
| 真实窗口输入 | PASS，24 项 | [window_input.txt](window_input.txt)：`tests/sword_workbench_playtest.gd`，经 `Input.parse_input_event` 送鼠标移动、左键、C、F |
| 旧移动窗口验收中改写的断言 | PASS | `tests/character_movement_playtest.gd`「剑法工作台可从顶层进入」 |

窗口验收数值：剑阵按住约 1.2 s 悬停 25 把；一轮齐射命中木桩 10 次；剑在外时按 F 保持地面状态；御剑时可放剑气；结束时 `TimeKeeper` 无残留请求。

## 实际画面

真实窗口截图（1024×640 内容），人物位于画面中央：

- [待机](sword-idle.png)：本命剑悬在右肩后上方。
- [剑气](sword-qi.png)：右臂前指，剑气已飞出画面中心。
- [飞剑出击](sword-strike.png)：右臂前指，本命剑在远处木桩附近。
- [剑阵蓄势](sword-array_hold.png)：身后两排扇面悬停。
- [剑阵齐射](sword-array_volley.png)：逐把沿弧线射向指向点。
- [御剑剑气](sword-flight_qi.png)：御剑悬停时放出的月牙剑光。

## 过程中修正的问题

- 首轮截图地面过曝、剑气加法混合在浅色地面上几乎看不见、剑阵只有几像素宽：调暗地面与光照，剑气改为普通透明混合，镜头正交尺寸 20 → 14，两把剑绘制放大 1.4 倍。
- 剑阵连中把木桩晃倒：晃动倾角封顶 0.28 rad。
- 剑阵每次命中都顿帧时，一轮齐射损失约四分之一游戏时间：剑阵命中不再顿帧，只保留木桩闪白与晃动。

## 边界

未做镜头抖动、受击火花、飞剑拖尾与出招关键帧动画；木桩没有血量。出招姿势是右臂运行时转向，只验证了权重升降，未逐帧检查肩部蒙皮。三招的手感、速度与射程是第一轮起点，需要使用者试玩判断。截图脚本的鼠标来自注入事件，没有验证编辑器内嵌 Game 视图的鼠标坐标。

## 复验

```sh
Blender --background --factory-startup --python-exit-code 1 --python tools/art/generate_bound_sword_20261009.py
Godot --headless --path src --import
Godot --headless --path src tests/test_runner.tscn
python3 tools/verify/run_all.py
Godot --path src --script res://tests/sword_workbench_playtest.gd -- --capture-prefix=/absolute/path/sword
```
