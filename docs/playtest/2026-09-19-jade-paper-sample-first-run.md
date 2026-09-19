# Playtest · 青玉纸白样板首轮实机渲染

- 日期：2026-09-19
- 场景：`res://levels/experiments/character_movement/jade_paper_sample.tscn`
- 方式：Godot 4.6 `--write-movie` 真实渲染管线截帧（gl_compatibility，1280×800，第 40 帧），非编辑器摆拍
- 证据：[2026-09-19-jade-paper-sample-first-run.png](2026-09-19-jade-paper-sample-first-run.png)

## 观察到

- 场景可启动、可玩：HUD 正常、角色着地（高度 0.0 m、状态步行）、碰撞与相机装配无报错（run 日志 0 error）。
- 铺装 1.9 m 方砖 + 深色砖缝 + 收边带读数清楚；台基压顶暖沙色；亭子青玉瓦/暖木柱/石基座；人物靛青袍；松冠深绿、岩青灰。
- 远景盘与高度雾在地平线处衔接，远景降对比成立。

## 已修复的实机问题（详见台账「关键约束」）

1. 远景盘顶面 (+0.3) 盖住地面与铺装 → 中心降至 -0.71。
2. glTF baseColorFactor 被导入器 linear→sRGB 转换导致洗白 → 色卡预补偿导出。
3. 铺装 from_pydata 蝴蝶结面 → bmesh create_cube 重建。
4. 高度雾参数（8 m/0.02）把小场景泡雾 → 调至 20 m/0.004。

## 未验证

- 步行 / 跳跃 / 御剑的交互手感与多机位动作视频（方向 note 验收 §2）未做——本轮只做静态首帧验证；交互验收由使用者实机试玩判断。
- 审美结论归使用者。
