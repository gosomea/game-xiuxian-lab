# 角色移动实验组：集成审计记录（基线 99e4894）

**本轮只记录研究与提案；不包含运行时修复。** 只读研究，未改 `src/`/`design/`/工具/资产/旧 notes，未运行 Godot。四路研究（UX、装配复用、镜头、动作）合并后的证据基线：仓库 `99e4894`；统一提案见 [composable-labs](../../notes/proposed/gameplay/2026-09-18-character-movement-composable-labs.md)（**proposed**）。

**阅读约定**：`[事实]`（有源码行/GLB 解析/官方文档）；`[推断]`（由事实推出、未运行验证）；`[待验证]`（需运行/实拍才能定）。

## 1. 用户七条诉求 → 方案与验收对照（按用户原编号）

| # | 用户诉求 | 现状证据 | 方案（详见提案） | 验收 |
|---|---|---|---|---|
| 1 | 入口：点角色移动直达子实验 | `lab_hub.gd:72` 只选中 + `:106-108` 才进入；子目录同构 `movement_lab_hub.gd:196`/`:241-243` `[事实]` | 两级卡片一次点击直达（2 击）；planned 只看说明 | 点击链 2 击 |
| 2 | 镜头 | 现有 HARD/SMOOTH/DEADZONE/LOOKAHEAD 是 A 的参数预设（`camera_lab_rig.gd:18-39`）；yaw 仅 Q/E（`camera_lab.gd:27,34`）`[事实]` | A/B/C/D + 高度 modifier + 单 executor；投影为 Resource | 模式可操作区分；切换无跳变 |
| 3 | UI：字大/占屏 | 字号 override 20+ 处；18%/9.6% 为**旧截图与源码常量估算**，非当前实测 `[推断]` | Control+Theme 复用，信息分层优先；问题折叠/tooltip | 960×640/1280×720/1920×1080 按 UI 缩放验证，默认遮盖 ≤15%（建议目标、压力场例外） |
| 4 | 御剑 | 四场可进御剑中仅 `sword_flight_course` 无绑剑调用；motion/state/mountain 已绑 `[事实]` | 可安装飞行表现包，4 场统一接入 | 剑可见 + 脚下位置/朝向/帧内尺寸截屏 |
| 5 | 人物动作工作台 | 同模型同装配，但缺动作库与操控预览；工作台无播放器 UI（`cultivator.glb` 0 skin/0 anim）`[事实]` | 4 组动作简表 + 选择/播放/暂停/单步/循环/倍率/A–B 过渡 + 侧正斜与脚接触观察；P0 程序动作真播 | 播放/暂停/单步可复算 |
| 6 | 解耦与挂载 | 嵌套 Sheet 不能共享 actor 组件（`capability_manager.gd:30-36`、`capability.gd:19-44`、`sheet_loader.gd:18,29-36`）；输入映射 2 份、相机跟随 6 份 `[事实]` | 局部装配适配器（提案待验证）+ 可安装包；装配树见提案 §3 | 新场景凭标准角色+相机包+配置即能挂，无复制 bind |
| 7 | 统一庭院模型 | 七场均 preload `swordsman.tscn`（camera_lab.gd:17 等）→ `models/cultivator.glb`（swordsman.tscn:7,25）`[事实]` | 固定唯一 prefab；文档归属修正 | 模型引用/标识 + 轮廓，不锁 mesh 数 |

**新增横切问题（不占第 7 条）**：返回位置/模式不保留（`movement_lab_hub.gd:65-71`；首页无 `ui_cancel`）；输入上下文未统一（RMB 捕获/Esc/滚轮归属/连续旋转下 WASD 地面基）——方案见提案 §1 与 §3，验收为「Esc 先退捕获/面板再返回；滚轮只滚 GUI；返回记忆」`[事实]` 现状 + `[推断·待验证]` 方案。

## 2. 装配与复用审计

- `[事实]` 七场角色装配相同，差异只在场景侧输入/相机/HUD/绑剑；三能力 `Jump(50)/SwordFlight(100)/SwordsmanMovement(0)`；全仓唯一 `move_and_slide()` 在 `swordsman.gd:50`。
- `[事实]` 剑绑定三份复制（motion_stage.gd:458-466、state_transition_lab.gd:339-346、mountain_realm.gd:581-587），训练场缺失；无脚本设置剑局部变换 `[待验证]` 落位。
- `[事实]` `cultivator.glb` = 23 网格 / 4952 三角形 / 8 材质 / **0 skin / 0 animation**；`cultivator_presentation.gd:78-121` 程序枢轴 + 物理状态驱动。
- `[事实]` 文档过期：`movement_garden/README.md:13`、`asset_ledger.md:11` 仍写 `generate_movement_assets.py`，实际为 `tools/art/generate_cultivator_refined.py`；23/4952/8 与旧读数不符。
- `[事实]` catalog 漏记：`sword_flight.gd:12/42` 用常量传 `&"sword_flight_block"`，生成器正则只认字面量 → `SwordFlight.uses_tags=[]`。**本轮只记录**：后续先改生成器常量标签提取（或显式声明契约），配负向控制与回归，再重跑生成 catalog。
- `[事实]` Sheet 边界：`sorted_capabilities()` 只看直系子；`game_object()` 要求父是 manager；`component()` 只扫宿主直系；`SheetLoader.attach` 仅 `host.add_child(sheet)`，`detach` 不调 `_on_deactivated`。→ 嵌套 Sheet 不能共享 actor 组件；**适配器方案 `[推断·待验证]`**。
- `[事实]` 隐藏复制：输入映射两份、相机跟随六份；`camera_lab_rig` 仅 1 消费者。

## 3. 镜头审计

- `[事实]` 现状：正交 `projection`（camera_lab.gd:63-65），无 RMB 拖拽/平移；遮挡只射线观测不改镜头（`:159-169`；`docs/playtest/2026-09-18-camera-lab.md:121-126` 自述为已知限制）。
- `[事实]` Godot 4.6：正交 `size` 是宽/高的直径、由 `keep_aspect` 决定（本机 `4.6.stable.official.89cea1439`；源码 `camera_3d.cpp @4.6-stable`）；捕获旋转用不受内容缩放影响的 `screen_relative`，非捕获平移可读 viewport 鼠标位置，UI 命中用 `get_hovered_control()`。
- `[参考实现]` Cinemachine 3.1.7：Orbital Follow（Range/Wrap/Recentering）、Position Composer（**Dead Zone / Hard Limits / 阻尼 / 前视**）、Brain（优先级选 live camera + blend）、Input Axis Controller（Cancel Delta Time / Suppress Input While Blending）；Phantom Camera v0.11.0.3 的 host 独占写入。
- **来源纠正**：Phantom 源码 commit `3e32997` 中 `FollowMode.THIRD_PERSON` 注释为 `ShapeCast3D`，不写作 SpringArm3D；Godot 引用固定 `/en/4.6/`；Cinemachine 只借思想、不接 Unity 包。
- `[推断·待验证]` 模式 Capability 挂 CameraRig manager 直系；单 executor 独占写；`mode_id`+Tag 互斥；modifier 有确定顺序与退出清残量；投影是 Resource。
- `[待验证]` C 连续环绕下 WASD 地面基漂移；正交下 orbit 的距离/pitch 语义；遮挡规避成本。

## 4. 动作审计

- `[事实]` 0 skin/0 clip，全仓 `AnimationPlayer|AnimationTree|AnimationMixer|Skeleton3D` grep 命中 0；现有动作 = `gait` 相位 + 物理边沿增益（`cultivator_presentation.gd:88-158`）；工作台无播放器 UI。
- `[事实]` 预览倍率不得写 `Engine.time_scale`（唯一写入者 `src/core/time_keeper.gd:6-7`）；读数应走 `pose_state()`（`cultivator_presentation.gd:161-187`），而 `mountain_visual_playtest.gd:107-108` 仍读私有 `_legs/_arms`。
- `[事实]` `_gait` 由 `grounded and speed>0.2` 门控、`_phase` 仅着地推进（`:116-119`）→ 御剑 12 m/s 不直接驱动地面步态；超速步态读感 `[待验证]`。
- `[事实]` in-place 与 root motion 都不违反唯一提交点：root motion delta 可经 `get_root_motion_position()` 交给 actor 唯一 executor；当前建议 in-place 是**迁移成本与现无 clip**，不是架构禁止。
- `[待验证]` socket `Visual/Sockets/<Name>` 未建立，真足滑指标「待建立」；骨骼化须另存目录与新文件名，旧 `.blend/.glb` 保留并登记替代关系。

## 5. 新增问题登记（本轮发现，未落地）

1. `sword_flight_course` 缺飞剑且无测试覆盖 → S0 补测试（现有剑断言仅在 motion_stage_playtest.gd:391-392、mountain_traversal_playtest.gd:17,246-248）。
2. camera 遮挡只射线观测、未规避（camera_lab.gd:159-169）。
3. input/HUD/camera 跟随三处复制（§2）。
4. 模型文档源生成器与统计过期（§2）。
5. catalog 常量 tag 漏记（§2，修复路径见上）。
6. Sheet 宿主/lifecycle/调度边界（§2）。
7. SystemFont 跨机器差异是风险（回退字形），不是已发生乱码；仓内 0 字体文件。
8. 缺能力子集/任意组合验证：现有仅 mountain_traversal_playtest.gd 的移除测试，无子集角色启动；不等于「全无验证」。
9. smoke 绿 ≠ 画面验收：飞剑 visible 只是初步，需脚下位置/朝向/帧内可见尺寸截屏。

## 6. 来源（固定版本，访问 2026-09-18）

| # | 来源 | 版本/提交 |
|---|---|---|
| S1 | [Godot Camera3D](https://docs.godotengine.org/en/4.6/classes/class_camera3d.html) | 4.6（`project.godot` features 4.6；本机 4.6.stable） |
| S2 | [Godot InputEventMouseMotion](https://docs.godotengine.org/en/4.6/classes/class_inputeventmousemotion.html) | 4.6 |
| S3 | [Godot Input](https://docs.godotengine.org/en/4.6/classes/class_input.html)（MouseMode） | 4.6 |
| S4 | [Godot Viewport](https://docs.godotengine.org/en/4.6/classes/class_viewport.html) | 4.6 |
| S5 | [Godot camera_3d.cpp](https://raw.githubusercontent.com/godotengine/godot/4.6-stable/scene/3d/camera_3d.cpp) | tag 4.6-stable |
| S6 | [Cinemachine Orbital Follow](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachineOrbitalFollow.html) | 3.1.7 |
| S7 | [Cinemachine Position Composer](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachinePositionComposer.html) / [Brain](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachineBrain.html) / [Input Axis Controller](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachineInputAxisController.html) | 3.1.7 |
| S8 | [Phantom Camera](https://phantom-camera.dev/follow-modes/overview) + [phantom_camera_3d.gd](https://raw.githubusercontent.com/ramokz/phantom-camera/3e32997c6948c2adee1a2fa3e6cb5ad0e8f7e3b3/addons/phantom_camera/scripts/phantom_camera/phantom_camera_3d.gd) | v0.11.0.3 → `3e32997` |
| S9 | [Godot AnimationTree](https://docs.godotengine.org/en/4.6/tutorials/animation/animation_tree.html) / [BlendSpace1D](https://docs.godotengine.org/en/4.6/classes/class_animationnodeblendspace1d.html) / [Retargeting](https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/retargeting_3d_skeletons.html) | 4.6 |
| S10 | [Blender NLA](https://docs.blender.org/manual/en/latest/editors/nla/index.html) / [Armatures](https://docs.blender.org/manual/en/latest/animation/armatures/index.html) | 5.2 LTS |

S9 只使用 Godot 4.6 已存在的 AnimationTree / AnimationNodeBlendSpace1D / 骨骼重定向 / root motion 事实（父级已核验 4.6 `animation_tree` 有效）。检索降级：`web_search` 返回 401，改用官方域名/官方仓库 curl。**业界实现一律只称参考实现。**

## 7. 本文件不构成决策

所有方案在 [composable-labs](../../notes/proposed/gameplay/2026-09-18-character-movement-composable-labs.md)（proposed）中受理；核心 `core/` 改动须另开 owning tech note，本轮不写 core、不写 src。

## 8. 限制

未启动 Godot、未跑 test_runner/playtest；18%/9.6% 等像素占比为**源码常量算术与旧截图估算**（旧 960×600/1200×800 图早于当前 960×640 min），不代表现状；HUD ≤15% 遮盖、字号/命中区为**建议目标未实测**；滚轮归属、断行一致性、16:9 表现、遮挡规避、适配器行为、骨骼迁移均为 `[待验证]`。
