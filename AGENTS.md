# AGENTS.md — game-xiuxian-lab

> 每个 Agent 会话进入本仓必读。本文件只放「每次会话都需要」的规则；子树特有规则放子树 AGENTS.md，不重复本文件已有内容。

## 一句话定位

独立的 2.5D 修仙模块实验室，基于 game-template 0.4.0。先搭建可独立运行的模块与组合实验场景，再考虑完整玩法；不要求核心循环、胜负条件或十分钟可玩版本。完全摒弃 game-xiuxian-godot：禁止从其迁移设计、代码、素材或建立运行依赖。运行时采用 Capabilities 能力架构，复用部分使用机械检查。**任何 Coding Agent（Codex / Claude Code / CodeBuddy / dsh）在本仓享有同等能力**——协作面只有：本文件、`design/`（词汇表与能力目录）、`notes/`、`skills/`、CLI 门禁脚本。

## 仓库布局

```
game-xiuxian-lab/
│  # 仓库根只放「与引擎无关」的开发范式基建
├── AGENTS.md                     # 本文件（唯一真身）
├── CLAUDE.md / CODEBUDDY.md      # symlink → AGENTS.md，只编辑真身
├── .agents|.claude|.codex|.codebuddy|.workbuddy/skills  # symlink → ../skills
│
├── src/                          # 整个 Godot 工程；res:// == src/
│   ├── project.godot
│   ├── core/                     #   架构层：基类与全局设施（准入严格）
│   ├── game/                     #   游戏功能包（AGENTS.md 在此，含编写纪律）
│   ├── levels/                   #   关卡场景
│   ├── ui/                       #   全局 UI（按需创建）
│   ├── assets/                   #   全局共享与批量生成资源 + AI 台账
│   ├── data/                     #   运行时数据：vocabulary/（公共 API）content/
│   ├── addons/                   #   第三方 Godot 插件
│   └── tests/                    #   godot --headless 可跑的测试
│
├── design/                       # 人与 Agent 读的契约（永不进运行时）
│   ├── pillars.md                #   设计支柱，每个游戏实例化时重写
│   └── capability_catalog.json   #   生成物：全部能力的触发条件/参数/依赖
│   └── package_policy.json       #   两级玩法包规模阈值与 implemented note 豁免
├── notes/                        # 决策记录（规则见 notes/README.md）
├── skills/                       # SKILL.md 标准作业程序，命名带域前缀
├── tools/verify/                 # 门禁脚本（Python 3 标准库，零依赖 CLI）
├── tools/gen/                    # 生成器；生成物不手改，verify 查新鲜度
├── mcp/                          # 可选 MCP 服务器集成（非依赖）
└── docs/                         # onboarding、playtest 记录等
```

## 命令表

| 命令 | 干什么 |
|---|---|
| `python3 tools/verify/run_all.py` | 全部 Tier 0 门禁 + 负向控制 |
| `python3 tools/verify/run_all.py --with-tests` | 附带运行时测试（需 Godot；未找到则跳过并提示） |
| `godot --headless --path src tests/test_runner.tscn` | 只跑运行时测试 |
| `python3 tools/gen/gen_vocabulary_index.py` | 重生成词汇索引（改了 `src/data/vocabulary/` 后必跑） |
| `python3 tools/gen/gen_capability_catalog.py` | 重生成能力目录（改了能力源码后必跑） |
| `godot --headless --path src --import` | 生成全局类缓存（首次 clone 后必跑） |

## Agent 上手顺序

本工程处于**模块探索期**。这是使用者明确选择的工作方式，优先于随模板继承的 flow-zero-to-one / flow-prototype 对原型位置、核心循环和建造准入的默认规则。

1. 读 `design/pillars.md`，了解实验室目标；不要替用户收口成完整游戏。
2. 读 `src/data/content/experiments.json`，它是模块清单与状态的真相源。没有场景的计划不得显示为已完成或伪造可运行入口。
3. 读 `design/capability_catalog.json` 与 `src/data/vocabulary/index.json`，再按需要读具体实现。
4. 独立实验放 `src/levels/experiments/<module>/`；组合实验也允许独立场景。可复用行为放两级 `src/game/<domain>/<package>/`。只有真正可抛弃的小比较才放临时目录。
5. 当前模块只确定局部操作与验证目标，不要求任务链、整体经济、主线或成品时长。`ready` 代表当前探索范围已能供组合使用；最终规则允许调整。
6. 新增稳定共享行为走 `flow-add-capability`；3D 场景读 `godot-3d-essentials`，UI 读 `godot-ui-control`，运行验收走 `flow-playtest-verify`。用户已授权的实现无需反复确认。
7. 模板 vitals 示例只保留在 `src/tests/fixtures/template_vitals/` 作为测试夹具，不属于本项目玩法或模块进度。基础核心来自模板，不复制旧修仙项目。

## 约定

### 铁律（架构层）

1. **Component 只存数据，不做决策。** 允许字段、派生值计算、数据存取方法、数据变化 signal；禁止 `_process`、行为分支、改全局状态。由 verify-component-purity 机械兜底。
2. **词汇表是全项目唯一公共 API。** Capability 之间禁止直接引用；通信只走 Component 共享数据 + TagRegistry 阻塞（带 instigator 登记）。新增 Tag/事件/Component 字段必须先在 `src/data/vocabulary/` 登记，verify-vocabulary 拒绝未登记的使用；运行时可用 `Vocabulary.assert_tag()` 自检。

### 铁律（流程层）

3. **先决策记录，后实现。** 任何 `src/` 运行时代码、任何门禁脚本落地前，对应的 notes 决策必须已存在（proposed 经确认或 implemented）。先写代码后补文档视为流程事故，需回滚后按正确顺序重做。
4. **非琐碎变更同 PR 带 notes。** 改变行为/架构/契约/工具链的决策必须在同一变更中新增或更新至少一篇 note；更新已持有该决策的 note 即满足，禁止重复建 note。
5. **Agent 无关检验。** 任何环节若只有某个特定 Agent 能完成，即为设计漏洞，必须打回重做。dsh-godot-ai 是可选增强，不是依赖。

### 约定（工程层）

6. **门禁负向控制**：每条门禁落地时必须在 `tools/verify/negative_control.py` 增加一个「故意非法案例被真实拒绝」的用例，否则该门禁视为不存在。
7. **门禁必须给修复路径**：新增门禁的失败输出要带 `fix=` 提示，指向具体命令或动作。只判对错不给出路的门禁会把 Agent 推入试错循环。
8. **Skill 命名必须带域前缀**（`flow-` / `godot-` / `design-` / `feel-` / `ui-` / `web-` / `proto-` / `mp-` / `mcp-`）且 frontmatter 的 `name` 必须等于目录名——Agent 按 `name` 路由。由 verify-skills 机械兜底，规范见 `skills/README.md`。
9. **生成物不手改**：`src/data/vocabulary/index.json`、`design/capability_catalog.json` 只由 `tools/gen/` 产出；改了源头必须重跑生成器，verify 查新鲜度。
10. **门禁分层启用**：Tier 0 全开；Tier 1/2 的启用条件见 gate-tiers note，不提前付维护税。

玩法分包的执行规则下沉在 `src/game/AGENTS.md`：领域目录只导航，运行时内容进入 `src/game/<domain>/<package>/`。`src/game/combat/*.gd` 是错误的大包形态；`src/game/abilities/spirit_quake/`、`src/game/systems/targeting/` 是正确叶子包。`verify-packages` 与 `design/package_policy.json` 机械兜底。

### 编辑本文件的元规则

- 每条规则自包含（不读链接也能执行），理由用链接指向 owning note。
- 本文件超过 150 行时：relocating（下沉子树文件）→ condense → 显式 raise，按此顺序。
- 不用比喻，不写无法机械或人工核验的句子。

## 当前状态（2026-09-17）

初始化：实验目录 + 空白 3D 工作台；八个模块均为待探索。依据：[module-lab-bootstrap](notes/implemented/process/2026-09-17-module-lab-bootstrap.md)。启动入口 `src/levels/lab_hub.tscn`，基础工作台 `src/levels/empty_stage.tscn`。先读 README 获取运行方式。
