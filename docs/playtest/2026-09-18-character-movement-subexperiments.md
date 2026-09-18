# 角色移动子实验目录验收（2026-09-18）

场景：`res://levels/experiments/character_movement/movement_lab_hub.tscn`（角色移动顶层入口 → 子实验目录）。
决策依据：[character-movement-subexperiments](../../notes/proposed/gameplay/2026-09-18-character-movement-subexperiments.md)（proposed，使用者已确认，允许实现）。
数据真相源：`res://data/content/character_movement_subexperiments.json`。
验收档位：**CLI 档**（`godot --headless` + 真实场景树 + 真实键盘事件 + 窗口模式截图）。
编辑器桥状态：godot-ai MCP（v3.4.7，127.0.0.1:8000/9500）在本会话多次查询均为
`PLUGIN_DISCONNECTED / sessions count=0`——运行中的 Godot 编辑器未连接插件，因此未走
`project_run` / `editor_screenshot`，全部证据来自 CLI；MCP 不是本改动依赖。

## 范围（第一阶段收口）

角色移动子实验目录 + 数据真相源；七项子实验中的四项有真实入口（4 / 7）；四个已落地子场景的
Esc / 返回按钮统一回到子实验目录；原始测试日志不入 Git。

## 五问分类

| 项 | 1 已实现 | 2 已运行通过（命令 + 结果） | 3 静态检查 | 4 未验证 | 5 外部阻塞 |
|---|---|---|---|---|---|
| 子实验清单七项与状态 |  | ✔ `test_movement_lab_hub.gd` 49/49 | ✔ JSON 与 note 提案逐项对齐 |  |  |
| hub 显示 4 / 7 可进入 |  | ✔ `movement_hub_playtest.gd` 68 PASS / 0 FAIL（计数 4 / 7） |  |  |  |
| 四个真实入口可进入 |  | ✔ camera_lab / motion_stage / movement_garden / mountain_realm 逐项真实进入 | ✔ `can_open` 只认 status + 真实可加载场景 |  |  |
| 三个 planned 条目禁用 |  | ✔ 逐项点击详情如实、按钮禁用、不切换场景 |  |  |  |
| 键盘焦点可用 |  | ✔ 初始焦点 = 镜头实验室；方向键移动焦点；回车选择 → 进入子实验 |  |  |  |
| 小窗 960×640 布局 |  | ✔ 7 项仍可见、计数 4 / 7 仍如实 |  |  |  |
| 顶层 hub → movement hub |  | ✔ `Module_character_movement` + `LaunchButton` 真实进入 MovementLabHub | ✔ `experiments.json` 入口为 hub 路径 |  |  |
| 子场景 Esc 回 MovementLabHub |  | ✔ 四个入口逐项真实进入后 Esc 全部回 MovementLabHub | ✔ 四个场景脚本返回常量指向本目录 |  |  |
| MovementLabHub Esc 回 LabHub |  | ✔ hub 的 Esc 与返回按钮都回到顶层 LabHub |  |  |  |
| 直接启动子场景仍可返回嵌套目录 |  | ✔ `character_movement_playtest.gd`（39 PASS）与群山 hub 批次直接启动后 Esc 回 MovementLabHub |  |  |  |
| hub 不改 core / 不写角色状态 |  |  | ✔ 无 Capability 引用、无 velocity / move_and_slide |  |  |
| 门禁 |  | ✔ 12 项 Tier 0 全通过 + 负向控制 27/27 |  |  |  |
| 运行时单元套件 |  | ✔ **178 通过 / 0 失败**（10 套件） |  |  |  |
| 既有回归 |  | ✔ lab 13 PASS / 0 FAIL；庭院 39 PASS / 0 FAIL；群山 **220 PASS / 0 FAIL** |  |  |  |
| 返回层级文案一致 |  | ✔ 庭院 / 群山读回按钮文本 = `返回子实验目录`、控制提示同；hub 按钮 = `返回实验目录` |  |  |  |
| 窗口模式截图 |  | ✔ 本 hub 窗口模式 `--capture-prefix` 全通过，6 张入仓；motion_stage owner 重拍 7 张 | ✔ 人工读图核对 4 / 7 与禁用态 |  |  |
| 原始日志不进 Git |  | ✔ 仓内无 `-checks.txt`，完整输出在本机 `~/.cache/game-xiuxian-lab/character-movement-subexperiments/` | ✔ 仅 md + png 入仓 |  |  |

## 精确计数（本次集成运行）

**快照声明**：本表是本次集成收口时的最终计数，为唯一权威快照。并行代理的子报告（`2026-09-18-camera-lab.md`、
`2026-09-18-motion-stage.md`）在各自落地阶段记录的数字与命令批次可能与本表不同（例如其 playtest 计数与
截图集合）；两者不一致时**以本表为准**。差异举例：`camera_lab_playtest.gd` / `motion_stage_playtest.gd`
在本表为 89 / 154，子报告若记录其他数字属其自身批次的快照。

| 检查 | 命令 | 结果 |
|---|---|---|
| Tier 0 门禁 + 负向控制 | `python3 tools/verify/run_all.py` | 通过（12 项门禁 + 负向控制 27/27） |
| 单元套件 | `godot --headless --path src tests/test_runner.tscn` | **178 通过 / 0 失败**（含 `test_movement_lab_hub.gd` 49） |
| hub 运行验收 | `--script res://tests/movement_hub_playtest.gd` | **68 PASS / 0 FAIL** |
| 顶层目录回归 | `--script res://tests/lab_playtest.gd` | 13 PASS / 0 FAIL |
| 庭院回归 | `--script res://tests/character_movement_playtest.gd` | 39 PASS / 0 FAIL |
| 群山全量回归 | `--script res://tests/mountain_traversal_playtest.gd` | **220 PASS / 0 FAIL** |
| 群山返回批次（最小） | `--script ... -- --batch=hub` | 10 PASS / 0 FAIL |
| notes 格式 / diff 卫生 | `python3 tools/verify/verify_notes_format.py`；`git diff --check` | 22 个目标合规；无空白错误 |
| 窗口模式截图 | `--path src --script ...movement_hub_playtest.gd -- --capture-prefix=...` | 0 FAIL，6 张截图 |
| 并行场景交叉检查 | `--script res://tests/camera_lab_playtest.gd` / `motion_stage_playtest.gd` | camera_lab **89 PASS / 0 FAIL**；motion_stage **154 PASS / 0 FAIL**（owner 修复返回文案后的完整重跑；7 张截图重拍） |

原始输出保存在本机 `~/.cache/game-xiuxian-lab/character-movement-subexperiments/`
（`gates.log` / `tests.log` / `movement-hub.log` / `lab-hub.log` / `garden.log` /
`mountain.log` / `movement-hub-capture.log` / `camera-lab-peer.log` / `motion-stage-peer.log`），
不入 Git；本文件只保留精简结论与截图。

## 返回路径契约（收口后）

- 顶层 `LabHub` → 「角色移动」→ `MovementLabHub` → 四个子场景之一。
- 任一子场景 Esc / 返回按钮 → `MovementLabHub`（直接启动子场景同样如此，不回到顶层）；按钮文本为
  「返回子实验目录」，控制提示同样写明「Esc 返回子实验目录」，由运行断言读回文本防漂移。
- `motion_stage.gd` 的按钮文本与提示已由 owner 统一为「返回子实验目录」（与 `MovementLabHub` 目标一致）；
  原「待统一」条目已失效并删除。`camera_lab.gd` 同为「返回子实验目录」。
- `MovementLabHub` Esc / 返回按钮 → 顶层 `LabHub`。
- 未落地条目（`planned`）不提供入口，界面显示「待探索 · 未落地」与「场景尚未搭建」禁用按钮。

## 视觉档（窗口模式截图）

| 截图 | 内容 |
|---|---|
| `...-movement-hub-1280x800.png` | 1280×800：七项、计数 4 / 7、镜头实验室选中、四个可进入条目状态为「探索中」 |
| `...-movement-hub-960x640.png` | 960×600 视口（最小窗口）下七项仍完整可见，详情与按钮可用 |
| `...-movement-hub-entry-camera_lab.png` | 从 hub 真实进入镜头实验室 |
| `...-movement-hub-entry-motion_stage.png` | 从 hub 真实进入人物动作工作台 |
| `...-movement-hub-entry-movement_garden.png` | 从 hub 真实进入移动庭院 |
| `...-movement-hub-entry-mountain_realm.png` | 从 hub 真实进入群山宗门 |

人工读图确认：七个条目在两种窗口尺寸下完整显示（无裁切、无重叠）；四个已落地条目显示「探索中」，
三个未落地条目显示「待探索 · 未落地」，详情面板对 planned 显示「入口：尚未落地（scene 为空，状态 待探索）」
且按钮为禁用态「场景尚未搭建」。截图由真实键盘 / 焦点驱动，非摆拍。

## 已知边界

- **camera_lab / motion_stage 的玩法细节不在本次验收范围**：本次只确认它们可作为子实验条目被进入、
  且返回路径正确（交叉运行其自带 playtest 作为稳定性证据：89 / 154 全通过）；其自身的镜头策略与
  动作表现验收由对应 owner 的报告负责。文件在集成运行前已停止写入，集成期间未再变化。
- **子报告快照差异**：并行子报告记录的是其各自阶段的数字与状态，本报告的「精确计数」表为最终集成快照；
  两者不一致时以本表为准（见上）。
- **未提交**：按任务约定不 commit / push，改动留给父代理审计后按阶段提交。
