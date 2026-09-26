---
name: mcp-blender
description: Use when inspecting or editing Blender scenes and 3D game assets through blender-mcp or Blender's command line, including modeling, materials, rigs, animation, rendering, and GLB export. Godot scene work uses godot-* skills.
---

# mcp-blender

本 Skill 指导 Blender 实时场景操作与可复现的命令行资产处理。仓库收录的社区版 blender-mcp 1.8.7 提供 25 个工具；Blender Lab 官方 MCP 是另一套接口，不能套用这里的工具名。

本文件是指引，不是清单脚本。

真相来源：`mcp/README.md`（工具清单、安装、凭据、风险）、`notes/implemented/process/2026-09-26-blender-operation-skill-refresh.md`、根 `AGENTS.md`（资产保留）、具体资产的 `docs/art/<asset>/asset_ledger.md`。

## 硬性前置（不满足则停止并告知用户）

1. **`execute_blender_code` 可执行任意 Python** —— 修改已打开的场景前确认 `.blend` 已保存；未保存时先让使用者保存，避免覆盖唯一副本。命令行处理现有资产时使用新输出路径，不原位覆盖旧源文件或导出文件。
2. **确认实际连接**：先检查当前客户端是否提供 `get_addon_status`。有工具时调用它；如果状态工具报错，可用 `get_scene_info` 做只读连接验证，并分别记录状态工具故障与场景读取结果。无工具时检查客户端 MCP 配置与 Blender 端监听状态，不声称已经连通，也不要猜工具可用。插件已安装、MCP 已注册、Blender 端已启动是三件事。
3. **需凭据的工具先查状态**：`get_sketchfab_status` / `get_hyper3d_status` / `get_hunyuan3d_status` / `get_polyhaven_status` 返回未配置时，告知用户需要哪个环境变量，不要替用户猜 Key。

## 固定起手式

实时 MCP 可用时，任何修改前先读状态，不凭记忆假设场景内容。工具要求 `user_prompt` 时传入使用者原话：

```
get_scene_info                    # 场景里有什么
get_object_info(<name>)           # 目标对象的具体属性
get_viewport_screenshot           # 当前视觉状态（改动前基线）
```

如果当前客户端没有 Blender MCP 工具，先确认是否需要操作打开的场景。只读检查或批量处理磁盘资产可用 Blender 命令行：`/Applications/Blender.app/Contents/MacOS/Blender --background <file.blend> --python <script.py>`；路径以实际安装位置为准。实时编辑需要先接通 MCP，再按上面的起手式操作。不要用命令行静默替换使用者正在编辑的文件。

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

### E. 人物骨架与动作
1. 先读取 Armature 的骨骼名、层级、网格绑定和现有 Action/动画槽，再确定修改目标；不要凭通用 Mixamo 骨名假设当前模型结构。
2. 改姿态或动作时在原资产上继续修改才可沿用文件名；新方案另存版本，源 `.blend` 与导出 `.glb` 都保留。当前 `cultivator_tripo_v9` 只有 22 根骨、没有手指骨；涉及手型的动作先说明骨架边界。
3. 对动作逐 clip 检查起止帧、根运动、脚底接触、站姿和骨盆相对双脚的位置。当前项目的权威量具与标定方法见根 `AGENTS.md` 和 `tools/art/`，不要只凭视口截图判断贴地或倾斜。
4. 导出 GLB 后回读动画名、骨架与网格，并在 Godot 重新导入后验证；源文件中动作可见不代表导出和运行时一致。

### F. 导入 Godot 前的清理
1. 减面（静态道具做 Decimate 即可，不做完整 retopo）。
2. 合并材质、统一命名。
3. 导出 GLB（Godot 原生格式，PBR 贴图直接识别）。
4. 源文件、导出文件与预览图落到本仓相应的 `src/assets/` 或模块资产目录；更新对应的 `docs/art/<asset>/asset_ledger.md`，新方案不覆盖旧版探索资产。
5. 在 Godot 导入面板勾选 Generate → Collisions（静态碰撞一步到位）。

## 验证与汇报

- 实时操作每批改动后：回读对象/场景状态 + 截图；命令行批处理则回读输出资产的结构、数值，并在需要视觉判断时渲染预览。
- 汇报格式：做了什么、调了哪些工具、回读证据（状态字段或截图路径）、台账登记情况、未完成或不确定的部分。
- 手感/美观类判断标注「需人工确认」，不代替用户下结论。

## 排除

- 不碰 `mcp/blender-mcp/` 源码（vendored 上游，改动需单独 notes 决策）。
- 不替用户开关遥测、不替用户写凭据。
- 不用 `execute_blender_code` 绕过专用工具「图快」。
- 不在同一会话里并行启动第二个 blender-mcp 实例（上游只支持一个）。
