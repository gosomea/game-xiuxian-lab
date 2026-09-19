# Note: 青玉纸白样板落地：混元生成资产 + 样板场景（第一轮实施）

Status: implemented

实施授权：使用者于 2026-09-19 明确指示按 [青玉纸白方向 note](2026-09-19-jade-paper-art-direction.md) 优化项目视觉/美术/人物/场景，并授权"必要时用混元直接生成 3D，再在 Blender 里编辑"。本 note 记录第一轮（样板范围）的实施决策与实施记录；方向 note 保持 proposed，其批量推广与总验收仍开放。

## 问题

方向 note 已给出完整规格但没有可运行的实物：五张概念图不可运行，八个场景的环境参数各写一套，"青玉纸白"是否真的在 Godot 实机中成立（配色 / 剪影 / 雾 / 轮廓）没有任何证据。方向 note §6 的第一步是小型样板，本 note 决策样板的资产来源、制作管线与场景装配。

## 决策

### 1. 范围：只做样板，不批量推广

按方向 note §6 顺序：本轮交付小型样板场景 `jade_paper_sample.tscn`（亭 / 台阶 / 松 / 岩 / 人物 / 飞剑 / 远景一屏可比较）。五峰与既有场景不在本轮改动。

### 2. 人物与飞剑：零改动（已合规）

逐条核对现役资产与方向 note §2/§3：

| 项 | 方向要求 | 实测（GLB 读数） | 结论 |
|---|---|---|---|
| 人物比例 | 6.5–7 头身 | 1.70 m ≈ 6.8 头身 | 达标 |
| 人物衣 | 交领/腰封/袍摆三线 | `Robe_Collar` / `Robe_Sash` / `Robe_Skirt` 独立分件 | 达标 |
| 人物头 | 发髻成立 | `Hair_Bun` + 开口发帽 `Hair_Cap` | 达标 |
| 人物色 | 靛青主色 + 月白内衬 + 淡金腰封 | `Robe_Indigo`(0.086,0.146,0.246) / `Inner_Ivory`(0.76,0.73,0.66) / `Sash_Wood_Gold`(0.43,0.31,0.13) | 达标 |
| 飞剑 | 剑体可辨 | `Blade steel` / `Hilt wrap`(暖棕) / `Aged bronze`(古铜) | 达标 |

人物分件名（`Leg_L` 等）是 `cultivator_presentation.gd` 的硬契约，混元整体生成的人物网格会破坏分件刚体动画，禁止替换人物模型。本轮人物与飞剑不改。

### 3. 环境资产：混元生成 + Blender 归一

无分件契约的静态环境物（亭/松/岩）用混元 3D 生成（腾讯云 hy-3d 文生 3D），再在 Blender 内编辑：

- 来源声明：混元生成几何 + 烘焙贴图；Blender 内仅做缩放/朝向归一、减面与材质调色；不做人工雕刻。逐资产 job_id 登记于台账。
- 归一：Y-up、底面 z=0、xy 居中、等比缩放到目标高度（松 6.0 m / 岩 2.2 m / 亭 4.6 m，按人参照 1.70 m）。
- 材质调色：按烘焙贴图色相给面分段（松=冠/干，亭=瓦/木/石），调色系数（色卡/段均色，逐通道截断）直接烘进 1024 贴图副本。必须烘进像素——glTF 导出器不导出 MixRGB 乘法节点（`baseColorFactor` 会丢，本轮实测踩坑）。
- 另存：新文件名 `jade_pavilion.glb` / `jade_pine.glb` / `jade_rock.glb` / `jade_sample_terrain.glb`（台基+台阶+铺装+收边，程序建模）；旧资产零删除零覆盖。
- 复现脚本：`tools/art/build_jade_sample_terrain.py`（地形）与 `tools/art/process_jade_hunyuan.py`（混元后处理，含色卡）。

### 4. 样板场景

`src/levels/experiments/character_movement/jade_paper_sample.tscn` + `.gd`：

- 复用 `Swordsman`（三能力不变）、共享 `CameraRig`（fixed_follow + 滚轮缩放）、`LabHud`、共享 `MovementLabInput`。
- 场景内置 `WorldEnvironment`：低饱和青蓝天穹、高度雾（`fog_height=8`、`fog_height_density=0.02`）压远景对比；暖金斜光 + 阴影。
- 碰撞为场景内显式盒（样板规模不引入布局 JSON 机制）：地面/台基/台阶/树干/岩石/边界；装饰面契约由地形 GLB 自带（压顶高出主体 0.02、踏面条高出踏步 0.02、砖面高出地面 0.02）。
- 注册进 `character_movement_subexperiments.json`（id `jade_paper_sample`，exploring）与 `movement_lab_hub.gd` REQUIRED_IDS。

## 备选方案

- 混元整体替换人物：不采用。分件名是表现层硬契约，替换会静默瘫痪步态/御剑姿态动画（方向 note §4 表现层边界同样禁止）。
- 保留混元烘焙贴图原色：不采用。生成色与色卡漂移（岩石实测偏冰蓝），样板的价值就在于验证统一色卡。
- 材质调色走 shader 乘法节点：不采用。glTF 导出器丢节点（本轮实测），调色必须烘进像素。
- 亭/松/岩全程序建模复刻现有管线：不采用。使用者明确授权混元生成；生成件与程序件的质感差异正是样板要比较的对象。
- 直接改 mountain_realm 五峰落地新方向：不采用。违反方向 note §6（先样板验证、后批量推广）。

## 后果

- `tools/verify/run_all.py --with-tests` 全绿（当前 959 项），负向控制 27/27；子实验清单基线从七项扩为八项并同步测试。
- 样板场景在真实 Godot（gl_compatibility，Movie Maker 截帧）可启动、可渲染，首帧证据入 `docs/playtest/2026-09-19-jade-paper-sample-first-run.md`。
- 新 GLB 读数（网格/三角形/材质/贴图/字节/sha256）与混元 job_id、来源声明登记于 `docs/art/jade_paper_sample/asset_ledger.md`；`hunyuan_raw/` 保留原始产物与预览图。
- 旧资产零删除零覆盖：`cultivator.glb` / `flying_sword.glb` / `mountain_realm*.glb` sha256 不变，新资产全部另存新文件名。
- 审美结论归使用者：使用者视觉确认前，样板状态保持 exploring，不宣称方向通过；交互手感与多机位动作视频（方向 note 验收 §2）留待实机试玩轮。


## 实施记录（2026-09-19）

已落地：

- 资产：`jade_pavilion.glb`（79,999 tris）/ `jade_pine.glb`（39,994）/ `jade_rock.glb`（30,000）/ `jade_sample_terrain.glb`（696），混元 job_id 与 sha256 见 [资产台账](../../../docs/art/jade_paper_sample/asset_ledger.md)；原始产物归档于同目录 `hunyuan_raw/`。
- 场景：`jade_paper_sample.tscn/.gd`（注册进清单与 hub，入口第 8 项）。
- 验证：`tools/verify/run_all.py --with-tests` 全绿（959 通过）；实机首帧证据 [playtest 记录](../../../docs/playtest/2026-09-19-jade-paper-sample-first-run.md)。
- 实机修复四项（远景盘顶面遮地、baseColorFactor 导入转换洗白、铺装蝴蝶结面、高度雾参数），机制层结论已回写台账「关键约束」。
- 测试基线随清单从七项扩为八项（`test_movement_lab_hub.gd` / `movement_hub_playtest.gd`）。

未做（留给后续轮次）：

- 交互手感与多机位动作视频（方向 note 验收 §2）。
- 批量推广到五峰与既有场景（方向 note §6 第 7 步，须样板过使用者视觉验收后）。


## 第二轮（2026-09-19 上午，使用者反馈驱动）

使用者看首帧后指示：场景不够完善（山/水/草/建筑不全），人物也要替换，且指定用内置 3D 生成。本轮决策：

### 场景扩充（仍在样板内，不改五峰）

| 项 | 来源 | 规格（方向 note §2/§3 口径） |
|---|---|---|
| 远山 | 混元生成 `jade_mountain.glb` | 剪影为主、降对比，放 60–140 m 环带，靠雾做水墨层次 |
| 山门牌坊 | 混元生成 `jade_gate.glb` | 台基/柱梁/檐分层清楚，人尺度门洞可走 |
| 石灯笼 | 混元生成 `jade_lantern.glb` | 台阶两侧成对 |
| 竹丛 | 混元生成 `jade_bamboo.glb` | 竖向成簇、疏密朝向，西侧成组 |
| 水面 | Godot 侧平面 + 石岸 | 低饱和青蓝，岸线收边，不做水下碰撞 |
| 草簇 | 程序建模 `jade_grass.glb` | 深松绿，成组聚散散布 |

### 人物替换（策略变更，覆盖第一轮"零改动"结论）

使用者明确要求替换人物并指定内置 3D 生成。混元整体网格会破坏 `cultivator_presentation.gd` 的 13 分件名契约，故采用**混元生成 + Blender 按衣装结构切割成命名分件**：

- 切缝全部藏在服装结构下：腰缝被腰带（留在静部）盖住、肩缝加静部肩垫、髋缝藏在裙壳内、头/发/脸不参与摆动留在静部。
- 分件名严格保留：`Leg_L/R`、`Foot_L/R`、`Arm_Sleeve_L/R`、`Cuff_L/R`、`Hand_L/R`、`Robe_Skirt/HemBand/Panel` + 静件 `Robe_Upper/Inner/Collar/Sash`、`Head`、`Hair_Cap/Bun`、`Face_Nose/Eyes/Brows`。
- 产出 `cultivator_jade.glb`（另存，旧 `cultivator.glb` 保留），`cultivator_visual.tscn` 换引用即全场景生效；导出后必须过表现层装配断言（枢轴数量/父节点/成员接管）。
- 材质取向：优先保留混元烘焙贴图（提示词直接写色卡），偏离色卡时用第一轮的贴图乘法调色校正。

执行顺序：先出 note（本节），后写切割代码。


### 第二轮实施记录（同日补记）

- 场景扩充落地：山门（北侧 z=-14）、灯笼 ×2、竹丛 ×4、草簇 ×12、水塘+三板石桥（东侧）、
  护环碰撞（不可趟水）、边界扩至 20 m。
- 人物替换落地：`cultivator_jade.glb`（16 分件 / 34,013 tris，混元 job 与 sha 见台账第二轮表）；
  `cultivator_visual.tscn` 已换引用，全部场景受益；旧 `cultivator.glb` sha256 不变。
- 实测校正三条：踝切线降至 0.035H（否则 Foot 缺失）；头并入 Robe_Upper（避免颈缝）；
  远山摆位多轮标定为台基正后方 25–45 m 矮山包（正交+雾的可见窗口极窄，机制见台账）。
- 门禁 `--with-tests` 全绿（959/0）；实机证据 [round2](../../../docs/playtest/2026-09-19-jade-paper-sample-round2.md)。


### 第三轮实施记录（Mixamo 真骨骼动画，资产就绪）

- 使用者指示接入其 mixamo-mcp（`projects/mixamo-mcp/`，Edge 持久登录态）：
  合并单网格 OBJ 上传 → **人工拖放标记点**（repo 自动化不支持 marker 拖放，
  Edge 有头窗口由使用者完成 3 步）→ 自动绑骨成功（角色 cultivator_jade_for_mixamo）。
- 动画下载 ×4：Walking（skin=true，带蒙皮角色）/ Idle / Running / Jump Up（仅骨架动作），
  inplace=on，fbx_unity 30fps。下载经 S3 预签名 URL 拦截 + urllib（Edge 打开跨域附件会崩，
  mcp_server 同款 workaround；每动画独立浏览器会话）。
- 组装（`mixamo-mcp/mixamo_driver_phase3.py`）：Mixamo FBX 是 **cm 单位**（骨架 scale 0.01），
  只把骨架 ×100（网格局部数据已是米，×100 会变 172m）；动作重命名 walk/idle/run/jump；
  **袍子权重锁定**（robe 岛只保留 Hips，腿/袖各自保留骨链，空权重回填首骨）——
  即"人物与衣服分开"的等效实现（外袍刚体挂髋，腿在裙内摆）。
- 产物：`src/game/actors/swordsman/models/cultivator_rigged.glb`
  （Skeleton3D + AnimationPlayer，clips=[idle,jump,run,walk]，walk 实播验证通过）；
  源 `docs/art/cultivator_jade/cultivator_rigged.blend`；上传源 FBX/OBJ 同目录留存。
- **接入未做（下一轮）**：`cultivator_visual_rigged.tscn` + 骨骼驱动表现层
  （drop-in 替换 CultivatorPresentation，同节点名 + 同 API）+ motion 预览测试适配。


### mixamo MCP 与 skill 收编进本仓（同日）

- 使用者指示收编：`mcp/mixamo/`（自研 Playwright 自动化 + 8 工具 + 驱动脚本 phase1/2/3 +
  LICENSE/README/.gitignore；browser_profile/downloads/.venv 为运行态，gitignore 不入库）
  + `skills/mcp-mixamo/SKILL.md`（纪律：人工标记前置、驱动入口、踩坑清单、验证方式）。
- `verify_mcp.py` INTEGRATIONS 注册 mixamo（8 工具），mcp/README.md 清单更新；
  全局 `~/.workbuddy/mcp.json` 的 mixamo 条目改指本仓路径。
- 原 `projects/mixamo-mcp/` 保留为原型备份，不再维护。


### 第四轮实施记录（骨骼角色接入新场景）

使用者指示：新场景装上骨骼角色，动作配合运动，实现易懂。决策：

1. **只接新场景**：`jade_paper_sample.gd` 在 `_spawn_player()` 后把 Visual 子树替换为
   `cultivator_visual_rigged.tscn`（rigged GLB + 骨骼驱动表现层）；其余场景维持分件
   刚体视觉（motion 预览测试零影响）。
2. **表现层 drop-in**：`cultivator_skeleton_presentation.gd` 沿用 CultivatorPresentation
   的公开 API（auto_read_actor / actor_path / advance_state / sample_state / pose_state /
   reset_pose），只读 motion() 快照驱动 AnimationPlayer，不碰物理。
3. **动作映射（含速度同步）**：御剑=idle 0.6 倍速+前倾 12°；空中=jump 播完保持；
   着地 speed>5.5→run、>0.3→walk（播放速率 = 实际水平速度 / 动作自然速度
   walk 1.6 / run 3.2 m/s，防滑步）；否则 idle。切换用 play(clip, 0.15) 交叉淡化。
4. 朝向以实机截图核对（Mixamo 导出面朝可能 +Z，错则 Visual 转 180°）。

## 风险

- 混元产物面数与拓扑不可控：本轮以 Decimate 预算兜底（松 40k / 岩 30k / 亭 80k），超预算对象放行前必须先减面。
- 混元件的平滑高模质感与程序件的硬朗低模质感存在断层，样板阶段刻意并置供使用者比较；若判为不可接受，混元件需退回 Geometry 白模 + 手动块面化。
- 色相分段按贴图颜色投票，阴影区可能被误分类（松冠暗部曾落入木段）；当前阈值 (sat>=0.08, hue 0.20–0.60) 下一轮若出现脏色，先调阈值再考虑手工修分。
- 亭的朝向（PAVILION_YAW_DEG）以实机截图核对，错误会表现为亭背对出生点。

