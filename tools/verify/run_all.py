#!/usr/bin/env python3
"""run_all：门禁总入口（Agent / 人 / CI 三方同一入口）。

Tier 0 全开；Tier 1/2 门禁写好后通过 --tier 参数选择性启用
（依据 notes/implemented/process/2026-08-28-gate-tiers.md）。

用法：
  python tools/verify/run_all.py              # Tier 0
  python tools/verify/run_all.py --tier 1     # Tier 0 + 1
  python tools/verify/run_all.py --with-tests # 附带运行时测试（需要 GODOT 环境变量或默认路径）
  python tools/verify/run_all.py --list       # 列出门禁与所属 Tier
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent

GODOT_CANDIDATES = [
    "/Applications/Godot.app/Contents/MacOS/Godot",
    "godot",
    "godot4",
]

# (名称, 命令, tier)
GATES: list[tuple[str, list[str], int]] = [
    ("verify-vocabulary-index", [sys.executable, "tools/gen/gen_vocabulary_index.py", "--check"], 0),
    ("verify-capability-catalog", [sys.executable, "tools/gen/gen_capability_catalog.py", "--check"], 0),
    ("verify-packages", [sys.executable, "tools/verify/verify_packages.py"], 0),
    ("verify-vocabulary", [sys.executable, "tools/verify/verify_vocabulary.py"], 0),
    ("verify-capabilities", [sys.executable, "tools/verify/verify_capabilities.py"], 0),
    ("verify-component-purity", [sys.executable, "tools/verify/verify_component_purity.py"], 0),
    ("verify-scenes", [sys.executable, "tools/verify/verify_scenes.py"], 0),
    ("verify-skills", [sys.executable, "tools/verify/verify_skills.py"], 0),
    ("verify-mcp", [sys.executable, "tools/verify/verify_mcp.py"], 0),
    ("verify-agent-entries", [sys.executable, "tools/verify/verify_agent_entries.py"], 0),
    ("verify-notes-format", [sys.executable, "tools/verify/verify_notes_format.py"], 0),
    ("negative-control", [sys.executable, "tools/verify/negative_control.py"], 0),
]


def find_godot() -> str | None:
    explicit = os.environ.get("GODOT")
    if explicit:
        return explicit
    for candidate in GODOT_CANDIDATES:
        if Path(candidate).exists():
            return candidate
        found = shutil.which(candidate)
        if found:
            return found
    return None


def run_tests() -> int:
    godot = find_godot()
    if godot is None:
        print("SKIP 运行时测试 — 未找到 Godot 可执行文件（设置 GODOT 环境变量指定路径）")
        return 0
    result = subprocess.run(
        [godot, "--headless", "--path", "src", "tests/test_runner.tscn"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    for line in result.stdout.splitlines():
        if line.startswith(("OK", "FAIL", "  ", "测试合计")):
            print(line)
    return result.returncode


def main(argv: list[str]) -> int:
    if "--list" in argv:
        for name, command, tier in GATES:
            print(f"Tier {tier}  {name:26s} {' '.join(command[1:])}")
        return 0

    max_tier = 0
    if "--tier" in argv:
        max_tier = int(argv[argv.index("--tier") + 1])

    selected = [gate for gate in GATES if gate[2] <= max_tier]
    failed: list[str] = []

    for name, command, _tier in selected:
        result = subprocess.run(command, cwd=REPO_ROOT)
        if result.returncode != 0:
            failed.append(name)

    if "--with-tests" in argv:
        print()
        if run_tests() != 0:
            failed.append("runtime-tests")

    print()
    if failed:
        print(f"门禁未通过（{len(failed)}/{len(selected)}）：{', '.join(failed)}")
        return 1
    print(f"门禁全部通过（Tier <= {max_tier}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
