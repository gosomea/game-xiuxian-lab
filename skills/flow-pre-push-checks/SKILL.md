---
name: flow-pre-push-checks
description: Use before pushing, before claiming checks pass — push 前、或要对他人/自己声称「检查通过」之前使用。不用于日常编辑中的快速自检（那时跑单个相关门禁即可）。
---

# flow-pre-push-checks

推送前选最小检查集并取证。本文件是指引，不是清单脚本。

真相来源：根 `AGENTS.md`（命令表、约定 6/9）、`notes/implemented/process/2026-08-28-gate-tiers.md`。

## 工作流

1. **核实变更面**：`git status` + `git diff --stat`，列出变更涉及的域（src / design / notes / skills / tools / docs）。
2. **选最小检查集**：
   - `src/` 或 `tests/` 变了 → 运行时测试 + verify-capabilities + verify-component-purity；改了能力还要重跑 `gen_capability_catalog.py`
   - `src/data/vocabulary/` 变了 → 重跑 `gen_vocabulary_index.py` + verify-vocabulary
   - `src/game/`、`design/package_policy.json` 或豁免 note 变了 → verify-packages
   - 任何 `.tscn` 变了 → verify-scenes（场景路径非法会导致引擎段错误，必查）
   - `notes/` 变了 → verify-notes-format
   - `skills/`、`docs/` 变了 → 人工通读改动 diff
   - `tools/` 变了 → negative_control.py 必须重跑
3. **执行**：优先跑 `python3 tools/verify/run_all.py --with-tests`（含负向控制与运行时测试）；变更面小可只跑选中项。
4. **取证汇报**：只汇报实际跑过的命令与其结果；没跑的不说「应该没问题」。失败项如实列出，不带「可能」「应该」。
5. **推送**：全绿后推送；若本地绿 CI 红，以 CI 为准并记录差异原因（环境差异是待修问题，不是豁免理由）。

## 排除

- 不用 `--no-verify` 跳过 hooks（用户显式要求时才可，且必须汇报跳过了什么、为什么 CI 会不同）。
- 不重复跑已经绿过且变更面不涉及的检查。
