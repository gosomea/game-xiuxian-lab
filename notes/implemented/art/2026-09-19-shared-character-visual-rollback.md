# Note: 共享移动场景回退 Blender 原创角色

Status: implemented

## 问题

除青玉纸样板外的移动场景继续通过 `cultivator_visual.tscn` 使用
`cultivator_jade.glb`，其宽袖袍角色不适合现阶段移动动作观察。使用者要求这些场景先换回
最早建立的 Blender 原创角色路线，同时保留青玉纸样板现役的 v7 骨骼动画底座。

## 决策

共享 `cultivator_visual.tscn` 的模型资源改回
`res://game/actors/swordsman/models/cultivator.glb`。该资源来自本仓 Blender 程序建模路线，
继续复用既有 `CultivatorPresentation` 程序动作，不改变角色物理、能力、碰撞、移动数值、
正面轴或飞剑装配。

`jade_paper_sample.gd` 在角色入树前显式替换为
`cultivator_visual_neutral_youth_v7.tscn`，因此不受这次共享默认视觉回退影响。

## 备选方案

1. 保持 `cultivator_jade.glb` —— 宽袖袍仍遮挡肢体与移动姿态，否决。
2. 把所有场景立刻换成 v7 —— 使用者只要求“其他场景”回退，且 v7 是样板专用真人动作链，
   会扩大本轮范围，否决。
3. 覆盖或删除 `cultivator_jade.glb` —— 违反探索资产保留规则，否决。

## 后果

- 默认 `Swordsman`、正式动作工作台及其程序预览、移动庭院、群山宗门等共享场景恢复 Blender
  原创角色；
- 青玉纸样板继续使用 v7，不被这次回退覆盖；
- 旧青玉袍模型和所有历史资产继续留在仓库，后续仍可对照。
