# Tripo 修仙角色 v9（cultivator_tripo_v9）资产台账

日期：2026-09-19 ｜ 生成脚本：\`tools/art/process_cultivator_tripo_v9.py\`（一次运行可复现，两阶段）
依据：\`notes/proposed/art/2026-09-19-cultivator-tripo-v9-runtime.md\`（**proposed**；本台账只覆盖 Phase 1，不代表运行时接入已获批）

## 本轮定位与边界

**Phase 1 只做：归档 → 导入审计 → 朝向归一 → 网格清理 → 分区减面 → 导出上传候选 → 可审查证据。**
本轮**不含** Mixamo 上传/绑骨、不含骨架与动画、**不改 \`src/\`**、**未提交 Git**。

已完成 / 未完成：

| 项 | 状态 |
|---|---|
| raw 逐位归档 + SHA 校验 | 完成 |
| 朝向证据与归一（-Y 正面 / 足底 z=0 / 米制） | 完成 |
| 网格清理、分区减面、UV 与贴图保留 | 完成 |
| clean.blend / clean.glb / Mixamo FBX+OBJ / OBJ 目录 | 完成 |
| 16 张渲染 + 方向证据 + 前后对照 | 完成 |
| 独立进程重新打开并审计 | 完成（24/24 required 通过）|
| Mixamo 上传 + 人工标记 + 自动绑骨 | **未开始（Phase 2）** |
| 运行时 GLB（\`idle/walk/run/jump\`）与 v9 视觉场景 | **未开始（Phase 3）** |
| Git 提交 | **未提交**（按本阶段要求）|

## 来源与许可

- 原始模型：使用者提供的 \`docs/art/9b092e988c21840611f833788e4e4e9a.glb\`，78,881,664 字节，
  SHA-256 \`69ed3a5b9a6279fd4756212c5ab43e25521fefbbc12baaed150d8e6dfd031627\`。
  **根原件本轮未删除、未修改**（\`source_still_present: true\`，哈希逐位一致）。
- 生成器署名：\`Khronos glTF Blender I/O v4.0.43\`；原始 GLB 无 \`skins\`/\`animations\`/\`cameras\`。
- **作者、版权与商用许可状态未知。** 参考 GLB 由使用者直接提供，本仓无来源 URL、无 license 文件、
  无授权声明。**不得声称这是本仓原创设定，也不得在未确认授权前作为可商用素材使用。**
  本仓原创的部分仅为清理/减面/导出流程脚本与台账；模型本体权利状态待使用者确认。

## 原始模型审计（导入时实测）

| 项 | 值 |
|---|---|
| 场景 / 节点 / 网格 / primitive | 1 / 1 / 1 / 1 |
| 材质 / 贴图 / 图像 | 1 / 3 / 3（全部内嵌 PNG）|
| 三角面 | **1,498,548** |
| 顶点 / 多边形 | 889,030 / 1,498,548 |
| UV 层 | \`UVMap\` 1 层，u/v 均在 [0,1] 内（越界 0）|
| 顶点色 | 无 |
| 骨骼 / 动画 / 相机 | 0 / 0 / 0 |
| 贴图 | 3 × 4096²（baseColor / metallicRoughness / normal），baseColor **alpha 全为 1.0**（无镂空发片）|
| 节点变换 | 源文件 \`node_0\` 带 +90°X 四元数；glTF 导入器计入 \`matrix_world\`，导入后需 apply |
| 原始包围盒 | x[-0.2882, 0.2880] y[-0.1218, 0.1606] z[0.0000, 1.1470]，高 **1.1470 m** |
| 扩展 | \`KHR_materials_specular\`（非 required）|

## 朝向判定（几何/材质证据，非包围盒猜测）

判定方法写在脚本 \`orientation_evidence()\`：在**世界坐标**下量三组证据。
（注意：只用 mesh 局部坐标会在 OBJ/FBX 往返时得出错误结论——本轮修过这个测量口径的 bug。）

| 证据 | 实测（原始尺度） | 结论 |
|---|---|---|
| 头部中线 \`|x|<0.025\` 的 y 跨度 | [-0.0948, +0.0886]，跨度中点 -0.0031，**鼻子在 -0.0948** | 脸朝 **-Y** |
| 最低 2 cm 内脚尖 y 范围 | [-0.1218, +0.0414] | 脚趾朝 **-Y**（鞋跟 +Y）|
| 躯干带 (z 0.60–0.90) 顶点数 | +Y 侧 48,899 ｜ -Y 侧 9,022 | 发量/背部在 **+Y** |
| 前视渲染（相机置于 -Y） | 看到正脸、前襟、靴面 | 视觉确认 |

**因此模型导入后已经面朝 Blender -Y，实际施加的旋转量 = 0°。** 不为了「看起来在做修正」而强加旋转；
\`normalize_orientation()\` 仍显式执行 \`transform_apply(location/rotation/scale)\` 并把旋转量记入 manifest。

### 尺寸归一

原始高 1.1470 m，但人体比例是成年人（约 6.0 头身、成人脸型/肩宽/腿长），
1.147 m 不满足「合理米制身高」，按契约要求归一：

- 均匀缩放 ×**1.52573104**（保留比例，不做非均匀拉伸），目标身高 **1.750 m**
- 与本仓现役运行时角色 v7（1.7447 m）同量级，可直接接入
- 缩放的代价：相对原始模型，表面点位移 p50 = 0.71 mm / p95 = 6.01 mm / max = 19.30 mm（2.005 m 体对角线基准）
- **原始 1.1470 m 尺度完整保留在 \`raw/\` 与 \`source/*_imported.blend\`**，可回溯对比

## 清理与减面

### 清理（\`clean_mesh()\`，作用于最终拓扑）

| 动作 | 前 | 后 |
|---|---|---|
| 孤立点（无面相连） | 161 | 0 |
| 松散边（无面相连） | 82 | 0 |
| 零面积面 | 0 | 0 |
| 重复面（同顶点集合） | 0 | 0 |
| 非有限坐标 | 0 | 0 |
| 顶点 | 430,322 | 331,669 |
| 非流形边 | 252,922 | 101,141 |

**保守焊接阈值 1.0e-5 m（10 µm）**：依据是焊接前最短边 **5.19e-5 m**，
阈值只占最短边的 **19.3%**——不会焊死唇缝、指缝或衣片。
焊接合并 98,492 个重复点（merged_verts），这是顶点从 430,322 降到 331,669 的主因（减面已先降过一轮）。

**非流形边 101,141 条仍未归零**：原模型是「多层衣装 + 独立发片 + 薄壳」的典型生成网格，
本就非水密。本轮不需要水密（Mixamo 不要求），**未做强制封闭**，避免产生新的穿插或法线错误。
法线已统一：\`bmesh.ops.recalc_face_normals\` 作用于全部面。

### 减面（\`decimate()\`，分区掩码，非全局一刀切）

**策略**：不用全局固定数字，而是给「不可塌陷区」建可达掩码——
用**顶点组 + \`Decimate(COLLAPSE)\` + \`invert_vertex_group=True\` + \`vertex_group_factor=1.0\`**
（实测该组合下权重 1.0 = 完全保护），掩码只保护关键区，其余自由几何承受 collapse。

| 保护区 | 判据（面中心，原始 1.1470 m 尺度） |
|---|---|
| 脸 + 前发 | \`z ≥ 0.925\` 且 \`y ≤ 0.045\` |
| 双手 | \`|x| ≥ 0.235\` 且 \`0.45 ≤ z ≤ 0.80\` |
| 靴子/双脚 | \`z ≤ 0.10\` |

阈值按身高比例换算，跨尺度稳定。受保护顶点 195,649 个。

| 区域 | 减面前 | 减面后 | 结论 |
|---|---|---|---|
| **合计** | **1,498,548** | **599,418** | **−60.00%**（契约要求 ≥40%）|
| 脸+前发 | 145,460 | 144,970 | 保留 99.7% |
| 双手 | 76,248 | 76,043 | 保留 99.7% |
| 双脚/靴 | 89,700 | 89,594 | 保留 99.9% |
| 自由几何（躯干/衣装/后发） | 1,187,140 | 288,811 | 压到 24.3%（collapse ratio 0.40）|

自由几何的 collapse ratio = **0.40**（在掩码之外生效）。

**轮廓偏差**（原始点云到清理后网格的最近距离，body 对角线 2.005 m）：

| p50 | p95 | p99 | max |
|---|---|---|---|
| 0.71 mm | 6.01 mm | 9.21 mm | 19.30 mm |

### 减面参数是实测选出来的，不是猜的

脚本参数由 \`iterations/_decimate_probe/\` 的扫描确定：同一模型上渲染 0.50 / 0.40 / 0.30 三档的
头部、手、靴、后发、侧视、3/4 头部特写逐一目视比较。
**0.40 档（−60%）在脸/手/靴/后发/衣装轮廓上与原始无法分辨**；0.30 档（−70%）开始出现
后发分缕边缘与衣摆轮廓的可辨磨损，因此**未采用更激进的目标**。
（\`iterations/_decimate_probe/\` 保留全部扫描渲染作为取舍证据。）

## 产物

### 源文件

| 文件 | 字节 | SHA-256 |
|---|---|---|
| \`source/cultivator_tripo_v9_imported.blend\` | 87,426,687 | （见 manifest）原始状态存档，含原始几何与内嵌贴图 |
| \`source/cultivator_tripo_v9_clean.blend\` | 24,563,411 | \`b0f893059e99daafae5f888d9301441ac348dbeb40b92eccbbbcbb1f513e775f\` |

### 导出

| 文件 | 字节 | SHA-256 |
|---|---|---|
| \`exports/cultivator_tripo_v9_clean.glb\` | 53,974,948 | \`749fe625e4ef4c2f133eae4f7d64f65942d9e9f625385c62214cb9492299faba\` |
| \`exports/cultivator_tripo_v9_mixamo_upload.fbx\`（**标准上传件**，Z-up / 面朝 -Y） | 22,127,948 | \`83f543f3153c43475939d0856fb686001e05bbd91aaa30167f8a126069853275\` |
| \`exports/cultivator_tripo_v9_mixamo_upload_yup.fbx\`（optional 备用，Y-up / 面朝 -Z） | 22,127,948 | \`f070e209d4811d8dc06076bc92200f412acc9d34f5a7db5278624f0fc55203a6\` |
| \`exports/mixamo_upload_obj/cultivator_tripo_v9_mixamo_upload.obj\`（**标准**，Z-up） | 64,912,801 | \`f289f1f17eb94e86f09e6252c09a31969903c21f6da5b7ae308ecd83589a266a\` |
| \`exports/mixamo_upload_obj/cultivator_tripo_v9_mixamo_upload_yup.obj\`（optional 备用） | 64,913,081 | \`0ce8c4954552b92bd18fe58aced87c828b76a6eca56f6b20dbaaa2e50b21d2f6\` |
| \`exports/mixamo_upload_obj/*.mtl\` + 同目录 2 张 PNG | — | 见 manifest |

### 贴图（从 GLB 内嵌解包）

| 文件 | 尺寸 | 字节 |
|---|---|---|
| \`textures/texture_pbr_20250901.png\`（baseColor） | 4096² | 16,909,976 |
| \`textures/texture_pbr_20250901_metallic-texture_pbr_20250901_roughness.png\` | 4096² | 8,274,929 |
| \`textures/texture_pbr_20250901_normal.png\` | 4096² | 7,805,984 |

clean.blend 中三张图均为 \`//../textures/...\` **相对路径**，重开可解析（审计实测 true），不再 packed。

## 回读证据（独立进程 \`-- audit\` 重新打开产物）

**24/24 required 全部通过**（\`export_audit.json\` 的 \`required_all_passed: true\`）。

| 断言 | 实测 |
|---|---|
| raw 副本 SHA 与根原件一致 | 双向一致：raw = source = \`69ed3a5b…\` |
| clean.blend 恰好 1 网格，0 armature/skin/action/camera/light | 1 对象 / 1 网格；四类均为 0 |
| clean.blend UV 存在 | 1 层 \`UVMap\`，越界 0 |
| clean.blend 纹理相对路径可解析 | 3/3 true |
| clean.blend 足底 z≈0 | 0.000000000 |
| clean.blend 面朝 -Y | nose_y = -0.1447，toes_y ∈ [-0.1859, +0.0631] |
| clean.glb 1 mesh / 1 primitive | 1 / 1 |
| clean.glb 属性 | \`NORMAL\` / \`POSITION\` / \`TEXCOORD_0\` |
| clean.glb 0 skin / 0 animation / 0 camera | 0 / 0 / 0 |
| clean.glb 重新导入 | foot_z = 0.000000，高 1.7500 m，面朝 -Y |
| upload.fbx 1 网格，0 armature/action/camera/light | 通过 |
| upload.fbx 重新导入 | foot_z = 0.000000，高 1.7500 m，面朝 -Y，UV 1 层 |
| upload.obj 1 网格 + UV，足底≈0，面朝 -Y | 通过 |
| 14 张必需渲染 | 全部存在且非空 |
| 三角面下降 ≥40% | **−60.00%** |
| 脸/手/靴保护区未塌陷 | 99.7% / 99.7% / 99.9% |
| 非有限坐标 | 0 |

### optional / non-blocking

- \`*_yup.{fbx,obj}\` 是**备用上传件**（Y-up / 面朝 -Z，对应本仓已通过 Mixamo 的
  \`mcp/mixamo/kaykit_route_b_prepare.py\` 约定），**不是 Phase 1 硬前置**。
- 已知口径问题：OBJ 往返会把轴向表达为**导入矩阵**而不是烘焙进顶点，
  早期审计用局部坐标判定朝向因此误报；已改为世界坐标判定。
  FBX 一对（Z-up 与 Y-up）在重新导入后**都**通过 foot_z≈0 与面朝判定。
- 结论：**标准 Z-up OBJ/FBX 是唯一需要交付的上传件**；Y-up 件保留备用，其未通过项不影响 Phase 1 验收。

## 渲染证据（manifest 记录 16 个条目，磁盘 18 个 PNG）

- **16 个条目**：14 张正式证据 + \`orientation_proof\` 的 2 张单图原稿
  （\`_persp\` / \`_top\`，由合成图拆分而来，不计入条目）。
- **before/after 顺序已核验**：\`original_*\` 三张在减面**之前**渲染（代码里 \`render_original_trio()\`
  先于 \`decimate()\`），与对应 \`clean_*\` 的 SHA-256 两两不同，确认不是同图重命名。

| 文件 | 内容 |
|---|---|
| \`original_front/side/back.png\` | **清理前**（已入自动流程：在减面之前渲染）|
| \`clean_front/side/back.png\` | 清理后正交三视图 |
| \`clean_three_quarter_front/back.png\` | 3/4 正交 |
| \`clean_head_closeup.png\` | 头部特写 |
| \`clean_hand_closeup.png\` / \`clean_foot_closeup.png\` | 手 / 靴特写 |
| \`clean_hands_feet.png\` | 合成：左手 \| 靴子 \| 3/4 全景（垂直居中留边，不重采样）|
| \`clean_gray_front.png\` | 无贴图灰模，只看轮廓与法线 |
| \`orientation_proof.png\` | 坐标轴证据：**红=-Y（正面）/ 绿=+X / 蓝=+Z**，地面写 FRONT/BACK，附俯视图 |
| \`orientation_proof_persp.png\` / \`_top.png\` | 上图的单张原图 |
| \`comparison_front.png\` / \`comparison_side.png\` | 左原始 \| 右清理后，同尺度同机位 |

### 逐图目视结论（人工，非脚本判定）

- **comparison_front**：左右在脸、发、交领、腰饰、衣摆、靴形上无法分辨；减面未造成可见塌陷
- **clean_side**：鼻梁/下颌线连续；长发为独立发片且边缘完整；袍摆下缘金纹未糊
- **clean_back**：后发仍成缕、尖角清晰；袍摆中线开衩与云纹刺金完整
- **clean_head_closeup**：眼睛（上下眼睑/瞳孔/高光）、鼻翼、唇线、眉毛、额际碎发均保留；无「糊脸/空洞」
- **clean_hands_feet**：手指分缝、指甲缘、指节可见；靴面金线、缝线、鞋底厚度完整
- **clean_gray_front**：灰模下轮廓连续无破面、无明显的减面棱角、无穿模
- **orientation_proof**：透视图中红色箭头（-Y）从人物正面伸出、绿色 +X 指向人物右手侧、
  蓝色 +Z 向上；地面 \`FRONT\` 标签位于 -Y 一侧、\`BACK\` 位于 +Y 一侧；
  **右图俯视确认人物鼻尖朝图像下方（即 -Y）**——即面朝 Blender -Y，符合 Mixamo 契约
- **未运行的文件**：本轮未产出 128/256 px 游戏尺度缩略图（Phase 1 未要求）；
  \`orientation_proof_persp.png\` / \`_top.png\` 是 \`orientation_proof.png\` 的两张单图原稿，一并保留

## 已知限制与未验证项

1. **非流形边 101,141 条**：多层衣装/发片的固有薄壳结构，本轮不追求水密。
2. **自由几何压到 24.3%**：躯干与衣装在 p99 上有 9.2 mm、最大 19.3 mm 位移，
   近距特写（<10 cm）理论上仍可能看出；本轮渲染机位下不可辨。
3. **材质 1 个、贴图 3 张 4096²**：未做纹理降采样。若运行时体积吃紧，
   下一阶段可在 Phase 3 再决定是否降到 2048²（本轮以保真为先）。
4. **未做 UV 重排**：沿用原始 \`UVMap\`，仅验证在 [0,1] 内且越界 0。
5. **未做骨骼/权重**：本轮不产生任何 skeleton/skin；「动作友好」仅为静态几何承诺
   （A-pose、腋下/胯下留净空），**未在 Mixamo 实机验证**。
6. **身高 1.75 m 是本流程的主动选择**（原模型 1.147 m），已在 manifest 记录缩放因子与理由；
   若后续要求「保持原始绝对尺度」，需回退到 \`imported.blend\` 重新导出。
7. **未接运行时**：\`src/\` 零改动；v9 尚未进入任何 Godot 场景。
8. **版权未知**（见「来源与许可」）——上传 Mixamo 前建议使用者先确认该 GLB 的授权状态。

## Mixamo 上传的剩余人工步骤（Phase 2，本轮未开始）

1. **人工**：在浏览器登录 Mixamo（登录态失效时跑 \`mcp/mixamo/login_once.py\`）。
2. 上传 \`exports/mixamo_upload_obj/cultivator_tripo_v9_mixamo_upload.obj\`
   （或 \`exports/cultivator_tripo_v9_mixamo_upload.fbx\`）。
3. **人工**：Auto-Rigger 的下巴 / 双腕 / 胯部 / 双脚踝标记**必须人工拖放**
   （\`mcp/mixamo/screens/upload.py\` 明确标注不支持自动化），共 3 步 Next。
4. 脚本轮询到绑骨完成，\`status\` 确认角色名与 T-pose。
5. 下载 \`Walking\`(带 skin) / \`Idle\` / \`Running\` / \`Jump Up\`，**inplace=on**，fbx_unity 30fps。
6. 下载物与 Mixamo 原始结果作为 v9 独立源资产保存入库。

**上传硬前置自检（Phase 1 已满足）**：单网格 ✅ ｜ 保留 UV ✅ ｜ 无骨架/动画/相机/灯光 ✅ ｜
米制 ✅ ｜ 足底 z=0 ✅ ｜ 面朝 Blender -Y ✅ ｜ 纹理可解析 ✅

## 不纳入交付的文件（**已保留，未删除**）

| 文件 | 建议 | 理由 |
|---|---|---|
| \`source/*.blend1\`（2 个，共 ≈112 MB） | 不纳入 Git | Blender 自动生成的上一版备份，非探索资产、可再生；内容与对应 \`.blend\` 仅差一次保存。**保留在磁盘**，如需可删。 |
| \`iterations/_engine_probe/\`（688 KB） | 可保留 | 渲染引擎可用性探测（EEVEE/Cycles/Workbench），是本次排版取舍的证据 |
| \`iterations/_decimate_probe/\`（38 MB） | **建议保留并入库** | 减面档位选择的直接证据（0.50/0.40/0.30 逐区渲染），支撑「为何选 0.40」 |
| \`iterations/_unpack_probe/\`（119 MB） | 不纳入 Git | 贴图解包语义与 FBX 往返的临时探测件（含原始尺度 FBX 53 MB + 16 MB PNG），结论已固化进脚本与台账，属中间产物 |

> 依据仓规「探索资产不得删除」：以上**一律未删除**；是否入库由主代理决定。
> \`iterations/\` 下三个 \`_*_probe/\` 与本轮正式产物是**不同性质**的（探测 vs 交付），
> 故未与正式渲染混放。

## 复现命令

\`\`\`sh
# 全流程（raw 校验 -> imported/clean blend -> 导出 -> 16 张渲染 -> manifest）
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python tools/art/process_cultivator_tripo_v9.py

# 独立审计（新进程重新打开 clean.blend / clean.glb / upload.fbx / upload.obj）
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python tools/art/process_cultivator_tripo_v9.py -- audit
\`\`\`

全程使用 \`--background --factory-startup\` 隔离进程，**未操作或污染使用者当前 Blender 会话**。

---

# Phase 2 · Mixamo 绑骨上传（进行中）

## 上一轮失败记录（保留，不掩盖）

| 项 | 内容 |
|---|---|
| 上传件 | \`exports/cultivator_tripo_v9_mixamo_upload.fbx\`（**标准件**，599,417 tri / 22.1 MB，sha \`83f543f3153c4347…\`）|
| 结果 | Mixamo Auto-Rigger 长时间停在 **"Processing upload"**（约 15 分钟未进入 marker 页）|
| 页面状态 | \`STATE review Processing upload Your character is processing. This should take less than half a minute.\` |
| 浏览器活性 | Edge 主进程 + GPU 进程持续占用 CPU（实测 +3s/+1.5s CPU 时间 per 10s），说明**在跑但未完成**，非浏览器崩溃 |
| 处置 | 判定为本轮失败证据，**不再原样重复**；改为派生的低面代理上传件 |

## 低面绑骨代理件（**proxy-only，非最终运行时视觉**）

派生脚本：\`tools/art/build_cultivator_tripo_v9_lowpoly.py\`（两阶段 build / audit，从 \`clean.blend\` 派生，不覆盖任何 Phase 1 产物）。

| 项 | 值 |
|---|---|
| source | \`source/cultivator_tripo_v9_clean.blend\`（599,417 tri，sha \`b0f89305…\`，审计确认未被覆盖）|
| \`source/cultivator_tripo_v9_lowpoly.blend\` | 见 \`lowpoly_manifest.json\` |
| **\`exports/cultivator_tripo_v9_mixamo_lowpoly.fbx\`** | **216,774 tri / 8.16 MB**（<15 MB 达标）|
| 三角面 | 216,774（目标区间 180k–250k ✅，较 clean −63.8%）|
| 减面 ratio | 0.3617（**二分自动标定** 6 次收敛，目标 215k，实测差 +1,820）|
| 身高 / 足底 | 1.750000 m / z = 0.000000000（减面后 1.749870 m，线性归位 Z 轴修正，非放宽断言）|
| UV / 材质 | \`UVMap\` 1 层，越界 0；1 材质；纹理相对路径 3/3 可解析 |
| 单网格 / 骨架 | 1 mesh，**0 armature / 0 action / 0 camera / 0 light**（blend 与 FBX 重开双重确认）|
| 朝向 | 面朝 Blender −Y（nose_y = −0.1447，toes_y ∈ [−0.18586, +0.0631]）|
| 轮廓偏差 | p95 = 7.99 mm（相对 clean）|
| 独立审计 | \`lowpoly_audit.json\`：**15/15 required 通过** |

### 保护分级（不再把 31 万面全部锁死）

| 级别 | 判据（原始尺度换算） | 面数 |
|---|---|---|
| 核心保护 w=1.0 | 脸+前发 \`z≥0.905 且 y≤−0.020\`；手 \`|x|≥0.300\`；脚 \`z≤0.058\` | 143,392 |
| 软保护 w=0.30 | 发际/衣摆外轮廓、前臂、靴筒 \`z≤0.120\` | 200,231 |
| 自由 | 其余（躯干、后发、衣装主体） | 255,794 |

### ⚠️ 用途限制（主代理视觉审查结论）

**该 lowpoly 网格仅作为 Mixamo 绑骨代理，禁止直接作为最终运行时视觉。**

主代理视觉审查：面部与手尚可，但**衣摆、内衫、裤面与部分发片存在明显三角塌陷/破碎感**（参照
\`renders/lowpoly_front.png\`、\`lowpoly_back.png\`、\`lowpoly_hem_closeup.png\`）。

**Phase 3 强制要求**：取得带皮肤 rig 后，必须把**骨架与权重转移/重建到 599,417-tri clean mesh**，
再以 **clean-quality 网格**导出最终 runtime GLB；并必须做动作渲染验证穿插与权重，
不得直接把 lowpoly 网格当作运行时资产。

### 低面新增渲染

\`lowpoly_front/side/back.png\`、\`lowpoly_head_closeup.png\`、\`lowpoly_hand_closeup.png\`、
\`lowpoly_hem_closeup.png\`、\`lowpoly_comparison_front.png\`（左 clean ｜ 右 lowpoly）、
\`lowpoly_comparison_head.png\`。

## Phase 2 复现命令

\`\`\`sh
# 低面代理件构建 + 独立审计
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python tools/art/build_cultivator_tripo_v9_lowpoly.py
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python tools/art/build_cultivator_tripo_v9_lowpoly.py -- audit

# 上传（人机协作；marker 必须人工拖放）
cd mcp/mixamo && .venv/bin/python mixamo_driver_phase1.py \
  ../../docs/art/cultivator_tripo_v9/exports/cultivator_tripo_v9_mixamo_lowpoly.fbx
\`\`\`

## 尝试 3：OBJ + MTL + 纹理 ZIP（仍未到达 marker 页）

按指示改用 OBJ 路径重试（不经 FBX）。打包脚本：\`tools/art/export_cultivator_tripo_v9_mixamo_zip.py\`（两阶段，独立审计 14/14 通过）。

| 项 | 值 |
|---|---|
| 打包目录 | \`exports/cultivator_tripo_v9_mixamo_obj/\` |
| OBJ | \`cultivator_tripo_v9_mixamo.obj\`，22.96 MB（米制 / Z-up / 正面 −Y / 三角化）|
| MTL | 引用 \`texture_pbr_20250901.png\`（map_Kd）+ \`texture_pbr_20250901_normal.png\`（map_Bump），**仅 2 张必需纹理** |
| **ZIP** | **\`exports/cultivator_tripo_v9_mixamo_upload.zip\`，30,644,169 B**，4 条目，CRC 全通过 |
| 独立重导入 | 1 网格 / 0 armature·action·camera·light / **216,774 tri**（与 lowpoly 一致）/ UV 越界 0 / 1.750000 m / foot_z 0.000000 / 面朝 −Y ✅ |
| 审计 | \`mixamo_obj_audit.json\`：**14/14 required 通过**；Phase 1 四件旧资产 SHA 全部确认未被覆盖 |

> 注：ZIP 30.64 MB 未满足「<15 MB」——该阈值原是给**二进制 FBX**（低面件 8.16 MB，已达标）定的；
> OBJ 是文本格式，同网格天然约为 FBX 的 3 倍。故记录体积、**不**用错误阈值判失败（标 optional）。

**结果：再次停在 \`Processing upload\`，6 分钟上限内未进入 marker 页，按指令停止。**
证据：\`iterations/phase2_upload_attempts/attempt_03_obj_zip.log\`。

## 三次尝试横向对比（结论倾向：Mixamo 会话/服务端问题）

| # | 格式 | 体积 | 三角面 | 结果 |
|---|---|---|---|---|
| 1 | FBX 标准件 | 22.1 MB | 599,417 | \`review\` 卡住 ~15 min，未到 marker |
| 2 | FBX 低面件 | 8.16 MB | 216,774 | \`review\` 卡住 ~12 min，未到 marker |
| 3 | OBJ+MTL+纹理 ZIP | 30.64 MB | 216,774 | \`review\` 卡住 6 min（上限），未到 marker |

三种**完全不同的格式与体积**（8–31 MB，二进制与文本）都停在服务端同一阶段，且
\`Uploading...\` → \`Processing upload\` 的**上传本身每次都成功**。若是模型问题，预期页面报错
（如 \`unable to map skeleton\`）或卡在上传阶段；实测是**上传成功、服务端处理不返回**。
登录态正常（\`LOGGED_IN True\` / \`Session active\`）。

**因此更可能是 Mixamo 会话或服务端侧问题**（Auto-Rigger 服务排队/故障、账号授权或额度），
而非本侧上传件问题。未做也不应由本 agent 做的验证：更换账号、重新登录、等待服务恢复——需人工判断。

## ⚠️ 最终目标未变（Phase 3 硬约束）

lowpoly 网格**仍为 proxy-only**，禁止作为最终运行时视觉。取得带皮肤 rig 后，
**必须把骨架与权重转移/重建到 599,417-tri \`clean\` mesh**，再以 clean-quality 网格导出
runtime GLB，并做动作渲染验证穿插与权重。

---

## Phase 3 — Make-It-Animatable 绑骨与四动作（2026-09-21）

### 路线变更：Mixamo → Make-It-Animatable

Phase 2 的三次 Mixamo Auto-Rigger 上传全部卡在服务端
`Processing upload`，未进入 marker 页面（见 Phase 2 台账）。本轮改用 **Make-It-Animatable**
（Gradio 5.50.0）完成绑骨，服务真实地址 `http://21.6.90.117:7860/`。

**注意它与本机不是同一台机器**：`21.6.90.117` 不在本机网卡上（本机为 `10.31.67.55` /
`192.168.255.10`），经 `utun6`（网关 `192.168.255.10`）可达。因此**直接访问
`127.0.0.1:7860` 不通**——使用者给的是这个地址，但当时该端口没有监听。
本轮用端口转发把它映射上来：`tools/art/port_forward_mia_7860.py`
（纯 TCP 双向转发，`127.0.0.1:7860` → `21.6.90.117:7860`）。
`tools/art/mia_rig_cultivator_tripo_v9.py` 默认就用 `http://127.0.0.1:7860/`；
也可用 `--base-url http://21.6.90.117:7860/` 直连而完全不需要转发。
转发进程一旦退出需重新建立，不影响已产出的资产。

该服务与 Mixamo 的关键差异：**输入接受 `.glb`**，因此 599,417-tri 的 clean 网格直接绑骨，
不需要低面代理件，也不需要事后权重转移——handoff 中「把 Mixamo 骨架/权重转回 clean mesh」
这一步被整条消除。22 根 Mixamo 兼容骨（`mixamorig:*`，无手指骨）。
服务是**有状态**的：一次客户端会话内先 `/pipeline` 绑骨，再 `/vis_blender` 逐个取动作；
四个 clip 必须来自**同一次运行**，否则骨架/权重不一致。

### 输入

| 项 | 值 |
|---|---|
| 文件 | `exports/cultivator_tripo_v9_clean.glb` |
| bytes | 53,974,948 |
| sha256 | `13d64374...`（全量见 `cleanup_manifest.json`） |
| 面数 | 599,417 tris，单网格，UV 保留，1.75 m，足底 z=0，Blender 正面 -Y |

### 服务参数（全部固定，无人工干预）

`No Fingers=True`、`Input Rest Pose=No`、`Input Rest Parts=[]`、`Input is GS=False`、
`Opacity Threshold=0.01`、`Use Normal=False`、`Weight Post-Processing=True`、
`Bone Name of Weight Visualization=LeftArm`、`Reset to Rest=True`、
`Retarget Animation to Character=True`、`In Place=True`。

### 动作映射与选型

| 逻辑 clip | 服务库动画 | 时长 | 采样 | 选型依据 |
|---|---|---|---|---|
| `idle` | `Idle.fbx` | 4.033 s | 121 帧 | 默认；髋部 Y 跨度 0.027 m，根位移 0 |
| `walk` | `Walking.fbx` | 1.433 s | 43 帧 | 默认；髋部 Y 跨度 0.041 m，根位移 0.004 m |
| `run` | **`Run.fbx`** | 0.767 s | 23 帧 | **替换**；默认 `Running.fbx` 绑骨失败，见下 |
| `jump` | `Jump.fbx` | 2.200 s | 66 帧 | 默认；髋部 Y 跨度 0.406 m（起跳位移，正常） |

**`Running.fbx` 必须排除**：该库动画在本角色上 retarget 失败，脊柱持续前折，
网格高度从 1.76 m 塌到 0.65 m 并持续 37/77 帧（`renders/v9_actions/run_*` 可见）。
用 `tools/art/score_mia_clip.py` 结构性预筛（髋部 Y 跨度 0.632 m、单帧最大旋转 141.8°）
并用 `tools/art/diagnose_cultivator_tripo_v9_actions.py` 逐帧高度确认。
备选 `Run.fbx` / `Sprint.fbx` 零塌陷帧，最终取时长更贴近正常跑步的 `Run.fbx`；
四个候选的对照渲染在 `renders/run_candidates/`。

### 运行时 GLB 构建（三步，全部可复现）

1. `tools/art/mia_rig_cultivator_tripo_v9.py` — 驱动服务：一次会话内 `rig` + 四个 clip，
   原始产物落 `iterations/mia_rig/<stamp>/`（每 clip 三个 slot + manifest + sha256）。
   最终一致会话：`iterations/mia_rig/20260921-ship/`。
2. `tools/art/build_cultivator_tripo_v9_runtime_glb.py`（Blender 5.2.1）— 导入四个
   `clip_*_slot2.fbx`，重命名为精确 `idle/walk/run/jump`，导出单一 GLB 并做地面对齐。
   **必须走 FBX 而非服务返回的 GLB**：`slot1.glb` 缺 `NORMAL`（FBX2glTF 转换丢失），
   导入后平面着色；`slot2.fbx` 同时带 `LayerElementNormal` 与动画。
3. `tools/art/splice_cultivator_tripo_v9_material.py` — 用 clean GLB 的完整 PBR
   （baseColor + metallicRoughness + normal）替换 FBX 只带 baseColor 的材质。

### 两个必须记录的坑

- **服务 GLB 缺法线**：`clip_*_slot1.glb` 的 `attributes` 只有
  `JOINTS_0/POSITION/TEXCOORD_0/WEIGHTS_0`，无 `NORMAL`，而 `clip_*_slot0.glb` 与
  `slot2.fbx` 都有。直接用 slot1 会得到平面着色。
- **地面偏移**：Auto-Rigger 预测的骨架使角色**整体下沉约 0.98–1.00 m**（脚尖在 z≈-0.98），
  与本项目其它角色（`cultivator_neutral_youth_v7` 脚在 y≈0.001、
  `cultivator_rigged` 在 y≈-0.0001）不一致，直接接入会陷入地面。
  修正方式：在 Blender 里量出各 locomotion clip 逐帧最低点取最小值（`jump` 排除，
  否则会被腾空帧带偏），再在 **glTF 层**同时抬高场景根节点静态 translation **和**每个
  Armature 根节点的 translation 动画采样器 Y 分量。
  只改静态值不够——导出器给 Armature 根节点烘焙了全零 translation 动画轨道，
  动画会覆盖静态值，表现为「rest pose 正常但所有 clip 仍陷地」。

### 产出与验收

| 项 | 值 |
|---|---|
| 运行时 GLB | `src/game/actors/swordsman/models/cultivator_tripo_v9.glb` |
| bytes | 77,065,808 |
| sha256 | `87707b3f5382325f48bf8cafa79d63b5950067f993d100ba27a44ed57a23b14c` |
| 面数 | 599,417 tris（顶点 432,587） |
| 骨架 | 1 × Skeleton3D，22 骨，`mixamorig:*` |
| 动画 | 1 × AnimationPlayer，4 clip 精确名 `idle/walk/run/jump` |
| 材质 | 1 material，3 texture（baseColor 4096², metallicRoughness 4096², normal 4096²） |
| 地面 | idle/walk/run 逐帧最低点 ≥ +0.011 m，无陷地；jump 腾空 +0.44 m |
| 朝向 | 建模正面 -Y → Godot +Z（与 v7 同路线，待实机确认） |

逐帧诊断：`iterations/mia_rig/20260921-ship/action_diagnosis.json`；
结构评分：`iterations/mia_rig/20260921-ship/clip_scores.json`；
构建报告：`iterations/mia_rig/20260921-ship/blender_build_report.json`；
材质拼接报告：`iterations/mia_rig/20260921-ship/material_splice_report.json`；
动作多视图渲染：`renders/v9_ship/`（4 clip × 正/侧/背 × 3 相位 = 36 张）、
`renders/run_candidates/`（4 候选对照）。

### 已知限制

1. 骨骼无手指骨（`No Fingers=True`）；手部为整体网格。
2. `loop_mode` 导入后全部为 `LOOP_NONE`，需在表现层运行时显式设置
   （沿用 `kaykit_route_a_presentation.gd` 的先例）。
3. 3 × 4096² 纹理在 `gl_compatibility` 下约 192 MB RGBA，未做实机内存/帧率测量；
   如需要可降到 2048²。
4. `jump` 为单次动作，表现层仅在 `!grounded` 时播放。

### 保留

Phase 1/2 的全部产物（`raw/`、`source/`、`exports/` 旧文件、`renders/`、
`iterations/phase2_upload_attempts/`）与 root 下原始 GLB 一律保留，未删除、未覆盖。
`exports/cultivator_tripo_v9_runtime.glb`（纯 glTF 合并路线产物，早期方案）同样保留为对照。

---

## Phase 4 — 动作气质重选、步幅实测与 Shift 疾行（2026-09-21）

### 为什么重选

Phase 3 的待机是 `Idle.fbx`：手臂松垂、身体微晃、下巴略抬，读起来是**西方剑士的随手站姿**，
与本项目的修仙者气质不符。本轮按「立如松、手收于体侧、肩平气沉」重选，并把同类候选全部
渲染对比后决策，而不是凭名字挑。

### 待机候选对比（渲染见 `renders/idle_candidates/`）

| 候选 | 姿态 | 结论 |
|---|---|---|
| `Idle.fbx`（Phase 3 现役） | 手臂松垂、重心偏、下巴抬 | **淘汰**：休闲西方式站姿 |
| `Standing_Idle.fbx` | 单臂抬起做手势、重心偏移 | 淘汰：更像口语化手势 |
| `Focus.fbx` | 双手抱头 | 淘汰：姿态与角色无关 |
| `Ninja_Idle.fbx` | 武术下蹲架势 | 淘汰：过「忍者」，与修士不符 |
| `Warrior_Idle.fbx` | 立如松、手垂体侧、头正颈直 | 可用，与下一项同气质 |
| **`Breathing_Idle.fbx`** | **立如松、手垂体侧、肩平、呼吸起伏** | **采用**：最贴合「站桩」，且时长 9.97 s 循环自然 |

### 御剑姿态：维持「站立 + 前倾」，明确否决两个候选

Phase 3 的御剑是 `idle @0.6 倍速 + 前倾`。本轮验证了两个「看起来更贴切」的候选并**否决**：

| 候选 | 实际内容 | 结论 |
|---|---|---|
| `Flying.fbx` | **超人式水平俯冲**（身体几乎水平、双臂前伸） | 淘汰：这是飞行/坠落，不是踏剑 |
| `Floating.fbx` | 漂浮/下坠姿态，双腿悬空张开 | 淘汰：同样不是踏剑 |

结论：`Flying`/`Floating` 都不表达「脚踏飞剑、身姿直立」，**现有站立+前倾方案本来就是对的**。
两个候选的渲染保留在 `renders/v2_final/` 与 `renders/fly_compare/`，作为否决依据。
`fly` clip 仍打进 `iterations/mia_rig/20260921-v2/` 作对照，但不进运行时资产。

### 步幅实测（新工具 `tools/art/measure_clip_stride.py`）

滑步的根因是「播放速率 = 实际速度 / 参考速度」里的参考速度此前是估计值（1.6 / 3.2），
而实际移动速度是 4.0 m/s，导致 walk 永远以 **2.5 倍速**播放、作者节奏被破坏。

这些 clip 是**原地**的（根不位移，位移由物理提供），所以正确量法是**支撑期内脚相对身体的
后移量**，它等于该步的步长，于是：

    natural_speed = step_length / stance_seconds

实测结果（30 fps）：

| clip | step | stance | stride(2 步) | **自然速度** | 支撑脚路径摆幅 |
|---|---|---|---|---|---|
| idle | — | — | — | **不迈步**（如实标注） | 0 |
| walk | 0.2147 m | 0.1667 s | 0.4294 m | **1.288 m/s** | 0.0087 m |
| run | 0.1141 m | 0.0333 s | 0.2282 m | **3.426 m/s** | 0 |

交叉验证：1.29 / 3.43 m/s 正落在真人步行（1.2–1.4）与跑步（3–4）区间内，说明量的是对的东西。
数值调用路径也改名以免误导：`walk_stride_meters` → `walk_reference_mps`
（契约是 `rate = speed / 该值`，它是**速度**不是长度；旧名让本轮一度把长度填了进去）。

### Shift 疾行（新输入）

| 项 | 值 | 依据 |
|---|---|---|
| `sprint_input` | bool，场景在按住 Shift 期间写入 | 与 `move_input` 同为输入，非状态 |
| `move_speed` | 1.55 m/s | 贴近 walk 自然速度 1.288；rate ≈ 1.20 |
| `sprint_speed` | 3.45 m/s | 贴近 run 自然速度 3.426；rate ≈ 1.01 |
| `RUN_SPEED_MPS` 阈值 | 5.5 → **2.2** | 取两档之间，使 Shift 真的切换 clip |
| 速率夹取带 | 0.5–2.5 → **0.6–1.8** | 实测步幅下 rate 已 ≈1.0，过宽上限只会变成快放 |

疾行只在**确有移动输入**时生效：站着按 Shift 不进入奔跑姿态（已加测试断言）。
接入场景：motion_stage、movement_garden、mountain_realm、sword_flight_course、
ground_contact_course、state_transition_lab（剑术训练场为飞行场景，疾行仅随地面段生效）。

### 产物

| 项 | 值 |
|---|---|
| 运行时 GLB | `src/game/actors/swordsman/models/cultivator_tripo_v9.glb` |
| sha256 | `79adbded1eafecd3f71a4bf164584d354ea024714828083dc5e805ca8e5b25b7` |
| 来源会话 | `iterations/mia_rig/20260921-v2/`（idle=Breathing_Idle, walk=Walking, run=Run, jump=Jump） |
| 候选会话 | `iterations/mia_rig/20260921-cand/`（10 候选）、`20260921-fly2/`（飞行候选） |
| 步幅报告 | `iterations/mia_rig/20260921-v2/stride.json` |

### 保留

Phase 1–3 全部产物零删除。本轮新增的候选会话、候选渲染、`Flying`/`Floating` 对照渲染
一并入库。被替换的 `Idle.fbx` 版本仍完整保留在 `20260921-ship/`（以及更早的 `final2/`）。

---

## Phase 5 — 手工制作的修仙姿态（2026-09-21）

### 动机

库中没有打坐、负手而立、结印这类姿态，最近的（`Ninja_Idle` 武术架势、`Focus` 抱头、
`Breathing_Idle` 立如松）只解决「站」，解决不了「坐」与「负手」。本轮在**现有骨架**上
手工摆姿态，不引入第二套骨架。

### 工具

| 工具 | 作用 |
|---|---|
| `tools/art/author_cultivator_pose.py` | 按骨骼局部欧拉角摆姿态 + 轻微呼吸循环，导出 `clip_<name>_slot2.fbx`（与下载姿态同形，走同一条落地管线） |
| `tools/art/solve_pose_targets.py` | 给定链末端目标坐标，坐标下降反解骨骼角度（带关节限位） |

**为什么必须有求解器**：实测 `LeftArm` 绕 X +45° 让手向**外上方**走（+X/+Z），
不是直觉的「前抬」。按直觉写成负 X「后旋」的结果是**双手举到头顶**（首次渲染即如此）。
求解器把这类错误变成可测量的厘米数。

### 骨架边界（实测）

22 骨：hips、3×spine、neck、head、2×(shoulder, arm, forearm, hand)、
2×(upleg, leg, foot, toe)。**无手指骨** → 掐诀/结印的**指印做不出来**，
只能到「手叠手」。此限制由工具在 `MISSING_BY_DESIGN` 中显式输出，不静默忽略。

### 产出

| 姿态 | 说明 | 手臂求解误差 | 状态 |
|---|---|---|---|
| `meditate_seat` | 盘腿打坐（半跏趺坐），手叠于腹前 | 3.6–4.4 cm | 可接受 |
| `hands_behind_back` | 负手而立，双手背后交叠 | 1.0–1.1 cm | 可接受 |
| `sword_riding` | 御剑而立，双脚并拢微前倾 | — | **未达标准，手臂需重解** |

文件：`iterations/authored_poses/clip_<name>_slot2.fbx`（各 28.2 MB，90 帧 @30fps，含呼吸循环）；
渲染：`renders/authored/<name>_{front,side,threequarter}.png`；报告：`*_report.json`。

### 与运行时的关系

**这三个姿态尚未接入运行时。** `cultivator_tripo_v9.glb` 仍是四段 `idle/walk/run/jump`。
它们是候选资产：要接入需再跑一次 `build_cultivator_tripo_v9_runtime_glb.py`
（把姿态目录作为 `--iteration`）并重新拼接材质。是否接入、接入到哪个场景，
属于玩法层选择，留给使用者决定。

### 保留

Phase 1–4 全部产物零删除。三个姿态的中间迭代渲染（含失败的「双手举顶」版本）保留在
`renders/authored/` 与求解报告 `*_solve.json` 中，作为「为什么需要求解器」的证据。

---

## Phase 6 — 手作姿态接入运行时（2026-09-21）

Phase 5 的三个姿态原为候选资产，本轮**接入运行时**，并修掉接入过程中暴露的三个真问题。

### 御剑姿态修正

Phase 5 的 `sword_riding` 两臂前伸，是西方飞行姿态的读法。改为**复用负手角度**——
负手御剑才是修士的标志姿态。差别只在体势：上身前倾迎风、双膝微屈吸震、双脚并拢立于剑上。
手臂角度与 `hands_behind_back` 同源（同一次反解结果，误差 1.0–1.1 cm）。

### 接入时暴露并修掉的三个问题

**1. 物体级位移被导出器丢弃。** 第一版把根骨下移写在 armature **object** 的 `location` 上，
导出后完全无效：FBX 与 glTF 导出器都不保留 armature 节点的 transform（glTF 侧写 `T=None`）。
实测证据：下移 −0.7238 m 后往返导入，姿态最低点仍回到 −0.2569，与下移前一致。
改为写在**根骨 `mixamorig:Hips` 的 location** 上——它是姿态数据，随动画一起导出。

**2. 根骨的「上」不是 Z，也不是简单除以 100。** 实测该骨
`location.Y += 1.0` 抬高 0.0098 m，`location.Z += 1.0` 只抬高 0.0021 m，
因为骨静止矩阵旋转了平移轴。按直觉写「Z 是上」或「除以 0.01」都会得到无效修正。
最终改为**数值求解有效轴**：逐轴探测单位响应，再按需缩放（3 次评估，对导入器的朝向选择免疫）。
求解后残差 0.00000 m。

**3. 不能把姿态最低点归零。** 构建脚本随后会把整个场景根抬高 −L（L = 站立 clip 最低点
≈ −1.01232），该位移对所有 clip 一视同仁；在 author 阶段归零会被再次抬高，浮空 1 米。
正确目标是**对齐静止姿态的地面**（`rest_lowest`），使手作姿态与站立 clip 处于同一竖直坐标系。
盘腿使轮廓抬高约 0.72 m，因此该姿态下移 0.72 m、站立类姿态只微调 0.03 m —— 这个量级差异
本身就是修正正确的证据。

### 运行时资产

| 项 | 值 |
|---|---|
| 文件 | `src/game/actors/swordsman/models/cultivator_tripo_v9.glb` |
| bytes | 77,513,468 |
| clip | `idle`(9.967s) `walk`(1.433s) `run`(0.767s) `jump`(2.200s) **`idle_guarded`(3.033s) `meditate`(3.033s) `sword_ride`(3.033s)** |
| 骨架 | 单 Skeleton3D，22 骨 |
| 材质 | 单 material，3 × 4096² PBR |

七个 clip 的地面接触实测（feet_y，越低越贴地；jump 腾空属正常）：

| clip | feet_y | 高度 |
|---|---|---|
| idle | +0.0373 | 1.798 |
| walk | +0.0189 | 1.796 |
| run | +0.0789 | 1.640 |
| jump | +0.4631 | 1.548（腾空） |
| idle_guarded | +0.0316 | 1.824 |
| **meditate** | **+0.0318** | **1.040（坐姿，故矮）** |
| sword_ride | +0.0319 | 1.845 |

`meditate` 修正前为 +0.7556（浮空 0.72 m），修正后 +0.0318，与其余姿态同量级。

### 表现层接口

三个手作状态是**可选增量**，不是核心契约：

- `has_state(clip) -> bool`：资产里有没有这个状态（旧四段资产返回 false）。
- `play_state(clip) -> bool`：显式覆盖当前状态；未知 clip 返回 false，不静默成功。
  覆盖期间**不被速度推翻**（实测 9 m/s 仍保持 `meditate`）——「角色现在是在打坐还是待机」
  是玩法层的决定，表现层没有依据替它决定。
- `release_state()`：解除覆盖，回到按速度自动选择（实测回到 `run`）。

`_configure_looping()` 对可选状态宽容（缺失即跳过），因此四段旧资产与新七段资产都能跑；
四段核心动作仍为硬前置断言。

### 实机证据

`docs/playtest/evidence/`：`v9-idle_guarded.png`、`v9-meditate.png`、`v9-sword_ride.png`，
由 `src/tests/v9_authored_state_playtest.gd` 在真实 `motion_stage` 场景中驱动并截图，
断言表现层快照与 AnimationPlayer 实际播放一致。截图可见打坐者坐于地面、御剑者立于地面。

### 保留

Phase 1–5 全部产物零删除。被替换的 `sword_riding` 旧版 FBX 与渲染仍在
`renders/authored/` 的历史迭代中；求解报告 `hand_solve.json`、`hands_behind_solve.json` 保留，
作为「为什么需要求解器」的证据。

---

## Phase 7 — 御剑姿态接管飞行（2026-09-21）

### 关闭遗留缺口

Phase 5/6 的 `sword_ride` 只能经 `play_state()` 手动驱动，而**真实的御剑飞行仍在用
`idle @0.6 倍速 + 节点前倾`** 这个占位实现——即「有资产没用法」。本轮让飞行状态直接采用
该姿态，占位实现退为旧资产的回退路径。

改动（`cultivator_skeleton_presentation.gd`）：

| 项 | 改前 | 改后 |
|---|---|---|
| `flying` 选用的 clip | `idle` | `sword_ride`（有该 clip 时） |
| 播放速率 | 0.6 | 1.0 |
| 节点 `rotation.x` 前倾 | `-flight_lean`（0.21 rad） | **0**（前倾由姿态自带） |
| 旧四段资产 | — | 退回原路径：`idle @0.6` + `-flight_lean` |

**为什么不再叠加节点前倾**：`sword_ride` 的脊柱本身已经前倾（髋 +9°、脊柱逐节累加），
再叠 0.21 rad 会变成弯腰。节点前倾因此只服务于回退路径——那条路径没有自带前倾，正需要它。
`flight_lean` 保留为导出参数并已在文档说明其仅用于回退。

### 实机验证

| 断言 | 结果 |
|---|---|
| 按 F 进入御剑状态 | PASS |
| 御剑时自动选 `sword_ride` | PASS（实际 `sword_ride`） |
| 不叠加节点前倾 | PASS（`rotation.x=0.0000`） |
| 落地回到 `idle` | PASS |

状态轨迹实测：`地面 idle,rot.x=0.0000` → `御剑 sword_ride,flying=true,rot.x=0.0000`
→ `关飞 idle,flying=false`。

截图：`docs/playtest/evidence/v9-sword_ride_flying.png`（HUD 显示「御剑=是 / 着地=否」，
人物以负手前倾姿态悬于空中）。

### 测试

`test_jade_paper_rigged_animation.gd` 的御剑断言改为**按资产实际内容分支**：有 `sword_ride`
时断言 `sword_ride` + 速率 1.0，没有时断言旧路径 `idle` + 速率 0.6。两种路径都被覆盖，
不写死单一期望值——写死会在换资产时产生假失败（本用例已如此失败过一次）。

`v9_authored_state_playtest.gd` 增补真实 F 键飞行的三条断言与一张截图。

1189 运行时测试通过。

### 保留

Phase 1–6 全部产物零删除。

---

## Phase 8 — 修掉继承来的躯干后仰与跑步转向（2026-09-22）

使用者报告「人物是斜的」。**第一次判断说这是等距机位造成的观感，错的**：正视图虽然对称，
侧视图显示躯干偏离脚踝铅垂线约 **12.5°**，是真实的后仰。等距视角下世界竖直仍渲染成屏幕竖直，
所以那个倾斜是角色的，不是机位的。

### 两个独立缺陷

| 缺陷 | 实测 | 性质 |
|---|---|---|
| 躯干后仰 | idle 12.81°、walk 5.98°、`idle_guarded` 12.49° | 自动绑骨**继承**来的：服务原产 `slot1.glb` 即为 13.86° |
| 跑步转向 | 髋部平均 yaw **+32.0°**，全程 [+22.7, +39.3] | `Run.fbx` 的 retarget 系统性转歪 |

其它 clip 的 yaw 都在 0 附近（idle +0.6 / walk −2.1 / jump −3.5 / sprint −2.1），
而 `Running.fbx` 达 +113.7°——同一批里三个候选都坏，说明这是逐 clip 的偶发问题，不是流程性错误。

### 修法一：跑步换 `Sprint.fbx`

`Sprint.fbx` 的 yaw 为 −2.1°（正常），且姿态本身是标准跑姿。`Run.fbx` 保留在
`20260921-v2/`、作为「转歪」的证据；`Running.fbx` 保留在 `20260921-final2/`。
`run` 参考速度随之重测为 **2.0305 m/s**。

### 修法二：躯干矫正写进构建期（不再走 FBX 往返）

第一版把矫正做成独立工具（导入 FBX → 改姿态 → 导出 FBX），**这是三个缺陷的来源**，
因为 Blender 的 FBX 导出器总会把 armature **物体**变换烘成一条动画轨道：

1. 下游地面位移对那条轨道**又加了一次**，角色浮空 1.09 m
   （实测 Armature 平移 +2.1066 m = 2 × 1.0533）。
2. 为阻止它而清空物体动画时**连骨骼动作一起清掉了**，构建报 `import produced no action`。
3. 试图用「重设基线」补偿，结果变成 3 倍（+3.1600）。

改为在**构建期、导出之前、内存中**矫正（`tools/art/cultivator_lean_fix.py`），
整类问题随之消失：没有中间文件可供导出器改写。

矫正本身用**数值求解**而非推导：探针测出哪条脊柱局部轴最能改变倾斜（本骨架是 `Spine` 的 X 轴，
−0.847 deg/deg），再用**区间线搜索**收敛。不能用导数步长——第一次矫正后重新探测会报告
「已跨越竖直」的响应，符号翻转，除下去会发散（实测 3.5 → 5.5 → 9.1 → 15.4 → 26.7 → 47.1 → 84.6°）。

目标不是 0：髋→头 连线本身就不是解剖学竖直（髋关节在脊柱后方），完全归零会显得僵直。
取 **1.6°** 残留。

### 结果

| clip | 矫正前 | 矫正后 |
|---|---|---|
| idle | +12.81° | +1.71° |
| walk | +5.98° | +1.83° |
| run | −21.63°（含跑姿前倾） | +1.34° |
| jump | −5.03° | +1.49° |
| idle_guarded | +12.52° | +1.71° |
| sword_ride | −4.58° | +1.31° |
| meditate | **原样保留** | 坐姿本就该折起，强行竖直会毁掉姿态 |

七个 clip 地面接触全部贴合（feet_y 0.059–0.096 m，`jump` 腾空 0.504 属正常）。

### 新增量具（本次能定位问题，靠的就是先有量具）

| 工具 | 作用 |
|---|---|
| `tools/art/measure_spine_axis.py` | 测髋→头 轴偏离竖直的角度与方向，FBX/GLB 均可 |
| `tools/art/measure_glb_upright.py` | 逐 clip 测 roll / pitch / yaw，判定「站歪」 |
| `tools/art/measure_clip_excursion.py` | 用脚相对髋的摆幅测步幅（支撑法对 17 帧短 clip 失效时用） |
| `tools/art/render_upright_check.py` | **画一条真实铅垂线**再渲染：把「是不是真的斜」变成一眼可判 |
| `tools/art/cultivator_lean_fix.py` | 构建期内存矫正（被 build 脚本导入） |
| `tools/art/score_mia_clip.py` | 新增**髋部 yaw 偏差**判据，负向控制：坏 run 判 BAD、好 clip 判 OK |

`render_upright_check.py` 是这次的关键——围绕骨骼坐标系反复推理给出了互相矛盾的结论
（四元数读作后仰、渲染看着直、等距视角看着斜），而画一条铅垂线让答案不再依赖推理。

### 其它修正

- `movement_garden.gd` 引用了未声明的 `KEY_SPRINT`，**整个脚本解析失败、场景加载不出来**。
  该场景自带输入表、不加载 `MovementLabInput`，因此本地声明该常量。
- `motion_stage` 默认机位由斜侧改为**正面**；斜侧下人物相对屏幕是斜的，容易被误读成人物站歪。
- 一批按旧速度（4.0 m/s）标定的测试阈值改为**从活动组件读取**，并按速度换算帧数预算
  （`frames_for_walk()`）。写死常量会在每次调速后产生假失败——本次实际造成
  `mountain_traversal_playtest` 11 条、`character_movement_playtest` 2 条、`camera_lab` 3 条。

### 保留

Phase 1–7 全部产物零删除。失败的中间迭代（`20260921-ship7-upright{,2,3,4}`、`lean_fix/`）
按探索资产保留规则留在原处，作为「为什么矫正必须写进构建期」的证据；`_hist_*.glb`
与 git 中对应版本逐字节一致，属冗余提取物。

## Phase 9 — 逐 clip 地面接触标定（2026-09-22）

使用者复查同一人物后反馈「依然是斜着的、不是踩着地面的」。**躯干层面确实已经竖直了**
（以骨盆为参考系的实测 3.12°；截图里躯干轴线离屏幕铅垂约 1.3°），因此这次的问题不在
Phase 8 修过的那一维。实测得到两个新的独立缺陷，其中只有前者本轮修掉。

### 缺陷一（已修）：角色整体浮空 4–7 cm

构建期的地面位移取「各 locomotion clip 最低点的**最小值**」。这个统计口径必然让**恰好一个**
clip 贴地、其余 clip 各自浮空 (自身最低点 − 最小值)。逐 clip 量最低蒙皮顶点：

| clip | 修正前 | 修正后 |
|---|---|---|
| `idle` | +0.0673 | −0.0000 |
| `walk` | +0.0410 | −0.0000 |
| `run` | +0.0168 | −0.0000 |
| `idle_guarded` | +0.0726 | −0.0000 |
| `meditate` | +0.0725 | +0.0000 |
| `sword_ride` | +0.0726 | −0.0000 |
| `jump`（腾空，不参与标定） | +0.0793 | +0.0793 |

对照：同仓 `cultivator_neutral_youth_v7` 与 `cultivator_rigged` 每个 clip 都在
**0.0072–0.0175**，即使用者已经接受的「踩着地面」基线。截图里的直接证据是脚底
**完全没有接触阴影**（阴影只落在身后地面），且两只靴子的整个鞋底都看得全。

修法：`apply_per_clip_ground_offset.py` 按量具报告逐 clip 施加 Y 位移。有根平移轨道的
四段（`idle`/`walk`/`run`/`jump`）改该轨道每个采样点；手作三段没有根平移轨道，**追加一条
常量平移通道**，让偏移随 clip 走。静态根保持 `[0.0, 1.05332, 0.0]` 不动——它决定
「没有 clip 驱动根平移」时（表现层 MANUAL 停帧、显式覆盖状态）的姿势，按某个 clip 的量
调小会让停住的姿势沉进地面。

### 缺陷二（已量、未修）：骨盆相对双脚前移

`measure_glb_balance.py` 新增的口径：骨盆水平投影到双脚中点的距离。
v9 为 **0.1544 m / 10.22°**，被接受的 v7 为 **0.0507 m / 3.12°**。躯干（髋→头）本身
读数正常，说明「上身在已位移的骨盆上被摆正」——这是 Phase 8 的矫正加在髋以上、而没管
骨盆位置的结果。

本轮**不修**：与被接受控件对比只能说「量级可疑」，没有一个等价的对照基线能确定正确目标值；
把未确认的目标值烘进姿态正是 Phase 5 手作姿态「按直觉写的后旋把手举到头顶」的同一类错误。
留量具与数字，等第二个人物或使用者目视确认后再决定。

### 量具与教训

| 工具 | 口径 |
|---|---|
| `measure_glb_ground_contact.py` | **权威**：逐 clip、逐帧的蒙皮网格最低顶点（含所需 Y 位移） |
| `measure_glb_foot_bones.py` | 骨骼级同一件事，用于给 Godot 测试定阈值 |
| `measure_glb_balance.py` | 骨盆相对双脚 / 骨盆相对头，分离「没站住」与「没竖直」 |
| `render_ground_contact.py` | z=0 平面 + 脚部近景 + 铅垂参考条，把米数变成一眼可判 |
| `apply_per_clip_ground_offset.py` | 逐 clip 施加位移（默认 dry-run） |

三条会得出错误结论的坑，都已在对应文件里写明：

1. **骨骼级 ≠ 顶点级。** 骨骼高度随脚部旋转变化：`run` 的摆动腿脚尖下压、`idle_guarded`
   双脚放平，两者都正确贴地时骨骼级差 0.10 m 而顶点级差 0。拿骨骼数字收紧「是否贴地」
   的判据，会得到一个在资产完全正确时失败的测试。
2. **`Icosphere` 陷阱。** Blender 导入任一 GLB 都会多出一个 42 顶点、不在场景图内的
   `Icosphere`；按位置取「第一个 mesh」会量到它并得到恒为 −1.0 的读数。
3. **换资产后必须重导。** Godot 导入缓存不新鲜时，测试会读到**上一版**资产的值，
   表现为「判据太严」的假失败——被测对象与测量对象不是同一份数据。

运行时回归：`src/tests/test_cultivator_v9_ground_contact.gd`（22 断言，含用原资产真实读数
做的负向控制）。阈值 0.08 m 取在实测的两组值（正确 0.0555 / 回归 0.1046）之间，
因此它能抓住「恢复成统一全局偏移」这一真实回归，抓不住任意 clip 上 2 cm 的浮动——
后者由顶点级量具负责。
