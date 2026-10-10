# 本地旧人物 LFS 历史精简 · 2026-10-10

依据：[精简决策](../../../notes/implemented/process/2026-10-10-local-lfs-history-compaction.md)。使用者同意精简已从当前目录删除的旧人物历史；本次不上传或修改 GitHub。

精简实施后的远端发布另获使用者明确授权，依据[完整 LFS 上传与强推决策](../../../notes/implemented/process/2026-10-10-lfs-remote-publication.md)。本报告中的未上传状态与推送阻断描述精简阶段，不再作为当前发布限制。

## 范围与备份

- 原工作区分支：`codex/sword-spell-exploration`，原 HEAD：`f0f29a5e7043ef5f108c9fa2e9d1d4a783c1b050`；包含最新三项剑法探索成果。
- 只移除[清单](plan.json)的 255 个精确历史路径，对应 212 个不再被任何分支尖端使用的旧人物 LFS 对象，8,611,699,289 bytes（8.020 GiB）。
- 保留所有当前文件、源、导出与当前归档；两份环境备份 `jade_pine.blend1`、`jade_rock.blend1` 排除。无引用的小暂存对象也未顺带清理。
- 保留 `main`、五个剑法分支和 Codex 引用；不会将旧分支合回新历史。Codex 的直接树引用没有历史父链，树内容保持不变。
- 完整备份：`/Users/yuqixian/.codex/backups/game-xiuxian-lab/20261010-lfs-compaction-f0f29a5-d5c1ccc2/`。`before.git` 保存实施前完整 Git/LFS 与工作树元数据，`pre-rewrite.git` 包含实施前决策检查点，`candidate/` 为独立实施与验收副本。切换时另存最新原数据库。

同一磁盘上的完整备份继续占用空间，APFS 写时复制的共享块仍被备份引用；日常仓库逻辑体积的缩减不等于磁盘实际空闲量。

## 历史与内容审计

- 103 个提交、135201 个保留路径/模式/blob 条目逐项核对，作者、提交者、消息、父子图和提交数保持。
- 只移除清单路径；所有分支和 Codex 引用尖端树与实施前相同。
- [改写审计](rewrite-audit.json)、[提交映射](commit-map.json)记录全部改写提交。[实施程序](rewrite_history.py)在实际写入对象后独立核对树、消息与父子关系，核对通过才事务更新引用。
- 回收前，对全部剩余历史 LFS 内容验证 SHA-256 与大小：40 个对象，1149407340 bytes。任何仍有引用的对象均不回收。[对象审计](lfs-audit.json)、[限定回收程序](collect_lfs_objects.py)。
- 本地 LFS 缓存由 9761470959 bytes（9.091 GiB）降为 1149771670 bytes（1.071 GiB）。最新剑法分支新增的对象已经计入，故实施前比之前 9.079 GiB 的盘点略大。

重新打包后普通 Git pack+索引为 769.22 MiB，`git fsck --full` 退出 0；见[空间统计](storage.json)、[打包后检查](git-fsck-after-gc.txt)。

普通 blob 豁免的基线 SHA 已按新映射更新，文件/blob 例外保持；LFS 属性同步继续由原生成器执行。

## 验收与恢复

Tier 0 与 33/33 负向控制通过，运行时测试 2808 通过 / 0 失败；见[检查输出](checks.txt)。`git lfs fsck --objects --pointers HEAD` 退出 0，见[LFS 检查](lfs-fsck.txt)。游戏源码和资产未改动。

主工作区已完成接管：在所有工作树干净且分支未产生新提交的条件下，只同步本次 19 个策略、工具元数据、文档与证据文件，再采用验收后的 Git 数据库。工作树原始资产没有重写。五个工作树在切换时均干净；接管后 LFS 资产门禁、LFS 检查与 Git 完整性检查退出 0。最新旧数据库保留在 `live-before-adoption.git`，见[接管复核](adoption.json)。

现有独立工作树继续跟随各自已映射的分支，索引与当前文件保持。后续本地开发继续正常提交；推送阻断配置保留。已剔除的旧人物文件须从 `before.git` 或 `pre-rewrite.git` 的旧历史恢复，日常仓库不再承诺这些版本存在。常规开发不能直接删除 LFS 对象或运行 `git lfs prune`。

若要重做本次操作，先从 `pre-rewrite.git` 恢复独立副本，再运行实施程序；不要在当前已精简数据库重复执行来覆盖原映射和证据。原完整历史迁移的映射可与本次映射组合，原完整性审计仅描述精简前的迁移状态。
