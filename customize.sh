ui_print "****************************************"
ui_print "*         antigravity-android          *"
ui_print "****************************************"

TERMUX_HOME="/data/data/com.termux/files/home"
TERMUX_USR="/data/data/com.termux/files/usr"
TERMUX_BIN="$TERMUX_USR/bin"

if [ -f "$MODPATH/files/agy_i18n.sh" ]; then
    . "$MODPATH/files/agy_i18n.sh"
    agy_i18n_init "$TERMUX_HOME"
else
    agy_i18n_refresh_cache() { :; }
    agy_i18n_init() { :; }
    agy_msg() { local _k="$1"; shift; printf '%s%s\n' "$_k" "${*:+: $*}"; }
fi

get_device_slug() {
    local name="$(getprop ro.product.marketname)"
    [ -z "$name" ] && name="$(getprop ro.product.model)"
    [ -z "$name" ] && name="$(getprop ro.product.device)"
    echo "$name" | tr "[:upper:]" "[:lower:]" | sed -E "s/[^a-z0-9]+/-/g" | sed -E "s/^-+|-+$//g"
}

DEVICE_SLUG="$(get_device_slug)"
[ -z "$DEVICE_SLUG" ] && DEVICE_SLUG="phone"
HOSTNAME="localhost-$DEVICE_SLUG"

ui_print "$(agy_msg cust_detected_device "$DEVICE_SLUG")"
ui_print "$(agy_msg cust_set_hostname "$HOSTNAME")"
ui_print "$(agy_msg cust_detected_locale "${AGY_LOCALE:-en}")"

if [ ! -d "$TERMUX_HOME" ] || [ ! -d "$TERMUX_BIN" ]; then
    ui_print "$(agy_msg cust_err_no_termux "$TERMUX_HOME")"
    ui_print "$(agy_msg cust_err_init_termux)"
    abort "$(agy_msg cust_abort_termux)"
fi

TERMUX_UID=$(/system/bin/stat -c "%u" "$TERMUX_HOME" 2>/dev/null || echo 10466)
TERMUX_GID=$(/system/bin/stat -c "%g" "$TERMUX_HOME" 2>/dev/null || echo "$TERMUX_UID")
TERMUX_CTX=$(/system/bin/stat -c "%C" "$TERMUX_HOME" 2>/dev/null || true)
ui_print "$(agy_msg cust_termux_uid "$TERMUX_UID")"

agy_i18n_refresh_cache "$TERMUX_HOME" "$TERMUX_UID" "$TERMUX_GID" "$TERMUX_CTX"
agy_i18n_init "$TERMUX_HOME" 1

# 1. Auto-detect & provision environment (Termux packages, glibc, CA/DNS, LSE/QEMU, wallentx agy)
ui_print "$(agy_msg cust_check_env)"
_agy_ui_log() {
    ui_print "  $1"
}
AGY_ENV_LIB_ONLY=1
AGY_ENV_LOG_FN=_agy_ui_log
. "$MODPATH/files/ensure_antigravity_env.sh"
ensure_env_main
ENV_RC=$?
if [ "$ENV_RC" -eq 2 ]; then
    ui_print "$(agy_msg cust_env_offline_later)"
elif [ "$ENV_RC" -ne 0 ]; then
    ui_print "$(agy_msg cust_env_warn "$ENV_RC")"
fi

# 2. Configure config.json
export PYTHONDONTWRITEBYTECODE=1
CONFIG_DIR="$TERMUX_HOME/.gemini/config"
CONFIG_FILE="$CONFIG_DIR/config.json"
mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_FILE" ]; then
    if [ -x "$TERMUX_BIN/python3" ]; then
        "$TERMUX_BIN/python3" -B -c "
import json, os
loc = os.environ.get('AGY_LOCALE', 'en')
msgs = {
    'zh-TW': ('已更新 config.json', '更新 config.json 失敗:'),
    'zh-CN': ('已更新 config.json', '更新 config.json 失败:'),
    'ja': ('config.json を更新しました', 'config.json の更新に失敗しました:'),
    'en': ('Updated config.json', 'Failed to update config.json:'),
}
ok_m, err_m = msgs.get(loc, msgs['en'])
path = '$CONFIG_FILE'
try:
    with open(path, 'r', encoding='utf-8') as f:
        raw = f.read().strip()
    cfg = json.loads(raw) if raw else {}
    if not isinstance(cfg, dict):
        cfg = {}
    cfg.setdefault('userSettings', {})['cliRemoteControlHostname'] = '$HOSTNAME'
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2)
    print(ok_m)
except Exception as e:
    print(err_m, e)
"
    else
        ui_print "$(agy_msg cust_warn_no_python_cfg)"
    fi
else
    cat << EOF > "$CONFIG_FILE"
{
  "userSettings": {
    "cliRemoteControlHostname": "$HOSTNAME"
  }
}
EOF
fi
chmod 644 "$CONFIG_FILE" 2>/dev/null || true
chown "$TERMUX_UID:$TERMUX_GID" "$TERMUX_HOME/.gemini" "$CONFIG_DIR" "$CONFIG_FILE" 2>/dev/null
mkdir -p "$TERMUX_HOME/.gemini/antigravity-cli"
touch "$TERMUX_HOME/.gemini/antigravity-cli/boot.log" 2>/dev/null
chmod 644 "$TERMUX_HOME/.gemini/antigravity-cli/boot.log" 2>/dev/null
chown "$TERMUX_UID:$TERMUX_GID" "$TERMUX_HOME/.gemini/antigravity-cli" "$TERMUX_HOME/.gemini/antigravity-cli/boot.log" 2>/dev/null
if [ -n "$TERMUX_CTX" ] && [ -x /system/bin/chcon ]; then
    /system/bin/chcon "$TERMUX_CTX" "$TERMUX_HOME/.gemini" "$CONFIG_DIR" "$CONFIG_FILE" "$TERMUX_HOME/.gemini/antigravity-cli" "$TERMUX_HOME/.gemini/antigravity-cli/boot.log" 2>/dev/null || true
fi
ui_print "$(agy_msg cust_cfg_updated "$HOSTNAME")"

# 3. Pre-create shared lock files for root status detection
TERMUX_RUN="$TERMUX_USR/var/run"
mkdir -p "$TERMUX_RUN"
for _lf in "$TERMUX_RUN/agy_root.lock" "$TERMUX_RUN/agy_start.lock"; do
    [ -f "$_lf" ] || : > "$_lf"
    chmod 644 "$_lf" 2>/dev/null
    chown "$TERMUX_UID:$TERMUX_GID" "$_lf" 2>/dev/null
    if [ -n "$TERMUX_CTX" ] && [ -x /system/bin/chcon ]; then
        /system/bin/chcon "$TERMUX_CTX" "$_lf" 2>/dev/null || true
    fi
done

# 4. Install helper scripts into ~/.local/bin/
mkdir -p "$TERMUX_HOME/.local/bin"
rm -rf "$TERMUX_HOME/.local/bin/__pycache__" 2>/dev/null || true
cp -f "$MODPATH/files/agy_i18n.sh" "$TERMUX_HOME/.local/bin/agy_i18n.sh"
cp -f "$MODPATH/files/agy_py_i18n.py" "$TERMUX_HOME/.local/bin/agy_py_i18n.py"
cp -f "$MODPATH/files/ensure_antigravity_env.sh" "$TERMUX_HOME/.local/bin/ensure_antigravity_env.sh"
cp -f "$MODPATH/files/agy_boot_service.sh" "$TERMUX_HOME/.local/bin/agy_boot_service.sh"
cp -f "$MODPATH/files/cleanup_offline_instances.py" "$TERMUX_HOME/.local/bin/cleanup_offline_instances.py"
cp -f "$MODPATH/files/cleanup_empty_conversations.py" "$TERMUX_HOME/.local/bin/cleanup_empty_conversations.py"
cp -f "$MODPATH/files/patch_agy_hostname.py" "$TERMUX_HOME/.local/bin/patch_agy_hostname.py"
cp -f "$MODPATH/files/sync_gemini_perms.py" "$TERMUX_HOME/.local/bin/sync_gemini_perms.py"
chmod 755 \
    "$TERMUX_HOME/.local/bin/agy_i18n.sh" \
    "$TERMUX_HOME/.local/bin/agy_py_i18n.py" \
    "$TERMUX_HOME/.local/bin/ensure_antigravity_env.sh" \
    "$TERMUX_HOME/.local/bin/agy_boot_service.sh" \
    "$TERMUX_HOME/.local/bin/cleanup_offline_instances.py" \
    "$TERMUX_HOME/.local/bin/cleanup_empty_conversations.py" \
    "$TERMUX_HOME/.local/bin/patch_agy_hostname.py" \
    "$TERMUX_HOME/.local/bin/sync_gemini_perms.py"
chown -Rh "$TERMUX_UID:$TERMUX_GID" "$TERMUX_HOME/.local" 2>/dev/null || chown -R "$TERMUX_UID:$TERMUX_GID" "$TERMUX_HOME/.local" 2>/dev/null
if [ -n "$TERMUX_CTX" ] && [ -x /system/bin/chcon ]; then
    /system/bin/chcon -Rh "$TERMUX_CTX" "$TERMUX_HOME/.local" 2>/dev/null || /system/bin/chcon -R "$TERMUX_CTX" "$TERMUX_HOME/.local" 2>/dev/null || true
fi
ui_print "$(agy_msg cust_scripts_installed)"

# 5. Patch agy / agy.va39 binaries for persistent hostname
ui_print "$(agy_msg cust_check_patch)"
if [ -x "$TERMUX_BIN/python3" ]; then
    HOME="$TERMUX_HOME" PREFIX="$TERMUX_USR" AGY_LOCALE="${AGY_LOCALE:-en}" "$TERMUX_BIN/python3" -B "$TERMUX_HOME/.local/bin/patch_agy_hostname.py" 2>&1 | while IFS= read -r _line; do
        ui_print "  $_line"
    done
    HOME="$TERMUX_HOME" PREFIX="$TERMUX_USR" "$TERMUX_BIN/python3" -B "$TERMUX_HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 || true
fi

# 6. Configure or upgrade ~/.bashrc
BASHRC="$TERMUX_HOME/.bashrc"
BLOCK_FILE="$MODPATH/files/bashrc_block.sh"
if [ -x "$TERMUX_BIN/python3" ] && [ -f "$BLOCK_FILE" ]; then
    "$TERMUX_BIN/python3" -B -c "
import os, re
rc_path = '$BASHRC'
block = open('$BLOCK_FILE', 'r', encoding='utf-8').read().rstrip() + '\n'
content = open(rc_path, 'r', encoding='utf-8').read() if os.path.exists(rc_path) else ''
new_pat = re.compile(r'# >>> antigravity-remote-control >>>.*?# <<< antigravity-remote-control <<<\n?', re.DOTALL)
old_pat = re.compile(r'# Antigravity Remote Control helpers & auto-start safeguard.*?\nfi\n?', re.DOTALL)
if new_pat.search(content):
    content = new_pat.sub(lambda _: block, content)
elif old_pat.search(content):
    content = old_pat.sub(lambda _: block, content)
else:
    if content and not content.endswith('\n'):
        content += '\n'
    content += ('\n' if content else '') + block
with open(rc_path, 'w', encoding='utf-8') as f:
    f.write(content)
"
    chown "$TERMUX_UID:$TERMUX_GID" "$BASHRC" 2>/dev/null
    chmod 644 "$BASHRC" 2>/dev/null
    [ -n "$TERMUX_CTX" ] && [ -x /system/bin/chcon ] && /system/bin/chcon "$TERMUX_CTX" "$BASHRC" 2>/dev/null || true
    ui_print "$(agy_msg cust_bashrc_updated)"
elif [ -f "$BLOCK_FILE" ] && ! grep -q "# >>> antigravity-remote-control >>>" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    cat "$BLOCK_FILE" >> "$BASHRC"
    chown "$TERMUX_UID:$TERMUX_GID" "$BASHRC" 2>/dev/null
    chmod 644 "$BASHRC" 2>/dev/null
    [ -n "$TERMUX_CTX" ] && [ -x /system/bin/chcon ] && /system/bin/chcon "$TERMUX_CTX" "$BASHRC" 2>/dev/null || true
    ui_print "$(agy_msg cust_bashrc_added)"
fi

# 7. Clean up standalone service.d script
if [ -f "/data/adb/service.d/agy_boot.sh" ]; then
    rm -f "/data/adb/service.d/agy_boot.sh"
    ui_print "$(agy_msg cust_removed_serviced)"
fi
if [ -d "/data/adb/modules/antigravity_boot" ]; then
    : > "/data/adb/modules/antigravity_boot/disable" 2>/dev/null || true
    : > "/data/adb/modules/antigravity_boot/remove" 2>/dev/null || true
fi
rm -rf "/data/adb/modules_update/antigravity_boot" 2>/dev/null || true

# Localize installed module.prop description
if [ -f "$MODPATH/module.prop" ]; then
    _mod_desc=$(agy_msg module_desc)
    if [ -x "$TERMUX_BIN/python3" ]; then
        "$TERMUX_BIN/python3" -B -c "
import sys
p, desc = sys.argv[1], sys.argv[2].replace('\n', ' ').strip()
with open(p, 'r', encoding='utf-8') as f:
    lines = f.readlines()
out = [('description=' + desc + '\n') if l.startswith('description=') else l for l in lines]
if not any(l.startswith('description=') for l in out):
    out.append('description=' + desc + '\n')
with open(p, 'w', encoding='utf-8') as f:
    f.writelines(out)
" "$MODPATH/module.prop" "$_mod_desc" 2>/dev/null || true
    fi
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755

# 8. 刷入完成前詢問是否立即於背景開啟 Remote Control (僅於開機狀態的安裝環境詢問)
_choose_vol_key() {
    local timeout_sec="${1:-15}"
    case "${AGY_START_ON_FLASH:-}" in
        1|y|yes|true) return 0 ;;
        0|n|no|false) return 1 ;;
        keep) return 4 ;;
    esac

    if [ -x "$TERMUX_BIN/python3" ]; then
        local py_rc=3
        "$TERMUX_BIN/python3" -B -c '
import glob, os, select, struct, sys, time

EV_KEY = 0x01
KEY_VOLUMEDOWN = 114
KEY_VOLUMEUP = 115
EVENT_FMT = "qqHHi"
EVENT_SIZE = struct.calcsize(EVENT_FMT)

fds = []
for path in sorted(glob.glob("/dev/input/event*")):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        while True:
            try:
                chunk = os.read(fd, EVENT_SIZE * 32)
                if not chunk:
                    break
            except BlockingIOError:
                break
            except OSError:
                break
        fds.append(fd)
    except OSError:
        pass

if not fds:
    sys.exit(3)

deadline = time.monotonic() + float(sys.argv[1])
while fds:
    rem = deadline - time.monotonic()
    if rem <= 0:
        break
    try:
        readable, _, _ = select.select(fds, [], [], rem)
    except InterruptedError:
        continue
    for fd in list(fds):
        if fd not in readable:
            continue
        try:
            data = os.read(fd, EVENT_SIZE * 64)
        except BlockingIOError:
            continue
        except OSError:
            fds.remove(fd)
            try:
                os.close(fd)
            except OSError:
                pass
            continue
        if not data:
            fds.remove(fd)
            try:
                os.close(fd)
            except OSError:
                pass
            continue
        usable = len(data) - (len(data) % EVENT_SIZE)
        for off in range(0, usable, EVENT_SIZE):
            _, _, ev_type, ev_code, ev_val = struct.unpack_from(EVENT_FMT, data, off)
            if ev_type == EV_KEY and ev_val == 1:
                if ev_code == KEY_VOLUMEUP:
                    sys.exit(0)
                elif ev_code == KEY_VOLUMEDOWN:
                    sys.exit(1)

sys.exit(2)
' "$timeout_sec" 2>/dev/null
        py_rc=$?
        [ "$py_rc" -ne 3 ] && return "$py_rc"
    fi

    local getevent_bin=""
    if [ -x /system/bin/getevent ]; then
        getevent_bin="/system/bin/getevent"
    else
        getevent_bin=$(command -v getevent 2>/dev/null || true)
    fi
    if [ -z "$getevent_bin" ] || ! command -v timeout >/dev/null 2>&1; then
        return 3
    fi

    local vol_devs="" cur_dev="" lp_out line
    lp_out=$("$getevent_bin" -lp 2>/dev/null || true)
    while IFS= read -r line; do
        case "$line" in
            "add device "*": "*)
                cur_dev="${line#*: }"
                ;;
            *KEY_VOLUMEUP*|*KEY_VOLUMEDOWN*)
                if [ -n "$cur_dev" ]; then
                    case " $vol_devs " in
                        *" $cur_dev "*) ;;
                        *) vol_devs="${vol_devs:+$vol_devs }$cur_dev" ;;
                    esac
                fi
                ;;
        esac
    done << EOF
$lp_out
EOF

    local res_file="${TMPDIR:-/dev/tmp}/.agy_vol.$$"
    local now_sec deadline rem pids="" dev
    rm -f "$res_file"
    now_sec=$(date +%s 2>/dev/null || echo 0)
    deadline=$((now_sec + timeout_sec))

    if [ -n "$vol_devs" ]; then
        for dev in $vol_devs; do
            (
                while [ ! -s "$res_file" ]; do
                    now_sec=$(date +%s 2>/dev/null || echo 0)
                    rem=$((deadline - now_sec))
                    [ "$rem" -gt 0 ] || break
                    line=$(timeout "$rem" "$getevent_bin" -lqc 1 "$dev" 2>/dev/null) || break
                    case "$line" in
                        *KEY_VOLUMEUP*" DOWN"*|*KEY_VOLUMEUP*" 00000001"*)
                            echo "UP" > "$res_file"
                            break
                            ;;
                        *KEY_VOLUMEDOWN*" DOWN"*|*KEY_VOLUMEDOWN*" 00000001"*)
                            echo "DOWN" > "$res_file"
                            break
                            ;;
                    esac
                done
            ) </dev/null >/dev/null 2>&1 &
            pids="${pids:+$pids }$!"
        done
    else
        (
            while [ ! -s "$res_file" ]; do
                now_sec=$(date +%s 2>/dev/null || echo 0)
                rem=$((deadline - now_sec))
                [ "$rem" -gt 0 ] || break
                line=$(timeout "$rem" "$getevent_bin" -lqc 1 2>/dev/null) || break
                case "$line" in
                    *KEY_VOLUMEUP*" DOWN"*|*KEY_VOLUMEUP*" 00000001"*)
                        echo "UP" > "$res_file"
                        break
                        ;;
                    *KEY_VOLUMEDOWN*" DOWN"*|*KEY_VOLUMEDOWN*" 00000001"*)
                        echo "DOWN" > "$res_file"
                        break
                        ;;
                esac
            done
        ) </dev/null >/dev/null 2>&1 &
        pids="$!"
    fi

    while [ ! -s "$res_file" ]; do
        now_sec=$(date +%s 2>/dev/null || echo 0)
        [ "$now_sec" -lt "$deadline" ] || break
        sleep 0.2 2>/dev/null || sleep 1
    done

    local wp
    for wp in $pids; do
        pkill -P "$wp" 2>/dev/null || true
        kill "$wp" 2>/dev/null || true
        wait "$wp" 2>/dev/null || true
    done

    local choice=""
    [ -s "$res_file" ] && choice=$(cat "$res_file" 2>/dev/null)
    rm -f "$res_file"
    case "$choice" in
        UP) return 0 ;;
        DOWN) return 1 ;;
        *) return 2 ;;
    esac
}

_pgrep_exec() {
    if [ -x "$TERMUX_BIN/pgrep" ]; then
        "$TERMUX_BIN/pgrep" "$@"
    else
        pgrep "$@"
    fi
}

_pkill_exec() {
    if [ -x "$TERMUX_BIN/pkill" ]; then
        "$TERMUX_BIN/pkill" "$@"
    else
        pkill "$@"
    fi
}

_is_agy_active_now() {
    if TMUX_TMPDIR="$TERMUX_USR/var/run" "$TERMUX_BIN/tmux" has-session -t agy 2>/dev/null; then
        return 0
    fi
    if _pgrep_exec -f '[a]gy_boot_service\.sh --runner' >/dev/null 2>&1; then
        return 0
    fi
    if _pgrep_exec -f '[a]gy(\.va39|-va39)? --remote-control' >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "$TERMUX_BIN/flock" ] && [ -f "$TERMUX_USR/var/run/agy_root.lock" ] && \
       ! "$TERMUX_BIN/flock" -n -s "$TERMUX_USR/var/run/agy_root.lock" true 2>/dev/null; then
        return 0
    fi
    return 1
}

_stop_agy_and_wait() {
    if [ -x "$TERMUX_BIN/bash" ] && [ -f "$TERMUX_HOME/.local/bin/agy_boot_service.sh" ]; then
        HOME="$TERMUX_HOME" PREFIX="$TERMUX_USR" TMUX_TMPDIR="$TERMUX_USR/var/run" \
            "$TERMUX_BIN/bash" "$TERMUX_HOME/.local/bin/agy_boot_service.sh" --stop </dev/null >/dev/null 2>&1 && return 0
    fi

    TMUX_TMPDIR="$TERMUX_USR/var/run" "$TERMUX_BIN/tmux" kill-session -t agy 2>/dev/null || true
    _pkill_exec -f '[a]gy_boot_service\.sh --runner' 2>/dev/null || true
    _pkill_exec -f '[a]gy(\.va39|-va39)? --remote-control' 2>/dev/null || true
    _pkill_exec -f '[c]leanup_offline_instances\.py' 2>/dev/null || true
    _pkill_exec -f '[s]ync_gemini_perms\.py' 2>/dev/null || true

    local i=0
    while [ "$i" -lt 8 ]; do
        _is_agy_active_now || return 0
        sleep 0.5 2>/dev/null || sleep 1
        i=$((i + 1))
    done

    TMUX_TMPDIR="$TERMUX_USR/var/run" "$TERMUX_BIN/tmux" kill-session -t agy 2>/dev/null || true
    _pkill_exec -9 -f '[a]gy_boot_service\.sh --runner' 2>/dev/null || true
    _pkill_exec -9 -f '[a]gy(\.va39|-va39)? --remote-control' 2>/dev/null || true
    _pkill_exec -9 -f '[c]leanup_offline_instances\.py' 2>/dev/null || true
    _pkill_exec -9 -f '[s]ync_gemini_perms\.py' 2>/dev/null || true

    i=0
    while [ "$i" -lt 6 ]; do
        _is_agy_active_now || return 0
        sleep 0.5 2>/dev/null || sleep 1
        i=$((i + 1))
    done
    return 1
}

_launch_remote_control_detached() {
    local tver skip_env
    tver=$(dumpsys package com.termux 2>/dev/null | sed -n 's/.*versionName=//p' | head -n 1 | tr -d '\r')
    tver="${tver:-0.118.3}"
    skip_env=1
    [ "${ENV_RC:-0}" -ne 0 ] && skip_env=0

    if [ -x "$TERMUX_BIN/python3" ]; then
        "$TERMUX_BIN/python3" -B -c '
import os, subprocess, sys
home, usr, bin_dir, tver, skip_env = sys.argv[1:6]
env = {
    "HOME": home,
    "PREFIX": usr,
    "SHELL": os.path.join(bin_dir, "bash"),
    "TMUX_TMPDIR": os.path.join(usr, "var", "run"),
    "TMPDIR": os.path.join(usr, "tmp"),
    "USER": "root",
    "LANG": "en_US.UTF-8",
    "PYTHONDONTWRITEBYTECODE": "1",
    "TERMUX_VERSION": tver,
    "AGY_FROM_FLASH": "1",
    "AGY_FORCE_START": "1",
    "AGY_SKIP_ENV_CHECK": skip_env,
    "PATH": f"{bin_dir}:{home}/.local/bin:/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk",
}
preload = os.path.join(usr, "lib", "libtermux-exec-ld-preload.so")
if os.path.isfile(preload):
    env["LD_PRELOAD"] = preload
subprocess.Popen(
    [os.path.join(bin_dir, "bash"), os.path.join(home, ".local", "bin", "agy_boot_service.sh"), "--force"],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    cwd=home,
    close_fds=True,
    start_new_session=True,
    env=env,
)
' "$TERMUX_HOME" "$TERMUX_USR" "$TERMUX_BIN" "$tver" "$skip_env" >/dev/null 2>&1 && return 0
    fi

    (
        exec </dev/null >/dev/null 2>&1
        [ -n "${OUTFD:-}" ] && eval "exec ${OUTFD}>&-" 2>/dev/null || true
        for _fd in 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            eval "exec ${_fd}>&-" 2>/dev/null || true
        done
        unset ASH_STANDALONE LD_LIBRARY_PATH MODPATH ZIPFILE OUTFD NVBASE EXTPATH TMP
        export HOME="$TERMUX_HOME"
        cd "$TERMUX_HOME" 2>/dev/null || cd / 2>/dev/null || true
        export PREFIX="$TERMUX_USR"
        export SHELL="$TERMUX_BIN/bash"
        export TMUX_TMPDIR="$TERMUX_USR/var/run"
        export TMPDIR="$TERMUX_USR/tmp"
        export USER="root"
        export LANG="en_US.UTF-8"
        export PYTHONDONTWRITEBYTECODE=1
        export TERMUX_VERSION="$tver"
        export AGY_FROM_FLASH="1"
        export AGY_FORCE_START="1"
        export AGY_SKIP_ENV_CHECK="$skip_env"
        export PATH="$TERMUX_BIN:$TERMUX_HOME/.local/bin:/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk"
        [ -f "$TERMUX_USR/lib/libtermux-exec-ld-preload.so" ] && export LD_PRELOAD="$TERMUX_USR/lib/libtermux-exec-ld-preload.so"
        if command -v setsid >/dev/null 2>&1; then
            setsid "$TERMUX_BIN/bash" "$TERMUX_HOME/.local/bin/agy_boot_service.sh" --force </dev/null >/dev/null 2>&1 &
        else
            "$TERMUX_BIN/bash" "$TERMUX_HOME/.local/bin/agy_boot_service.sh" --force </dev/null >/dev/null 2>&1 &
        fi
    ) </dev/null >/dev/null 2>&1
}

_agy_runtime_ready() {
    local p sz
    for p in "$TERMUX_BIN/agy.va39" "$TERMUX_BIN/agy-va39" "$TERMUX_HOME/.local/bin/agy.va39" "$TERMUX_HOME/.local/bin/agy-va39"; do
        [ -x "$p" ] && return 0
    done
    for p in "$TERMUX_BIN/agy" "$TERMUX_HOME/.local/bin/agy"; do
        if [ -x "$p" ]; then
            sz=$(/system/bin/stat -c "%s" "$p" 2>/dev/null || wc -c < "$p" 2>/dev/null || echo 0)
            [ "${sz:-0}" -ge 2097152 ] && return 0
        fi
    done
    return 1
}

_set_remote_control_flag() {
    local _val="$1"
    local _rc_file="$CONFIG_DIR/remote_control"
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    printf '%s\n' "$_val" > "${_rc_file}.tmp.$$" 2>/dev/null && \
        mv -f "${_rc_file}.tmp.$$" "$_rc_file" 2>/dev/null || \
        rm -f "${_rc_file}.tmp.$$" 2>/dev/null
    chmod 644 "$_rc_file" 2>/dev/null || true
    chown "$TERMUX_UID:$TERMUX_GID" "$TERMUX_HOME/.gemini" "$CONFIG_DIR" "$_rc_file" 2>/dev/null || true
    if [ -n "$TERMUX_CTX" ] && [ -x /system/bin/chcon ]; then
        /system/bin/chcon "$TERMUX_CTX" "$TERMUX_HOME/.gemini" "$CONFIG_DIR" "$_rc_file" 2>/dev/null || true
    fi
}

_is_rc_disabled_now() {
    local _rc_file="$CONFIG_DIR/remote_control" _rv=""
    [ -r "$_rc_file" ] && _rv=$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "$_rc_file" 2>/dev/null)
    [ "$_rv" = "0" ]
}

if [ "${BOOTMODE:-false}" != "true" ]; then
    ui_print "$(agy_msg cust_recovery_skip)"
elif [ "${ENV_RC:-0}" -eq 2 ] || [ ! -x "$TERMUX_BIN/bash" ] || [ ! -x "$TERMUX_BIN/tmux" ] || ! _agy_runtime_ready; then
    ui_print "$(agy_msg cust_deferred_offline)"
else
    _agy_running_now=0
    _is_agy_active_now && _agy_running_now=1

    ui_print ""
    if [ "$_agy_running_now" -eq 1 ]; then
        ui_print "$(agy_msg cust_ask_restart)"
        ui_print "$(agy_msg cust_vol_up_restart)"
        ui_print "$(agy_msg cust_vol_down_keep)"
        ui_print "$(agy_msg cust_vol_timeout_hint_keep)"
    else
        ui_print "$(agy_msg cust_ask_start)"
        ui_print "$(agy_msg cust_vol_up_start)"
        ui_print "$(agy_msg cust_vol_down_later)"
        ui_print "$(agy_msg cust_vol_timeout_hint)"
    fi

    _choose_vol_key 15
    _vol_rc=$?
    if [ "$_vol_rc" -eq 0 ]; then
        _set_remote_control_flag 1
        ui_print "$(agy_msg cust_yes_starting)"
        if [ "$_agy_running_now" -eq 1 ]; then
            ui_print "$(agy_msg cust_stopping_old)"
            if ! _stop_agy_and_wait; then
                ui_print "$(agy_msg cust_warn_old_slow)"
            fi
            if [ -x "$TERMUX_BIN/python3" ] && [ -f "$TERMUX_HOME/.local/bin/sync_gemini_perms.py" ]; then
                "$TERMUX_BIN/python3" -B "$TERMUX_HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 || true
            fi
        fi
        _has_oauth_token=0
        if [ -s "$TERMUX_HOME/.gemini/antigravity-cli/antigravity-oauth-token" ] && grep -qE '"(access|refresh)_token"[[:space:]]*:[[:space:]]*"[^"]+' "$TERMUX_HOME/.gemini/antigravity-cli/antigravity-oauth-token" 2>/dev/null; then
            _has_oauth_token=1
        else
            ui_print "$(agy_msg cust_hint_no_token_wait)"
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [customize] User opted to start Remote Control during module install." >> "$TERMUX_HOME/.gemini/antigravity-cli/boot.log" 2>/dev/null || true
        _launch_remote_control_detached
        _started_now=0
        for _w in 1 2 3 4 5 6 7 8; do
            if TMUX_TMPDIR="$TERMUX_USR/var/run" "$TERMUX_BIN/tmux" has-session -t agy 2>/dev/null; then
                _started_now=1
                break
            fi
            sleep 1
        done
        if [ "$_started_now" -eq 1 ]; then
            if [ "$_has_oauth_token" -eq 1 ]; then
                ui_print "$(agy_msg cust_ok_started)"
                ui_print "$(agy_msg cust_hint_started_use)"
            else
                ui_print "$(agy_msg cust_ok_standby_ready)"
                ui_print "$(agy_msg cust_hint_standby_login)"
            fi
        else
            ui_print "$(agy_msg cust_hint_scheduled)"
            ui_print "$(agy_msg cust_hint_check_log)"
        fi
    elif [ "$_vol_rc" -eq 1 ]; then
        _set_remote_control_flag 0
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [customize] User opted to disable Remote Control during module install." >> "$TERMUX_HOME/.gemini/antigravity-cli/boot.log" 2>/dev/null || true
        if [ "$_agy_running_now" -eq 1 ]; then
            ui_print "$(agy_msg cust_stopping_old)"
            if ! _stop_agy_and_wait; then
                ui_print "$(agy_msg cust_warn_old_slow)"
            fi
            if [ -x "$TERMUX_BIN/python3" ] && [ -f "$TERMUX_HOME/.local/bin/sync_gemini_perms.py" ]; then
                "$TERMUX_BIN/python3" -B "$TERMUX_HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 || true
            fi
            ui_print "$(agy_msg cust_choice_no_stopped)"
        else
            ui_print "$(agy_msg cust_choice_no)"
        fi
    elif [ "$_vol_rc" -eq 2 ]; then
        if [ "$_agy_running_now" -eq 1 ]; then
            ui_print "$(agy_msg cust_choice_timeout_keep)"
        else
            _set_remote_control_flag 0
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [customize] Timed out on prompt; defaulted Remote Control to disabled." >> "$TERMUX_HOME/.gemini/antigravity-cli/boot.log" 2>/dev/null || true
            ui_print "$(agy_msg cust_choice_timeout)"
        fi
    elif [ "$_vol_rc" -eq 4 ]; then
        ui_print "$(agy_msg cust_choice_keep)"
    else
        ui_print "$(agy_msg cust_choice_no_ev)"
    fi
fi

_mod_ver=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1 | tr -d '\r\n')
ui_print "****************************************"
ui_print "$(agy_msg cust_done_title "${_mod_ver:-v1.0.1}")"
if _is_rc_disabled_now; then
    ui_print "$(agy_msg cust_done_sub_disabled)"
    ui_print "$(agy_msg cust_done_sub_disabled_hint)"
else
    ui_print "$(agy_msg cust_done_sub)"
    ui_print "* $HOSTNAME"
fi
ui_print "****************************************"
