#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT="$(dirname "$LIB_DIR")"
. "$LIB_DIR/common.sh"
load_config

SWIFT_DIR="$BUILD_DIR/swift"
LOCAL_DEPS="$BUILD_DIR/local_deps"
CMAKE_DIR="$BUILD_DIR/cmake"
HAZKEY_SRC="$BUILD_DIR/hazkey"
STAGE="$BUILD_DIR/stage"
PACKAGES="$BUILD_DIR/packages"
mkdir -p "$BUILD_DIR" "$LOCAL_DEPS" "$STAGE" "$PACKAGES"

echo "=== apt deps ==="
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    wget gnupg2 ca-certificates git file \
    build-essential gettext fakeroot \
    libfcitx5core-dev libfcitx5config-dev libfcitx5utils-dev \
    cmake ninja-build \
    qt6-base-dev qt6-tools-dev qt6-tools-dev-tools \
    libqt6widgets6 libqt6gui6 qt6-l10n-tools \
    libglx-dev libgl1-mesa-dev libxkbcommon-dev

echo "=== CMake $CMAKE_VER ==="
if [ ! -x "$CMAKE_DIR/bin/cmake" ]; then
    mkdir -p "$CMAKE_DIR"
    cmake_tgz="cmake-${CMAKE_VER}-linux-aarch64.tar.gz"
    (cd "$BUILD_DIR" && wget -nc "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/${cmake_tgz}")
    tar xf "$BUILD_DIR/${cmake_tgz}" --strip-components=1 -C "$CMAKE_DIR"
fi
export PATH="$CMAKE_DIR/bin:$PATH"
cmake --version | head -1

echo "=== Swift toolchain ==="
if [ ! -x "$SWIFT_DIR/usr/bin/swift" ]; then
    mkdir -p "$SWIFT_DIR"
    swift_tgz="$(basename "$SWIFT_URL")"
    (cd "$BUILD_DIR" && wget -nc "$SWIFT_URL")
    tar xf "$BUILD_DIR/$swift_tgz" --strip-components=1 -C "$SWIFT_DIR"
fi
export PATH="$SWIFT_DIR/usr/bin:$LOCAL_DEPS/bin:$PATH"
swift --version | head -2

if [ "$STATIC_PROTOBUF" = yes ]; then
    echo "=== protobuf $PROTOBUF_TAG (static) ==="
    if [ ! -x "$LOCAL_DEPS/bin/protoc" ]; then
        (
            cd "$BUILD_DIR"
            if [ ! -d protobuf ]; then
                git clone --branch "$PROTOBUF_TAG" --depth 1 https://github.com/protocolbuffers/protobuf.git
            fi
            cd protobuf && mkdir -p build && cd build
            cmake .. \
                -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_SHARED_LIBS=OFF \
                -Dprotobuf_BUILD_TESTS=OFF \
                -DCMAKE_CXX_FLAGS="-fPIC" \
                -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
                -DCMAKE_INSTALL_PREFIX="$LOCAL_DEPS"
            make -j"$(nproc)"
            make install
        )
    fi
else
    sudo apt-get install -y protobuf-compiler libprotoc-dev
fi

echo "=== upstream clone (ref=$HAZKEY_REF) ==="
if [ ! -d "$HAZKEY_SRC/.git" ]; then
    git clone https://github.com/7ka-Hiira/hazkey.git "$HAZKEY_SRC"
fi
git -C "$HAZKEY_SRC" fetch --tags --force
git -C "$HAZKEY_SRC" checkout "$HAZKEY_REF"
git -C "$HAZKEY_SRC" submodule update --init --recursive

# Qt 6.6+ 互換のための upstream UI ファイル微修正(CI と同じ sed)
sed -i "s/Qt::Orientation::/Qt::/g" "$HAZKEY_SRC/hazkey-settings/mainwindow.ui"

PROTO_STATIC_FLAG="OFF"
[ "$STATIC_PROTOBUF" = yes ] && PROTO_STATIC_FLAG="ON"

VULKAN_FLAG="OFF"
[ "$VULKAN_ENABLED" = yes ] && VULKAN_FLAG="ON"

echo "=== build hazkey-settings ==="
(
    cd "$HAZKEY_SRC/hazkey-settings"
    rm -rf build && mkdir build && cd build
    cmake -G Ninja .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_CXX_FLAGS="-I$LOCAL_DEPS/include" \
        -DCMAKE_PREFIX_PATH="$LOCAL_DEPS" \
        -DProtobuf_USE_STATIC_LIBS="$PROTO_STATIC_FLAG"
    ninja -j"$(nproc)"
    env DESTDIR="$STAGE" ninja install
)

echo "=== build fcitx5-hazkey (C++ addon) ==="
(
    cd "$HAZKEY_SRC/fcitx5-hazkey"
    rm -rf build && mkdir build && cd build
    cmake -G Ninja .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$LOCAL_DEPS" \
        -DProtobuf_USE_STATIC_LIBS="$PROTO_STATIC_FLAG"
    ninja -j"$(nproc)"
    env DESTDIR="$STAGE" ninja install
)

echo "=== build hazkey-server (Swift, Vulkan=$VULKAN_FLAG) ==="
(
    cd "$HAZKEY_SRC/hazkey-server"
    rm -rf build && mkdir build && cd build
    cmake -G Ninja .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DHAZKEY_SERVER_SWIFT_LTO_MODE=full \
        -DGGML_VULKAN="$VULKAN_FLAG"
    ninja -j"$(nproc)"
    env DESTDIR="$STAGE" ninja install
)

echo "=== strip ==="
find "$STAGE/" -type f -print0 \
    | xargs -0 file -i \
    | grep -E "application/(x-pie-executable|x-sharedlib)" \
    | cut -d: -f1 \
    | xargs -I{} strip "{}" 2>/dev/null || true

echo "=== package tarball ==="
TAG="$(git -C "$HAZKEY_SRC" describe --tags --abbrev=0 2>/dev/null || echo dev)"
TGZ="$PACKAGES/fcitx5-hazkey-${TAG}-aarch64.tar.gz"
tar -czf "$TGZ" -C "$STAGE" .
echo "[OK] artifact: $TGZ"
