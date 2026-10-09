# 历史大文件 LFS 迁移 · 2026-10-10

依据：[迁移决策](../../../notes/implemented/process/2026-10-10-historical-lfs-migration.md)。使用者授权本地历史迁移；远端上传与强推尚未执行。

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

独立副本清理旧引用/reflog、重新打包后的空间统计将在最终本地接管前记录。原数据库始终保留。

## 发布边界

已核实远端 `origin/main` 仍为 `81726d3b449efae116327a7289e96faa61bd012a`。账号剩余配额不能确认：账单 API 返回 404 并提示缺少 `user` scope，浏览器未登录。未扩展权限、修改预算、购买配额或上传对象。按当前历史需要存储约 9.08 GiB 的 LFS 内容。

远端发布应先检查余量/预算、确认上传与强推，再执行 LFS 上传和指定旧 SHA 的 `--force-with-lease`。不要直接普通 pull 或把旧历史分支合并回来。远端更新后，新使用者安装 LFS、重新克隆并 `git lfs pull` 后运行 Godot；已有未提交工作先另行保存，再切换新克隆。
