# 实验记录

一个模块可有多轮实验，也可有组合实验。记录按 `YYYY-MM-DD-module-topic.md` 命名，不追求长文。

每次留下：本轮观察什么；如何打开场景与操作；实际看到了什么；喜欢/不满意什么；当前结论；已知边界；下一次值得比较的选项。主观手感由使用者试玩后填写，自动检查不替代人的判断。

当前已有角色移动模块（`character_movement`，exploring）：入口为子实验目录（`movement_lab_hub.tscn`，清单见 `res://data/content/character_movement_subexperiments.json`），七项子实验（镜头实验室、人物动作工作台、地形接触训练场、御剑飞行训练场、状态切换压力场、移动庭院、群山宗门）全部有可运行场景；群山宗门为组合验收场景、移动庭院为小场景回归。其余模块仍为 planned。模块清单以 `src/data/content/experiments.json` 为准；**本轮验收以 [集成报告](../playtest/2026-09-18-character-movement-subexperiments.md) 为准**（七个场景入口与返回链、Tier 0 与全部 standalone 计数）；群山宗门的组合场景证据见 [群山验收](../playtest/2026-09-18-mountain-traversal.md)，各子实验另有自己的报告。
