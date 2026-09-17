#!/usr/bin/env python3
"""verify_packages 的结构、阈值与豁免单元测试。"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.verify.verify_packages import check_packages


class VerifyPackagesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="gt_packages_")
        self.root = Path(self.temporary.name)
        self.game = self.root / "src" / "game"
        self.policy = self.root / "design" / "package_policy.json"
        self.game.mkdir(parents=True)
        self.policy.parent.mkdir(parents=True)
        (self.root / "notes" / "implemented" / "tech").mkdir(parents=True)
        (self.root / "notes" / "proposed" / "tech").mkdir(parents=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_policy(self, exceptions: list[dict] | None = None) -> None:
        self.policy.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "limits": {"max_capabilities": 4, "max_non_test_gdscript": 12},
                    "exceptions": exceptions or [],
                }
            ),
            encoding="utf-8",
        )

    def write_capabilities(self, count: int, package: str = "systems/vitals") -> Path:
        directory = self.game / package
        directory.mkdir(parents=True, exist_ok=True)
        for index in range(count):
            (directory / f"cap_{index}.gd").write_text(
                f"class_name Cap{index}\nextends Capability\nfunc _should_activate() -> bool:\n\treturn true\n",
                encoding="utf-8",
            )
            (directory / f"test_cap_{index}.gd").write_text("extends RefCounted\n", encoding="utf-8")
        return directory

    def write_note(self, lifecycle: str, status: str) -> str:
        relative = f"notes/{lifecycle}/tech/2026-09-02-package.md"
        (self.root / relative).write_text(f"# Note: package\n\nStatus: {status}\n", encoding="utf-8")
        return relative

    def messages(self) -> list[str]:
        failures, _ = check_packages(self.game, self.policy)
        return [failure.message for failure in failures]

    def test_valid_two_level_package(self) -> None:
        self.write_policy()
        self.write_capabilities(2)
        self.assertEqual(self.messages(), [])

    def test_domain_root_runtime_file_fails(self) -> None:
        self.write_policy()
        domain = self.game / "systems"
        domain.mkdir()
        (domain / "combat.gd").write_text("extends Node\n", encoding="utf-8")
        self.assertTrue(any("只负责导航" in message for message in self.messages()))

    def test_fifth_capability_fails_without_exception(self) -> None:
        self.write_policy()
        self.write_capabilities(5)
        self.assertTrue(any("Capability 5/4" in message for message in self.messages()))

    def test_thirteenth_non_test_script_fails(self) -> None:
        self.write_policy()
        directory = self.game / "systems" / "vitals"
        directory.mkdir(parents=True)
        for index in range(13):
            (directory / f"helper_{index}.gd").write_text("extends Node\n", encoding="utf-8")
        self.assertTrue(any("非测试 GDScript 13/12" in message for message in self.messages()))

    def test_valid_exception_allows_oversized_package(self) -> None:
        note = self.write_note("implemented", "implemented")
        self.write_policy([{"package": "systems/vitals", "note": note, "reason": "这些能力共享同一状态生命周期，删除时必须整体移除。"}])
        self.write_capabilities(5)
        self.assertEqual(self.messages(), [])

    def test_missing_note_fails(self) -> None:
        self.write_policy([{"package": "systems/vitals", "note": "notes/implemented/tech/missing.md", "reason": "同一删除单元"}])
        self.write_capabilities(5)
        self.assertTrue(any("不存在" in message for message in self.messages()))

    def test_proposed_note_fails(self) -> None:
        proposed = self.write_note("proposed", "proposed")
        self.write_policy([{"package": "systems/vitals", "note": proposed, "reason": "同一删除单元"}])
        self.write_capabilities(5)
        self.assertTrue(any("notes/implemented" in message for message in self.messages()))

    def test_empty_reason_fails(self) -> None:
        note = self.write_note("implemented", "implemented")
        self.write_policy([{"package": "systems/vitals", "note": note, "reason": "  "}])
        self.write_capabilities(5)
        self.assertTrue(any("reason 不能为空" in message for message in self.messages()))


if __name__ == "__main__":
    unittest.main()
