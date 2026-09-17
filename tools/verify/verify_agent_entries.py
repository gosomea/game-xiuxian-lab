#!/usr/bin/env python3
"""verify-agent-entries：Agent 入口一致性门禁（Tier 0）。

依据 notes/implemented/process/2026-08-28-agent-agnostic-dual-plane.md。

Agent 适配平面全部是指向真身的符号链接，无一份重复内容。本门禁保证它们不断：
1. 每个入口存在且确实是 symlink（不是内容为路径文本的普通文件——
   Windows 上未开启 core.symlinks 时 clone 会产生这种假文件，Agent 会读到垃圾）；
2. 指向的目标为约定的相对路径（绝对路径换机器即失效）；
3. 目标可解析到真身。

失败时给出跨平台修复指引，不静默降级。
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import REPO_ROOT, Failure, report  # noqa: E402

DOC = "notes/implemented/process/2026-08-28-agent-agnostic-dual-plane.md"

# 入口相对路径 -> (期望的 symlink 目标, 解析后应为目录)
ENTRIES: dict[str, tuple[str, bool]] = {
    "CLAUDE.md": ("AGENTS.md", False),
    "CODEBUDDY.md": ("AGENTS.md", False),
    ".agents/skills": ("../skills", True),
    ".claude/skills": ("../skills", True),
    ".codex/skills": ("../skills", True),
    ".codebuddy/skills": ("../skills", True),
    ".workbuddy/skills": ("../skills", True),
}

SYMLINK_HINT = (
    "创建符号链接：ln -sfn <目标> <入口>；"
    "Windows 需先 git config core.symlinks true 并开启开发者模式后重新 clone"
)


def check_entry(root: Path, entry: str, expected_target: str, expect_dir: bool) -> list[Failure]:
    failures: list[Failure] = []
    path = root / entry

    if not path.exists() and not path.is_symlink():
        failures.append(
            Failure(path, f"Agent 入口缺失（应为指向 {expected_target} 的符号链接）", fix=SYMLINK_HINT)
        )
        return failures

    if not path.is_symlink():
        failures.append(
            Failure(
                path,
                "存在但不是符号链接（Windows 未启用 symlink 时 clone 会产生内容为路径文本的假文件，Agent 会读到垃圾）",
                fix=f"删除该文件后重建：rm -rf {entry} && ln -sfn {expected_target} {entry}；" + SYMLINK_HINT,
            )
        )
        return failures

    actual_target = str(Path(path).readlink())
    if actual_target != expected_target:
        failures.append(
            Failure(
                path,
                f"符号链接目标为 {actual_target!r}，应为 {expected_target!r}"
                + ("（绝对路径换机器或换 clone 位置即失效）" if Path(actual_target).is_absolute() else ""),
                fix=f"ln -sfn {expected_target} {entry}",
            )
        )
        return failures

    if not path.exists():
        failures.append(
            Failure(path, f"符号链接悬空：目标 {expected_target} 不存在", fix=f"恢复 {expected_target}，或修正链接目标")
        )
        return failures

    if expect_dir and not path.is_dir():
        failures.append(Failure(path, f"目标 {expected_target} 应解析为目录", fix="检查 skills/ 是否被重命名或删除"))
    elif not expect_dir and not path.is_file():
        failures.append(Failure(path, f"目标 {expected_target} 应解析为文件", fix="检查 AGENTS.md 是否被重命名或删除"))

    return failures


def main(argv: list[str]) -> int:
    root = REPO_ROOT if len(argv) <= 1 else Path(argv[1])
    failures: list[Failure] = []
    for entry, (target, expect_dir) in ENTRIES.items():
        failures.extend(check_entry(root, entry, target, expect_dir))
    return report("verify-agent-entries", failures, len(ENTRIES), DOC)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
