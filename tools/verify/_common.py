"""门禁公共工具：路径定位、GDScript 轻量解析、结果汇报。

设计约束（notes/implemented/process/2026-08-28-gate-tiers.md）：
- 仅使用 Python 3 标准库，零第三方依赖。
- 所有门禁走同一 CLI 入口约定：main() 返回 0 通过 / 1 失败。
- GDScript 没有官方 Python AST 库，这里做正则级的结构提取。提取器保持保守：
  宁可漏报也不误报，漏报由 code-review 的语义检查兜住。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Godot 工程根（见 notes/implemented/tech/2026-08-30-godot-project-under-src.md）：
# res:// 等价于 GODOT_PROJECT，仓库根只放基建。
GODOT_PROJECT = REPO_ROOT / "src"

CORE = GODOT_PROJECT / "core"
GAME = GODOT_PROJECT / "game"
LEVELS = GODOT_PROJECT / "levels"
UI = GODOT_PROJECT / "ui"
TESTS = GODOT_PROJECT / "tests"
VOCAB = GODOT_PROJECT / "data" / "vocabulary"
CONTENT = GODOT_PROJECT / "data" / "content"
NOTES = REPO_ROOT / "notes"

# 全部含 GDScript 的运行时目录（见 notes/implemented/tech/2026-08-29-directory-conventions.md）。
# 门禁按内容而非按路径发现目标，因此新增运行时目录只需在此登记。
RUNTIME_ROOTS = [CORE, GAME, LEVELS, UI]

# 注释与字符串剥离用
_LINE_COMMENT = re.compile(r"#.*$", re.MULTILINE)
_STRING_LITERAL = re.compile(r"""(&?)(["'])(?:\\.|(?!\2).)*\2""")


class Failure:
    """一条门禁失败记录。

    fix 是给 Agent/人的修复路径提示：门禁不只判定对错，还要指出下一步动作
    （见 notes/implemented/process/2026-08-28-first-audit-gaps.md 缺口 3）。
    """

    def __init__(self, path: Path | str, message: str, line: int | None = None, fix: str | None = None) -> None:
        self.path = path
        self.message = message
        self.line = line
        self.fix = fix

    def __str__(self) -> str:
        try:
            shown = Path(self.path).relative_to(REPO_ROOT)
        except (ValueError, TypeError):
            shown = self.path
        location = f"{shown}:{self.line}" if self.line else f"{shown}"
        rendered = f"  {location}\n      {self.message}"
        if self.fix:
            rendered += f"\n      修复：{self.fix}"
        return rendered


def report(gate_name: str, failures: list[Failure], checked: int, doc: str | None = None) -> int:
    """统一汇报格式。返回进程退出码。"""
    if failures:
        print(f"FAIL {gate_name} — {len(failures)} 项不合规（检查 {checked} 个目标）")
        for failure in failures:
            print(str(failure))
        if doc:
            print(f"      规则依据：{doc}")
        return 1
    print(f"OK   {gate_name} — 检查 {checked} 个目标，全部合规")
    return 0


def gd_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(p for p in root.rglob("*.gd") if p.is_file())


def strip_comments(text: str) -> str:
    """去掉行注释（含 ## 文档注释）。不处理多行字符串中的 # ——保守取舍。"""
    return _LINE_COMMENT.sub("", text)


def string_literals(text: str) -> list[tuple[str, bool, int]]:
    """提取字符串字面量：返回 (内容, 是否 StringName(&"..."), 行号)。"""
    result: list[tuple[str, bool, int]] = []
    for match in _STRING_LITERAL.finditer(text):
        raw = match.group(0)
        is_string_name = raw.startswith("&")
        content = raw[2:-1] if is_string_name else raw[1:-1]
        line = text.count("\n", 0, match.start()) + 1
        result.append((content, is_string_name, line))
    return result


def extends_of(text: str) -> str | None:
    match = re.search(r"^extends\s+([A-Za-z_][A-Za-z0-9_]*)", strip_comments(text), re.MULTILINE)
    return match.group(1) if match else None


def class_name_of(text: str) -> str | None:
    match = re.search(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)", strip_comments(text), re.MULTILINE)
    return match.group(1) if match else None


def func_names(text: str) -> list[str]:
    return re.findall(r"^\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)", strip_comments(text), re.MULTILINE)


def load_json_files(root: Path) -> list[tuple[Path, dict]]:
    """加载目录下全部 JSON。解析失败直接抛出，由调用方转成 Failure。"""
    import json

    result: list[tuple[Path, dict]] = []
    if not root.exists():
        return result
    for path in sorted(root.rglob("*.json")):
        with path.open(encoding="utf-8") as handle:
            result.append((path, json.load(handle)))
    return result


def die(message: str) -> None:
    print(f"ERROR {message}", file=sys.stderr)
    raise SystemExit(2)
