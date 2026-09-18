# 实验场景

每个模块使用独立目录与可直接运行的 `.tscn`。组合实验按已讨论的设计建立。

`character_movement/mountain_realm.tscn` 是群山宗门移动探索场景（平面移动 / 跳跃 / 御剑三能力，180×160 m、五峰、三落脚点）；`movement_garden.tscn` 保留作小场景回归，只观察修士移动、转向与 Blender 庭院呈现。剑法及其余模块尚未实现；`../empty_stage.tscn` 提供独立空白 3D 基底。模块状态以 `res://data/content/experiments.json` 为准。