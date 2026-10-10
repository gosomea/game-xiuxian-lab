# 修仙 · 模块实验室

独立的 **2.5D 模块实验项目**，基于 game-template 0.4.0 / Godot 4.6。

当前 **角色移动已完成本轮探索（ready）**，十一个子实验均当前可用；**2 个模块探索中**：二维坊市与剑法战斗；地图及其余 5 个模块待探索。移动模块以子实验目录 `movement_lab_hub.tscn` 为入口，十一个子实验（综合工作台、镜头、动作、地形接触、御剑飞行、状态切换、庭院、群山、青玉样板、水墨湖岸、西湖夕照）逐一观察；群山宗门是其中的综合场景。剑法战斗以剑法工作台为入口，比较三种出剑方式，不含血量与胜负。移动的完成范围与装配边界见[当前结论](docs/experiments/character-movement.md)。

## 启动

macOS 可双击根目录 `run.command`。也可在 Godot 导入 `src/project.godot`，按 F6 运行任意实验场景，按 F5 进入实验目录。

```sh
./run.command
./run.command --editor
./run.command --stage
python3 tools/verify/run_all.py --with-tests
```

跨平台：设置 `GODOT` 指向 Godot 4.6 可执行文件，或将 `godot` / `godot4` 放入 PATH，然后执行 `./run.command`。若直接使用 CLI，首次运行先执行 `godot --headless --path src --import`，再 `godot --path src`。

本仓使用 **Git LFS 保存大资产**。使用者已授权将精简后的已提交历史和完整 LFS 内容发布到 `origin/main`，接替此前仅本地模式。取得已发布版本时，安装 Git LFS，执行 `git lfs install --local` 与 `git lfs pull`，再导入 Godot。完整本地备份仍须包含工作树和 `.git`（尤其 `.git/lfs/objects`）。[同步与备份步骤](docs/onboarding.md#lfs-同步与备份)。

新 `.blend/.glb/.obj` 与任何大于 5 MB 的文件使用 LFS；历史大文件已迁入 LFS，未修改的小旧资产仍为普通 Git blob。资产暂存前运行 `python3 tools/assets/sync_lfs_attributes.py`；历史提交映射、恢复与后续发布步骤见[迁移记录](docs/migrations/2026-10-10-historical-lfs/report.md)和[旧人物历史精简](docs/migrations/2026-10-10-lfs-compaction/report.md)。人物动作新版本使用[轻量动作源与导出流程](docs/art/cultivator_motion_library_20261010/asset_ledger.md)。

## 目前可以看到什么

- **实验目录**：九个模块的目标、范围与依赖；角色移动、二维坊市与剑法战斗已有探索场景。
- **剑法工作台**：本命剑悬浮在右肩后；鼠标指向地面，左键出剑，C 或按钮在剑气（月牙剑光穿透木桩）、飞剑出击（本命剑弧线飞出再飞回）、剑阵（按住在身后蓄剑、松开万箭齐发）之间切换；五根木桩命中时闪白晃动，剑气与飞剑命中有短顿帧。飞剑在外时不能御剑，御剑时仍可放剑气与剑阵。移动与镜头沿用共享操作，R 重置、Esc 返回。[运行记录](docs/playtest/2026-10-09-sword-workbench/report.md)。
- **角色移动子实验目录**：**两级卡片各一次点击直达（共 2 击）**，十一项子实验逐项回答问题，**十一项全部有真实场景入口（11 / 11）**：移动综合工作台、镜头实验室、人物动作工作台、地形接触训练场、御剑飞行训练场、状态切换压力场、移动庭院、群山宗门、青玉纸白样板、水墨湖岸样板、西湖夕照 · 穿云。每个子场景的 Esc 回到本目录，本目录的 Esc 回到顶层实验目录；返回后恢复上次选中项与滚动位置。综合工作台使用参数侧栏，其余场景共享紧凑 LabHud（标题 + 核心状态 + 短提示常显，明细按 H / F1 展开）。
- **群山宗门**：180×160 m、五峰三落脚点的 Blender 程序建模场景。WASD / 方向键移动，Space 跳跃 / 上升，Ctrl 下降，F 开关御剑，滚轮缩放，R 复位（含关闭飞行），Esc 返回；HUD 常显步行 / 空中 / 御剑与高度，明细按 H 展开。相机走共享 CameraRig（高空跟随不压回地面）。没有攻击、命中或战斗 UI。
- **移动庭院（小场景回归）**：修士与风格化庭院的移动组合基线，可直接单独运行；**默认进入组合环绕 / 自由跟随**（`orbit`：WASD 移动、Q/E 连续旋转、滚轮缩放、按住右键拖动 yaw/pitch），点界面按钮可切回 `fixed_follow`，不占用数字键；R 重置、Esc 返回。
- **镜头实验室**：四模式（`fixed_follow` / `quarter_turn` / `orbit` / `overview`）与四种跟随预设对比；**默认进入组合环绕 / 自由跟随**（`orbit`，同时支持 WASD、Q/E 连续旋转、滚轮缩放、按住右键拖动）；1–4 选模式、Tab 换预设、Z/X 或滚轮缩放、MMB 平移、Home 回中。
- **移动综合工作台**：移动目录首项。侧栏编辑步行、疾跑、起跳、空中水平移动、御剑、镜头和其他注册组件参数，开关可卸下或恢复移动、跳跃、御剑与镜头行为。修改即时预览，点击「保存为全局默认」后，所有共享三维修士与镜头的实验（包括剑法工作台）及下次启动沿用；可撤销未保存或恢复原始默认。[运行记录](docs/playtest/2026-10-10-movement-workbench/report.md)。
- **人物动作工作台**：真实输入模式观察现役 22 骨人物的七段动作（站立、步行、疾跑、跳跃、待命、静修、御剑），另可逐段播放 / 暂停 / 单步 / 循环 / 调速与比较过渡。现役人物源与导出见[资产台账](docs/art/cultivator_motion_library_20261010/asset_ledger.md)。
- **水墨湖岸样板**：暖纸、白墙墨瓦、淡粉树、五层塔与湖面远山。保留现役角色，复用三项移动能力；可步行过桥、御剑绕塔、收剑降落小岛，落水自动复位。[实验说明](docs/experiments/ink-lakeside-sample.md)。
- **二维坊市**：独立的东方动漫风斜角街口，可四向行走并与三位路人交谈；它验证二维画风与遮挡，不复用三维人物模型。
- **空白 3D 工作台**：保留网格、正交相机与缩放，供其他模块独立起步。
- **工程基础**：模板核心、词汇与能力目录生成器、分包规范、门禁和回归测试。

目前群山、宗门与御剑是程序建模的美术探索；使用者已认可基本移动动作，最终画风、连续移动手感与其它模块仍待继续验证。实验室界面沿用「纸白 · 青绿」配色。

所有三维修士场景统一使用 WASD / 方向键移动、Shift 疾跑、Space 跳跃 / 御剑上升、Ctrl 下降、F 起飞 / 收剑；动作工作台预览模式独立。[统一操作验收](docs/playtest/2026-10-04-unified-traversal.md)。

## 模块清单

真相源为 `src/data/content/experiments.json`。界面从它读取，不在菜单代码另维护一份清单。

| 模块 | 独立实验目标 |
|---|---|
| 二维坊市 | 东方动漫风斜角街口、四向行走、人物与环境遮挡 |
| 地图探索 | 地形、道路、建筑、遮挡、镜头与区域边界 |
| 角色移动 | 平面移动、跳跃、御剑飞行、碰撞与跟随镜头 |
| 剑法战斗 | 剑气、飞剑出击、剑阵三种出剑方式与命中反馈比较 |
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
src/levels/experiments/        独立与组合实验场景（character_movement、eastern_2d）
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

早期移动实验边界见 [实验记录](docs/experiments/character-movement.md)；现役动作验收见[运行记录](docs/playtest/2026-10-09-upright-motion/report.md)。群山与御剑源文件、复现方式与资产台账在 `docs/art/mountain_realm/`；现役人物源与导出见[角色资产台账](docs/art/cultivator_motion_library_20261010/asset_ledger.md)，庭院资产在 `docs/art/movement_garden/`。

### 西湖夕照综合场景

移动目录最后一项为「西湖夕照 · 穿云」：压缩西湖、杭州街区、堤桥与三岛、夕阳天空和 32–48 米云层。完整复用移动、Shift 疾跑、跳跃、御剑与 CameraRig，支持四模式、正交/透视、直升穿云。详见 [游览操作](docs/experiments/west-lake-sunset.md)。
