#!/usr/bin/env python3
"""verify-packages：两级玩法分包与包规模门禁（Tier 0）。

默认检查 `src/game` 和 `design/package_policy.json`。领域目录只导航，
真正运行时内容属于 `src/game/<domain>/<package>/`；Capability 与配对测试
必须留在叶子包根。包超过 policy 阈值时，只接受引用 implemented note 的显式豁免。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import GAME, REPO_ROOT, Failure, extends_of, report  # noqa: E402

DEFAULT_POLICY = REPO_ROOT / "design" / "package_policy.json"
DOC = "notes/implemented/tech/2026-09-02-two-level-gameplay-packages.md"
SNAKE_CASE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")

# `.uid` / `.import` 是 Godot 伴生元数据；Markdown 与 `.gitkeep` 是仓库说明，
# 它们本身不形成运行时包。其余常见 Godot/资产/数据文件都视为运行时内容。
NON_RUNTIME_NAMES = {"AGENTS.md", ".gitkeep", ".gdignore"}
NON_RUNTIME_SUFFIXES = {".uid", ".import", ".md"}


@dataclass(frozen=True)
class PackageStats:
    path: Path
    name: str
    capabilities: int
    non_test_gdscript: int


def is_runtime_file(path: Path) -> bool:
    return path.name not in NON_RUNTIME_NAMES and path.suffix.lower() not in NON_RUNTIME_SUFFIXES


def is_capability(path: Path) -> bool:
    if path.suffix != ".gd" or path.name.startswith("test_"):
        return False
    return extends_of(path.read_text(encoding="utf-8")) == "Capability"


def implemented_note_failure(repo_root: Path, note_value: object) -> str | None:
    if not isinstance(note_value, str) or not note_value:
        return "note 必须是 notes/implemented/ 下的非空相对路径"
    note_rel = Path(note_value)
    if note_rel.is_absolute() or ".." in note_rel.parts or note_rel.parts[:2] != ("notes", "implemented"):
        return "note 必须位于 notes/implemented/，且不得使用绝对路径或 .."
    note_path = repo_root / note_rel
    if not note_path.is_file():
        return f"豁免 note 不存在：{note_value}"
    lines = note_path.read_text(encoding="utf-8").splitlines()
    if len(lines) < 3 or lines[2].strip() != "Status: implemented":
        return f"豁免 note 必须为 Status: implemented：{note_value}"
    return None


def load_policy(policy_path: Path, repo_root: Path) -> tuple[dict | None, list[Failure]]:
    failures: list[Failure] = []
    try:
        policy = json.loads(policy_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, [Failure(policy_path, "package policy 不存在", fix="创建 design/package_policy.json，写入 schema_version、limits 与 exceptions")]
    except (json.JSONDecodeError, OSError) as error:
        return None, [Failure(policy_path, f"package policy 无法解析：{error}", fix="修复 JSON 语法后重跑 verify-packages")]

    if not isinstance(policy, dict):
        return None, [Failure(policy_path, "package policy 顶层必须是 JSON object", fix="按 design/package_policy.json 示例重写 policy")]
    if policy.get("schema_version") != 1:
        failures.append(Failure(policy_path, "schema_version 必须为 1", fix='设置 "schema_version": 1'))

    limits = policy.get("limits")
    if not isinstance(limits, dict):
        failures.append(Failure(policy_path, "limits 必须是 object", fix="补充 max_capabilities 与 max_non_test_gdscript"))
    else:
        for key in ("max_capabilities", "max_non_test_gdscript"):
            value = limits.get(key)
            if not isinstance(value, int) or isinstance(value, bool) or value < 1:
                failures.append(Failure(policy_path, f"limits.{key} 必须是正整数", fix=f"为 {key} 设置大于 0 的整数阈值"))

    exceptions = policy.get("exceptions")
    if not isinstance(exceptions, list):
        failures.append(Failure(policy_path, "exceptions 必须是数组", fix='没有豁免时使用 "exceptions": []'))
        return policy, failures

    seen: set[str] = set()
    for index, item in enumerate(exceptions):
        label = f"exceptions[{index}]"
        if not isinstance(item, dict):
            failures.append(Failure(policy_path, f"{label} 必须是 object", fix="每项填写 package、note、reason"))
            continue
        package = item.get("package")
        if not isinstance(package, str) or len(Path(package).parts) != 2 or any(not SNAKE_CASE.fullmatch(part) for part in Path(package).parts):
            failures.append(Failure(policy_path, f"{label}.package 必须是 snake_case 的 domain/package", fix='例如 "systems/example"'))
        elif package in seen:
            failures.append(Failure(policy_path, f"重复豁免 package：{package}", fix="每个包只保留一个 exceptions 条目"))
        else:
            seen.add(package)

        reason = item.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            failures.append(Failure(policy_path, f"{label}.reason 不能为空", fix="说明为什么这些文件仍属于同一个状态生命周期和删除单元"))

        note_error = implemented_note_failure(repo_root, item.get("note"))
        if note_error:
            failures.append(Failure(policy_path, f"{label}：{note_error}", fix="先将 owning note 完整实施并移至 notes/implemented/，再登记豁免"))

    return policy, failures


def collect_packages(game_root: Path) -> tuple[list[PackageStats], list[Failure]]:
    failures: list[Failure] = []
    packages: dict[str, Path] = {}

    if not game_root.is_dir():
        return [], [Failure(game_root, "src/game 不存在", fix="创建 src/game/<domain>/<package>/，或用 --game 指向实际玩法目录")]

    for domain in sorted(path for path in game_root.iterdir() if path.is_dir() and not path.name.startswith(".")):
        if not SNAKE_CASE.fullmatch(domain.name):
            failures.append(Failure(domain, "领域目录名必须为 snake_case", fix=f"将 {domain.name} 改为小写 snake_case"))

        domain_runtime = [path for path in domain.iterdir() if path.is_file() and is_runtime_file(path)]
        for path in domain_runtime:
            failures.append(
                Failure(
                    path,
                    f"领域目录 {domain.name}/ 只负责导航，不得直接放运行时文件",
                    fix=f"创建 src/game/{domain.name}/<具体功能包>/，按行为边界、状态生命周期和删除单元移动 {path.name}",
                )
            )

        for package in sorted(path for path in domain.iterdir() if path.is_dir() and not path.name.startswith(".")):
            if not SNAKE_CASE.fullmatch(package.name):
                failures.append(Failure(package, "叶子包目录名必须为 snake_case", fix=f"将 {package.name} 改为小写 snake_case"))
            packages[f"{domain.name}/{package.name}"] = package

    # 游戏根只允许 AGENTS/元数据；文件或单层包内容不能绕过 domain/package。
    for path in sorted(game_root.iterdir()):
        if path.is_file() and is_runtime_file(path):
            failures.append(
                Failure(
                    path,
                    "运行时文件不能直接放在 src/game 根目录",
                    fix="移动到 src/game/<domain>/<package>/；第一层导航、第二层才是删除单元",
                )
            )

    stats: list[PackageStats] = []
    for name, package in sorted(packages.items()):
        gdscript = sorted(path for path in package.rglob("*.gd") if path.is_file())
        capabilities = [path for path in gdscript if is_capability(path)]
        non_test = [path for path in gdscript if not path.name.startswith("test_")]

        for capability in capabilities:
            if capability.parent != package:
                failures.append(
                    Failure(
                        capability,
                        f"Capability 必须位于叶子包 {name} 根目录",
                        fix=f"将 {capability.name} 移到 src/game/{name}/，并把 test_{capability.name} 一同移动",
                    )
                )
            paired_test = capability.parent / f"test_{capability.name}"
            if paired_test.exists() and capability.parent != package:
                failures.append(Failure(paired_test, "Capability 配对测试必须与能力一起位于叶子包根目录", fix=f"移动到 src/game/{name}/"))

        stats.append(PackageStats(package, name, len(capabilities), len(non_test)))

    return stats, failures


def check_packages(game_root: Path, policy_path: Path) -> tuple[list[Failure], int]:
    # 标准布局下 policy 位于 <repo>/design；自定义测试/迁移目录也沿用这一关系。
    repo_root = policy_path.parent.parent
    policy, failures = load_policy(policy_path, repo_root)
    stats, structure_failures = collect_packages(game_root)
    failures.extend(structure_failures)
    if policy is None or any(not isinstance(policy.get(key), expected) for key, expected in (("limits", dict), ("exceptions", list))):
        return failures, len(stats)

    limits = policy["limits"]
    if any(not isinstance(limits.get(key), int) or isinstance(limits.get(key), bool) or limits.get(key, 0) < 1 for key in ("max_capabilities", "max_non_test_gdscript")):
        return failures, len(stats)

    exceptions = {item.get("package"): item for item in policy["exceptions"] if isinstance(item, dict) and isinstance(item.get("package"), str)}
    existing = {item.name for item in stats}
    for package_name in sorted(set(exceptions) - existing):
        failures.append(Failure(policy_path, f"豁免指向不存在的包：{package_name}", fix="删除过期豁免，或修正 package 为实际 domain/package"))

    for item in stats:
        exceeded: list[str] = []
        if item.capabilities > limits["max_capabilities"]:
            exceeded.append(f"Capability {item.capabilities}/{limits['max_capabilities']}")
        if item.non_test_gdscript > limits["max_non_test_gdscript"]:
            exceeded.append(f"非测试 GDScript {item.non_test_gdscript}/{limits['max_non_test_gdscript']}")
        if exceeded and item.name not in exceptions:
            failures.append(
                Failure(
                    item.path,
                    f"叶子包超出规模阈值：{', '.join(exceeded)}",
                    fix="优先按不同玩家行为、状态生命周期或删除单元拆包；若确认不可拆，先完成 owning note，再在 design/package_policy.json 登记豁免",
                )
            )

    return failures, len(stats)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="验证 src/game 两级玩法包结构与规模")
    parser.add_argument("--game", type=Path, default=GAME, help="玩法目录，默认 src/game")
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY, help="包策略 JSON，默认 design/package_policy.json")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    failures, checked = check_packages(args.game.resolve(), args.policy.resolve())
    return report("verify-packages", failures, checked, DOC)


if __name__ == "__main__":
    raise SystemExit(main())
