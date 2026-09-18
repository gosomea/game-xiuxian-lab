# 镜头包（camera_rig）交付与验收（2026-09-18）

只读事实 + 已运行证据。实现范围：四模式镜头包 + 两个真实消费者（镜头实验室 / 移动庭院）。
本文件不修改任何全局 notes；`AGENTS.md` 状态与 `experiments.json` 的既有标签不因本交付改变。

## 1. 四个模式（长期语义名，数字键 1-4）

| # | mode_id | 操作 | 交互要点 |
|---|---|---|---|
| 1 | `fixed_follow` | WASD 屏幕相对移动；Tab 在其四种预设间循环 | hard / smooth / deadzone / lookahead 是**同一模式**的比较参数，不是四种交互模式 |
| 2 | `quarter_turn` | Q / E 每次 key-down 转 **±90°**（离散） | 按住不连续旋转；与 fixed_follow 的自由跟随可区分 |
| 3 | `orbit` | **RMB 按住拖动**连续环绕（俯角限幅 12°–78°） | 仅此模式捕获鼠标；用 `screen_relative`，像素位移**不乘帧时长** |
| 4 | `overview` | **MMB 拖动**平移焦点 + Home / 可视按钮回中 | 不做鼠标捕获（不锁光标）；平移按真实相机基与投影换算，焦点离目标后方向仍与画面一致 |

正交 / 透视是 **CameraRigConfig 的投影数据**，与控制行为正交；透视下滚轮改 `distance`（`distance_min/max/step` 限幅），正交下才改 `size`。

## 2. 架构

- `src/game/systems/camera_rig/`：4 个模式 Capability + 普通节点 `CameraRig`（唯一 executor）+ 纯数据 `CameraRigComponent` + `CameraRigConfig` Resource。
- **唯一写者**：只有 CameraRig 写 Camera3D 的 position / look_at / projection / size / near / far；模式只写组件期望姿态。
- **同帧次序**：`process_physics_priority = -10` 早于角色（0）；executor 写相机后经桥接层把**最终**地面基写入目标（`set_camera_ground_basis`），角色物理与渲染同帧一致；`right_axis()/forward_axis()` 读实际相机 basis，平滑混合期间也一致。
- **模式互斥**：`mode_id` 唯一真源；切换走 executor 的 `transition_time` 混合，起点取**上一帧真实提交状态**（focus / lookahead / yaw / pitch / distance / size / fov 一起插值），连续切换不跳。
- **高度/速度自适应是数据 modifier**：`height_distance_bias` / `speed_distance_bias`（各带上限）由 executor 每帧算进有效距离，**不是第 5 个 Capability**。
- **focus 收缩**：x/z 夹取；`focus_clamp_y_enabled` 默认 **false**，高空御剑不会被压回地面；2.5D 地平场地（庭院）显式打开并把 min/max y 设为 0；开放空域用场景 3D bounds 打开 y。

## 3. 输入契约（默认不抢场景按键）

- `enable_mode_selection_keys` / `enable_preset_key` / `enable_zoom_keys` 默认 **false**；只有镜头实验室显式打开；庭院用可视按钮切模式，数字键仍归场景。
- `mode_choices` 决定可用子集与 1..N 映射，默认 `[fixed_follow]`。
- Q / E 只在 `quarter_turn`（离散）与 `orbit`（连续）被消费，其余模式放行给场景。
- **RMB 仅 orbit**、**MMB 仅 overview**；release / 失焦 / 离树 / 切模式都由 owner 标记清账，且恢复进入捕获前的 `mouse_mode`（不误放别人的捕获）。
- 捕获态 Esc / RMB release 走 `_input`（即使 GUI 消费该事件也能退捕获）；开始捕获与滚轮走 `_unhandled_input`，因此 **GUI 滚轮不缩放**、点按钮不捕获。切模式丢弃未消费 delta，不跨模式积压。

## 4. 两个真实消费者

| 场景 | 用法 |
|---|---|
| `camera_lab.tscn` | 四模式 + 四预设全开；1-4 / Tab / ZX / 滚轮启用；HUD 常显仅「当前模式一句核心操作」，完整键表进详情（H / F1） |
| `movement_garden.tscn` | 默认 `fixed_follow`（smooth，yaw 43°/pitch 39.6°/distance 26.65，换算自旧固定偏移 (14,17,15)），旧构图与初始镜头不变；紧凑 `ModeToggleButton` 切 `orbit`，不占数字键 |

## 5. 已运行命令与结果

| 命令 | 结果 |
|---|---|
| `Godot --headless --path src res://game/systems/camera_rig/test_camera_rig_runner.tscn` | **128 / 0**（fixed_follow 25、quarter_turn 13、orbit 25、overview 14、executor 51） |
| `Godot --headless --path src --script res://tests/camera_lab_playtest.gd` | 0 失败（捕获生命周期、屏幕相对基、缩放、切模式纯度、HUD 版面） |
| `Godot --headless --path src --script res://tests/character_movement_playtest.gd` | 0 失败（含**第二消费者**：点击切 orbit → 数字键不改模式 → RMB 旋转 → W 沿旋转后相机前方 dot 1.000 → 切回） |
| y 夹取回归（executor 套件内） | `target y=20` 不被压 0；`focus_clamp_y_enabled=false` 保留高度；打开后按 min/max 生效 |
| 透视滚轮回归（orbit + executor 套件内） | 四个模式一致：正交改 size、透视改 distance；orbit+透视运行时探针 `distance 20.00 → 17.00`、相机实际移动 3.000 m；上下限分别停在 `distance_min` / `distance_max` |
| 平移生命周期回归（executor 套件内） | MMB 抬起被 GUI 消费时经 `_input` 兜底仍结束平移；失焦 / 切模式 / reset 清 `pan_active`/`pan_delta`/`pan_world_delta`/`recenter_request`；重回 overview 鼠标未按不产生平移 |
| `python3 tools/verify/run_all.py` | Tier 0 全过 + 负向控制 27/27 |
| 三分辨率截图（`--ui-size=960x640 / 1280x720 / 1920x1080`，关闭 content scale 以 1:1 出图） | 每档 PASS：HUD 10 个矩形与 9 个按钮全部在视口内（越界 0 / 溢出 0）、不遮挡角色屏幕点 |

**测试入口（冻结）**：`res://game/systems/camera_rig/test_camera_rig_runner.tscn`（场景模式；`tests/test_runner.gd` 的 SUITES 由集成者维护，本包不修改）。
单测总入口 `tests/test_runner.tscn` 当前 **395 / 0**（`test_motion_preview.gd` 不在其 SUITES，属并行方）。

## 6. 证据图（`docs/playtest/`，旧 5 张保留）

- 四模式同路径同输入对比：`2026-09-18-camera-lab-mode-{fixed_follow,quarter_turn,orbit,overview}.png`
- RMB 捕获态：`2026-09-18-camera-lab-orbit-rmb-captured.png`
- 三分辨率 HUD：`2026-09-18-camera-lab-ui-{960x640,1280x720,1920x1080}.png`
- 本轮修 orbit 透视缩放与平移生命周期后**未重拍**任何既有 PNG（母级冻结要求：新增证据一律用新文件名）。

## 7. 未验证边界与已知限制

- **遮挡只做观测，不做规避**：`is_occluded()` 是相机→目标肩部的只读射线，HUD 只显示「是/否」；**没有任何自动遮挡避让、推近、抬升或半透明化实现**，也未验证。灰盒里的遮挡对照只证明读数正确。
- 手感类（跟随舒适度、前视观感、orbit 环绕是否晕、overview 回中快慢）**需人工试玩**；自动化只覆盖可观察量与一致性。
- 御剑高度 modifier 只有数据通路 + 单元断言；未在群山 / 御剑航线的高空实机验收（两场景在本包之外，由集成者按 `focus_clamp_y_enabled` 语义迁移）。
- 连续环绕下 WASD 地面基与画面一致已断言，但「旋转中操作是否舒适」未验证。
- 未做：手柄 / 键盘可映射输入、边缘平移（只实现 MMB 拖拽）、点击地面移动（属另一输入能力）。
- **平移（MMB）不捕获鼠标**，因此结束事件可能被 GUI 消费：已由 `_input` 兜底处理并消费，但未在真实 GUI（带按钮遮挡的 3D 视口拖拽）下人工验证过。
- 相机包在 actor/装配侧（ActorAssembly / FlightBundle）的只读交叉审计另见 `2026-09-18-actor-assembly-audit.md`。
- 模式切换混合是姿态插值，**不是** Cinemachine 式的 shot 评估与优先级仲裁。