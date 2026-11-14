[English](README.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

# antigravity-android

**作者：** [KonAyame774](https://github.com/KonAyame774)  
**模块 ID：** `antigravity-android` · **版本：** `v1.0` (`versionCode: 100`)

适用于 **KernelSU / KernelSU Next / Magisk / APatch** 的 Root 模块，可在 Android 开机时以 `root` 权限自动启动 **Antigravity CLI Remote Control** (`agy remote-control`)，并集成 Termux 环境部署、固定设备主机名补丁、`~/.gemini` 权限与 SELinux 实时同步、空白对话／离线实例自动清理以及 4 语界面。

---

## 主要功能

- **开机以 Root `tmux` 自动启动** (`service.sh`, `agy_boot_service.sh`)
  - 等待 Android 启动完成（`sys.boot_completed=1`）、凭据加密存储就绪（`sys.user.0.ce_available=true`）及网络连接正常后，在名为 `agy` 的 root `tmux` 会话中启动 `agy remote-control`。
  - 通过 root 锁文件（`$PREFIX/var/run/agy_root.lock`、`$PREFIX/var/run/agy_start.lock`）防止重复启动，并在启用状态下于打开 Termux 时提供自动守护检查。
- **固定设备主机名** (`patch_agy_hostname.py`, `customize.sh`, `service.sh`)
  - 根据 Android 系统属性（`ro.product.marketname` / 机型 / 设备代号）生成固定名称（`localhost-<device>`），写入 `~/.gemini/config/config.json` 的 `cliRemoteControlHostname`。
  - 动态修补 `aarch64` Go ELF（`agy` / `agy.va39`），使 `--remote-control` 改读 `userSettings.cliRemoteControlHostname`，避免每次重启生成随机后缀。
- **自动部署 Termux 与 glibc 环境** (`ensure_antigravity_env.sh`)
  - 自动安装所需 Termux 软件包（`bash`、`python`、`tmux`、`curl`、`tar`、`util-linux`、`procps`、`coreutils`、`ca-certificates`、`resolv-conf`、`glibc-repo`、`glibc`，若 `/proc/cpuinfo` 缺少 `atomics` 还会安装 `qemu-user-aarch64`），配置 DNS/hosts，并从 [`wallentx/antigravity-cli-termux`](https://github.com/wallentx/antigravity-cli-termux) 下载或更新独立二进制文件。
- **实时权限与 SELinux 同步 + 凭据监听** (`sync_gemini_perms.py`, `agy_boot_service.sh`)
  - 通过 Linux `inotify` 与轮询（`lgetxattr`/`lsetxattr`）持续监控 `~/.gemini` 与 `~/.config/antigravity`，确保以 root 运行 `agy` 时，Termux 用户端仍可正常读写 `config.json`、日志与凭据元数据。
  - 保护敏感文件权限（例如将 `.ls_csrf_token` 保持为 `0600`），并在 OAuth 凭据变更或失效时自动重载服务。
- **空白对话与离线实例自动清理** (`cleanup_empty_conversations.py`, `cleanup_offline_instances.py`)
  - 自动清除重启时产生的零内容空白对话（优先调用本地 `DeleteCascadeTrajectory` RPC，并具备离线 SQLite / `jetbox_summaries_proto.pb` 回退机制），严格保留包含步骤/消息、brain 文件、标题注释或锁定中的任何对话。
  - 在启动前执行离线空白清理、启动后执行开机空白清理，并每 1800 秒定期清理空白对话与过期离线实例。
- **音量键交互切换与无人值守刷入** (`customize.sh`)
  - 刷入时提供 15 秒音量键提示（`[音量 +]` 立即启动/重启并启用开机自启；`[音量 -]` 保持停用；超时则维持运行中会话，未运行时默认停用）。
  - 支持环境变量 `AGY_START_ON_FLASH=1|0|keep`（`1|y|yes|true`、`0|n|no|false`、`keep`），并自动迁移／清除旧版 `antigravity_boot` 模块。
- **4 语界面支持** (`agy_i18n.sh`, `agy_py_i18n.py`)
  - 安装引导、`module.prop` 描述、运行日志与终端命令全面支持 **English (`en`)**、**繁體中文 (`zh-TW`)**、**简体中文 (`zh-CN`)** 与 **日本語 (`ja`)**。

---

## 系统要求

- 已获取 Root 权限的 ARM64 (`aarch64`) Android 设备（**KernelSU**、**KernelSU Next**、**Magisk** 或 **APatch**）
- 已安装 **Termux**（路径位于 `/data/data/com.termux/files`）
- 具备互联网连接（用于首次部署软件包／二进制文件、更新与远程控制认证）

---

## 新手完整使用教程（从零开始）

如果是第一次在 Android 配置 Antigravity CLI Remote Control，请按以下顺序操作即可：

### 第一步：准备 Root 权限与 Termux
1. 确认手机为 ARM64 (`aarch64`) 设备且已获取 Root 权限（**KernelSU**、**KernelSU Next**、**Magisk** 或 **APatch**）。
2. 从 [GitHub Releases (`termux/termux-app`)](https://github.com/termux/termux-app/releases) 或 **F-Droid** 下载并安装 **Termux** *（请勿使用已停止维护的 Google Play 版本）*。
3. 安装后打开 **Termux** 至少一次，等到屏幕出现 `$` 命令提示符，表示基础环境初始化完成。
4. **为 Termux 授予 Root 权限** *（例如在 KernelSU / APatch 打开“超级用户”页面开启 Termux 开关；Magisk 在弹出授权时点击允许）*。
5. 保持手机网络连接正常，便于首次安装自动下载软件包和二进制文件。

### 第二步：下载并刷入模块
1. 前往本项目的 [**Releases**](https://github.com/KonAyame774/antigravity-android/releases) 页面下载 **`antigravity-android-v1.0.zip`**。
2. 打开 **KernelSU / KernelSU Next**、**Magisk** 或 **APatch** → 进入“**模块**”→ 点击“**安装／从本地安装**”并选择刚下载的 ZIP 包。
3. 等待安装脚本自动在 Termux 部署所需软件包（`bash`、`python`、`tmux`、`glibc` 等）、DNS/hosts 配置及 Antigravity CLI 独立可执行文件。
4. 刷入过程中屏幕会提示选择（**15 秒倒计时**），请按手机**音量键**决定：
   - **推荐新手直接按 `音量 +`**：开启开机自启动，并立即在后台启动 `agy remote-control`。
   - **按 `音量 -`**：暂不开启自启动（将 `~/.gemini/config/remote_control` 设为 `0`，之后随时可输入 `agy-start` 开启）。
   - *(进阶／脚本刷入)* 也可提前设置环境变量 `AGY_START_ON_FLASH=1`、`0` 或 `keep`。
5. 查看刷入结尾提示：
   - 若管理器建议重启、或想完整验证开机自启流程，可点击“**重启**”。
   - 若屏幕已提示服务启动完成（或正在待机等待登录），也可不重启直接进入下一步。

### 第三步：登录 Google 账号（首次使用必做）
1. 先**彻底关闭再重新打开 Termux**（或输入 `source ~/.bashrc`），以加载 `agy-*` 管理命令。
2. 在 Termux 中运行：
   ```bash
   agy
   ```
3. 按照屏幕引导完成 Google 账号登录（复制或打开登录链接完成授权后返回 Termux）。
4. **不需要自己手动运行 `agy remote-control`**：
   - 登录凭证（`~/.gemini/antigravity-cli/antigravity-oauth-token`）生成后，后台模块会在几秒内自动检测并重载使 Remote Control 上线。
   - 如果你在第二步按了 `音量 -`（先停用），登录后请再输入一次 `agy-start` 即可开启并启动服务。

### 第四步：确认状态并从网页端远程连接
1. 在 Termux 中输入：
   ```bash
   agy-status
   ```
   确认服务运行中且显示 `Connection status:` 在线状态（以及固定设备名，例如 `localhost-<device>`）。
2. 在手机浏览器、电脑或平板打开 **[https://antigravity.google.com](https://antigravity.google.com)**，登录**同一个 Google 账号**。
3. 点击左上角设备下拉菜单，选择 **`localhost-<device>`** 即可开始远程使用！

### 第五步：日常操作与常见问题排查
- **查看实时画面（`agy-attach`）**：想查看 `agy remote-control` 后台窗口输出时输入 `agy-attach`；看完想退出并**保持后台继续运行**，请依次按 **`Ctrl+B` 再按 `D`** *（切勿按 `Ctrl+C`，否则会中止服务）*。
- **手动开关／重启**：
  - `agy-start`：启动服务并开启开机自启
  - `agy-stop`：停止服务并关闭自动启动
  - `agy-restart`：重启后台服务
- **切换显示语言**：输入 `agy-lang zh-CN`（可选 `zh-TW`、`zh-CN`、`en`、`ja` 或 `auto`）。
- **常见问题排查**：
  - **提示 `agy-status: command not found`**：说明环境变量未重新加载，关闭 Termux 重开或执行 `source ~/.bashrc`。
  - **提示 `su` 无权限 / Permission denied**：检查 KernelSU / Magisk / APatch 是否已授予 **Termux** Root 权限。
  - **重启后仍未上线**：运行 `agy-log` 查看开机时是否尚未联网，或尚未执行第三步的 `agy` 登录 Google。
  - **网页出现空白对话或离线旧实例**：后台会自动定期清理，也可手动运行 `agy-clean` 立即清理。

---

## Termux 常用管理命令

安装时会写入 `~/.bashrc` 的 `# >>> antigravity-remote-control >>>` 区块：

| 命令 | 说明 |
| --- | --- |
| `agy-status` | 查看服务运行状态（`tmux` / PID）、自启开关、主机名与显示语言 |
| `agy-start` | 启用开机自启并以 root 启动 `agy remote-control` |
| `agy-stop` | 停止运行中的服务并关闭自动启动 |
| `agy-restart` | 干净重启 root `agy remote-control` 服务 |
| `agy-attach` | 附加进入当前运行中的 root `tmux` 会话（`agy`） |
| `agy-clean` | 手动清理离线旧实例并立即清理空白对话（`--min-age 0 --verbose`） |
| `agy-log` | 查看运行日志（`~/.gemini/antigravity-cli/boot.log` 与 `/data/adb/agy_boot.log`） |
| `agy-lang [lang]` | 切换显示语言（`en`、`zh-TW`、`zh-CN`、`ja`，或输入 `auto` 恢复系统检测） |

---

## 日志与配置文件路径

| 路径 | 用途 |
| --- | --- |
| `/data/adb/agy_boot.log` | Android 开机阶段脚本日志（`service.sh`） |
| `~/.gemini/antigravity-cli/boot.log` | 服务运行、主机名补丁、凭据监听与自动清理日志 |
| `~/.gemini/config/config.json` | 存储 `cliRemoteControlHostname`（`localhost-<device>`） |
| `~/.gemini/config/remote_control` | 自动启动开关（`0` 表示禁用开机及打开 Termux 时的自动启动） |
| `~/.gemini/config/lang` | 手动指定界面语言（`en`、`zh-TW`、`zh-CN`、`ja`） |
| `/data/adb/antigravity_lang` | 供 root 阶段读取的语言设置镜像 |
| `~/.local/bin/` | `customize.sh` 安装服务与清理脚本的目标目录 |

---

## 仓库结构与自行打包

```text
antigravity-android/
├── META-INF/com/google/android/
│   ├── update-binary
│   └── updater-script
├── files/
│   ├── agy_boot_service.sh           # Root tmux 运行器、凭据监听与定期清理调度
│   ├── agy_i18n.sh                   # Shell 4 语多语言函数库
│   ├── agy_py_i18n.py                # Python 4 语多语言函数库
│   ├── bashrc_block.sh               # Termux ~/.bashrc 命令与启动守护区块
│   ├── cleanup_empty_conversations.py# 空白对话 RPC + 离线 SQLite 回退清理工具
│   ├── cleanup_offline_instances.py  # 离线远程连接实例清理工具
│   ├── ensure_antigravity_env.sh     # Termux/glibc/DNS/二进制文件部署与更新脚本
│   ├── patch_agy_hostname.py         # aarch64 Go ELF 动态主机名补丁工具
│   └── sync_gemini_perms.py          # inotify 实时 UID/GID 与 SELinux MCS 同步工具
├── customize.sh                      # 模块安装脚本、设备名配置与音量键切换
├── module.prop                       # 模块元数据
├── service.sh                        # 开机启动脚本（KernelSU/Magisk/APatch）
├── README.md
├── README.zh-TW.md
├── README.zh-CN.md
└── README.ja.md
```

如需从源码打包可刷入的模块 ZIP：

```bash
zip -r antigravity-android-v1.0.zip META-INF customize.sh module.prop service.sh files -x '*/__pycache__/*' '*.pyc'
```

---

## 实测环境

已在以下真机环境完成刷入验证、重启测试与自动清理实测：

- **设备：** Redmi Turbo 3 (`peridot`)
- **操作系统：** Xiaomi HyperOS 4（`OS4.0.5.0.XNPCNXM`，Android 17 / SDK 37）
- **内核版本：** `6.1.138-android14-Wild`（`aarch64`）
- **Root 与终端环境：** KernelSU（`ksud 3.4.2-100-ga6c81fa4`）+ Termux

---

## 免责声明

- 本模块以 **`root` 权限** 运行，会写入或调整 Termux 相关目录与配置（`~/.local/bin/`、`~/.bashrc`、`~/.gemini/`、`~/.config/antigravity/`），同步所有者／SELinux 标签，并动态修补 `aarch64` 版 Antigravity CLI 可执行文件（`agy` / `agy.va39`）以固定设备主机名。
- 模块依赖于 [`wallentx/antigravity-cli-termux`](https://github.com/wallentx/antigravity-cli-termux) 的二进制文件结构，若上游版本变动可能会影响兼容性。
- 本项目按**“现状”（AS-IS）**提供，不附带任何明示或默示保证；刷入任何 Root 模块前请先备份重要数据与凭证，一切风险由使用者自行承担。

---

## 服务条款与数据使用说明

> [!WARNING]
> 已知 AI 编码代理存在特定安全风险，包括自主执行代码、数据泄露、提示词注入（Prompt Injection）以及供应链风险；本模块更以 **`root`** 权限运行 Antigravity CLI Remote Control，权限风险更高。请务必持续监控并核对代理执行的每一项操作。

使用 Antigravity CLI 即表示您同意让 Google 根据 Google 服务条款和 Google 隐私政策收集并使用您的交互数据（Interactions data）以帮助改进产品；您可随时在设置中选择退出（Opt out）。

### 法律条款与隐私政策链接

- **服务条款（Terms of Service）：** [antigravity.google/terms](https://antigravity.google/terms)
- **隐私政策（Privacy Policy）：** [policies.google.com/privacy](https://policies.google.com/privacy)

---

## 开发说明与致谢

- **开发方式：** 本项目通过 **Antigravity CLI** 以 AI 辅助开发（**Vibe Coding**）方式完成，使用模型为 **Gemini 4 Hydrogen** 与 **Gemini 3.8 Flash**，并已在上述真机设备与系统环境完成实测与调试。
- **上游二进制文件：** [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux)
- **模块作者：** [KonAyame774](https://github.com/KonAyame774)
- **开源协议：** [GNU General Public License v3.0](LICENSE) —— 本协议仅适用于本仓库内的模块脚本与源码文件；安装或运行时另行下载的第三方软件包与 Antigravity CLI 二进制文件，仍各自受其原协议及服务条款约束。
