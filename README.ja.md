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

## 初心者向け完全ガイド（最初から手順解説）

Android で初めて Antigravity CLI Remote Control をセットアップする場合は、以下の手順通りに進めてください：

### ステップ 1：Root 権限と Termux の準備
1. 端末が ARM64 (`aarch64`) であり、**KernelSU** / **KernelSU Next** / **Magisk** / **APatch** で Root 化されていることを確認します。
2. [GitHub Releases (`termux/termux-app`)](https://github.com/termux/termux-app/releases) または **F-Droid** から **Termux** をインストールします *（Google Play 版は古いため非推奨です）*。
3. インストール後、**Termux** を一度起動して `$` プロンプトが表示されるまで待ち、初期セットアップを完了させます。
4. **Root 管理アプリで Termux に Root 権限を付与** します *（KernelSU / APatch の場合は「スーパーユーザー」タブで Termux を有効化、Magisk の場合は `su` 許可ダイアログを承認）*。
5. 初回パッケージおよびバイナリの取得のため、端末をインターネットに接続した状態にしておきます。

### ステップ 2：モジュールのダウンロードとフラッシュ
1. 本リポジトリの [**Releases**](https://github.com/KonAyame774/antigravity-android/releases) ページから **`antigravity-android-v1.0.zip`** をダウンロードします。
2. **KernelSU / KernelSU Next**、**Magisk**、または **APatch** を開き、「**モジュール**」→「**インストール**」からダウンロードした ZIP を選択します。
3. インストーラーが Termux パッケージ（`bash`、`python`、`tmux`、`glibc` など）、DNS/hosts 設定、および Antigravity CLI スタンドアロンバイナリを自動導入するまで待ちます。
4. フラッシュ中に音量キーの選択プロンプトが表示されたら（**15 秒以内**）、音量ボタンで選択します：
   - **初心者におすすめ — `音量 +` を押す**：自動起動を有効化し、すぐに `agy remote-control` を起動します。
   - **`音量 -` を押す**：自動起動を無効のまま導入します（`~/.gemini/config/remote_control` が `0` に設定され、あとから `agy-start` でいつでも起動可能）。
   - *(スクリプト等からの無人実行)* 事前に `AGY_START_ON_FLASH=1`、`0`、`keep` を指定できます。
5. フラッシュ完了時のメッセージを確認します：
   - 起動時自動実行を確認したい場合や再起動が推奨された場合は「**再起動**」します。
   - すでに起動完了（またはログイン待機状態）と表示されている場合は、再起動せずそのままステップ 3 へ進めます。

### ステップ 3：Google アカウントでログイン（初回のみ必須）
1. 一度 **Termux を完全に終了して開き直す**（または `source ~/.bashrc` を実行する）ことで、`agy-*` 管理コマンドを読み込みます。
2. Termux で次を実行します：
   ```bash
   agy
   ```
3. 画面の案内に従い、ブラウザで Google アカウントにログインして Termux に戻ります。
4. **手動で `agy remote-control` を実行する必要はありません**：
   - 認証トークン（`~/.gemini/antigravity-cli/antigravity-oauth-token`）が保存されると、バックグラウンドサービスが数秒以内に自動検知してオンライン化します。
   - ステップ 2 で `音量 -` を選んだ場合は、ログイン完了後に `agy-start` を 1 回実行してください。

### ステップ 4：接続状態の確認と Web からの接続
1. Termux で次を実行します：
   ```bash
   agy-status
   ```
   プロセスが稼働中で `Connection status:` の接続状態および固定ホスト名（例：`localhost-<device>`）が表示されることを確認します。
2. スマホ・PC・タブレットのブラウザで **[https://antigravity.google.com](https://antigravity.google.com)** を開き、**同じ Google アカウント** でログインします。
3. 左上の端末セレクタから **`localhost-<device>`** を選ぶと、リモート操作を開始できます。

### ステップ 5：日常の使い方とトラブルシューティング
- **実行中のコンソール確認（`agy-attach`）**：`agy-attach` で稼働中の `tmux` 画面を確認できます。サービスを止めずに抜けるときは **`Ctrl+B` のあと `D`** を押してください *（`Ctrl+C` はプロセス終了になるため押さないでください）*。
- **手動での起動／停止／再起動**：
  - `agy-start`：サービスを起動し自動起動を有効化
  - `agy-stop`：サービスを停止し自動起動を無効化
  - `agy-restart`：バックグラウンドサービスを再起動
- **表示言語の切り替え**：`agy-lang ja`（`en`、`zh-TW`、`zh-CN`、`ja`、`auto` が利用可能）。
- **よくあるつまずきポイント**：
  - **`agy-status: command not found` と出る**：Termux を開き直すか `source ~/.bashrc` を実行してください。
  - **`su` 権限エラー（Permission denied）**：KernelSU / Magisk / APatch 側で **Termux** に Root 権限が付与されているか確認してください。
  - **再起動後もオフラインのまま**：`agy-log` を実行して起動時のネットワーク接続状況やステップ 3（`agy` でのログイン）が完了しているか確認してください。
  - **空会話や古いオフライン端末が残る**：定期クリーンアップで自動削除されますが、`agy-clean` で即座に手動削除も可能です。

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
- **ライセンス:** [GNU General Public License v3.0](LICENSE) —— 本ライセンスは本リポジトリ内のモジュールスクリプトおよびソースファイルにのみ適用されます。実行時に別途ダウンロードされるサードパーティ製パッケージおよび Antigravity CLI バイナリには、それぞれのライセンスおよび利用規約が適用されます。
