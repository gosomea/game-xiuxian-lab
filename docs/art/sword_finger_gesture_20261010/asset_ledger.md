# 剑指施法手部 · 2026-10-10

依据：[共享施法剑指决策](../../../notes/implemented/art/2026-10-10-sword-finger-gesture.md)。本轮资产完全由本仓构建脚本原创生成，没有新增外部模型、贴图或许可。

| 资产 | 用途 |
|---|---|
| `sword_finger_hand_20261010.blend` | 独立米制右手，腕骨与五指各三骨，带可编辑 `gesture` 时间线 |
| `src/game/shared/sword_cast/models/sword_finger_hand_20261010.glb` | 运行时手部网格、蒙皮、十六骨与结诀动画 |
| `build_hand.py` / `build_report.json` | 可复现构建与导出结构回读 |
| `relaxed.png` / `sword_fingers.png` | 原创手部的放松与结诀预览 |
| `reference.png` | 使用者提供的剑诀截图，仅作本地动作参考 |
| `initial/` | 法线修正前的手部源、导出与预览，保留作比较 |
| `baseline_hand.png` / `inspect_baseline.py` | 原人物固定手型的只读近景基线 |

原二十二骨身体、贴图和七段动作保留原路径。剑法装配后，局部重建 ArrayMesh 索引隐藏右手腕口外旧手，保留所有身体顶点属性与材质；卸载还原原共享 Mesh。新手部通过 BoneAttachment3D 借用右手腕，厘米制身体与米制手部在装配时显式转换。手部始终绑定手腕，施法权重从零到一连续采样 `gesture`，双指伸直并拢、无名指与小指收拢，收势恢复放松。

复现：在仓库根执行 `Blender --background --factory-startup --python-exit-code 1 --python docs/art/sword_finger_gesture_20261010/build_hand.py`，然后 `Godot --headless --path src --import`。脚本默认用于本资产同版本继续编辑；新方案必须另存脚本目录和输出名。Blender 源、导出与预览均保留并提交。新 `.blend`、`.glb` 使用 LFS。

实际运行验收见[剑指施法报告](../../playtest/2026-10-10-sword-finger-gesture/report.md)。

同资产打磨：重新计算闭合掌部与指部网格的朝外法线，拇指进一步收拢；不改变骨数、网格帧坐标或动画命名。旧版比较材料保留在 initial。

体积与接缝打磨：增加五枚薄指甲网格、调整双指间距与闭指关节角度；基于原人物贴图的暖肤色识别清除腕口旧手残片，保留较深袖口。手部 Shader 使用柔和的法线填光提升强环境光中的体积感；无图形 Dummy renderer 保留导出材质，骨架、蒙皮、结诀采样完全相同。

手腕方向修正：手部源、蒙皮和手指动画沿用；共享表现层固定掌宽侧轴，结诀正上，发令俯转约 105° 至前方偏下 15°，手腕基准取自手臂 IK 之前的基础动画。旧窗口证据保留，最终证据另存 `upright105/`。
