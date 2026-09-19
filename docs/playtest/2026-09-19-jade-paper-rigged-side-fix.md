# 青玉纸白骨骼角色左右肢体修正验收

日期：2026-09-19

范围：`jade_paper_sample` 正式角色入口、Mixamo 蒙皮后处理、idle/walk/run/jump 状态映射。

结论：原始 Mixamo 模型与动作库正常；第三轮本地权重后处理曾把解剖学左右映射反，并裁掉手指骨权重。本轮已修正并重新导出资产。

## 根因与对照

- Mixamo 静止骨架中 `LeftArm/LeftHand` 位于角色局部 `+X`，`RightArm/RightHand` 位于 `-X`。
- 旧 `mixamo_driver_phase3.py` 使用 `X<0 => left`，因此左右袖、手和腿被交叉锁到对侧骨链。
- 旧保留集只精确匹配 `Hand`，会删除 `HandThumb/Index/Middle/Ring/Pinky` 子链；失去允许权重的点又按兜底规则挂到上臂，形成手腕不跟手骨、袖手姿态异常。
- 原始 `walk_skin.fbx` 在后处理前具备双侧 Arm/ForeArm/Hand 完整权重，因此不是模型造型或 Mixamo 动作文件本身损坏。

## 修正后的结构证据

Blender 阶段 3 现在按 `+X=Left/-X=Right` 分类，并保留同侧
`Shoulder -> Arm -> ForeArm -> Hand*` 全链。生成器在保存前强制检查权重质心；本轮结果：

| 权重组 | X 质心 | 权重总量 | 结果 |
|---|---:|---:|---|
| LeftArm | +0.241 | 1012.1 | 正确侧 |
| LeftHand | +0.491 | 692.3 | 正确侧 |
| LeftHandIndex1 | +0.563 | 43.7 | 手指链保留 |
| LeftUpLeg | +0.243 | 638.9 | 正确侧 |
| RightArm | -0.238 | 1510.2 | 正确侧 |
| RightHand | -0.485 | 636.9 | 正确侧 |
| RightHandIndex1 | -0.565 | 39.9 | 手指链保留 |
| RightUpLeg | -0.111 | 84.8 | 正确侧 |

任一组为空、落在身体对侧或偏离中线不足 0.02 m，生成脚本都会失败，不再输出运行资产。

## Godot 运行路径验收

- 对 `.glb` 执行 Godot 4.6 headless 重新导入，导入完成，无错误。
- 正式 `jade_paper_sample.tscn` 实例化后，`Swordsman/Visual` 是骨骼视觉，旧分件模型不存在，`FlyingSword` 仍由装配器正确挂入。
- `AnimationPlayer` 仅一份，包含 `idle/walk/run/jump`；走、跑、跳、御剑状态均经表现层公开 API 映射。
- 运行时回归：`test_jade_paper_rigged_animation.gd` 22/0；全套运行测试 981/0。
- 有头场景启动后保持运行且控制台 0 error；静止与运动姿态中的双臂已由各自同侧骨链驱动。

## 尚需使用者判断

结构错误已经排除，但动作是否符合期望的修仙气质（摆臂幅度、步幅、御剑姿态）仍是审美与手感判断，不能由自动门禁代替。若下一轮只是不喜欢姿态，应替换或调动作 clip；不应再改左右骨映射，也不应旋转整个角色来掩盖蒙皮问题。
