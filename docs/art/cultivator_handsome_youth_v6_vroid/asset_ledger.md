# 英俊少年修士 v6（HairSample Male）资产台账

日期：2026-09-19

## 来源与许可

- 原作者：VRoid Project。
- 资产集合：VRoid Studio CC0 models。
- 来源页：https://opengameart.org/content/vroid-studio-cc0-models
- 许可：CC0；来源页明确显示 License(s): CC0，并说明旧版 VRoid 样本由 VRoid 明确以 CC0 发布。
- 下载文件：`hairsample_male.zip`；下载日期 2026-09-19。
- 格式：VRM 0.x，原始角色由 VRoid Studio 0.14.0 导出。
- 原始 zip：`source/hairsample_male_original.zip`；SHA-256 `ba87440272b157a443dbe2cddb375eb175bce3586a45a84779bb018a5e730129`。
- 原始 VRM：`source/HairSample_Male_original.vrm`；SHA-256 `4af2194f90ba846f3b13c00b50b14262419062d2171d17de922bcce2f89979c7`。
- 临时审计用 `.glb` 仅为同一 VRM 的扩展名副本，SHA-256 与原 VRM 相同；不作为不同来源资产登记。
- 页面摘录见 `source/SOURCE.md`。

## 原件审计

- 完整人物，不是单独发型：`Body`、`Face`、`Hair001` 三个蒙皮网格；17,669 顶点、24,858 三角面、14 个 glTF 材质、25 个纹理。
- Armature 共 91 骨，VRM Humanoid 映射 54 项；含 16 根 `HairJoint-*` 和 8 根 `J_Sec_*` 辅助骨。
- 原件无内嵌动画。
- 源人物在 Blender 中面向 `+Y`；正面相机位于人物 `+Y`，Godot 导出前向需由 manifest 单独记录。
- Blender glTF 导入会生成无材质、无蒙皮的辅助 `Icosphere`；它不是人物网格，构建时删除。

## 迭代记录

- `iteration_01`：在完整成熟原件上删除帽兜/抽绳现代元素、改色并添加交领、腰封、四片短摆与半束马尾。独立审美审查 69/100 FAIL；脸、原生碎发、少年比例与半束马尾可保留，宽松直筒上衣、硬厚腰带、矩形短摆、现代袖鞋和错误 idle 姿势不通过。该迭代的 `.blend` 与四向图保存在 `iterations/iteration_01/`，不覆盖。
- `iteration_02`：FAIL。尝试收窄原上衣连续网格、减薄腰封、拓宽交领、增加短外层/弧形短摆/束口/绑腿并修正静态 idle，但四向图暴露更严重的程序附件堆叠：青蓝外层成为直立硬盒式无袖 tabard，腋下出现大破口；束口像悬空粗圆环；绑腿像矩形筒；交领叠线混乱；腰封仍呈硬条。该迭代仅作为失败证据保留，不再继续程序附件第三轮。根目录主输出在构建时同步为本次失败版，不能作为通过候选使用。

原始 zip/VRM 永不覆盖。尚未运行真实 walk/run/jump；所有静态图和导出只用于代表链审美送审，manifest 必须保持 `real_animation_tested: false`。
