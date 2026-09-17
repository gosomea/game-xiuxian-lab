# Note: 目录结构对齐 Godot 社区惯例

Status: implemented

Superseded: 2026-09-02 — 资源归属、`core/` 准入和 Godot 编辑纪律继续有效；顶层 `project_root/game/vitals` 布局先由 0.3 的 `2026-08-30-godot-project-under-src.md`、再由 0.4 的 `2026-09-02-two-level-gameplay-packages.md` 取代。以下旧树保留为历史。

## 问题

上一版结构（`src/core` + `src/features` + `src/demo` + 顶层 `assets/`）存在三个缺陷，其中第一个由本仓自身造成：

**资源归属双轨制。** 曾同时提议「功能包内建 `assets/` 子目录」（场景中心流派）与保留顶层 `assets/`（代码分离流派）。两种流派混用后，一张图该放哪没有可判定的规则——这是最坏的形态。

**命名不属游戏惯例。** `features/` 是前端/后端约定（React、Vue 的 feature folders）。Godot 官方示例结构使用领域名词（`models/`、`characters/`、`levels/`、`docs/`），`abmarnie/godot-architecture-organization-advice`（263 stars，Godot 4 专门向）使用 `addons/`、`assets/`、`src/`，两家均无 `features/`。`demo/` 同样偏离——在游戏语境中它本质是一个关卡，Godot 官方对应目录为 `levels/`。

**`core/` 的膨胀风险被误判为结构问题。** 实际是准入问题：`core/` 随架构增长而非随游戏内容增长（功法从 8 门扩到 40 门不会给 `core/` 增加任何文件）。真正的风险是它吸收「通用但非框架」的内容（伤害公式、网格工具、数值查表），退化为倾倒场——与 `shared/` 同一种失败模式。

## 决策

### 采用场景中心结构

```
project_root/
├── addons/              # 第三方 Godot 插件，各自附带 license
├── core/                # 架构层：基类与全局设施（准入见下）
├── game/                # 游戏内容，一包一功能；场景专属资源放包内
│   ├── vitals/
│   └── shared/          # 跨功能共享，准入需 notes 决策
├── levels/              # 关卡场景（引用 game/ 的内容）
│   └── sandbox.tscn     # 模板示例关卡，实例化时可删
├── ui/                  # 全局 UI（按需创建）
└── assets/              # 仅「全局共享」与「批量生成」资源 + AI 资产台账
```

**资源归属规则**（消灭双轨制，采自 abmarnie 的三级分流）：

| 资源类型 | 位置 |
|---|---|
| 场景专属 | 与场景同目录，**以场景名做前缀** |
| 某类场景共享 | 以该场景类型命名的中心目录 |
| 全局共享 / 批量生成 | `assets/`，按数据类型或类别分目录 |

**场景名前缀**是新增约定，价值在于搜索即导航：搜索 `vitals` 一次得到 `vitals.tscn`、`vitals_component.gd`、`vitals_icon.png`、`vitals_data.tres`。

`assets/` 保留但职责收窄为「全局共享 + 批量生成」，正好承载 2D 美术管线的批量产出与 Steam AI 披露台账。

### `core/` 的准入标准与切分触发器

准入：**只有「不认识任何具体玩法、且被两个以上功能包依赖」的架构设施可进 `core/`。**

明确反例（属 `game/shared/` 而非 `core/`）：伤害计算公式、网格/坐标工具、数值查表、任何提及具体游戏概念的代码。

切分触发器：**超过 15 个文件时**按职责分为 `core/base/` 与 `core/globals/`，**不提前切分**。当前 7 个文件，扁平可读。

### 三条采纳的社区规范

**资源用 `.tres` 而非 `.res`**：文本格式使 git 历史人类可读。大数值块（mesh 等）可例外。写入 `src/AGENTS.md`。

**前置断言优于防御性检查**：在 `_ready` 或依赖注入点 `assert` 关键属性已正确设置，尽早暴露配置错误；不在各处写 null 检查掩盖问题。写入 `src/AGENTS.md`。

**不在 Godot 编辑器外移动或重命名文件**：会导致 `.uid` 与场景内引用同本地文件失去同步。本仓此前的迁移均由 shell 完成，因此每次都需 `--import` 重建缓存。写入 `src/AGENTS.md`，并说明不得已在外部移动后的补救步骤。

另有一条既有决策获得外部验证：全局状态优先级为 `static` > 自定义 Resource > Autoload（仅限横切关注点），本仓的静态类选择（见 [static-globals-over-autoload](2026-08-28-static-globals-over-autoload.md)）正是该优先级的首选项。

### 规模适用性声明

`abmarnie` 明确指出：代码量低于一万行、场景资源少于百个、或单人开发时，此类架构实践「收益充其量是边际的」。本模板当前 13 个文件，因此纪律为：**顶层命名现在定对**（此时改动成本近零，后期需改动全部路径引用、门禁与文档），**子层切分推迟到触发器满足**（现在做是过早优化）。

## 备选方案

- **代码分离流派（`game/` 只放代码与场景，全部美术集中 `assets/`）**：输在与两家权威相悖。Godot 官方核心建议是「把资源尽可能放在使用它的场景附近」，abmarnie 同为场景中心。该方案的优点（批量美术管线路径统一）已由 `assets/` 职责收窄保留。
- **保留 `features/` 命名**：输在惯例。它是 Web 领域约定；游戏领域使用领域名词。虽有 AI-agent 向的 Godot skill 提倡 feature-driven 结构，但其指的是组织原则而非目录名。
- **`demo/` 保留为独立顶层目录（或改名 `examples/`）**：输在必要性。模板的 demo 本质是一个沙盒关卡，`levels/sandbox.tscn` 已足够表达，无需为一个场景单开顶层目录。
- **现在就切分 `core/`（`core/base/` + `core/globals/`）**：输在过早。7 个文件的扁平目录完全可读；切分会引入两层路径而无实际收益。已设数字触发器，届时切分成本极低。
- **完全按类型分包（`scripts/`、`scenes/`、`textures/`）**：`abmarnie` 承认这种「数据导向」目录对某些项目更好，优点是不必思考新文件该放哪。输在功能内聚——本仓已在 [src-feature-packaging](2026-08-28-src-feature-packaging.md) 论证：功能被拆散会导致改动跨目录、删除留孤儿、资源无处安放。
- **按玩家可见系统分包（`actors/` + `systems/` + `ui/`）**：更贴近 Godot 官方示例（`characters/` + `levels/`），但输在跨切面。一个「战斗」功能会同时横跨 actors、systems、ui 三处，重新引入功能被拆散的问题。`levels/` 与 `ui/` 予以采纳（它们确实是独立维度），实体与逻辑仍按功能聚合于 `game/`。

## 后果

- 代价：本次迁移改动全部路径引用（门禁常量、场景 `ext_resource`、测试 SUITES、文档）；Godot 需重建 `.uid` 与导入缓存。「场景名前缀」约定尚无门禁强制，依赖人工与评审。
- 收益：资源归属有唯一可判定规则；目录名与 Godot 社区惯例一致，新成员与 Agent 的认知成本降低；`core/` 有明确准入与切分条件，膨胀路径被显式堵住。
- 验证：11 条门禁全绿，22 项负向控制仍全部被拒，47 条运行时断言通过。
