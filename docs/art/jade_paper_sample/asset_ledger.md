# 资产台账 · jade_paper_sample

## 一句话

青玉纸白样板（第一轮实施）美术资产：**亭 / 松 / 岩为腾讯混元 3D（hy-3d 文生 3D）生成 + 本地 Blender 5.2.1 归一与调色**，
**台基 / 台阶 / 铺装 / 收边为 AI 代理脚本 + Blender 程序建模**。逐资产的生成 job_id、复现脚本与本目录源文件见下表。
依据：[实施 note](../../../notes/proposed/art/2026-09-19-jade-paper-sample-implementation.md)。

## 条目

| 字段 | 值 |
|---|---|
| 资产名 | `jade_pavilion`（六角亭）/ `jade_pine`（松）/ `jade_rock`（山岩）/ `jade_sample_terrain`（台基+台阶+铺装+收边） |
| 来源 | 亭/松/岩：混元 3D 生成（几何 + 烘焙贴图），Blender 内仅缩放归一、Decimate 减面、贴图乘法调色；地形：AI 代理脚本 + Blender 程序建模。无素材库下载 |
| 混元 job_id | 亭 `1492584116846845952` · 松 `1492582230114689024` · 岩 `1492582225773854720`（腾讯云 hy-3d，2026-09-19） |
| 生成/处理脚本 | `tools/art/build_jade_sample_terrain.py`（地形）；`tools/art/process_jade_hunyuan.py`（混元后处理，含色卡与分段规则） |
| 原始产物 | `hunyuan_raw/{pavilion,pine,rock}_raw.glb` + `*_preview.png`（混元原样，只读对照） |
| 源文件 | 本目录 `jade_{pavilion,pine,rock}.blend`、`jade_sample_terrain.blend` |
| 运行输出 | `src/levels/experiments/character_movement/jade_{pavilion,pine,rock}.glb`、`jade_sample_terrain.glb`（新文件名，未覆盖任何旧资产） |
| 生成日期 | 2026-09-19 |
| 生成方式声明 | 亭/松/岩含 AI 生成几何与贴图（腾讯混元 3D）；地形为程序原创。不在台账内做平台政策结论 |
| 导出器 | Khronos glTF Blender I/O（Blender 5.2.1 自带），`export_yup` |
| 轴向 | 正面朝 Blender +Y 建模，export_yup 后为 Godot -Z/-Z 语义（地形台阶朝 Godot +Z 为刻意，见脚本头注释） |

## 数值（2026-09-19 读数，GLB JSON 直读）

| 产物 | 网格 | 三角形 | 材质 | 贴图 | 字节 | sha256 |
|---|---|---|---|---|---|---|
| `jade_pavilion.glb` | 1 | 79,999 | 3（瓦/木/石） | 3 | 7,012,192 | `d7c1be574a7f0dbcee021dd438f0c6b1f5deb7e88988d6649badaada6eb9e338` |
| `jade_pine.glb` | 1 | 39,994 | 2（冠/干） | 2 | 4,616,456 | `b32455a7aa0c2bd8040195917cc2e75ede65bb2521f91cf6d21f6390d9cc1d51` |
| `jade_rock.glb` | 1 | 30,000 | 1（青灰） | 1 | 1,638,424 | `5f741ea67dc06e210545750f72712502a229a33f647aa4d833406e6bc9d63ed0` |
| `jade_sample_terrain.glb` | 11 | 696 | 5（压顶/立面/砖/收边/踏面） | 0 | 44,888 | `25274ec95ea37375491e20553c6f5a4fcca61e7d86b69684505e035f64ae8c06` |

尺寸归一：松高 6.0 m、岩高 2.2 m、亭高 4.6 m（置于 0.6 m 台基上顶约 5.2 m）；底面 z=0、xy 居中。

## 调色（线性值，混元件为贴图乘法系数目标）

| 段 | Godot albedo（显示口径） | 说明 |
|---|---|---|
| 青玉瓦 tile | (0.013, 0.147, 0.102) 线性 | 亭顶 |
| 暖棕木 wood | (0.132, 0.060, 0.020) 线性 | 亭柱/松干 |
| 深松绿 foliage | (0.024, 0.085, 0.045) 线性 | 松冠（比 #1F3D2B 提亮一档保冠内可读） |
| 青灰岩 stone | (0.112, 0.144, 0.162) 线性 | 岩石/亭基座 |
| 地形五段 | 见 `build_jade_sample_terrain.py` TARGETS_DISPLAY | Godot albedo 显示口径，导出前 srgb_to_linear 预补偿 |

## 关键约束（本轮实测踩坑，后续必读）

- **glTF 导出器不导出 MixRGB 乘法节点**：材质调色必须烘进贴图像素（`_bake_tinted_image`），否则 `baseColorFactor` 丢失、回退原始贴图色。
- **Godot 导入器把 glTF `baseColorFactor` 做 linear→sRGB 转换后写入 albedo**（实测 0.434→0.690，精确吻合 `linear_to_srgb`）：程序建模色卡必须按"Godot albedo 显示口径 → srgb_to_linear 预补偿"导出，否则整体曝光洗白一档（上一轮"纸白被洗白"的机制层根因）。
- **Godot 从 GLB 抽取的 `*_tex.png` 是运行时依赖不是垃圾**：删掉会让 `.scn` 加载失败（本轮实测）；必须入 Git。
- **远景盘 CylinderMesh 中心 vs 顶面**：1 m 高圆柱中心放 y=-0.2 → 顶面 +0.3，会盖住地面与铺装；必须保证顶面低于地面（现 -0.71 → 顶 -0.21）。
- **`from_pydata` 手排顶点两次踩坑**（蝴蝶结面 / 法线异常）：铺装改用 `bmesh.ops.create_cube` 逐砖生成再合并。

## 与旧资产的替代关系

| 新资产 | 替代/关系 | 旧资产状态 |
|---|---|---|
| `jade_pavilion/pine/rock/sample_terrain.glb` | 样板场景专用，不替代任何旧资产 | `mountain_realm*.glb`、`cultivator.glb`、`flying_sword.glb` 原样保留，sha256 未变 |

## 未完成 / 未验证项

- 审美结论归使用者：样板状态 exploring，使用者视觉确认前不宣称方向通过。
- 亭的生成件为六角攒尖（非四角），方向 note 未限定角数，样板阶段接受。
- 人物与飞剑本轮零改动（核对已合规），实机观感随样板一并交使用者确认。

## 第二轮条目（2026-09-19 上午）

| 字段 | 值 |
|---|---|
| 新增资产 | `jade_mountain`（远山）/ `jade_gate`（山门牌坊）/ `jade_lantern`（石灯笼）/ `jade_bamboo`（竹丛）/ `jade_grass`（草簇，程序）/ `cultivator_jade`（人物 v2） |
| 混元 job_id | 远山 `1492711808166518784` · 山门 `1492711810679128064` · 灯笼 `1492713095788756992` · 竹丛 `1492713098065993728` · 人物 `1492713977825722368` |
| 源文件 | 本目录 `jade_{mountain,gate,lantern,bamboo}.blend`、`jade_grass.blend`；`docs/art/cultivator_jade/cultivator_jade.blend` |
| 运行输出 | `src/levels/experiments/character_movement/jade_{mountain,gate,lantern,bamboo,grass}.glb`；`src/game/actors/swordsman/models/cultivator_jade.glb`（+同名贴图 PNG 为 Godot 抽取的运行时依赖，必须入 Git） |
| 处理脚本 | `tools/art/build_jade_grass.py`（草）；`tools/art/process_cultivator_jade.py`（人物切割） |

## 第二轮数值（GLB JSON 直读）

| 产物 | 网格 | 三角形 | 材质 | 贴图 | 字节 | sha256 |
|---|---|---|---|---|---|---|
| `jade_mountain.glb` | 1 | 50,000 | 1 | 1 | 2,434,780 | `41fd33de964c8915d4cc5841edfefc2724164dbabeeb380386593d8ed3195545` |
| `jade_gate.glb` | 1 | 80,000 | 1 | 1 | 3,785,864 | `8c5216c28442c3537ecd2e17e4d8b6ef4f17a38f269c98bc0856fb720af53104` |
| `jade_lantern.glb` | 1 | 29,999 | 1 | 1 | 1,871,424 | `ae7eed049238b14a783fb1394cb9b3a2c287c4ea438a358c2597af86397e7b2b` |
| `jade_bamboo.glb` | 1 | 40,000 | 1 | 1 | 2,324,516 | `4b3fa63998c2ea6657498541b931cb8a803c0af45b47554c65d1eda9b1e99758` |
| `jade_grass.glb` | 1 | 54 | 1 | 0 | 4,008 | `4948913ff941bd4f9399dbbff7db12150f9bf4d22ffd95bb254cc384efbdc962` |
| `cultivator_jade.glb` | 16 | 34,013（Decimate 0.45 后） | 3 | 1 | ~8 MB | `045403040cde7afbe75cf1fe8f65e30f017e50c491ebf0a751545e72fa1e6b2c` |

人物 v2 分件：`Leg_L/R` + `Foot_L/R`、`Arm_Sleeve_L/R` + `Cuff_L/R` + `Hand_L/R`、
`Robe_Skirt/HemBand/Panel`（13 摆动件契约）+ `Robe_Upper`（躯干+头静件）+ `Shoulder_Cap_L/R`（遮肩缝）。
头/发/脸并入 Robe_Upper（同静件，避免颈缝）。高 1.75 m（7 头身）。旧 `cultivator.glb` sha256 不变。

## 第二轮踩坑补充

- **正交视野边界**：pitch -38.7° 正交下 35 m 外一切被雾吞没（fog 0.0035@100 m≈30%，
  与天空同调即隐形）；近距高墙（45 m 混元远山）会占满整帧。远山甜点 = 台基正后方
  25–45 m、6–10 m 矮山包（多轮标定，摆位常量含注释）。
- **混元人物切割**（`process_cultivator_jade.py`）：bisect 前必须 `select_all`（op 只作用于
  选中顶点）、切后 `separate(LOOSE)`（bisect 不分离）、只切包围盒跨越切面的碎片
  （否则碎片 2^N 爆炸）；join 按去偶基名分组（Blender 重名自动 .001 后缀）；
  踝切线必须低于靴筒顶（0.06H 切不开 → Foot 缺失 → 表现层断言失败）。
- 遮缝策略实测有效：腰缝靠贴图自带腰带（静侧）覆盖、肩缝靠扁肩垫覆盖、髋缝藏裙内；
  无需额外腰封环（烘焙腰带已跨缝，加环反而突兀）。

## 第三轮条目（Mixamo 真骨骼角色，2026-09-19）

| 字段 | 值 |
|---|---|
| 资产 | `cultivator_rigged`（蒙皮角色 + Skeleton3D + AnimationPlayer，clips=[idle,jump,run,walk]） |
| 来源 | 自产模型（cultivator_jade 合并单网格 OBJ）经 Mixamo Auto-Rigger 绑骨（**标记点由使用者人工拖放**）+ Mixamo 动画库 4 clip 下载；Blender 组装 + 袍子权重锁定 |
| 动画 | Walking（skin=true）/ Idle / Running / Jump Up，inplace=on，fbx_unity 30fps |
| 上传源 | 本目录 `cultivator_jade_for_mixamo.obj`（6.0 MB）/ `.fbx`（16 MB，备用） |
| 源文件 | `docs/art/cultivator_jade/cultivator_rigged.blend`（3,329,954 bytes；sha256 `e71cf47423d1082952b931cebd74cb8137e09b41a0e29b1c65c24b799baa1174`） |
| 归档源 | `cultivator_rigged_pre_side_fix.blend`（交叉绑肢故障对照；sha256 `904e1170e1b60e186ad9a9f7926c066bd8b717bfce26b763fca3dd635b955143`）；`cultivator_rigged_side_fix_pre_validation.blend`（左右已修、生成器断言落地前；sha256 `43988a77af2dcab5d014cf8af166129992edd80fd46bf9bcd9603f0f8ac1561e`）；二者不得用于运行时 |
| 运行输出 | `src/game/actors/swordsman/models/cultivator_rigged.glb`（3,304,672 bytes；sha256 `911fd380333b85fc3f66a2b9303140cb63f20638f2a94d81eefa4cba8f16e843`；+抽取贴图 PNG 为运行时依赖） |
| 三角形/骨骼 | 34,013 tris（Decimate 后）；mixamorig 骨架约 65 骨 |
| Godot 验证 | AnimationPlayer clips=[idle,jump,run,walk]，Skeleton3D ×1，walk 实播通过（probe） |
| 驱动脚本 | `projects/mixamo-mcp/mixamo_driver_phase{1,2,3}.py`（上传绑骨/下载/组装；phase1 标记步为人工） |
| 接入状态 | **资产就绪，场景接入下一轮**（cultivator_visual_rigged.tscn + 骨骼驱动表现层） |
| 权重锁定 | 袍子岛仅保留 Hips（外袍刚体挂髋等效）；按 Mixamo 静止骨架坐标 `+X=Left/-X=Right` 为腿/袖保留同侧完整骨链（含手指子链）；躯干/头不动 |
