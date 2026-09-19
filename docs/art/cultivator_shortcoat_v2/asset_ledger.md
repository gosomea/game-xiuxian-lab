# 青玉短打修士 v2 资产台账

日期：2026-09-19

决策依据：[青玉短打修士 v2 note](../../../notes/proposed/art/2026-09-19-movement-cultivator-shortcoat-v2.md)

## 定位

面向 2.5D 修仙移动 demo 的原创静态角色候选。它不是 v1 的覆盖修改，而是按“青玉纸白”方向重新建立的人体、短外衫、交领、腰封、分片下摆、软靴、面部和束发结构。当前只用于视觉确认及下一轮 Mixamo 自动绑骨；没有接入 Godot 运行时。

## 来源与许可

- 全部几何、材质、预览与生成脚本由本项目原创生成；没有下载或改造第三方网格、贴图、骨架或动画。
- 本轮只参考了仓库既有美术方向与内部审查尺寸，不附带第三方许可。
- 输出沿用本项目许可。

## 构建

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup \
  --python tools/art/generate_cultivator_shortcoat_v2.py -- build preview audit
```

生成器会依次：建立可编辑分件源模型；导出面向 Godot -Z 的静态 GLB 分支；导出保持 Blender -Y 正面的单网格 Mixamo FBX；重置为空场景并重新导入 FBX；用独立语义材质定位鼻、眼、头、髻、鞋尖与鞋跟；断言正面、身高、落地、中心、矩阵、Mesh/Armature/Action 数量；最后直接从回读 FBX 渲染 `upload_front_check`。

## 文件

| 文件 | 用途 |
|---|---|
| `cultivator_shortcoat_v2.blend` | 38 个具名部件的可编辑主源，角色正面为 Blender -Y |
| `cultivator_shortcoat_v2.glb` | 静态 Godot 方向分支：复制后绕 Z 旋转 180°，Blender +Y 映射 Godot -Z |
| `cultivator_shortcoat_v2_mixamo_tpose.fbx` | 单 Mesh、无骨架、无动作的 Mixamo 上传输入，保持 Blender -Y 正面 |
| `cultivator_shortcoat_v2_front/side/back/three_quarter.png` | 正交、无透视的比例和造型审查图 |
| `cultivator_shortcoat_v2_FRONT_axis_proof.png` | 带 `FRONT / FACE = -Y` 标识的正面证据 |
| `cultivator_shortcoat_v2_upload_front_check.png` | 直接从空场景回读 FBX 渲染，必须同时看到脸、交领、腰扣、鞋尖 |
| `cultivator_shortcoat_v2_2p5d_size18.png` | 1280×720、正交 size 18 的约 70 px 远距读形检查 |
| `cultivator_shortcoat_v2_2p5d_size6.png` | 1280×720、正交 size 6 的中距读形检查 |
| `cultivator_shortcoat_v2_grey_front/side/back/three_quarter.png` | 中性单材质四向审查，排除色卡对布裁片与体块判断的干扰 |
| `iterations/` | 被淘汰但保留的逐轮 `.blend` 与 front 预览 |
| `build_manifest.json` | 尺寸、面数、hash、预览和 FBX 回读轴证据真相源 |

## 造型与运动边界

- 6.72 头身，约 1.686 m 至头顶；肩宽、腰宽、髋宽和臂展按动画角色比例约束；
- 贴体窄袖到腕，手、肘、腋下、髋、膝、踝、脚尖保持可见；
- 只有前左/前右/后左/后右四块主短摆，没有侧挂条、披风、大袖或整圈长裙；
- 短摆为上窄下宽、微弧、斜底边的布片，正中腿缝保持约 40 mm；
- 月白集中在颈胸交领和窄袖口，暖金只用于小腰扣和髻根束带；
- 角色正面在主 `.blend` 与 Mixamo FBX 中是 Blender -Y；GLB 是独立旋转后的 Godot 分支，两个导出不可混用。

## 边界

静态造型和上传方向检查通过不代表动作变形通过。下一轮必须上传 `cultivator_shortcoat_v2_mixamo_tpose.fbx`，取回 idle/walk/run/jump，并检查肩腋、肘腕、髋膝、鞋尖和四块短摆权重。动作验证前不得替换 `jade_paper_sample`。

截至 iteration 04 后的最终程序返修，技术结构仍合格，但静态美术自评为 79/100。若独立复审仍低于 80，本资产只保留为程序化管线样本；下一候选应改用成熟 CC0 动画友好人体底模，并在 Blender 中人工重拓扑服装和头脸，而不是继续修改本生成器。
