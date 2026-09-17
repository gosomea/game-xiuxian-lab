# Note: 场景中心的两级玩法分包

Status: implemented

## 问题

0.3 的 `src/game/<功能>/` 只有「按功能放在一起」这一条语义，且把 feature 描述为可小到一个能力、也可大到一个子系统。执行者面对已有 `combat/`、`movement/` 等目录时，没有机械依据判断应继续复用还是拆包，容易把导航领域误当删除单元。catalog 的 `feature` 字段也把这两个层级压成一个含义，门禁无法统计真正可独立增删的叶子包。

Godot 场景与资源倾向按自包含场景就近组织，因此目录边界还需要明确场景、功能 UI、Component 和共享契约的所有权，而不能只约束 GDScript 放在哪个文件夹。

## 决策

运行时玩法统一放在 `src/game/<domain>/<package>/`。第一层 domain 只负责导航，推荐 `actors/`、`abilities/`、`systems/`、`shared/`，但允许项目使用其他 `snake_case` 名称；第二层 package 才是可独立增删、由门禁统计的叶子包。领域目录不得直接放 `.gd`、`.tscn`、`.tres` 等运行时文件。

叶子包同时满足三项判据：同一玩家可感知行为、同一状态生命周期、同一删除单元。同属 combat 或 movement 只是导航关系，不足以合并为一个包。Capability 及配对测试放在包根；包内可继续建立贴图、音频、模型等资源子目录。

有明确领域所有者的 Component 留在所有者包，即使其他包读取它。只有没有自然所有者的跨包数据契约进入 `shared/<contract>/`，且必须有 owning note。`levels/` 只放完整关卡及关卡专属编排；可复用场景和功能专属 UI 留在所属叶子包。M1/M2/M3 等开发阶段名不得成为长期运行时包或类型边界。

包规模超过 4 个 Capability 或 12 个非测试 GDScript 时失败。确实仍属于同一删除单元的包可在 `design/package_policy.json` 中豁免，但必须提供非空理由并引用 `notes/implemented/` 下 `Status: implemented` 的 owning note。

capability catalog 升级为 schema v2，以 `domain` 和 `package` 表达两级归属；`feature/features` 不再兼容。`src/levels/` 下正式关卡场景的根节点若挂脚本，脚本 basename 必须与场景 basename 相同，使场景的控制入口可直接定位。

## 备选方案

- **保留单层 `game/<feature>/`，只补写更多文字说明**：输在无法机械区分导航大类和删除单元；`combat/` 是否过大仍完全依赖执行者临场判断，catalog 和门禁也拿不到稳定边界。
- **强制四个固定领域白名单**：输在模板替具体游戏做了过多领域建模。`actors/abilities/systems/shared` 适合作为推荐导航，但卡牌、叙事或建造游戏可能需要不同领域名；结构门禁只应约束层级、命名和叶子边界。
- **允许三层及更深代码包**：输在统计边界重新变得含糊。资源子目录可以更深，但 Capability 与 GDScript 代码继续下沉会让 package 到底是哪一级无法由路径稳定推导。
- **任何超阈值都强制拆包，不设豁免**：输在把规模指标误当架构真理。少数高内聚删除单元可能合理地超过阈值，但必须通过 implemented note 让该例外成为有意、可复查的决定。

## 后果

- 收益：模板示例位于 `src/game/systems/vitals/`，sandbox 根挂同名 `sandbox.gd`；package gate 能机械检查结构、阈值与 implemented note 豁免，catalog v2 明确输出 `systems` 与 `systems/vitals`。
- 收益：scene gate 拒绝正式关卡场景根挂异名脚本，同时 Sheet、测试场景与子节点脚本不受同名规则误伤。
- 代价：0.4.0 是破坏性目录升级，派生项目需要通过 Godot 编辑器手工移动并重新 import；`docs/migrations/0.3-to-0.4.md` 提供选择性同步步骤，不建立自动同步。
- 已知边界：按文本识别 Capability 仍可能漏掉间接继承；不做孤儿脚本启发式硬门禁，删除完整性继续由 View Owners、路径搜索和 `class_name` 动态实例化人工审查兜底。
- 验证：`godot --headless --path src --import` 成功；12 条 Tier 0、27 项负向控制、8 个 package policy 单测与 47 条 Godot 断言全部通过。
