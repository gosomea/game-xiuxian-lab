# cultivator_refined 美术资产

2026-09-18 由 AI 代理编写脚本、经本地 Blender 5.2.1 LTS 独立后台进程程序建模，
**全部为程序原创几何**：无下载资产、无素材库、无贴图、无骨骼与动画数据。
唯一外部依赖是 Blender 自带 Python（`bpy` / `bmesh` / `mathutils`）。

决策依据：[群山宗门自然地貌与庭院美术重建](../../../notes/implemented/art/2026-09-18-mountain-realm-visual-rebuild.md)（人物条目）。

## 源文件与生成物

| 文件 | 角色 | 生成方式 |
|---|---|---|
| `cultivator_refined.blend` | 本轮角色源文件 | `tools/art/generate_cultivator_refined.py` |
| `cultivator_front.png` / `_side.png` / `_three_quarter.png` / `_closeup.png` | 形体预览（Cycles 24 采样 + 降噪，非运行时素材） | 同一脚本 `preview` 阶段 |
| `src/game/actors/swordsman/models/cultivator.glb` | 运行时角色资源（**原路径保留**，旧庭院同样受益） | 同一脚本 `build` 阶段 |

本目录是这批资产的唯一真源；`src/` 下的 GLB 是导出产物，不要手改。

## 复现命令

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python tools/art/generate_cultivator_refined.py -- build preview
```

非 macOS 把可执行文件换成 PATH 中的小写 `blender`。全程 `--background --factory-startup`，
不操作用户已打开的 `.blend`。重跑会覆盖 `.blend`、GLB 与四张预览图。

## 设计约束（本轮视觉验收点）

- **不覆盖脸**：头发是开口发帽（开口半角 0.72 rad ≈ 41°），只覆盖头顶、后脑与两鬓，
  正面可见额头、眉、眼、鼻；侧面可见发际线与面部轮廓。发髻在头顶偏后，不是整颗黑球。
- **脸**：颅骨截面 + 下颌收窄 + 鼻楔 + 耳 + 眉眼，正/侧都成形。
- **下摆不是圆锥桶**：裙摆是前开口的 A 字外壳（`gap=0.30`、5 瓣涟漪、实体化厚度），
  开口处露出浅色内裙与两腿，深色下摆缘明确布料层次。
- **两脚与双袖可读**：鞋底平面在 z=0、圆头带跟；袖是垂坠宽袖，有袖口与露出的手。
- **比例**：身高 1.70 m，约 6.8 头身；足底 z=0，正面朝 Godot -Z（`export_yup` + 朝 -Y 建模）。

## 轴向（此前本文件写错，已按实测改正）

Blender Z-up；部件朝 Blender **-Y** 建模。导出前 `normalize_orientation()` 会把全部网格
**先等比缩放、再绕 Z 轴旋转 180°**，使正面转到 Blender **+Y**；随后 `export_yup=True` 按
`(bx, by, bz) -> (bx, bz, -by)` 映射，因此导出正面为 Godot **-Z**，与
`Swordsman._face_aim()` 的「模型局部 -Z 为正面」一致。

**180° 旋转不可省略**：上一版本文档只写了 +Y→-Z，漏掉该旋转，脚本重写时相应丢失了旋转，
导致脸朝 Godot +Z（实测 `Face_Eyes` z-center 为 **+0.0887**）。现已修复，并由
`stage_build()` 的 `assert_axis_contract()` 在**写出的 GLB 上**直接断言，无法再静默回归：

```
AXIS gltf(Godot) | head_z=+0.0020 nose_z=-0.1111 eye_z=-0.0887 toe_z=-0.1470 bun_z=+0.0338
            | nose<0=True toe<0=True bun>head=True
```

断言内容：鼻/眼 z 必须小于头 z（脸朝 -Z）、鞋尖 z<0、发髻在脸之后、鞋底不低于 y=0；
另断言交领与胸前内襟在同一高度窗口内确实高于袍身外壳（防止被埋进胸口）。

角色脚底在 Blender z=0，每个对象世界原点为单位矩阵，不引入额外变换。

## 与旧版本的差异


| 项 | 旧 `generate_movement_assets.py` | 本轮 `generate_cultivator_refined.py` |
|---|---|---|
| 躯干 | 立方体胸/腰块 | 截面 loft 的胸腰渐变 + 肩斜 |
| 下摆 | 闭合圆锥裙 | 前开口 A 字壳（腰 0.138 → 摆 0.216）+ 实体厚度 + 深色缘 |
| 四肢 | 立方体袖/腿 | 肩→袖→手 **一体 loft**（无拼接缝）+ 锥形裤腿 |
| 头部 | 球 + 方颈 | 颅骨截面 + 独立鼻件 + 耳 + 贴面眉/眼 |
| 头发 | 包住半张脸的黑球 | 沿头型偏移的开口发帽（发际线随高度收窄）+ 头顶发髻 |
| 衣襟 | 无 | 沿袍面 loft 的交领 V 带 + 前胸内襟 + 下摆分片 |
| 法线 | 全面平滑 | 平滑 + 按 46° 标记锐边（衣褶清晰、曲面不破） |

## 纯表现层（模型本体的运动近似）

`src/game/actors/swordsman/cultivator_presentation.gd`（约 130 行，同 actor 包）挂在
`swordsman.tscn` 的 `Visual/CultivatorPresentation`，只读 `actor.motion()` 的
`actual_velocity` / `on_floor` / `flight_active`，**不写任何 Component 字段、不新增 Capability、
不动物理根与胶囊**。删除该节点后角色行为与碰撞完全不变。

`_ready()` 按实测分件包围盒建立枢轴并把网格 reparent 进去（枢轴仍在 GLB 根内）：

| 枢轴 | 成员 | 实测枢轴高度 |
|---|---|---|
| 髋 ×2 | `Leg_L/R` + `Foot_L/R` | y ≈ 0.696（Leg 顶面） |
| 肩 ×2 | `Arm_Sleeve_L/R` + `Cuff_L/R` + `Hand_L/R` | y ≈ 1.421（袖顶面） |
| 腰 | `Robe_Skirt` + `Robe_HemBand` + `Robe_Panel` | y ≈ 0.974（裙顶面） |

表现内容：髋部前后交替摆动（相位由水平速度 / `stride_meters` 推进，停步即停相）、双臂反相摆动、
袍摆随速度与御剑后拖、腾空收腿、御剑时前倾 + 双臂外张平衡 + 厘米级悬停起伏。

**已知边界**：GLB 无骨骼，这是**分件刚体摆动**，不是骨骼动画，也不是 IK 步态；脚掌没有锁定，
因此脚底会有小幅滑动；竖直起伏刻意只有厘米级（0.006–0.035 m）。分件拓扑为独立刚体、
袖与袍是连体 loft，无法做肘/膝弯曲，故不造新 rig。手感是否可接受由使用者在 Godot 中试玩判断。

## 限制与未验证项

- Godot 端导入、材质与实机画面由环境集成/验收代理验证；本目录只含 Blender 端读数与预览。
- 无骨骼、无动画数据；后续步行摆臂/衣摆/御剑姿态只能是纯表现脚本，不得变成第 4 个 Capability，
  也不改速度、重力与能力互斥。
- 程序建模是风格化形体探索，不是成品雕刻；预览为 Cycles 一次性渲染，重跑会覆盖。
- 本仓根目录暂无 LICENSE 文件；资产为本仓原创，对外分发授权声明由使用者补充。

登记人：角色美术代理；日期 2026-09-18。
