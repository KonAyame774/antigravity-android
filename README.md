[English](README.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

# antigravity-android

**Author:** [KonAyame774](https://github.com/KonAyame774)  
**Module ID:** `antigravity-android` · **Version:** `v1.0.1` (`versionCode: 101`)

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

## Beginner Step-by-Step Guide (Start to Finish)

Follow these steps in order if this is your first time setting up Antigravity CLI Remote Control on Android:

### Step 1: Prepare Root Permissions & Termux
1. Confirm your Android device is ARM64 (`aarch64`) and rooted with **KernelSU**, **KernelSU Next**, **Magisk**, or **APatch**.
2. Install **Termux** from [GitHub Releases (`termux/termux-app`)](https://github.com/termux/termux-app/releases) or **F-Droid** *(avoid the outdated Google Play build)*.
3. Open **Termux** at least once and wait until the `$` shell prompt appears so initial setup completes.
4. **Grant Root access to Termux** in your root manager *(in KernelSU / APatch open the Superuser tab and enable root for Termux; in Magisk approve the `su` prompt when asked)*.
5. Keep your phone connected to the internet for initial package and binary setup.

### Step 2: Download & Flash the Module
1. Download **`antigravity-android-v1.0.1.zip`** from this repository's [**Releases**](https://github.com/KonAyame774/antigravity-android/releases) page.
2. Open **KernelSU / KernelSU Next**, **Magisk**, or **APatch** → go to **Modules** → tap **Install** and select `antigravity-android-v1.0.1.zip`.
3. Wait while the installer automatically configures Termux packages (`bash`, `python`, `tmux`, `glibc`, etc.), DNS/hosts, and downloads the standalone Antigravity CLI binary.
4. When prompted during flashing (**15-second window**), choose with the volume buttons:
   - **Recommended for beginners — press `Vol +`**: Enables boot auto-start and launches `agy remote-control` right away.
   - **Press `Vol -`**: Installs the module without enabling auto-start (`~/.gemini/config/remote_control` is set to `0`; you can turn it on anytime later with `agy-start`).
   - *(Automated / scripted flash)* Set `AGY_START_ON_FLASH=1`, `0`, or `keep` before flashing.
5. Check the end of the flash output:
   - If you want a clean boot test or your root manager recommends it, tap **Reboot**.
   - If the installer reports that the service is already started (or standby waiting for login), you can proceed straight to Step 3 without rebooting.

### Step 3: Sign In to Google (First-Time Setup)
1. **Close and reopen Termux completely** (or run `source ~/.bashrc`) so the `agy-*` helper commands load into your shell.
2. Run:
   ```bash
   agy
   ```
3. Follow the on-screen sign-in prompt to log in with your Google account in your browser and return to Termux once finished.
4. You do **not** need to run `agy remote-control` manually:
   - Once your OAuth token is saved (`~/.gemini/antigravity-cli/antigravity-oauth-token`), the background service automatically detects it and brings Remote Control online within a few seconds.
   - If you pressed `Vol -` during installation earlier, run `agy-start` once to enable and launch it.

### Step 4: Verify Status & Connect from Antigravity Web
1. In Termux, run:
   ```bash
   agy-status
   ```
   Wait until you see the process running and `Connection status:` showing online (along with your fixed device hostname, e.g. `localhost-<device>`).
2. Open **[https://antigravity.google.com](https://antigravity.google.com)** in any browser (on your phone, PC, or tablet) and sign in with the **same Google account**.
3. Open the host/device selector in the top-left corner and pick **`localhost-<device>`** to start using Antigravity remotely.

### Step 5: Daily Usage & Troubleshooting
- **View live `tmux` console (`agy-attach`)**: Run `agy-attach` to inspect the live `agy remote-control` screen. To exit the viewer **without stopping the service**, press **`Ctrl+B` then `D`** *(do not press `Ctrl+C`)*.
- **Start / Stop / Restart manually**:
  - `agy-start` — Start the service and enable boot auto-start
  - `agy-stop` — Stop the service and disable boot auto-start
  - `agy-restart` — Cleanly restart the background service
- **Switch display language**: Run `agy-lang zh-TW` (or `en`, `zh-CN`, `ja`, `auto`).
- **Common issues**:
  - **`agy-status: command not found`**: Reopen Termux or run `source ~/.bashrc`.
  - **Root / `su` permission denied**: Open KernelSU / Magisk / APatch and confirm **Termux** is granted root access.
  - **Still offline after reboot**: Run `agy-log` to check whether the device had internet at boot or still needs Step 3 (`agy` Google sign-in).
  - **Extra blank conversations or old offline entries**: Background cleanup removes them automatically; you can also run `agy-clean` to clean immediately.

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
zip -r antigravity-android-v1.0.1.zip META-INF customize.sh module.prop service.sh LICENSE files -x '*/__pycache__/*' '*.pyc'
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
- **License:** [GNU General Public License v3.0](LICENSE) — applies solely to the module scripts and files authored in this repository; third-party packages and the Antigravity CLI binary downloaded at runtime remain governed by their respective licenses and terms.
