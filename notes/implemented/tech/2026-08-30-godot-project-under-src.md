# Note: Godot 工程收口到 src/，与仓库基建分离

Status: implemented

## 问题

根目录有 27 个条目：7 个 Agent 入口（dotfile）、6 个游戏目录（`addons` `assets` `core` `game` `levels` `tests`）、6 个基建目录（`design` `docs` `mcp` `notes` `skills` `tools`）、6 个根文件、以及 `.godot` 缓存与 `.github`。

根因不是「游戏代码怎么分包」，而是**两套不同生命周期的东西被摊在同一层**：

- **Godot 工程**：引擎拥有、随游戏内容增长、由编辑器管理其导入缓存与 uid
- **AI 开发范式基建**：决策记录、SOP、门禁、MCP 集成、设计契约——与具体引擎无关，换引擎也保留

上一版决策 [directory-conventions](2026-08-29-directory-conventions.md) 把 `core/` `game/` `levels/` 提到根层，依据是 Godot 官方《Project organization》的扁平示例。该依据被误用：**官方示例假设仓库只含一个游戏**，其结构中没有 notes/skills/tools 这类基建层。同时该决策引用了 `abmarnie/godot-architecture-organization-advice`，却漏掉其首要建议——「所有源码放 `src/` 便于导航」，其示例根结构仅 `addons/ + assets/ + src/` 三个游戏目录。取其「场景中心」而弃其「src 收口」属选择性引用。

## 决策

**`src/` 成为完整的 Godot 工程根**，`project.godot` 移入其中。仓库根只保留基建与元信息。

```
game-template/
├── src/                      # 整个 Godot 工程；res:// == src/
│   ├── project.godot
│   ├── core/                 # 架构层
│   ├── game/                 # 游戏功能包
│   ├── levels/               # 关卡
│   ├── ui/                   # 全局 UI（按需）
│   ├── assets/               # 全局共享与批量生成资源 + AI 台账
│   ├── data/                 # 运行时数据：vocabulary/ content/
│   ├── addons/               # 第三方 Godot 插件（引擎要求 res://addons/）
│   ├── tests/                # 测试
│   └── .godot/               # 导入缓存（随工程移入，根目录因此变干净）
├── design/                   # 人与 Agent 读的设计契约：pillars.md、capability_catalog.json
├── notes/  skills/  tools/  mcp/  docs/
└── AGENTS.md 等根文件 + Agent 入口 dotfile
```

根层游戏目录从 6 个降为 1 个，实体目录从 12 个降为 7 个，且类别清晰：**1 个游戏 + 6 个基建**。

### 附带收益

- `res://` 路径变短：`res://core/capability.gd` 而非 `res://src/core/capability.gd`。
- `.godot/` 缓存与 `addons/` 都被收进 `src/`，不再占用根层视野。
- 换引擎或增加第二个前端（例如 Web 版数值原型）时，基建层无需改动。

### `design/` 的拆分依据

`design/` 原本混合了两种性质的内容，本次按性质拆开：

| 内容 | 性质 | 去向 |
|---|---|---|
| `vocabulary/` | 门禁与**运行时**双方消费（`Vocabulary.gd` 读 `index.json`） | `src/data/vocabulary/` |
| `content/` | 游戏数据，运行时读取 | `src/data/content/` |
| `pillars.md` | 纯人读契约，永不进运行时 | 留在 `design/` |
| `capability_catalog.json` | 生成物，Agent 读，永不进运行时 | 留在 `design/` |

判据是**是否需要 `res://` 访问**。词汇表仍是「全项目唯一公共 API」，其地位不因位置改变——它现在位于游戏工程内，这与它「被运行时加载」的事实更一致。

### 门禁与命令的适配

- `tools/verify/_common.py` 增加 `GODOT_PROJECT = REPO_ROOT / "src"`，全部运行时路径常量以此为基。
- Godot 命令统一加 `--path src/`。
- `run_all.py` 的测试调用与 CI、lefthook 的 glob 同步更新。

## 备选方案

- **维持扁平（上一版结构）**：输在混层。游戏目录与基建目录同层，新增基建（如 Tier 1 门禁的数据目录）会继续加剧混乱；且它对「一个仓库同时含游戏与开发范式」这一实际情况没有表达能力。
- **`project.godot` 留在根，仅代码移入 `src/`**：输在收口不完整。`addons/` 被引擎强制要求位于 `res://addons/`，故必须与 `project.godot` 同层；`assets/`、`tests/`、`.godot/` 也会滞留根层，实体目录仅从 12 降到 10，收益有限。
- **`design/` 整体移入 `src/`**：输在混淆。`pillars.md` 与 `capability_catalog.json` 永不被运行时读取，放进游戏工程会让 Godot 无谓导入，且削弱它们作为「跨阶段契约」的可见性（探索期项目尚无 `src/` 内容，但已需要 `pillars.md`）。
- **`design/` 整体留在根，由生成器向 `src/` 输出运行时副本**：技术可行且与既有「生成物 + 新鲜度门禁」模式一致，但输在重复与门禁增量。`content/` 是人工编写的游戏数据而非生成物，无法用该模式覆盖，最终仍需拆分 `design/`——那不如一次按性质拆清。
- **基建层移入 `harness/` 等单一目录，游戏留在根**：与本决策镜像对称。输在两点：Godot 编辑器会把整个仓库当作工程扫描（基建目录需逐个 `.gdignore`）；且基建是本模板的核心价值，把它降为一个子目录不符其地位。

## 后果

- 代价：一次性改动全部 `res://` 路径、门禁常量、测试入口、CI 与 hooks 的 glob、文档中的命令示例；Godot 需重建 `.godot` 缓存与 `.uid`。已有的两个实例项目（`game-fanren-godot`、`game-xiuxian-godot`）需同步迁移。
- 收益：根层类别清晰，新成员与 Agent 一眼可分「游戏」与「范式」；基建层与引擎解耦，未来可服务非 Godot 前端。
- 本决策 supersede [directory-conventions](2026-08-29-directory-conventions.md) 中关于**顶层布局**的部分；该 note 中的资源归属三级分流、`core/` 准入标准与切分触发器、`.tres` 优于 `.res`、前置断言、不在编辑器外移动文件等结论**继续有效**，仅其路径前缀由 `<root>/` 变为 `src/`。
