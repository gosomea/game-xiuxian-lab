# 全新修仙移动动作资产台账（2026-09-27）

## 来源与构建

- 人物网格、材质、22 骨骨架、蒙皮：`src/game/actors/swordsman/models/cultivator_tripo_v9.glb`。人物造型仍是临时现役模型，未重新建模。
- 动作制作：`tools/art/build_cultivator_motion_20260927.py`。导入后立即移除原 GLB 的全部 Action，从绑定姿态重新制作七段动作；`build_manifest.json` 记录 `sampled_imported_action_frames: 0`。
- 可编辑源：`cultivator_motion_20260927.blend`。Godot 导出：`src/game/actors/swordsman/models/cultivator_motion_20260927.glb`，同目录还包含 Godot 抽取的贴图与 `.import` 配置。两者均应进 Git。
- 构建命令：`/Applications/Blender.app/Contents/MacOS/Blender -b -t 4 --python tools/art/build_cultivator_motion_20260927.py`；随后运行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path src --import`。

## 动作设计

| clip | 用途 | 制作要点 |
|---|---|---|
| `idle` | 默认静止 | 双手自然下垂，呼吸幅度很小，不负手 |
| `idle_guarded` | 工作台待命姿态 | 手臂略收，静止时不自动启用 |
| `walk` | 普通步行 | 直立、肩摆克制、交替支撑与摆腿 |
| `run` | 疾行 | 更大步幅与更快周期，躯干微前倾，仍保持收束 |
| `jump` | 地面跳起 | 预备、收腿、腾空、落地；物理根的上升由 Jump 能力驱动 |
| `sword_ride` | 御剑 | 双足错步、膝微屈，身体保持稳定；飞剑由原装配逻辑驱动 |
| `meditate` | 工作台静修姿态 | 低坐、双手落于腿上；22 骨无手指，无法做结印 |

步行与疾行的脚趾相对骨盆水平行程分别约 0.731 m、0.901 m；导出周期约 0.917 s、0.792 s。按双足交替支撑估算自然速度约 1.59 m/s、2.28 m/s，对应游戏移动速度 1.55 m/s、2.25 m/s，场景参考速度分别设为 1.55 和 2.25 m/s。

## 验证与限制

- [蒙皮鞋底逐帧报告](ground_contact.json)：六段接地状态与地面偏差在 3 mm 内；`jump` 允许离地。骨骼足节点比真正鞋底高约 10 cm，因此不能用足骨原点的高度代替鞋底接触判据。
- `idle_preview.png`、`walk_preview.png`、`run_preview.png`、`jump_preview.png`、`sword_ride_preview.png`、`meditate_preview.png` 是同一导出 GLB 的独立静帧，带 z=0 地面和真实竖直参照。静帧只能看姿态，动作连续性以实机工作台为准。
- [窗口验收与删档记录](../../../docs/playtest/2026-09-27-fresh-motion/README.md)记录真实移动场景截图、运行时测试和 v1–v6 删除清单。中国修仙气质与最终水墨画风仍需使用者试玩判断；当前人物材质与场景画风尚未统一到参考图。
