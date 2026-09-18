# 实验：角色移动与庭院呈现

- 日期：2026-09-18。
- 场景：`res://levels/experiments/character_movement/movement_lab_hub.tscn`（当前入口，子实验目录）；子实验场景 `camera_lab.tscn`（镜头实验室）、`motion_stage.tscn`（人物动作工作台）、`movement_garden.tscn`（小场景回归）、`mountain_realm.tscn`（群山宗门组合验收）。
- 观察目标（群山宗门）：三个移动能力在高低差与空中场景中的手感与可读性——屏幕相对移动、独立跳跃、御剑飞行、碰撞与镜头；走路动画与最终美术仍待试玩评价。
- 操作：WASD / 方向键移动，Space 跳跃 / 上升，Ctrl 下降，F 开关御剑，滚轮缩放，R 复位（含关闭飞行），Esc 返回。
- 美术：群山山体 / 宗门建筑与御剑由 Blender 程序建模（源文件与台账见 [美术目录](../art/mountain_realm/)）；修士角色与庭院沿用上一轮 movement_garden 资产。
- 小场景回归：movement_garden.tscn 保留可直接运行，只验证平面移动与旧庭院；上面「观察目标」以外的旧记录属于该回归场景。
- 使用者试玩反馈：待记录，不以技术验证代替审美与手感评价。
- 边界（群山场景）：没有攻击、木桩、命中结算或战斗 UI；角色仍是静态模型随方向转身，没有走路或骨骼动画。碰撞覆盖五峰碰撞壳（0→台顶侧壁）、75 个布局盒（地形 / 台阶 / 建筑 / 屋顶 / 近地道具）与 bounds 四墙 + 天花；远山与云为装饰无碰撞。剑法与战斗组织需要单独讨论。
- 小场景回归边界（movement_garden）：只覆盖场地边界、两个障碍代理与庭院视觉；灯、竹与亭仍是装饰。

角色移动保持 exploring，剑法恢复 planned。此前近身范围练剑场已被否决并撤回，不能作为后续设计的默认基线。

## 本轮结论（2026-09-18）

- 已通过：三能力装配与调度顺序、屏幕相对移动 / 方向键等价 / 斜向限速、起跳-落地-按住不连跳-空中不补跳、御剑开关 / 升降 / 悬停 / 恢复重力、飞行阻塞跳跃、能力逐个移除后其余仍工作、R 复位与阻塞清账、失焦保留悬停、bounds 边界 / 天花 / 掉出回收、两处山顶平台真实输入飞行降落、撞山 / 撞楼 / 低台阶真实站立。
- 已知限制：跳跃顶点约 1.0 m、单级台阶 0.75 m 需起跳（验证数据，非手感结论）；相机为固定俯视跟随，无避让；AI 程序建模不等于成品美术；手感与审美待使用者试玩。
- 证据：`docs/playtest/2026-09-18-mountain-traversal.md`（五问分类）；小场景旧证据见[运行验收](../playtest/2026-09-18-character-movement.md)。
- 本轮群山宗门探索的接口与装配记录见 [mountain-scene-plan.md](mountain-scene-plan.md)（历史前置方案）；三能力接口契约见 [traversal-contract.md](traversal-contract.md)，布局契约见 [layout-contract.md](../art/mountain_realm/layout-contract.md)。

## 子实验目录（2026-09-18）

依据 [character-movement-subexperiments](../../notes/proposed/gameplay/2026-09-18-character-movement-subexperiments.md)（proposed，使用者已确认，允许实现；转 implemented 由父代理在阶段提交时处理）。

- 顶层入口：顶层目录的「角色移动」现指向 `res://levels/experiments/character_movement/movement_lab_hub.tscn`；hub 可独立启动（`./run.command res://levels/experiments/character_movement/movement_lab_hub.tscn`），也可从顶层实验目录进入。
- 数据真相源：`res://data/content/character_movement_subexperiments.json`。七项子实验按 note 顺序登记：镜头实验室、人物动作工作台、地形接触训练场、御剑飞行训练场、状态切换压力场、移动庭院、群山宗门。
- 状态规则：未落地条目 `scene` 为空、状态 `planned`，界面禁用「进入子实验」并如实显示「尚未落地」。第一阶段收口后有四条真实入口：镜头实验室、人物动作工作台、移动庭院、群山宗门（计数 4 / 7）；地形接触训练场、御剑飞行训练场、状态切换压力场仍为 `planned`。数据读取、校验与按钮生成都在 hub 脚本内，未改动 `core/`，也未建立通用菜单框架。
- 返回路径（2026-09-18 第一阶段收口后统一）：四个已落地子场景的 Esc 与返回按钮都回到 `movement_lab_hub.tscn`；hub 的 Esc 与「返回实验目录」再回到顶层 `lab_hub.tscn`。直接启动任一子场景后，一条 Esc 即回到移动子实验目录，形成「顶层 → 移动目录 → 子场景」的两级返回链。
- 边界：hub 只做清单读取与入口编排，不写角色 `velocity`/移动意图/能力内部状态；三项 Capability 与角色根唯一 `move_and_slide()` 提交点不变。
- 集成验证（CLI 档，本会话 godot-ai 无活动编辑会话）：`movement_hub_playtest.gd` 68 项全通过（4/7 计数、四个入口、两级返回链、返回按钮文案读回）；数据契约套件 `tests/test_movement_lab_hub.gd` 49 项通过；`character_movement_playtest.gd` 39 项、`mountain_traversal_playtest.gd` 220 项全通过。最终计数以 [docs/playtest/2026-09-18-character-movement-subexperiments.md](../playtest/2026-09-18-character-movement-subexperiments.md) 的「精确计数」表为准（并行子报告为其自身阶段快照，可能不同）；原始日志不入 Git，保存在 `~/.cache/game-xiuxian-lab/character-movement-subexperiments/`。