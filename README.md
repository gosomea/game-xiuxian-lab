# 修仙 · 模块实验室

独立的 **2.5D 模块实验项目**，基于 game-template 0.4.0 / Godot 4.6。

当前先探索角色移动与呈现：**1 个移动模块探索中，剑法及其余 6 个模块待探索。** 移动模块现以子实验目录 `movement_lab_hub.tscn` 为入口，七个子实验（镜头、动作、地形接触、御剑飞行、状态切换、庭院、群山）逐一观察；群山宗门是其中的综合场景，用来观察平面移动、独立跳跃与御剑飞行在高低差和空中场景中的表现。剑法表现与战斗组织另行设计，不从移动场景推导战斗规则。

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

- **实验目录**：八个模块的目标、范围与依赖；只有角色移动提供探索场景入口，剑法保持待设计。
- **角色移动子实验目录**：**两级卡片各一次点击直达（共 2 击）**，七项子实验逐项回答问题，**七项全部有真实场景入口（7 / 7）**：镜头实验室、人物动作工作台、地形接触训练场、御剑飞行训练场、状态切换压力场、移动庭院、群山宗门。每个子场景的 Esc 回到本目录，本目录的 Esc 回到顶层实验目录；返回后恢复上次选中项与滚动位置。各场景共享紧凑 LabHud（标题 + 核心状态 + 短提示常显，明细按 H / F1 展开）。
- **群山宗门**：180×160 m、五峰三落脚点的 Blender 程序建模场景。WASD / 方向键移动，Space 跳跃 / 上升，Ctrl 下降，F 开关御剑，滚轮缩放，R 复位（含关闭飞行），Esc 返回；HUD 常显步行 / 空中 / 御剑与高度，明细按 H 展开。相机走共享 CameraRig（高空跟随不压回地面）。没有攻击、命中或战斗 UI。
- **移动庭院（小场景回归）**：修士与风格化庭院的纯水平移动基线，可直接单独运行；WASD 移动、滚轮缩放、R 重置、Esc 返回，另可点界面按钮在 `fixed_follow` 与 `orbit` 两个镜头模式间切换（RMB 拖动环绕），不占用数字键。
- **镜头实验室**：四模式（`fixed_follow` / `quarter_turn` / `orbit` / `overview`）与四种跟随预设对比；1–4 选模式、Tab 换预设、Z/X 或滚轮缩放、RMB 环绕、MMB 平移、Home 回中。
- **人物动作工作台**：真实输入模式观察角色动作，另可选程序动作预览（播放 / 暂停 / 单步 / 循环 / 倍率 / A–B 过渡）；动作仍是程序近似，**尚无骨骼动画**。
- **空白 3D 工作台**：保留网格、正交相机与缩放，供其他模块独立起步。
- **工程基础**：模板核心、词汇与能力目录生成器、分包规范、门禁和回归测试。

目前群山、宗门与御剑是程序建模的美术探索；移动手感与视觉评价待使用者试玩。实验室界面沿用「纸白 · 青绿」配色。

## 模块清单

真相源为 `src/data/content/experiments.json`。界面从它读取，不在菜单代码另维护一份清单。

| 模块 | 独立实验目标 |
|---|---|
| 地图探索 | 地形、道路、建筑、遮挡、镜头与区域边界 |
| 角色移动 | 平面移动、跳跃、御剑飞行、碰撞与跟随镜头 |
| 剑法战斗 | 剑法表现与战斗组织方式，待单独设计 |
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
src/levels/experiments/        独立与组合实验场景（character_movement：movement_lab_hub + mountain_realm + movement_garden）
src/game/                     供场景复用的模块实现
src/core/                     从模板继承的核心设施
src/data/content/experiments.json  模块清单
src/ui/                       实验室界面样式
src/tests/fixtures/            模板回归测试夹具，不装配进实验场景
docs/experiments/              实验结论与记录模板
docs/playtest/                 运行验收证据
```

新增模块和场景的方法见 [上手说明](docs/onboarding.md)。项目约定见 [AGENTS.md](AGENTS.md)，探索目标见 [design/pillars.md](design/pillars.md)。本工程独立于既有修仙项目，仅以 game-template 为实现基线，并使用本目录下的独立 Git 仓库管理。每轮有文件变更的开发结束前完成适用检查并创建本地 commit，代码、场景、Blender 源文件及导出资产一起保存；具体规则见 [开发 Git 保存](notes/implemented/process/2026-09-18-development-git-checkpoints.md)。

## 角色移动实验

从目录选择「角色移动」进入子实验目录，再由目录内条目进入具体子场景，或直接启动：

```sh
./run.command res://levels/experiments/character_movement/movement_lab_hub.tscn
./run.command res://levels/experiments/character_movement/mountain_realm.tscn
```

小场景回归（纯水平移动的旧庭院）：

```sh
./run.command res://levels/experiments/character_movement/movement_garden.tscn
```

本轮边界与试玩反馈见 [实验记录](docs/experiments/character-movement.md)；接口与装配记录见 [群山场景方案](docs/experiments/mountain-scene-plan.md)。群山与御剑源文件、复现方式与资产台账在 `docs/art/mountain_realm/`，修士角色与庭院资产在 `docs/art/movement_garden/`。
