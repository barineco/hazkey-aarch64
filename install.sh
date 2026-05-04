#!/usr/bin/env bash

# fcitx5-hazkey を Arch Linux ARM (aarch64) host にビルド・配備する。
#   ./install.sh                # container 作成 → build → host install → wrapper
#   ./install.sh --build-only   # container 作成 → build
#   ./install.sh -h             # ヘルプ

set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/host.sh"

mode="install"
for arg in "$@"; do
    case "$arg" in
        --build-only) mode="build" ;;
        -h|--help) sed -n '3,6p' "$0"; exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

load_config

phase_setup_container

echo "=== build (in container '$CONTAINER') ==="
distrobox-enter "$CONTAINER" -- bash "$ROOT/lib/build.sh"

if [ "$mode" = "build" ]; then
    echo "[OK] build complete (host 配備は --build-only により skip)"
    exit 0
fi

phase_install_host
phase_install_wrapper

echo "[OK] install complete."
