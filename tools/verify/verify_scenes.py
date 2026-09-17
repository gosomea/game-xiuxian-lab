#!/usr/bin/env python3
"""verify-scenes：场景文件门禁（Tier 0）。

覆盖全仓 .tscn（不只 src/sheets/）。存在理由：手写/生成的场景文件若节点路径非法，
Godot 资源解析器会直接段错误崩溃，且无任何编译期提示——这类错误必须在提交前拦下。
（见 notes/implemented/tech/2026-08-28-scene-gate.md）

检查：
1. ext_resource 引用的路径存在（悬空引用）；
2. 节点的 parent 路径合法：不得为空字符串；引用的父节点必须已在本文件中声明；
3. Sheet 额外要求：至少含一个脚本节点、嵌套无环；
4. `src/levels/` 的正式关卡场景若根节点挂脚本，脚本 basename 必须与场景同名。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import GODOT_PROJECT, REPO_ROOT, Failure, report  # noqa: E402

EXT_RESOURCE = re.compile(r'\[ext_resource\s+type="([^"]+)"[^\]]*path="res://([^"]+)"[^\]]*id="([^"]+)"')
NODE_TAG = re.compile(r'\[node\s+name="([^"]+)"(?:\s+type="[^"]*")?(?:\s+parent="([^"]*)")?')
SCRIPT_ASSIGNMENT = re.compile(r'^script\s*=\s*(ExtResource|SubResource)\("([^"]+)"\)', re.MULTILINE)
DOC = "notes/implemented/tech/2026-08-28-scene-gate.md"

# Sheet 按文件名后缀识别，不按所在目录——使 Sheet 可与其功能同处一包
# （依据 notes/implemented/tech/2026-08-28-src-feature-packaging.md）
SHEET_SUFFIX = "_sheet.tscn"


def is_sheet(path: Path) -> bool:
    return path.name.endswith(SHEET_SUFFIX)


def res_path(relative: str, project_root: Path = GODOT_PROJECT) -> Path:
    """res:// 等价于 Godot 工程根（src/），不是仓库根。"""
    return project_root / relative


def check_scene(path: Path, project_root: Path = GODOT_PROJECT) -> tuple[list[Failure], list[Path], bool]:
    """返回 (失败列表, 引用的其他场景, 是否含脚本节点)。"""
    failures: list[Failure] = []
    text = path.read_text(encoding="utf-8")
    referenced_scenes: list[Path] = []
    has_script = False

    for res_type, relative, _resource_id in EXT_RESOURCE.findall(text):
        target = res_path(relative, project_root)
        if not target.exists():
            failures.append(
                Failure(
                    path,
                    f"悬空引用：res://{relative} 不存在",
                    fix="修正 ext_resource 的 path，或恢复被删除/移动的文件",
                )
            )
            continue
        if res_type == "Script":
            has_script = True
        if target.suffix == ".tscn":
            referenced_scenes.append(target)

    declared: set[str] = set()
    is_first = True
    for match in NODE_TAG.finditer(text):
        name, parent = match.group(1), match.group(2)
        line = text.count("\n", 0, match.start()) + 1

        if is_first:
            if parent is not None:
                failures.append(
                    Failure(path, f"根节点「{name}」不应带 parent 属性", line, fix="删除根节点的 parent=... ")
                )
            declared.add(".")
            declared.add(name)
            is_first = False
            continue

        if parent is None:
            failures.append(
                Failure(path, f"非根节点「{name}」缺少 parent 属性", line, fix='添加 parent="." 或具体父节点路径')
            )
            continue

        if parent == "":
            failures.append(
                Failure(
                    path,
                    f"节点「{name}」的 parent 为空字符串（Godot 资源解析器会因此段错误崩溃）",
                    line,
                    fix='改为 parent="."（挂在根节点下）',
                )
            )
            continue

        if parent != "." and parent not in declared:
            failures.append(
                Failure(
                    path,
                    f"节点「{name}」的 parent 路径「{parent}」未在本文件中声明",
                    line,
                    fix="父节点必须先声明；检查路径拼写与节点顺序",
                )
            )

        full = name if parent == "." else f"{parent}/{name}"
        declared.add(full)

    return failures, referenced_scenes, has_script


def root_script(path: Path) -> tuple[str | None, bool]:
    """返回根脚本的 res:// 相对路径；第二项表示根是否挂了内嵌 SubResource 脚本。"""
    text = path.read_text(encoding="utf-8")
    nodes = list(NODE_TAG.finditer(text))
    if not nodes:
        return None, False
    root_body_end = nodes[1].start() if len(nodes) > 1 else len(text)
    root_body = text[nodes[0].end():root_body_end]
    assignment = SCRIPT_ASSIGNMENT.search(root_body)
    if assignment is None:
        return None, False
    kind, resource_id = assignment.groups()
    if kind == "SubResource":
        return None, True
    for res_type, relative, candidate_id in EXT_RESOURCE.findall(text):
        if candidate_id == resource_id and res_type == "Script":
            return relative, False
    return None, False


def is_formal_level_scene(path: Path, scan_root: Path) -> bool:
    if is_sheet(path) or path.name.startswith("test_") or "tests" in path.parts:
        return False
    try:
        relative = path.relative_to(scan_root)
    except ValueError:
        return False
    if scan_root.resolve() == GODOT_PROJECT.resolve():
        return len(relative.parts) > 1 and relative.parts[0] == "levels"
    if scan_root.name == "levels":
        return True
    return len(relative.parts) > 1 and relative.parts[0] == "levels"


def detect_cycle(graph: dict[Path, list[Path]]) -> list[Path] | None:
    WHITE, GREY, BLACK = 0, 1, 2
    color: dict[Path, int] = {node: WHITE for node in graph}
    stack: list[Path] = []

    def visit(node: Path) -> list[Path] | None:
        color[node] = GREY
        stack.append(node)
        for peer in graph.get(node, []):
            if color.get(peer, WHITE) == GREY:
                return stack[stack.index(peer):] + [peer]
            if color.get(peer, WHITE) == WHITE:
                found = visit(peer)
                if found:
                    return found
        stack.pop()
        color[node] = BLACK
        return None

    for node in list(graph):
        if color[node] == WHITE:
            found = visit(node)
            if found:
                return found
    return None


def main(argv: list[str]) -> int:
    root = GODOT_PROJECT if len(argv) <= 1 else Path(argv[1])

    scenes = sorted(p for p in root.rglob("*.tscn") if ".godot" not in p.parts)
    if not scenes:
        return report("verify-scenes", [], 0)

    failures: list[Failure] = []
    graph: dict[Path, list[Path]] = {}

    for scene in scenes:
        scene_failures, referenced, has_script = check_scene(scene, root)
        failures.extend(scene_failures)
        graph[scene] = referenced

        if is_sheet(scene) and not has_script:
            failures.append(
                Failure(
                    scene,
                    "Sheet 未引用任何脚本节点（空 Sheet 无意义）",
                    fix="加入至少一个 Capability 或 Component 节点；纯数值修饰请用 Component 字段而不是建 Sheet",
                )
            )

        if is_formal_level_scene(scene, root):
            script_path, embedded = root_script(scene)
            if embedded:
                failures.append(
                    Failure(
                        scene,
                        "正式关卡场景的根控制脚本不能是内嵌 SubResource，无法验证同名归属",
                        fix=f"将根脚本保存为 res://levels/{scene.stem}.gd，并挂回场景根节点",
                    )
                )
            elif script_path is not None and Path(script_path).stem != scene.stem:
                failures.append(
                    Failure(
                        scene,
                        f"根控制脚本 {Path(script_path).name} 与场景 {scene.name} 不同名",
                        fix=f"将根控制脚本重命名为 {scene.stem}.gd（优先用 Godot 编辑器移动），或把异名脚本移到真正所属的可复用子场景",
                    )
                )

    cycle = detect_cycle(graph)
    if cycle:
        chain = " -> ".join(p.name for p in cycle)
        failures.append(
            Failure(cycle[0], f"场景嵌套存在环：{chain}", fix="打断循环引用；场景嵌套必须是有向无环的")
        )

    return report("verify-scenes", failures, len(scenes), DOC)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
