# 资产台账 · state_transition_lab

按 [mcp-blender skill](../../../skills/mcp-blender/SKILL.md) 的登记纪律：来源、许可结论、日期。
生成方式：**AI 代理编写脚本，经 Blender 程序建模**；未调用图像/3D 生成服务，也无下载资产，
因此没有 Sketchfab/Poly Haven/Hyper3D/Hunyuan3D 条目。

| 字段 | 值 |
|---|---|
| 资产名 | `state_transition_lab`（心境 / 身法试炼阵） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS 程序建模；无外部素材、无下载、未调用图像/3D 生成服务 |
| 生成脚本 | `tools/art/generate_state_transition_lab.py` |
| 复现命令 | 见 `README.md`「复现命令」；全程 `--background --factory-startup`，不操作用户打开的 .blend |
| 源文件（source） | `docs/art/state_transition_lab/state_transition_lab.blend` |
| 输出（output） | `src/levels/experiments/character_movement/state_transition_lab.glb`、`docs/art/state_transition_lab/trial_preview.png` |
| 生成日期 | 2026-09-18 |
| 第三方素材 | 无 |
| 许可依赖 | 无第三方许可约束（几何与材质均为本仓原创；仅依赖 Blender 自带 Python） |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明 |
| 运行环境 | Blender 5.2.1 LTS（2026-08-25 构建） |
| 二进制校验和 | 见 `README.md` 校验和表（sha256） |
| 数值摘要 | 91 网格；玉盘半径 9 m / 顶面 y=0；石门墙 z=-5.5；断桥缺口 x ∈ [9.5, 11.5] |
| 生成方式声明 | AI 代理编写脚本，经 Blender 程序建模；未调用图像/3D 生成服务，无第三方素材 |
| 验收 | 见 [状态切换压力场验收](../../playtest/2026-09-18-state-transition-lab.md) |
| 未完成 | 审美待使用者实机判断；无骨骼、无动画、GLB 不含碰撞（Godot 侧精确装配代理） |

登记人：状态切换压力场实现代理；日期 2026-09-18。
