#!/system/bin/sh
MODDIR=${0%/*}
LOGFILE="/data/adb/agy_boot.log"
TERMUX_HOME="/data/data/com.termux/files/home"

exec > "$LOGFILE" 2>&1
chmod 644 "$LOGFILE" 2>/dev/null || true

I18N_SCRIPT="$MODDIR/files/agy_i18n.sh"
[ ! -f "$I18N_SCRIPT" ] && I18N_SCRIPT="$TERMUX_HOME/.local/bin/agy_i18n.sh"
if [ -f "$I18N_SCRIPT" ]; then
    . "$I18N_SCRIPT"
    agy_i18n_init "$TERMUX_HOME"
else
    agy_i18n_refresh_cache() { :; }
    agy_i18n_init() { :; }
    agy_msg() { local _k="$1"; shift; printf '%s%s\n' "$_k" "${*:+: $*}"; }
fi

echo "=========================================="
echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_started "$$" "$(id -u)")"

# 1. Wait for Android boot completion
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_boot_completed)"

# 2. Wait for CE user storage unlock
while [ "$(getprop sys.user.0.ce_available)" != "true" ] || [ ! -x /data/data/com.termux/files/usr/bin/sh ]; do
    sleep 2
done
agy_i18n_refresh_cache "$TERMUX_HOME"
agy_i18n_init "$TERMUX_HOME" 1
echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_ce_unlocked)"

# 3. Wait for network connectivity
echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_wait_net)"
for i in $(seq 1 30); do
    if /system/bin/ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || [ -n "$(getprop net.dns1)" ]; then
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_net_ready)"
        break
    fi
    sleep 2
done

# 4. System settle delay
sleep 3

# 5. Setup Termux and root environment variables
export HOME="$TERMUX_HOME"
export PREFIX="/data/data/com.termux/files/usr"
export SHELL="$PREFIX/bin/bash"
export TMUX_TMPDIR="$PREFIX/var/run"
export TMPDIR="$PREFIX/tmp"
export USER="root"
export LANG="en_US.UTF-8"
TERMUX_VERSION=$(dumpsys package com.termux 2>/dev/null | sed -n 's/.*versionName=//p' | head -n 1 | tr -d '\r')
export TERMUX_VERSION="${TERMUX_VERSION:-0.118.3}"
export PATH="$PREFIX/bin:$TERMUX_HOME/.local/bin:/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk:$PATH"
if [ -f "$PREFIX/lib/libtermux-exec-ld-preload.so" ]; then
    export LD_PRELOAD="$PREFIX/lib/libtermux-exec-ld-preload.so"
fi

# 6. Boot-time environment verification & auto-provisioning
export PYTHONDONTWRITEBYTECODE=1
ENV_HELPER="$TERMUX_HOME/.local/bin/ensure_antigravity_env.sh"
ENV_RC=0
if [ -x "$ENV_HELPER" ] || [ -f "$ENV_HELPER" ]; then
    /system/bin/sh "$ENV_HELPER" --boot
    ENV_RC=$?
    if [ "$ENV_RC" -eq 0 ]; then
        export AGY_SKIP_ENV_CHECK=1
    else
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_env_warn "$ENV_RC")"
    fi
fi

# 7. Detect device model slug and update config.json
get_device_slug() {
    local name="$(getprop ro.product.marketname)"
    [ -z "$name" ] && name="$(getprop ro.product.model)"
    [ -z "$name" ] && name="$(getprop ro.product.device)"
    echo "$name" | tr "[:upper:]" "[:lower:]" | sed -E "s/[^a-z0-9]+/-/g" | sed -E "s/^-+|-+$//g"
}
DEVICE_SLUG="$(get_device_slug)"
[ -z "$DEVICE_SLUG" ] && DEVICE_SLUG="phone"
HOSTNAME="localhost-$DEVICE_SLUG"
echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_hostname "$HOSTNAME")"

CONFIG_DIR="$TERMUX_HOME/.gemini/config"
CONFIG_FILE="$CONFIG_DIR/config.json"
mkdir -p "$CONFIG_DIR"
if [ -x "$PREFIX/bin/python3" ]; then
    "$PREFIX/bin/python3" -B -c "
import json, os
loc = os.environ.get('AGY_LOCALE', 'en')
msgs = {
    'zh-TW': ('[service] 已校正 config.json 名稱為: $HOSTNAME', '[service] 校正 config.json 出錯:'),
    'zh-CN': ('[service] 已校正 config.json 名称为: $HOSTNAME', '[service] 校正 config.json 出错:'),
    'ja': ('[service] config.json のホスト名を更新しました: $HOSTNAME', '[service] config.json 更新エラー:'),
    'en': ('[service] Updated config.json hostname: $HOSTNAME', '[service] Failed to update config.json:'),
}
ok_m, err_m = msgs.get(loc, msgs['en'])
path = '$CONFIG_FILE'
try:
    cfg = {}
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            raw = f.read().strip()
        if raw:
            loaded = json.loads(raw)
            if isinstance(loaded, dict):
                cfg = loaded
    if cfg.get('userSettings', {}).get('cliRemoteControlHostname') != '$HOSTNAME':
        cfg.setdefault('userSettings', {})['cliRemoteControlHostname'] = '$HOSTNAME'
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(cfg, f, indent=2)
        print(ok_m)
except Exception as e:
    print(err_m, e)
"
    TERMUX_UID=$(/system/bin/stat -c "%u" "$TERMUX_HOME" 2>/dev/null || echo 10466)
    TERMUX_GID=$(/system/bin/stat -c "%g" "$TERMUX_HOME" 2>/dev/null || echo "$TERMUX_UID")
    TERMUX_CTX=$(/system/bin/stat -c "%C" "$TERMUX_HOME" 2>/dev/null || true)
    chmod 644 "$CONFIG_FILE" 2>/dev/null || true
    chown "$TERMUX_UID:$TERMUX_GID" "$TERMUX_HOME/.gemini" "$CONFIG_DIR" "$CONFIG_FILE" 2>/dev/null || true
    if [ -n "$TERMUX_CTX" ] && [ -x /system/bin/chcon ]; then
        /system/bin/chcon "$TERMUX_CTX" "$TERMUX_HOME/.gemini" "$CONFIG_DIR" "$CONFIG_FILE" 2>/dev/null || true
    fi
    if [ -f "$TERMUX_HOME/.local/bin/sync_gemini_perms.py" ]; then
        "$PREFIX/bin/python3" -B "$TERMUX_HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 || true
    fi
fi

# 8. Check persistent Remote Control toggle before launching daemon
RC_FLAG_FILE="$CONFIG_DIR/remote_control"
RC_FLAG=""
if [ -r "$RC_FLAG_FILE" ]; then
    RC_FLAG=$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "$RC_FLAG_FILE" 2>/dev/null)
fi
if [ "$RC_FLAG" = "0" ]; then
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_rc_disabled)"
    exit 0
fi

# 9. Launch remote-control daemon as root
echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_launching "$(id -u)")"
if [ -x "$PREFIX/bin/bash" ]; then
    "$PREFIX/bin/bash" "$TERMUX_HOME/.local/bin/agy_boot_service.sh"
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_launch_done "$?")"
else
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg svc_err_no_bash)"
fi
