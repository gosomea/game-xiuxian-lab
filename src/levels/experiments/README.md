# 实验场景

每个模块使用独立目录与可直接运行的 `.tscn`。组合实验按已讨论的设计建立。

`character_movement/movement_lab_hub.tscn` 是角色移动子实验目录，数据真相源为 `res://data/content/character_movement_subexperiments.json`。2026-10-10 使用者确认本轮移动探索完成，模块与十项子实验均为 `ready`：`camera_lab.tscn`（镜头实验室）、`motion_stage.tscn`（人物动作工作台）、`ground_contact_course.tscn`（地形接触训练场）、`sword_flight_course.tscn`（御剑飞行训练场）、`state_transition_lab.tscn`（状态切换压力场）、`movement_garden.tscn`（移动庭院）、`mountain_realm.tscn`（群山宗门）、`jade_paper_sample.tscn`（青玉纸白样板）、`ink_lakeside_sample.tscn`（水墨湖岸样板）和 `west_lake_sunset.tscn`（西湖夕照）。全部子场景统一返回 `movement_lab_hub.tscn`；`movement_lab_hub` 的 Esc 与返回按钮回到顶层 `../lab_hub.tscn`。

`sword_combat/sword_workbench.tscn` 是剑法工作台，状态 `exploring`，复用共享修士与镜头，比较剑气、飞剑出击、剑阵三招。其余六个计划模块仍无场景；`../empty_stage.tscn` 提供独立空白 3D 基底。模块状态以 `res://data/content/experiments.json` 为准。

`eastern_2d/market_square.tscn` 是首个独立 2D 实验：东方动漫风的青石坊市。WASD / 方向键四向步行，靠近路人按 E 交谈，Esc 关闭对话或返回顶层目录。该场景使用自己的 2D 人物、镜头和场地碰撞，不引用 3D 角色移动能力；后续二维场景按实际需求继续增设。
