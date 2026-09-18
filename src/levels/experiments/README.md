# 实验场景

每个模块使用独立目录与可直接运行的 `.tscn`。组合实验按已讨论的设计建立。

`character_movement/movement_lab_hub.tscn` 是角色移动子实验目录，数据真相源为 `res://data/content/character_movement_subexperiments.json`，七项子实验全部有可运行入口：`camera_lab.tscn`（镜头实验室：镜头策略对比灰盒）、`motion_stage.tscn`（人物动作工作台：动作表现观察）、`ground_contact_course.tscn`（地形接触训练场：斜坡 / 台阶 / 墙角 / 窄路 / 边缘）、`sword_flight_course.tscn`（御剑飞行训练场：立体路线与落点）、`state_transition_lab.tscn`（状态切换压力场：切换 / 失焦 / 重置 / 拖墙清账）、`movement_garden.tscn`（移动庭院：小场景回归与 Blender 庭院呈现）、`mountain_realm.tscn`（群山宗门：平面移动 / 跳跃 / 御剑三能力，180×160 m、五峰、三落脚点）。全部子场景统一返回 `movement_lab_hub.tscn`；`movement_lab_hub` 的 Esc 与返回按钮回到顶层 `../lab_hub.tscn`。剑法及其余模块尚未实现；`../empty_stage.tscn` 提供独立空白 3D 基底。模块状态以 `res://data/content/experiments.json` 为准；角色移动子实验状态以 `res://data/content/character_movement_subexperiments.json` 为准。