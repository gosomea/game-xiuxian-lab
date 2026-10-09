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

原始素材、派生资源、脚本、场景及 Godot `.import` 描述都应入本项目独立 Git 仓库；`.godot/`、系统文件和运行日志可重建。保留 Agent 入口的相对符号链接。Blender 的新 `.blend1` 自动备份不提交，已有跟踪备份保留。

新 GLB/Blender/OBJ 与任何大于 5 MB 的文件使用 LFS；历史大文件已迁入 LFS，未修改的小旧文件保留普通 blob。资产暂存前运行 `python3 tools/assets/sync_lfs_attributes.py`，随后将 `.gitattributes` 与资产一起 `git add`。检查入口包含 LFS 属性与指针门禁；历史迁移已保留原内容并改写提交号；已有克隆的切换与恢复见[迁移记录](migrations/2026-10-10-historical-lfs/report.md)，不要把旧分支合回新历史。

纯动作版本使用[轻量源与独立动作库](art/cultivator_motion_library_20261010/asset_ledger.md)，共享网格、贴图和 rest。改网格或骨架才建立新的共享模型版本。

## 仅本地开发与备份

使用者于 2026-10-10 选择 LFS 内容只保留本地。继续正常 `git add`、本地提交、切换已有版本和运行 Godot；本地操作不使用 GitHub LFS 配额。保留 LFS 过滤器与门禁。暂不执行 `git push`、`git lfs push` 或对旧远端 fetch/pull；远端没有迁移后的内容，也不保存后续本地进度。

本机当前仓库采用以下可撤销配置，普通 `git push origin` 会在连接远端前被拒绝：

```sh
git config --local remote.origin.pushurl disabled://local-only-lfs
git config --local protocol.disabled.allow never
```

这是 `.git/config` 中的本地配置，普通 clone 不会继承；复制完整仓库会携带它。显式 URL 或直接 `git lfs push` 可以绕开普通 Git 推送配置，此模式下不要执行。若以后明确决定发布且确认配额，先解除配置，再按迁移报告上传完整对象并更新远端：

```sh
git config --local --unset-all remote.origin.pushurl
git config --local --unset-all protocol.disabled.allow
```

开发暂停、提交保存后，复制整个仓库目录到备份位置，确保包含隐藏的 `.git` 与全部 `.git/lfs/objects`。仅 `git bundle` 或复制当前工作树不能备份历史资产；本地 LFS 对象不能删除，也不运行 `git lfs prune`。现有迁移备份保留，但后续提交与新增对象须继续更新备份。同一磁盘的备份不能应对磁盘损坏，建议另存到独立磁盘。

恢复时使用完整仓库副本，安装 Git LFS（macOS：`brew install git-lfs`），执行 `git lfs install --local`、`git lfs checkout` 与 `git lfs fsck --objects --pointers refs/heads/main`，再导入 Godot；本地对象完整时无需 `git lfs pull`。仅从 GitHub clone 目前只能取得旧版本，不能恢复这份本地工程。
