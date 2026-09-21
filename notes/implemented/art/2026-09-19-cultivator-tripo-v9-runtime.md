# Note: Tripo 修仙角色 v9 清理、绑骨与全移动场景接入

Status: implemented

## 问题

使用者提供 `docs/art/9b092e988c21840611f833788e4e4e9a.glb`，并依据侧对话检查结果指定其为
下一版人物候选。原始 GLB 约 75 MB，尚未形成可追溯资产目录，朝向、面数、网格卫生、
与自动化绑骨服务的兼容性、原地动作和 Godot 运行时接线均未在本仓验证。当前角色移动实验仍
混用共享分件视觉与 v7 中性底座，不能保证所有移动场景看到同一个人物。

## 决策

新增独立 `cultivator_tripo_v9` 资产链，完整保留用户提供的原始 GLB，不覆盖 v1–v8、
旧 Mixamo 角色或任何既有运行时模型。整条链分四段落地。

**一、清理。** Blender 5.2.1 后台隔离进程复制并清理源模型，修正为 Blender `-Y` 正面、
足底 `z=0`、米制，清理孤立点与退化面，减面到 599,417 tri（原 1,498,548，约 -60%），
导出单网格保留 UV 的 clean GLB（53,974,948 bytes）。清理前后有三角面、材质、包围盒、
非流形/退化面和多视图渲染对比（`export_audit.json` required 24/24）。

**二、绑骨。** Phase 2 的 Mixamo Auto-Rigger 三次上传全部卡在服务端 `Processing upload`，
未进入 marker 页面。改用 **Make-It-Animatable**（Gradio 5.50.0）完成绑骨，服务真实地址
`http://21.6.90.117:7860/`；该主机**不在本机网卡上**（经 `utun6` 可达），因此使用者给出的
`127.0.0.1:7860` 当时没有监听，需先建立端口转发
（`tools/art/port_forward_mia_7860.py`），或给驱动脚本传
`--base-url http://21.6.90.117:7860/` 直连。
该服务接受 `.glb` 输入，因此 599,417-tri 的 clean 网格**直接绑骨**：不经过低面代理件，
也不存在事后权重转移。产出 22 根 Mixamo 兼容骨（`mixamorig:*`，无手指骨）。
服务为有状态会话：同一客户端内先 `/pipeline` 绑骨、再 `/vis_blender` 逐 clip 取件，
四个 clip 必须来自同一次运行。

动作映射为 `idle=Idle.fbx`、`walk=Walking.fbx`、`run=Run.fbx`、`jump=Jump.fbx`，全部
`In Place=True`。**`Running.fbx` 被排除**：该库动画在本角色上 retarget 失败，脊柱持续前折，
网格高度从 1.76 m 塌到 0.65 m 并持续 37/77 帧；改用 `Run.fbx`（零塌陷帧）。这一判定由
`tools/art/score_mia_clip.py` 结构性预筛加
`tools/art/diagnose_cultivator_tripo_v9_actions.py` 逐帧高度确认，不靠目测。

**三、运行时资产。** 服务每个 clip 返回三个 slot，只有 FBX 同时带动画与法线
（`clip_*_slot1.glb` 缺 `NORMAL`，直接用会平面着色）。因此用 Blender 导入四个
`slot2.fbx`、把 action 重命名为精确 `idle/walk/run/jump`、导出单一 GLB，再用 clean GLB
的完整 PBR（baseColor + metallicRoughness + normal）替换 FBX 只带 baseColor 的材质。

地面偏移修正：Auto-Rigger 预测的骨架使角色整体下沉约 1.00 m，与本项目其它角色
（`cultivator_neutral_youth_v7` 脚在 y≈0.001、`cultivator_rigged` 在 y≈-0.0001）不一致。
在 glTF 层同时抬高场景根节点静态 translation **和** Armature 根节点的 translation 动画
采样器 Y 分量——只改静态值不够，因为导出器给该根节点烘焙了全零 translation 动画轨道，
动画会覆盖静态值，表现为「rest pose 正常但所有 clip 仍陷地」。

**三点五、步幅实测与疾行。** 滑步的根因是播放速率公式 `rate = 速度 / 参考速度` 里的参考
速度只是估计（1.6 / 3.2），而实际移动速度 4.0 m/s，使 walk 永远以 2.5 倍速播放、作者节奏
被破坏，且 5.5 的 run 阈值永远够不到（**run 是死分支**）。
新增 `tools/art/measure_clip_stride.py`：这些 clip 是原地的，因此正确量法是**支撑期内脚相对
身体的后移量**（等于步长），`natural_speed = step_length / stance_seconds`。实测 walk
1.288 m/s、run 3.426 m/s（落在真人步速区间，交叉验证方法正确）。
据此：`move_speed` 4.0 → **1.55**、新增 `sprint_speed` **3.45**（Shift 疾行）、
`RUN_SPEED_MPS` 5.5 → **2.2**、速率夹取 0.5–2.5 → **0.6–1.8**。
参数 `walk_stride_meters` 更名 `walk_reference_mps`——契约是 `rate = speed / 该值`，
它是**速度**不是长度，旧名具误导性（本轮一度据旧名把长度填了进去）。
疾行只在确有移动输入时生效。

**四、Godot 接入。** 新增独立 `cultivator_tripo_v9_visual.tscn`（根 `CultivatorVisualTripoV9`
→ 模型实例 `CultivatorTripoV9` + `CultivatorSkeletonPresentation`），默认 `swordsman.tscn`
改为实例化 v9 视觉，使所有经正式 Swordsman prefab 生成的移动实验自动统一；
`jade_paper_sample` 移除自己的 v7 特例替换；motion preview 通过共享视觉链复用同一 v9 场景。
`cultivator_skeleton_presentation.gd` 原样复用（它只按 clip 名查找，不依赖骨名）。
因导入的 clip 全部是 `LOOP_NONE`，表现层补一次显式循环设置（沿用
`kaykit_route_a_presentation.gd` 的先例）。

**五、库缺的姿态改为手工制作。** 库中没有打坐、负手而立、结印这类姿态，最近的几个也
气质不符。新增两个工具在**现有骨架**上手工摆姿态，而不是引入第二套骨架：

- `tools/art/author_cultivator_pose.py`：按骨骼局部欧拉角摆姿态，配一段轻微呼吸循环后
  导出为 `clip_<name>_slot2.fbx`，形状与 `build_cultivator_tripo_v9_runtime_glb.py` 的输入
  一致，因此手工姿态与下载姿态走完全相同的落地管线。
- `tools/art/solve_pose_targets.py`：给定链末端的目标世界坐标，用坐标下降反解骨骼角度
  （带关节限位，防止用脱臼姿势去够目标）。

**为什么需要求解器**：手调欧拉角会失败，且失败只在渲染里才看得出来。实测
`LeftArm` 绕 X +45° 让手向**外上方**走（+X/+Z），不是直觉以为的「前抬」；
因此按直觉写的负 X「后旋」实际把手举到了头顶（本轮第一次渲染就是这样）。
求解器把这类错误变成可测量的误差数字。

**骨架能力的硬边界**：22 骨、**无手指骨**，所以掐诀/结印的**指印**做不出来，
只能到「手叠手」这一层。这条写进工具的 `MISSING_BY_DESIGN` 并在报告里输出，
不假装能做。腿、脊柱、腕、肘、肩全部可摆，因此打坐盘腿与负手而立可做。

已制作三个姿态（`iterations/authored_poses/`，渲染见 `renders/authored/`）：

| 姿态 | 状态 | 求解误差 |
|---|---|---|
| `meditate_seat` 盘腿打坐 | 可接受：腿交叠、手叠于腹前 | 手臂 3.6–4.4 cm |
| `hands_behind_back` 负手而立 | 可接受：双手背后交叠、身姿端正 | 1.0–1.1 cm |
| `sword_riding` 御剑而立 | 已修正：改为**复用负手角度**（负手御剑才是修士标志姿态），上身前倾、膝屈、并足 | 同负手 1.0–1.1 cm |

**三个姿态已接入运行时**（Phase 6）。`cultivator_tripo_v9.glb` 现含七段：
核心四段 `idle/walk/run/jump` + 手作三段 `idle_guarded`（负手而立）/`meditate`（盘腿打坐）/
`sword_ride`（御剑而立）。接入时修掉三个真问题，都属「看起来能跑、其实无效」一类：

1. **物体级位移被导出器丢弃**：把下移写在 armature **object** 的 location 上完全无效，
   FBX/glTF 都不保留 armature 节点 transform（实测下移 −0.7238 m 后往返导入回到原高度）。
   改为写在**根骨 Hips 的 location** 上，它是姿态数据，随动画导出。
2. **根骨的「上」不是 Z**：实测 `location.Y+=1.0` 抬高 0.0098 m、`location.Z+=1.0` 只抬高
   0.0021 m（骨静止矩阵旋转了平移轴）。按直觉写 Z 或「除以 0.01」都得到无效修正。
   改为**数值求解有效轴**（逐轴探测单位响应再缩放），残差 0.00000 m。
3. **不能把姿态最低点归零**：构建脚本随后会按站立 clip 抬高整个场景根（≈ +1.012 m，
   对所有 clip 一视同仁），author 阶段归零会被再次抬高而浮空 1 米。应**对齐静止姿态的地面**。
   盘腿抬高轮廓 ≈0.72 m，故坐姿下移 0.72 m、站立类只微调 0.03 m——量级差异本身即修正正确的证据。

表现层新增可选接口：`has_state()` / `play_state()` / `release_state()`。
手作状态是**可选增量**：旧四段资产缺这些 clip 时表现层照常工作（`_configure_looping` 跳过缺失），
四段核心动作仍是硬前置断言。`play_state` 是显式覆盖且**不被速度推翻**（实测 9 m/s 仍保持打坐）
——「角色在打坐还是待机」属玩法层决定，表现层不替它判断。

## 备选方案

1. 直接把 75 MB 原始 GLB 接入 Godot —— 未验证朝向、网格和运行成本，且缺骨架与动作，否决。
2. 覆盖现役 `cultivator_neutral_youth_v7.glb` —— 会破坏探索资产保留与回退证据，否决。
3. 只替换青玉纸样板 —— 使用者要求全部角色移动实验统一，且继续保留多条视觉链会再次产生
   方向和动作不一致，否决。
4. 沿用旧角色的 Mixamo 骨架并强行套模型 —— 顶点权重与骨架不匹配，不能证明手脚、头发和
   衣装在动作中成立，否决。
5. 用有位移的动作 —— 会与 CharacterBody3D 物理移动叠加导致滑步和漂移，否决；四段动作
   必须原地。
6. 继续等待 Mixamo 服务恢复 —— 三次不同格式与体积的上传均在服务端停滞，没有可预期的
   恢复时间；本机已有等价能力且输入契约更宽（接受 `.glb`），否决继续等待。
7. 用低面代理件绑骨后把权重转回 clean 网格 —— 代理件衣摆与发片有明显三角塌陷，
   且权重转移本身是新引入的失败面；Make-It-Animatable 能直接吃 599K 网格，否决代理路线。
8. 只在 Blender 里移动 armature 来修正地面偏移 —— 导出器丢弃 armature 节点的静态
   translation，实测无效，否决。
9. 用服务直接返回的合并 GLB 作为运行时资产（纯 glTF 层面合并四个 `slot1.glb`）——
   结构上可行且保留完整 PBR，但没有法线；保留为对照方案，否决作为最终资产。
10. 为修仙姿态引入第二套骨骼（例如另找一个自带打坐的模型）—— 会得到两套骨架、两套
   动作命名与两条防滑标定，且现有角色的权重与气质都要重做；在同一骨架上手工摆姿态
   避免了这一切，否决换骨架。
11. 手工姿态改用纯手调欧拉角、不加求解器 —— 实测会失败（臂轴方向与直觉相反，
   「后旋」写成负 X 把手举到了头顶），且错误只在渲染里可见；求解器把误差变成数字，
   否决纯手调。
12. 把根骨下移写在 armature **object** 上 —— 导出器丢弃 armature 节点 transform，实测无效，
   否决；必须写在根骨 Hips 的 location 上。
13. 把姿态最低点归零来修浮空 —— 构建脚本随后会按站立 clip 抬高场景根，两者叠加会浮空 1 米；
   应改为对齐静止姿态的地面，否决归零。
14. 御剑姿态另解一套手臂角度 —— 负手御剑本就是修士标志姿态，复用已解好的负手角度既省一次
   求解又更贴气质，另解一套只会得到两个不一致的手部姿态，否决。
15. 御剑继续沿用 `idle@0.6 + 节点前倾` 占位实现 —— 既然已经手作了专门的御剑而立姿态，
   继续用占位等于「有资产没用法」；且该姿态自带前倾，比抬速的 idle 更贴语义，否决沿用。
16. 御剑时既用 `sword_ride` 又叠加 `flight_lean` 节点前倾 —— 姿态脊柱已前倾，再叠 0.21 rad
   会变成弯腰；前倾只能来自一处，否决叠加。

## 后果

- 运行时资产 `src/game/actors/swordsman/models/cultivator_tripo_v9.glb`，77,065,808 bytes，
  599,417 tri，单 Skeleton3D（22 骨）、单 AnimationPlayer（4 clip 精确名）、单 material
  （3 × 4096² 贴图）。实测 idle/walk/run 逐帧最低点 ≥ +0.011 m 不陷地，jump 腾空 +0.44 m。
- 全部移动实验、motion preview 与青玉纸样板改用 v9 人物；v1–v8、旧长袍、v7 中性底座与
  全部分件视觉保留为回退与故障对照资产，零删除、零覆盖。
- `Running.fbx` 这类「服务能返回但实际坏掉」的动作说明：绑骨服务不会为 retarget 质量兜底，
  必须有一套结构性判据。`tools/art/score_mia_clip.py` 与
  `tools/art/diagnose_cultivator_tripo_v9_actions.py` 因此成为该链的一部分，而不是一次性
  调试脚本。
- 骨骼无手指骨；`loop_mode` 导入后为 `LOOP_NONE`，由表现层运行时显式设置；
  3 × 4096² 纹理在 `gl_compatibility` 下约 192 MB RGBA，尚未做实机内存/帧率测量。
- 动作气质是**取舍而非客观正确**：库中最接近东方气质的是 `Breathing_Idle`/`Warrior_Idle`
  （立如松），并无真正的「打坐」「掐诀」「踏剑」姿态可用；`Ninja_Idle` 偏武术架势、
  `Focus`/`Praying` 语义不符。若后续要真正的修仙动作，需要外部动作库或手工制作，
  这不是换一个 Mixamo 名字能解决的。
- 步幅实测值依赖当前 30 fps 导出与这套骨架；换 clip 或改帧率需重跑
  `tools/art/measure_clip_stride.py`，否则滑步会回来。
- 手工姿态只到「肢体姿态」这一层：无手指骨意味着**结印、掐诀、剑诀**这些以手型为核心的
  修仙动作做不出来。若这些是必需表现，需要先给骨架加手指骨并重绑权重，那是另一轮工作。
- `sword_ride` 已接管真实御剑飞行（Phase 7）：`flying` 时自动选用该姿态并按原速播放，
  不再叠加节点前倾（姿态自带前倾，叠加会弯腰）。旧四段资产退回 `idle@0.6 + 节点前倾`，
  `flight_lean` 因此仅服务于该回退路径。
- 另外两个手作状态（`idle_guarded` 负手而立、`meditate` 盘腿打坐）仍只经
  `play_state()` 显式驱动，**没有场景自动使用**。要让角色真的坐下来打坐，需要一个实验场景
  或玩法规则去调用；表现层不替玩法决定何时进入这两个状态。
- 手工姿态的关节限位是人工设的合理范围，不是解剖学精确值；求解结果需渲染复核，
  不能只看误差数字（误差小不代表姿态自然）。
- 探索资产体积显著增加仓库大小（v9 目录约 1.2 GB）。使用者已明确选择「所有项目资产必须
  进入 Git」优先于仓库体积，因此不做忽略或外部存放。

台账见 `docs/art/cultivator_tripo_v9/asset_ledger.md`「Phase 3」。
