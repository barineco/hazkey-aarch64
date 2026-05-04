CONFIG="${ROOT}/config.kdl"

# flat KDL の文字列値を抽出。`key "value"` 形式のみ対応。
kdl_string() {
    local key="$1"
    grep -E "^${key}([[:space:]]+|$)" "$CONFIG" | head -1 | sed -E 's/^[^"]*"([^"]*)".*/\1/'
}

# flat KDL の boolean 値を抽出。`key #true` / `key #false` のみ対応。
kdl_bool() {
    local key="$1" v
    v="$(grep -E "^${key}([[:space:]]+|$)" "$CONFIG" | head -1 | grep -oE '#(true|false)' | head -1 | tr -d '#')"
    [ "$v" = "true" ]
}

load_config() {
    [ -f "$CONFIG" ] || { echo "ERROR: $CONFIG が見つからない" >&2; exit 1; }

    CONTAINER="$(kdl_string container)"
    IMAGE="$(kdl_string image)"
    SWIFT_URL="$(kdl_string swift-url)"
    CMAKE_VER="$(kdl_string cmake-version)"
    PROTOBUF_TAG="$(kdl_string protobuf-tag)"
    HAZKEY_REF="$(kdl_string hazkey-ref)"
    PREFIX="$(kdl_string prefix)"
    MANIFEST="$(kdl_string manifest)"
    CONFIGTOOL_WRAPPER="$(kdl_string configtool-wrapper)"
    CONFIGTOOL_WRAPPER="${CONFIGTOOL_WRAPPER/#\~/$HOME}"

    VULKAN_ENABLED="no"
    kdl_bool vulkan && VULKAN_ENABLED="yes"

    STATIC_PROTOBUF="no"
    kdl_bool static-protobuf && STATIC_PROTOBUF="yes"

    BUILD_DIR="${ROOT}/build"

    : "${CONTAINER:?config に container が無い}" \
      "${IMAGE:?config に image が無い}" \
      "${SWIFT_URL:?config に swift-url が無い}" \
      "${HAZKEY_REF:?config に hazkey-ref が無い}" \
      "${PREFIX:?config に prefix が無い}" \
      "${MANIFEST:?config に manifest が無い}"
}
