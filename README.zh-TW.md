[English](README.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

# antigravity-android

**作者：** [KonAyame774](https://github.com/KonAyame774)  
**模組 ID：** `antigravity-android` · **版本：** `v1.0` (`versionCode: 100`)

適用於 **KernelSU / KernelSU Next / Magisk / APatch** 的 Root 模組，可在 Android 開機時以 `root` 權限自動啟動 **Antigravity CLI Remote Control** (`agy remote-control`)，並整合 Termux 環境佈署、固定裝置主機名稱修補、`~/.gemini` 權限與 SELinux 即時同步、空白對話／離線實例自動清理以及 4 語介面。

---

## 主要功能

- **開機以 Root `tmux` 自動啟動** (`service.sh`, `agy_boot_service.sh`)
  - 等待 Android 開機完成（`sys.boot_completed=1`）、憑證加密儲存空間就緒（`sys.user.0.ce_available=true`）及網路連線正常後，於名為 `agy` 的 root `tmux` 會話中啟動 `agy remote-control`。
  - 透過 root 鎖檔（`$PREFIX/var/run/agy_root.lock`、`$PREFIX/var/run/agy_start.lock`）避免重複啟動，並於啟用狀態下在開啟 Termux 時提供自動守護檢查。
- **固定裝置主機名稱** (`patch_agy_hostname.py`, `customize.sh`, `service.sh`)
  - 依 Android 系統屬性（`ro.product.marketname` / 機型 / 裝置代號）產生固定名稱（`localhost-<device>`），寫入 `~/.gemini/config/config.json` 的 `cliRemoteControlHostname`。
  - 動態修補 `aarch64` Go ELF（`agy` / `agy.va39`），使 `--remote-control` 改讀 `userSettings.cliRemoteControlHostname`，不再於每次重啟產生隨機後綴。
- **自動佈署 Termux 與 glibc 環境** (`ensure_antigravity_env.sh`)
  - 自動安裝所需 Termux 套件（`bash`、`python`、`tmux`、`curl`、`tar`、`util-linux`、`procps`、`coreutils`、`ca-certificates`、`resolv-conf`、`glibc-repo`、`glibc`，若 `/proc/cpuinfo` 缺乏 `atomics` 亦會安裝 `qemu-user-aarch64`），修正 DNS/hosts 設定，並從 [`wallentx/antigravity-cli-termux`](https://github.com/wallentx/antigravity-cli-termux) 下載或更新獨立執行檔。
- **即時權限與 SELinux 同步 + 憑證監看** (`sync_gemini_perms.py`, `agy_boot_service.sh`)
  - 透過 Linux `inotify` 與輪詢（`lgetxattr`/`lsetxattr`）持續監控 `~/.gemini` 與 `~/.config/antigravity`，確保以 root 執行 `agy` 時，Termux 使用者端仍可正常讀寫 `config.json`、日誌與憑證中繼資料。
  - 保護敏感檔案權限（例如將 `.ls_csrf_token` 維持為 `0600`），並在 OAuth 憑證變更或失效時自動重新載入服務。
- **空白對話與離線實例自動清理** (`cleanup_empty_conversations.py`, `cleanup_offline_instances.py`)
  - 自動清除重啟時產生的零內容空白對話（優先呼叫本機 `DeleteCascadeTrajectory` RPC，並具備離線 SQLite / `jetbox_summaries_proto.pb` 後備機制），嚴格保留含有步驟/訊息、brain 檔案、標題註記或鎖定中的任何對話。
  - 於啟動前執行離線空白清理、啟動後執行開機空白清理，並每 1800 秒定期清理空白對話與逾期離線實例。
- **音量鍵互動切換與無人值守刷入** (`customize.sh`)
  - 刷入時提供 15 秒音量鍵提示（`[音量 +]` 立即啟動/重啟並啟用開機自啟；`[音量 -]` 保持停用；逾時則維持執行中會話，若未執行則預設停用）。
  - 支援環境變數 `AGY_START_ON_FLASH=1|0|keep`（`1|y|yes|true`、`0|n|no|false`、`keep`），並自動遷移／清除舊版 `antigravity_boot` 模組。
- **4 語介面支援** (`agy_i18n.sh`, `agy_py_i18n.py`)
  - 安裝精靈、`module.prop` 描述、執行日誌與終端機指令全面支援 **English (`en`)**、**繁體中文 (`zh-TW`)**、**简体中文 (`zh-CN`)** 與 **日本語 (`ja`)**。

---

## 系統需求

- 已取得 Root 權限的 ARM64 (`aarch64`) Android 裝置（**KernelSU**、**KernelSU Next**、**Magisk** 或 **APatch**）
- 已安裝 **Termux**（路徑位於 `/data/data/com.termux/files`）
- 具備網際網路連線（用於初次佈署套件／二進位檔、更新與遠端連線驗證）

---

## 安裝方式

1. 安裝 **Termux** 並至少開啟一次以完成基礎環境初始化。
2. 至 **Releases** 下載 `antigravity-android-v1.0.zip`（或依下方指令自行從原始碼打包）。
3. 在 **KernelSU / KernelSU Next**、**Magisk** 或 **APatch** 中刷入該 ZIP 模組。
4. 刷入過程中依畫面提示以音量鍵選擇：
   - **`音量 +`**：啟用自動啟動，並立即啟動（或重啟）`agy remote-control`。
   - **`音量 -`**：停用遠端控制自動啟動（將 `~/.gemini/config/remote_control` 設為 `0`）。
   - *(進階／腳本刷入)* 可預先指定 `AGY_START_ON_FLASH=1`、`0` 或 `keep`。
5. 開啟新的 Termux 工作階段（或執行 `source ~/.bashrc`）即可載入 `agy-*` 指令；若尚未登入 Antigravity CLI，請先於 Termux 完成登入。

---

## Termux 常用管理指令

安裝時會寫入 `~/.bashrc` 的 `# >>> antigravity-remote-control >>>` 區段：

| 指令 | 說明 |
| --- | --- |
| `agy-status` | 查看服務執行狀態（`tmux` / PID）、自啟開關、主機名稱與顯示語言 |
| `agy-start` | 啟用開機自啟並以 root 啟動 `agy remote-control` |
| `agy-stop` | 停止執行中的服務並關閉自動啟動 |
| `agy-restart` | 乾淨重啟 root `agy remote-control` 服務 |
| `agy-attach` | 附加進入目前執行中的 root `tmux` 會話（`agy`） |
| `agy-clean` | 手動清理離線舊實例並立即清理空白對話（`--min-age 0 --verbose`） |
| `agy-log` | 檢視執行日誌（`~/.gemini/antigravity-cli/boot.log` 與 `/data/adb/agy_boot.log`） |
| `agy-lang [lang]` | 切換顯示語言（`en`、`zh-TW`、`zh-CN`、`ja`，或輸入 `auto` 恢復系統偵測） |

---

## 日誌與設定檔位置

| 路徑 | 用途 |
| --- | --- |
| `/data/adb/agy_boot.log` | Android 開機階段腳本日誌（`service.sh`） |
| `~/.gemini/antigravity-cli/boot.log` | 服務執行、主機名稱修補、憑證監看與自動清理日誌 |
| `~/.gemini/config/config.json` | 儲存 `cliRemoteControlHostname`（`localhost-<device>`） |
| `~/.gemini/config/remote_control` | 自動啟動開關（`0` 代表停用開機及開啟 Termux 時的自動啟動） |
| `~/.gemini/config/lang` | 手動指定介面語言（`en`、`zh-TW`、`zh-CN`、`ja`） |
| `/data/adb/antigravity_lang` | 供 root 階段讀取的語言設定鏡像 |
| `~/.local/bin/` | `customize.sh` 安裝服務與清理腳本的目的目錄 |

---

## 專案結構與自行打包

```text
antigravity-android/
├── META-INF/com/google/android/
│   ├── update-binary
│   └── updater-script
├── files/
│   ├── agy_boot_service.sh           # Root tmux 執行器、憑證監看與定期清理排程
│   ├── agy_i18n.sh                   # Shell 4 語多國語言函式庫
│   ├── agy_py_i18n.py                # Python 4 語多國語言函式庫
│   ├── bashrc_block.sh               # Termux ~/.bashrc 指令與啟動守護區塊
│   ├── cleanup_empty_conversations.py# 空白對話 RPC + 離線 SQLite 後備清理工具
│   ├── cleanup_offline_instances.py  # 離線遠端連線實例清理工具
│   ├── ensure_antigravity_env.sh     # Termux/glibc/DNS/二進位檔佈署與更新腳本
│   ├── patch_agy_hostname.py         # aarch64 Go ELF 動態主機名稱修補工具
│   └── sync_gemini_perms.py          # inotify 即時 UID/GID 與 SELinux MCS 同步工具
├── customize.sh                      # 模組安裝腳本、裝置名稱設定與音量鍵切換
├── module.prop                       # 模組中繼資訊
├── service.sh                        # 開機啟動腳本（KernelSU/Magisk/APatch）
├── README.md
├── README.zh-TW.md
├── README.zh-CN.md
└── README.ja.md
```

若要從原始碼打包成可刷入的模組 ZIP：

```bash
zip -r antigravity-android-v1.0.zip META-INF customize.sh module.prop service.sh files -x '*/__pycache__/*' '*.pyc'
```

---

## 實測環境

已於下列實機環境完成刷入驗證、重啟測試與自動清理實測：

- **裝置：** Redmi Turbo 3 (`peridot`)
- **作業系統：** Xiaomi HyperOS 4（`OS4.0.5.0.XNPCNXM`，Android 17 / SDK 37）
- **核心版本：** `6.1.138-android14-Wild`（`aarch64`）
- **Root 與終端環境：** KernelSU（`ksud 3.4.2-100-ga6c81fa4`）+ Termux

---

## 免責聲明

- 本模組以 **`root` 權限** 運作，會寫入或調整 Termux 相關目錄與設定（`~/.local/bin/`、`~/.bashrc`、`~/.gemini/`、`~/.config/antigravity/`），同步擁有者／SELinux 標籤，並動態修補 `aarch64` 版 Antigravity CLI 執行檔（`agy` / `agy.va39`）以固定裝置主機名稱。
- 模組相依於 [`wallentx/antigravity-cli-termux`](https://github.com/wallentx/antigravity-cli-termux) 的二進位檔結構，若上游版本改版可能會影響相容性。
- 本專案按**「現狀」（AS-IS）**提供，不附帶任何明示或默示保證；刷入任何 Root 模組前請先備份重要資料與憑證，一切風險由使用者自行承擔。

---

## 服務條款與資料使用說明

> [!WARNING]
> 已知 AI 編碼代理存在特定安全風險，包含自主執行程式碼、資料外洩、提示詞注入（Prompt Injection）以及供應鏈風險；本模組更以 **`root`** 權限執行 Antigravity CLI Remote Control，權限風險更高。請務必持續監看並核對代理執行的每一項操作。

使用 Antigravity CLI 即表示您同意讓 Google 依 Google 服務條款與 Google 隱私權政策收集並使用您的互動資料（Interactions data）以協助改進產品；您可隨時在設定中選擇退出（Opt out）。

### 法律條款與隱私權連結

- **服務條款（Terms of Service）：** [antigravity.google/terms](https://antigravity.google/terms)
- **隱私權政策（Privacy Policy）：** [policies.google.com/privacy](https://policies.google.com/privacy)

---

## 開發說明與致謝

- **開發方式：** 本專案透過 **Antigravity CLI** 以 AI 輔助開發（**Vibe Coding**）方式完成，使用模型為 **Gemini 4 Hydrogen** 與 **Gemini 3.8 Flash**，並已於上述實機裝置與系統環境完成實測與除錯。
- **上游二進位檔：** [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux)
- **模組作者：** [KonAyame774](https://github.com/KonAyame774)
