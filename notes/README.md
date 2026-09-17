# notes/ — 决策记录体系

Agent Note 记录影响仓库的决策或提案，承载 **why 和被否决的方案**——代码和文档无法承载的部分。读者是未来的维护者（人和 AI）。

## 路径即元数据

```
{lifecycle}/{class}/yyyy-mm-dd-主题标题.md
```

- 文件名日期 = 首次提出日期，不随状态迁移改变。
- 纯中文写作；文件名不含语言后缀，将来加英文版用 `.en.md` 后缀，无需迁移历史（双语配对门禁归 Tier 2，当前不开）。

## Lifecycle（状态机）

| 目录 | 含义 | 规则 |
|---|---|---|
| `proposed/` | 实施前待评审的提案 | 评审通过 → 迁移到 implemented 并改写骨架；否决 → 迁移到 rejected 并在 Status 行写一句原因 |
| `implemented/` | 已交付的决策 | 代码改事实（路径/命名/默认值）时**同变更原地更新事实**，不改决策本身；supersede 走新 note + 交叉链接 |
| `rejected/` | 被否决的提案 | 仅在理由能防止「诱人的、有意义的错误」时保留，否则删除 |
| `archived/` | 已完结且不再指导未来的 implemented | 永久冻结，不得当作当前行为的权威；proposed 永不归档（过时则 reject） |

## Class（封闭集合）

`gameplay`（玩法机制）/ `tech`（运行时架构与技术选型）/ `art`（美术与资产管线）/ `audio` / `narrative`（叙事与文案）/ `process`（流程、工具链、协作）。
新增 class 必须同时修改本文件与 verify-notes-format 的常量。

## 文件格式（verify-notes-format 门禁强制）

头部前三行精确为：

```markdown
# Note: <标题>

Status: <status>
```

Status 合法值：`proposed` / `implemented` / `rejected — <一句话原因>`，且必须与所在目录一致。

正文骨架：

| lifecycle | 骨架 |
|---|---|
| proposed | `## 问题` → `## 提案` → `## 备选方案` → `## 验收标准` → `## 风险` |
| implemented | `## 问题` → `## 决策`（现在时）→ `## 备选方案` → `## 后果` |
| rejected | 冻结的提案原文，判决在 Status 行 |

- `## 问题` 永远第一节，要能脱离方案独立成立。
- **`## 备选方案` 是强制的**：只记录真实考虑过的方案，每个写清「为什么输了」。不记录被击败方案的决策会招来重新争论——这正是 notes 存在要防止的失败。
- implemented 中禁止提案期标题（`## 提案` `## 验收标准`），迁移时必须改写骨架。

## 写作纪律

- 长度不是标准，信息密度是。
- 交叉引用必须用相对 markdown 链接，禁止裸文字。
- 禁止集中式 INDEX.md；active 树本身就是工作清单。
- note 永不编辑成另一个决策。

## 已确认的简化（相对 DSH 原版）

- 不引 stacked PR 流程（单人/小团队过重；保留为 rejected 候选，团队 >4 人可重议）。
- archived 暂不做 append-only 哈希冻结清单（归 Tier 2，notes >100 篇且历史被「顺手现代化」时开启）。
