# 现成人体步行动作对照资产台账

依据：[决策 note](../../../notes/implemented/art/2026-09-27-third-party-walk-comparison.md)。本目录的所有试验版本都是探索资产；`trials/` 是停用版本的保留位置，不是清理目录。

## 人物与来源

现有人物网格、材质、蒙皮和 22 骨骨架来自仓库已提交的 `src/game/actors/swordsman/models/cultivator_tripo_v9.glb`。此次只迁移动作，未重建人物，也未改现役 `cultivator_xianxia_motion_v1.glb`。

| 动作来源 | 固定版本与原件 | 使用条件 |
|---|---|---|
| KayKit `Walking_A` | [本仓原件](../kaykit_route_ab/upstream/kaykit-adventurers-1.0-672074b/Rogue_Hooded.glb)，上游 [KayKit Adventurers](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) commit `672074b73ba276876a19e8816ecdc5241817ab47`；SHA-256 `93e6e25213009952276d9cf34f5d96a243767334c66f280db0433ddfabb91545` | [原包 LICENSE](../kaykit_route_ab/upstream/kaykit-adventurers-1.0-672074b/LICENSE.txt)：CC0，允许修改及商用，署名非强制。 |
| CMU Subject 16 `16_47` | [BVH 原件](upstream/cmu_016/16_47.bvh)，[转换者声明](upstream/cmu_016/READMEFIRST.txt)；[CMU 索引](https://mocap.cs.cmu.edu/search.php?subjectnumber=16)，[转换版仓库](https://github.com/una-dinosauria/cmu-mocap) commit `09a07f54f3bbb58797325f009282d0b2048a2871`；BVH SHA-256 `2138c2e46a95052a437a71b1bff5680fb490636c989556576b0533754ee61cf6`，声明 SHA-256 `8e6fe2e640b3728ef2e43e722cb5ae9cdf0010028c0517c4226ed165f9037930` | CMU 原数据可用于研究、教学及商业用途；转换者 Bruce Hahne 在随附声明中说明对这个 BVH 转换版不附加限制。原数据不作为独立商品销售。 |

CMU BVH 原件为 417 帧、120 Hz。只取第 63–199 帧：从稳定步行开始到下一次近似相同的全身姿态，首尾九个主骨骼的姿态差范数约 5.65°。按每 4 帧取一帧生成 30 Hz、35 帧的循环动作；水平根位移由游戏控制。KayKit 源为 24 Hz，采样到 30 Hz。构建脚本是 [build_walk_source_comparison.py](../../../tools/art/build_walk_source_comparison.py)。

CMU 原件保留原有 CRLF 和行尾空格以保持哈希可核对；同目录 `.gitattributes` 只对这两份上游原件关闭 Git 的空白检查，不修改文件内容。

## 派生文件与替代关系

| 版本 | 源与导出 | 结论 |
|---|---|---|
| v1 | `trials/first_export/*.blend`、`*.glb` | 首次导出误把 KayKit 原包 76 段动作带入；封存。 |
| v2 | `trials/second_export/*.blend`、`*.glb` 与渲染 | 仅含两段候选，但双臂仍沿 T-pose 方向；封存。 |
| v3 | `trials/third_export/*.blend`、`*.glb` 与渲染 | 添加自然下垂基础臂姿；CMU 肩部仍水平；封存。 |
| v4 | `trials/fourth_export/*.blend`、`*.glb` 与渲染 | 分离摆臂增量，发现 CMU 源头前段包含非正常步行肩姿；封存。 |
| v5 | [Blender 源](cultivator_walk_sources_v5.blend)、[Godot GLB](../../../src/game/actors/swordsman/models/cultivator_walk_sources_v5.glb)、[构建清单](build_manifest_v5.json) | CMU 只取稳定循环段；KayKit 摆臂/跨步减幅。当前独立对照资产，**未替换现役动作**。 |

v5 GLB 为 62,746,160 bytes，SHA-256 `58a00ee3860871992df27d52f1656a04cf2748d8e5b2a42241c52a0f189b3a6b`。Godot 导入时抽取的三张贴图和 `.import` 描述符在 `src/game/actors/swordsman/models/` 与 GLB 同目录，连同源 `.blend` 和停用版本入 Git。Blender 5.2.1 构建，Godot 4.6 导入运行。

## 逐帧检查与观察

[v5 鞋底逐帧报告](ground_contact_v5.json)在导出的蒙皮网格上测最低点：CMU `-0.0015..+0.0015 m`，KayKit `-0.0028..+0.0001 m`。这只能证明没有整体浮空，不能证明支撑脚完全不滑。

同一量法量足相对骨盆的支撑段，现役 `walk` 自然速度约 `1.584 m/s`，CMU 候选约 `1.235 m/s`，KayKit 约 `1.333 m/s`（仅找到一段足够长的支撑段，置信度低）。独立场景统一用 `1.55 m/s` 移动，三个动作的播放倍率分别约 `0.98 / 1.16 / 1.26`。CMU 可用支撑段的足轨迹最大横向偏差约 `0.033 m`；它仍会有少量脚滑，不能把贴地报告视为最终验收。

[v5 侧面 CMU](renders/v5_cmu/side.png)的手臂自然下垂，步态更接近日常行走；[v5 侧面 KayKit](renders/v5_kaykit/side.png)仍有膝部过高和手部后收，气质不适合作为现役修士步行。 [Godot 同镜头实机截图](../../playtest/2026-09-27-walk-sources/compare-loop-v2-candidate-2.png)用于观察整合结果。最终审美和手感还需人工连续观看；本轮不提升任何候选到正式人物。
