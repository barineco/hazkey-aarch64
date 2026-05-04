#!/usr/bin/env bash

# fcitx5-hazkey を Arch Linux ARM (aarch64) host にビルド・配備する。
#   ./install.sh                  # container 作成 → build → host install → wrapper
#   ./install.sh --build-only     # container 作成 → build
#   ./install.sh --clean-after    # install 完了後に build/ を削除(再生成可能な一時成果物)
#   ./install.sh --clean          # build/ のみ削除(install 工程は実行しない)
#   ./install.sh -h               # ヘルプ

set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/host.sh"

mode="install"
clean_after=0
for arg in "$@"; do
    case "$arg" in
        --build-only) mode="build" ;;
        --clean-after) clean_after=1 ;;
        --clean) mode="clean" ;;
        -h|--help) sed -n '3,8p' "$0"; exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

if [ "$mode" = "clean" ]; then
    echo "=== cleanup build/ (--clean) ==="
    rm -rf "$ROOT/build"
    echo "[OK] build/ removed."
    exit 0
fi

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

if [ "$clean_after" = 1 ]; then
    echo "=== cleanup build/ (--clean-after) ==="
    rm -rf "$ROOT/build"
    echo "[OK] build/ removed."
fi

echo "[OK] install complete."
