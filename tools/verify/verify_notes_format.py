#!/usr/bin/env python3
"""verify-notes-format：决策记录格式门禁（Tier 0）。

依据 notes/README.md：
1. 头部前三行精确为 `# Note: <标题>` / 空行 / `Status: <status>`；
2. Status 值合法且与所在 lifecycle 目录一致；
3. class 目录属于封闭集合；
4. 骨架章节按 lifecycle 齐备；
5. implemented 禁止提案期标题；
6. `## 备选方案` 非空（不记录被击败方案的决策会招来重新争论）。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import NOTES, Failure, report  # noqa: E402

CLASSES = {"gameplay", "tech", "art", "audio", "narrative", "process"}
LIFECYCLES = {"proposed", "implemented", "rejected", "archived"}

REQUIRED_SECTIONS = {
    "proposed": ["## 问题", "## 提案", "## 备选方案", "## 验收标准", "## 风险"],
    "implemented": ["## 问题", "## 决策", "## 备选方案", "## 后果"],
    "rejected": ["## 问题"],
    "archived": ["## 问题", "## 决策", "## 备选方案", "## 后果"],
}
FORBIDDEN_IN_IMPLEMENTED = ["## 提案", "## 验收标准", "## 实施计划", "## 迁移计划"]
FILENAME = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.md$")


def check_note(path: Path, lifecycle: str) -> list[Failure]:
    failures: list[Failure] = []
    lines = path.read_text(encoding="utf-8").splitlines()

    if len(lines) < 3:
        failures.append(Failure(path, "文件过短，缺少头部块"))
        return failures

    if not lines[0].startswith("# Note: ") or len(lines[0]) <= len("# Note: "):
        failures.append(Failure(path, f"第 1 行必须为 `# Note: <标题>`，实际：{lines[0]!r}", 1))
    if lines[1].strip() != "":
        failures.append(Failure(path, "第 2 行必须为空行", 2))
    if not lines[2].startswith("Status: "):
        failures.append(Failure(path, f"第 3 行必须为 `Status: <status>`，实际：{lines[2]!r}", 3))
        return failures

    status = lines[2][len("Status: "):].strip()
    if lifecycle == "rejected":
        if not status.startswith("rejected —"):
            failures.append(Failure(path, "rejected 的 Status 必须为 `rejected — <一句话原因>`", 3))
    else:
        expected = "implemented" if lifecycle == "archived" else lifecycle
        if status != expected:
            failures.append(Failure(path, f"Status 应为 {expected!r}（与所在目录一致），实际 {status!r}", 3))

    if lifecycle == "archived" and not any(line.startswith("Archived: ") for line in lines[3:5]):
        failures.append(Failure(path, "archived note 必须在 Status 行下方带 `Archived: YYYY-MM-DD`", 4))

    body = "\n".join(lines)
    for section in REQUIRED_SECTIONS[lifecycle]:
        if section not in body:
            failures.append(Failure(path, f"缺少必需章节 {section}"))

    if lifecycle in ("implemented", "archived"):
        for banned in FORBIDDEN_IN_IMPLEMENTED:
            if banned in body:
                failures.append(Failure(path, f"{lifecycle} 中禁止提案期标题 {banned}（迁移时必须改写为现在时）"))

    if "## 备选方案" in body:
        section = body.split("## 备选方案", 1)[1]
        section = re.split(r"^## ", section, maxsplit=1, flags=re.MULTILINE)[0]
        if len(section.strip()) < 40:
            failures.append(
                Failure(
                    path,
                    "## 备选方案 内容过少；每个真实考虑过的方案要写清为什么输了",
                    fix="补充真实考虑过的备选（只记录真实存在的，不要编造），每个说明它输在哪一点",
                )
            )

    if not FILENAME.match(path.name):
        failures.append(
            Failure(path, "文件名必须为 `yyyy-mm-dd-小写连字符标题.md`", fix="重命名文件；日期用首次提出日期，不随状态迁移改变")
        )

    return failures


def main(argv: list[str]) -> int:
    root = NOTES if len(argv) <= 1 else Path(argv[1])
    failures: list[Failure] = []
    checked = 0

    for lifecycle_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        lifecycle = lifecycle_dir.name
        if lifecycle not in LIFECYCLES:
            failures.append(
                Failure(
                    lifecycle_dir,
                    f"未知 lifecycle 目录（合法：{sorted(LIFECYCLES)}）",
                    fix="把 note 移入合法 lifecycle 目录；新增 lifecycle 需先改 notes/README.md 与本门禁常量",
                )
            )
            continue

        for note in sorted(lifecycle_dir.rglob("*.md")):
            if note.name == "README.md" or note.name == "AGENTS.md":
                continue
            relative = note.relative_to(lifecycle_dir)
            if len(relative.parts) >= 2:
                note_class = relative.parts[0]
                if note_class not in CLASSES:
                    failures.append(
                        Failure(
                            note,
                            f"未知 class 目录「{note_class}」（合法：{sorted(CLASSES)}）",
                            fix="移入合法 class 目录；新增 class 需同时改 notes/README.md 与本门禁常量",
                        )
                    )
            checked += 1
            failures.extend(check_note(note, lifecycle))

    return report("verify-notes-format", failures, checked, "notes/README.md")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
