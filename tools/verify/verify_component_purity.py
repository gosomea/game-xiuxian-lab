#!/usr/bin/env python3
"""verify-component-purity：Component 纯度门禁（Tier 0）。

铁律：Component 只存数据，不做决策（根 AGENTS.md 约定 1）。

拒绝在 extends Component 的脚本中出现：
1. 每帧回调 _process / _physics_process / _input / _unhandled_input；
2. 全局决策设施引用 TagRegistry / TimeKeeper / Input / Engine.time_scale；
3. 场景树遍历（get_tree / get_node / get_parent）——数据容器不该认识自己的宿主结构。

允许：字段、派生值计算函数、数据存取方法、数据变化 signal、_ready 中的字段初始化。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import RUNTIME_ROOTS, Failure, extends_of, gd_files, report, strip_comments  # noqa: E402

FORBIDDEN_FUNCS = ["_process", "_physics_process", "_input", "_unhandled_input", "_unhandled_key_input"]
FORBIDDEN_SYMBOLS = ["TagRegistry", "TimeKeeper", "Input", "Engine", "get_tree", "get_node", "get_parent"]


def check_file(path: Path) -> list[Failure]:
    text = path.read_text(encoding="utf-8")
    if extends_of(text) != "Component":
        return []

    failures: list[Failure] = []
    body = strip_comments(text)

    for name in FORBIDDEN_FUNCS:
        match = re.search(rf"^\s*func\s+{re.escape(name)}\s*\(", body, re.MULTILINE)
        if match:
            line = body.count("\n", 0, match.start()) + 1
            failures.append(
                Failure(
                    path,
                    f"Component 禁止实现 {name}（每帧回调属于决策）",
                    line,
                    fix=f"把 {name} 的逻辑移到一个 Capability 的 _tick_active 中，Component 只保留数据字段",
                )
            )

    for symbol in FORBIDDEN_SYMBOLS:
        for match in re.finditer(rf"\b{re.escape(symbol)}\b", body):
            line = body.count("\n", 0, match.start()) + 1
            failures.append(
                Failure(
                    path,
                    f"Component 禁止引用 {symbol}（数据容器不做决策、不认识宿主结构）",
                    line,
                    fix=f"把用到 {symbol} 的逻辑上移到 Capability；Component 只暴露字段与派生值计算",
                )
            )
            break

    return failures


def main(argv: list[str]) -> int:
    roots = RUNTIME_ROOTS if len(argv) <= 1 else [Path(argv[1])]
    files: list[Path] = []
    for root in roots:
        files.extend(gd_files(root))
    failures: list[Failure] = []
    checked = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        if extends_of(text) == "Component":
            checked += 1
            failures.extend(check_file(path))
    return report("verify-component-purity", failures, checked, "AGENTS.md 铁律 1")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
