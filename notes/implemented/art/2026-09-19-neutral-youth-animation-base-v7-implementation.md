# Note: 无仙侠衣装的清俊少年动画底座 v7 实施

Status: implemented

## 问题

`notes/proposed/art/2026-09-19-neutral-youth-animation-base-v7.md` 提案已获使用者认可：
停止当前仙侠衣装制作，为「青玉纸白」样板换上一个干净、正面明确、可播放真人动作的
少年动画底座。本 note 记录该提案的落地方式、实测证据与被证伪的假设。

## 决策

新增独立代表链 `cultivator_neutral_youth_v7`，不覆盖 v2–v6 与现役 `cultivator_rigged.glb`。

### 人体

用未改原件 Generic Anime Male（CC-BY-4.0）作人体、少年脸与骨架底座。原件有 168 骨，
其中 103 根是作者的控制骨（`Ctrl_*`、`*_IK_*`、`*_FK_*`）并带 82 条约束。本轮删除
控制骨与控制器显示网格，只保留 65 根 `mixamorig` 变形骨与 4 个角色子网格；约束
一并删除，否则失效的 `COPY_TRANSFORMS` 会污染姿态。

### 中性遮挡层

只在原身体子网格上按**已有面分区**重绘：躯干、上肢、下肢、骨盆为深靛
（`#2E3A5C`）贴身层；头、颈、手、脚保留原表面材质。颈、腕、踝用 smoothstep
过渡带（颈线避开 `Neck` 骨所属关节）。**不新增任何几何**：顶点 5445、面 9762、
世界包围盒位移 0.0 m 逐位不变。躯干与骨盆露皮肤面数为 0。

不做交领 / 腰封 / 袍摆 / 护腕 / 绑腿；不做头发（保留底座头部，标记临时），
不使用硬板发片。

### 动作迁移：为什么不能用同名骨直接拷贝

提案风险一节预判了这一点，实测证伪了「同名即可复用」：两套骨架 65 根骨同名，
但 64 根共有骨中 **37 根 rest 局部朝向差 >5°，最大 179.3°**（`mixamorig:LeftHand`）。
因此改用 rest 帧共轭 + armature 空间标准形的重定向：

```
1) 源动作按变形骨链自根累乘   → posed_old[bone]（armature 空间姿态）
2) 目标骨反解 pose basis      →  B = L_new⁻¹ · (P_new⁻¹ · posed_old)
```

其中旧链必须走**源骨架自己的变形骨父级**：原件里 `mixamorig:RightArm` 的父骨是
`Ctrl_ForeArm_FK_Right`，旧四动作骨架里则是 `mixamorig:RightForeArm`。借用对方父级
会得到 0.068 m 的系统误差。

三个实现级陷阱（都通过逐帧回读暴露，见台账「踩坑」）：
`use_connect=True` 骨骼的 pose location 被 Blender 丢弃、四元数双覆盖符号、
`keyframe_insert` 遗留单点。

### 接线

样板 `jade_paper_sample.gd` 的视觉场景从 `cultivator_visual_rigged.tscn` 换成
`cultivator_visual_neutral_youth_v7.tscn`（仍经 `Visual/CultivatorSkeletonPresentation`
消费同名 clips，表现层脚本与四个动作映射常量一个字未改）。其余七个移动场景未动；
旧长袍视觉保留为回退与故障对照。

## 备选方案

1. 直接按骨名拷贝旧动作 —— 实测 37/64 骨 rest 朝向差 >5°，会产生扭曲姿态，已否决。
2. 按骨长比例缩放后拷贝 —— 只修缩放不修朝向，仍会残留肩腕髋偏移，已否决。
3. 重新录制/购买动作 —— 使用者明确不购买、不上传 Mixamo，且本轮只做底座，已排除。
4. 保留 v6 仙侠衣装 —— 已冻结，不接入运行时。

## 后果

- 新增运行时链：`models/cultivator_neutral_youth_v7.glb`（2.1 MB，skin 65 joints，
  clips=idle/walk/run/jump）与 `cultivator_visual_neutral_youth_v7.tscn`。
- builder 同时保存 Godot 从 GLB 映射出的中性遮挡层 PNG 源文件；这样即使删除导入缓存，
  首次扫描也不会只剩 `.import` 边车或产生纹理 UID 回退警告。
- `test_jade_paper_rigged_animation.gd` 断言改为装入 v7 模型、且显式断言不再加载旧
  `CultivatorRigged`。
- 门禁 `run_all.py --with-tests` 全绿（负向控制 27/27，运行时测试 1080/0）。
- **v7 是临时美术底座，不是最终角色。** 不含仙侠服装、无头发、遮挡层只服务动作与
  比例验证；审美结论归使用者，滑步与跳跃手感未做人工试玩。
- 中性遮挡层在颈、踝两条过渡带存在可见锯齿（逐面着色所致），属已知限制。
- 骨骼连接被全部断开（`use_connect=False`）以启用 pose location，rest 位置位移 0.0 m；
  这是本资产的动作正确性前提，后续若重建骨架需保持该语义。
