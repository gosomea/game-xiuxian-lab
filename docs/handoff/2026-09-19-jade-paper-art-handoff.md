# 交接文档 · 青玉纸白美术方向实施（2026-09-19）

> 交接对象：接手「青玉纸白」美术方向落地与人物动画的下一任（人或 Agent）。

> 2026-09-19 接线复核：正式样板入口现已确实在角色入树前替换骨骼 Visual；同时修复
> Mixamo 后处理中左右肢体交叉绑定和手指骨权重被裁掉的问题。结构证据与回归结果见
> `docs/playtest/2026-09-19-jade-paper-rigged-side-fix.md`。修正前资产保留为
> `docs/art/cultivator_jade/cultivator_rigged_pre_side_fix.blend`，仅供故障对照。
> 本文档自包含：背景、现状、文件地图、待办、验证方式。细节以引用的 note/台账为准。

## 一、背景与目标

- 依据 commit `4af58e4` 采纳的美术方向 note
  `notes/proposed/art/2026-09-19-jade-paper-art-direction.md`（仍为 proposed，总验收未关）：
  > 国风动画化造型，精致低模生产，温润 PBR 材质，青玉暖木色卡，水墨意象远景，
  > 角色与飞剑保留细轮廓，场景通过光影和雾形成层次。
- 实施策略：**小型样板先行**（方向 note §6），样板过使用者视觉验收后才批量推广到五峰与旧场景。
- 全部实施记录集中在
  `notes/implemented/art/2026-09-19-jade-paper-sample-implementation.md`（四轮记录都在里面，先读它）。

## 二、现状（已完成四轮，全部已 commit）

| 轮 | 内容 | 关键产物 |
|---|---|---|
| 1 | 样板场景 + 混元生成环境资产（亭/松/岩）+ 程序台基铺装 | `jade_paper_sample.tscn/.gd`、`jade_{pavilion,pine,rock}.glb`、`jade_sample_terrain.glb` |
| 2 | 扩景（山门/灯笼/竹丛/草/水塘/石桥/远山带）+ 人物 v2（混元生成 + 分件切割） | `jade_{gate,lantern,bamboo,mountain}.glb`、`cultivator_jade.glb`、`jade_grass.glb` |
| 3 | Mixamo 真骨骼：绑骨 + 4 动作下载 + 袍子权重锁定 → 骨骼角色 GLB | `cultivator_rigged.glb`（Skeleton3D + AnimationPlayer，clips=[idle,jump,run,walk]） |
| 4 | 骨骼角色接入样板场景（本交接时刚接线，**动作配合待实机核**） | `cultivator_visual_rigged.tscn`、`cultivator_skeleton_presentation.gd` |

- 场景入口：`src/levels/experiments/character_movement/jade_paper_sample.tscn`
  （子实验目录第 8 项「青玉纸白样板」，exploring）。
- 人物：`swordsman.tscn` 默认仍是分件刚体视觉；**仅样板场景**在 `_spawn_player()`
  里把 Visual 替换为 `cultivator_visual_rigged.tscn`（骨骼版），其余 7 个场景不受影响。
- 门禁：`python3 tools/verify/run_all.py --with-tests` 全绿（959/0，27/27 负向控制）。
- 实机截图：`docs/playtest/2026-09-19-jade-paper-sample-round2.png`（二轮）；
  四轮接线渲染已跑通（0 error，人物入景）。

## 三、文件地图

| 内容 | 路径 |
|---|---|
| 方向 note（proposed） | `notes/proposed/art/2026-09-19-jade-paper-art-direction.md` |
| 实施 note（四轮记录） | `notes/implemented/art/2026-09-19-jade-paper-sample-implementation.md` |
| 资产台账（job_id/sha256/踩坑） | `docs/art/jade_paper_sample/asset_ledger.md`、`docs/art/cultivator_jade/` |
| 混元后处理脚本 | `tools/art/process_jade_hunyuan.py`（含色卡与分段规则） |
| 地形/草生成脚本 | `tools/art/build_jade_sample_terrain.py`、`tools/art/build_jade_grass.py` |
| 人物切割脚本 | `tools/art/process_cultivator_jade.py` |
| Mixamo 驱动 | `mcp/mixamo/mixamo_driver_phase{1,2,3}.py`（MCP 集成已收编进本仓 `mcp/mixamo/`） |
| 骨骼表现层 | `src/game/actors/swordsman/cultivator_skeleton_presentation.gd` |
| 骨骼视觉场景（旧长袍，保留为回退） | `src/game/actors/swordsman/cultivator_visual_rigged.tscn` |
| **现役人物视觉（v7 中性底座）** | `src/game/actors/swordsman/cultivator_visual_neutral_youth_v7.tscn` |
| 纪律 skill | `skills/mcp-mixamo/SKILL.md` |

## 三·五、2026-09-19 v7 人物替换（本交接之后的最新状态）

使用者已决定**停止仙侠衣装制作**，本轮只做中性动画底座。样板人物视觉已从
`cultivator_visual_rigged.tscn`（旧青玉长袍）换成
`cultivator_visual_neutral_youth_v7.tscn`（无仙侠衣装，原身体 + 深靛遮挡层）。

- 依据：`notes/proposed/art/2026-09-19-neutral-youth-animation-base-v7.md`；
  实施记录：`notes/implemented/art/2026-09-19-neutral-youth-animation-base-v7-implementation.md`；
  台账（含全部踩坑）：`docs/art/cultivator_neutral_youth_v7/asset_ledger.md`；
  验收：`docs/playtest/2026-09-19-neutral-youth-v7.md`。
- 旧长袍视觉与 `cultivator_rigged.glb` **保留未删**，作为回退与故障对照，只是不再接入运行时。
- v7 是**临时美术底座**：无服装、无头发、遮挡层只服务动作验证；后续完整角色走 3D 生成。
- 动作迁移不是按骨名直拷（实测 37/64 骨 rest 朝向差 >5°，最大 179.3°），
  而是 rest 帧共轭 + armature 空间标准形重定向，整数帧端点误差 2e-6 m。

## 四、立即待办（按优先级）

1. **实机试玩验收（使用者本人，审美结论唯一来源）**：
   `./run.command` → 角色移动 → 第 8 项「青玉纸白样板」。
   核对：走/跑/跳动作是否配合（滑步？）、跳跃节奏、御剑姿态、朝向是否正确。
   v7 模型导出用 `export_yup=True`（Blender -Y 正面 → Godot +Z 正面），已按此验证；
   若仍背对镜头，再考虑旋转视觉场景里的模型实例。
2. **速度同步校准**：`cultivator_skeleton_presentation.gd` 的 `walk_stride_meters=1.6` /
   `run_stride_meters=3.2` 是 Mixamo 近似值——实机看滑步就调这两个数（步频跟不上调小，漂移调大）。
3. **跳跃手感**：当前 airborne 播 `jump` 单次并保持末帧，落地切 walk/idle——若体验差，
   换起跳/落地双 clip（Mixamo 搜 "Jump Landing"）。
4. **御剑表现**：当前 idle 0.6 倍速 + 前倾 0.21 rad——想更好可从 Mixamo 加
   "Falling (Idle)" 或悬浮类动作映射到 flying 态。
5. **（大头）全场景推广**：方向 note §6 第 7 步——其余 7 个场景换骨骼视觉 +
   `motion_preview` 系测试适配到新表现层 API（drop-in 键已兼容 clock/gait/phase/speed，
   但 leg_left 等分件键需随刚体系统一起退役）。**必须样板过使用者验收后再动**。

## 五、机制层坑（全部实测，改前必读——细节在台账「踩坑」节）

- glTF 导出器丢 MixRGB 节点 → 调色烘进贴图像素；Godot 导入 baseColorFactor 会做
  linear→sRGB 转换 → 色卡按显示口径 srgb_to_linear 预补偿。
- GLB 抽取的 `*_tex.png` 是运行时依赖，删了加载崩；必须入 Git。
- 正交视野：35 m 外被雾吞没、近距高墙填满整帧；远山甜点 = 台基正后方 25–45 m、6–10 m 高。
- Mixamo FBX 是 cm（骨架 scale 0.01）：只把骨架 ×100；Blender 5.2 glTF 导出用
  `export_animation_mode="ACTIONS"`（无 export_animation 布尔）。
- Playwright 驱动 Mixamo：标记点必须人工拖放；Edge 下载 S3 附件会崩 context
  → 拦截预签名 URL + urllib，每动画独立会话。

## 六、验证命令

```sh
python3 tools/verify/run_all.py --with-tests          # 门禁 + 959 项测试
godot --headless --path src tests/test_runner.tscn    # 只跑测试
godot --path src --resolution 1280x800 \
  res://levels/experiments/character_movement/jade_paper_sample.tscn \
  --write-movie /tmp/f.png --quit-after 60            # 实机截帧（f00000059.png 收敛帧）
```

## 七、边界与授权

- 本仓 Git：本地 commit 已获长期授权；push/强推/改历史**不在授权内**。
- 资产纪律：新版本另存不覆盖；GLB 抽取贴图必须入 Git；台账同步登记 job_id/sha256。
- 审美结论归使用者：自动化通过 ≠ 视觉验收通过。
- 原型备份：`projects/mixamo-mcp/`（不再维护）、旧 `cultivator.glb`（sha256 不得变）。
