# 资产台账 · sword_flight_course（御剑飞行训练场「云路玉环」）

按 [mcp-blender skill](../../../skills/mcp-blender/SKILL.md) 的登记纪律：来源、许可结论、日期。
生成方式：**AI 代理编写脚本，经 Blender 5.2.1 LTS 程序建模**；未调用图像/3D 生成服务，无下载资产。

| 字段 | 值 |
|---|---|
| 资产名 | `sword_flight_course`（浮空玉环门 ×5、云阶 ×3、落剑台 ×2、起飞坪、悬停光柱、悬浮石 ×5、远山剪影 ×4） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS（2026-08-25 构建）程序建模；无第三方素材 |
| 生成脚本 | `tools/art/generate_sword_flight_course.py` |
| 源文件 | `docs/art/sword_flight_course/sword_flight_course.blend`（60 个可编辑分件） |
| 运行输出 | `src/levels/experiments/character_movement/sword_flight_course.glb`、`..._collision.json` |
| 预览 | `course_preview_{overview,takeoff,gates,hover,landing}.png`（Cycles 24 采样 + 降噪，960×640） |
| 生成日期 | 2026-09-18 |
| 第三方素材 / 许可依赖 | 无；唯一外部依赖是 Blender 自带 Python |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明。 |
| 生成方式声明 | AI 代理编写脚本，Blender 程序建模；未调用图像/3D 生成服务。 |
| 导出器 | Khronos glTF Blender I/O（Blender 5.2.1 自带），`export_yup=True` |
| 可复现性 | 固定种子（`random.Random(stable_seed(name))`）；同一 Blender 版本可复现 |

## 单一真源：几何与碰撞同源

生成器在**同一份数值**上同时建几何与写碰撞/路线 JSON（`sword_flight_course_collision.json`，
schema `sword_flight_course_collision/1`），因此不存在"视觉在此、碰撞在彼"的漂移：

| 类别 | 数量 | 说明 |
|---|---|---|
| 可碰撞件（`colliders`） | 86 | 起飞坪 1、云阶 3、落剑台 2、玉环环体 80（5 门 × 16 块） |
| 纯视觉件（`visual_only`） | 49 | 发光带、系挂件、光柱、悬浮石、远山剪影、落点围边与旗 |
| 玉环环体 | 80 块 | 沿圆周排布，块间距 < 角色胶囊直径，**不能从环壁缝隙钻过** |
| 路线判据 | JSON | 门心 / 朝向 / 半径、悬停区中心 / 半径 / 秒数、落点中心 / 台面高 / 半径 |

Godot 侧只读该 JSON 装配 `CourseCollision`，验收脚本逐项核对"每个 collider 都有同名场景节点"
与"纯视觉件未被登记为碰撞体"，两条机械检查都在 playtest 中执行。

## 数值（2026-09-18 最终读数）

| 产物 | 字节 | sha256 |
|---|---|---|
| `sword_flight_course.glb` | 614444 | `befddc04bd06cab254a91cccd1d271b1f8930ef276d9c9f23e87543bba3d6a3e` |
| `sword_flight_course_collision.json` | 20885 | `a59f67f70d025fdb605437974b1965ac2ac968cb00c346173e84eb2101c54cb7` |
| `sword_flight_course.blend` | 151526 | `f93f20667f46864573b69842308dee8894c970461fb9b97d3451a72efbe44ea7` |

生成读数：`COURSE ok objects=60 tris=7320 colliders=86 visual_only=49`。

## 路线（与 JSON 同源，此处仅为可读摘要）

| 玉环门 | 位置 (x, y, z) | 朝向 yaw | 半径 |
|---|---|---|---|
| `gate_1` 初启 | (0.0, 5.0, -2.0) | 0° | 2.40 |
| `gate_2` 升云 | (6.5, 9.0, -12.0) | 35° | 2.30 |
| `gate_3` 揽月 | (16.5, 13.0, -16.5) | 80° | 2.10 |
| `gate_4` 穿隙 | (32.0, 11.0, -10.0) | 130° | 1.80（最窄） |
| `gate_5` 回风 | (34.0, 7.5, 2.0) | 176° | 2.10 |

悬停区：中心 (30.0, 8.0, 7.0)、半径 3.4 m、**2.5 s**（位于末门与落点之间的自然航路上）。
落点：`landing_near` 台面 4.5 m（近而高，需控下降）／`landing_far` 台面 0.8 m（远而稳，低平宽大）。

## 版本与保留规则（探索资产）

本资产当前**只有一个版本**：`sword_flight_course.blend`（主源文件）+ `sword_flight_course.glb`，
二者是同一原模型的源与导出，不存在第二个独立版本。规则：

| 情形 | 处置 |
|---|---|
| **在同一原模型上继续修改**（调形状、挪位置、改材质） | 允许更新主 `*.blend` 与对应 `*.glb`，并在本台账「数值」表更新字节与 sha256，注明修改点。 |
| **另存为新版本或形成独立探索版本**（重做一版航线、换方案、A/B 对比） | 必须**另存文件名或版本目录**（例如 `sword_flight_course_v2.blend` / `docs/art/sword_flight_course_v2/`），并把该版本及其 `.glb` 一并纳入 Git；**不得覆盖**旧版本。 |
| 被替代的旧版本 | 保留在库并可连同依赖归档，维护引用与替代关系；Git 历史不能替代旧源文件与导出资产的保留。 |
| **Blender 覆盖保存产生的 `*.blend1`** | 它保存覆盖前那一刻的**可编辑源状态**，属于探索资产：必须**保留并纳入 Git**，并在本台账登记（文件名 + 产生时机）。**不得当作缓存删除**，也不得用忽略规则排除。 |
| 引擎导入缓存与临时运行日志 | 不属于源资产或交付资产，可不入库。 |

**本目录当前不存在任何 `.blend1`**（生成脚本以 `save_as_mainfile` 首次写出主文件，未发生覆盖保存）。
以后一旦 Blender 因覆盖保存产生 `.blend1`（例如继续修改主模型并再次导出），
按上表第四行处理：保留、入库、在台账登记，不得清理掉。

另存明确版本名（上表第二行）仍然是**独立方案**的正确做法：`.blend1` 只是自动的上一时刻快照，
不能替代"另存文件名或版本目录"所表达的方案分叉；两者并行遵守，不互相替代。

预览图在导出 GLB 之后单独渲染，不进 GLB。远山剪影与悬浮石是**纯视觉、无碰撞**，
不会在航线中制造隐形障碍。既有探索资产（庭院 / 群山 / 角色）未改动、未删除。
