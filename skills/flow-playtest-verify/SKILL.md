---
name: flow-playtest-verify
description: Use for playtest-level acceptance of a feature — 功能做完需要「真跑起来」验收时使用：启动游戏、观察状态、截图、出报告。不替代单元测试（先跑 tests）与数值模拟（走 flow-balance-check）。
---

# flow-playtest-verify

「能跑」与「是对的」之间的最后一道验证。本文件是指引，不是清单脚本。

真相来源：根 `AGENTS.md`（约定 5：本流程两档实现，无 MCP 不阻塞）、`notes/implemented/tech/2026-08-28-capabilities-architecture.md`（负面保证：门禁不承诺好玩）。

## 两档形态

- **CLI 档（任何 Agent/人可用）**：`godot --headless` 启动场景 → 读状态断言 → 输出文本报告。
- **MCP 档（装了 dsh-godot-ai / godot-mcp 时）**：编辑器内实时操作 + 截图视觉闭环。用了就标注，缺失不构成阻塞。

## 工作流

1. **定验收点**：本功能「玩起来是对的」的可观察标准是什么？（状态变化/画面表现/交互反馈）写不出验收点的功能不算做完。
2. **跑测试先行**：`godot --headless --path . tests/test_runner.tscn` 全绿才进入 playtest（顺序不可换）。
3. **启动与观察**：CLI 档用 headless 场景 + 状态打印断言；MCP 档进编辑器运行 + 截图。
4. **记录证据**：状态断言输出 / 截图文件（放 `docs/playtest/` 并按日期命名）。
5. **判定与汇报**：验收点逐项给 PASS/FAIL + 证据链接；FAIL 项明确归属层（机制实现/数值/表现/疑似引擎问题）。手感类主观项标「需人工 playtest」，不替人下结论。

## 排除

- 不用「代码看起来对」替代运行证据。
- 不在 playtest 中顺手修无关问题（发现另开变更）。
