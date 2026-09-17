---
name: flow-add-content
description: Use when adding data-driven game content — 功法/法宝/事件/道具等纯数据内容（JSON）的新增或批量生产时使用。不用于新增行为机制（走 flow-add-capability）。
---

# flow-add-content

内容层数据的标准生产流程。本文件是指引，不是清单脚本。

真相来源：`design/pillars.md`（内容必须回溯到支柱）、`src/data/vocabulary/`、`notes/implemented/process/2026-08-28-gate-tiers.md`（Tier 1 的 content-schema 与 balance 门禁）。

## 工作流

1. **核实支柱**：该内容服务哪条设计支柱？回溯不了的不进仓库。
2. **核实词汇**：内容中引用的 Tag/事件/能力名必须已登记；引用未实现的能力时，在内容 JSON 标 `status: "blocked"` 并说明依赖，不许假装可用。
3. **按 schema 写数据**：运行时内容放 `src/data/content/<类别>/`（目录随首个内容类别建立）；字段遵循该类别的 schema（schema 文件与 Tier 1 门禁同步落地）。
4. **数值自检**：与同类内容对比关键数值（冷却/消耗/强度），明显离群的需要一句理由注释。
5. **验证**：`python3 tools/verify/run_all.py`（Tier 1 启用后含 content-schema 与 balance 模拟）。
6. **汇报**：新增内容清单、引用的能力/词汇、数值对比结论、balance 门禁输出（如启用）。

## 排除

- 不为内容写 GDScript（内容驱动不了时说明缺机制，走 flow-add-capability 或写 proposed note）。
- 不复制粘贴现有内容改数值充数（伪广度，pillars 明确反对）。
