#!/usr/bin/env python3
"""gen-vocabulary-index：把 src/data/vocabulary/ 分域文件合并为 index.json。

生成物不手改（根 AGENTS.md 约定 8）。运行时（GDScript）与门禁读索引，
人和 Agent 只编辑分域文件。verify_vocabulary_index.py 查新鲜度。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "verify"))

from _common import VOCAB, load_json_files  # noqa: E402

INDEX_PATH = VOCAB / "index.json"
HEADER = "由 tools/gen/gen_vocabulary_index.py 生成，请勿手改；编辑 tags/ events/ components.json 后重跑。"


SECTIONS = ("tags", "groups", "events", "components", "meta")


def build_index() -> dict:
    index: dict = {"_generated_by": HEADER}
    for section in SECTIONS:
        index[section] = {}
    for path, data in load_json_files(VOCAB):
        if path == INDEX_PATH:
            continue
        source = str(path.relative_to(VOCAB))
        for section in SECTIONS:
            for key, value in (data.get(section) or {}).items():
                if key in index[section]:
                    raise SystemExit(
                        f"ERROR 词汇重复定义：{section}.{key} 同时出现在 "
                        f"{index[section][key]['_source']} 与 {source}"
                    )
                entry = dict(value) if isinstance(value, dict) else {"value": value}
                entry["_source"] = source
                index[section][key] = entry
    return index


def main(argv: list[str]) -> int:
    check_only = "--check" in argv
    index = build_index()
    serialized = json.dumps(index, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    if check_only:
        if not INDEX_PATH.exists():
            print("FAIL verify-vocabulary-index — index.json 不存在，请运行 python tools/gen/gen_vocabulary_index.py")
            return 1
        current = INDEX_PATH.read_text(encoding="utf-8")
        if current != serialized:
            print("FAIL verify-vocabulary-index — index.json 与分域文件不同步，请重跑生成器")
            return 1
        total = sum(len(index[section]) for section in SECTIONS)
        print(f"OK   verify-vocabulary-index — 索引与分域文件同步（{total} 条词汇）")
        return 0

    INDEX_PATH.write_text(serialized, encoding="utf-8")
    total = sum(len(index[section]) for section in SECTIONS)
    print(f"生成 {INDEX_PATH.relative_to(VOCAB.parent.parent)}：{total} 条词汇")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
