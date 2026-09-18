# mountain_realm 美术资产

群山宗门场景与御剑模型。**AI 代理编写脚本 + 本地 Blender 5.2.1 LTS 程序建模**的原创几何：
无下载素材、无贴图、未调用图像/3D 生成服务、无骨骼与动画；唯一外部依赖是 Blender 自带 Python。

- 坐标与布局契约：[layout-contract.md](layout-contract.md)
- 台账（来源/许可/校验和/数值/踩坑）：[asset_ledger.md](asset_ledger.md)
- 决策依据：[mountain-traversal](../../../notes/implemented/gameplay/2026-09-18-mountain-traversal.md)（本轮美术决策由该 note 覆盖，未另建 art note）
- 配色沿用：[paper-jade-palette](../../../notes/implemented/art/2026-09-17-paper-jade-palette.md)

## 产物

| 文件 | 角色 |
|---|---|
| `src/levels/experiments/character_movement/mountain_realm_layout.json` | 布局真源：bounds / spawn / 3 落脚点 / 75 个实体盒 / 远山云层 |
| `src/levels/experiments/character_movement/mountain_realm.glb` | 可见美术（含五峰、宗门、庭院、植被、远山云层） |
| `src/levels/experiments/character_movement/mountain_realm_collision.glb` | 碰撞壳：5 个 PascalCase 节点，与可见山体**共用同一 mesh** |
| `src/game/abilities/sword_flight/models/flying_sword.glb` | 御剑：长 1.80 m、局部 −Z 为剑尖、原点在剑身顶面 |
| `mountain_realm.blend` / `flying_sword.blend` | Blender 源文件（本目录是唯一真源，`src/` 下的 GLB 是导出产物） |
| `mountain_realm_preview.png` | Cycles 预览（1000×640，非运行时素材） |

## 复现

见 [asset_ledger.md](asset_ledger.md)「复现命令」。五个阶段（`layout` / `collision` / `terrain` / `sword` / `preview`）
各自独立进程，全部 `--background --factory-startup`，不操作用户已打开的 `.blend`。重跑会覆盖 GLB 与 .blend。

## 当前状态（2026-09-18）

主审已看预览并接受本轮进入 Godot 实机审计。**全部最终 GLB 已写完并冻结**（校验和见台账），
Godot 端的导入、碰撞安装与画面验收由场景/验收代理执行；本目录不含 Godot 侧结论。
