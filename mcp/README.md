# mcp/ — MCP 服务器集成

MCP 服务器提供**工具**（Agent 能做什么）；`skills/` 提供**使用纪律**（何时用、按什么顺序、怎么验证）。两者分目录的理由见 [mcp-directory-separation](../notes/implemented/process/2026-08-28-mcp-directory-separation.md)。

**全部 MCP 都是可选增强。** 模板的核心链路（门禁、测试、能力开发）不依赖任何 MCP —— 这是 AGENTS.md 铁律 5「Agent 无关」的必然要求。

## 清单

| 目录 | 上游 | 版本 | 许可 | 配套 skill |
|---|---|---|---|---|
| `blender-mcp/` | [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp) | 1.8.7（vendored） | MIT | `skills/mcp-blender/` |

未 vendored 但推荐的可选 MCP：

| 名称 | 用途 | 说明 |
|---|---|---|
| [dsh-godot-ai](https://github.com/deepseek-ai) | Godot 编辑器内实时操作与截图验证 | 装了它 `flow-playtest-verify` 升级为视觉闭环；未装则走 CLI 档 |

## blender-mcp

把 Blender 接入任意 LLM，自然语言驱动建模、材质、场景搭建与 AI 生成 3D 资产。**25 个工具**，分五组：

| 组 | 工具 |
|---|---|
| 状态检查 | `get_addon_status` / `get_scene_info` / `get_object_info` / `get_viewport_screenshot` |
| 代码执行 | `execute_blender_code`（⚠️ 任意 Python，见风险） |
| Poly Haven 资产 | `get_polyhaven_status` / `get_polyhaven_categories` / `search_polyhaven_assets` / `download_polyhaven_asset` / `set_texture` |
| Sketchfab 模型 | `get_sketchfab_status` / `search_sketchfab_models` / `get_sketchfab_model_preview` / `download_sketchfab_model` |
| AI 生成 3D | `get_hyper3d_status` / `generate_hyper3d_model_via_text` / `generate_hyper3d_model_via_images` / `poll_rodin_job_status` / `import_generated_asset` / `get_hunyuan3d_status` / `generate_hunyuan3d_model` / `poll_hunyuan_job_status` / `import_generated_asset_hunyuan` |
| 其他 | `disable_telemetry` / `record_trajectory_feedback` |

### 安装

需要 Blender 3.0+、Python 3.10+、`uv`（**必须用官方安装器，不要 `pip install uv`**，否则没有 `uvx`）。

```bash
uvx blender-mcp install-addon        # 安装 Blender 插件（会写入 addons 目录，留 .bak 备份）
```

然后在 Blender：`Edit → Preferences → Add-ons` 启用 **Interface: Blender MCP**；3D 视口按 `N` → **BlenderMCP** 标签页 → **Start MCP Server**。

客户端配置（Claude Code 为例）：

```bash
claude mcp add blender uvx blender-mcp
```

其他客户端（Claude Desktop / Cursor / VS Code / OpenCode）配置见 `blender-mcp/README.md`。**同一时间只能运行一个实例。**

`spawn uvx ENOENT` 是最常见故障：GUI 启动的客户端不继承终端 PATH，用 `which uvx` 的绝对路径填 `command`，改完完全退出并重启客户端。

### 风险与须知

1. **`execute_blender_code` 可执行任意 Python** —— 使用前必须保存 .blend 文件。`skills/mcp-blender` 把这条列为硬性前置。
2. **遥测默认开启**，上游声明数据可能用于研究与训练 AI 模型。关闭：环境变量 `DISABLE_TELEMETRY=true`，或在插件偏好设置中取消勾选。详见 `blender-mcp/TERMS_AND_CONDITIONS.md`。**模板不替用户决定这一项。**
3. **第三方服务需自备凭据**：Sketchfab（`BLENDERMCP_SKETCHFAB_API_KEY`）、Hyper3D Rodin（`BLENDERMCP_HYPER3D_API_KEY`）、Hunyuan3D（`BLENDERMCP_HUNYUAN3D_SECRET_ID` / `_SECRET_KEY`）。Poly Haven 无需 Key。
4. **生成的 3D 资产必须登记** `assets/asset_ledger.md`（来源、模型、prompt、许可），用于 Steam AI 内容披露。
5. 环境变量：`BLENDER_HOST`（默认 localhost）、`BLENDER_PORT`（默认 9876）、`BLENDERMCP_ADDONS_DIR`。

### 版本对应

vendored 的是 1.8.7。`uvx blender-mcp` 总取最新版——若上游工具改名或新增，`skills/mcp-blender` 的工具清单会过时。核对方式：

```bash
grep -c '@mcp.tool()' mcp/blender-mcp/src/blender_mcp/server.py   # 应为 25
```

上游更新后需同步 `skills/mcp-blender/SKILL.md` 的工具清单，并在 notes 记录版本变更。
