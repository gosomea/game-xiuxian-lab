# Note: Skill 命名前缀 taxonomy

Status: implemented

## 问题

模板汇集三类来源的 skill：dsh-godot-ai 迁移的 16 个 Godot 技能、本仓原生的工作流 SOP、外部（Codex 技能市场）的通用游戏开发 skill。无前缀混放时，归属域、来源与适用边界不可见，Agent 路由时也无法按域过滤；外部 skill 原名（如 `game-engine`、`game-developer`）语义重叠，直接混用必然撞车。

## 决策

域前缀是 skill 命名的第一公民，强制登记（根 AGENTS.md 约定 7）：

| 前缀 | 域 | 来源 |
|---|---|---|
| `godot-` | Godot 引擎域 | 迁移自 dsh-godot-ai，保持原名不改 |
| `flow-` | 本仓开发工作流 | 本仓原生 |
| `design-` | 游戏设计理论/引擎架构 | 外部，安装时改名落盘 |
| `feel-` | 操作手感与反馈 | 外部 |
| `ui-` | 游戏 UI/UX | 外部 |
| `web-` | Web 小游戏技术 | 外部 |
| `proto-` | 原型与玩法生成 | 外部 |
| `mp-` | 多人联机 | 外部 |

10 个外部 skill 的前缀映射与建议安装时机登记在 [skills/README.md](../../../skills/README.md) 的「外部 skill 注册表」；仓内只登记槽位，不分发实体（无源文件，且其许可以「用户自行安装」为前提）。命名冲突时本仓 skill 优先，外部改名并登记。

## 备选方案

- **无前缀扁平命名**：输在可路由性。前缀让「只做 2D 项目时不加载 mp-/web-」成为一行过滤规则；扁平命名下域信息只能靠 description 猜。
- **外部 skill 保持原名**：输在撞车与语义重叠（`game-ui-design` vs `game-ui-ux` vs 本仓未来的 ui 类 skill）。统一改前缀后语义归域管理。
- **按来源分目录（external/ native/）而非前缀**：输在消费方式。SKILL.md 的消费方按名字路由，不按目录；且来源会随维护易主变化（外部 skill 可能被 fork 成本仓原生），目录归属会造成无谓迁移。

## 后果

- 代价：外部 skill 安装需多一步改名登记；前缀集合扩张需改两处（skills/README.md 与根 AGENTS.md 约定 7）。
- 收益：skill 清单可机械审计（前缀集合封闭）；Agent 可按域裁剪加载；外部技能的热度信息（安装量）与模板判断（建议安装时机）分离记录，避免「按热度盲装」。
