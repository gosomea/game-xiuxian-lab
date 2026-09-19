# 青玉短打修士 v3（Quaternius 路线）资产台账

日期：2026-09-19

## 来源链

- 原作者/资产包：Quaternius，Universal Base Characters，Superhero Male。
- 原始许可：CC0 1.0 Universal；原文保存为 `source/QUATERNIUS-LICENSE.txt`。
- 官方页面：https://quaternius.com/packs/universalbasecharacters.html
- 固定镜像：https://github.com/programasweights/avatar
- 固定 commit：`ddd5fc34a445bcded3cf9836607aaeebc19a5c78`
- 镜像原路径：`public/assets/character.glb`
- 下载日期：2026-09-19
- 本地原件 SHA-256：`8f5a6cf6c1cf96e0a0f8e1a861b4245d42b7f88d44e5076da3d48f3fc52f4e76`
- 镜像的来源说明原样保存为 `source/MIRROR-ASSETS.md`。免费 Standard 包只包含 Superhero 比例；Regular Male 不在合法免费源中，因此未伪称使用 Regular Male。

## 本项目改造

- 保留 65 骨 Quaternius Humanoid armature、bone rest pose、原人体权重、连续肩腋髋膝手脚拓扑与 UV。
- 收窄躯干肩胸，制作贴体交领短外衫、窄袖、连续腰封、四片弧形短摆、收腿裤、软靴、发际/鬓发/发髻。
- 新衣装壳体直接复制底座成熟表面与权重；交领、短摆和发饰按邻近人体骨骼显式蒙皮。
- 主色 `#263B5C`、深靛 `#18283F`、月白 `#E4DFD2`、暖金 `#B7924C`。
- 主资产保留骨架与权重，目标是直接使用 Quaternius Universal Animation Library；本轮没有上传 Mixamo。

## 输出与边界

`cultivator_shortcoat_v3_quaternius.blend` 是可编辑主源；`cultivator_shortcoat_v3_quaternius_rigged.glb` 是 Godot 候选。`iterations/` 保存至少两轮不可覆盖的视觉迭代。四向彩色/灰模、2.5D size 18/6、pose stress 和 `build_manifest.json` 是审计证据。

技术检查不替代审美判断；独立静态审查低于 80/100 时必须标记失败候选，不得接入运行时。
