#!/usr/bin/env bash
# uninstall.sh — manifest を辿って host から fcitx5-hazkey の配置物を削除する。
#   ./uninstall.sh             # 削除実行
#   ./uninstall.sh -h          # このヘルプ
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/host.sh"

for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

load_config
phase_uninstall
