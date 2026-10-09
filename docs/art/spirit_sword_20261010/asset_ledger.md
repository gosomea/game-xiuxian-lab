# 共享灵剑几何 · 2026-10-10

新共享导出 `src/game/shared/sword_cast/models/spirit_sword_20261010.glb` 为既有程序剑阵网格的相同几何副本，原 `array_sword.glb` 保留。源仍为仓库内 `docs/art/bound_sword_20261009/bound_sword_20261009.blend`，复现脚本为 `tools/art/generate_bound_sword_20261009.py`。共享版本供天轮、巨剑、剑雨使用，不建立对旧剑阵叶子包的运行依赖。

单网格单材质、38 三角面。导出局部剑尖 −Z = −0.702m、柄尾 +0.155m，总长0.857m；原点在剑格。使用 SwordSpellVisual.TIP_LENGTH=0.702 与 TOTAL_LENGTH=0.857，以实际缩放换算剑尖位置。三种视觉在各自 View 中组合，同一几何不重复导出动作版本。

依据 [实施决策](../../../notes/implemented/gameplay/2026-10-10-sword-spell-exploration.md)。新导出走 LFS。

## 原创合成命中音

`generate_sword_audio.py` 用 Python 标准库、固定随机种子生成 `src/game/shared/sword_cast/audio/giant_impact.wav`（0.70秒低频重击与短金属余响）和 `light_sword.wav`（0.23秒轻落剑声），44.1kHz 单声道16-bit。脚本和 WAV 都进入 Git；运行时不依赖 Python。无需外部素材或授权。三维声源跟随命中点；重击与批次轻声分别限频。主 Agent 验收音频资源与播放请求，主观听感留供后续调节。
