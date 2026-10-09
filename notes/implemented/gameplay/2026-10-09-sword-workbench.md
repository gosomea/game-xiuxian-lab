# Note: 剑法工作台与悬浮本命剑

Status: implemented

## 问题

剑法战斗模块（`sword_combat`）一直是 planned，没有场景。使用者要求按仓库规范做出第一个剑术场景，比较三种出剑方式：剑气、飞剑出击、剑阵万箭齐发；鼠标指向出剑，目标为静止木桩，只要命中反馈，不要血量与胜负；剑悬浮在人物身边而不是握在手中。一次性原型（已删除）验证过三招放在一起成立，但它绕开了修士、能力与镜头，不能作为正式实现。

现有约束：骨架没有手指骨，握剑手型做不出来；现役飞剑模型长 1.80 m、原点在剑身顶面，是御剑站立平台；渲染器为 Compatibility，官方粒子拖尾不可用；能力之间只能通过 Component 字段与 TagRegistry 通信；叶子包最多 4 个 Capability。

## 决策

依据使用者 2026-10-09 授权实施。新增独立场景 `src/levels/experiments/sword_combat/sword_workbench.tscn`，由顶层实验目录进入，`sword_combat` 登记为 exploring。场景使用完整 `Swordsman`（移动、跳跃、御剑照旧）和共享 CameraRig；平地灰盒上放五根木桩。

**包划分。** 三招各是一个叶子包，玩家可独立感知、生命周期独立、可整体删除：`game/abilities/sword_qi/`（`SwordQi`）、`game/abilities/flying_sword_strike/`（`FlyingSwordStrike`）、`game/abilities/sword_array/`（`SwordArray`）。三招共用的输入与表现契约没有自然所有者（任何一招删除，其余两招仍要读它），放在 `game/shared/sword_cast/`：`SwordCastComponent`（输入、当前招式、面向请求、出招姿势、本命剑位置与各招参数）、`SwordCastBundle`（按 owner 原则把组件、能力与表现装到既有宿主上）、`SwordCastPresentation`（悬浮本命剑与出招姿势）。木桩是 `game/actors/training_dummy/`，`SwordTargetComponent` 记录命中，分组 `sword_target` 供查询。

**模拟在能力内部。** 剑气与剑阵的投射物是能力持有的数据，在 `_tick_active` 中推进，并把渲染所需的位置与朝向写入 `SwordCastComponent` 的数组字段；各包的视图节点只读这些字段并绘制。能力不在场景树里生成节点，因此无头测试可以用 `CapabilityManager.tick()` 逐帧推进。命中判定用投射物本帧位移线段到木桩竖直圆柱的距离，不依赖物理帧与碰撞层；命中时调用目标组件的数据存取方法登记一次。

**悬浮本命剑。** 本命剑平时悬在人物右肩后上方，随朝向转动并轻微浮动；飞剑出击时由 `FlyingSwordStrike` 沿弧线把它送向指向点，到达或命中后飞回。剑在外期间该能力登记 `sword_away_block`，`SwordFlight` 读到它不起飞；御剑期间（`sword_flight_block`）不能出击。剑气与剑阵在御剑时也能使用。

**出招姿势。** 由 `SwordCastPresentation` 在骨架上挂一个 `SkeletonModifier3D`，按组件里的姿势权重把右上臂与前臂转向出招方向：剑气与飞剑向前平指，剑阵蓄势时斜上举。出招时能力写面向请求，场景把人物转向指向点。

**新剑资产。** `tools/art/generate_bound_sword_20261009.py` 用 Blender 程序生成，沿用现役飞剑的钢色剑身与青铜剑格配色：本命剑长 1.0 m、原点在剑格中心、局部 −Z 为剑尖，单网格三材质；剑阵用剑是同造型的单材质简化版，用 MultiMesh 一次绘制。现役 `flying_sword.glb` 继续只用于御剑，不改动。

**操作。** 左键出剑（剑阵为按住蓄势、松开齐射），`C` 或 HUD 按钮循环切换招式，鼠标指向地面决定方向；右键与 Q/E 仍归镜头；移动、疾跑、跳跃、御剑沿用共享输入，键位由角色移动实验的 `MovementLabInput` 解码（本模块在清单中依赖 `character_movement`）；R 重置，Esc 返回顶层目录。指向点按最近一次鼠标移动事件的视口坐标，每物理帧随镜头重新投影到人物所在高度的地面。

**命中反馈。** 木桩闪白并晃动，倾角封顶，连中不会被推倒。剑气与飞剑命中时场景经 `TimeKeeper` 请求约 60 ms 顿帧，两次之间至少隔 0.22 s；剑阵一轮可连中十几下，逐下顿帧实测让齐射损失约四分之一的游戏时间、变成持续卡顿，因此剑阵命中不触发顿帧。镜头抖动需要改共享镜头包，本轮不做。

## 备选方案

- **剑握在右手。** 没有手指骨，手掌无法握合，挂在 `RightHand` 骨上会穿模或悬空；使用者选择悬浮。
- **直接用现役飞剑模型。** 1.8 m 长、原点在站立面、十个网格分开，手边悬浮与几十把齐射都不合适；保留它给御剑。
- **AI 生成剑模型。** 面数与贴图远超需要，还要重拓扑，造型不如脚本可控，也难复现。
- **投射物生成独立节点并用 Area3D 碰撞。** 依赖物理帧与碰撞层，无头测试只能等真实帧；几十把剑各配 Area3D 也更重。选择能力内数据加几何判定。
- **Blender 关键帧出招动画加 AnimationTree 上半身层。** 出招方向随鼠标变化，预制关键帧只能对正前方；还需把现有表现层从 AnimationPlayer 改为 AnimationTree。本轮改用运行时骨骼修饰器；以后需要更丰富的手势时仍可补关键帧。
- **三招放进一个包。** 三招可以单独删除、单独调整，合并会违反叶子包判定；共享部分进 `shared/sword_cast/`。
- **用 `sword_flight_block` 同时表示剑在外。** 语义不同：御剑阻塞的是地面移动，剑在外阻塞的是御剑本身；新登记 `sword_away_block`。

## 后果

- 顶层目录新增可进入的「剑法战斗」，状态 exploring；其余 planned 模块不变。旧移动窗口验收脚本里「剑法无运行入口」的断言同步改为「剑法可进入」。
- `SwordFlight` 增加一个只读阻塞检查；其余移动、镜头和人物资产不变。
- 三招参数在 `SwordCastComponent` 上，可在场景 HUD 观察；数值是第一轮手感起点，不是平衡结论。
- 俯视 14 m 正交视野下，本命剑与剑阵用剑都以 1.4 倍绘制；命中半径仍取组件参数。
- 未做：镜头抖动、受击火花粒子、飞剑拖尾、出招关键帧动画、木桩血量。运行验收与已知边界见 [运行记录](../../../docs/playtest/2026-10-09-sword-workbench/report.md)，资产见 [本命剑台账](../../../docs/art/bound_sword_20261009/asset_ledger.md)。
