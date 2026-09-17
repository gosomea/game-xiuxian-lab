#!/usr/bin/env python3
"""verify-mcp：MCP 集成一致性门禁（Tier 0）。

依据 notes/implemented/process/2026-08-28-mcp-directory-separation.md。

MCP 服务器提供工具，skills/mcp-* 提供纪律。两者必须对应且工具清单不漂移——
上游改名或新增工具时，纪律 skill 会静默过时，本门禁负责发现。

检查：
1. 每个 mcp/<name>/ 有对应的 skills/mcp-<短名>/（纪律不可缺席）；
2. vendored 源码的工具数与 skill 中记录的数量一致（防上游漂移）；
3. vendored 目录保留 LICENSE（再分发合规）。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import REPO_ROOT, Failure, report  # noqa: E402

MCP_ROOT = REPO_ROOT / "mcp"
SKILLS = REPO_ROOT / "skills"
DOC = "mcp/README.md"

# mcp 目录名 -> (配套 skill 目录名, 工具计数源文件, 期望工具数)
INTEGRATIONS: dict[str, tuple[str, str, int]] = {
    "blender-mcp": ("mcp-blender", "src/blender_mcp/server.py", 25),
}

TOOL_DECORATOR = re.compile(r"@mcp\.tool\(\)")


def check_integration(directory: Path, skill_name: str, source: str, expected: int) -> list[Failure]:
    """directory 由调用方传入实际路径，不从 MCP_ROOT 重新拼接——
    否则以自定义 root 运行时（负向控制）会误检真实仓库内容。"""
    failures: list[Failure] = []

    skill = SKILLS / skill_name
    if not (skill / "SKILL.md").exists():
        failures.append(
            Failure(
                directory,
                f"缺少配套纪律 skill：skills/{skill_name}/SKILL.md",
                fix=f"创建 skills/{skill_name}/SKILL.md，写明工具分组、硬性前置、验证方式",
            )
        )

    if not (directory / "LICENSE").exists():
        failures.append(
            Failure(directory, "vendored 目录缺少 LICENSE（再分发需保留上游许可）", fix="从上游补回 LICENSE 文件")
        )

    server = directory / source
    if not server.exists():
        failures.append(
            Failure(
                directory,
                f"找不到工具定义源文件 {source}（上游结构可能已变）",
                fix="核对上游结构并更新 verify_mcp.py 的 INTEGRATIONS 表",
            )
        )
        return failures

    actual = len(TOOL_DECORATOR.findall(server.read_text(encoding="utf-8")))
    if actual != expected:
        failures.append(
            Failure(
                server,
                f"工具数变化：期望 {expected}，实际 {actual}（skills/{skill_name} 的工具清单可能已过时）",
                fix=f"核对 skills/{skill_name}/SKILL.md 与 mcp/README.md 的工具清单，"
                f"同步后把 verify_mcp.py 的期望值改为 {actual}，并在 notes 记录版本变更",
            )
        )

    return failures


def main(argv: list[str]) -> int:
    root = MCP_ROOT if len(argv) <= 1 else Path(argv[1])
    if not root.exists():
        return report("verify-mcp", [], 0)

    failures: list[Failure] = []
    checked = 0

    for directory in sorted(p for p in root.iterdir() if p.is_dir()):
        checked += 1
        if directory.name not in INTEGRATIONS:
            failures.append(
                Failure(
                    directory,
                    "未登记的 MCP 集成",
                    fix="在 verify_mcp.py 的 INTEGRATIONS 表登记，并在 mcp/README.md 清单中说明用途、安装与风险",
                )
            )
            continue
        skill_name, source, expected = INTEGRATIONS[directory.name]
        failures.extend(check_integration(directory, skill_name, source, expected))

    return report("verify-mcp", failures, checked, DOC)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
