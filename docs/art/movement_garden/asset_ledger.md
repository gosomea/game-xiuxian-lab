# 资产台账 · movement_garden

按 [mcp-blender skill](../../../skills/mcp-blender/SKILL.md) 的登记纪律：来源、许可结论、日期。
生成方式：**AI 代理编写脚本，经 Blender 程序建模**；未调用图像/3D 生成服务，也无下载资产，
因此没有 Sketchfab/Poly Haven/Hyper3D/Hunyuan3D 条目。

| 字段 | 值 |
|---|---|
| 资产名 | `movement_garden`（修士角色 + 修仙庭院） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS 程序建模；无外部素材、无下载、未调用图像/3D 生成服务 |
| 生成脚本 | `tools/art/generate_movement_assets.py`（角色）、`tools/art/generate_movement_garden.py`（庭院） |
| 复现命令 | 见 `README.md`「复现命令」（macOS 完整 Blender 路径，其他平台用小写 `blender`）；全程 `--background --factory-startup`，不操作用户打开的 .blend |
| 源文件（source） | `docs/art/movement_garden/cultivator.blend`、`docs/art/movement_garden/movement_garden.blend` |
| 输出（output） | `src/game/actors/swordsman/models/cultivator.glb`、`src/levels/experiments/character_movement/movement_garden.glb`、`docs/art/movement_garden/garden_preview_surface_clearance.png` |
| 生成日期 | 2026-09-18（庭院于 2026-09-18 二次修改：共面闪烁修复；三次修改：独立审计几何修正，均见下） |
| 第三方素材 | 无 |
| 许可依赖 | 无第三方许可约束（几何与材质均为本仓原创；仅依赖 Blender 自带 Python） |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明 |
| 运行环境 | Blender 5.2.1 LTS（2026-08-25 构建），导出器 Khronos glTF Blender I/O v5.2.40 |
| 二进制校验和 | 见 `README.md` 校验和表（sha256） |
| 数值摘要 | 角色：17 网格 / 5080 三角形 / 7 材质 / 1.70 m；庭院：319 网格 / 40720 三角形 / 13 材质 / 18×14 m |
| 生成方式声明 | AI 代理编写脚本，经 Blender 程序建模；未调用图像/3D 生成服务，无第三方素材（发布政策结论未在本轮研究，不在此断言） |
| 验收 | Godot 最终验收已通过：32 项物理断言全 PASS、87 条单测通过、4 张截图，见 [角色移动庭院验收](../../playtest/2026-09-18-character-movement.md) |
| 未完成 | 手感与配色审美待使用者实机判断；无骨骼、无动画、无碰撞体（Godot 侧自建代理） |

## 2026-09-18 第二次修改：庭院地面共面/穿插修复（surface clearance）

依据 [装饰面共面导致的跨场景地面闪烁](../../../notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md)
与 [mountain-traversal](../../../notes/implemented/gameplay/2026-09-18-mountain-traversal.md) 已实现的
「装饰面高出承载面」约定。**属于「在原模型上继续修改」，因此原位更新同一 `.blend` 与 GLB，同时保留旧件。**

**几何变更（仅垂直层级；水平造型、装置位置、数量、材质、三角形数 40720 全部不变）：**

| 件 | 修复前 | 修复后 |
|---|---|---|
| `Floating courtyard plinth` | 顶 −0.230 | 不变（−0.230） |
| `Limestone upper terrace` | 顶 **0.000**（与碰撞地面同面） | 顶 **−0.020**、底 −0.220 |
| `Sand garden surface` | y ∈ [−0.0075, +0.0175]，**穿过**台基顶面 | y ∈ [−0.010, +0.020]，底面比台基顶高 10 mm |
| 50 × `Hand cut paving` | 底面 0.028 ± 0.003、厚 0.055，约半数落入 ±1.5 mm | **底面固定 0.030**（单一平面），厚 0.055 ± 0.003 ⇒ 随机只改可见顶面 |
| 铺装/条石/压顶/台基/灯座/竹干等承托件 | 底面贴承托面 | 统一自 0.030 起算，与砂面 ≥10 mm（薄片 ≥2 mm 绝对下限） |

碰撞地面由 `movement_garden.gd` 程序生成（`BoxShape3D`，顶 y = 0），**该脚本零改动**；角色站立高度与移动语义不变。

**保留的旧件（全部在仓内跟踪，本轮未删除任何探索资产）：**

| 路径 | 字节 | sha256 | 关系说明 |
|---|---|---|---|
| `garden_preview.png` | 1132128 | `5d245717…5088249a` | **修复前**庭院预览原件，按用户要求原位保留 |
| `garden_preview_pre_surface_clearance.png` | 1132128 | `5d245717…5088249a` | 同上字节的历史副本，命名标注「surface clearance 之前」 |
| `movement_garden.blend1` | 256742 | `f99acf09…9abdf5f` | **修复前**源文件副本：重导时 Blender 自动产生的版本备份，曾被误清理，已按 git HEAD 字节恢复；作为修复前源资产长期保留 |
| `movement_garden.blend11` | 256742 | `f99acf09…9abdf5f` | 同上，第二次误生成的同类备份；与 `blend1` 字节相同，同为修复前源 |

`blend1` / `blend11` 内容等同修复前的 `movement_garden.blend`（`f99acf09…`），在 Blender 5.2.1 下均可正常打开（319 网格）。
生成器已设 `save_version=0`，后续重跑不会再产生新的 `.blend1` 轮转文件。

最终集成轮补齐了本目录的**仓内修复前归档**（用 `git show HEAD:<path>` 按旧字节另存，逐字节等于基线提交 `240c23c` 引入的旧字节）：

| 归档文件 | 字节 | sha256 | 来源 |
|---|---|---|---|
| `pre_surface_clearance_movement_garden.blend` | 256742 | `f99acf09ed21809da8a961be10ff0f75d33bc724b02c61c01a21823b69abdf5f` | = HEAD 旧 `.blend`，与 `.blend1`/`.blend11` 字节相同 |
| `pre_surface_clearance_movement_garden.glb` | 2418472 | `44a7f011a2813bd0a086b72dcea63d38feb803cff21a3c43aa0fbc1a92d42ad3` | = HEAD 旧 GLB（修复前导出） |

**修复后校验和（完整表见 `README.md`）：** `movement_garden.blend` 257320 字节 `6dc09cc4…`；
`movement_garden.glb` 2448860 字节 `9b614427…`；新预览 `garden_preview_surface_clearance.png` 1154459 字节 `6eb05355…`。

## 2026-09-18 第三次修改：独立审计几何修正（Scholar rock / Pavilion column base）

独立审计在第二次修复的资产上又命中两处：Scholar rock base 顶面从碰撞代理顶以下被整体压低，
以及 Pavilion column base 底面（0.085）与随机铺砖顶面（0.0822–0.0879）近共面（1.28–1.36 mm）。
两者都属「在原模型上继续修改」：原位更新同一 `.blend` 与 GLB，旧件不覆盖、不删除。

| 件 | 修正前 | 修正后 | 做法 |
|---|---|---|---|
| `Scholar rock base` | 顶 0.870、底 −0.230（1 m 碰撞代理顶 y=1.0 下方余量 13 cm） | 顶 **0.970**、底 **−0.270** | 中心 +Z 半径同时调整（中心 0.350、Z 半径 0.620），**不是整体下移** |
| `Pavilion column base` ×4 | 顶 0.335、底 0.085（与铺砖顶最近 1.28–1.36 mm） | 顶 **0.335（不变）**、底 **0.010** | 向下增高：底钉到 `PAVING_BOTTOM−0.02`，埋入铺砖区下方 |

- Scholar rock base 底面比 plinth 顶（−0.230）下沉 **40 mm**（≥20 mm 要求），顶面保持修复前的可见高度
  0.970，使角色 1 m 碰撞代理顶 y=1.0 与岩顶余量约 3 cm。
- Pavilion column base 底面比随机铺砖最高顶 0.087939 低 **77.9 mm**，比最低顶 0.082188 低 **72.2 mm**，
  不再出现 1.28–1.36 mm 的近共面；可见顶保持 0.335 不变。
- 生成器导出前自检升级：除原有 50 块铺砖固定底面合同（`PAVING_REAL bottom=0.030000`、49 个不同顶面）外，
  新增对**实际生成顶点**的两条断言——`ROCK_BASE_REAL bottom=-0.270000 top=0.970000`、
  `COLUMN_BASE_REAL bottom=0.010000 top=0.335000 count=4 paving_top_min=0.082188 gap=0.072188`。
  断言失败即不导出。
- 水平造型、装置位置、数量、材质、三角形数（40720）与 319 网格全部不变；`movement_garden.gd` 与
  碰撞代理零改动，唯一物理提交点不变。

**本轮校验和：** `movement_garden.blend` 257361 字节 `c690ff65…`；
`movement_garden.glb` 2451280 字节 `6433d276…`；预览 `garden_preview_surface_clearance.png` 1154508 字节 `3847ff1a…`。
`movement_garden.blend1` / `.blend11`（修复前源副本）与两张修复前预览未删除、未覆盖。
角色资产 `src/game/actors/swordsman/models/cultivator.glb`（121736 字节
`70fc5eb6a4cd60579ac06bde5e65da6cc22e32f48316eae53e813387ae36b426`）**不在本轮资产写集**，其读数不作变化断言。

验收证据：[庭院地表间距验收](../../playtest/2026-09-18-movement-garden-surface-clearance.md)。

登记人：Blender 资产交付代理；日期 2026-09-18。数值与轴向的完整说明见 `README.md`。
