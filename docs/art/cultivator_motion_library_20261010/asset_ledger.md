# 共享人物与独立动作库 · 2026-10-10

本轮只拆分存储与装配，没有改动作设计、网格、蒙皮、材质、速度或骨架。依据：[资产增长方案](../../../notes/implemented/process/2026-10-09-repository-binary-growth.md)。原始人物与动作来源继续见[上身扶正台账](../cultivator_upright_motion_20261009/asset_ledger.md)。

## 资产与依赖

| 资产 | 路径 | 本轮体积与用途 |
|---|---|---|
| 共享网格、材质、贴图、rest 与蒙皮 | `src/game/actors/swordsman/models/cultivator_upright_motion_20261009.glb` | 62,839,116 bytes；原文件保留，旧完整动作用于回归比较 |
| 共享 Blender 数据库 | `docs/art/cultivator_upright_motion_20261009/cultivator_upright_motion_20261009.blend` | 原文件保留，提供网格数据与三张贴图 |
| 现役可编辑动作源 | `cultivator_upright_motion_20261010.blend` | 364,315 bytes；本地 22 骨与七段 Action，0 张本地图片，网格和材质为相对库链接 |
| 现役独立动作库 | `src/game/actors/swordsman/models/motions/cultivator_upright_motion_20261010.glb` | 149,996 bytes；精确拆出原 GLB 动画数据，不重采样 |
| Blender 重导出验证库 | `src/game/actors/swordsman/models/motions/cultivator_upright_motion_20261010_blender_roundtrip.glb` | 151,448 bytes；从轻量源导出，保留作管线回归，未挂现役视觉 |

新源与两份动作 GLB 均进入 Git LFS。它们是本项目现有资产的派生物，没有新增外部素材或许可。旧探索版本全部保留。

共享视觉场景仍为 `cultivator_aligned_motion_20260927_visual.tscn`。模型子节点名、唯一 Skeleton3D 和唯一 AnimationPlayer 不变；`CultivatorSkeletonPresentation.animation_library` 显式挂载新独立库。库使用空命名空间，七段精确名继续为 `idle/walk/run/jump/idle_guarded/meditate/sword_ride`。

## 后续动作编辑

1. 在 Blender 打开本目录的轻量 `.blend`。本地 Armature 与 Action 可以编辑；链接网格提供实际蒙皮预览。
2. 新探索方案用 Blender 的 **Save As** 另存到新版本目录，使库路径自动相对重映射。新版本必须保留自己的源与动作导出。不要用旧完整人物生成器给每个动作版本再次导出整份人物。
3. 用下列导出器导出独立库。默认拒绝覆盖已有输出；只有继续修改同一资产时才使用 `--replace`，并记录台账。
4. 导出器检查共享骨架的骨名、父子关系、rest 和 Armature 祖先变换；新增骨、改蒙皮或改网格时先建立新共享模型版本，再将动作绑定到它。
5. 在共享视觉场景只更换 `animation_library` 引用，保持共享模型引用。新的 GLB 自动生成 `AnimationLibrary` 的 `.import` 配置。
6. 用四个量具检查轻量源，再重导入 Godot、运行测试和窗口验收。轻量 GLB 没有可量鞋底的网格，不能把它当作完整人物传给旧 `--glb` 流程。

轻量源的库路径为 `//../cultivator_upright_motion_20261009/cultivator_upright_motion_20261009.blend`。分发时保留仓库目录结构和共享 `.blend`；只拷贝轻量源到仓库外会丢失几何依赖。

## 复现

以下命令在仓库根执行；替换本机 Blender/Godot 路径。创建源与导出验证版本默认要求新的输出路径。

```sh
Blender --background --factory-startup --python-exit-code 1 --python tools/art/cultivator_motion_assets.py -- create-source --shared-source docs/art/cultivator_upright_motion_20261009/cultivator_upright_motion_20261009.blend --output docs/art/cultivator_motion_library_20261010/cultivator_upright_motion_20261010.blend --report docs/art/cultivator_motion_library_20261010/source_report.json
python3 tools/art/split_cultivator_motion_glb.py --source src/game/actors/swordsman/models/cultivator_upright_motion_20261009.glb --output src/game/actors/swordsman/models/motions/cultivator_upright_motion_20261010.glb --report docs/art/cultivator_motion_library_20261010/split_report.json
Blender --background --factory-startup --python-exit-code 1 --python tools/art/cultivator_motion_assets.py -- export --source docs/art/cultivator_motion_library_20261010/cultivator_upright_motion_20261010.blend --shared-model src/game/actors/swordsman/models/cultivator_upright_motion_20261009.glb --output src/game/actors/swordsman/models/motions/cultivator_upright_motion_20261010_blender_roundtrip.glb --report docs/art/cultivator_motion_library_20261010/export_report.json
```

动作量具（`M` 是轻量源；这里的源验证与 Godot 独立动作库回归互相补充）：

```sh
M=docs/art/cultivator_motion_library_20261010/cultivator_upright_motion_20261010.blend
D=docs/art/cultivator_motion_library_20261010
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_aligned_motion_geometry.py -- --blend $M --report $D/geometry.json
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_locomotion_balance.py -- --blend $M --report $D/balance.json --check
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_glb_ground_contact.py -- --blend $M --report $D/ground_contact.json
Blender --background --factory-startup --python-exit-code 1 --python tools/art/measure_human_motion_posture.py -- --blend $M --report $D/posture.json
Godot --headless --path src --import
python3 tools/assets/sync_lfs_attributes.py
git add .gitattributes docs/art/cultivator_motion_library_20261010 src/game/actors/swordsman/models/motions
python3 tools/verify/run_all.py --with-tests
```

`source_report.json`、`split_report.json`、`export_report.json` 分别记录相对库链接、原始动画字节拆分与重新导出。运行时逐关键帧/六相位等价和窗口结果见[运行记录](../../playtest/2026-10-10-asset-growth/report.md)。

本源在首次生成后的同资产迭代中修正了网格的父变换复制：保留 `matrix_basis` 与 `matrix_parent_inverse`，避免未更新依赖图时把 world 矩阵当作 local 再乘一次。生成器新增站立蒙皮鞋底等价自检；没有修改骨架动作或共享模型。
