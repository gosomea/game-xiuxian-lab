# 资产台账 · movement_garden

按 [mcp-blender skill](../../../skills/mcp-blender/SKILL.md) 的登记纪律：来源、许可结论、日期。
生成方式：**AI 代理编写脚本，经 Blender 程序建模**；未调用图像/3D 生成服务，也无下载资产，
因此没有 Sketchfab/Poly Haven/Hyper3D/Hunyuan3D 条目。

| 字段 | 值 |
|---|---|
| 资产名 | `movement_garden`（修士角色 + 修仙庭院） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS 程序建模；无外部素材、无下载、未调用图像/3D 生成服务 |
| 生成脚本 | `tools/art/generate_movement_assets.py`（角色）、`tools/art/generate_movement_garden.py`（庭院） |
| 复现命令 | 见 `README.md`「复现命令」（macOS 完整 Blender 路径，其他平台用小写 `blender`）；全程 `--background --factory-startup`，不操作用户打开的 .blend |
| 源文件（source） | `docs/art/movement_garden/cultivator.blend`、`docs/art/movement_garden/movement_garden.blend` |
| 输出（output） | `src/game/actors/swordsman/models/cultivator.glb`、`src/levels/experiments/character_movement/movement_garden.glb`、`docs/art/movement_garden/garden_preview.png` |
| 生成日期 | 2026-09-18 |
| 第三方素材 | 无 |
| 许可依赖 | 无第三方许可约束（几何与材质均为本仓原创；仅依赖 Blender 自带 Python） |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明 |
| 运行环境 | Blender 5.2.1 LTS（2026-08-25 构建），导出器 Khronos glTF Blender I/O v5.2.40 |
| 二进制校验和 | 见 `README.md` 校验和表（sha256） |
| 数值摘要 | 角色：17 网格 / 5080 三角形 / 7 材质 / 1.70 m；庭院：319 网格 / 40720 三角形 / 13 材质 / 18×14 m |
| 生成方式声明 | AI 代理编写脚本，经 Blender 程序建模；未调用图像/3D 生成服务，无第三方素材（发布政策结论未在本轮研究，不在此断言） |
| 验收 | Godot 最终验收已通过：32 项物理断言全 PASS、87 条单测通过、4 张截图，见 [角色移动庭院验收](../../playtest/2026-09-18-character-movement.md) |
| 未完成 | 手感与配色审美待使用者实机判断；无骨骼、无动画、无碰撞体（Godot 侧自建代理） |

登记人：Blender 资产交付代理；日期 2026-09-18。数值与轴向的完整说明见 `README.md`。
