# v9 完整人体步行、疾跑、跳跃资产台账

## 来源与版本

- 现役人物外形、22 骨、蒙皮和材质：`src/game/actors/swordsman/models/cultivator_motion_20260927.glb`。这是上一版新制动画人物；本轮只借其人物及其它四段状态，未覆盖原文件。
- 动作源：`docs/art/cultivator_jade/cultivator_rigged.blend` 的早期 Mixamo `walk/run/jump`，65 骨。该源是项目保留的、曾获使用者认可的正常人体动作链。来源构建流程见 `mcp/mixamo/README.md`。未重新使用已经删除的 v1–v6 人物与动画试验资产。
- 构建脚本：`tools/art/build_cultivator_human_motion_20260927.py`。按关节世界旋转变化重定向到 v9 的骨架，保留 v9 骨长与网格；将源髋部竖直起伏接到根节点，把水平根位移留给游戏物理。步行手臂向现役普通站姿混合 45%，避免旧源肩宽在 v9 袍装上造成撑臂。
- 可编辑源：`cultivator_human_motion_20260927.blend`。运行时导出：`src/game/actors/swordsman/models/cultivator_human_motion_20260927.glb`。`build_manifest.json` 记录输入与导出的 SHA-256、动作范围、地面校准；贴图和导入边车同版本入仓。
- Blender 构建命令：`/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/build_cultivator_human_motion_20260927.py`。随后运行 Godot `--headless --path src --import`。

## 动作与速度

| 动作 | 来源 | 周期 / 时间 | 用途 |
|---|---|---:|---|
| `idle` | 上版普通站姿 | 约 3 秒循环 | 默认静止，不负手 |
| `walk` | Mixamo 完整人体步行 | 1.033 秒循环 | 普通走路 |
| `run` | Mixamo 完整人体跑步 | 0.633 秒循环 | W+Shift 疾跑 |
| `jump` | Mixamo 起跳动作 | 0.533 秒单次 | 离地、腾空；物理高度由 Jump 能力决定 |
| `idle_guarded` / `meditate` / `sword_ride` | 上版独立状态 | 各自循环 | 工作台待命、静修、御剑 |

导出 GLB 的足尖相对骨盆行程约为 1.053 / 1.332 米每周期，对应参考速度 1.02 / 2.10 米/秒。角色实际普通走速为 1.25 米/秒，Shift 疾跑为 2.25 米/秒；表现层播放速率约 1.23 / 1.07 倍。该行程法估计脚步匹配，连续场景中的滑步仍须靠试玩观察。

## 验证图像与边界

- [逐帧蒙皮鞋底报告](ground_contact.json)：`walk` 最低点 -0.0003 米，`run` +0.0009 米。只按整段动作给固定地面偏移，保留动作原有的腾空与重心变化。
- [侧面五相位 × 三动作](contact_sheet.png)、[正面五相位 × 走跑](front_contact_sheet.png)：全部从最终导出 GLB 渲染；`frames/`、`front_frames/` 保存每张原图，可逐张比较。
- [正式移动场景验收](../../../docs/playtest/2026-09-27-human-locomotion/report.md)：Godot 窗口模式实机输入和截图。修仙气质与角色比例仍需使用者亲自试玩评价；本轮只解决步行、疾跑、跳跃的人体动作质量。
