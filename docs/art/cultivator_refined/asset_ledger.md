# 资产台账 · cultivator_refined

按 [mcp-blender skill](../../../skills/mcp-blender/SKILL.md) 的登记纪律：来源、许可结论、日期。

| 字段 | 值 |
|---|---|
| 资产名 | `cultivator_refined`（修士角色，替换 blocky 立方体人体） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS（2026-08-25 构建）程序建模；无第三方素材、无下载、无贴图、无骨骼与动画数据 |
| 生成脚本 | `tools/art/generate_cultivator_refined.py`（阶段 `build` / `preview`） |
| 复现命令 | `/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_cultivator_refined.py -- build preview`；全程 `--background --factory-startup`，不操作用户打开的 .blend |
| 源文件 | `docs/art/cultivator_refined/cultivator_refined.blend` |
| 运行输出 | `src/game/actors/swordsman/models/cultivator.glb`（**原路径保留**，旧庭院同样受益） |
| 预览 | `cultivator_front.png` / `_side.png` / `_three_quarter.png` / `_closeup.png`（Cycles 24 采样 + 降噪，非运行时素材） |
| 生成日期 | 2026-09-18 |
| 第三方素材 / 许可依赖 | 无（几何与材质均为本仓原创；仅依赖 Blender 自带 Python） |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明 |
| 导出器 | Khronos glTF Blender I/O v5.2.40 |
| 轴向契约 | 部件按 Blender -Y 建模，导出前绕 Z 旋转 180°，`export_yup` 后正面为 Godot **-Z**；由 `assert_axis_contract()` 在写出的 GLB 上断言 |
| 二进制校验和（sha256） | `cultivator.glb` = `70fc5eb6a4cd60579ac06bde5e65da6cc22e32f48316eae53e813387ae36b426`（121736 B）；`cultivator_refined.blend` = `0370960d24c5d5e14ae8379c5a40b50376fe93131e21bbcc3fd748ec95462da6`（155563 B） |
| 数值摘要 | 23 网格 / 4952 三角形 / 8 材质 / 0 图片 / 0 动画 / 0 骨骼；身高 1.70 m（约 5.9 头身）；足底 y=0 |
| 表现层 | `src/game/actors/swordsman/cultivator_presentation.gd`（纯表现，无骨骼），见 [README](README.md) |
| 验收 | 静态：`verify-scenes` / `verify-packages` / `verify-capabilities` / `verify-component-purity` / `verify-vocabulary` 通过；GLB 轴与表面契约由生成器自断言。**Godot 端导入与实机画面由场景/验收代理运行**（角色模型本轮未在 Godot 中执行） |
| 未完成 / 未验证 | 无骨骼动画（分件刚体摆动近似，脚底会有小幅滑动）；面部/衣褶为风格化程序建模，非雕刻级；预览为一次性渲染，重跑会覆盖 |

登记人：角色美术代理；日期 2026-09-18。形体与轴向细节见 [README.md](README.md)。
