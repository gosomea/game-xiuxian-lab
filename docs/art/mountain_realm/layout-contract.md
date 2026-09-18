# 群山宗门 · 布局契约 v2（已过主代理审计，实施中）

Owner: Blender 美术交付代理 · 2026-09-18 · 状态：**审计通过**（v1 的 A–F 六项修正已并入）。
真源：本文件 + `src/levels/experiments/character_movement/mountain_realm_layout.json`（脚本生成，唯一坐标真源）。
决策依据：[mountain-traversal](../../../notes/implemented/gameplay/2026-09-18-mountain-traversal.md)（本轮美术决策已由该 note 覆盖，不新增 art note）。
Godot 世界 **Y-up、米**，角色正面 / 北为 **−Z**；Blender Z-up，换算 `godot = (bx, bz, −by)`、`blender = (gx, −gz, gy)`。
`rect` = `center(x,z)` + `size(X×Z)`；盒子 `center` 含 y，`top_y == center.y + size.y/2`。

## 交付路径（场景方按此 preload）

| 产物 | 路径 |
|---|---|
| 布局真源 | `src/levels/experiments/character_movement/mountain_realm_layout.json` |
| 可见美术 | `src/levels/experiments/character_movement/mountain_realm.glb` |
| 碰撞壳 | `src/levels/experiments/character_movement/mountain_realm_collision.glb` |
| 御剑 | `src/game/abilities/sword_flight/models/flying_sword.glb` |
| 生成脚本 | `tools/art/generate_mountain_realm.py`（阶段 layout / terrain / collision / sword / preview） |
| 源文件·台账·预览 | `docs/art/mountain_realm/` |

## 全局

| 项 | 值 |
|---|---|
| bounds | min (−90, −6, −80) → max (90, 60, 80) |
| 越界处理 | 由 scene 建**碰撞墙 + 顶棚**限制（`limit_mode: scene_collision_walls_and_ceiling`）；只有 y < fall_out_y(−6) 才回收重生 |
| 谷底 | `ground_valley` (0, −0.5, 0) 180×1×160，行走面 y=0 |
| spawn | **(−30, 12.02, 34)**，yaw 0（面朝 −Z 群山），落在 `spawn_courtyard` 顶面；也是重生点 |

## 五峰（轮廓参数为视觉与碰撞共用真源；足印互不重叠，最小间隙 5 m）

| name | 碰撞节点 | 足印 center(x,z) size(X×Z) | 台顶 y |
|---|---|---|---|
| main_peak 主峰 | `MainPeakCol` | (4, −34) 54×46 | 月台 30 / 宗门台 36 |
| north_peak 北峰 | `NorthPeakCol` | (−46, −52) 36×30 | 28 |
| west_peak 西峰 | `WestPeakCol` | (−70, −6) 30×30 | 20 |
| east_ridge 东岭 | `EastRidgeCol` | (56, 20) 44×26 | 16 |
| front_mesa 前丘 | `FrontMesaCol` | (−30, 34) 42×34 | 12 |

主峰拆两个壳（同一对象 `MainPeakCol` 内的两个闭合体）：0→30 山肩（顶环 32×42 覆盖月台与台阶起点）
＋ 30→36 高台实体（center (4,−46) 30×20，只在台阶以北）。**月台与 30→36 台阶上方不得被壳封盖。**
北峰壳含主壳与西北岩肩、北侧脊（共 3 个闭合体）。地面到 12 m 起点庭院不设连续登山路，本轮明确御剑可到。

## 三落脚点 landing_points

| name | top_y | 净空 rect | 归属 |
|---|---|---|---|
| spawn_courtyard | 12 | (−30,34) 20×16 | 前丘起点庭院（重生点） |
| summit_sect | 36 | (4,−41) 22×10 | 主峰宗门庭院（与两侧廊台净空不重叠） |
| north_pavilion | 28 | (−46,−52) 14×12 | 北峰小庭院 |

## 山体碰撞（视觉与碰撞共用同一 mesh）

- 碰撞壳由 bmesh 轮廓环（顶环 + 逐段收分环 + 谷底外扩环）生成**闭合壳体**；**同一批对象既进
  `mountain_realm.glb` 也进 `mountain_realm_collision.glb`**，因此可接近岩面偏差为 **0**（不是 1.5 m）。
- 每峰一个对象，节点名 = 上表 PascalCase（`MainPeakCol` 等），多闭合体合并在同一对象内。
- 碰撞 GLB 只含这 5 个对象；平台顶面、台阶、建筑由 JSON `boxes` 的立方体代理承担。
- 视觉侧在同一壳体上按高度分 4 条岩层材质带；**凸出的小装饰（檐角、树冠、竹叶、灯罩、苔石）允许无碰撞**。

## 精度要求（可核验）

| 项 | 目标 |
|---|---|
| 山体可接近岩面偏差 | 0（共用 mesh）；装饰件不作为行走面 |
| 平台/台顶站立面误差 | ≤ 0.02 m（`top_y` 同时是视觉盒顶面与站立面，同源生成） |
| 单级台阶抬升 | 0.75 m ≤ 跳跃顶点 1.0 m（跳速 6、重力 18） |
| 廊台檐下净高 | 4.0 m |

## 建筑与屋顶

- **`boxes` 每项都是实体，JSON 不含 `enterable` 之类挖空标记，scene 不得自行挖盒。**
- 青瓦主殿 `main_hall_*`：墙体**分段盒** `wall_north/west/east/south_a/south_b` + `lintel`，
  南面留真实门洞（x∈[2,6]、门高 36→40），殿内**内部空腔**由分段墙体自然形成。
- 屋顶 `role:"roof"` 为**实心 AABB 代理**：`eaves`(顶 42.2) + `upper`(顶 45.0)；视觉为坡屋面，屋面**必须完全内含于**该 AABB，
  脊高 = `top_y`。禁止用覆盖整栋/整院的实心盒代替分段墙体。
- 山门：`shanmen_pillar_west/east` + `lintel` + `roof`，中央 5.8 m 门洞。
- 廊台：x=4±13.5（±3.6 宽），柱距 4 m，双坡瓦顶檐高 40.4；檐下净高 4 m 可穿行。
- 宗门台石栏高 1.4 m，南面留 6 m 门洞对台阶；松/竹/石灯为 `role:"prop"`，**仅近地树干/灯柱/丛芯实心**。

## 起点庭院练跳石台

`jump_step`：center (−35.5, 12.275, 30)，size 2.2×0.55×2.2，**顶面 12.55**（抬升 0.55 m）；
跳速 6 / 重力 18 顶点 1.0 m，可跳上；供跳跃与落地验证。

## 御剑模型（独立 GLB）

- 长 1.8 m（沿局部 Z），最宽 0.26 m，厚 0.07 m；**局部 −Z 为剑尖**。
- 原点 = 剑身**顶面中心**（Y=0 即人物足底站立面，场景无需补偿偏移）。
- 无骨骼/动画/贴图；青灰钢 + 暖金剑格 + 缠绳剑柄可辨识。

## 美术语言（素材语言复用，禁止随机圆锥填数）

岩灰岩层带（4 级）与谷底石台；青瓦（`Jade roof tiles`）坡屋面 + 屋脊压顶 + 檐角起翘；
主殿/廊台/山门构成宗门群组；松（三层锥冠）与竹丛（多竿 + 尖叶）分列庭院与峰顶；
石灯、苔石、铺地石板（顶面与平台面齐平）；远山 8 座低多边形山影 + 8 层云带形成纵深。
纸白青绿基调沿用 [paper-jade-palette](../../../notes/implemented/art/2026-09-17-paper-jade-palette.md)；
旧 `movement_garden` 18×14 m 尺度与素材语言可参考，**不导入旧游戏资产**。

## mountain_realm_layout.json（schema）

```json
{
  "schema": "mountain_realm_layout/1",
  "units": "meters",
  "up_axis": "Y",
  "blender_to_godot": "godot = (bx, bz, -by)",
  "bounds": {"min": [-90, -6, -80], "max": [90, 60, 80], "fall_out_y": -6,
             "limit_mode": "scene_collision_walls_and_ceiling"},
  "spawn": {"position": [-30, 12.02, 34], "yaw_deg": 0, "landing_point": "spawn_courtyard"},
  "landing_points": [{"name": "spawn_courtyard", "top_y": 12, "center": [-30, 34], "size": [20, 16], "peak": "front_mesa"}],
  "collision": {"mode": "visual_glb + separate_trimesh_shell", "shell_glb": "res://.../mountain_realm_collision.glb",
                "ring_segments": 20, "mountains": [{"name": "main_peak", "node": "MainPeakCol", "top_y": 36, "shell_count": 2}]},
  "boxes": [{"name": "summit_terrace", "role": "ground", "center": [4, 35, -46], "size": [30, 2, 20], "top_y": 36, "solid": true}],
  "decor": [{"name": "distant_hill_1", "kind": "hills", "solid": false, "center": [-124, 10, -70], "size": [46, 30, 62]}],
  "checks": {"box_count": 0, "solid_count": 0, "role_histogram": {}, "landing_point_count": 3, "problems": []}
}
```

字段约束：`role ∈ {ground, mountain, building, roof, stairs, prop}`；`center` 含 y；`solid` 控碰撞；
`decor` 一律 `solid:false`（远山云层无碰撞）；`checks.problems` 必须为空数组。
