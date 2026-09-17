#!/usr/bin/env python3
"""gen-capability-catalog：从源码提取能力元数据，生成 design/capability_catalog.json。

存在理由：Agent 进入仓库时需要用一次读取获得「本项目有哪些能力、触发条件、数据依赖」，
而不是逐个 grep 源码。catalog 是生成物，靠 --check 保证与源码同步。

发现方式为按内容（extends Capability），与 verify_capabilities 一致。
schema v2 从 `src/game/<domain>/<package>/<capability>.gd` 推导 domain/package；
Capability 及其配对测试必须位于叶子包根，非法层级不会生成带漂移的 catalog。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "verify"))

from _common import GAME, REPO_ROOT, RUNTIME_ROOTS, class_name_of, extends_of, func_names, gd_files, strip_comments  # noqa: E402

CATALOG_PATH = REPO_ROOT / "design" / "capability_catalog.json"  # 非运行时读取，留在仓库根
HEADER = "由 tools/gen/gen_capability_catalog.py 生成，请勿手改；改动能力源码后重跑。"

AXIS = ["_should_activate", "_on_activated", "_tick_active", "_should_deactivate", "_on_deactivated"]

EXPORT = re.compile(r"^@export\s+var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z0-9_]+)\s*=\s*(.+)$", re.MULTILINE)
SIGNAL = re.compile(r"^signal\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
COMPONENT_READ = re.compile(r"component\s*\(\s*&\"([A-Za-z0-9_]+)\"\s*\)")
TAG_USE = re.compile(r"TagRegistry\.\w+\s*\([^,]+,\s*&\"([A-Za-z0-9_]+)\"")
GROUP_USE = re.compile(r"get_nodes_in_group\s*\(\s*&\"([A-Za-z0-9_]+)\"|add_to_group\s*\(\s*&\"([A-Za-z0-9_]+)\"")
DOC_FIRST = re.compile(r"^##\s*(.+)$", re.MULTILINE)


def summary_of(text: str) -> str:
    for line in DOC_FIRST.findall(text):
        stripped = line.strip()
        if stripped and not stripped.startswith("用法"):
            return stripped
    return ""


def package_of(path: Path) -> tuple[str, str]:
    """从 `game/<domain>/<package>/<file>` 推导归属；非法层级直接拒绝。"""
    try:
        parts = path.relative_to(GAME).parts
    except ValueError:
        raise ValueError(
            f"{path.relative_to(REPO_ROOT)}：Capability 必须位于 src/game/<domain>/<package>/；"
            "移动到明确的两级叶子包，并把配对测试一同移动"
        ) from None
    if len(parts) < 3:
        raise ValueError(
            f"{path.relative_to(REPO_ROOT)}：Capability 不能位于 src/game 根或领域根；"
            "创建 src/game/<domain>/<具体功能包>/ 后移动脚本与配对测试"
        )
    if len(parts) > 3:
        package = "/".join(parts[:2])
        raise ValueError(
            f"{path.relative_to(REPO_ROOT)}：Capability 必须留在叶子包根；"
            f"移动到 src/game/{package}/，资源子目录可以继续保留"
        )
    return parts[0], f"{parts[0]}/{parts[1]}"


def describe(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    body = strip_comments(text)

    parameters = [
        {"name": name, "type": type_name, "default": default.strip()}
        for name, type_name, default in EXPORT.findall(body)
    ]

    groups: set[str] = set()
    for first, second in GROUP_USE.findall(body):
        groups.add(first or second)

    test_file = path.parent / f"test_{path.name}"

    domain, package = package_of(path)
    return {
        "class": class_name_of(text) or "",
        "domain": domain,
        "package": package,
        "script": str(path.relative_to(REPO_ROOT)),
        "test": str(test_file.relative_to(REPO_ROOT)) if test_file.exists() else "",
        "summary": summary_of(text),
        "axis_implemented": [name for name in AXIS if name in func_names(text)],
        "parameters": parameters,
        "reads_components": sorted(set(COMPONENT_READ.findall(body))),
        "uses_tags": sorted(set(TAG_USE.findall(body))),
        "uses_groups": sorted(groups),
        "signals": sorted(set(SIGNAL.findall(body))),
    }


def build_catalog() -> dict:
    entries: list[dict] = []
    for root in RUNTIME_ROOTS:
        for path in gd_files(root):
            if path.name.startswith("test_"):
                continue
            if extends_of(path.read_text(encoding="utf-8")) != "Capability":
                continue
            entries.append(describe(path))

    entries.sort(key=lambda entry: (entry["package"], entry["class"]))
    domains = sorted({entry["domain"] for entry in entries})
    packages = sorted({entry["package"] for entry in entries})
    return {
        "_generated_by": HEADER,
        "schema_version": 2,
        "count": len(entries),
        "domains": domains,
        "packages": packages,
        "capabilities": entries,
    }


def main(argv: list[str]) -> int:
    try:
        catalog = build_catalog()
    except ValueError as error:
        print(f"FAIL verify-capability-catalog — 玩法包结构非法\n      {error}")
        return 1
    serialized = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    if "--check" in argv:
        if not CATALOG_PATH.exists():
            print("FAIL verify-capability-catalog — capability_catalog.json 不存在")
            print("      修复：python3 tools/gen/gen_capability_catalog.py")
            return 1
        if CATALOG_PATH.read_text(encoding="utf-8") != serialized:
            print("FAIL verify-capability-catalog — catalog 与能力源码不同步")
            print("      修复：python3 tools/gen/gen_capability_catalog.py")
            return 1
        print(
            f"OK   verify-capability-catalog — catalog 与源码同步"
            f"（{catalog['count']} 个能力，{len(catalog['domains'])} 个领域，{len(catalog['packages'])} 个叶子包）"
        )
        return 0

    CATALOG_PATH.write_text(serialized, encoding="utf-8")
    print(
        f"生成 design/capability_catalog.json：{catalog['count']} 个能力，"
        f"叶子包 {', '.join(catalog['packages']) or '(无)'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
