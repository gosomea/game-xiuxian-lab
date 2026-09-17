# 修仙 · 模块实验室

独立的 **2.5D 模块实验项目**，基于 game-template 0.4.0 / Godot 4.6。

当前目标是把地图、角色、剑法、小镇交流、成长与人物交互等模块逐个做出来，在独立场景中运行、调整和比较。模块就绪后再考虑完整游戏的玩法组织。当前处于空工程初始化：**0 个玩法模块已建，8 个待探索。**

## 启动

macOS 可双击根目录 `run.command`。也可在 Godot 导入 `src/project.godot`，按 F6 运行任意实验场景，按 F5 进入实验目录。

```sh
./run.command
./run.command --editor
./run.command --stage
python3 tools/verify/run_all.py --with-tests
```

跨平台：设置 `GODOT` 指向 Godot 4.6 可执行文件，或将 `godot` / `godot4` 放入 PATH，然后执行 `./run.command`。若直接使用 CLI，首次运行先执行 `godot --headless --path src --import`，再 `godot --path src`。

## 目前可以看到什么

- **实验目录**：八个模块的目标、范围与依赖；条目均显示「待探索」，无虚假的可运行入口。
- **空白 3D 工作台**：一个参考地面网格、正交俯视相机、环境与灯光，确认工程的 3D 基础可运行。滚轮缩放、R 重置视角、Esc 返回目录。
- **工程基础**：模板核心设施、词汇与能力目录生成器、分包规范、检查工具及回归测试。

工作台不计为地图 Demo；没有角色、战斗或 NPC。相机与界面只是实验基础，不代表最终美术方向。

当前实验室使用「纸白 · 青绿」配色：浅纸色背景、深墨色文字、青绿交互色与少量暖金提示。菜单与工作台统一，文字和控件样式集中于 `src/ui/lab_theme.tres`。实际截图与验证结果见 [配色验收记录](docs/playtest/2026-09-17-paper-jade.md)。

## 模块清单

真相源为 `src/data/content/experiments.json`。界面从它读取，不在菜单代码另维护一份清单。

| 模块 | 独立实验目标 |
|---|---|
| 地图探索 | 地形、道路、建筑、遮挡、镜头与区域边界 |
| 角色移动 | 移动、转向、动画、碰撞与跟随 |
| 剑法战斗 | 角色施法、剑气、命中与受击反馈 |
| 小镇交流 | 地图进入小镇、接近 NPC、发起对话 |
| 人物成长 | 属性、境界、功法熟练度与变化展示 |
| 人物交互 | 交谈、赠送、交易、切磋及关系变化 |
| NPC 生活 | 作息、目标、行动与世界时间 |
| 背包物品 | 拾取、使用、装备、整理与物品状态 |

状态：`planned` 待探索；`exploring` 探索中；`ready` 当前范围可用。`ready` 必须对应有效独立场景，不表示最终平衡或完整玩法已完成。依赖只是共享模块关系，不是开发排期。

## 目录

```text
src/levels/lab_hub.tscn        实验目录
src/levels/empty_stage.tscn     空白 3D 工作台
src/levels/experiments/        后续独立与组合实验场景
src/game/                     供场景复用的模块实现
src/core/                     从模板继承的核心设施
src/data/content/experiments.json  模块清单
src/ui/                       实验室界面样式
src/tests/fixtures/            模板回归测试夹具，不装配进实验场景
docs/experiments/              实验结论与记录模板
docs/playtest/                 运行验收证据
```

新增模块和场景的方法见 [上手说明](docs/onboarding.md)。项目约定见 [AGENTS.md](AGENTS.md)，探索目标见 [design/pillars.md](design/pillars.md)。本工程独立于既有修仙项目，仅以 game-template 为实现基线；当前源码归 forever-skills 大仓管理。
