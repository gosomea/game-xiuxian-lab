# Note: Agent 无关的双平面解耦

Status: implemented

## 问题

模板若绑定单一 Agent 工具（如 dsh），其价值随该工具的存亡与使用者的工具偏好而波动；而模板的核心资产（架构纪律、流程、SOP、门禁）本质上是工具无关的。需要一个划分，使得「换 Agent」和「换流程」互不波及。

## 决策

仓库分两个平面：

**Agent 无关平面（模板本体）**：`AGENTS.md`（宪法）、`notes/`（纯 Markdown 决策记录）、`skills/`（SKILL.md 事实标准）、`src/data/vocabulary/`（纯 JSON）、`tools/verify/` + `tools/gen/`（Python 3 标准库零依赖 CLI）、`src/`（完整 Godot 工程，含 `tests/`）。任何 Coding Agent、人类、CI 通过同一入口消费：读同一套文档，跑同一套 CLI。

**Agent 适配平面（薄、可换、可缺席）**：全部为指向真身的符号链接，无一份重复内容。

| 入口 | 形态 | 指向 |
| --- | --- | --- |
| `CLAUDE.md` / `CODEBUDDY.md` | symlink | `AGENTS.md` |
| `.agents/skills` | symlink | `../skills` |
| `.claude/skills` | symlink | `../skills` |
| `.codex/skills` | symlink | `../skills` |
| `.codebuddy/skills` | symlink | `../skills` |
| `.workbuddy/skills` | symlink | `../skills` |

MCP 接入（`mcp/`，见 [mcp-directory-separation](2026-08-28-mcp-directory-separation.md)）同为可选增强。dsh-godot-ai 是最强驱动形态（编辑器内实时验证 + 截图闭环），但不是依赖。

符号链接一律用**相对路径**（`../skills`），不用绝对路径——绝对路径在换机器、换 clone 位置或容器内即失效。`verify-agent-entries` 门禁检查每个入口存在、是 symlink、且目标解析正确。

**Windows 取舍**：Windows 上 Git 需要开启 `core.symlinks=true` 且用户具备创建符号链接的权限（开发者模式或管理员），否则 clone 后 symlink 会变成含路径文本的普通文件。此时**门禁会失败并给出修复指引**，而非静默降级——因为静默降级会让 Agent 读到一个内容为 `../skills` 的假文件。真身（`AGENTS.md`、`skills/`）在任何平台都完好，Windows 用户即使不修 symlink 也能通过直接读真身正常工作。

**检验标准**：任何环节若只有某个特定 Agent 能完成，即为设计漏洞，必须打回重做（已写入根 AGENTS.md 约定 5）。

技术选型推论：词汇表用 JSON 不用 YAML——Godot 标准库无 YAML 解析器，JSON 三头通吃（Python 门禁可查、GDScript 运行时可加载、Agent 可读写）。

## 备选方案

- **以 dsh-godot-ai 为默认开发环境**：输在排他。dsh 的 Preset/MCP 体验最强，但 Codex / Claude Code 用户将被排除，模板失去「任意 coding agent 可用」的定位。dsh 降级为可选增强后两方兼得。
- **纯文档约定，不做 CLI 门禁**：输在门禁无法统一执行。文档约定依赖 Agent 自觉，不同 Agent 的遵守度不一；CLI 门禁让 Agent、人、CI 三方走同一裁判入口。
- **为每个 Agent 维护一份原生配置**（`.codex/` `.claude/` `.codebuddy/` 各一套 skill 副本）：输在维护税与漂移。多份副本必然漂移；symlink 到单一真身（`skills/`）消除整个失效类别。
- **只提供 `AGENTS.md`，不建 Agent 专属目录**：输在自动发现。多数 Agent 会主动扫描自己的约定目录（`.claude/skills` 等）并据此加载 skill；缺少这些入口时，skill 需要用户手工指路或 Agent 全仓搜索，可用性明显下降。symlink 的成本是每个入口一个符号链接，收益是开箱即用。
- **符号链接用绝对路径**：输在可移植性。绝对路径在换机器、换 clone 位置或容器内即失效（本上游仓库的 `.workbuddy/skills` 就是绝对路径，属已知瑕疵，模板不复制该做法）。

## 后果

- 代价：模板不能使用任何 Agent 的私有高级能力作为必需环节（如 dsh 的 session 事件），能力上限取各 Agent 交集。
- 收益：模板寿命与任何单一工具解耦；新 Agent 出现时适配成本 = 一个 symlink；CI 与本地、人与 Agent 的验证完全一致。
