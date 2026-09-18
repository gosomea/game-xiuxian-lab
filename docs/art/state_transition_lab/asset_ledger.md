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
| 最近修改 | 2026-09-18 共面闪烁修复（第二轮，错开埋深后定稿），详见 `README.md`「共面闪烁修复」小节 |
| 修复前源/导出归档 | `pre_surface_clearance_state_transition_lab.blend` 195965 字节 / `f00fe206f07ec7ec4450960b30df0667007b8affb8e3f3ae4cc85c56377ac6d4`（逐字节等于 HEAD 旧 `.blend`）；`pre_surface_clearance_state_transition_lab.glb` 2311704 字节 / `43f77a9c37979be81f799a3add3451f16170a1ea3d1fe0d3667e777aec6daa4a`（逐字节等于 HEAD 旧 GLB）。用 `git show HEAD:<path>` 按旧字节另存，修复前状态不再只依赖 Git 历史。 |
| `.blend1` 状态 | `state_transition_lab.blend1` 205559 字节 / `7605faf5f88fd90bc84ed43e3b3ec940b7d7e8c3c1629187c789ea9645fba6d3`。它不是修复前源（与 HEAD 旧 `.blend` 的 195965 / `f00fe206…` 不同），也不是当前 `.blend`（205314 / `8e5996d9…`），而是修复重导过程中某次覆盖保存轮转出的**中间态备份**；修复前源状态以 `pre_surface_clearance_state_transition_lab.blend` 归档为准。保留、入库、不得清理。 |
| 碰撞影响 | **无**。碰撞仍在 `state_transition_lab.gd` 本地装配：DiscFloor 顶 y=0、Bridge 段顶 y=0、断桥缺口 x ∈ [9.1, 11.5]（内侧边缘）、外缘 6.1/14.7 断言均未改。GLB 仅视觉。 |
| 埋入底面同高（B 类允许项） | 竖直构件埋入盘体的端盖底面彼此同高（门槛 −10 mm / 墙身 −12 mm / 柱 −14 mm 等）属**不可见 B 类允许项**：端盖被实体包住、不产生可见面竞争。该口径与 [地形接触训练场台账](../ground_contact_course/asset_ledger.md)「B 类允许项」一致。 |
| 修复验证 | 全 GLB 机械扫描（同向水平面口径）：两两「同向水平面共面（|Δy| ≤ 1.5 mm 且水平重叠 ≥ 0.05 m²）」命中 **0 组**（修复前 22 组，最大 322.56 m²）；修复前/后同相机 A/B：帧 2–22 近景变化像素 24.20%/26.94% → 9.87%/10.51%；相机冻结后连续 6 帧差异 **0 px**；专属 playtest 133 条 PASS / 0 FAIL。原始日志见 `~/.cache/game-xiuxian-lab/surface-clearance/state-transition/`。 |
| 保留的旧资产 | `trial_preview_pre_surface_clearance.png`（修复前预览字节）、`trial_preview_surface_clearance.png`（新预览副本）、`state_transition_lab.blend1`（Blender 自动备份，见下）、`pre_surface_clearance_state_transition_lab.blend`（修复前源归档）、`pre_surface_clearance_state_transition_lab.glb`（修复前导出归档）。均在库内跟踪，未删除任何旧资产。 |
| 数值摘要 | 91 网格；玉盘半径 9 m / 顶面 y=0；石门墙 z=-5.5；断桥缺口 x ∈ [9.1, 11.5]（内侧边缘，与 `GAP_MIN_X` / `GAP_MAX_X` 一致） |
| 生成方式声明 | AI 代理编写脚本，经 Blender 程序建模；未调用图像/3D 生成服务，无第三方素材 |
| 验收 | 见 [状态切换压力场验收](../../playtest/2026-09-18-state-transition-lab.md) |
| 未完成 | 审美待使用者实机判断；无骨骼、无动画、GLB 不含碰撞（Godot 侧精确装配代理） |

登记人：状态切换压力场实现代理；日期 2026-09-18。
