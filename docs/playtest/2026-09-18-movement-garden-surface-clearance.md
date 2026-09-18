# 移动庭院地表间距验收（2026-09-18）

场景：`res://levels/experiments/character_movement/movement_garden.tscn`（子实验「移动庭院」，小场景回归）。
修复对象：砂地 / 台基 / 50 块手工铺砖的穿插与近共面闪烁；第三次修改追加独立审计命中的
Scholar rock base 顶面过低与 Pavilion column base 底面近共面（见「独立审计修正轮」）。
决策依据：[装饰面共面与透明穿叠导致的跨场景地面闪烁](../../notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md)（本场景为该 note 表内第 3 行）。
资产台账与几何变更表：[movement_garden/asset_ledger.md](../art/movement_garden/asset_ledger.md)。
验收档：**CLI 档**（`godot --headless` + 窗口模式截图）。
所有权边界：只动 `tools/art/generate_movement_garden.py`、`docs/art/movement_garden/**`、`movement_garden.glb` 与其 `.import`；
`movement_garden.gd`、碰撞代理、相机、阴影代码与共享 verifier **零改动**（见下静态检查行）。

## 最终摘要

- 静态间距检查：**13 PASS / 0 FAIL**（`~/.cache/game-xiuxian-lab/surface-clearance/movement-garden/static_check.log`）。
- 庭院专属 playtest：**39 PASS / 0 FAIL**（`playtest.log`），含站立 / 碰撞 / 移动语义 / 重置 / 返回路径。
- 运行时单元套件（第二次修复轮读数；审计修正轮按范围未重跑全量套件）：**260 通过 / 0 失败**（`test_runner.log`）。
- 生成器自检：导出前基于**实际生成顶点**断言通过，`PAVING_REAL bottom=0.030000 top_span=(0.082188, 0.087939) distinct_tops=49`，
  以及审计修正两条 `ROCK_BASE_REAL bottom=-0.270000 top=0.970000`、`COLUMN_BASE_REAL bottom=0.010000 top=0.335000 count=4 paving_top_min=0.082188 gap=0.072188`。
- 视觉对照：**冻结静止稳定（连续 10 帧 0 差异）已证明**；**移动相机对照未证明修复有效**，见「未验证 / 限制」。
- Git：本档描述的写集（生成器、`docs/art/movement_garden/**`、本档与重导出的 `movement_garden.glb`）已随最终集成轮的本地提交保存；此后无未提交改动。

## 几何修复（生成器 → 重导）

统一承托契约（米）：`SURFACE_CLEARANCE = 0.010`，薄片绝对下限 2 mm。

| 层 | 修复前 | 修复后 |
|---|---|---|
| 碰撞地面（程序 `BoxShape3D`） | 顶 y = 0.000 | **顶 y = 0.000（未改）** |
| `Limestone upper terrace` | 顶 0.000 | 顶 **−0.020**、底 −0.220 |
| `Sand garden surface` | y ∈ [−0.0075, +0.0175]（穿过台基顶） | y ∈ [−0.010, +0.020]（底面高出台基顶 10 mm） |
| 50 × `Hand cut paving` | 底面 0.028 ± 0.003（随随机变化、压进砂层） | **底面固定 0.030**，厚 0.055 ± 0.003 ⇒ 随机只改可见顶面 |
| 条石 / 压顶 / 台基 / 灯座 / 竹干等 | 底面贴承托面 | 自 0.030 起算，与砂面 ≥10 mm |

数量、水平位置、材质、三角形数（40720）与 13 个材质全部不变：**没有删铺装**，50 块手工砖俱在（`paving_blocks=50`）。

## 五问分类

| 项 | 1 已实现 | 2 已运行通过（命令 + 结果） | 3 静态检查 | 4 未验证 | 5 外部阻塞 |
|---|---|---|---|---|---|
| 台基顶不再与 y=0 碰撞面同面 | ✔ 生成器 `TERRACE_TOP=−0.020` | | ✔ GLB 实测 −0.02000 | | |
| 砂面不再穿过台基 | ✔ 砂底面固定 −0.010，高于台基顶 10 mm | | ✔ 实测 gap 0.01000，且不再有 y 区间重叠 | | |
| 50 块铺砖底面固定、随机只改顶面 | ✔ `thick` 随机、`center=PAVING_BOTTOM+thick/2` | ✔ 生成器导出前自检：底面**唯一值** `0.030000`、49 个不同顶面 | ✔ GLB 实测底面集合 = {0.030}，最小 gap 0.01000 | | |
| 随机幅度不可能重回承托层 | ✔ 顶抖动 ±0.003 作用在固定底面上 | | ✔ 抖动下限 0.02700 > 砂顶 0.02000 | | |
| 承托链其余件 | ✔ 条石/压顶/台基/灯座/竹干改自 0.030 起算 | | ✔ gap 各 0.01000；plinth 顶保持 −0.230 | | |
| 庭院造型与风格保留 | ✔ 只改垂直层级 | ✔ 319 网格 / 13 材质 / 40720 三角形与修复前一致 | | 观感由使用者实机判断 | |
| 独立审计修正①：Scholar rock 底面下沉 | ✔ 调中心 + Y 半径（非整体平移），顶保持 0.970 | ✔ 生成器顶点自检 + GLB 实测 | | | |
| 独立审计修正②：Pavilion column base 钉底 | ✔ 底 = PAVING_BOTTOM−0.02 = 0.010，顶保持 0.335 | ✔ 生成器顶点自检 + GLB 实测 | | | |
| 站立高度与移动语义不变 | ✔ `movement_garden.gd` 零改动 | ✔ 专属 playtest **39 PASS / 0 FAIL**（含真实角色 sweep 的 6 个碰撞体断言、R 重置、两级返回） | ✔ `git status` 该脚本无改动 | | |
| 全量回归 | | ✔ `tests/test_runner.tscn` → **通过 260 / 失败 0** | | | |
| 冻结静止稳定 | | ✔ 连续 10 帧帧间差异 **0 px**（1280×800，MSAA 4x） | | | |
| **移动相机不再整片翻闪** | | | | ✔ **未证明**：见下 | |
| 旧资产保留 / 新件入账 | | | ✔ 修复前 3 类旧件（预览、源副本 ×2）在仓；新预览与哈希已入台账 | | |
| 相机 / 阴影 / 角色代码未被用来掩盖问题 | | | ✔ movement_garden 自身运行时代码与断言未改（`movement_garden.gd`、`movement_garden.tscn` 及 `src/tests/character_movement_playtest.gd` 中本场景断言）；最终集成轮新增 experimental 探针 `src/tests/ground_contact_course_surface_clearance_capture.gd`（非门禁，见地形台账），`tools/verify/` 无改动 | | |

## 独立审计修正轮（2026-09-18 第三次修改，本轮读数）

只动所有权内文件；未跑全量套件（按本轮范围只跑该场景必要检查与 `git diff --check`）。

| 检查 | 命令 | 结果 |
|---|---|---|
| 生成器自检 + 重导 | `Blender --background --factory-startup --python tools/art/generate_movement_garden.py` | `ROCK_BASE_REAL bottom=-0.270000 top=0.970000 plinth_top=-0.230000`；`COLUMN_BASE_REAL bottom=0.010000 top=0.335000 count=4 paving_top_min=0.082188 gap=0.072188`；`PAVING_REAL bottom=0.030000 top_span=(0.082188, 0.087939) distinct_tops=49`；`MESHES 319` |
| 静态间距检查（只读，仓外脚本） | `python3 ~/.cache/game-xiuxian-lab/surface-clearance/movement-garden/check_surface_clearance.py <glb>` | **13 PASS / 0 FAIL** |
| 庭院专属 playtest | `Godot --headless --path src --script res://tests/character_movement_playtest.gd` | **39 PASS / 0 FAIL**（末行 `失败 0`） |
| 工作区格式 | `git diff --check` | exit 0，无空白错误 |
| 旧件未被覆盖 | `shasum -a 256 -c`（重跑前记录） | `blend1` / `blend11` / `garden_preview.png` / `garden_preview_pre_surface_clearance.png` 全部 OK；仅本轮应重渲染的 `garden_preview_surface_clearance.png` 按预期更新 |

几何实测（GLB 世界 Y，米）：`Scholar rock base` y ∈ [−0.270, **+0.970**]（底面比 plinth 顶 −0.230 低 40 mm，
与 `movement_garden.gd` 的 1 m 碰撞代理顶 y=1.0 余量约 3 cm）；`Pavilion column base` y ∈ [**+0.010**, +0.335]（顶不变，
底面低于随机铺砖顶面 0.082188–0.087939 至少 72.2 mm，原 1.28–1.36 mm 近共面消失）。

## 未验证 / 限制（必须如实标注）

**移动相机对照未能判别修复效果。** 本仓库尚无通过验证的判据，本轮也未能建立一个：

- 帧间「变化像素数」在相机微移下被正常视差淹没，不是闪烁量（note 已警告）。
- 为排除视差，本轮实现**位移补偿残差**（相机沿自身屏幕右方精确移动 1 px，用 ±1 px 平移解释上一帧，
  统计补偿后仍变化的像素；理论上刚体平移无法解释的 z-fighting 翻转会被留下）。
  `~/.cache/game-xiuxian-lab/surface-clearance/movement-garden/flicker_compare.txt`
- 结果：**修复前与修复后落在同一区间**——整景铺装区 7.5–8.7 vs 8.9–12.2 /1000px；
  6 m 近景单块铺砖边缘 5.0–9.0 vs 5.5–10.1 /1000px。**该指标无法区分两个资产**，因此不能作为修复有效证据。
- 可以确定的是：补偿残差在「铺装区」与「无装饰砂地对照区」处于同一量级
  （整景 8.9–12.2 vs 8.5–13.1 /1000px），符合 note「移动组差异应回落到与无装饰地面相同量级」的**比较口径**；
  但这只说明**铺装区没有超出砂地的额外异常**，不等于证明共面闪烁已消失。
- 本轮未能定位到原始闪烁在屏幕上的具体位置，因此也没有做「只勾选该区域 / 隐藏该件」的定向对照。
  生成器的水平造型未被改动（只有垂直层级变化），故本轮的层级修正**有确定的静态依据**，但缺少对应的运行时判别证据。

**残余近共面（未处理，需后续扫描确认是否可接受）。** 本轮只保证「装饰层 ↔ 承托层」的间距；
同一水平面内部的相邻件（例：条石顶 0.060 与压顶底 0.030 一侧、`Meditation stone top` 与 `Celadon bowl`
在 0.80/0.82 附近的竖直关系）未逐一扫描。按 note，这类需以「允许清单」逐条判定，不在本轮范围。

**其余未验证**：配色与采光的审美判断（交使用者）；`mountain_realm` / `peak_courtyards` 未扫描（本轮范围外）。

## 复现命令

```sh
# 1) 生成器（导出前自检，失败即不导出）
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_movement_garden.py

# 2) 静态间距检查（一次性脚本，不进仓、不进 Tier 0）
python3 ~/.cache/game-xiuxian-lab/surface-clearance/movement-garden/check_surface_clearance.py \
  src/levels/experiments/character_movement/movement_garden.glb

# 3) 庭院专属 playtest
/Applications/Godot.app/Contents/MacOS/Godot --headless --path src --script res://tests/character_movement_playtest.gd

# 4) 全量运行时套件
/Applications/Godot.app/Contents/MacOS/Godot --headless --path src tests/test_runner.tscn

# 5) 窗口截图（4 张）
/Applications/Godot.app/Contents/MacOS/Godot --path src --script res://tests/character_movement_playtest.gd \
  -- --capture-prefix=~/.cache/game-xiuxian-lab/surface-clearance/movement-garden/surface_clearance

# 6) 冻结/移动对照探针（只读，两个 GLB 走同一代码路径）
/Applications/Godot.app/Contents/MacOS/Godot --path src --script \
  ~/.cache/game-xiuxian-lab/surface-clearance/movement-garden/flicker_probe.gd \
  -- --out=<日志目录> --tag=fixed --glb=<argv 指定的 GLB 绝对路径>
```

## 日志与证据（仓外，`~/.cache/game-xiuxian-lab/surface-clearance/movement-garden/`）

| 文件 | 内容 |
|---|---|
| `static_check.log` | 静态间距检查 13 PASS / 0 FAIL |
| `playtest.log` | 庭院专属 playtest 39 PASS / 0 FAIL |
| `test_runner.log` | 全量套件 260 通过 / 0 失败 |
| `capture.log` + `surface_clearance-*.png` | 窗口截图 4 张（character-closeup / character-near / garden / small） |
| `flicker_compare.txt` | 冻结 + 位移补偿残差对照（修复前 vs 修复后） |
| `check_surface_clearance.py` / `flicker_probe.gd` | 本轮一次性只读检查脚本（**不进仓**：按 note 验收标准第 5 条，未加负向控制前不得声称为门禁） |

## 交付物

| 文件 | 字节 | sha256 |
|---|---|---|
| `tools/art/generate_movement_garden.py` | — | 生成器（层级契约 + 审计修正常量 + `save_version=0` + 导出前顶点自检） |
| `src/levels/experiments/character_movement/movement_garden.glb`（审计修正后） | 2451280 | `6433d276d0105c1728f6b9d18dd2dc8850a3ed491113c2172a3bf90c5c901512` |
| `docs/art/movement_garden/movement_garden.blend`（同上） | 257361 | `c690ff65983c9272836f48b931f4e17e0f781abdd940d421ee209bdc1790eb83` |
| `docs/art/movement_garden/garden_preview_surface_clearance.png`（同上） | 1154508 | `3847ff1ae39028935ea62ef849ad54bde9bde6e66023b1c0da99f273b938c20f` |
| `movement_garden.glb` / `.blend` / 预览（**第二次修复**读数，已被第三次覆盖） | 2448860 / 257320 / 1154459 | `9b614427…` / `6dc09cc4…` / `6eb05355…` |
| `src/game/actors/swordsman/models/cultivator.glb`（**不在本轮资产写集**，不作变化断言） | 121736 | `70fc5eb6a4cd60579ac06bde5e65da6cc22e32f48316eae53e813387ae36b426` |
| `docs/art/movement_garden/garden_preview.png`（修复前，保留） | 1132128 | `5d24571740699be8af2dba6281638b4499edb6cb50a257f98ddc09ec5088249a` |
| `docs/art/movement_garden/garden_preview_pre_surface_clearance.png`（同上字节） | 1132128 | `5d245717…5088249a` |
| `docs/art/movement_garden/movement_garden.blend1`（修复前源） | 256742 | `f99acf09ed21809da8a961be10ff0f75d33bc724b02c61c01a21823b69abdf5f` |
| `docs/art/movement_garden/movement_garden.blend11`（同上字节） | 256742 | `f99acf09…9abdf5f` |

修复前 GLB 原件（2418472 字节 `44a7f011a2813bd0a086b72dcea63d38feb803cff21a3c43aa0fbc1a92d42ad3`）
已按旧字节另存为仓内归档 `docs/art/movement_garden/pre_surface_clearance_movement_garden.glb`（对照探针即用它作修复前基线）；
同目录另有 `pre_surface_clearance_movement_garden.blend`（256742 字节 `f99acf09…`）。两者逐字节等于修复前提交时点的旧字节，修复前状态不再只依赖 Git 历史。

## 流程事故（如实记录）

重导过程中 Blender 自动产生的 `movement_garden.blend1` 与 `movement_garden.blend11` 曾被**误删除**，
违反根 AGENTS.md「探索资产不得删除」。已按 git HEAD 的修复前字节恢复两个路径（sha256 均为 `f99acf09…`，
Blender 可正常打开、319 网格），并在 `asset_ledger.md` 逐项登记来源与关系。
生成器已设 `save_version=0`，避免后续重跑继续产生新的轮转文件。本轮之后不得再清理任何资产。
