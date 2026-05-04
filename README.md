# hazkey-aarch64

Arch Linux ARM (aarch64) で、日本語ライブ変換に対応した fcitx5-hazkey をビルド・インストールするためのスクリプトです。Parallels Desktop で Arch Linux ARM を動かす構成に適しています。


## 前提構成

- Arch Linux ARM (aarch64) host、fcitx5 5.x が動作中
- `podman` / `distrobox` / `slirp4netns` / `fuse-overlayfs`
- ユーザー `$PATH` に `~/.local/bin` が含まれる

未導入の場合:

```bash
sudo pacman -S --needed podman distrobox slirp4netns fuse-overlayfs
podman info # rootless が動くこと
```


## 導入手順

### 1. インストール

- `install.sh` はユーザー権限で実行可能
- 実際の `install` 段階でのみ内部で `sudo` を実行

```bash
# container 作成 → build → install → wrapper 設置
./install.sh

# container 作成 → build 
./install.sh --build-only

# ヘルプ
./install.sh -h
```


### 2. fcitx5 設定

- 再起動を行い新規アドオンを認識させる

```bash
pkill -x fcitx5; fcitx5 -d & disown

# GUI で hazkey を有効化する
fcitx5-configtool
```

- 設定は `~/.config/fcitx5/profile` を直接編集も可能


## 設定

ビルドと配備の挙動は `config.kdl` で制御します。

| key | 既定値 | 内容 |
|---|---|---|
| `container` | `"hazkey-build"` | distrobox container 名 |
| `image` | `"docker.io/library/ubuntu:24.04"` | container base image |
| `swift-url` | Swift 6.2 ubuntu24.04-aarch64 tarball URL | Swift toolchain ダウンロード元 |
| `cmake-version` | `"4.1.0"` | Kitware からダウンロードする CMake バージョン |
| `protobuf-tag` | `"v21.12"` | 静的リンク用 protobuf の git tag |
| `hazkey-ref` | `"0.2.1"` | upstream `7ka-Hiira/hazkey` の checkout ref |
| `vulkan` | `#false` | Zenzai Vulkan backend 有効化 |
| `static-protobuf` | `#true` | protobuf を静的リンク |
| `prefix` | `"/usr"` | host 配備先 prefix |
| `manifest` | `"/var/lib/hazkey-aarch64/installed-files.txt"` | uninstall 用 manifest 配置先 |
| `configtool-wrapper` | `"~/.local/bin/fcitx5-configtool"` | wrapper 配置先 |

## 実行構成

```
fcitx5 daemon
 └─ /usr/lib/fcitx5/fcitx5-hazkey.so            ... C++ addon
     └─ /usr/bin/hazkey-server                  ... sh wrapper
         └─ /usr/lib/hazkey/hazkey-server
             ├─ /usr/lib/hazkey/libllama/       ... llama.cpp 共有ライブラリ群
             └─ /usr/share/hazkey/Dictionary/   ... azooKey 辞書

GUI:
 └─ /usr/bin/hazkey-settings → /usr/lib/hazkey/hazkey-settings  ... Qt6 設定 UI
```

- Swift toolchain は upstream CI と同じ `swift-6.2-RELEASE-ubuntu24.04-aarch64`
- CMake は 4.1.x を使用 (Qt6 autogen が generated header を解決可能)

## アンインストール

- `config.kdl` の `manifest` で指す経路を辿って配置物を消します。

```bash
./uninstall.sh

# configtool wrapper も合わせて削除する
rm ~/.local/bin/fcitx5-configtool
```


## リポジトリ構成

```
├── README.md
├── install.sh
├── uninstall.sh
├── config.kdl
├── build/          ビルド成果の出力先 (.gitignore)
└── lib/
    ├── common.sh   KDL parser + load_config
    ├── build.sh    コンテナ内 build pipeline
    └── host.sh     container / install / wrapper / uninstall
```


## 既知事項

host の `fcitx5-qt` 5.1.12 が `fcitx5` daemon 5.1.17 の `UpdateClientSideUI` を受けた瞬間に SIGBUS を起こす host 側のバグがあります。`install.sh` が設置する `~/.local/bin/fcitx5-configtool` wrapper は `QT_IM_MODULE=` 経由で Qt 入力 plugin を bypass する作りで、configtool 自体は立ち上がるようになります。


## ライセンス

- 本スクリプト群は [Unlicense](https://unlicense.org/) です。(public domain dedication)
- 配布物で利用するコンポーネントについては upstream の指定に従ってください。

- MIT:
    - 本体 (`7ka-Hiira/hazkey`)
    - 変換エンジン (`azooKey/AzooKeyKanaKanjiConverter`)
    - llama.cpp fork (`7ka-hiira/llama.cpp`)

- Apache-2.0:
    - 辞書 (`azooKey/azooKey_dictionary_storage`)
