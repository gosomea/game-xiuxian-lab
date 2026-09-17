# skills/ — 标准作业程序（SOP）与前缀规范

每个 skill 一个目录，内含 `SKILL.md`。格式为跨工具事实标准（Codex / Claude Code / CodeBuddy / dsh 均可消费）。

**全部 32 个 skill 随模板分发，clone 即可用，无需额外安装。**

## 前缀 taxonomy（由 verify-skills 门禁强制）

域前缀是 skill 的第一公民：看到名字就知道归属域与适用边界，Agent 可按域裁剪加载（例如纯 2D 项目不加载 `mp-` / `web-`）。

门禁检查三件事：目录名带合法前缀、`SKILL.md` 存在、**frontmatter 的 `name` 与目录名一致**（Agent 按 `name` 路由，不一致会导致按清单找不到 skill）。

| 前缀 | 域 | 数量 |
|---|---|---|
| `flow-` | 开发与探索工作流 | 10 |
| `godot-` | Godot 引擎域知识 | 16 |
| `design-` | 游戏设计理论与引擎架构 | 3 |
| `ui-` | 游戏 UI/UX | 2 |
| `web-` | Web 小游戏技术 | 2 |
| `feel-` | 操作手感与反馈 | 1 |
| `proto-` | 原型与玩法生成 | 1 |
| `mp-` | 多人联机 | 1 |
| `mcp-` | MCP 服务器使用纪律（工具在 `mcp/`） | 1 |

## flow-：工作流

### 探索期（0→1，模板外进行）

拿到模板但还没有 idea 时的入口。这几个 skill 的方法吸收自 [mattpocock/skills](https://github.com/mattpocock/skills)（MIT，2026-08-28）与 [DY-2026/GameDesignOS](https://github.com/DY-2026)（MIT），**已重写为 Agent 无关形式**——上游依赖 Claude Code 的 slash command 与 Skill tool 调用机制，直接 vendored 会违反铁律 5（决策见 [zero-to-one-skills](../notes/proposed/2026-08-28-zero-to-one-skills.md)）。

| Skill | 用途 |
|---|---|
| `flow-zero-to-one` | **空项目入口**：六步链条，从模糊偏好到可进建造期的设计契约 |
| `flow-grilling` | 追问打磨方案（frontier 分轮提问、事实/决策分离、grillable 判据） |
| `flow-prototype` | 可丢弃原型，回答「必须看到才能答」的问题 |
| `flow-wayfinder` | 议题超出单会话容量时先画地图（按风险排序，非技术依赖排序） |

### 建造期（1→N，受本仓纪律约束）

| Skill | 用途 |
|---|---|
| `flow-add-capability` | 新增行为单元的标准流程 |
| `flow-add-content` | 内容层数据（功法/法宝/事件）生产 |
| `flow-balance-check` | 数值改动的证据生产 |
| `flow-pre-push-checks` | 推送前最小检查集选择 |
| `flow-code-review` | 自审与互审（blocking requirements） |
| `flow-playtest-verify` | 功能验收（CLI 档 / MCP 档两形态） |

## godot-：引擎域（源自 dsh-godot-ai）

`godot-2d-movement` / `godot-3d-essentials` / `godot-ai-orchestration` / `godot-animation` / `godot-audio` / `godot-csharp` / `godot-export` / `godot-gdscript` / `godot-multiplayer` / `godot-nodes-scenes` / `godot-physics` / `godot-resources` / `godot-shaders` / `godot-signals-groups` / `godot-tilemap` / `godot-ui-control`

## 外部 skill（已 vendored，附上游归属）

来自 Codex 技能市场，按前缀 taxonomy 重命名后随模板分发（决策见 [external-skills-vendored](../notes/implemented/process/2026-08-28-external-skills-vendored.md)）。上游更新不自动同步，需要时按原名比对。

| 分发名 | 上游原名 | 用途 | 建议使用时机 | 许可 |
|---|---|---|---|---|
| `design-game-theory` | game-design-theory | 游戏设计理论（MDA、玩家心理） | 立项 / 支柱讨论期 | 未声明 |
| `design-game-engine` | game-engine | Web 游戏引擎与架构设计 | 架构决策期 | MIT |
| `design-game-developer` | game-developer | 通用游戏开发（ECS、物理、优化） | 通用兜底 | MIT |
| `feel-game-feel` | game-feel | 手感、打击感、屏幕震动、缓动 | 「能运行但不好玩」时 | 未声明 |
| `ui-game-design` | game-ui-design | 游戏 UI 设计（HUD、菜单、可读性） | UI 系统开工前 | 未声明 |
| `ui-game-ux` | game-ui-ux | UI/UX（响应式布局、手柄焦点、安全区） | 同上，可并用 | 未声明 |
| `web-threejs-ui` | threejs-game-ui-designer | Three.js 游戏 UI | 仅 Web 3D 技术栈 | 未声明 |
| `web-dev-game` | develop-web-game | 用 Codex 做网页小游戏（含 Playwright 测试环） | Web 原型期 | MIT |
| `proto-game-generation` | higgsfield-game-generation | 可玩浏览器游戏与精灵图生成 | 原型探索期 | MIT |
| `proto-pixel-asset-pipeline` | pixel-asset-pipeline | AI 像素素材生成→Godot 可用 sprite sheet 流水线 | 素材批量生产期 | 未声明 |
| `proto-pixel-art-processing` | pixel-art-processing | 精灵图后处理（视频抽帧/GIF 转换/抠图/切片，派生自 FrameRonin） | 素材后处理期 | 未声明 |
| `mp-multiplayer-game` | multiplayer-game | 多人联机（匹配、tick 循环、状态同步） | 联机需求出现时 | 未声明 |

⚠️ **公开发布前的待确认项**：标注「未声明」的 6 项需逐个确认上游许可，或改回槽位登记模式。个人/内部使用不受影响。

## mcp-：MCP 服务器使用纪律

MCP 服务器提供工具，`mcp-` skill 提供纪律（何时用、按什么顺序、怎么验证、哪些操作不可逆）。服务器实体在 `mcp/`，清单见 [mcp/README.md](../mcp/README.md)。

| Skill | 对应 MCP | 为什么需要 |
|---|---|---|
| `mcp-blender` | `mcp/blender-mcp`（25 个工具） | 上游只给工具不给纪律：`execute_blender_code` 可执行任意 Python、AI 生成资产需轮询与台账登记、Sketchfab 各模型许可不同需逐个确认 |

`blender-mcp` 本身**不在** `skills/` 下 —— 它是 PyPI 包加 Blender 插件，无 SKILL.md（已核对上游 v1.8.7）。分目录决策见 [mcp-directory-separation](../notes/implemented/process/2026-08-28-mcp-directory-separation.md)。

## SKILL.md 写作规范（沿用 DSH 模式）

1. **Frontmatter 即触发器**：`name`（必须等于目录名）+ `description`（写成「Use when …」触发场景清单，含反向边界）。
2. 开篇一句定位 + 「本文件是指引，不是清单脚本」。
3. 真相来源清单：挂 AGENTS.md / notes / docs 指针，不复制规则。
4. 固定起手式：先核实状态（分支 / 范围 / 现状），再行动。
5. 编号工作流，每步给命令模板。
6. 结尾规定验证动作与汇报格式。
7. 排除清单：明确不碰什么。
