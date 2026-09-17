# 实验工程上手

先读根目录 README 与 design/pillars.md。默认打开实验目录；空白工作台可用于观察固定俯视空间，不计为完成模块。

## 新增一个实验场景

1. 明确这轮要看到的局部行为，以及判断结果的方式。不用先设计完整游戏。
2. 在 `src/levels/experiments/<module>/` 新建场景，例如 `map_exploration.tscn`。根控制脚本与场景同名。可在 Godot 编辑器打开 `empty_stage.tscn` 后另存为新场景作为起点，另存后将根脚本改为同名或移除，再加入实验逻辑；不要修改共享工作台冒充模块。
3. 把真正复用的行为放进 `src/game/<domain>/<package>/`；某实验专属编排与它的场景放在一起。3D 物理移动使用 `_physics_process`；模板的通用 CapabilityManager 当前是 `_process` 驱动，接入物理行为时应单独确定调度设计。
4. 修改 `src/data/content/experiments.json` 对应条目的 `scene` 为 `res://levels/experiments/.../*.tscn`，状态改为 `exploring`。菜单会自动提供运行按钮。
5. 模块需要返回入口时，使用 `res://levels/lab_hub.tscn`；每个场景也必须能在编辑器 F6 独立运行。
6. 完成这一轮探索后，在 `docs/experiments/` 记录结论，按当前范围决定继续 `exploring` 或标记 `ready`。
7. 改能力或词汇时重跑对应生成器；稳定实现完成后运行 `python3 tools/verify/run_all.py --with-tests`，再观察实际画面和交互。

## 清单字段

- `id`：稳定 snake_case 标识。
- `title` / `category` / `summary`：界面展示。
- `question` / `scope`：本轮想观察的内容，不是最终玩法承诺。
- `depends_on`：引用已有模块 ID，不能构成循环。
- `status`：`planned`、`exploring`、`ready`。
- `scene`：独立 `.tscn` 的 `res://levels/` 路径。`planned` 必须为空；`exploring` 可以暂时为空；`ready` 必须是可加载 PackedScene。

依赖不要求先标记 ready 才能探索：例如剑法可以先使用占位角色验证。依赖只表达共享方向。

## 初始工作台

X/Z 是地面，Y 是高度。正交相机与场景环境可在编辑器中直接调整；运行时滚轮缩放，R 恢复初始视角，Esc 或返回按钮回到实验目录。工作台没有玩家实体或地图玩法。

## 版本与素材

原始素材、派生资源、脚本、场景及 Godot `.import` 描述都应入版本管理；`.godot/`、系统文件和运行日志可重建。保留 Agent 入口的相对符号链接。当前工程归父仓库管理，不设独立远端。
