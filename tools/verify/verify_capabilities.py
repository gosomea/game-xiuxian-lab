#!/usr/bin/env python3
"""verify-capabilities：Capability 契约门禁（Tier 0）。

发现方式为**按内容**而非按路径：扫描 src/ 下全部 .gd，取 extends Capability 者。
这使能力可与其所属功能同处一个包（game/<功能名>/），而不必集中在固定目录
（依据 notes/implemented/tech/2026-08-28-src-feature-packaging.md）。

检查每个 Capability 脚本：
1. 实现 _should_activate（最小契约）且轴函数不少于两个；
2. 不引用其他 Capability 类型（通信只走 Component + TagRegistry）——
   同一功能包内的能力之间同样禁止，物理相邻不构成例外；
3. 同目录存在配对测试 test_<basename>.gd。

「已在 catalog 中登记」由 gen_capability_catalog.py --check 单独保证。
负向控制用例在 tools/verify/negative_control.py 中以临时目录构造。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import (  # noqa: E402
    REPO_ROOT,
    RUNTIME_ROOTS,
    Failure,
    class_name_of,
    extends_of,
    func_names,
    gd_files,
    report,
    strip_comments,
)

AXIS = ["_should_activate", "_on_activated", "_tick_active", "_should_deactivate", "_on_deactivated"]
DOC = "AGENTS.md 铁律 2 / skills/flow-add-capability/SKILL.md"


def is_test_file(path: Path) -> bool:
    return path.name.startswith("test_")


def capability_files(roots: list[Path]) -> list[Path]:
    """按内容发现：extends Capability 且非测试文件。"""
    found: list[Path] = []
    for root in roots:
        for path in gd_files(root):
            if is_test_file(path):
                continue
            if extends_of(path.read_text(encoding="utf-8")) == "Capability":
                found.append(path)
    return sorted(found)


def check_capability(path: Path, peers: dict[str, Path]) -> list[Failure]:
    failures: list[Failure] = []
    text = path.read_text(encoding="utf-8")
    body = strip_comments(text)
    self_class = class_name_of(text)

    if self_class is None:
        failures.append(
            Failure(
                path,
                "Capability 必须声明 class_name（catalog 与门禁按类名识别能力）",
                fix="在文件首行添加 class_name <名称>",
            )
        )

    implemented = [name for name in func_names(text) if name in AXIS]
    if "_should_activate" not in implemented:
        failures.append(
            Failure(
                path,
                "必须实现 _should_activate（激活条件是能力的最小契约）",
                fix="添加 func _should_activate() -> bool，返回本能力何时该激活",
            )
        )
    if len(implemented) < 2:
        failures.append(
            Failure(
                path,
                f"五函数轴至少实现两个（当前 {implemented}）；只有激活条件没有行为的能力没有意义",
                fix=f"补一个行为函数：{', '.join(n for n in AXIS if n not in implemented)}",
            )
        )

    for peer_class, peer_path in peers.items():
        if peer_class == self_class:
            continue
        hit = re.search(rf"\b{re.escape(peer_class)}\b", body)
        if hit:
            line = body.count("\n", 0, hit.start()) + 1
            same_package = peer_path.parent == path.parent
            note = "（同一功能包内也不例外：物理相邻不改变解耦要求）" if same_package else ""
            failures.append(
                Failure(
                    path,
                    f"禁止直接引用其他 Capability「{peer_class}」{note}",
                    line,
                    fix="改为读写共享 Component 字段，或用 TagRegistry 阻塞表达互斥；"
                    "需要的数据在 Component 里没有就先扩展 Component",
                )
            )

    for match in re.finditer(r"(?:preload|load)\s*\(\s*[\"']([^\"']+)[\"']", body):
        target = match.group(1)
        if target.endswith(".gd") and Path(target).name != path.name:
            resolved = REPO_ROOT / target.replace("res://", "")
            if resolved.exists() and extends_of(resolved.read_text(encoding="utf-8")) == "Capability":
                line = body.count("\n", 0, match.start()) + 1
                failures.append(
                    Failure(path, f"禁止加载其他 Capability 脚本：{target}", line, fix="同上：通信走 Component / TagRegistry")
                )

    test_file = path.parent / f"test_{path.name}"
    if not test_file.exists():
        failures.append(
            Failure(
                path,
                f"缺少同目录配对测试 {test_file.name}（无测试的能力不予入库）",
                fix=f"在 {path.parent.name}/ 下创建 {test_file.name}，"
                "至少覆盖激活条件成立/不成立与失活清理",
            )
        )

    return failures


def main(argv: list[str]) -> int:
    roots = RUNTIME_ROOTS if len(argv) <= 1 else [Path(argv[1])]
    roots = [r for r in roots if r.exists()]
    if not roots:
        return report("verify-capabilities", [], 0)

    files = capability_files(roots)
    peers: dict[str, Path] = {}
    for path in files:
        found = class_name_of(path.read_text(encoding="utf-8"))
        if found:
            peers[found] = path

    failures: list[Failure] = []
    for path in files:
        failures.extend(check_capability(path, peers))

    return report("verify-capabilities", failures, len(files), DOC)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
