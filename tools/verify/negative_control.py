#!/usr/bin/env python3
"""negative_control：门禁负向控制验证。

根 AGENTS.md 约定 6：每条门禁必须证明「故意非法的案例会被真实拒绝」，
否则该门禁视为不存在——只跑正向用例的门禁可能因为选择器写错而恒真。

做法：在临时目录构造非法样本，对该目录运行对应门禁，断言退出码非零。
不污染仓库工作树。
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent

def run_gate(script: str, target: Path) -> int:
    command = [sys.executable, f"tools/verify/{script}"]
    if script == "verify_packages.py":
        command.extend(["--game", str(target / "src" / "game"), "--policy", str(target / "design" / "package_policy.json")])
    else:
        command.append(str(target))
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    return result.returncode


def write_package_policy(root: Path, exceptions: list[dict] | None = None) -> None:
    path = root / "design" / "package_policy.json"
    path.parent.mkdir(parents=True)
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "limits": {"max_capabilities": 4, "max_non_test_gdscript": 12},
                "exceptions": exceptions or [],
            }
        ),
        encoding="utf-8",
    )


def write_capabilities(root: Path, count: int) -> None:
    directory = root / "src" / "game" / "systems" / "oversized"
    directory.mkdir(parents=True)
    for index in range(count):
        (directory / f"cap_{index}.gd").write_text(
            f"class_name NegativeCap{index}\nextends Capability\n\nfunc _should_activate() -> bool:\n\treturn true\n",
            encoding="utf-8",
        )
        (directory / f"test_cap_{index}.gd").write_text("extends RefCounted\n", encoding="utf-8")


def case_package_domain_root_file(root: Path) -> tuple[str, Path]:
    write_package_policy(root)
    domain = root / "src" / "game" / "systems"
    domain.mkdir(parents=True)
    (domain / "combat.gd").write_text("extends Node\n", encoding="utf-8")
    return "领域目录直接放运行时文件", root


def case_package_oversized_without_exception(root: Path) -> tuple[str, Path]:
    write_package_policy(root)
    write_capabilities(root, 5)
    return "第 5 个 Capability 没有豁免", root


def case_package_exception_missing_note(root: Path) -> tuple[str, Path]:
    write_package_policy(
        root,
        [{"package": "systems/oversized", "note": "notes/implemented/tech/missing.md", "reason": "同一状态生命周期"}],
    )
    write_capabilities(root, 5)
    return "超限豁免引用不存在的 implemented note", root


def case_package_exception_proposed_note(root: Path) -> tuple[str, Path]:
    note = root / "notes" / "proposed" / "tech" / "2026-09-02-package.md"
    note.parent.mkdir(parents=True)
    note.write_text("# Note: package\n\nStatus: proposed\n", encoding="utf-8")
    write_package_policy(
        root,
        [{"package": "systems/oversized", "note": "notes/proposed/tech/2026-09-02-package.md", "reason": "同一状态生命周期"}],
    )
    write_capabilities(root, 5)
    return "超限豁免引用 proposed note", root


def case_capability_missing_test(root: Path) -> tuple[str, Path]:
    directory = root / "game" / "notest"
    directory.mkdir(parents=True)
    (directory / "no_test.gd").write_text(
        "class_name NoTestCap\nextends Capability\n\nfunc _should_activate() -> bool:\n\treturn true\n\n\nfunc _tick_active(_d: float) -> void:\n\tpass\n",
        encoding="utf-8",
    )
    return "缺少同目录配对测试的 Capability", root


def case_capability_cross_reference(root: Path) -> tuple[str, Path]:
    # 同一功能包内的两个能力互相引用——物理相邻不构成例外
    directory = root / "game" / "combat"
    directory.mkdir(parents=True)
    (directory / "shield.gd").write_text(
        "class_name ShieldCap\nextends Capability\n\nfunc _should_activate() -> bool:\n\treturn true\n\n\nfunc _tick_active(_d: float) -> void:\n\tpass\n",
        encoding="utf-8",
    )
    (directory / "test_shield.gd").write_text("extends RefCounted\n", encoding="utf-8")
    (directory / "peeker.gd").write_text(
        "class_name PeekerCap\nextends Capability\n\nfunc _should_activate() -> bool:\n\tvar s := ShieldCap.new()\n\treturn s != null\n\n\nfunc _tick_active(_d: float) -> void:\n\tpass\n",
        encoding="utf-8",
    )
    (directory / "test_peeker.gd").write_text("extends RefCounted\n", encoding="utf-8")
    return "同一功能包内跨 Capability 直接引用", root


def case_capability_no_class_name(root: Path) -> tuple[str, Path]:
    directory = root / "game" / "anon"
    directory.mkdir(parents=True)
    (directory / "anon.gd").write_text(
        "extends Capability\n\nfunc _should_activate() -> bool:\n\treturn true\n\n\nfunc _tick_active(_d: float) -> void:\n\tpass\n",
        encoding="utf-8",
    )
    (directory / "test_anon.gd").write_text("extends RefCounted\n", encoding="utf-8")
    return "Capability 未声明 class_name", root


def case_component_decision(root: Path) -> tuple[str, Path]:
    path = root / "bad_component.gd"
    path.write_text(
        "class_name BadComponent\nextends Component\n\nfunc _process(_delta: float) -> void:\n\tpass\n",
        encoding="utf-8",
    )
    return "Component 实现每帧回调", root


def case_component_global_reference(root: Path) -> tuple[str, Path]:
    path = root / "bad_component2.gd"
    path.write_text(
        "class_name BadComponent2\nextends Component\n\nfunc check(target: Node) -> bool:\n\treturn TagRegistry.is_blocked(target, &\"regen_block\")\n",
        encoding="utf-8",
    )
    return "Component 引用全局决策设施", root


def case_unregistered_vocabulary(root: Path) -> tuple[str, Path]:
    path = root / "typo.gd"
    path.write_text(
        "extends Node\n\nfunc apply(target: Node) -> void:\n\tTagRegistry.add_block(target, &\"shenshi_blok\", self)\n",
        encoding="utf-8",
    )
    return "使用未登记的 Tag（拼写错误）", root


def case_sheet_dangling(root: Path) -> tuple[str, Path]:
    path = root / "dangling.tscn"
    path.write_text(
        '[gd_scene load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://src/does_not_exist.gd" id="1"]\n\n'
        '[node name="Bad" type="Node"]\nscript = ExtResource("1")\n',
        encoding="utf-8",
    )
    return "Sheet 悬空引用", root


def case_note_missing_alternatives(root: Path) -> tuple[str, Path]:
    directory = root / "implemented" / "tech"
    directory.mkdir(parents=True)
    (directory / "2026-08-28-bad-note.md").write_text(
        "# Note: 缺少备选方案的决策\n\nStatus: implemented\n\n## 问题\n\n略。\n\n## 决策\n\n略。\n\n## 后果\n\n略。\n",
        encoding="utf-8",
    )
    return "notes 缺少 ## 备选方案", root


def case_note_status_mismatch(root: Path) -> tuple[str, Path]:
    directory = root / "implemented" / "tech"
    directory.mkdir(parents=True)
    (directory / "2026-08-28-mismatch.md").write_text(
        "# Note: Status 与目录不一致\n\nStatus: proposed\n\n## 问题\n\n略。\n\n## 决策\n\n略。\n\n"
        "## 备选方案\n\n**某方案**：输在这里写足够长的理由说明它为什么被击败。\n\n## 后果\n\n略。\n",
        encoding="utf-8",
    )
    return "notes Status 与 lifecycle 目录不一致", root


def case_capability_no_behavior(root: Path) -> tuple[str, Path]:
    directory = root / "game" / "onlycond"
    directory.mkdir(parents=True)
    (directory / "only_condition.gd").write_text(
        "class_name OnlyCondition\nextends Capability\n\nfunc _should_activate() -> bool:\n\treturn true\n",
        encoding="utf-8",
    )
    (directory / "test_only_condition.gd").write_text("extends RefCounted\n", encoding="utf-8")
    return "只有激活条件、无任何行为函数的 Capability", root


def case_sheet_empty(root: Path) -> tuple[str, Path]:
    path = root / "empty_sheet.tscn"
    path.write_text('[gd_scene format=3]\n\n[node name="Empty" type="Node"]\n', encoding="utf-8")
    return "不含任何脚本节点的空 Sheet", root


def case_note_bad_filename(root: Path) -> tuple[str, Path]:
    directory = root / "implemented" / "tech"
    directory.mkdir(parents=True)
    (directory / "BadName.md").write_text(
        "# Note: 文件名不合规\n\nStatus: implemented\n\n## 问题\n\n略。\n\n## 决策\n\n略。\n\n"
        "## 备选方案\n\n**某方案**：输在这里写足够长的理由说明它为什么被击败。\n\n## 后果\n\n略。\n",
        encoding="utf-8",
    )
    return "notes 文件名不符合日期-标题规范", root


def case_note_proposal_heading_in_implemented(root: Path) -> tuple[str, Path]:
    directory = root / "implemented" / "tech"
    directory.mkdir(parents=True)
    (directory / "2026-08-28-stale-heading.md").write_text(
        "# Note: implemented 里残留提案期标题\n\nStatus: implemented\n\n## 问题\n\n略。\n\n## 决策\n\n略。\n\n"
        "## 提案\n\n不该出现。\n\n## 备选方案\n\n**某方案**：输在这里写足够长的理由说明它为什么被击败。\n\n## 后果\n\n略。\n",
        encoding="utf-8",
    )
    return "implemented 中残留提案期标题", root


def case_scene_empty_parent(root: Path) -> tuple[str, Path]:
    path = root / "empty_parent.tscn"
    path.write_text(
        '[gd_scene load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://core/component.gd" id="1"]\n\n'
        '[node name="Root" type="Node2D"]\n\n'
        '[node name="Child" type="Node" parent=""]\nscript = ExtResource("1")\n',
        encoding="utf-8",
    )
    return "节点 parent 为空字符串（会导致引擎段错误）", root


def case_scene_undeclared_parent(root: Path) -> tuple[str, Path]:
    path = root / "undeclared_parent.tscn"
    path.write_text(
        '[gd_scene load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://core/component.gd" id="1"]\n\n'
        '[node name="Root" type="Node2D"]\n\n'
        '[node name="Child" type="Node" parent="NoSuchNode"]\nscript = ExtResource("1")\n',
        encoding="utf-8",
    )
    return "节点 parent 指向未声明的节点", root


def case_level_root_script_name_mismatch(root: Path) -> tuple[str, Path]:
    directory = root / "levels"
    directory.mkdir(parents=True)
    (directory / "m3_flow.gd").write_text("extends Node2D\n", encoding="utf-8")
    path = directory / "arena.tscn"
    path.write_text(
        '[gd_scene load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://levels/m3_flow.gd" id="1_m3_flow"]\n\n'
        '[node name="Arena" type="Node2D"]\n'
        'script = ExtResource("1_m3_flow")\n',
        encoding="utf-8",
    )
    return "arena.tscn 根节点挂异名 m3_flow.gd", root


def case_skill_no_prefix(root: Path) -> tuple[str, Path]:
    directory = root / "some-skill"
    directory.mkdir(parents=True)
    (directory / "SKILL.md").write_text(
        '---\nname: some-skill\ndescription: "Use when nothing."\n---\n\n# some-skill\n',
        encoding="utf-8",
    )
    return "skill 目录名缺少域前缀", root


def case_skill_name_mismatch(root: Path) -> tuple[str, Path]:
    directory = root / "flow-renamed"
    directory.mkdir(parents=True)
    (directory / "SKILL.md").write_text(
        '---\nname: flow-old-name\ndescription: "Use when nothing."\n---\n\n# flow-renamed\n',
        encoding="utf-8",
    )
    return "skill frontmatter name 与目录名不一致", root


def case_skill_missing_description(root: Path) -> tuple[str, Path]:
    directory = root / "flow-nodesc"
    directory.mkdir(parents=True)
    (directory / "SKILL.md").write_text("---\nname: flow-nodesc\n---\n\n# flow-nodesc\n", encoding="utf-8")
    return "skill frontmatter 缺少 description", root


def case_mcp_unregistered(root: Path) -> tuple[str, Path]:
    directory = root / "some-mcp"
    directory.mkdir(parents=True)
    (directory / "LICENSE").write_text("MIT\n", encoding="utf-8")
    return "未登记的 MCP 集成目录", root


def case_mcp_missing_license(root: Path) -> tuple[str, Path]:
    directory = root / "blender-mcp" / "src" / "blender_mcp"
    directory.mkdir(parents=True)
    (directory / "server.py").write_text("@mcp.tool()\ndef noop():\n    pass\n" * 25, encoding="utf-8")
    return "vendored MCP 缺少 LICENSE", root


def case_agent_entry_missing(root: Path) -> tuple[str, Path]:
    (root / "skills").mkdir(parents=True)
    (root / "AGENTS.md").write_text("# AGENTS\n", encoding="utf-8")
    return "Agent 入口缺失（无 .claude/skills 等）", root


def case_agent_entry_plain_file(root: Path) -> tuple[str, Path]:
    (root / "skills").mkdir(parents=True)
    (root / "AGENTS.md").write_text("# AGENTS\n", encoding="utf-8")
    (root / "CLAUDE.md").symlink_to("AGENTS.md")
    (root / "CODEBUDDY.md").symlink_to("AGENTS.md")
    for entry in (".agents", ".claude", ".codex", ".codebuddy"):
        (root / entry).mkdir()
        (root / entry / "skills").symlink_to("../skills")
    # .workbuddy/skills 写成普通文件，模拟 Windows 未启用 symlink 的 clone 结果
    (root / ".workbuddy").mkdir()
    (root / ".workbuddy" / "skills").write_text("../skills", encoding="utf-8")
    return "Agent 入口是普通文件而非 symlink（Windows clone 假文件）", root


CASES = [
    ("verify_packages.py", case_package_domain_root_file),
    ("verify_packages.py", case_package_oversized_without_exception),
    ("verify_packages.py", case_package_exception_missing_note),
    ("verify_packages.py", case_package_exception_proposed_note),
    ("verify_capabilities.py", case_capability_missing_test),
    ("verify_capabilities.py", case_capability_cross_reference),
    ("verify_capabilities.py", case_capability_no_behavior),
    ("verify_capabilities.py", case_capability_no_class_name),
    ("verify_component_purity.py", case_component_decision),
    ("verify_component_purity.py", case_component_global_reference),
    ("verify_vocabulary.py", case_unregistered_vocabulary),
    ("verify_scenes.py", case_sheet_dangling),
    ("verify_scenes.py", case_sheet_empty),
    ("verify_scenes.py", case_scene_empty_parent),
    ("verify_scenes.py", case_scene_undeclared_parent),
    ("verify_scenes.py", case_level_root_script_name_mismatch),
    ("verify_skills.py", case_skill_no_prefix),
    ("verify_skills.py", case_skill_name_mismatch),
    ("verify_skills.py", case_skill_missing_description),
    ("verify_mcp.py", case_mcp_unregistered),
    ("verify_mcp.py", case_mcp_missing_license),
    ("verify_agent_entries.py", case_agent_entry_missing),
    ("verify_agent_entries.py", case_agent_entry_plain_file),
    ("verify_notes_format.py", case_note_missing_alternatives),
    ("verify_notes_format.py", case_note_status_mismatch),
    ("verify_notes_format.py", case_note_bad_filename),
    ("verify_notes_format.py", case_note_proposal_heading_in_implemented),
]


def main() -> int:
    failures: list[str] = []

    for script, builder in CASES:
        workspace = Path(tempfile.mkdtemp(prefix="gt_negctl_"))
        try:
            label, target = builder(workspace)
            code = run_gate(script, target)
            if code == 0:
                failures.append(f"{script} 未拒绝非法案例：{label}")
                print(f"FAIL {script:30s} 应拒绝但通过了：{label}")
            else:
                print(f"OK   {script:30s} 正确拒绝：{label}")
        finally:
            shutil.rmtree(workspace, ignore_errors=True)

    print()
    if failures:
        print(f"负向控制未通过（{len(failures)}/{len(CASES)}）：门禁存在假通过风险")
        return 1
    print(f"负向控制全部通过（{len(CASES)}/{len(CASES)}）：每条门禁都能拒绝对应非法案例")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
