#!/usr/bin/env python3
"""verify-skills：Skill 命名与结构门禁（Tier 0）。

依据 notes/implemented/process/2026-08-28-skill-prefix-taxonomy.md
与 notes/implemented/process/2026-08-28-external-skills-vendored.md。

检查每个 skills/<name>/：
1. 目录名带合法域前缀（Agent 可按域裁剪加载）；
2. 存在 SKILL.md；
3. SKILL.md 有 frontmatter 且含 name 与 description；
4. frontmatter 的 name 与目录名一致 —— Agent 按 name 路由，不一致会导致按清单找不到 skill。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import REPO_ROOT, Failure, report  # noqa: E402

SKILLS = REPO_ROOT / "skills"
PREFIXES = ("flow-", "godot-", "design-", "feel-", "ui-", "web-", "proto-", "mp-", "mcp-")
DOC = "skills/README.md"

NAME_LINE = re.compile(r"^name:\s*[\"']?([A-Za-z0-9_-]+)[\"']?\s*$", re.MULTILINE)
DESC_LINE = re.compile(r"^description:\s*\S", re.MULTILINE)


def frontmatter_of(path: Path) -> str | None:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    return text[3:end]


def check_skill(directory: Path) -> list[Failure]:
    failures: list[Failure] = []
    name = directory.name

    if not name.startswith(PREFIXES):
        failures.append(
            Failure(
                directory,
                f"skill 目录名缺少合法域前缀（合法：{', '.join(PREFIXES)}）",
                fix=f"重命名为 <前缀>{name} 并同步改写 SKILL.md 的 name 字段与 skills/README.md 清单",
            )
        )

    skill_file = directory / "SKILL.md"
    if not skill_file.exists():
        failures.append(
            Failure(directory, "缺少 SKILL.md", fix="补齐 SKILL.md（格式见 skills/README.md 的写作规范）")
        )
        return failures

    frontmatter = frontmatter_of(skill_file)
    if frontmatter is None:
        failures.append(
            Failure(skill_file, "缺少 YAML frontmatter（--- 包裹的头部块）", fix="在文件开头添加含 name 与 description 的 frontmatter")
        )
        return failures

    if not DESC_LINE.search(frontmatter):
        failures.append(
            Failure(
                skill_file,
                "frontmatter 缺少 description（它是 Agent 选择 skill 的唯一依据）",
                fix="添加 description，写成「Use when …」触发场景清单，含反向边界",
            )
        )

    match = NAME_LINE.search(frontmatter)
    if match is None:
        failures.append(Failure(skill_file, "frontmatter 缺少 name", fix=f"添加 name: {name}"))
    elif match.group(1) != name:
        failures.append(
            Failure(
                skill_file,
                f"frontmatter 的 name「{match.group(1)}」与目录名「{name}」不一致（Agent 按 name 路由）",
                fix=f"把 name 改为 {name}",
            )
        )

    return failures


def main(argv: list[str]) -> int:
    root = SKILLS if len(argv) <= 1 else Path(argv[1])
    if not root.exists():
        return report("verify-skills", [], 0)

    directories = sorted(p for p in root.iterdir() if p.is_dir() and not p.name.startswith("_"))
    failures: list[Failure] = []
    for directory in directories:
        failures.extend(check_skill(directory))

    return report("verify-skills", failures, len(directories), DOC)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
