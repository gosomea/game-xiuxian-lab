# 群山宗门场景装配方案（首轮，只读）

日期：2026-09-18。状态：**已实施**（两份契约已审计通过并落盘）。实施结果与验证分工见本文末节；
运行验收由 traversal_qa 独占，本文只记录装配接口与决策。
依据：[mountain-traversal](../../notes/implemented/gameplay/2026-09-18-mountain-traversal.md)。
本轮不改 `src/`、不运行 Godot，只审阅新场景需要的输入 / 镜头 / HUD / 布局接口。

## 边界

- 我的写集：`src/levels/experiments/character_movement/mountain_realm.gd` / `mountain_realm.tscn`、
  必要的旧 `movement_garden.gd` 输入 API 适配（不回退行为）、`src/data/content/experiments.json`、
  README / AGENTS 当前状态、本文与 `docs/experiments/` 实验记录。
- 不碰：角色 / 能力 / 美术模型、`core/`、`project.godot`、`src/tests/`（除下方 G4 被明确指派）、他人未提交改动。
- 不 commit / push；不读旧修仙项目；`character_movement` 保持 exploring，地图 / 剑法仍 planned；本场景不新增玩法。

## 现状盘点（只读）

- 角色已有公共装配 API：`Swordsman.set_move_input / set_camera_ground_basis / set_aim_direction / reset_motion`；
  数据在 `SwordsmanMotionComponent`，当前只装 `SwordsmanMovement` 一个能力。
- 现有 `movement_garden.gd` 直接写组件字段（未走 `Swordsman` API），把主按键表 `_pressed`、相机、
  边界与障碍代理全放在场景脚本里。可作编排范式参考，但边界收口在场地内、相机 Y 钉在 0，
  不适合直接复用到大场景。
- HUD 用代码搭建：`CanvasLayer > Control(full rect, lab_theme) > MarginContainer > VBox`，
  顶栏标题 + 底栏按键 / 重置 / 返回；按钮 `focus_mode = FOCUS_NONE`，移动键始终抵达 `_unhandled_input`。
  `lab_theme.tres` 提供 `MutedLabel / AccentLabel / PrimaryButton / ModuleSelected` 变体。
- `verify-scenes` 要求正式关卡根脚本与场景同名（`mountain_realm.gd` 满足），且 `ext_resource` 无悬空引用：
  GLB 与 JSON 要先于场景就位，否则解析即失败（现有场景统一 `preload` 关键依赖）。
- `verify-vocabulary` 只看 `&"字面量"`：新组件字段 / 新词汇必须先登记再在 `mountain_realm.gd` 里引用。
- `LabCatalog._valid_scene()` 在运行时 `load()` 场景：`experiments.json` 指向新场景前，新场景必须能真实加载。

## 需要契约定义的接口

### 输入（需要 traversal-contract 给字段名与写者）

1. 分工：场景把物理键转成意图量，能力只读意图不读键。建议场景统一 `_unhandled_input` 维护 `_pressed`（WASD 与方向键映射到同一个 Vector2），Space / Ctrl / F 的边沿当帧写意图字段。
2. 需要字段（名称待冻结）：跳跃边沿、升降轴（0/1）、御剑切换。升降建议用持续量，跳跃与切剑建议边沿 + 可清空的派生态。
3. 飞行水平输入归属：建议 `move_input` 仍是唯一水平输入字段，飞行能力读取它；TagRegistry 阻塞只决定谁提交物理，不再造第二份输入。
4. 状态回读（只读，供 HUD 与复位）：着地、御剑中（或等价 `motion_state`）。HUD 的「步行 / 空中 / 御剑」直接读这些字段组合，不新增第二份真源。
5. 复位契约：R 要「位置 + 速度 + 飞行状态」全清。场景只负责传送与清输入；能力状态清空要有一次可调用入口（建议扩充 `Swordsman.reset_motion()` 或等价组件清空）。
6. 失焦（已按主代理审计修正）：场景 `_clear_pressed()` 清水平 / 升降 / 跳跃边沿 / F 边沿共四种输入，**但已开启的御剑保持悬停**，不自动关飞、不坠落；只有 R 关闭飞行并清账（`reset_motion()`）。

### 镜头（场景自持，但需要布局给两个数）

- 保留正交固定俯视 + 刚性偏移，扩展为 XYZ 跟随：目标为角色位置，Y 不夹到 0；滚轮缩放夹在布局能承受的范围内。
- 需要布局给 `bounds`（水平边界，防飞行 / 镜头越界）与最高峰高度（相机 Y 上限与 `far`；现 `far = 120`，180×160 场景需 ≥ 200）。
- 不新增镜头碰撞避让：固定 35–45° 俯角 + 抬升跟随即可保证高峰可见。
- 掉落回收：需要最低安全高度或 `fall_y` 阈值，越界传送回 spawn 并清状态。

### HUD（场景自持）

- 沿用现有骨架与主题变体，新增一行状态（步行 / 空中 / 御剑）与一行按键说明（WASD + 方向键、Space 跳 / 升、Ctrl 降、F 御剑、R 复位、Esc 返回）。
- 按键说明开 `autowrap`；1280×800 与 960×640 下不挡中心。状态只读回读字段；不做战斗 UI 与能力面板。
- 本轮不抽公共 HUD 组件：庭院作为小场景回归保持不动，避免与他人写集冲突；后续确有同步需求再抽。

### 布局与碰撞（需要 layout-contract 冻结 schema）

- 建议运行路径 `res://levels/experiments/character_movement/mountain_realm_layout.json`（场景专属、与场景同目录、同前缀）；文档契约在 `docs/art/mountain_realm/layout-contract.md`。
- 场景只消费不生成布局；碰撞由 JSON 代理建成 `StaticBody3D + BoxShape3D / CylinderShape3D`，世界层统一 layer 1 / mask 1；GLB 只给视觉、不含碰撞。
- 需要字段：`schema_version`、`bounds`、`spawn`（含朝向可选）、`landing_points[]`（id + 位置 + 可站立范围，至少起点庭院 / 主峰 / 侧峰）、`colliders[]`（id + 形状 + center + size + 可选 yaw）、`fall_y` 或等价阈值、最高峰高度。
- 坐标约定必须写明：世界绝对坐标、米、Y-up、GLB 与 JSON 同原点，避免碰撞代理与视觉错位。峰顶 12/24/36 米与「能站上去」由布局自查，我只按数据装配与验证落地。

## 需求缺口（阻塞开工）

- G1 能力契约未出：跳跃 / 飞行字段名、写者、升降边界、状态回读、复位入口未定 → 输入层与 HUD 无法写。
- G2 布局契约未出：JSON 运行路径与 schema 未定 → 加载器与碰撞装配无法写；`preload` 策略要求 GLB / JSON 先存在。
- G3 相机参数未定：没有边界与峰高，相机 Y 上限、`far`、缩放范围只能猜。
- G4 现有测试硬编码冲突：`src/tests/character_movement_playtest.gd` 的 `_run_hub_gate()` 断言 `character_movement.scene == movement_garden.tscn`；切换 `experiments.json` 入口会直接让它失败。已读[独立验收矩阵](traversal-acceptance-plan.md)：其交付物含「必要更新 character_movement_playtest.gd 入口指针断言」，故由验收代理同变更更新，我不碰 `src/tests/`。
- G5 F 语义：若御剑在能力内部闩锁，R 与失焦无法从场景侧真正关闭飞行 → 契约必须选「字段派生态 + 可清空」。
- G6 互斥判定点：单帧 F + Space、起跳后开飞、空中关飞的结果需契约写明，我据此写集成断言。
- G7 GLB 落点：我按 `mountain_realm.glb` 预载；美术改名需提前同步。
- G8 HUD 状态文本映射：验收计划 C8 归「场景代理 + contract」。我需要契约确定三个能力的状态字段，才能给出「步行 / 空中 / 御剑」的确定映射；若跳跃与御剑共用 `is_on_floor` 语义，必须规定优先级（御剑 > 跳跃 > 步行）。

## 我的装配顺序（契约冻结后）

1. 审阅并冻结两份契约，回一份接口确认（更新本文）；字段名、JSON 路径、schema 一旦冻结才写代码。
2. 等美术 GLB + 布局 JSON 就位；只读校验尺寸、spawn 可达、平台高度与代理数量，不改美术文件。
3. `mountain_realm.tscn` 最小骨架：WorldEnvironment + Sun + Camera3D（`unique_name_in_owner`），根脚本与场景同名。
4. `mountain_realm.gd`：加载并校验 JSON → 生成碰撞代理 → 实例化角色到 spawn；先跑 headless 解析 / 导入检查，窗口与真实物理验收留给验收代理。
5. 输入层：WASD / 方向键 → `set_move_input`；Space / Ctrl / F 写意图；R 全复位；Esc 返回；失焦清全部输入。优先用 `Swordsman` 公共 API，不直写组件字段。
6. 镜头：XYZ 跟随 + 边界 / 峰高处理 + 滚轮缩放 + `far` 调整。
7. HUD：沿用骨架 + 状态行 + 按键行 + 返回 / 复位。
8. 掉落回收与自动回 spawn。
9. `experiments.json` 入口切换 + `docs/experiments/` 记录 + README / AGENTS 当前状态同步；`movement_garden` 保留直接运行作回归。
10. 与验收代理对齐集成测试清单（入口门禁、按键映射、跳 / 飞 / 落、R / Esc / 失焦、两种窗口尺寸）。

## 不做

- 不改角色 / 能力 / 美术模型；不新增 Capability；不碰 `core/`、`project.godot`、`src/tests/`（除 G4 被指派）。
- 不把 `world_map` 或 `character_movement` 改成 ready；不宣称地图系统完成。
- 不回滚或整理他人未提交改动；不 commit / push。

## 实施结果（2026-09-18）

落盘产物：

| 文件 | 说明 |
|---|---|
| `src/levels/experiments/character_movement/mountain_realm.gd` | 场景装配：布局读取、碰撞、边界、相机、HUD、输入编排（不在 src/tests 内） |
| `src/levels/experiments/character_movement/mountain_realm.tscn` | 根节点 `MountainRealm` + WorldEnvironment + Sun + 正交 Camera3D；不引用任何 GLB |
| `src/data/content/experiments.json` | `character_movement.scene` 指向 `mountain_realm.tscn`（状态仍 exploring） |
| `src/levels/experiments/character_movement/movement_garden.gd` | 适配为 `Swordsman` 公共 API（set_move_input / set_camera_ground_basis / set_aim_direction / clear_input / reset_motion），行为不回退 |

装配关键约定：

- 美术 GLB 全部 **preload 硬依赖**（山体 / 碰撞壳 / 御剑）：资源缺失即脚本加载失败，不静默降级、不伪造入口；`.tscn` 不引用 GLB，因此场景解析不被美术排期阻塞。
- 布局坐标只在运行时从 `mountain_realm_layout.json` 读取，不硬编码早期文档数值（`summit_sect.center` 按 JSON 的 `[4,-41]/22×9` 消费）。
- 布局字段按 schema 原样解析：`boxes[].center` 是 `[x,y,z]` 三元组；`landing_points[].center` 与 `collision.mountains[].base.center` 是 `[x,z]` 二元组，y 由 `top_y` 单独给出——两种读取器分开，不改 schema。
- 碰撞节点路径稳定可测：山体壳为 `World/ShellCollision/<碰撞壳节点名>`（`EastRidgeCol`…`FrontPeakCol` 共 5 个），盒体为 `World/BoxCollision/<JSON name>`（75 个实体盒，节点名 = JSON name），边界为 `World/Boundaries/{West,East,North,South,Ceiling}`（按 bounds 5 面实体约束）。
- 山体壳只提取 `MeshInstance3D` 的 `create_trimesh_shape()` 到同名 `StaticBody3D`，源节点 `visible=false` 后 `queue_free()`，不渲染显示。
- 御剑视觉由场景实例化为角色 `Visual/FlyingSword`，经 `actor.bind_flight_visual()` 注入，可见性由 actor 按 `flight_active` 统一同步；场景不做第二套状态。
- 相机固定俯视跟随 XYZ，滚轮 14→240（可看全群山），`far=600`。
- 失焦清水平 / 升降 / 跳跃边沿 / F 边沿四种输入，已开启御剑保持悬停；R 走 `reset_motion()` 关闭飞行并清账；掉落仅以 `fall_out_y=-6` 回收至 spawn。

静态自检（未运行 Godot，执行权归 traversal_qa）：函数清单 29/29 齐全、括号与大括号配平、无空格缩进混用、无未登记 `&"…"` 词汇字面量。三只 GLB 已解析确认节点名与 `layout-contract` 一致（壳 5 节点 1520 三角形、御剑 10 节点 486 三角形）。
