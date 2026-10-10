# Note: 发布精简后的 Git 与 LFS 历史

Status: implemented

## 问题

历史大文件迁入 LFS 并精简旧人物版本后，GitHub 主分支仍停留在迁移前的 `81726d3b449efae116327a7289e96faa61bd012a`。此前的仅本地模式阻断推送，远端不能恢复当前已提交的工程。

## 决策

使用者于 2026-10-10 明确要求“commit and push 把 直接 -f”，授权本次完整 LFS 上传与强推。此决定接替[历史迁移](2026-10-10-historical-lfs-migration.md)的仅本地发布限制和[历史精简](2026-10-10-local-lfs-history-compaction.md)的暂不发布选择；资产保留范围与完整备份要求继续有效。

1. 本次发布已验收、已提交的 `codex/sword-spell-exploration` 内容到 `origin/main`。其他会话仍在编辑且尚未完成验收的剑指动作留在工作区，不作为本次提交内容。
2. 只解除本仓 `.git/config` 的 `remote.origin.pushurl=disabled://local-only-lfs` 与 `protocol.disabled.allow=never`，保留 LFS 过滤器和 pre-push hook，不改全局配置或账号预算。
3. 固定发布提交，核对剩余历史指针及本地内容，先用 `git lfs push --all origin <发布提交>` 上传该提交可达的完整资产，再执行 `git push -f origin <发布提交>:refs/heads/main`。依据使用者明确要求，本次使用 `-f`；不跳过 hook，不发布缺失 LFS 内容的指针。
4. 推送后独立读取远端 `main`，确认与发布提交完全一致。本地 `main` 可快进到同一提交，保留当前工作分支和其他工作树。
5. 后续推送和历史改写仍需使用者授权；旧历史不能合回新历史。其他克隆应重新克隆，或先保存本地工作再按映射迁移。常规开发仍不删除 LFS 对象、不执行 `git lfs prune`。

## 备选方案

- 继续只在本地保存：使用者已明确要求发布，故接替此前选择。
- 只推 Git 指针、不上传 LFS：远端克隆缺少项目资产，不能交付工程。
- 本次使用 `--force-with-lease`：此前方案采用此方式；本次按使用者明确的 `-f` 指令执行，并在推送前后读取远端提交。
- 发布全部探索分支：当前整合分支已经包含已接受的剑法成果，其他独立分支保留在本地，本次只更新远端主分支。

## 后果

发布使用精简后约 1.07 GiB 的完整历史 LFS 内容，而非精简前约 9.09 GiB 的旧人物版本。远端主分支采用新的提交历史；独立备份仍是清单内旧人物版本的恢复来源。新克隆须安装 Git LFS、取得真实资产，再导入 Godot；备份仍应包含完整 `.git` 和工作树。
