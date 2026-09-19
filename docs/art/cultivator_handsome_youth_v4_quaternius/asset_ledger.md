# 英俊少年修士 v4（Quaternius 路线）资产台账

日期：2026-09-19

## 来源链 A：成熟连续衣装与 Regular Male 骨架

- 原作者/资产包：Quaternius，Modular Character Outfits - Fantasy，Male Peasant（Regular Male 比例）。
- 原始许可：CC0 1.0 Universal；原文保存为 `source/QUATERNIUS-OUTFITS-LICENSE.txt`。
- 固定镜像：https://github.com/agentkaerf/FreeModels
- 固定 commit：`db3df04d1e4714298a09510b26fb6de6645138a2`
- 镜像原路径：`Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf`
- 下载日期：2026-09-19
- 本地原件 SHA-256：`8f5a6cf6c1cf96e0a0f8e1a861b4245d42b7f88d44e5076da3d48f3fc52f4e76`

## 来源链 B：兼容头脸

- 原作者/资产包：Quaternius，Universal Base Characters，SuperHero Male。
- 原始许可：CC0 1.0 Universal；原文保存为 `source/QUATERNIUS-LICENSE.txt`。
- 固定镜像：https://github.com/programasweights/avatar
- 固定 commit：`ddd5fc34a445bcded3cf9836607aaeebc19a5c78`
- 镜像原路径：`public/assets/character.glb`
- 本地原件 SHA-256：`d6f3b64cab629f6ddca9ba063811aeffd3663a8a4e49ade47cd9505dc2bbd70f`

## 本项目改造

- 保留 Regular Male 的 65 骨 Quaternius Humanoid armature、bind/rest pose、成熟衣装拓扑、UV、法线/ORM 与原权重。
- 以拓扑连通域规则移除盘扣、腰扣和肩部装饰小岛；不把练功服装饰带入新方向。
- 收窄胸背、手臂和大腿，建立贴身交领、双层腰封、四片柔软开衩短摆、深蓝软靴。
- 头脸沿兼容 Quaternius 权重接入并作青年化比例调整；五束长发目前统一绑定 Head，几何已分段，后续真实动作轮再加辅助发骨链。
- 色卡：月白为主，青蓝为辅，深蓝收边，小面积暖金/翠玉。
- 主资产保留骨架与权重，目标兼容 Quaternius Universal Animation Library；本轮未上传 Mixamo，也未跑真实 walk/run/jump 动画。

## 用户视觉参考边界

用户提供的四张本地图只用于提炼“白蓝轻装、前腿开放、年轻俊美、半束长发”的共同语言。参考图没有复制进资产目录，未抽取纹样、贴图或几何，也不复刻其中具体版权角色。

## 输出与边界

`cultivator_handsome_youth_v4_quaternius.blend` 是可编辑主源；`cultivator_handsome_youth_v4_quaternius_rigged.glb` 是 Godot 候选。`iterations/` 同时保留 iteration 01 的失败方向证据和 iteration 02 的纠偏结果；四向彩色/灰模、2.5D size 18/6、pose stress 和 `build_manifest.json` 是审计证据。

本轮仅完成白模/色块方向稿。技术检查不替代审美判断；尚未做独立静态 80/100 门禁，也尚未跑真实动作，因此不得称为最终角色或接入运行时。
