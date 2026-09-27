# 清俊少年动画底座 v7（cultivator_neutral_youth_v7）资产台账

日期：2026-09-19 ｜ 生成脚本：`tools/art/build_cultivator_neutral_youth_v7.py`（一次运行可复现）
依据：`notes/proposed/art/2026-09-19-neutral-youth-animation-base-v7.md`

## 本轮定位

**中性动画底座，不是最终角色美术。** 不含交领、腰封、袍摆、袖袍、护腕、绑腿，
不含硬板发片；不做头发（保留底座头部，明确标记为临时）。运行时只用于验证走/跑/跳/
御剑状态，后续完整角色交给 3D 生成流程。

## 来源与许可

- 人体与骨架：**Generic Anime Male**，作者 jonshipman，Sketchfab CC-BY-4.0。
  未改原件 `docs/art/cultivator_neutral_youth_v7/source/generic_anime_male_original.blend`，
  SHA-256 `a58cb67a0451b9198692e75385259dd8c72c914ea4c49e44e205ce34d986cc2a`（本轮未改动）。
- 动作：旧四动作骨架 `docs/art/cultivator_jade/cultivator_rigged.blend` 的
  `idle` / `walk` / `run` / `jump`（Mixamo 来源，见该目录台账）。**未上传 Mixamo。**

派生链：`generic_anime_male_original.blend` → `cultivator_neutral_youth_v7.blend` → `cultivator_neutral_youth_v7.glb`。
v2–v6 与现役 `cultivator_rigged.glb` 均未被覆盖或删除。

## 产物

| 文件 | 说明 |
|---|---|
| `docs/art/cultivator_neutral_youth_v7/cultivator_neutral_youth_v7.blend` | v7 源文件（65 变形骨 + 4 子网格 + 4 action） |
| `docs/art/cultivator_neutral_youth_v7/cultivator_neutral_youth_v7_neutral_body.png` | 深靛遮挡层贴图 2048²（从源身体贴图派生，已 packed） |
| `docs/art/cultivator_neutral_youth_v7/build_manifest.json` | 构建期全部回读证据（见下「回读」） |
| `docs/art/cultivator_neutral_youth_v7/renders/` | 四视图、脸/脚尖特写、四动作姿态截图 |
| `docs/art/cultivator_neutral_youth_v7/source_textures/` | 原件打包贴图导出（取证用） |
| `src/game/actors/swordsman/models/cultivator_neutral_youth_v7.glb` | 运行时 GLB（skin 65 joints + 4 clips） |
| `src/game/actors/swordsman/cultivator_visual_neutral_youth_v7.tscn` | Godot 视觉场景 |

GLB SHA-256：`d8f489d1ef0ac8c73f327d67d46e138313a4ce933d96565ac9d9da54dad4ff8d`（以 manifest 为准，重建会变）。

## 回读证据

- **GLB**：`skins=[{name: CultivatorNeutralYouthV7, joints: 65}]`，
  `animations=[idle, jump, run, walk]`，每 clip 195 通道，
  属性含 `JOINTS_0` / `WEIGHTS_0`，导出 `export_yup=True`（Blender -Y 正面 → Godot +Z 正面）。
- **遮挡层**：9762 面中覆盖 4617 / 过渡 1099 / 露皮肤 4046；躯干+骨盆露皮肤 **0**；
  顶点 5445、面 9762、包围盒位移 **0.0 m**（逐位不变，不增加轮廓）。
- **动作**：整数帧端点误差 **2e-6 m**（构造侧 1e-6），半帧同为 2e-6 m。

## 踩坑（全部实测，改前必读）

1. **同名骨不能直接拷贝动作。** 两套骨架 65 根骨同名，但审计实测 64 根共有骨里
   37 根 rest 局部朝向差 >5°，最大 **179.3°**（`mixamorig:LeftHand`）。
   直接拷 pose 会得到扭曲姿态。见「重定向」。
2. **控制骨删除会改变父级链。** 原件有 168 骨（含 103 根 `Ctrl_*` / `*_IK_*` 非
   deform 骨）。`mixamorig:RightArm` 的父骨在原件里是 `Ctrl_ForeArm_FK_Right`，
   在旧四动作骨架里是 `mixamorig:RightForeArm`。跨骨架换算必须走各自的
   **变形骨父级链**，不能借用对方的父级。
3. **Blender 丢弃 `use_connect=True` 骨骼的 pose location。** 这是本轮最隐蔽的坑：
   构造侧误差 1e-6 m，但经 Blender 求值后四个动作统一残留 **0.068 m**。
   根因是 v7 骨架需要 0.068 m 级关节补偿平移，而这些平移恰好落在
   `RightArm`/`LeftArm`/`RightShoulder`/`Spine2` 等连接骨上被丢弃。
   解法：`enable_pose_translation()` 断开全部 14 根连接骨（rest 位置位移 0.0 m）。
4. **四元数双覆盖。** `to_quaternion()` 符号任意，相邻帧符号相反对分量线性插值会
   穿过原点，姿态被放大成米级偏移（`run` 实测 2.18 m）。必须逐帧对齐符号。
5. **`keyframe_insert` 会留下单点。** 建 action 结构后要把每个通道清空再写完整帧表，
   否则插入的首点会与目标序列首尾相接，插值穿过中间所有值（实测 2.68 m 偏移）。
6. **作者控制骨带 82 条约束。** 删除控制骨后这些 `COPY_TRANSFORMS` 会失效并污染
   姿态，必须连同约束一起删。
