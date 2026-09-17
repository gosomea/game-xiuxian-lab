# game/ — 运行时架构与编写规则

> 子树规则。全局规则见仓库根 [AGENTS.md](../../AGENTS.md)，不在此重复。
> 本文件描述 `src/`（Godot 工程根，`res://` 等价于此）内部的组织与纪律。
> 架构决策真源：[capabilities-architecture](../../notes/implemented/tech/2026-08-28-capabilities-architecture.md)、[sheet-format](../../notes/implemented/tech/2026-08-28-sheet-format.md)、[two-level-gameplay-packages](../../notes/implemented/tech/2026-09-02-two-level-gameplay-packages.md)、[directory-conventions](../../notes/implemented/tech/2026-08-29-directory-conventions.md)。

## 顶层目录职责

结构对齐 Godot 官方《Project organization》与社区惯例：**按功能分包，资源尽量靠近使用它的场景。**

| 目录 | 内容 | 纪律 |
|---|---|---|
| `core/` | Capability / Component 基类、CapabilityManager、TagRegistry、TimeKeeper、SheetLoader、Vocabulary | 架构层。**准入见下**；不放任何具体玩法；改动需单独 notes 决策 |
| `game/<domain>/<package>/` | 领域导航下的叶子功能包：数据、能力、测试、Sheet、可复用场景与专属资源 | **package 必须可整体删除而不留孤儿** |
| `game/shared/<contract>/` | 没有自然领域所有者的跨包数据契约 | 必须有 owning note；不是「不知道放哪」的去处 |
| `levels/` | 完整关卡与关卡专属编排，引用 `game/` 内容 | 可复用子场景不放这里；正式关卡根脚本与场景同名 |
| `ui/` | 全局 UI（按需创建） | 功能专属 UI 属于该功能包 |
| `assets/` | **仅**全局共享与批量生成的资源 + AI 资产台账 | 场景专属资源不放这里 |
| `data/` | 运行时数据：`vocabulary/`（全项目唯一公共 API）、`content/`（游戏内容 JSON） | 运行时经 `res://data/...` 读取；门禁同时消费 |
| `addons/` | 第三方 Godot 插件 | 各自附带 license |

### `core/` 准入标准

**只有「不认识任何具体玩法、且被两个以上功能包依赖」的架构设施可进 `core/`。**

明确反例（属某个领域所有者包，或经 owning note 进入 `game/shared/<contract>/`，不属 `core/`）：伤害计算公式、网格与坐标工具、数值查表、任何提及具体游戏概念的代码。

`core/` 随架构增长，不随游戏内容增长——功法从 8 门扩到 40 门不会给它增加任何文件。**超过 15 个文件时**才按职责切分为 `core/base/` 与 `core/globals/`，不提前切分。

### 两级玩法包（唯一受支持形态）

```
game/
├── abilities/
│   ├── spirit_quake/       # 玩家可独立感知、独立生命周期、可独立删除
│   └── wisp_surge/
├── actors/
│   └── spirit_wisp/
├── systems/
│   ├── targeting/
│   └── vitals/
└── shared/
    └── run_upgrade/        # 无自然所有者的契约；必须有 owning note
```

第一层 domain **只负责导航**。推荐 `actors/`、`abilities/`、`systems/`、`shared/`，但不设白名单；其他领域名必须是 `snake_case`。第二层 package 才是门禁统计和可独立增删的叶子包，按三项同时判定：

1. 同一玩家可感知行为；
2. 同一状态生命周期；
3. 同一删除单元。

同属 combat 或 movement 不足以放进同一包。**错误**：`game/combat/*.gd`，领域根直接堆运行时文件。**正确**：`game/abilities/spirit_quake/`、`game/systems/targeting/`。M1/M2/M3 等开发阶段名不得作为长期运行时包或类型边界。

领域目录不得直接放 `.gd`、`.tscn`、`.tres` 等运行时文件。Capability 及其 `test_<basename>.gd` 留在叶子包根；贴图、音频、模型等资源可在包内继续建子目录。超过 4 个 Capability 或 12 个非测试 GDScript 时，先按行为/生命周期/删除单元拆包；确实不可拆才通过 `design/package_policy.json` + implemented owning note 豁免。

### 所有权与场景归属

- 有明确领域所有者的 Component 留在所有者包，即使其他包读取它；不要为了“被多人读取”就移进 shared。
- 只有没有自然所有者的跨包数据契约进入 `shared/<contract>/`，且 owning note 必须说明为什么没有自然所有者。
- `levels/` 只放完整关卡及关卡专属编排；功能专属 UI、可复用场景、材质与音效留在所属叶子包。
- `src/levels/<name>.tscn` 的根节点若挂控制脚本，脚本必须命名为 `<name>.gd`；可复用子场景和子节点脚本不受此规则限制。

### 资源归属规则

| 资源类型 | 位置 |
|---|---|
| 场景专属 | 与场景同目录，**以场景名做前缀** |
| 某类场景共享 | 以该场景类型命名的中心目录 |
| 全局共享 / 批量生成 | `assets/`，按数据类型或类别分目录 |

**场景名前缀让搜索即导航**：搜 `vitals` 一次得到 `vitals_sheet.tscn`、`vitals_component.gd`、`vitals_icon.png`、`vitals_data.tres`。

### 叶子包内的文件约定

```
game/systems/vitals/
├── vitals_component.gd          # 数据（extends Component）
├── vitals_regeneration.gd       # 能力（extends Capability）
├── test_vitals_regeneration.gd  # 配对测试，必须与被测脚本同目录
├── vitals_guard.gd
├── test_vitals_guard.gd
├── vitals_sheet.tscn            # Sheet 按 _sheet.tscn 后缀识别，不靠目录
└── vitals_icon.png             # 场景专属资源，同名前缀
```

Capability 门禁仍按 `extends Capability` 发现目标；package gate 与 catalog v2 进一步要求能力位于 `game/<domain>/<package>/` 的包根。新增顶层运行时目录需在 `tools/verify/_common.py` 的 `RUNTIME_ROOTS` 登记，但玩法 Capability 不得借此绕过两级包边界。

## 编写纪律

### 架构

- 五函数轴中 `_should_activate` 是最小契约，必须实现；至少再实现一个行为函数。
- Capability 必须声明 `class_name`（catalog 与门禁按类名识别）。
- 配对测试 `test_<basename>.gd` 必须与被测脚本**同目录**。
- **同一功能包内的能力之间同样禁止直接引用。** 物理相邻不改变解耦要求——需要别人的数据就往 Component 设计里放字段，不去 `get_node` 抓对方的 Capability。
- 互斥/禁制 → `TagRegistry.add_block(target, tag, self)`，解除时传同一个 `self`；退场路径必须清账（`_on_deactivated` 或 `_exit_tree`）。
- 时停/变速 → 只走 `TimeKeeper.request/release`，禁止直接改 `Engine.time_scale` 或 `get_tree().paused`。
- 时序判断（冷却、延迟、持续时长）读 `manager_time()` 而非墙钟时间，使无头测试可精确推进。
- signal 只用于纯数据变化通知，不承载行为决策。
- 静态设施（TagRegistry / TimeKeeper / Vocabulary）跨场景存活，切换场景或测试用例之间必须 `clear_all()`。
- 全局状态优先级：**`static` > 自定义 Resource > Autoload**（Autoload 仅限横切关注点）。本仓的静态类选择即该优先级的首选项。

### 词汇与生成物

- 新增任何 `&"词汇"` 前先在 `src/data/vocabulary/`（`res://data/vocabulary/`）登记并重跑索引生成器。
- 改动能力后必跑 `python3 tools/gen/gen_capability_catalog.py`。

### Godot 工程实践

- **资源用 `.tres` 而非 `.res`**：文本格式让 git 历史人类可读。大数值块（mesh 等）可例外，但同类资源的扩展名要保持一致。
- **前置断言优于防御性检查**：在 `_ready` 或依赖注入点 `assert` 关键属性已正确设置，尽早暴露配置错误；不要到处写 null 检查掩盖问题。
- **不在 Godot 编辑器外移动或重命名文件**：会导致 `.uid` 与场景内 `ext_resource` 引用同本地文件失去同步。不得已在外部移动后，必须 `rm -rf src/.godot && godot --headless --path src --import` 重建缓存，并跑 `verify-scenes` 确认无悬空引用。
- 节点名用 PascalCase，文件与目录名用 snake_case（导出后的 PCK 是大小写敏感的）。
- 删除场景或资源前先在编辑器右键 → View Owners 检查依赖。

## 改动后必跑

```bash
python3 tools/gen/gen_capability_catalog.py
python3 tools/verify/verify_packages.py
python3 tools/verify/run_all.py --with-tests
```
