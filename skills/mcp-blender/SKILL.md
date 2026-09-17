---
name: mcp-blender
description: Use when driving Blender through the blender-mcp MCP server — 用 AI 操作 Blender 建模、改材质、搭场景、下载 Poly Haven/Sketchfab 资产、调 Hyper3D/Hunyuan3D 生成 3D 模型，以及把产出导入 Godot 前的清理。不用于 Godot 内的操作（走 godot-* skills），不用于纯 2D 资产（走 2D 出图管线）。
---

# mcp-blender

blender-mcp 提供 25 个工具但不提供使用纪律。本文件补上这一层：何时用哪个、按什么顺序、怎么验证、哪些操作不可逆。

本文件是指引，不是清单脚本。

真相来源：`mcp/README.md`（工具清单、安装、凭据、风险）、`notes/implemented/process/2026-08-28-mcp-directory-separation.md`、根 `AGENTS.md`（资产台账纪律）。

## 硬性前置（不满足则停止并告知用户）

1. **`execute_blender_code` 可执行任意 Python** —— 调用前必须确认 .blend 文件已保存。用户未保存时先要求保存，不要「顺手帮他保存」（覆盖风险）。
2. **确认连接可用**：先 `get_addon_status`，失败则报告「Blender 未启动 / 插件未启用 / MCP Server 未点 Start」三种可能，不要盲目重试。
3. **需凭据的工具先查状态**：`get_sketchfab_status` / `get_hyper3d_status` / `get_hunyuan3d_status` / `get_polyhaven_status` 返回未配置时，告知用户需要哪个环境变量，不要替用户猜 Key。

## 固定起手式

任何修改前先读状态，不凭记忆假设场景内容：

```
get_scene_info                    # 场景里有什么
get_object_info(<name>)           # 目标对象的具体属性
get_viewport_screenshot           # 当前视觉状态（改动前基线）
```

## 工作流

### A. 建模与修改
1. 读状态（起手式）。
2. 优先用具体工具而非 `execute_blender_code`——能用专用工具表达的操作不要写裸 Python。
3. 必须写 Python 时：**一次一个小步骤**，每步后回读 `get_scene_info` 或 `get_object_info` 验证。上游已知限制是「复杂操作需拆小、可能超时」。
4. 改完截图对比基线。

### B. 材质与贴图
1. `get_object_info` 确认对象当前材质。
2. Poly Haven 贴图走 `search_polyhaven_assets` → `download_polyhaven_asset` → `set_texture`。
3. 截图验证；材质类改动肉眼不看等于没验证。

### C. 资产获取（Poly Haven / Sketchfab）
1. 先 `get_*_status` 确认可用。
2. 搜索 → **预览**（`get_sketchfab_model_preview`）→ 再下载。跳过预览直接下载会引入不合用的模型和不必要的许可负担。
3. 下载后立即登记 `assets/asset_ledger.md`：路径、来源、许可结论、日期。**Sketchfab 各模型许可不同，必须逐个确认后记录，不能统一写「Sketchfab」。**

### D. AI 生成 3D（Hyper3D Rodin / Hunyuan3D）
1. 查状态 → 生成（`generate_hyper3d_model_via_text` 或 `_via_images`）→ **轮询**（`poll_rodin_job_status` / `poll_hunyuan_job_status`）→ 导入（`import_generated_asset*`）。
2. 轮询要有上限，不要无限等待；超时如实报告而不是宣称成功。
3. 生成物**必须**登记台账，记录模型、prompt/seed、许可。Hunyuan3D 权重许可有地区限制（EU/UK/KR 不适用），商用前须确认。
4. 生成的网格通常面数过高、拓扑脏——**AI 生成 ≠ 可直接进引擎**，见下节。

### E. 导入 Godot 前的清理
1. 减面（静态道具做 Decimate 即可，不做完整 retopo）。
2. 合并材质、统一命名。
3. 导出 GLB（Godot 原生格式，PBR 贴图直接识别）。
4. 落到 `assets/generated/<category>/`，命名遵循项目规范。
5. 在 Godot 导入面板勾选 Generate → Collisions（静态碰撞一步到位）。

## 验证与汇报

- 每批改动后：回读对象/场景状态 + 截图，两者都要。
- 汇报格式：做了什么、调了哪些工具、回读证据（状态字段或截图路径）、台账登记情况、未完成或不确定的部分。
- 手感/美观类判断标注「需人工确认」，不代替用户下结论。

## 排除

- 不碰 `mcp/blender-mcp/` 源码（vendored 上游，改动需单独 notes 决策）。
- 不替用户开关遥测、不替用户写凭据。
- 不用 `execute_blender_code` 绕过专用工具「图快」。
- 不在同一会话里并行启动第二个 blender-mcp 实例（上游只支持一个）。
