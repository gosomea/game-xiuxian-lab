# 预览版本说明

主 Agent 审查阶段图时发现首版巨剑图采样把快速高台的第二次同名施法 frame 编号混入第一次施法，导致 impact/fade 栏误取早期凝剑画面。采用首个连续 frame 段的 `*-phases-v2.png` 为正确阶段图；首版保留作诊断资产。原窗口 PNG、motion/acceptance JSON 和按文件前缀合成的 MP4/GIF 没有此问题。

首次系统 Python 3.14/Pillow 绘制阶段图进程退出139；编码好的 MP4/GIF 保留，改用 Codex 附带 Python/Pillow完成阶段图。构建脚本保留已存在的编码资产，未覆盖旧探索图。
