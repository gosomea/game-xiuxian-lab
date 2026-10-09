# 天降剑雨实现与分支验收

本分支完成 [[goal:rain]] 对应的 [[node:rain]]：独立的 HeavenlySwordRainComponent、HeavenlySwordRain、HeavenlySwordRainView 与配对测试。决策先由 `notes/implemented/gameplay/2026-10-10-sword-spell-exploration.md` 覆盖；词汇先登记并生成索引，再写运行时。仅本地开发，无推送。

## 实际流程

按下有效地面选点后，上空金青三环与十二组线形符文展开，24 把剑依次渐显、朝下悬停；地面青色双环显示作用区域。按住时选区平滑跟随真实地面指针。松手立即锁定当前看见的选区，逐剑做一次地面采样；快速点击也保留 0.72 秒聚剑与 0.22 秒完整成阵停悬。

随后三批落剑，每批 8 把，批距 0.30 秒，批内各剑错峰 0.012 秒。每剑从自己的真实悬停位置出发，0.62 秒内按 `u²` 加速下降，附带小幅收拢侧弧 `4u²(1-u)²`；朝向取同一轨迹的切线。连续剑尖线段参与三维 sweep，每剑每目标最多登记一次。轨迹没有独立于逻辑的视觉 Tween，也没有逐剑顿帧。

剑尖精确停在采样地面，剑身沿实际朝向留在地面上方。接地小环扩散，剑停留 0.32 秒后用 0.38 秒淡出，空中法环随后用 0.38 秒收束。三批各发一次 0.12 强度的轻空间反馈；没有 TimeKeeper 请求。散阵后冷却 0.55 秒。

## 默认参数

| 参数 | 默认值 | 用途 |
|---|---:|---|
| sword_count / batch_count | 24 / 3 | 分三批覆盖区域 |
| region_radius | 2.7 m | 地面选区与落点散布 |
| ceiling_height | 6.0 m | 剑尖悬停离选区中心的高度 |
| sword_scale | 1.55 | 复用共享灵剑几何的尺寸 |
| gather_time / hover_time | 0.72 / 0.22 s | 快点也能完整聚剑与停悬 |
| batch_interval / sword_stagger | 0.30 / 0.012 s | 可辨的分批节奏与批内小错峰 |
| fall_time | 0.62 s | 单剑连续加速下降 |
| linger_time / fade_time | 0.32 / 0.38 s | 接地停留与消散 |
| hit_radius | 0.25 m | 连续剑尖扫掠半宽 |
| follow_rate / bend_distance | 12 s⁻¹ / 0.22 m | 选区跟随与轻微侧弧 |
| cooldown | 0.55 s | 结束后可再次施法的等待 |

上空法环位于剑柄上方，默认最高环约为中心地面 +7.45 m；集成镜头需要保留整个法环与地面落区。参数为探索节奏，无伤害、血量、经济或平衡结论。

## 装配与数据 API

宿主直系子安装 `HeavenlySwordRainComponent`，CapabilityManager 直系子安装 `HeavenlySwordRain`。视图作为三维节点挂入场景，调用 `HeavenlySwordRainView.bind(component)`；视图顶级世界变换固定为单位变换，只读数据，不改镜头。

公共观察字段为 `phase`（gather / hover / rain / dissipate / idle）、`progress`、`ground_center`、`ground_normal`、`ceiling_center`、`ring_alpha`、`ring_angle`、`released`、`batches_launched` 与 `swords_landed`。统计在结束后保留，下次激活归零。

`swords` 每项含 `slot, batch, tip, forward, scale, alpha, state, trail, target`。`tip` 是真实世界剑尖，state 为 hover / fall / landed；末段 trail 为最近八个逻辑点。`impacts` 每项含 `position, normal, progress, alpha`。绘制时以共享 `SwordSpellVisual.TIP_LENGTH`（0.702 m）反算剑格原点；可用 `HeavenlySwordRainView.transform_for_sword(record)` 读取实际绘制变换输入。

输入只读取共享 SwordCastComponent：FORM_RAIN、aim_surface_point / valid / normal、cast_pressed / held / released 与 cancel_generation。蓄势时换招终止；释放后换招保留剑雨但不写当前人物姿势。重置、失焦与退场通过取消序号终止，能力退出树也清空剑、轨迹、冲击和法环。

地面采样 collision_mask=2；工作台地面/高台应为 collision_layer=3，木桩保持 layer=1。每剑锁区时只做一次向下查询，排除宿主 CollisionObject3D；无物理地面的确定性测试按 aim_surface_point / normal 投影到斜面。共享网格与法环工具来自 foundation，无新增外部资产或依赖。

## 分支验收

运行环境 Godot 4.6 stable，Compatibility 基线。实际执行：

- `Godot --headless --path src --import`：资源与类缓存导入完成，无脚本/资源错误。
- `Godot --headless --path src game/abilities/heavenly_sword_rain/test_heavenly_sword_rain_runner.tscn`：93 断言通过、0 失败。
- `python3 tools/gen/gen_vocabulary_index.py` 与 `gen_capability_catalog.py`：生成独立词汇和第 11 个能力。
- `python3 tools/verify/run_all.py`：Tier 0 门禁及 33/33 负向控制通过。
- `python3 tools/verify/run_all.py --with-tests`：中央运行时回归 2186 断言通过、0 失败；新套件由独立入口验收，集成时登记中央入口。

配对测试覆盖招式/无效选点、快速点击完整三批及真实时间间隔、锁区与后台姿势、蓄势换招/取消、每帧剑尖不穿地、实际轨迹切线、后段加速、单剑去重、高台斜面、真实 bit2 高台采样并忽略 bit1 木桩、冷却、卸载清理、尾迹网格与放大后精确剑尖变换。

Headless dummy renderer 的 MultiMesh get_instance_transform 返回单位变换，因此几何断言直接验证视图实际提交的 transform_for_sword 输入；没有把 dummy 返回值当作渲染证据。帅气、完整取景与真实窗口的连续动作质量由集成后的 [[node:acceptance]] 再验收，本分支测试不宣称用户已认可观感。

## 边界

剑雨固定当前可见选区，松手后不能重新瞄准。一次能力生命周期只允许一阵剑雨；释放后可以并行切到别的独立招式。地形采样只发生于锁区，期间移动平台不会追随；采样射线从选点上方约 14 米到下方 24 米，实验范围外需重新设计地形查询。没有挡攻击、防御、血量、伤害、敌人 AI、胜负或自动追踪。
