# 青玉短打修士 v1 资产台账

日期：2026-09-19

决策依据：[移动角色短装 note](../../../notes/proposed/art/2026-09-19-movement-cultivator-shortcoat.md)

## 一句话定位

用于验证走、跑、跳和御剑的**静态 T-pose 白样**。延续青玉纸白的交领、腰封、发髻与靛青/月白/暖金色卡，但主动移除长袍、大袖和披风；目前没有骨架、蒙皮或动作，未接入任何运行时场景。

## 来源与许可

- 几何、材质和构建脚本均由本项目在 Blender 中程序化原创生成，没有下载、复制或改造网上候选模型的网格、贴图、骨架或动画。
- Quaternius Universal Base Characters、Sketchfab、Fab 与 OpenGameArt 页面只用于本轮市场/授权/结构调研，没有任何第三方文件进入本目录。
- 生成器复用本仓 `tools/art/generate_cultivator_refined.py` 的程序几何帮助函数；旧模型文件没有被覆盖。
- 本目录中的模型资产沿用本项目许可；第三方候选的授权不附着于这些原创文件。

## 构建方式

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup \
  --python tools/art/generate_cultivator_shortcoat_v1.py -- build preview
```

构建环境：Blender 5.2.1 LTS。`build_manifest.json` 是本轮机器可读统计与哈希真相源。

## 文件

| 文件 | 用途 |
|---|---|
| `cultivator_shortcoat_v1.blend` | 可编辑源工程，26 个具名部件，保留材质与分片结构 |
| `cultivator_shortcoat_v1.glb` | 静态多部件预览交换文件；不进入现有 Godot 运行时 |
| `cultivator_shortcoat_v1_mixamo_tpose.fbx` | 下一轮自动绑骨输入：单 Mesh、8 材质、无 Armature、无动作 |
| `cultivator_shortcoat_v1_front.png` | 正面轮廓、marker 与腿间负空间证据 |
| `cultivator_shortcoat_v1_three_quarter.png` | 交领、短分片长度和侧面无遮挡证据 |
| `cultivator_shortcoat_v1_back.png` | 后背、发髻与后短分片证据 |
| `iterations/cultivator_shortcoat_v1_pre_split_palette.blend` | 第一光照检查后的迭代快照：浅色卡、单块正面短摆；因探索资产保留而另存 |
| `build_manifest.json` | 尺寸、面数、状态和产物 sha256 |

## 结构审计

最终白样：

- 4,204 triangles；
- 身体高度 1.700 m，总高（含发髻）1.767 m；
- 6.563 头身，T-pose 臂展 1.5249 m；
- 鞋底 z=0；
- 26 个源部件；
- 无骨架、无蒙皮、0 animations；
- Mixamo FBX 回读：1 Mesh、2,182 vertices、2,140 polygons、8 materials、0 Armature。

静态动作友好约束：

- 左右前摆、左右后摆、左右侧摆彼此分离，没有任何布片横跨双腿；
- 下摆止于大腿上段，膝、踝、脚尖无遮挡；
- 袖口止于手腕，手和拇指标记完整露出；
- T-pose 肘部和腋下轮廓明确，无披风或胸前硬挂片；
- 正面交领只贴胸，不向下延伸成围巾或长飘带。

## 当前边界

这不是可替换玩家角色的完成资产。它只证明“原始青玉画风 + 移动友好短装”的静态轮廓可行。下一轮应把 `cultivator_shortcoat_v1_mixamo_tpose.fbx` 送入自动绑骨，至少回收 idle/walk/run/jump，并实机检查腋下、胯部、膝部、袖口与六片短摆。动作验收前不得替换 `jade_paper_sample` 当前视觉。

