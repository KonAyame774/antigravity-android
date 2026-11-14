#!/system/bin/sh
# Antigravity CLI & wallentx/antigravity-cli-termux 環境偵測與自動補全腳本
# 支援在 KernelSU / Magisk / APatch 刷入階段 (customize.sh) 或開機階段 (service.sh) 執行。

TERMUX_ROOT="${TERMUX_ROOT:-/data/data/com.termux/files}"
TERMUX_HOME="${TERMUX_HOME:-$TERMUX_ROOT/home}"
TERMUX_USR="${TERMUX_USR:-$TERMUX_ROOT/usr}"
TERMUX_BIN="${TERMUX_BIN:-$TERMUX_USR/bin}"

AGY_REPO="${AGY_REPO:-wallentx/antigravity-cli-termux}"
AGY_INSTALL_URL="${AGY_INSTALL_URL:-https://github.com/$AGY_REPO/releases/latest/download/antigravity-termux-standalone.tar.gz}"

_env_load_i18n() {
    if command -v agy_msg >/dev/null 2>&1; then
        return 0
    fi
    local _self_dir="." _cand
    case "${0:-}" in
        */*) _self_dir="${0%/*}" ;;
    esac
    for _cand in \
        "${MODPATH:+$MODPATH/files/agy_i18n.sh}" \
        "$_self_dir/agy_i18n.sh" \
        "$TERMUX_HOME/.local/bin/agy_i18n.sh"; do
        if [ -n "$_cand" ] && [ -f "$_cand" ]; then
            . "$_cand"
            agy_i18n_init "$TERMUX_HOME"
            return 0
        fi
    done
    agy_msg() {
        local _k="$1"; shift
        if [ "$#" -gt 0 ]; then
            printf '%s: %s\n' "$_k" "$*"
        else
            printf '%s\n' "$_k"
        fi
    }
}
_env_load_i18n

_env_log() {
    if [ -n "${AGY_ENV_LOG_FN:-}" ]; then
        "$AGY_ENV_LOG_FN" "$1"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    fi
}

_detect_termux_version() {
    local ver=""
    if [ -n "${TERMUX_VERSION:-}" ]; then
        echo "$TERMUX_VERSION"
        return 0
    fi
    if command -v dumpsys >/dev/null 2>&1; then
        ver=$(dumpsys package com.termux 2>/dev/null | sed -n 's/.*versionName=//p' | head -n 1 | tr -d '\r')
    fi
    echo "${ver:-0.118.3}"
}

_init_termux_meta() {
    TERMUX_UID=$(/system/bin/stat -c '%u' "$TERMUX_HOME" 2>/dev/null || echo 10466)
    TERMUX_GID=$(/system/bin/stat -c '%g' "$TERMUX_HOME" 2>/dev/null || echo "$TERMUX_UID")
    TERMUX_CTX=$(/system/bin/stat -c '%C' "$TERMUX_HOME" 2>/dev/null || true)
    TERMUX_VERSION=$(_detect_termux_version)
    export HOME="$TERMUX_HOME"
    export PREFIX="$TERMUX_USR"
    export TMPDIR="$TERMUX_USR/tmp"
    export TERMUX_VERSION
    mkdir -p "$TMPDIR" 2>/dev/null || true
    if [ "$(id -u)" -eq 0 ]; then
        chown "$TERMUX_UID:$TERMUX_GID" "$TMPDIR" 2>/dev/null || true
        [ -n "$TERMUX_CTX" ] && [ -x /system/bin/chcon ] && /system/bin/chcon "$TERMUX_CTX" "$TMPDIR" 2>/dev/null || true
    fi
}

_fix_path_perms() {
    local target="$1"
    local rec="${2:-0}"
    [ -e "$target" ] || [ -L "$target" ] || return 0
    [ "$(id -u)" -eq 0 ] || return 0
    if [ "$rec" = "1" ]; then
        chown -Rh "$TERMUX_UID:$TERMUX_GID" "$target" 2>/dev/null || chown -R "$TERMUX_UID:$TERMUX_GID" "$target" 2>/dev/null || true
        if [ -n "${TERMUX_CTX:-}" ] && [ -x /system/bin/chcon ]; then
            /system/bin/chcon -Rh "$TERMUX_CTX" "$target" 2>/dev/null || /system/bin/chcon -R "$TERMUX_CTX" "$target" 2>/dev/null || true
        fi
    else
        chown -h "$TERMUX_UID:$TERMUX_GID" "$target" 2>/dev/null || chown "$TERMUX_UID:$TERMUX_GID" "$target" 2>/dev/null || true
        if [ -n "${TERMUX_CTX:-}" ] && [ -x /system/bin/chcon ]; then
            /system/bin/chcon -h "$TERMUX_CTX" "$target" 2>/dev/null || /system/bin/chcon "$TERMUX_CTX" "$target" 2>/dev/null || true
        fi
    fi
}

_shell_quote_args() {
    local out="" arg rest
    for arg in "$@"; do
        case "$arg" in
            *"'"*)
                rest="$arg"
                arg=""
                while :; do
                    case "$rest" in
                        *"'"*)
                            arg="${arg}${rest%%\'*}'\\''"
                            rest="${rest#*\'}"
                            ;;
                        *)
                            arg="${arg}${rest}"
                            break
                            ;;
                    esac
                done
                ;;
        esac
        out="${out:+$out }'$arg'"
    done
    printf '%s' "$out"
}

# Termux 的 apt-get / pkg 禁止以 uid=0 執行；降權為 Termux UID 並保留 inet (3003) 群組讓網路正常
_run_as_termux_net() {
    local preload="" cert_file="" cert_dir="" path_env
    path_env="$TERMUX_BIN:/system/bin:/system/xbin:/vendor/bin"
    [ -f "$TERMUX_USR/lib/libtermux-exec-ld-preload.so" ] && preload="$TERMUX_USR/lib/libtermux-exec-ld-preload.so"
    if [ -s "$TERMUX_USR/etc/tls/cert.pem" ]; then
        cert_file="$TERMUX_USR/etc/tls/cert.pem"
    elif [ -d "/apex/com.android.conscrypt/cacerts" ]; then
        cert_dir="/apex/com.android.conscrypt/cacerts"
    elif [ -d "/system/etc/security/cacerts" ]; then
        cert_dir="/system/etc/security/cacerts"
    fi

    if [ "$(id -u)" -ne 0 ]; then
        env -i \
            PATH="$path_env" \
            PREFIX="$TERMUX_USR" \
            HOME="$TERMUX_HOME" \
            TMPDIR="$TERMUX_USR/tmp" \
            TERMUX_VERSION="$TERMUX_VERSION" \
            DEBIAN_FRONTEND="noninteractive" \
            LANG="${LANG:-en_US.UTF-8}" \
            ${preload:+LD_PRELOAD="$preload"} \
            ${cert_file:+SSL_CERT_FILE="$cert_file"} \
            ${cert_dir:+SSL_CERT_DIR="$cert_dir"} \
            "$@"
        return $?
    fi

    if [ -x "$TERMUX_BIN/setpriv" ] && [ -x "$TERMUX_BIN/env" ]; then
        "$TERMUX_BIN/setpriv" \
            --reuid="$TERMUX_UID" \
            --regid="$TERMUX_GID" \
            --groups="3003,$TERMUX_GID" \
            "$TERMUX_BIN/env" -i \
            PATH="$path_env" \
            PREFIX="$TERMUX_USR" \
            HOME="$TERMUX_HOME" \
            TMPDIR="$TERMUX_USR/tmp" \
            TERMUX_VERSION="$TERMUX_VERSION" \
            DEBIAN_FRONTEND="noninteractive" \
            LANG="${LANG:-en_US.UTF-8}" \
            ${preload:+LD_PRELOAD="$preload"} \
            ${cert_file:+SSL_CERT_FILE="$cert_file"} \
            ${cert_dir:+SSL_CERT_DIR="$cert_dir"} \
            "$@"
        return $?
    fi

    if [ -x "$TERMUX_BIN/python3" ]; then
        "$TERMUX_BIN/python3" -c '
import os, sys
uid, gid = int(sys.argv[1]), int(sys.argv[2])
os.setgroups([3003, gid])
os.setgid(gid)
os.setuid(uid)
env = {
    "PATH": sys.argv[3],
    "PREFIX": sys.argv[4],
    "HOME": sys.argv[5],
    "TMPDIR": sys.argv[6],
    "TERMUX_VERSION": sys.argv[7],
    "DEBIAN_FRONTEND": "noninteractive",
    "LANG": "en_US.UTF-8",
}
if sys.argv[8]:
    env["LD_PRELOAD"] = sys.argv[8]
if sys.argv[9]:
    env["SSL_CERT_FILE"] = sys.argv[9]
if sys.argv[10]:
    env["SSL_CERT_DIR"] = sys.argv[10]
os.execvpe(sys.argv[11], sys.argv[11:], env)
' "$TERMUX_UID" "$TERMUX_GID" "$path_env" "$TERMUX_USR" "$TERMUX_HOME" "$TERMUX_USR/tmp" "$TERMUX_VERSION" "$preload" "$cert_file" "$cert_dir" "$@"
        return $?
    fi

    if command -v su >/dev/null 2>&1 && su -g "$TERMUX_GID" -G 3003 "$TERMUX_UID" -c true >/dev/null 2>&1; then
        local cmd_q
        cmd_q=$(_shell_quote_args "$@")
        su -g "$TERMUX_GID" -G 3003 "$TERMUX_UID" -c \
            "export PATH='$path_env' PREFIX='$TERMUX_USR' HOME='$TERMUX_HOME' TMPDIR='$TERMUX_USR/tmp' TERMUX_VERSION='$TERMUX_VERSION' DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 ${preload:+LD_PRELOAD='$preload'} ${cert_file:+SSL_CERT_FILE='$cert_file'} ${cert_dir:+SSL_CERT_DIR='$cert_dir'}; $cmd_q"
        return $?
    fi

    _env_log "$(agy_msg env_err_no_priv)"
    return 1
}

_pkg_installed() {
    "$TERMUX_BIN/dpkg-query" -W -f='${Status}\n' "$1" 2>/dev/null | grep -q "install ok installed"
}

_check_network() {
    if [ -x "$TERMUX_BIN/curl" ]; then
        if _run_as_termux_net "$TERMUX_BIN/curl" -fsSI --connect-timeout 3 --max-time 6 https://github.com >/dev/null 2>&1; then
            return 0
        fi
        # 若 ca-certificates 尚未安裝導致 HTTPS 憑證失敗，僅用於連通性探測一次
        if [ ! -s "$TERMUX_USR/etc/tls/cert.pem" ] && _run_as_termux_net "$TERMUX_BIN/curl" -kfsSI --connect-timeout 3 --max-time 6 https://github.com >/dev/null 2>&1; then
            return 0
        fi
    fi
    /system/bin/ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || /system/bin/ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1
}

_ensure_resolv_conf() {
    local resolv="$TERMUX_USR/etc/resolv.conf"
    local resolv_dir
    resolv_dir=$(dirname "$resolv")
    if [ ! -d "$resolv_dir" ]; then
        mkdir -p "$resolv_dir" 2>/dev/null || return 1
        chmod 755 "$resolv_dir" 2>/dev/null || true
        _fix_path_perms "$resolv_dir" 0
    fi
    if [ -e "$resolv" ] && [ ! -r "$resolv" ] && [ "$(id -u)" -ne 0 ]; then
        _env_log "$(agy_msg env_warn_resolv_perm)"
        return 0
    fi
    if [ -L "$resolv" ] && [ ! -s "$resolv" ]; then
        rm -f "$resolv" 2>/dev/null || true
    fi
    if [ ! -s "$resolv" ] || ! grep -qE '^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F:.]+' "$resolv" 2>/dev/null; then
        {
            local dns1 dns2
            dns1=$(getprop net.dns1 2>/dev/null | tr -d '\r')
            dns2=$(getprop net.dns2 2>/dev/null | tr -d '\r')
            [ -n "$dns1" ] && echo "nameserver $dns1"
            [ -n "$dns2" ] && echo "nameserver $dns2"
            echo "nameserver 8.8.8.8"
            echo "nameserver 8.8.4.4"
        } > "$resolv"
        [ ! -L "$resolv" ] && chmod 644 "$resolv" 2>/dev/null || true
        _fix_path_perms "$resolv" 0
        _env_log "$(agy_msg env_fix_resolv)"
        return 0
    fi
    [ ! -L "$resolv" ] && [ -f "$resolv" ] && chmod 644 "$resolv" 2>/dev/null || true
    _fix_path_perms "$resolv" 0
    return 0
}

_ensure_hosts_file() {
    local target="$1"
    local label="${2:-$target}"
    local parent
    parent=$(dirname "$target")
    if [ ! -d "$parent" ]; then
        mkdir -p "$parent" 2>/dev/null || return 1
        chmod 755 "$parent" 2>/dev/null || true
        _fix_path_perms "$parent" 0
    fi
    if [ -e "$target" ] && [ ! -r "$target" ] && [ "$(id -u)" -ne 0 ]; then
        _env_log "$(agy_msg env_warn_hosts_perm "$label")"
        return 0
    fi
    if [ -L "$target" ] && [ ! -s "$target" ]; then
        rm -f "$target" 2>/dev/null || true
    fi

    local changed=0
    if [ ! -s "$target" ]; then
        {
            echo "127.0.0.1 localhost"
            echo "::1 ip6-localhost"
        } > "$target"
        changed=1
    else
        if ! grep -qE '^[[:space:]]*127\.0\.0\.1[[:space:]]+([^#]*[[:space:]])?localhost([[:space:]]|#|$)' "$target" 2>/dev/null; then
            [ "$(tail -c 1 "$target" 2>/dev/null | wc -l)" -eq 0 ] && printf '\n' >> "$target"
            echo "127.0.0.1 localhost" >> "$target"
            changed=1
        fi
        if ! grep -qE '^[[:space:]]*::1[[:space:]]+([^#]*[[:space:]])?(localhost|ip6-localhost)([[:space:]]|#|$)' "$target" 2>/dev/null; then
            [ "$(tail -c 1 "$target" 2>/dev/null | wc -l)" -eq 0 ] && printf '\n' >> "$target"
            echo "::1 ip6-localhost" >> "$target"
            changed=1
        fi
    fi

    [ ! -L "$target" ] && [ -f "$target" ] && chmod 644 "$target" 2>/dev/null || true
    _fix_path_perms "$target" 0
    if [ "$changed" -eq 1 ]; then
        _AGY_NET_CHANGED=1
        _env_log "$(agy_msg env_fix_hosts "$label")"
    fi
    return 0
}

_ensure_glibc_net_configs() {
    local quiet_ok="${1:-1}"
    local any_changed=0

    if [ -d "$TERMUX_USR/etc" ]; then
        _AGY_NET_CHANGED=0
        _ensure_hosts_file "$TERMUX_USR/etc/hosts" "etc/hosts"
        [ "$_AGY_NET_CHANGED" -eq 1 ] && any_changed=1
    fi

    [ -d "$TERMUX_USR/glibc" ] || return 0

    local glibc_etc="$TERMUX_USR/glibc/etc"
    if [ ! -d "$glibc_etc" ]; then
        mkdir -p "$glibc_etc" 2>/dev/null || return 1
    fi
    chmod 755 "$glibc_etc" 2>/dev/null || true
    _fix_path_perms "$glibc_etc" 0

    # 1. glibc/etc/nsswitch.conf (必須讓 files 優先於 dns，避免斷網或無 local DNS 時 lookup localhost 失敗)
    local glibc_nss="$glibc_etc/nsswitch.conf"
    local nss_changed=0
    if [ -L "$glibc_nss" ] && [ ! -s "$glibc_nss" ]; then
        rm -f "$glibc_nss" 2>/dev/null || true
    fi
    if [ -e "$glibc_nss" ] && [ ! -r "$glibc_nss" ] && [ "$(id -u)" -ne 0 ]; then
        _env_log "$(agy_msg env_warn_nss_perm)"
    elif [ ! -s "$glibc_nss" ]; then
        cat << 'EOF' > "$glibc_nss"
passwd: files
group: files
hosts: files dns
networks: files
services: files
protocols: files
EOF
        nss_changed=1
    elif ! grep -qE '^[[:space:]]*hosts:[[:space:]]*files([[:space:]]|#|$)' "$glibc_nss" 2>/dev/null; then
        if grep -qE '^[[:space:]]*hosts:' "$glibc_nss" 2>/dev/null; then
            grep -vE '^[[:space:]]*hosts:' "$glibc_nss" > "${glibc_nss}.tmp.$$" 2>/dev/null || : > "${glibc_nss}.tmp.$$"
            echo "hosts: files dns" >> "${glibc_nss}.tmp.$$"
            mv -f "${glibc_nss}.tmp.$$" "$glibc_nss"
        else
            [ "$(tail -c 1 "$glibc_nss" 2>/dev/null | wc -l)" -eq 0 ] && printf '\n' >> "$glibc_nss"
            echo "hosts: files dns" >> "$glibc_nss"
        fi
        nss_changed=1
    fi
    [ ! -L "$glibc_nss" ] && [ -f "$glibc_nss" ] && chmod 644 "$glibc_nss" 2>/dev/null || true
    _fix_path_perms "$glibc_nss" 0
    if [ "$nss_changed" -eq 1 ]; then
        _env_log "$(agy_msg env_fix_nss)"
        any_changed=1
    fi

    # 2. glibc/etc/hosts
    _AGY_NET_CHANGED=0
    _ensure_hosts_file "$glibc_etc/hosts" "glibc/etc/hosts"
    [ "$_AGY_NET_CHANGED" -eq 1 ] && any_changed=1

    # 3. glibc/etc/resolv.conf (同步或連結至 Termux etc/resolv.conf)
    local glibc_resolv="$glibc_etc/resolv.conf"
    local main_resolv="$TERMUX_USR/etc/resolv.conf"
    local need_resolv_link=0
    if [ -L "$glibc_resolv" ]; then
        if [ ! -s "$glibc_resolv" ] || ! grep -qE '^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F:.]+' "$glibc_resolv" 2>/dev/null; then
            need_resolv_link=1
        fi
    elif [ -e "$glibc_resolv" ]; then
        if [ ! -r "$glibc_resolv" ] && [ "$(id -u)" -ne 0 ]; then
            _env_log "$(agy_msg env_warn_glibc_resolv_perm)"
        elif [ ! -s "$glibc_resolv" ] || ! grep -qE '^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F:.]+' "$glibc_resolv" 2>/dev/null; then
            need_resolv_link=1
        fi
    else
        need_resolv_link=1
    fi

    if [ "$need_resolv_link" -eq 1 ] && [ -s "$main_resolv" ]; then
        if ln -sf "$main_resolv" "$glibc_resolv" 2>/dev/null; then
            _env_log "$(agy_msg env_fix_glibc_resolv)"
            any_changed=1
        fi
    fi
    [ ! -L "$glibc_resolv" ] && [ -f "$glibc_resolv" ] && chmod 644 "$glibc_resolv" 2>/dev/null || true
    _fix_path_perms "$glibc_resolv" 0

    if [ "$any_changed" -eq 0 ] && [ "$quiet_ok" -eq 0 ]; then
        _env_log "$(agy_msg env_ok_glibc_net)"
    fi
    return 0
}

_fix_apt_post_install_perms() {
    local p
    for p in "$TERMUX_USR/etc" "$TERMUX_USR/var" "$TERMUX_USR/glibc" "$TERMUX_USR/bin" "$TERMUX_USR/lib" "$TERMUX_USR/share"; do
        [ -e "$p" ] && _fix_path_perms "$p" 1
    done
    # 修正任何殘留 root 擁有的套件檔 (避開運行中的 tmux socket)
    local find_bin="find"
    [ -x "$TERMUX_BIN/find" ] && find_bin="$TERMUX_BIN/find"
    "$find_bin" "$TERMUX_USR" ! -user "$TERMUX_UID" ! -path "$TERMUX_USR/var/run/tmux-*" ! -path "$TERMUX_USR/tmp/dbus-*" -exec chown -h "$TERMUX_UID:$TERMUX_GID" {} \; 2>/dev/null || true
}

_install_pkg_batch() {
    if [ $# -eq 0 ]; then
        return 0
    fi
    _env_log "$(agy_msg env_install_pkgs "$*")"
    _run_as_termux_net "$TERMUX_BIN/apt-get" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y --no-install-recommends "$@"
}

_check_agy_binary() {
    local bin="$1"
    [ -x "$bin" ] || return 1
    local resolved dir sz preload=""
    resolved=$(readlink -f "$bin" 2>/dev/null || echo "$bin")
    dir=$(dirname "$resolved")
    sz=$(wc -c < "$resolved" 2>/dev/null || echo 0)

    # 若是 wallentx C 啟動器 (<2MiB)，必須同時有可執行的 agy.va39 與 glibc loader
    if [ "$sz" -lt 2097152 ]; then
        [ -x "$dir/agy.va39" ] || return 2
        [ -x "$TERMUX_USR/glibc/lib/ld-linux-aarch64.so.1" ] || return 3
        [ -r "$TERMUX_USR/etc/resolv.conf" ] || return 3
        [ -s "$TERMUX_USR/etc/tls/cert.pem" ] || return 3
    fi

    [ -f "$TERMUX_USR/lib/libtermux-exec-ld-preload.so" ] && preload="$TERMUX_USR/lib/libtermux-exec-ld-preload.so"
    env \
        HOME="$TERMUX_HOME" \
        PREFIX="$TERMUX_USR" \
        TMPDIR="$TERMUX_USR/tmp" \
        TERMUX_VERSION="$TERMUX_VERSION" \
        ${preload:+LD_PRELOAD="$preload"} \
        "$bin" --version >/dev/null 2>&1
}

_describe_agy_mode() {
    local bin="$1"
    local resolved dir sz ver=""
    resolved=$(readlink -f "$bin" 2>/dev/null || echo "$bin")
    dir=$(dirname "$resolved")
    sz=$(wc -c < "$resolved" 2>/dev/null || echo 0)
    ver=$(HOME="$TERMUX_HOME" PREFIX="$TERMUX_USR" TERMUX_VERSION="$TERMUX_VERSION" "$bin" --version 2>/dev/null | tail -n 1 | tr -d '\r')
    if [ "$sz" -lt 2097152 ] && [ -x "$dir/agy.va39" ]; then
        agy_msg env_mode_wallentx "${ver:-unknown}"
    else
        agy_msg env_mode_native "${ver:-unknown}"
    fi
}

_install_wallentx_agy() {
    local tmp_tar="$TERMUX_USR/tmp/antigravity-termux-standalone.tar.gz"
    local extract_dir="$TERMUX_USR/tmp/.agy-extract.$$"
    local agy_bak="" va39_bak="" ok=0

    rm -rf "$extract_dir"
    mkdir -p "$extract_dir" "$TERMUX_BIN"
    _fix_path_perms "$extract_dir" 0

    _env_log "$(agy_msg env_dl_wallentx "$AGY_REPO")"
    if ! _run_as_termux_net "$TERMUX_BIN/curl" -fL --connect-timeout 15 --max-time 300 -H "Cache-Control: no-cache" -o "$tmp_tar" "$AGY_INSTALL_URL"; then
        _env_log "$(agy_msg env_err_dl_wallentx)"
        rm -rf "$extract_dir" "$tmp_tar"
        return 1
    fi

    if ! _run_as_termux_net "$TERMUX_BIN/tar" -xz -C "$extract_dir" -f "$tmp_tar" agy agy.va39 2>/dev/null; then
        _env_log "$(agy_msg env_err_extract_wallentx)"
        rm -rf "$extract_dir" "$tmp_tar"
        return 1
    fi

    [ -f "$TERMUX_BIN/agy" ] && { agy_bak="$TERMUX_BIN/agy.bak.$$"; mv -f "$TERMUX_BIN/agy" "$agy_bak"; }
    [ -f "$TERMUX_BIN/agy.va39" ] && { va39_bak="$TERMUX_BIN/agy.va39.bak.$$"; mv -f "$TERMUX_BIN/agy.va39" "$va39_bak"; }

    if "$TERMUX_BIN/install" -m 0755 "$extract_dir/agy" "$TERMUX_BIN/agy" && \
       "$TERMUX_BIN/install" -m 0755 "$extract_dir/agy.va39" "$TERMUX_BIN/agy.va39"; then
        _fix_path_perms "$TERMUX_BIN/agy" 0
        _fix_path_perms "$TERMUX_BIN/agy.va39" 0
        if _check_agy_binary "$TERMUX_BIN/agy"; then
            ok=1
            _env_log "$(agy_msg env_ok_wallentx "$(_describe_agy_mode "$TERMUX_BIN/agy")")"
        else
            _env_log "$(agy_msg env_err_verify_agy)"
        fi
    fi

    if [ "$ok" -eq 1 ]; then
        rm -f "$agy_bak" "$va39_bak" "$tmp_tar"
    else
        rm -f "$TERMUX_BIN/agy" "$TERMUX_BIN/agy.va39" "$tmp_tar"
        [ -n "$agy_bak" ] && [ -f "$agy_bak" ] && mv -f "$agy_bak" "$TERMUX_BIN/agy"
        [ -n "$va39_bak" ] && [ -f "$va39_bak" ] && mv -f "$va39_bak" "$TERMUX_BIN/agy.va39"
        rm -rf "$extract_dir"
        return 1
    fi
    rm -rf "$extract_dir"
    return 0
}

ensure_env_main() {
    local quiet_ok=0
    local force_wallentx=0
    local net_only=0
    local arg
    for arg in "$@"; do
        case "$arg" in
            --quiet-ok|--boot) quiet_ok=1 ;;
            --force-wallentx) force_wallentx=1 ;;
            --net-only) net_only=1 ;;
        esac
    done
    [ "${AGY_FORCE_WALLENTX:-0}" = "1" ] && force_wallentx=1
    [ -f "/data/adb/antigravity_force_wallentx" ] && force_wallentx=1

    if [ "$(uname -m)" != "aarch64" ]; then
        _env_log "$(agy_msg env_err_arch "$(uname -m)")"
        return 1
    fi

    if [ "$net_only" -eq 1 ]; then
        if [ ! -d "$TERMUX_HOME" ] || [ ! -d "$TERMUX_USR" ]; then
            _env_log "$(agy_msg env_err_no_termux_home "$TERMUX_HOME")"
            return 1
        fi
        _init_termux_meta
        _ensure_resolv_conf
        _ensure_glibc_net_configs "$quiet_ok"
        return 0
    fi

    if [ ! -d "$TERMUX_HOME" ] || [ ! -x "$TERMUX_BIN/dpkg-query" ] || [ ! -x "$TERMUX_BIN/apt-get" ]; then
        _env_log "$(agy_msg env_err_init_termux)"
        return 1
    fi

    _init_termux_meta

    # 1. Detect missing Termux packages
    local missing_stage1="" missing_stage2="" need_glibc_repo=0 need_lse_qemu=0
    local has_lse=0
    grep -q "atomics" /proc/cpuinfo 2>/dev/null && has_lse=1

    # Stage 1: Core tools + TLS/DNS + glibc-repo
    for pkg in bash python tmux curl tar util-linux procps coreutils ca-certificates resolv-conf glibc-repo; do
        local pkg_ok=1
        _pkg_installed "$pkg" || pkg_ok=0
        case "$pkg" in
            python)        [ -x "$TERMUX_BIN/python3" ] || pkg_ok=0 ;;
            tmux)          [ -x "$TERMUX_BIN/tmux" ] || pkg_ok=0 ;;
            curl)          [ -x "$TERMUX_BIN/curl" ] || pkg_ok=0 ;;
            tar)           [ -x "$TERMUX_BIN/tar" ] || pkg_ok=0 ;;
            util-linux)    { [ -x "$TERMUX_BIN/flock" ] && [ -x "$TERMUX_BIN/setpriv" ]; } || pkg_ok=0 ;;
            procps)        { [ -x "$TERMUX_BIN/pgrep" ] && [ -x "$TERMUX_BIN/pkill" ]; } || pkg_ok=0 ;;
            ca-certificates) [ -s "$TERMUX_USR/etc/tls/cert.pem" ] || pkg_ok=0 ;;
            resolv-conf)   [ -r "$TERMUX_USR/etc/resolv.conf" ] || pkg_ok=0 ;;
            glibc-repo)    [ -s "$TERMUX_USR/etc/apt/sources.list.d/glibc.list" ] || pkg_ok=0 ;;
        esac
        if [ "$pkg_ok" -eq 1 ]; then
            [ "$quiet_ok" -eq 0 ] && _env_log "$(agy_msg env_ok_pkg "$pkg")"
        else
            _env_log "$(agy_msg env_miss_pkg "$pkg")"
            missing_stage1="${missing_stage1:+$missing_stage1 }$pkg"
            [ "$pkg" = "glibc-repo" ] && need_glibc_repo=1
        fi
    done

    # Stage 2: glibc & (if CPU lacks LSE) qemu-user-aarch64
    if _pkg_installed glibc && [ -x "$TERMUX_USR/glibc/lib/ld-linux-aarch64.so.1" ]; then
        [ "$quiet_ok" -eq 0 ] && _env_log "$(agy_msg env_ok_glibc)"
    else
        _env_log "$(agy_msg env_miss_glibc)"
        missing_stage2="glibc"
    fi

    if [ "$has_lse" -eq 1 ]; then
        [ "$quiet_ok" -eq 0 ] && _env_log "$(agy_msg env_ok_lse)"
    elif _pkg_installed qemu-user-aarch64 && [ -x "$TERMUX_BIN/qemu-aarch64" ]; then
        [ "$quiet_ok" -eq 0 ] && _env_log "$(agy_msg env_ok_qemu)"
    else
        _env_log "$(agy_msg env_miss_qemu)"
        missing_stage2="${missing_stage2:+$missing_stage2 }qemu-user-aarch64"
        need_lse_qemu=1
    fi

    # 2. Provision missing packages if online
    local did_apt=0 need_pending=0
    if [ -n "$missing_stage1" ] || [ -n "$missing_stage2" ]; then
        if ! _check_network; then
            _env_log "$(agy_msg env_warn_offline_pkgs)"
            need_pending=1
        else
            _run_as_termux_net "$TERMUX_BIN/dpkg" --configure -a >/dev/null 2>&1 || true
            _env_log "$(agy_msg env_apt_update)"
            _run_as_termux_net "$TERMUX_BIN/apt-get" update >/dev/null 2>&1 || true

            if [ -n "$missing_stage1" ]; then
                # shellcheck disable=SC2086
                if _install_pkg_batch $missing_stage1; then
                    did_apt=1
                else
                    _env_log "$(agy_msg env_err_apt_stage1 "$missing_stage1")"
                    need_pending=1
                fi
            fi

            if [ -n "$missing_stage2" ]; then
                # Sync termux-glibc repo list after installing glibc-repo
                if [ "$need_glibc_repo" -eq 1 ]; then
                    _env_log "$(agy_msg env_apt_glibc)"
                    _run_as_termux_net "$TERMUX_BIN/apt-get" update >/dev/null 2>&1 || true
                fi
                # shellcheck disable=SC2086
                if _install_pkg_batch $missing_stage2; then
                    did_apt=1
                else
                    _env_log "$(agy_msg env_err_apt_stage2 "$missing_stage2")"
                    need_pending=1
                fi
            fi

            [ "$did_apt" -eq 1 ] && _fix_apt_post_install_perms
        fi
    fi

    # Ensure resolv.conf and glibc DNS/hosts/NSS configs are valid
    _ensure_resolv_conf
    _ensure_glibc_net_configs "$quiet_ok"

    # 3. Check or provision agy binary
    local active_agy=""
    if [ "$force_wallentx" -eq 0 ]; then
        if _check_agy_binary "$TERMUX_BIN/agy"; then
            active_agy="$TERMUX_BIN/agy"
        elif _check_agy_binary "$TERMUX_HOME/.local/bin/agy"; then
            active_agy="$TERMUX_HOME/.local/bin/agy"
        fi
    fi

    if [ -n "$active_agy" ]; then
        [ "$quiet_ok" -eq 0 ] && _env_log "$(agy_msg env_ok_agy "$(_describe_agy_mode "$active_agy")")"
    else
        if [ "$force_wallentx" -eq 1 ]; then
            _env_log "$(agy_msg env_force_wallentx)"
        elif [ -e "$TERMUX_BIN/agy" ] && [ ! -e "$TERMUX_BIN/agy.va39" ] && [ "$(wc -c < "$TERMUX_BIN/agy" 2>/dev/null || echo 0)" -lt 2097152 ]; then
            _env_log "$(agy_msg env_miss_va39)"
        else
            _env_log "$(agy_msg env_miss_agy)"
        fi

        if ! _check_network; then
            _env_log "$(agy_msg env_warn_offline_agy)"
            need_pending=1
        elif _install_wallentx_agy; then
            rm -f "/data/adb/antigravity_force_wallentx" 2>/dev/null || true
        else
            need_pending=1
        fi
    fi

    if [ "$need_pending" -eq 1 ]; then
        return 2
    fi
    return 0
}

case "${0##*/}" in
    ensure_antigravity_env.sh)
        if [ "${AGY_ENV_LIB_ONLY:-0}" != "1" ]; then
            ensure_env_main "$@"
        fi
        ;;
esac
