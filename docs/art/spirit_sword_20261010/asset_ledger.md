# 共享灵剑几何 · 2026-10-10

新共享导出 `src/game/shared/sword_cast/models/spirit_sword_20261010.glb` 为既有程序剑阵网格的相同几何副本，原 `array_sword.glb` 保留。源仍为仓库内 `docs/art/bound_sword_20261009/bound_sword_20261009.blend`，复现脚本为 `tools/art/generate_bound_sword_20261009.py`。共享版本供天轮、巨剑、剑雨使用，不建立对旧剑阵叶子包的运行依赖。

单网格单材质、38 三角面。导出局部剑尖 −Z = −0.702m、柄尾 +0.155m，总长0.857m；原点在剑格。使用 SwordSpellVisual.TIP_LENGTH=0.702 与 TOTAL_LENGTH=0.857，以实际缩放换算剑尖位置。三种视觉在各自 View 中组合，同一几何不重复导出动作版本。

依据 [实施决策](../../../notes/implemented/gameplay/2026-10-10-sword-spell-exploration.md)。新导出走 LFS。
