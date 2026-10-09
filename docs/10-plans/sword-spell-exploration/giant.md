# 巨剑镇落分支

对应 [[goal:giant]]、[[goal:quality]] 与 [[node:giant]]；机制依据为 `notes/implemented/gameplay/2026-10-10-sword-spell-exploration.md`。独立叶子包 `src/game/abilities/giant_sword_descent/` 持有一个 Capability、纯数据 Component、只读 View、暗刃 shader 与配对测试，删除时不影响另外两条法术分支。

## 实际流程与参数

| 阶段 | 默认时长 | 行为与表现 |
|---|---:|---|
| gather | 最少 0.42 秒；满亮 0.9 秒 | 按住时法阵和剑平滑跟随真实地面选点；剑从短光芯凝成完整主剑，轻微悬浮；快速松开锁点后补足最小凝聚 |
| hover | 0.26 秒 | 松开锁定实际地面点与法线，主剑及法阵平滑归位，剑轴归正，剑尖上提 0.35 米 |
| descent | 0.48 秒 | 剑尖按 `u³` 从悬停处向锁点加速镇落；世界朝下；每 tick 做三维 sweep，尾迹记录确定性位置 |
| impact | 0.2 秒 | 剑尖精确停在锁定点，单次 burst 与贯穿共用命中账本；同帧记录一次强度 1 的空间反馈；残剑、双扩散环与碎光 |
| fade | 0.62 秒 | 残剑和符环衰减，冲击碎光消退；随后清所有表现 |
| idle | 冷却 0.38 秒 | 等待下一次按下边沿 |

主剑完整长度 5.6 米，悬停剑尖距选点 6.3 米，锁点后上提至 6.65 米，因此完整几何包络顶部距地约 12.25 米。共享模型以剑格为原点，View 读取 `SwordSpellVisual.TIP_LENGTH / TOTAL_LENGTH` 换算原点和非均匀比例，地面尖端与可见几何一致。主剑半宽查询 0.52 米，落地冲击半径 3.2 米、向上高度 2 米，地面法阵半径 2.4 米，预览指数跟随速率 10/秒。以上是探索节奏与空间参数，未引入伤害、血量、经济或平衡结论；基线无此招式。

视图以暗青刃面、青玉细光芯、金色护手和金环区分层次。冠环悬在剑格附近，释放时逐渐消失；地面内外环和符纹标明落点；下降历史绘成短尾迹，冲击由两条扩散环与径向碎光表达。Compatibility 路径只用共享 Mesh、ImmediateMesh、StandardMaterial3D 和 spatial shader，不依赖粒子拖尾或修改全局渲染器。View 不写镜头。

## 集成 API

1. 在宿主直系挂 `GiantSwordDescentComponent`，在其 `CapabilityManager` 下挂 `GiantSwordDescent`。
2. `var view := GiantSwordDescentView.new()`，调用 `view.bind(data)` 后挂入场景；`render_snapshot()` 可在验收手动 tick 后立即画快照。
3. 输入仍走共享 `SwordCastComponent`：`FORM_GIANT`、按下/按住/松开、`aim_surface_valid / point / normal`、`cancel_generation`。本包不发额外地形射线；地面与木桩筛选由共享输入入口完成。
4. 可读快照：`phase`（idle/gather/hover/descent/impact/fade）、`phase_progress / phase_elapsed`、`charge / locked`、`target_point / normal`、`rune_point / normal / alpha`、`sword_tip / forward / length / alpha`、`tip_history`、`impact_age / serial`、`visual_time`。
5. 当前招式才写 `POSE_GIANT` 与 `pose_phase / progress`；蓄势换招取消，释放后换招允许继续，后台镇落不抢姿势。落地只调用一次 `record_feedback(point, 1.0)`，由共享表现层承担声音/镜头/顿帧。

取消序号变化、能力退出树、Component 卸载都撤销剑体、法阵和轨迹。能力没有持有 TagRegistry/TimeKeeper 请求；单次镇落的 `_hit` 在取消、失活及退出时清空。`impact_serial` 为完成次数统计，清表现时保留。

## 分支验证

环境：Godot 4.6 stable、Python 3、基线共享基础 `b4117cb`，独立 worktree。实际执行：

```bash
python3 tools/gen/gen_vocabulary_index.py
python3 tools/gen/gen_capability_catalog.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path src --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path src game/abilities/giant_sword_descent/test_giant_sword_descent_runner.tscn
python3 tools/verify/run_all.py
```

导入退出 0，无脚本错误。配对测试通过 151、失败 0，覆盖激活/无地面、快速点击完整阶段、平滑追点/准确锁点、逐帧单调下降和加速、朝下与尖端接地、高台4米地面、贯穿/冲击去重、半径与高度隔离、落地一次反馈、释放后换招继续及姿势归属、蓄势换招取消、取消后复用、能力退出/组件卸载、冷却、可见模型剑尖对齐和视图清场。Tier 0 与 33 项负向控制全部通过。

最终 DAG verify 将再次按执行契约运行导入、配对测试和 Tier 0，并保存 fingerprint/receipt。分支尚未单独运行真实窗口、人工点击、连续录像或两个窗口尺寸构图；这些由主 Agent 在集成后的 [[node:acceptance]] 验收。此处不以无头测试宣称主观“帅气”已获用户认可。
