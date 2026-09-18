# Note: 可组合实验室的装配与镜头契约

Status: implemented

> 决策批准：**2026-09-18 用户批准统一提案时一并采纳本契约**。Status 为 implemented 表示**决策已采纳**。
>
> **实现状态（2026-09-18 更新）**：本契约规定的适配器与镜头形状均已落地——`ActorAssembly` / `ActorAssemblyConfig` /
> `FlightBundle`（`src/game/actors/swordsman/`、`src/game/abilities/sword_flight/`）与
> `CameraRig` + `CameraRigComponent` + 四模式 Capability（`src/game/systems/camera_rig/`）。
> 逐项验收与最新计数见 [可组合移动实验最终报告](../../../docs/playtest/2026-09-18-composable-movement-labs.md)。
> **已完成**：七场统一迁移与全场回归均已实测通过（全场 `SCRIPT ERROR = 0`，主入口 921/0）。
>
> **补充决策（2026-09-18 第二轮，先决策后实现）**：本文件新增/修订的「组合环绕模式」「未归属 RMB 消费策略」「镜头输入组合测试契约」与「双形态验收」为**本轮已采纳决策**；`src/` 实现与运行证据**尚未落地**。实现必须在同一变更中覆盖 §4 的测试契约与「独立窗口 + 编辑器嵌入 Game 视图」两形态验收，再回来更新本实现状态。先决策后实现（根 `AGENTS.md` 铁律 3）。

## 问题

统一决策 [character-movement-composable-labs](../gameplay/2026-09-18-character-movement-composable-labs.md) 要求七场可组合装配与四模式镜头。现状有三个硬约束：

1. **嵌套 Sheet 不能直接复用父 actor 宿主组件**：`CapabilityManager.sorted_capabilities()` 只轮询直接子节点（`src/core/capability_manager.gd:30-36`）；`Capability.game_object()` 要求父节点是 `CapabilityManager` 且宿主是 `manager.get_parent()`（`src/core/capability.gd:19-23`）；`component()` 只扫宿主直系子（`:35-44`）。嵌套 Sheet 会让能力的 `game_object()` 落在 sheet 根上，阻塞与组件读写都打不到 actor。
2. **写入者不唯一**：镜头跟随逻辑在六场各写一份；若每个模式 Capability 各自写 `Camera3D`，同一帧会产生竞争与顺序不确定。
3. **包规模上限**：叶子包最多 4 个 Capability（`src/game/AGENTS.md` 两级包纪律、`design/package_policy.json`）。四模式 + executor + modifier 若都做成 Capability 会越限。

## 决策

### 1. 局部装配适配器（不新增 core）

- **挂载形状**：可安装包的能力**注册为既有宿主 `CapabilityManager` 的直系子节点**，复用宿主**唯一** Component；不新建 manager、不复制 Component。
- **装配 root**：`src/game/actors/swordsman/` 的 **ActorAssembly** 是装配 root，持有 movement / jump / flight 的依赖与**显式配置**（哪些 cap 启用、装哪些表现）；宿主仍是唯一 actor，基础 host 有**唯一 Component 与唯一 CapabilityManager**。不新建「什么都能塞」的 `game/shared/` 包。
- **可选 / 可组合（不是 helper）**：FlightBundle 是**独立的可选装配包**，自带其 visual 资源与姿态 provider；不得被降级为「检查既有三能力 + 挂一把剑」的 helper。装配单位是「可独立安装/卸载的包」，不是对既有装配的旁路检查。
- **owner / borrow 生命周期**：
  - **owner 原则**：installer **只卸载自身拥有的资源**（按 owner 登记的节点、视觉、材质、信号、输入），不扫描同名节点就认领，不卸载/不停用**借用的 caps**（借用的能力由另行显式声明后才可停用）。
  - **borrow 原则**：包可以借用宿主已有的 Component 与 manager，只读写自己登记的字段；退出时只清自己的字段与 tag，不碰其他能力的意图/速度/输入。
  - **失败 / 卸载**：**不得用 `reset_motion()` 来实现单包卸载**——那会清空无关能力的速度与输入。卸载失败按已登记步骤逆序回滚，宿主回到挂载前状态；`TagRegistry` 清理由能力自身 `_exit_tree` 兜底。
- **原子回滚**：挂载任一子步骤失败（资源加载、节点注册、视觉装配）时，按已登记步骤逆序回滚，宿主保持挂载前状态。
- **调度唯一**：所有能力由宿主唯一 manager tick；物理提交仍只有 actor 根一次 `move_and_slide()`。
- **接口与形状**：适配器是 `actors/swordsman` 内的 ActorAssembly 或所属叶子包内的**普通节点/静态设施**，用公开方法在既有 manager 下增删能力；**不修改 `core/`**。若实现暴露必须改 core 的情况，先另开 owning tech note 评审，不得顺手改。

### 2. CameraRig 唯一提交与输入顺序

- **宿主形状**：`CameraRig`（Node3D）是独立宿主，直接子节点为 `CameraRigComponent`（唯一）与 `CapabilityManager`（唯一）；模式 Capability 为 manager 直系子。
- **单一提交器**：四个模式 Capability 以长期语义命名——`fixed_follow` / `quarter_turn` / `orbit` / `overview`（本文档 A–D 仅作例图简称，**脚本不得用 A/B 阶段字母命名**）——只写 `CameraRigComponent` 的期望 pose/镜头数据；由**唯一提交器**消费并唯一写 `Camera3D`。`near/far` 等全局参数由提交器统一写，模式不得重复写。
  **实现落地形状**：提交器即 `CameraRig` 根节点自身（普通 Node3D，`_physics_process` → `advance()` → 写相机），
  **不是**名为 `CameraExecutor` 的独立子节点；「普通节点、非 Capability」这一约束由实现满足。
- **互斥**：`mode_id` 保证模式互斥（同一时刻只有一个模式持有效）；**需要外部阻塞时才使用已登记 TagRegistry**；切换走 executor 的平滑混合，旧模式交接后不得再写。
- **目标 snapshot 桥接**：CameraRig 对角色**只读目标 snapshot**（位置/速度/着地/飞行等已登记字段），经桥接层注入；Capability 之间不互引、不抓场景节点。
- **同帧 control yaw**：连续旋转时，WASD 屏幕相对移动使用**同一帧一致的控制偏航地面基**：执行顺序固定为「输入采样 → 模式写期望 pose → executor 应用 → actor 物理使用本地面基」，避免一帧反馈滞后。
- **输入顺序**：RMB down 仅在 viewport 未被 UI 消费时捕获；up / 失焦 / 退场必须释放并清累积 delta；**Esc 先退捕获/面板、后返回**；GUI 上滚轮只滚 GUI；键鼠可映射；**鼠标像素位移 `screen_relative` 不再乘 dt，键盘角速度 / 连续平移速度仍乘帧时长**。混合期间 delta 丢弃或显式接管，禁止累积后突然应用。
- **组合环绕模式（`orbit` 的正式定义，2026-09-18 补充）**：不新增第 5 个镜头 Capability。`orbit` 长期语义名不变，正式定义为「组合环绕 / 自由跟随」：同一模式内组合 **WASD 屏幕相对移动**（仍归 actor / 场景输入，地面基由提交器发布）、**Q/E 连续偏航**、**滚轮 / Z / X 缩放**、**RMB 拖动 yaw + pitch（受限俯角）**。其余三模式保持各自单一交互（`quarter_turn` 离散步进、`overview` 平移回中、`fixed_follow` 软区跟随），互不吞并；4 模式 Capability 预算不变。默认入 orbit 与 HUD 广告四组输入属场景编排，见统一决策 note §2。
- **未归属 RMB 消费策略（提交器数据开关，2026-09-18 补充）**：`CameraRigConfig` 新增可配置开关（默认关闭 = 现行行为，镜头包不抢场景按键）：实验场景显式启用后，**非 `orbit` 模式**在 **UI 未占用**的世界区域消费 RMB press / release，但**不进入捕获、不写 `Input.set_mouse_mode`、不写 `look_delta`**——避免未消费的右键事件泄漏给 Godot 编辑器嵌入的 Game 视图。`orbit` 的 RMB press 在 UI 未占用时**必须在同一输入事件内尽早进入捕获**（不得延迟到下一物理帧）；release / Esc / 失焦 / 离树 / 切模式必须释放捕获并恢复进入前的 `mouse_mode`。**UI 上方的右键由 GUI 优先，镜头包不得劫持**；捕获归属仍只属于设过捕获的那个 rig。该策略是 Resource 数据，不是 Capability。

### 3. 数据、词汇与资源边界

- 新增字段/tag（`mode_id`、投影、期望 pose、height/速度 modifier、preview 状态等）**先在 `src/data/vocabulary/` 登记**并重跑索引生成器；能力只读写 Component 共享数据与 TagRegistry。
- **modifier 是数据配置**：高度/速度自适应等由 executor 读取叠加，**不是 Capability**，避免撞 4-cap 上限与调度开销。
- **投影是 Resource 配置**：正交/有限透视及其 `size/fov/keep_aspect` 用 Resource 表达，不与跟随模式做组合爆炸。
- **RMB 归属策略是 Resource 配置**：未归属 RMB 开关与 `enable_*` 输入开关同层（默认关闭），组件不新增字段、不新增 Tag，本补充不触发词汇登记；若实现选择把策略写进 `CameraRigComponent`，必须先登记词汇再改代码。
- **Capability 预算**：镜头包恰好 4 个模式 Capability（`fixed_follow` / `quarter_turn` / `orbit` / `overview`，简称 A–D）+ 1 个普通提交器；executor 与 modifier 不计入 Capability（提交器由 `CameraRig` 根节点兼任，不额外增加节点或 Capability）。超过 4 个模式时先拆包或改数据配置，不得靠豁免堆叠。**组合环绕（`orbit`）不改变该预算**：把 WASD / Q/E / 滚轮 / RMB 组合进 `orbit` 是模式内行为组合，不是第 5 个能力；禁止为输入组合新增 Capability。

### 4. 生命周期与四子集组合验收

- **S3 必须真实实例化四个子集**：`Move` / `Move+Jump` / `Move+Flight` / `all`（Move+Jump+Flight）。每个子集是**真实启动的装配**（ActorAssembly 的显式配置），不是对全装配的检查，也不是 helper 旁路。
- 每次装卸后要求：被启用能力行为正确、未启用能力静默不触发、`flight_active` 等状态一致、`TagRegistry` 无残留阻塞、物理仍一次提交、无脚本错误。
- 卸载顺序：先停本包输入/捕获 → 解绑本包表现 → 移除本包能力并清本包 tag → 释放本包资源；**不得调用 `reset_motion()` 或等价清空动作作为卸载手段**（会清掉无关能力的速度/输入）。`_exit_tree` 兜底不得依赖 `SheetLoader.detach` 调用 `_on_deactivated`（现不调用，`src/core/sheet_loader.gd:29-36`）。
- **镜头输入组合与 RMB 归属测试契约（2026-09-18 补充，实现时必须覆盖）**：
  1. **早期捕获**：`orbit` 下 UI 未占用的 RMB press 在同一输入事件内进入捕获（事件被消费且 `is_captured()` 为真，不依赖下一物理帧）。
  2. **非 orbit fallback**：启用开关的场景在非 `orbit` 模式消费世界区域 RMB press / release，但 `is_captured()` 为假、`Input.get_mouse_mode()` 不变、`look_delta` 不累积。
  3. **不改变 mouse mode**：fallback 路径与 UI 上右键路径都不得调用 `Input.set_mouse_mode`；只有 `orbit` 捕获路径可写，且必须恢复进入前的值。
  4. **组合输入集成**：同一 `orbit` 帧序列内 WASD 位移沿发布后的相机地面基、Q/E 改偏航、滚轮改 size / distance、RMB 拖动同时改 yaw / pitch，四者互不覆盖、无跨帧积压。
  5. **退出恢复**：release / Esc / 失焦 / 离树 / 切换模式五条路径都释放捕获、恢复 `mouse_mode`、清 `look_delta` 与 `drag_active`。
- **双形态验收（2026-09-18 补充）**：以上行为必须在**独立窗口**与**Godot 编辑器嵌入 Game 视图**两种宿主下各验一次；嵌入视图额外确认「UI 上方右键不被镜头包劫持」「世界区域右键不泄漏为编辑器 / Game 视图的上下文操作」。仅无头单测不算完成。

## 备选方案

- **每包自带 CapabilityManager 的嵌套 Sheet**：否决。能力宿主会变成 sheet 根，阻塞与组件读写打不到 actor，见 [sheet-format](2026-08-28-sheet-format.md)。
- **为镜头新增第五个 modifier Capability，或把四模式人为拆成多包**：否决。Capability 可跨包注册到同一 manager；当前四模式同生命周期且未超 4-cap 阈值，无需为 modifier 配置人为拆包。
- **每个模式各自写 Camera3D**：否决。写入者不唯一会每帧竞争，且无法保证同帧 control yaw 一致。
- **直接改 `core/` 放宽 SheetLoader/Manager 语义**：本轮否决。除非实现暴露无法回避的阻塞，否则不改；届时另开 owning tech note。
- **用全局时钟驱动预览**：否决。预览时钟必须局部，不写 `Engine.time_scale`（唯一写入者 `src/core/time_keeper.gd:6-7`）。
- **为输入组合新增第 5 个镜头 Capability（如 `orbit_turn`）**：否决。撞叶子包 4 Capability 上限；输入组合是模式内行为组合，不是新能力。
- **纯数据 preset 表达组合（`follow_preset` / `enable_*` / `mode_choices`）**：否决。`follow_preset` 只被 `fixed_follow` 解释且只影响焦点策略，`enable_*` 只能整体开关，`mode_choices` 只能选整模式。
- **非 `orbit` 模式默认全局吞掉 RMB**：否决。违反「镜头包默认不抢场景按键」；改为默认关闭 + 实验场景显式启用。
- **fallback 路径也进入捕获或直接改 `mouse_mode`**：否决。非 orbit 无拖动需求，捕获会锁光标并泄漏全局状态。

## 后果

- **约束已生效**：S0–S3 的镜头与装配实现必须满足本契约；[统一决策](../gameplay/2026-09-18-character-movement-composable-labs.md) 的 S0/S1 验收按此检查。
- **实现已落地**：`src/game/actors/swordsman/` 的 ActorAssembly / ActorAssemblyConfig、`src/game/abilities/sword_flight/` 的
  FlightBundle、`src/game/systems/camera_rig/` 的 CameraRig + CameraRigComponent + 四模式 Capability 均已实现并进测试入口；
  `core/` **未改动**（`SheetLoader.detach` 不调 `_on_deactivated` 的现状事实未变，本契约仍以「不依赖该路径」规避）。
- **已由测试覆盖（运行证据）**：适配器幂等 / 回滚 / 四子集真实性 / owner-borrow 卸载边界由
  `src/game/actors/swordsman/test_actor_assembly.gd`（142 项）与 `src/game/abilities/sword_flight/test_flight_bundle.gd`（83 项）覆盖；
  单 executor 写次数、模式互斥与切换连续性由 `src/game/systems/camera_rig/test_camera_rig_executor.gd` 等 5 套（128 项）覆盖。
  上述数字为主入口 `tests/test_runner.tscn` 实测；七场迁移后的全场回归亦已实测（见最终报告 §7）。
  **仍有限定**：同帧 control yaw 的实机帧序未单独验证；连续环绕下的操作舒适度属人工试玩项。
- **已知限制**：嵌套 Sheet 的宿主边界与 `detach` 不清 `_on_deactivated` 是现状事实；本契约以「不依赖该路径」规避，不修改 core。
- **补充决策已记录、实现未落地（2026-09-18 第二轮）**：§2 / §3 / §4 的补充内容为已采纳决策；`src/game/systems/camera_rig/` 尚未实现，`docs/playtest/` 尚未出证据。实现变更必须在同一变更中覆盖 §4 的测试契约与「独立窗口 + 编辑器嵌入 Game 视图」双形态验收，并更新上文实现状态；不得只改代码、也不得只改文档。
