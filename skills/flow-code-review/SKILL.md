---
name: flow-code-review
description: Use when reviewing a diff/PR (self-review before push or peer review) — 审查任何变更 diff 时使用，含 AI 自审与多人互审。不用于日常实现过程（实现完先跑 flow-pre-push-checks）。
---

# flow-code-review

一个有一条实锤 blocker 的短评审，好于一串 nit。本文件是指引，不是清单脚本。

真相来源：根 `AGENTS.md`、`notes/README.md`、`notes/implemented/tech/2026-08-28-capabilities-architecture.md`。

## 起手式

核实审查范围（分支/base/head 或本地 diff）→ 拉全量 diff → 读足够周边代码理解设计意图。

## Blocking requirements（任一不满足即 blocker）

1. **铁律合规**：Component 无决策（对照 purity 门禁覆盖不到的语义层）；Capability 之间无直接引用；新增 Tag/事件已登记词汇表。
2. **先决策后实现**：`src/` 或 `tools/` 的变更能回溯到 notes；缺 note 的非琐碎变更打回。
3. **门禁证据**：与变更面匹配的检查已实际运行（对照 flow-pre-push-checks）；门禁自身的改动附负向控制证明。
4. **生成物同步**：词汇分文件变了 index.json 必须同 diff 更新。
5. **notes 质量**：新增 note 骨架合规、`## 备选方案` 非空且只含真实考虑过的方案。

## 手工检查（选与变更面相关项）

- 通信纪律：新耦合是否藏在共享数据的「约定俗成」里（读写同一字段但没更新词汇表/组件文档）。
- instigator 账目：阻塞/时停/压制的发起者是否在失活/退场路径全部清理。
- 散文语义：新增文档/注释/提示词是否可被「只有仓库、没有会话记录」的读者解析（cot-leakage 唯一测试）。
- AI 资产：assets/ 变更是否登记台账（Tier 1 启用后由门禁兜底，此前靠本项人工查）。

## 汇报格式

按「缺陷、位置、影响、证据」陈述；blocker 与建议分离；已被绿门禁覆盖的问题省略。收到 review 时逐条核实，基于技术理由修复或反驳，不做表演性认同。

## 排除

- 不审 `notes/archived/`（冻结）、不改审查范围外的文件。
