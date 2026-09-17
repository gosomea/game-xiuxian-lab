#!/bin/bash
set -euo pipefail

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAB_GODOT="${GODOT:-}"
if [[ -z "$LAB_GODOT" ]]; then
  if [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
    LAB_GODOT=/Applications/Godot.app/Contents/MacOS/Godot
  elif command -v godot >/dev/null 2>&1; then
    LAB_GODOT="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then
    LAB_GODOT="$(command -v godot4)"
  else
    echo '未找到 Godot 4.6。请安装 Godot，或设置 GODOT 为可执行文件路径。' >&2
    exit 1
  fi
fi

case "${1:-}" in
  --editor)
    shift
    exec "$LAB_GODOT" --editor --path "$LAB_ROOT/src" "$@"
    ;;
  --stage)
    shift
    "$LAB_GODOT" --headless --path "$LAB_ROOT/src" --import
    exec "$LAB_GODOT" --path "$LAB_ROOT/src" res://levels/empty_stage.tscn "$@"
    ;;
  --help|-h)
    echo '用法：./run.command [--editor | --stage] [Godot 参数]'
    exit 0
    ;;
  *)
    "$LAB_GODOT" --headless --path "$LAB_ROOT/src" --import
    exec "$LAB_GODOT" --path "$LAB_ROOT/src" "$@"
    ;;
esac
