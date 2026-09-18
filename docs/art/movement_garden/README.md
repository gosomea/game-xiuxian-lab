# movement_garden 美术资产

2026-09-18 由 AI 代理编写脚本、经本地 Blender 5.2.1 LTS 独立后台进程程序建模，
**全部为程序原创几何**：没有下载资产、没有素材库、没有贴图，未调用图像/3D 生成服务，
没有骨骼与动画。唯一外部依赖是 Blender 自带 Python（`bpy` / `mathutils` / `bmesh`）。

决策依据：[character-movement-garden](../../../notes/implemented/gameplay/2026-09-18-character-movement-garden.md)。

## 源文件与生成物

| 文件 | 角色 | 生成方式 |
|---|---|---|
| `cultivator.blend` | **旧版**角色源（blocky 立方体人体，历史归档，非当前源） | `tools/art/generate_movement_assets.py` |
| `movement_garden.blend` | 庭院源文件（含预览相机/灯光，不导出） | `tools/art/generate_movement_garden.py` |
| `garden_preview.png` | **修复前**庭院预览（历史原件，原位保留） | 修复前脚本末尾渲染 |
| `garden_preview_pre_surface_clearance.png` | 同上字节的历史副本（命名标注 surface clearance 之前） | 复制自 `garden_preview.png` |
| `garden_preview_surface_clearance.png` | 修复后庭院预览（Cycles 24 采样，1200×900，非运行时素材） | 同上脚本末尾渲染 |
| `movement_garden.blend1` / `movement_garden.blend11` | **修复前**庭院源文件副本（重导时误生成的版本备份，已按保留规则留档） | Blender 保存时自动产生 |
| `src/game/actors/swordsman/models/cultivator.glb` | 角色运行时资源（**原路径保留**，当前为 refined 版） | `tools/art/generate_cultivator_refined.py` |
| `src/levels/experiments/character_movement/movement_garden.glb` | 庭院运行时资源 | 第二个脚本导出 |

**角色当前源不在本目录**：refined 版角色源为 `docs/art/cultivator_refined/cultivator_refined.blend`，
生成器 `tools/art/generate_cultivator_refined.py`，它的唯一真源与完整读数见
[cultivator_refined README](../cultivator_refined/README.md) 与 [台账](../cultivator_refined/asset_ledger.md)。
本目录的 `cultivator.blend` 是 refined 之前的旧版角色源，按探索资产保留规则**原位留档、不删除、不覆盖**。

庭院资产的真源是本目录；`src/` 下的 GLB 是导出产物，不要手改。

## 复现命令

以下命令为 macOS（Blender 5.2.1 LTS）实测可用的完整路径写法；其他平台把可执行文件换成
PATH 中的小写 `blender`（即 `blender --background --factory-startup --python …`）。
命令不操作任何用户已打开的 .blend（全程 `--factory-startup` + `--background`）。

```sh
# 角色（当前 refined 版；写同一 GLB 路径）
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_cultivator_refined.py -- build preview
# 庭院
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_movement_garden.py
```

> **不要为了重现旧版角色而重跑 `generate_movement_assets.py`**：它写的是同一个
> `src/game/actors/swordsman/models/cultivator.glb` 路径（两脚本的 `CHAR_GLB` 相同），
> 重跑会静默把运行时角色覆盖回 blocky 旧版。重现旧版请直接查看归档源
> `docs/art/movement_garden/cultivator.blend`。

**重跑会覆盖 .blend 与 GLB 导出文件。** 2026-09-18 第三次修改（独立审计修正：Scholar rock base 底面下沉、
Pavilion column base 底面钉到 `PAVING_BOTTOM−0.02`）后，本表已更新为**审计修正后**读数；
修复前的旧件行原样保留。生成器已设 `save_version=0`，重跑不新增轮转文件，
`movement_garden.blend1` / `.blend11`（修复前源副本）原地保留、未被覆盖。
固定随机种子的重跑仍会覆盖 `.blend`/`.glb` 与 `garden_preview_surface_clearance.png`。

`cultivator.glb` 的真实路径是 `src/game/actors/swordsman/models/cultivator.glb`（早期文档漏写 `.glb` 后缀，
路径已更正）。该 GLB 当前由 **refined** 生成器产出，读数见下节与
[cultivator_refined 台账](../cultivator_refined/asset_ledger.md)。本目录的历史沿革：
庭院修复轮只修改并重导庭院，角色文件当轮未被写操作触碰；角色模型此后由独立的美术重建轮
（`generate_cultivator_refined.py`）在原路径上更新，属「在原模型上继续修改」，旧源以
`docs/art/movement_garden/cultivator.blend` 原位留档。

| 文件 | 字节 | sha256 |
|---|---|---|
| `cultivator.blend`（**旧版**角色源，历史归档） | 147621 | `dff485c89fb4d02bfae7ab59cc55e4d3b19d63d9d2d8b691a029d93ba92bb446` |
| `src/game/actors/swordsman/models/cultivator.glb`（**当前** refined 版；源 `docs/art/cultivator_refined/cultivator_refined.blend` 155563 B / `0370960d…`） | 121736 | `70fc5eb6a4cd60579ac06bde5e65da6cc22e32f48316eae53e813387ae36b426` |
| `movement_garden.blend`（2026-09-18 独立审计修正后） | 257361 | `c690ff65983c9272836f48b931f4e17e0f781abdd940d421ee209bdc1790eb83` |
| `movement_garden.glb`（同上） | 2451280 | `6433d276d0105c1728f6b9d18dd2dc8850a3ed491113c2172a3bf90c5c901512` |
| `garden_preview_surface_clearance.png`（同上，新预览） | 1154508 | `3847ff1ae39028935ea62ef849ad54bde9bde6e66023b1c0da99f273b938c20f` |
| `movement_garden.blend`（**修复前**，旧件） | 256742 | `f99acf09ed21809da8a961be10ff0f75d33bc724b02c61c01a21823b69abdf5f` |
| `movement_garden.blend1` / `movement_garden.blend11`（修复前源副本） | 256742 | 同上 `f99acf09…9abdf5f` |
| `movement_garden.glb`（**修复前**，旧件） | 2418472 | `44a7f011a2813bd0a086b72dcea63d38feb803cff21a3c43aa0fbc1a92d42ad3` |
| `garden_preview.png`（**修复前**预览，原位保留） | 1132128 | `5d24571740699be8af2dba6281638b4499edb6cb50a257f98ddc09ec5088249a` |
| `garden_preview_pre_surface_clearance.png`（同上字节副本） | 1132128 | `5d24571740699be8af2dba6281638b4499edb6cb50a257f98ddc09ec5088249a` |

## 数值（2026-09-18 读数）

两端读回一致：`.blend` 用 Blender 5.2.1 后台只读打开，`.glb` 直接解析 JSON chunk。

| 指标 | cultivator（当前 refined 版） | movement_garden |
|---|---|---|
| 网格对象 | **23** | 319（另 1 相机、1 灯光仅在 .blend） |
| 三角形 | **4952** | 40720（含 Bevel/Solidify 修改器求值结果） |
| 材质 | **8** | 13（.blend 内另有一个 0 用户的工厂残留 `Material`，未进 GLB） |
| 尺寸（长×宽×高，GLB 全件包围盒） | **0.507 m × 0.418 m × 1.775 m**（**身高 1.700 m**，1.775 含头顶发髻） | **18.0 m × 14.0 m × 4.86 m** |
| 顶点属性 | POSITION / NORMAL / TEXCOORD_0 | 同左 |
| 图片 / 贴图 / 动画 / 骨骼 | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| 导出器 | Khronos glTF Blender I/O v5.2.40 | 同左 |

- 角色脚底在 Blender z=0，身高（不含发髻）归一化到 1.70 m，每个对象世界原点为单位矩阵；
  旧版角色尺寸为 0.77 m × 0.66 m × 1.70 m（历史读数，见上表与 refined 台账）。
- 庭院地面 y≈0，上沿 4.04 m、底座 −0.82 m；Godot 侧另建碰撞代理，GLB 不含碰撞体。
- 独立审计修正（2026-09-18 第三次修改）：`Scholar rock base` 顶保持 **0.970**（对 1 m 碰撞代理余量约 3 cm）、
  底 **−0.270**（比 plinth 顶 −0.230 下沉 40 mm，做法是调中心 + Z 半径）；`Pavilion column base` 顶保持 **0.335**、
  底 **0.010**（= `PAVING_BOTTOM − 0.02`，低于随机铺砖顶 0.082188–0.087939 至少 72.2 mm）。
- 角色读数（2026-09-18 refined 重建，实测解析 GLB JSON chunk）：23 网格 / 4952 三角形 / 8 材质 / 0 图片 / 0 动画 / 0 骨骼；
  材质为 `Robe_Indigo`、`Robe_Indigo_Dark`、`Sash_Wood_Gold`、`Hair_Black`、`Skin`、`Shoe_Dark`、`Inner_Ivory`、`Trim_Ivory`。
  **旧版读数（历史，供对照）**：17 网格 / 5080 三角形 / 7 材质；材质为 `Robe_Blue` 1112、
  `Inner_Ivory` 768、`Skin` 1364、`Hair_Black` 900、`Trim_Ivory` 432、`Sash_Teal` 324、`Metal_Gold` 180。
  两个版本的源与完整差异见 [cultivator_refined README](../cultivator_refined/README.md)。
- 庭院材质 13 个均为纯色 PBR，最重的是 Celadon ceramic 14796、Ivory paving 7668、Bamboo leaves 7680。

## 轴向（此前文档有误，已修正）

Blender 为 Z-up，glTF 导出 `export_yup=True`，因此 **Blender +Y → glTF/Godot −Z**。

角色部件朝 Blender −Y 建模。**当前 refined 脚本**由 `normalize_orientation()` **先等比缩放、再绕 Z 转 180°**，
再经 `export_yup=True` 的 `(bx,by,bz) → (bx,bz,−by)` 映射，导出正面为 Godot **−Z**；该契约由
`assert_axis_contract()` 在写出的 GLB 上直接断言（实测 `nose_z=-0.1111`、`eye_z=-0.0887`、
`toe_z=-0.1470`），与 `Swordsman._face_aim()` 的「模型局部 −Z 为正面」一致。
**旧版脚本**用 `orient_parts()` 完成同样的缩放 + 180° 旋转（旧文读数：交领 glTF z ∈ [−0.198, 0.007]、
鞋尖 z=−0.130），其注释写的「−Y == Godot −Z」漏掉该旋转，是错误描述；几何本身正确。
轴向细节见 [cultivator_refined README](../cultivator_refined/README.md)。

## 已核对 / 当前限制

已核对：GLB 与 .blend 的对象数、三角形、材质、包围盒一致；脚本清理后仍有合法 Python 语法；
两处 .blend 均由 Blender 5.2.1 只读打开成功。Godot 端最终验收已完成：32 项真实物理断言全 PASS、
87 条单测通过、4 张窗口截图人工确认，见 [角色移动庭院验收](../../playtest/2026-09-18-character-movement.md)。

限制与未验证项：

- 构图已在 Godot 截图验收（见上）；手感与配色审美由使用者实机判断。几何「无穿插/无浮空」只做了数值核对。
- 程序建模是风格探索，不是成品雕刻、绑定或动画；角色两版（旧版与本目录留档、refined 当前版）均无骨骼
  （实测 0 skin / 0 animation），移动场景里的动作来自纯表现脚本 `cultivator_presentation.gd`。
- 庭院草叶类资产三角形占比高，属可优化项（未做减面）。
- `garden_preview.png` 是一次性渲染（现为修复前历史件，不再被重跑覆盖）；新渲染写入 `garden_preview_surface_clearance.png`。
- 本仓根目录暂无 LICENSE 文件；这批资产为本仓原创，如需对外分发其授权声明由使用者补充。

## 核对命令（只读，可复现）

```sh
# GLB：直接解析 JSON chunk，统计 mesh/material/三角形/包围盒
python3 - <<'PY'
import json, struct
d = open('src/game/actors/swordsman/models/cultivator.glb','rb').read()
off = 12
while off < len(d):
    n, t = struct.unpack_from('<II', d, off); off += 8
    if t == 0x4E4F534A:
        g = json.loads(d[off:off+n]); break
    off += n
print(len(g['meshes']), len(g['materials']),
      sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes'] for p in m['primitives']))
PY

# .blend：后台只读打开并打印对象/三角形/材质（非 macOS 用 PATH 中的 blender）
# 角色当前源（refined）：
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-expr \
"import bpy; bpy.ops.wm.open_mainfile(filepath='docs/art/cultivator_refined/cultivator_refined.blend', load_ui=False); \
print(len([o for o in bpy.context.scene.objects if o.type=='MESH']), [m.name for m in bpy.data.materials])"
# 旧版角色源（历史归档）：
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-expr \
"import bpy; bpy.ops.wm.open_mainfile(filepath='docs/art/movement_garden/cultivator.blend', load_ui=False); \
print(len([o for o in bpy.context.scene.objects if o.type=='MESH']), [m.name for m in bpy.data.materials])"
```
