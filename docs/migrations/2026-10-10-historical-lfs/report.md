# 历史大文件 LFS 迁移 · 2026-10-10

依据：[迁移决策](../../../notes/implemented/process/2026-10-10-historical-lfs-migration.md)。使用者授权本地历史迁移；远端上传与强推尚未执行。主工作区已采用验收通过的新 Git 元数据，源资产保持真实文件。

## 迁移与完整性

- 原主分支：`dbbcfb5961254b289cf3b235fadb3bd632956dd5`。
- 实施前决策检查点：`c3d73280832650c24910be4eca52fc261c318f03`；迁移后为 `2c77f5d813c9c14e32bae0f7442cf27902b8d598`。
- 阈值：严格大于 5,000,000 bytes，不限后缀。247 个唯一普通 blob（9,747,682,956 bytes，9.078 GiB）变为 LFS 内容对象，已有 3 个 LFS 对象保留。
- PASS：86 个历史提交、111,470 个路径/模式/内容条目均核对，提交信息与父子图保持，250 个 LFS 对象已计算 SHA-256；每个迁移对象的原始 Git blob 身份也相等。[审计 JSON](audit.json)
- PASS：审计工具的正向例与四个非法例（损坏对象、缺文件、改模式、改提交消息），共 5 项。[测试输出](audit-fixtures.txt)
- PASS：Tier 0 与 33/33 负向控制；运行时测试 2172 通过 / 0 失败。[检查输出](checks.txt)
- PASS：Git 完整性检查与 LFS 检查退出 0。[LFS 输出](lfs-fsck.txt)
- 旧资产豁免从 85 减为 41 个小文件；44 个现存大文件取消豁免，加上原有 3 个轻量源/导出，现役树共 47 个 LFS 文件。

[提交映射](commit-map.csv)保留旧 SHA → 新 SHA。它仅包含历史迁移对应关系，后续验收与文档提交不在映射中。原始源、导出、归档、历史已删除的旧候选均按各提交原有路径保留，没有恢复已清理的旧候选到现役树。

## 本地备份

备份目录：`/Users/yuqixian/.codex/backups/game-xiuxian-lab/20261010-lfs-migration-dbbcfb5-33174bf8/`。

- `original.git`：迁移前 `dbbcfb5` 的完整 Git 元数据，包括引用、reflog、不可达对象与已有 LFS 内容。
- `before-migration.git`：加入迁移决策检查点后的完整旧 Git 元数据，是逐提交审计输入。
- `migration/`：独立迁移与验收工作副本。
- `live-before-adoption.git`：主工作区切换前的完整 Git 元数据，包含初次备份后产生的本地元数据。

备份采用 APFS 写时复制，旧 pack/LFS 对象仍可独立恢复。它不作为日常仓库引用存在，以免继续保留旧 pack。

## 复现与审计

在独立副本、干净工作树上运行；不要在并行开发时直接重写主工作区。

```sh
git lfs migrate import --include-ref=refs/heads/main --above=5000000b --object-map=/absolute/backup/commit-map.csv
git lfs checkout
python3 tools/assets/audit_lfs_migration.py --original-git=/absolute/backup/before-migration.git --object-map=docs/migrations/2026-10-10-historical-lfs/commit-map.csv --report=/absolute/output/audit.json
python3 tools/assets/test_lfs_migration_audit.py
python3 tools/assets/sync_lfs_attributes.py
git add .gitattributes tools/assets/lfs_legacy_blobs.json
python3 tools/verify/run_all.py --with-tests
```

独立副本清理旧引用/reflog 后重新打包：原 pack+索引 4,169,773,597 bytes（3.883 GiB），新 pack+索引 718,522,862 bytes（685.24 MiB），减少 82.77%。LFS 缓存共 251 个（250 个历史引用对象，加 1 个 364,330 bytes 的遗留暂存对象）、9,748,713,045 bytes（9.079 GiB）。迁移后历史内普通 blob 大于阈值的数量为 0。[空间统计](storage.json)

迁移副本移除了旧本地引用与 reflog，记录见[引用清单](removed-local-refs.json)；原数据库完整保留在独立备份，没有作为当前仓库的分支留存。实际本地接管时还保留 `live-before-adoption.git`，包含切换前主工作区的最新元数据。

真实资产恢复后运行 Godot 导入，再跑原始运行时测试：2172/0，日志无 SCRIPT ERROR/ERROR/FAIL；见[导入输出](import.txt)、[运行输出](runtime.txt)。重新打包后的 `git fsck --full` 退出码为 0，见[完整性输出](git-fsck.txt)。

主工作区在原 `dbbcfb5` 上确认干净后完成接管：只同步本次 25 个策略、工具与文档文件，再切换 Git 元数据；现存模型、贴图、源文件均未改写。接管后工作树干净，LFS 资产门禁、LFS 对象/指针检查与 Git 完整性检查均退出 0。活动引用只有迁移后的 `main`，pack 为 685.24 MiB；见[接管复核](post-adoption.txt)。

## 发布边界

已核实远端 `origin/main` 仍为 `81726d3b449efae116327a7289e96faa61bd012a`。账号剩余配额不能确认：账单 API 返回 404 并提示缺少 `user` scope，浏览器未登录。未扩展权限、修改预算、购买配额或上传对象。按当前历史需要存储约 9.08 GiB 的 LFS 内容。

使用者随后决定只保留本地 LFS 并继续开发，当前不发布迁移后的历史。已设置本地 `remote.origin.pushurl=disabled://local-only-lfs`、`protocol.disabled.allow=never`；`git push --dry-run origin HEAD:refs/heads/main` 退出 128，报 `fatal: transport 'disabled' not allowed`，在连接远端之前被阻断。LFS 本地过滤器继续正常工作，GitHub 未修改。配置解除与完整备份/恢复见[上手说明](../../onboarding.md#仅本地开发与备份)。

本地模式复核：notes 与 Agent 入口门禁、LFS 资产门禁、`git lfs fsck --objects --pointers refs/heads/main`、`git fsck --full` 均退出 0；364,315 bytes 的现役动作 Blender 源经本地 clean 生成与已提交指针相同的内容，再经 smudge 还原，SHA-256 与原文件一致。没有改动游戏或资产内容。

若后续决定远端发布，应先检查余量/预算、确认上传与强推，再执行 LFS 上传和指定旧 SHA 的 `--force-with-lease`。远端更新前不要 fetch/pull，否则会重新下载旧历史；远端更新后不要把旧历史分支合并回来。远端更新后，新使用者安装 LFS、重新克隆并 `git lfs pull` 后运行 Godot；已有未提交工作先另行保存，再切换新克隆。
