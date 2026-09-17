# Note: 门禁分层启用体系（Tier 0/1/2）

Status: implemented

## 问题

门禁的价值随团队规模增长，但维护成本从第一天就存在。单人期全量照搬 DSH 的 30+ 门禁会拖垮迭代速度（过度工程是独立项目第一大死因）；完全不写又会在第二人加入时陷入「补课时推倒重来」。需要一个「写好但按阶段启用」的结构。

## 决策

门禁分三层，按条件启用；CI 从模板第一天进本体（单人时是第二双眼睛，多人时是裁判，不属于可选项）。

**Tier 0（已实现，全开）**：

| 门禁 | 检查内容 | 负向控制 |
|---|---|---|
| verify-capabilities | 五函数轴齐备、不引用其他 Capability、有配对测试、目录命名可发现 | 缺测试的能力、跨能力引用被拒 |
| verify-vocabulary | 代码中的 Tag/事件/组件词汇必须在 src/data/vocabulary/ 登记 | 打错 Tag 被拒 |
| verify-scenes | 场景引用/父路径合法、Sheet 非空、正式关卡根脚本同名 | 悬空引用、异名根脚本被拒 |
| verify-packages | `src/game/<domain>/<package>/` 层级、规模和 implemented note 豁免 | 领域根文件、超限包、无效豁免被拒 |
| verify-component-purity | Component 无每帧回调、不引用全局决策设施 | 塞决策函数、引用 TagRegistry 被拒 |
| verify-notes-format | notes 头部/Status/骨架/强制备选方案节 | 缺备选方案、Status 与目录不一致被拒 |
| verify-vocabulary-index | index.json 与分域文件新鲜度（gen/verify 配对） | 改分文件不重生成被拒 |
| verify-capability-catalog | capability_catalog.json 与能力源码新鲜度 | 改能力不重生成被拒 |

**Tier 1（待编写，第二人加入当周落地并全开）**：verify-content-schema（策划↔程序契约裁判）、verify-asset-ledger（AI 资产台账，Steam 披露兜底）、verify-balance（数值模拟门禁）、verify-notes-links（交叉引用存活）。这四条**尚未实现**——`run_all.py` 的 tier 参数与 CI 的 `if: false` job 是为它们预留的接线位。启用动作 = 实现脚本 + 注册到 GATES + 补负向控制用例 + 摘掉 CI 的 `if: false`，同日生效分支保护 + PR 模板 + CODEOWNERS。

**Tier 2（≥4 人或上架前按需）**：verify-prose（cot-leakage 审计）、GUT 测试框架迁移、archived 哈希冻结清单、core/ 覆盖率门禁、双语配对校验。

配套结构决策：

- **词汇表按域分文件**（tags/perception.json 等）+ 生成合并索引——消灭多人协作最大的合并冲突热点。
- **负向控制是门禁的入库条件**（根 AGENTS.md 约定 6）：每条门禁必须附带「故意非法案例被真实拒绝」的证明。
- 所有门禁为 `python3 tools/verify/<name>.py` CLI：Agent、人、CI 三方同一入口（见 [agent-agnostic-dual-plane](2026-08-28-agent-agnostic-dual-plane.md)）。
- **门禁必须给修复路径**：失败输出带 `fix=` 提示。只判对错不给出路的门禁会把 Agent 推入试错循环（见 [first-audit-gaps](2026-08-28-first-audit-gaps.md) 缺口 3）。

## 备选方案

- **单人期只写 Tier 0，Tier 1/2 需要时再写**：这正是当前采用的形态，但配套加了接线位（`--tier` 参数、CI 的 `if: false` job、gate-tiers 清单），使「需要时再写」不等于「到时候从零设计」。原先设想的「全部写好只是不启用」被否决：未接线的门禁脚本会随源码演进静默过时，启用时仍需重验，收益低于维护成本。
- **全量照搬 DSH 门禁密度**：输在维护税。DSH 是几百人年的仓库；个人/小团队项目的痛点清单不同，门禁只写「已经痛过」的规则（双语配对、stacked PR 等明确不痛的归入 Tier 2 或直接不引）。
- **门禁用 Godot 内建（GDScript 插件）而非 Python CLI**：输在消费面。GDScript 门禁只有装了 Godot 的环境能跑，CI 与无头检查受限；Python stdlib 零依赖 CLI 三方通吃（见双平面 note）。GDScript 侧的运行时不变式检查作为补充，不替代文件级门禁。

## 后果

- 代价：Tier 1/2 门禁写好到启用之间可能因上游格式变化而过时，启用时需先自验（负向控制用例仍被拒绝才算存活）。
- 收益：单人期只背 Tier 0 的维护税；协作扩容有明确的「翻开关」清单，扩容当周不走临时流程。
