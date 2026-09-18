# peak_courtyards 美术资产（庭院建筑）

2026-09-18 由 AI 代理编写脚本、经本地 Blender 5.2.1 LTS 独立后台进程程序建模，
**全部为程序原创几何**：无下载素材、无贴图、无骨骼、无动画，未调用图像/3D 生成服务。
唯一外部依赖是 Blender 自带 Python（bpy / mathutils / bmesh）。

决策依据：[2026-09-18-mountain-realm-visual-rebuild](../../../notes/implemented/art/2026-09-18-mountain-realm-visual-rebuild.md)。
素材语言（瓦亭 / 石灯 / 竹丛 / 铺石）沿用 [movement_garden](../movement_garden/README.md)。
地形边界见 [terrain-interface.md](../mountain_realm/terrain-interface.md)。

## 接口（与地形 / 场景代理的边界）

| 项 | 约定 |
|---|---|
| 运行时 GLB | `src/levels/experiments/character_movement/mountain_realm_courtyards.glb`（17 个按材质合并的节点） |
| 附加碰撞 JSON | `src/.../mountain_realm_courtyards_collision.json`（33 盒） |
| schema | `peak_courtyards_collision/1`，条目 `{name, center:[x,y,z], size:[x,y,z]}`，Godot 世界坐标 |
| 坐标系 | 按 **Godot 世界坐标** 一次导出（Y 上、北 = −Z）；场景在原点实例化 |
| 实例化方式 | preload 后 instantiate() 挂在场景原点；**不要**按节点名重定位（节点已按材质合并） |
| 逐构件编辑 | 读 `docs/art/peak_courtyards/mountain_realm_courtyards.blend`（833 个可编辑零件） |
| 公共布局 | **不改** `mountain_realm_layout.json` |
| 地形分工 | 山体、大型承载面（含 `shanmen_terrace`）、9 棵松归 `mountain_realm.glb` |

## 导出合并（性能，语义取舍已记录）

833 个源零件在**导出副本**里按主材质烘焙修改器后合并为 **17 个节点**（`courtyards_<material>`），
把 drawcall 从 700+ 降到材质数量级。合并前后三角形数与包围盒必须完全一致（`MERGE ok`，否则退出 4）；
世界坐标、几何与碰撞 JSON 不变。**代价**：GLB 不再保留逐构件节点名；需要单栋建筑开关时请读 .blend 或改合并分组。

## 三项构建期机械校验（失败即非零退出）

1. `COVERAGE`：每个属于本文件的既有盒都必须有可见几何，否则退出 2（防隐形墙）。
2. `LANDING_CLEARANCE`：新增实体不得侵入任何落点净空，否则退出 3。
3. `MERGE`：合并导出不得改变三角形数或包围盒，否则退出 4。

## 复现命令（仓库根）

```sh
# 全量：GLB + 附加碰撞 JSON + .blend（833 分件）+ 六张预览
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python tools/art/generate_peak_courtyards.py -- courtyards
# 子集（仅预览用，不覆盖附加碰撞 JSON）
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python tools/art/generate_peak_courtyards.py -- courtyards spawn,preview
```

全程 `--background --factory-startup`；重跑会覆盖 GLB / JSON / .blend / 预览。

## 产物与真源

| 文件 | 角色 |
|---|---|
| `src/.../mountain_realm_courtyards.glb` | 运行时网格（17 合并节点，不手改） |
| `src/.../mountain_realm_courtyards_collision.json` | 新增实体碰撞（场景消费） |
| `docs/art/peak_courtyards/mountain_realm_courtyards.blend` | Blender 源文件（唯一真源，833 分件） |
| `docs/art/peak_courtyards/courtyards_preview_*.png` | Cycles 预览（六张，非运行时素材） |

数值、校验和与踩坑见 [asset_ledger.md](asset_ledger.md)。
