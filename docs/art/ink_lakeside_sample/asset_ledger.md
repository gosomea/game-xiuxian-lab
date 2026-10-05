# 水墨湖岸样板资产台账

日期：2026-10-05。依据：[水墨湖岸决策](../../../notes/implemented/art/2026-10-05-ink-lakeside-sample.md)。

## 源与导出

- 原创程序几何源：[生成器](../../../tools/art/build_ink_lakeside_sample.py)，Python 标准库，无外部素材或模型服务依赖。随机种子 105。
- 导出：[环境 GLB](../../../src/levels/experiments/character_movement/ink_lakeside_sample_world.glb)，[布局与色板](../../../src/levels/experiments/character_movement/ink_lakeside_sample_layout.json)，[构建记录](build_manifest.json)。
- 场景：[水墨湖岸](../../../src/levels/experiments/character_movement/ink_lakeside_sample.tscn)。几何包括岸、塔、踏步、村落、花树、灰绿树、石桥、小岛与三层远山；湖面由场景 PlaneMesh 提供。
- 纸纹与湖面为该场景专属 shader，保存在场景目录并以场景名前缀命名。人物与动作仍引用现役共享资产，复制的 StandardMaterial3D 材质 override 仅作用于本场景实例。首轮 `ink_lakeside_sample_character.gdshader` 候选未用于最终场景，随首轮截图一起保留。日轮为同目录原创 SVG 源资产。

## 再生成

```sh
python3 tools/art/build_ink_lakeside_sample.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path src --import
```

在相同方案上修改源生成器允许更新本版本导出；另做视觉方案必须另存版本。源、导出、布局、Godot 导入边车和运行截图一起提交。

## 边界

- 塔和房屋是可绕行的封闭体，没有室内；三层远山没有碰撞，不可探索。
- 岸与小岛使用导出网格生成碰撞；建筑、树干、石桥与平台使用粗略碰撞代理。水面无碰撞，落水后返回出生点。
- 人物没有新建模型或动作，未增加手指骨。水墨方向尚待使用者认可。
