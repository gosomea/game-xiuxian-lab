#!/usr/bin/env python3
"""verify-vocabulary：词汇表登记门禁（Tier 0）。

铁律：词汇表是全项目唯一公共 API（根 AGENTS.md 约定 2）。

检查两件事：
1. GDScript 中所有 StringName 字面量（&"xxx"）必须在 src/data/vocabulary/ 登记为
   tag / group / event，或属于 Godot 内建白名单（输入动作、内建 signal/组等）。
   选择 StringName 而不是全部字符串，是因为项目约定用 &"" 表达「词汇」，
   普通字符串用于路径与文案——这个约定让门禁能精确定位而不误报。
2. TagRegistry.add_block/remove_block/is_blocked 的 tag 参数必须是已登记 tag。

消灭的失效类别：Tag 打错字导致机制静默失效。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import RUNTIME_ROOTS, TESTS, VOCAB, Failure, gd_files, load_json_files, report, string_literals, strip_comments  # noqa: E402

# Godot 内建：输入动作、常用内建组/信号名，不要求登记
BUILTIN_ALLOW = {
    "ui_accept", "ui_select", "ui_cancel", "ui_focus_next", "ui_focus_prev",
    "ui_left", "ui_right", "ui_up", "ui_down",
    "ui_page_up", "ui_page_down", "ui_home", "ui_end",
    "pressed", "toggled", "timeout", "finished", "animation_finished",
    "body_entered", "body_exited", "area_entered", "area_exited",
    "tree_exiting", "tree_exited", "ready", "process_frame", "physics_frame",
}


def load_vocabulary() -> tuple[set[str], set[str], dict[str, Path]]:
    """返回 (全部已登记词汇, 已登记 tag, 词汇 -> 定义文件)。"""
    all_words: set[str] = set()
    tags: set[str] = set()
    origin: dict[str, Path] = {}

    for path, data in load_json_files(VOCAB):
        if path.name == "index.json":
            continue
        for section in ("tags", "groups", "events", "meta"):
            for word in (data.get(section) or {}):
                all_words.add(word)
                origin[word] = path
                if section == "tags":
                    tags.add(word)
        for owner, definition in (data.get("components") or {}).items():
            all_words.add(owner)
            origin[owner] = path
            for field in (definition.get("fields") or {}):
                all_words.add(field)
                origin[field] = path
            for signal_name in (definition.get("signals") or {}):
                all_words.add(signal_name)
                origin[signal_name] = path
    return all_words, tags, origin


def check_file(path: Path, vocabulary: set[str], tags: set[str]) -> list[Failure]:
    failures: list[Failure] = []
    text = path.read_text(encoding="utf-8")
    body = strip_comments(text)

    for content, is_string_name, line in string_literals(body):
        if not is_string_name:
            continue
        if content in BUILTIN_ALLOW or content in vocabulary:
            continue
        failures.append(
            Failure(
                path,
                f"词汇 &\"{content}\" 未在 src/data/vocabulary/ 登记",
                line,
                fix=f"在 src/data/vocabulary/ 对应域文件登记「{content}」后运行 "
                "python3 tools/gen/gen_vocabulary_index.py；若是拼写错误请改正",
            )
        )

    for match in re.finditer(
        r"TagRegistry\.(?:add_block|remove_block|is_blocked)\s*\(\s*[^,]+,\s*&?[\"']([^\"']+)[\"']", body
    ):
        tag = match.group(1)
        if tag not in tags:
            line = body.count("\n", 0, match.start()) + 1
            failures.append(
                Failure(
                    path,
                    f"TagRegistry 使用了未登记为 tag 的词汇「{tag}」",
                    line,
                    fix=f"在 src/data/vocabulary/tags/<域>.json 的 tags 段登记「{tag}」并重跑索引生成器",
                )
            )

    return failures


def main(argv: list[str]) -> int:
    roots = RUNTIME_ROOTS + [TESTS] if len(argv) <= 1 else [Path(argv[1])]
    vocabulary, tags, _ = load_vocabulary()

    files: list[Path] = []
    for root in roots:
        files.extend(gd_files(root))

    failures: list[Failure] = []
    for path in files:
        failures.extend(check_file(path, vocabulary, tags))

    return report("verify-vocabulary", failures, len(files), "AGENTS.md 铁律 2")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
