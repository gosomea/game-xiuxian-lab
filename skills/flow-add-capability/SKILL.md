---
name: flow-add-capability
description: Use when adding a new Capability (行为单元) to the game — 新增任何功法/神通/被动/移动方式等行为单元时使用。不用于纯数值内容（走 flow-add-content）或修复现有能力缺陷（直接改并跑门禁）。
---

# flow-add-capability

新 Capability 的标准落地流程。本文件是指引，不是清单脚本；每步先理解再执行。

真相来源：根 `AGENTS.md`（铁律 1/2/3）、`src/game/AGENTS.md`、`notes/implemented/tech/2026-08-28-capabilities-architecture.md`、`src/data/vocabulary/`、`design/capability_catalog.json`（现有能力全貌）。

## 工作流

1. **核实现状**：读 `design/capability_catalog.json` 确认要加的能力是否已存在或有近似实现；读 `src/data/vocabulary/` 相关域文件，确认本次需要的 Tag/事件/Component 字段是否已登记；未登记的词汇**先登记**（编辑对应域 JSON，重跑 `python3 tools/gen/gen_vocabulary_index.py`）。
2. **确认决策**：该能力是否已有 notes 覆盖其设计？新机制（非现有机制的又一个实例）先写 proposed note，确认后再动手（AGENTS.md 铁律 3）。
3. **定位叶子包**：依次回答五个问题，不得因为已有 `combat/` 或 `movement/` 就直接复用：①是否是同一玩家可感知行为；②是否共享同一状态生命周期；③删除时是否必须整体删除；④Component、场景、功能 UI 与资源各自有无明确所有者；⑤加入后是否超过 4 个 Capability 或 12 个非测试 GDScript。三项边界不同时新建 `src/game/<domain>/<package>/`；领域只导航，推荐 `actors/abilities/systems/shared` 但不设白名单。`src/game/combat/*.gd` 错；`src/game/abilities/spirit_quake/`、`src/game/systems/targeting/` 对。有明确所有者的 Component 留在所有者包；无自然所有者的契约才进 `shared/<contract>/`，且先写 owning note。
4. **写能力**：声明 `class_name`，继承 `Capability`，实现五函数轴；遵守通信纪律（只读写 Component、用 TagRegistry 阻塞，**禁止引用其他 Capability——同一功能包内也不例外**）。时序判断读 `manager_time()` 而非墙钟时间。
5. **写配对测试**：与能力脚本**同目录**的 `test_<basename>.gd`，每个用例首行 `t.begin_case()`；至少覆盖激活条件成立/不成立、失活清理（含 instigator 阻塞撤销）。注册到 `tests/test_runner.gd` 的 SUITES。
6. **重生成 catalog**：`python3 tools/gen/gen_capability_catalog.py`。
7. **验证包边界**：运行 `python3 tools/verify/verify_packages.py`；超阈值优先拆包，确属同一删除单元时先完成 implemented owning note，再登记 policy 豁免。
8. **完整验证**：`python3 tools/verify/run_all.py --with-tests` 全绿。
9. **汇报**：新增/修改文件清单、domain/package 选择依据、新增词汇（如有）、门禁与测试输出摘要、已知边界。

## 排除

- 不改 `core/`（改动需单独 notes 决策）。
- 不跨能力引用「方便一下」——需要对方的数据就往 Component 设计里放。
- 不在 Capability 里写数值表（数值属于内容层，走 flow-add-content）。
