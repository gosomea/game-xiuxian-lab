# 角色视觉正面轴验收（2026-09-19）

## 现象

使用者在全部角色移动场景实机观察到：按 W 时角色位置向相机前方/北向移动，但人物背部
朝向行进方向。运动数据本身没有反：输入测试已证明 `W → move_input.y=-1 → camera_forward`，
场景也用同一方向写入 `aim_direction`。

## 根因与修正

现役人物导入 Godot 后以模型局部 `+Z` 为视觉正面；共享 `Swordsman._face_aim()` 和动作
预览却按局部 `-Z` 计算 yaw，形成恒定 180° 偏差。修正后：

```text
yaw = atan2(aim.x, aim.z)
visual_front = Basis(UP, yaw) × local(+Z)
visual_front · aim > 0.999
```

正式角色与动作预览复用同一换算。没有修改 W 输入、相机地面基、物理速度、碰撞或动作状态。

## 自动证据

- `docs/playtest/2026-09-19-character-facing-axis.png`：修正后的动作工作台真实运行第 89 帧；
  角色正面可见，启动日志无 error。
- `test_swordsman_movement.gd`：W 仍映射到相机前方；世界前/后/左/右四向均断言模型局部
  `+Z` 经 yaw 后与 aim 点积大于 `0.999`。
- `test_motion_preview.gd`：预览的 `heading`、快照 `forward` 与正式 actor 使用同一约定；
  `aim=-Z` 与 `aim=+X` 都直接验证可观察正面向量。
- `godot --headless --path src tests/test_runner.tscn`：1085 通过 / 0 失败。

## 人工复核动作

进入任一角色移动场景，依次按 W / S / A / D：人物胸口/面部应朝向实际位移方向，停止后
保留最后朝向。御剑与跳跃只改变动作和姿态，不应把 yaw 再翻转。最终审美与近景朝向仍以
使用者实机观察为准。
