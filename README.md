[English](README.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

# antigravity-android

**Author:** [KonAyame774](https://github.com/KonAyame774)  
**Module ID:** `antigravity-android` · **Version:** `v1.0` (`versionCode: 100`)

A root module for **KernelSU / KernelSU Next / Magisk / APatch** that runs **Antigravity CLI Remote Control** (`agy remote-control`) on Android at boot as `root`, paired with Termux provisioning, fixed device hostname patching, live permission & SELinux synchronization, automatic cleanup, and a 4-language interface.

---

## Features

- **Boot Autostart inside Root `tmux`** (`service.sh`, `agy_boot_service.sh`)
  - Waits for `sys.boot_completed=1`, credential-encrypted storage (`sys.user.0.ce_available=true`), and network connectivity before starting `agy remote-control` in a root `tmux` session named `agy`.
  - Uses root lock files (`$PREFIX/var/run/agy_root.lock`, `$PREFIX/var/run/agy_start.lock`) to prevent duplicate launches and includes a Termux shell launch safeguard when enabled.
- **Fixed Device Hostname** (`patch_agy_hostname.py`, `customize.sh`, `service.sh`)
  - Generates a consistent hostname (`localhost-<device>`) from Android system properties (`ro.product.marketname` / model / device) and saves `cliRemoteControlHostname` to `~/.gemini/config/config.json`.
  - Dynamically patches the `aarch64` Go ELF (`agy` / `agy.va39`) so `--remote-control` reads `userSettings.cliRemoteControlHostname` instead of creating random slugs on every restart.
- **Automated Termux & glibc Environment Provisioning** (`ensure_antigravity_env.sh`)
  - Installs required Termux packages (`bash`, `python`, `tmux`, `curl`, `tar`, `util-linux`, `procps`, `coreutils`, `ca-certificates`, `resolv-conf`, `glibc-repo`, `glibc`, plus `qemu-user-aarch64` if `/proc/cpuinfo` lacks `atomics`), configures DNS/hosts, and downloads or updates the standalone binary from [`wallentx/antigravity-cli-termux`](https://github.com/wallentx/antigravity-cli-termux).
- **Live Permission & SELinux Sync + Credential Watch** (`sync_gemini_perms.py`, `agy_boot_service.sh`)
  - Continuously monitors `~/.gemini` and `~/.config/antigravity` via Linux `inotify` + polling (`lgetxattr`/`lsetxattr`) to keep Termux UID ownership, SELinux MCS labels, and file permissions synchronized while `agy` runs as root.
  - Protects sensitive credential files (such as `.ls_csrf_token` with `0600`) and automatically reloads the daemon when OAuth tokens change or expire.
- **Automatic Blank & Offline Cleanup** (`cleanup_empty_conversations.py`, `cleanup_offline_instances.py`)
  - Removes zero-content empty conversations generated during restarts (via local `DeleteCascadeTrajectory` RPC with offline SQLite / `jetbox_summaries_proto.pb` fallback) while strictly preserving any conversation containing steps/messages, brain files, annotation titles, or active locks.
  - Runs offline cleanup pre-launch, startup cleanup post-launch, and periodic cleanup every 1800 seconds, alongside periodic cleanup of stale offline remote-control instances.
- **Volume-Key Install Toggle & Unattended Mode** (`customize.sh`)
  - Prompts for 15 seconds on install (`[Vol +]` Yes to start/enable immediately, `[Vol -]` No to keep disabled; timeout preserves a running session or defaults disabled if stopped).
  - Supports unattended installation via `AGY_START_ON_FLASH=1|0|keep` (`1|y|yes|true`, `0|n|no|false`, `keep`) and automatically cleans up legacy `antigravity_boot` installs.
- **4-Language Localization** (`agy_i18n.sh`, `agy_py_i18n.py`)
  - Supports **English (`en`)**, **Traditional Chinese (`zh-TW`)**, **Simplified Chinese (`zh-CN`)**, and **Japanese (`ja`)** across installer prompts, `module.prop`, logs, and shell helpers.

---

## Requirements

- Rooted ARM64 (`aarch64`) Android device running **KernelSU**, **KernelSU Next**, **Magisk**, or **APatch**
- **Termux** installed at `/data/data/com.termux/files`
- Internet access for initial Termux/glibc provisioning, binary updates, and Antigravity Remote Control

---

## Installation

1. Install **Termux** and open it at least once to finish initializing its environment.
2. Download `antigravity-android-v1.0.zip` from **Releases** (or package one from source as shown below).
3. Flash the zip in **KernelSU / KernelSU Next**, **Magisk**, or **APatch**.
4. Use the volume keys when prompted during flashing:
   - **`Vol +`**: Enable auto-start and start (or restart) `agy remote-control` now.
   - **`Vol -`**: Leave Remote Control disabled (`~/.gemini/config/remote_control` set to `0`).
   - *(Optional for scripted installs)* Set `AGY_START_ON_FLASH=1`, `0`, or `keep` before calling the installer.
5. Open a new Termux session (or run `source ~/.bashrc`) to load the `agy-*` helper commands, and ensure you are signed in to Antigravity CLI if you have not logged in yet.

---

## Termux Helper Commands

Installed into `~/.bashrc` between `# >>> antigravity-remote-control >>>` markers:

| Command | Description |
| --- | --- |
| `agy-status` | Show daemon status, PID/tmux state, auto-start flag, hostname, and language |
| `agy-start` | Enable auto-start and launch `agy remote-control` as root |
| `agy-stop` | Stop the running daemon and disable auto-start |
| `agy-restart` | Cleanly restart the root `agy remote-control` service |
| `agy-attach` | Attach to the running root `tmux` session (`agy`) |
| `agy-clean` | Manually remove stale offline instances and empty conversations (`--min-age 0 --verbose`) |
| `agy-log` | View runtime logs (`~/.gemini/antigravity-cli/boot.log` and `/data/adb/agy_boot.log`) |
| `agy-lang [lang]` | Set display language (`en`, `zh-TW`, `zh-CN`, `ja`, or `auto` for system detection) |

---

## Logs & Configuration Files

| Path | Purpose |
| --- | --- |
| `/data/adb/agy_boot.log` | Early Android boot script log (`service.sh`) |
| `~/.gemini/antigravity-cli/boot.log` | Service runner, hostname patching, OAuth watch, and cleanup log |
| `~/.gemini/config/config.json` | Stores `cliRemoteControlHostname` (`localhost-<device>`) |
| `~/.gemini/config/remote_control` | Auto-start toggle flag (`0` disables auto-start on boot / Termux launch) |
| `~/.gemini/config/lang` | Manual language override (`en`, `zh-TW`, `zh-CN`, `ja`) |
| `/data/adb/antigravity_lang` | Root-readable mirrored language setting |
| `~/.local/bin/` | Target directory where `customize.sh` installs service and cleanup scripts |

---

## Repository Structure & Building the Module Zip

```text
antigravity-android/
├── META-INF/com/google/android/
│   ├── update-binary
│   └── updater-script
├── files/
│   ├── agy_boot_service.sh           # Root tmux runner, OAuth watch, periodic cleanup triggers
│   ├── agy_i18n.sh                   # Shell 4-language i18n helper
│   ├── agy_py_i18n.py                # Python 4-language i18n helper
│   ├── bashrc_block.sh               # Termux ~/.bashrc helper functions & launch safeguard
│   ├── cleanup_empty_conversations.py# Blank conversation RPC + offline fallback cleaner
│   ├── cleanup_offline_instances.py  # Stale offline remote-control instance cleaner
│   ├── ensure_antigravity_env.sh     # Termux/glibc/DNS/binary setup & updater
│   ├── patch_agy_hostname.py         # Dynamic aarch64 ELF hostname patcher
│   └── sync_gemini_perms.py          # Live inotify UID/GID & SELinux MCS synchronizer
├── customize.sh                      # Module installer, hostname setup, volume-key toggle
├── module.prop                       # Module metadata
├── service.sh                        # Boot-time launcher (KernelSU/Magisk/APatch)
├── README.md
├── README.zh-TW.md
├── README.zh-CN.md
└── README.ja.md
```

To package a flashable module zip directly from a clean checkout:

```bash
zip -r antigravity-android-v1.0.zip META-INF customize.sh module.prop service.sh files -x '*/__pycache__/*' '*.pyc'
```

---

## Tested Environment

Verified on real hardware with live reboot/flash testing and automated cleanup checks:

- **Device:** Redmi Turbo 3 (`peridot`)
- **System / OS:** Xiaomi HyperOS 4 (`OS4.0.5.0.XNPCNXM`, Android 17 / SDK 37)
- **Kernel:** `6.1.138-android14-Wild` (`aarch64`)
- **Root & Shell Environment:** KernelSU (`ksud 3.4.2-100-ga6c81fa4`) + Termux

---

## Disclaimer

- This module operates with **`root` privileges**, modifies Termux configuration (`~/.local/bin/`, `~/.bashrc`, `~/.gemini/`, `~/.config/antigravity/`), synchronizes file ownership/SELinux labels, and dynamically patches the `aarch64` Antigravity CLI binary (`agy` / `agy.va39`) for fixed hostname support.
- It relies on the release binary layout of [`wallentx/antigravity-cli-termux`](https://github.com/wallentx/antigravity-cli-termux); future upstream updates may affect compatibility.
- Provided **as-is without any warranty**. Back up important data and credentials before flashing root modules. Use at your own risk.

---

## Terms of Service & Data Use

> [!WARNING]
> AI coding agents are known to have certain security risks, including autonomous code execution, data exfiltration, prompt injection, and supply chain risks — especially when running Antigravity CLI Remote Control with **`root`** privileges. Ensure that you monitor and verify all actions taken by the agent.

By using Antigravity CLI, you agree to help improve the product by allowing Google to collect and use your Interactions data, subject to the Google Terms of Service and Google Privacy Policy. You can choose to opt out at any time via your settings.

### Legal & Privacy Links

- **Terms of Service:** [antigravity.google/terms](https://antigravity.google/terms)
- **Privacy Policy:** [policies.google.com/privacy](https://policies.google.com/privacy)

---

## Credits & Development Note

- **Development Method:** Built with AI-assisted development (**vibe coding**) using **Gemini 4 Hydrogen** and **Gemini 3.8 Flash** in **Antigravity CLI**, then tested and debugged on the device and OS listed above.
- **Upstream Binary:** [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux)
- **Module Author:** [KonAyame774](https://github.com/KonAyame774)
