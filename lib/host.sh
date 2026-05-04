phase_setup_container() {
    if distrobox list 2>/dev/null | awk -F'|' 'NR>1{gsub(/ /,"",$2); print $2}' | grep -qx "$CONTAINER"; then
        echo "[OK] container '$CONTAINER' 既存"
        return 0
    fi
    distrobox-create --name "$CONTAINER" --image "$IMAGE" --yes
    echo "[OK] container '$CONTAINER' を作成"
}

phase_install_host() {
    local tgz
    tgz="$(ls -t "$BUILD_DIR/packages/"fcitx5-hazkey-*-aarch64.tar.gz 2>/dev/null | head -1 || true)"
    [ -n "$tgz" ] && [ -f "$tgz" ] || {
        echo "ERROR: build artifact 未生成。$BUILD_DIR/packages/ を確認" >&2
        exit 1
    }

    local tmp
    tmp="$(mktemp -d -t hazkey-stage.XXXXXX)"
    trap "rm -rf '$tmp'" EXIT

    echo "=== extract & inspect ($(basename "$tgz")) ==="
    tar -xzf "$tgz" -C "$tmp"

    # debian style multiarch lib dir をフラット化
    local triplet="" t
    for t in aarch64-linux-gnu x86_64-linux-gnu arm-linux-gnueabihf; do
        if [ -d "$tmp/usr/lib/$t" ]; then triplet="$t"; break; fi
    done
    if [ -n "$triplet" ]; then
        echo "    flatten /usr/lib/$triplet -> /usr/lib"
        cp -a "$tmp/usr/lib/$triplet/." "$tmp/usr/lib/"
        rm -rf "$tmp/usr/lib/$triplet"
        # wrapper script の triplet path を strip
        if [ -f "$tmp/usr/bin/hazkey-server" ]; then
            sed -i "s|/usr/lib/$triplet/|/usr/lib/|g" "$tmp/usr/bin/hazkey-server"
        fi
    fi

    # llama.cpp backend dir を wrapper に export
    if [ -f "$tmp/usr/bin/hazkey-server" ] && ! grep -q GGML_BACKEND_DIR "$tmp/usr/bin/hazkey-server"; then
        sed -i '/# hazkey-server wrapper script/r /dev/stdin' "$tmp/usr/bin/hazkey-server" <<'EOF'

if [ -z "${GGML_BACKEND_DIR}" ] ; then
    export GGML_BACKEND_DIR=/usr/lib/hazkey/libllama/backends/
fi
EOF
    fi

    # /usr/bin/hazkey-settings を flatten 後の path に再 link(upstream は multiarch path を指す)
    if [ -e "$tmp/usr/lib/hazkey/hazkey-settings" ]; then
        rm -f "$tmp/usr/bin/hazkey-settings"
        ln -s /usr/lib/hazkey/hazkey-settings "$tmp/usr/bin/hazkey-settings"
    fi

    echo "=== sudo install ==="
    sudo -v
    sudo mkdir -p "$(dirname "$MANIFEST")"
    (cd "$tmp" && find usr -mindepth 1 \( -type f -o -type l \)) | sort | sudo tee "$MANIFEST" >/dev/null
    sudo cp -a "$tmp/usr/." "$PREFIX/"

    if pgrep -x fcitx5 >/dev/null 2>&1; then
        pkill -HUP fcitx5 || true
    fi

    echo "[OK] installed to $PREFIX/. manifest: $MANIFEST"
}

phase_install_wrapper() {
    mkdir -p "$(dirname "$CONFIGTOOL_WRAPPER")"
    cat > "$CONFIGTOOL_WRAPPER" <<'EOF'
#!/usr/bin/env sh
exec env QT_IM_MODULE= /usr/bin/fcitx5-configtool "$@"
EOF
    chmod +x "$CONFIGTOOL_WRAPPER"
    echo "[OK] wrapper: $CONFIGTOOL_WRAPPER"
}

phase_uninstall() {
    [ -f "$MANIFEST" ] || { echo "ERROR: manifest $MANIFEST が見つからない" >&2; exit 1; }

    echo "=== remove tracked files ==="
    sudo bash -s "$PREFIX" "$MANIFEST" <<'EOS'
prefix="$1"; manifest="$2"
removed=0
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    target="$prefix/${rel#usr/}"
    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -f "$target"
        removed=$((removed + 1))
    fi
done < "$manifest"
echo "    removed $removed entries"
EOS

    sudo find "$PREFIX/lib/hazkey" -depth -type d -empty -delete 2>/dev/null || true
    sudo find "$PREFIX/share/hazkey" -depth -type d -empty -delete 2>/dev/null || true
    sudo rm -f "$MANIFEST"
    sudo rmdir "$(dirname "$MANIFEST")" 2>/dev/null || true

    if pgrep -x fcitx5 >/dev/null 2>&1; then
        pkill -HUP fcitx5 || true
    fi

    echo "[OK] uninstalled."
    [ -f "$CONFIGTOOL_WRAPPER" ] && echo "    note: wrapper 残存中($CONFIGTOOL_WRAPPER)。撤去するなら 'rm $CONFIGTOOL_WRAPPER'"
}
