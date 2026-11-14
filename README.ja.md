[English](README.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

# antigravity-android

**作者:** [KonAyame774](https://github.com/KonAyame774)  
**モジュール ID:** `antigravity-android` · **バージョン:** `v1.0` (`versionCode: 100`)

**KernelSU / KernelSU Next / Magisk / APatch** 向けの Root モジュールです。Android 起動時に `root` 権限で **Antigravity CLI Remote Control** (`agy remote-control`) を自動起動し、Termux 環境構築、固定ホスト名パッチ、`~/.gemini` の権限・SELinux リアルタイム同期、空スレッド／オフラインインスタンスの自動クリーンアップ、4言語 UI を統合します。

---

## 主な機能

- **Root `tmux` での起動時自動実行** (`service.sh`, `agy_boot_service.sh`)
  - `sys.boot_completed=1`、認証情報暗号化ストレージ（`sys.user.0.ce_available=true`）、およびネットワーク接続を確認した上で、`agy` という名前の root `tmux` セッション内で `agy remote-control` を起動します。
  - root ロックファイル（`$PREFIX/var/run/agy_root.lock`、`$PREFIX/var/run/agy_start.lock`）で二重起動を防止し、有効時は Termux 起動時にも状態を確認します。
- **固定デバイスホスト名** (`patch_agy_hostname.py`, `customize.sh`, `service.sh`)
  - Android システムプロパティ（`ro.product.marketname` / モデル名 / デバイス名）から固定ホスト名（`localhost-<device>`）を生成し、`~/.gemini/config/config.json` の `cliRemoteControlHostname` に保存します。
  - `aarch64` Go ELF（`agy` / `agy.va39`）を動的にパッチし、`--remote-control` 実行時にランダムなサフィックスではなく `userSettings.cliRemoteControlHostname` を参照させます。
- **Termux・glibc 環境の自動セットアップ** (`ensure_antigravity_env.sh`)
  - 必要な Termux パッケージ（`bash`、`python`、`tmux`、`curl`、`tar`、`util-linux`、`procps`、`coreutils`、`ca-certificates`、`resolv-conf`、`glibc-repo`、`glibc`、さらに `/proc/cpuinfo` に `atomics` がない場合は `qemu-user-aarch64`）を自動導入し、DNS/hosts 設定と [`wallentx/antigravity-cli-termux`](https://github.com/wallentx/antigravity-cli-termux) スタンドアロンバイナリの取得・更新を行います。
- **権限・SELinux リアルタイム同期と認証トークン監視** (`sync_gemini_perms.py`, `agy_boot_service.sh`)
  - Linux `inotify` とポーリング（`lgetxattr`/`lsetxattr`）で `~/.gemini` および `~/.config/antigravity` を常時監視し、`agy` を root 実行していても通常ユーザーの Termux から `config.json` やログ、トークン情報を読み書きできるようにします。
  - `.ls_csrf_token` などの機密ファイルの権限（`0600`）を保護し、OAuth トークンの変更や失効時にはサービスを自動リロードします。
- **空会話・オフラインインスタンスの自動削除** (`cleanup_empty_conversations.py`, `cleanup_offline_instances.py`)
  - 再起動時などに作られる内容ゼロの空会話を自動削除します（ローカル RPC `DeleteCascadeTrajectory` を優先し、オフライン時は SQLite / `jetbox_summaries_proto.pb` で処理）。ステップ／メッセージ、brain ファイル、タイトル注記、ロックがある会話は厳密に保護されます。
  - 起動前のオフライン削除、起動後のスタートアップ削除、1800 秒ごとの定期削除に加え、オフライン状態の古いリモートインスタンスも定期的に削除します。
- **音量キーによるインストール時切り替え・無人フラッシュ対応** (`customize.sh`)
  - インストール時に 15 秒間の音量キー入力プロンプトを表示します（`[音量 +]` で自動起動を有効化して今すぐ起動/再起動、`[音量 -]` で無効のまま維持、タイムアウト時は既存セッションを保持し未起動なら無効）。
  - 環境変数 `AGY_START_ON_FLASH=1|0|keep`（`1|y|yes|true`、`0|n|no|false`、`keep`）による非対話式インストールと、旧モジュール `antigravity_boot` の自動クリーンアップに対応します。
- **4言語ローカライズ** (`agy_i18n.sh`, `agy_py_i18n.py`)
  - **English (`en`)**、**繁體中文 (`zh-TW`)**、**简体中文 (`zh-CN`)**、**日本語 (`ja`)** に対応し、インストーラー、`module.prop` 説明文、ログ、ヘルパーコマンドを自動または手動で切り替えます。

---

## 動作要件

- Root 化済みの ARM64 (`aarch64`) Android 端末（**KernelSU** / **KernelSU Next** / **Magisk** / **APatch**）
- `/data/data/com.termux/files` にインストールされた **Termux**
- 初回のパッケージ／バイナリ構築、更新、リモートコントロール接続のためのインターネット接続

---

## インストール手順

1. **Termux** をインストールし、一度起動して初期セットアップを完了させます。
2. **Releases** から `antigravity-android-v1.0.zip` をダウンロードします（下記手順でソースから作成することも可能です）。
3. **KernelSU / KernelSU Next**、**Magisk**、または **APatch** で ZIP をフラッシュします。
4. フラッシュ中の画面案内に従い、音量キーで選択します：
   - **`音量 +`**：自動起動を有効化し、今すぐ `agy remote-control` を起動（または再起動）します。
   - **`音量 -`**：自動起動を無効のままにします（`~/.gemini/config/remote_control` を `0` に設定）。
   - *(スクリプト等からの無人実行)* 事前に `AGY_START_ON_FLASH=1`、`0`、`keep` を指定できます。
5. 新しい Termux セッションを開く（または `source ~/.bashrc` を実行する）と `agy-*` コマンドが読み込まれます。未ログインの場合は Termux 上で Antigravity CLI のログインを済ませてください。

---

## Termux ヘルパーコマンド

インストール時に `~/.bashrc` の `# >>> antigravity-remote-control >>>` ブロックへ追加されます：

| コマンド | 説明 |
| --- | --- |
| `agy-status` | サービスの稼働状況（`tmux` / PID）、自動起動設定、ホスト名、言語を表示 |
| `agy-start` | 自動起動を有効化し、`root` で `agy remote-control` を起動 |
| `agy-stop` | 稼働中のサービスを停止し、自動起動を無効化 |
| `agy-restart` | `root` の `agy remote-control` サービスをクリーンに再起動 |
| `agy-attach` | 稼働中の `root` `tmux` セッション（`agy`）へアタッチ |
| `agy-clean` | 古いオフラインインスタンスと空会話を手動で即時削除（`--min-age 0 --verbose`） |
| `agy-log` | 実行ログを表示（`~/.gemini/antigravity-cli/boot.log` および `/data/adb/agy_boot.log`） |
| `agy-lang [lang]` | 表示言語を変更（`en`、`zh-TW`、`zh-CN`、`ja`、または `auto` でシステム自動検出） |

---

## ログおよび設定ファイル

| パス | 用途 |
| --- | --- |
| `/data/adb/agy_boot.log` | Android 起動時スクリプト（`service.sh`）のログ |
| `~/.gemini/antigravity-cli/boot.log` | サービス実行、ホスト名パッチ、OAuth 監視、自動削除のログ |
| `~/.gemini/config/config.json` | `cliRemoteControlHostname`（`localhost-<device>`）を保存 |
| `~/.gemini/config/remote_control` | 自動起動トグル（`0` で起動時・Termux 起動時の自動実行を無効化） |
| `~/.gemini/config/lang` | 手動言語設定（`en`、`zh-TW`、`zh-CN`、`ja`） |
| `/data/adb/antigravity_lang` | root フェーズ参照用の言語設定ミラー |
| `~/.local/bin/` | `customize.sh` がサービス／クリーンアップスクリプトを配置するディレクトリ |

---

## リポジトリ構成とモジュール ZIP のビルド

```text
antigravity-android/
├── META-INF/com/google/android/
│   ├── update-binary
│   └── updater-script
├── files/
│   ├── agy_boot_service.sh           # Root tmux ランナー、認証監視、定期クリーンアップ
│   ├── agy_i18n.sh                   # Shell 用 4言語 i18n ヘルパー
│   ├── agy_py_i18n.py                # Python 用 4言語 i18n ヘルパー
│   ├── bashrc_block.sh               # Termux ~/.bashrc コマンド＆起動ガード
│   ├── cleanup_empty_conversations.py# 空会話 RPC + オフライン SQLite クリーナー
│   ├── cleanup_offline_instances.py  # オフラインリモートインスタンスクリーナー
│   ├── ensure_antigravity_env.sh     # Termux/glibc/DNS/バイナリ構築＆アップデーター
│   ├── patch_agy_hostname.py         # aarch64 Go ELF 動的ホスト名パッチャー
│   └── sync_gemini_perms.py          # inotify リアルタイム UID/GID & SELinux MCS 同期
├── customize.sh                      # インストーラー、ホスト名設定、音量キートグル
├── module.prop                       # モジュールメタデータ
├── service.sh                        # 起動時スクリプト（KernelSU/Magisk/APatch）
├── README.md
├── README.zh-TW.md
├── README.zh-CN.md
└── README.ja.md
```

ソースからフラッシュ可能なモジュール ZIP を作成するには：

```bash
zip -r antigravity-android-v1.0.zip META-INF customize.sh module.prop service.sh files -x '*/__pycache__/*' '*.pyc'
```

---

## 動作確認済み環境

以下の実機環境にて、モジュール導入・再起動テスト・自動クリーンアップの動作を確認しています：

- **端末:** Redmi Turbo 3 (`peridot`)
- **OS:** Xiaomi HyperOS 4（`OS4.0.5.0.XNPCNXM`、Android 17 / SDK 37）
- **カーネル:** `6.1.138-android14-Wild`（`aarch64`）
- **Root・シェル環境:** KernelSU（`ksud 3.4.2-100-ga6c81fa4`）+ Termux

---

## 免責事項

- 本モジュールは **`root` 権限** で動作し、Termux 関連の設定やディレクトリ（`~/.local/bin/`、`~/.bashrc`、`~/.gemini/`、`~/.config/antigravity/`）を変更するとともに、所有者・SELinux ラベルの同期および `aarch64` 版 Antigravity CLI バイナリ（`agy` / `agy.va39`）への動的パッチ適用を行います。
- [`wallentx/antigravity-cli-termux`](https://github.com/wallentx/antigravity-cli-termux) のバイナリ構成に依存しているため、今後の上流アップデートにより動作しなくなる場合があります。
- 本プロジェクトは **現状のまま（AS-IS）・無保証** で提供されます。Root モジュールのフラッシュ前に必ず重要なデータや認証情報をバックアップし、すべて自己責任でご利用ください。

---

## 利用規約およびデータの取り扱い

> [!WARNING]
> AI コーディングエージェントには、自律的なコード実行、データ流出、プロンプトインジェクション、サプライチェーンリスクなどのセキュリティリスクが存在することが知られています。特に本モジュールは **`root`** 権限で Antigravity CLI Remote Control を実行するため、必ずエージェントが行うすべての操作を監視・確認してください。

Antigravity CLI を使用することで、Google 利用規約および Google プライバシーポリシーに従い、製品改善のために Google がお客様のインタラクションデータ（Interactions data）を収集・利用することに同意したものとみなされます。設定からいつでもオプトアウト（無効化）できます。

### 規約・プライバシー関連リンク

- **利用規約（Terms of Service）：** [antigravity.google/terms](https://antigravity.google/terms)
- **プライバシーポリシー（Privacy Policy）：** [policies.google.com/privacy](https://policies.google.com/privacy)

---

## 開発について・クレジット

- **開発手法:** 本プロジェクトは **Antigravity CLI** 上で AI 支援開発（**Vibe Coding**）により作成され、使用モデルは **Gemini 4 Hydrogen** および **Gemini 3.8 Flash** です。その上で上記の実機端末・OS 環境にて検証およびデバッグを行っています。
- **上流バイナリ:** [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux)
- **モジュール作者:** [KonAyame774](https://github.com/KonAyame774)
