# >>> antigravity-remote-control >>>
unalias agy-attach agy-stop agy-start agy-restart agy-status agy-clean agy-log agy-lang 2>/dev/null

_agy_load_i18n() {
    if [ -f "$HOME/.local/bin/agy_i18n.sh" ]; then
        . "$HOME/.local/bin/agy_i18n.sh"
        agy_i18n_init "$HOME"
    elif ! command -v agy_msg >/dev/null 2>&1; then
        agy_i18n_init() { :; }
        agy_i18n_detect() { echo "en"; }
        agy_i18n_normalize() { echo "$1"; }
        agy_msg() { local _k="$1"; shift; printf '%s%s\n' "$_k" "${*:+: $*}"; }
    fi
}
_agy_load_i18n

_agy_hostname() {
    local h
    h=$(sed -n 's/.*"cliRemoteControlHostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME/.gemini/config/config.json" 2>/dev/null | head -n 1)
    echo "${h:-localhost-phone}"
}

_agy_root_lock_active() {
    local lock="$PREFIX/var/run/agy_root.lock"
    [ -f "$lock" ] && ! "$PREFIX/bin/flock" -n -s "$lock" true 2>/dev/null
}

_agy_start_lock_active() {
    local lock="$PREFIX/var/run/agy_start.lock"
    [ -f "$lock" ] && ! "$PREFIX/bin/flock" -n -s "$lock" true 2>/dev/null
}

_agy_pgrep() {
    if [ -x "$PREFIX/bin/pgrep" ]; then
        "$PREFIX/bin/pgrep" "$@"
    else
        pgrep "$@"
    fi
}

_agy_pkill() {
    if [ -x "$PREFIX/bin/pkill" ]; then
        "$PREFIX/bin/pkill" "$@"
    else
        pkill "$@"
    fi
}

_agy_is_running() {
    _agy_root_lock_active && return 0
    TMUX_TMPDIR="$PREFIX/var/run" "$PREFIX/bin/tmux" has-session -t agy 2>/dev/null && return 0
    _agy_pgrep -f '[a]gy_boot_service\.sh --runner' >/dev/null 2>&1 && return 0
    _agy_pgrep -f '[a]gy(\.va39|-va39)? --remote-control' >/dev/null 2>&1
}

_agy_rc_enabled() {
    local _f="$HOME/.gemini/config/remote_control" _v=""
    if [ -r "$_f" ]; then
        _v=$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "$_f" 2>/dev/null)
        [ "$_v" = "0" ] && return 1
    fi
    return 0
}

_agy_set_rc_flag() {
    local _val="$1"
    local _cfg="$HOME/.gemini/config"
    local _rf="$_cfg/remote_control"
    mkdir -p "$_cfg" 2>/dev/null || true
    if printf '%s\n' "$_val" > "$_rf" 2>/dev/null; then
        chmod 644 "$_rf" 2>/dev/null || true
    elif command -v su >/dev/null 2>&1; then
        su -c "mkdir -p '$_cfg' && printf '%s\n' '$_val' > '$_rf' && chmod 644 '$_rf'" </dev/null 2>/dev/null || true
    fi
}

agy-attach() {
    if [ "$(id -u)" -eq 0 ]; then
        TMUX_TMPDIR="$PREFIX/var/run" "$PREFIX/bin/tmux" attach -t agy 2>/dev/null || TMUX_TMPDIR="$PREFIX/var/run" "$PREFIX/bin/tmux" attach
    elif _agy_root_lock_active; then
        su -c "export HOME='$HOME' PREFIX='$PREFIX' TERM='${TERM:-xterm-256color}' LANG='${LANG:-en_US.UTF-8}' TMUX_TMPDIR='$PREFIX/var/run' TERMUX_VERSION='${TERMUX_VERSION:-0.118.3}' PATH='$PREFIX/bin:\$PATH'; '$PREFIX/bin/tmux' attach -t agy 2>/dev/null || '$PREFIX/bin/tmux' attach"
    else
        TMUX_TMPDIR="$PREFIX/var/run" "$PREFIX/bin/tmux" attach -t agy 2>/dev/null || TMUX_TMPDIR="$PREFIX/var/run" "$PREFIX/bin/tmux" attach
    fi
}

agy-stop() {
    if [ "$(id -u)" -eq 0 ]; then
        "$PREFIX/bin/bash" "$HOME/.local/bin/agy_boot_service.sh" --stop || true
    else
        if { _agy_root_lock_active || _agy_start_lock_active; } && command -v su >/dev/null 2>&1; then
            su -c "export HOME='$HOME' PREFIX='$PREFIX' TMUX_TMPDIR='$PREFIX/var/run'; '$PREFIX/bin/bash' '$HOME/.local/bin/agy_boot_service.sh' --stop" </dev/null 2>/dev/null || true
        fi
        if _agy_is_running || _agy_start_lock_active; then
            "$PREFIX/bin/bash" "$HOME/.local/bin/agy_boot_service.sh" --stop || true
        fi
    fi
}

agy-start() {
    agy_i18n_init "$HOME" 1 >/dev/null 2>&1 || true
    _agy_set_rc_flag 1
    local _tver="${TERMUX_VERSION:-0.118.3}"
    local _loc="${AGY_LOCALE:-en}"
    if [ "$(id -u)" -eq 0 ]; then
        AGY_LOCALE="$_loc" AGY_FORCE_START=1 "$HOME/.local/bin/agy_boot_service.sh" --force
    elif command -v su >/dev/null 2>&1; then
        su -c "export HOME='$HOME' PREFIX='$PREFIX' TMUX_TMPDIR='$PREFIX/var/run' PYTHONDONTWRITEBYTECODE=1 TERMUX_VERSION='$_tver' AGY_LOCALE='$_loc' AGY_FORCE_START=1 PATH='$PREFIX/bin:$HOME/.local/bin:/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk'; '$PREFIX/bin/bash' '$HOME/.local/bin/agy_boot_service.sh' --force" </dev/null || {
            agy_msg bashrc_su_fail
            AGY_LOCALE="$_loc" AGY_FORCE_START=1 "$HOME/.local/bin/agy_boot_service.sh" --force
        }
    else
        AGY_LOCALE="$_loc" AGY_FORCE_START=1 "$HOME/.local/bin/agy_boot_service.sh" --force
    fi
}

agy-restart() {
    agy-stop
    agy-start
}

_agy_has_token() {
    local _tp="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
    [ -s "$_tp" ] && grep -qE '"(access|refresh)_token"[[:space:]]*:[[:space:]]*"[^"]+' "$_tp" 2>/dev/null
}

agy-lang() {
    local _arg="${1:-}"
    local _cfg_dir="$HOME/.gemini/config"
    local _lang_file="$_cfg_dir/lang"
    if [ -z "$_arg" ]; then
        agy_i18n_init "$HOME" 1 >/dev/null 2>&1 || true
        local _mode="auto"
        if [ -s "$_lang_file" ]; then
            _mode=$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "$_lang_file" 2>/dev/null)
            [ -z "$_mode" ] && _mode="auto"
        elif [ -r "/data/adb/antigravity_lang" ] && [ -s "/data/adb/antigravity_lang" ]; then
            _mode=$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "/data/adb/antigravity_lang" 2>/dev/null)
            [ -z "$_mode" ] && _mode="auto"
        fi
        agy_msg bashrc_lang_current "${AGY_LOCALE:-en}" "$_mode"
        agy_msg bashrc_lang_usage
        return 0
    fi

    local _low
    _low=$(printf '%s' "$_arg" | tr '[:upper:]_' '[:lower:]-')
    case "$_low" in
        auto|system|default)
            rm -f "$_lang_file" 2>/dev/null || true
            if [ "$(id -u)" -eq 0 ]; then
                rm -f "/data/adb/antigravity_lang" 2>/dev/null || true
                command -v agy_i18n_refresh_cache >/dev/null 2>&1 && agy_i18n_refresh_cache "$HOME"
            elif command -v su >/dev/null 2>&1; then
                su -c "rm -f /data/adb/antigravity_lang; [ -f '$HOME/.local/bin/agy_i18n.sh' ] && . '$HOME/.local/bin/agy_i18n.sh' && agy_i18n_refresh_cache '$HOME'" </dev/null >/dev/null 2>&1 || true
            fi
            unset AGY_LANG AGY_LOCALE 2>/dev/null || true
            agy_i18n_init "$HOME" 1 >/dev/null 2>&1 || true
            agy_msg bashrc_lang_set_auto "${AGY_LOCALE:-en}"
            return 0
            ;;
        zh-tw|zh-hk|zh-mo|zh-hant|tw|zhtw|hk|mo|hant|tc|traditional|zh-cn|zh-sg|zh-hans|zh|cn|zhcn|hans|sc|simplified|ja|ja-jp|jp|japanese|en|en-us|en-gb|english)
            local _norm
            _norm=$(agy_i18n_normalize "$_arg")
            mkdir -p "$_cfg_dir" 2>/dev/null || true
            if ! printf '%s\n' "$_norm" > "$_lang_file" 2>/dev/null; then
                if command -v su >/dev/null 2>&1; then
                    su -c "mkdir -p '$_cfg_dir' && printf '%s\n' '$_norm' > '$_lang_file' && chmod 644 '$_lang_file'" </dev/null 2>/dev/null || true
                fi
            fi
            chmod 644 "$_lang_file" 2>/dev/null || true
            unset AGY_LANG 2>/dev/null || true
            AGY_LOCALE="$_norm"
            export AGY_LOCALE
            agy_msg bashrc_lang_set "$_norm"
            return 0
            ;;
        *)
            agy_i18n_init "$HOME" 1 >/dev/null 2>&1 || true
            agy_msg bashrc_lang_invalid "$_arg"
            return 1
            ;;
    esac
}

agy-status() {
    agy_i18n_init "$HOME" 1 >/dev/null 2>&1 || true
    if [ "$(id -u)" -eq 0 ]; then
        if ! _agy_is_running && ! _agy_rc_enabled; then
            agy_msg bashrc_status_disabled
        elif ! _agy_has_token; then
            agy_msg bashrc_status_wait_root
        else
            ps -ef | grep -E '[a]gy(\.va39|-va39)? --remote-control' || agy_msg bashrc_not_running
        fi
    elif _agy_root_lock_active; then
        agy_msg bashrc_root_locked "$PREFIX/var/run/agy_root.lock"
        if ! _agy_has_token; then
            agy_msg bashrc_conn_wait_oauth
        else
            su -c "ps -ef | grep -E '[a]gy(\.va39|-va39)? --remote-control'" </dev/null 2>/dev/null || true
        fi
    elif _agy_start_lock_active; then
        agy_msg bashrc_starting
    else
        if ! _agy_is_running && ! _agy_rc_enabled; then
            agy_msg bashrc_status_disabled
        else
            ps -ef | grep -E '[a]gy(\.va39|-va39)? --remote-control' || agy_msg bashrc_not_running
        fi
        if ! _agy_has_token; then
            agy_msg bashrc_conn_not_logged_in
        fi
    fi
    if _agy_is_running && _agy_has_token && [ -r "$HOME/.gemini/antigravity-cli/cli.log" ]; then
        local _logp="$HOME/.gemini/antigravity-cli/cli.log"
        local _conn
        _conn=$(grep -E 'Connection status:' "$_logp" 2>/dev/null | tail -n 1)
        if [ -n "$_conn" ]; then
            agy_msg bashrc_conn_state "$_conn"
        elif grep -qE 'Select login method|You are not logged into Antigravity' "$_logp" 2>/dev/null; then
            agy_msg bashrc_conn_verifying
        fi
    fi
}

agy-clean() {
    agy_i18n_init "$HOME" 1 >/dev/null 2>&1 || true
    local _loc="${AGY_LOCALE:-en}"
    local _use_direct=0
    if [ "$(id -u)" -eq 0 ]; then
        _use_direct=1
    elif ! _agy_root_lock_active && [ -r "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ]; then
        if [ ! -e "$HOME/.gemini/antigravity-cli/.ls_csrf_token" ] || [ -r "$HOME/.gemini/antigravity-cli/.ls_csrf_token" ]; then
            _use_direct=1
        fi
    fi
    if [ "$_use_direct" -eq 1 ]; then
        AGY_LOCALE="$_loc" "$PREFIX/bin/python3" -B "$HOME/.local/bin/cleanup_offline_instances.py"
        if [ -f "$HOME/.local/bin/cleanup_empty_conversations.py" ]; then
            AGY_LOCALE="$_loc" "$PREFIX/bin/python3" -B "$HOME/.local/bin/cleanup_empty_conversations.py" --min-age 0 --verbose
        fi
    else
        su -c "export HOME='$HOME' PREFIX='$PREFIX' AGY_LOCALE='$_loc'; '$PREFIX/bin/python3' -B '$HOME/.local/bin/cleanup_offline_instances.py'; [ -f '$HOME/.local/bin/cleanup_empty_conversations.py' ] && '$PREFIX/bin/python3' -B '$HOME/.local/bin/cleanup_empty_conversations.py' --min-age 0 --verbose" </dev/null
    fi
}

agy-log() {
    if [ -r "$HOME/.gemini/antigravity-cli/boot.log" ]; then
        cat "$HOME/.gemini/antigravity-cli/boot.log"
    else
        su -c "cat '$HOME/.gemini/antigravity-cli/boot.log' 2>/dev/null" </dev/null
    fi
    echo "--- KernelSU Log ---"
    if [ "$(id -u)" -eq 0 ]; then
        cat /data/adb/agy_boot.log 2>/dev/null
    else
        su -c "cat /data/adb/agy_boot.log 2>/dev/null" </dev/null
    fi
}

if ! _agy_is_running && ! _agy_start_lock_active; then
    if ! _agy_rc_enabled; then
        echo -e "\033[0;33m$(agy_msg bashrc_banner_disabled)\033[0m"
        echo -e "\033[0;36m$(agy_msg bashrc_banner_disabled_hint)\033[0m\n"
    else
        ( (agy-start) </dev/null >/dev/null 2>&1 & )
        if ! _agy_has_token; then
            echo -e "\033[1;33m$(agy_msg bashrc_banner_root_wait "$(_agy_hostname)")\033[0m"
            echo -e "\033[0;36m$(agy_msg bashrc_banner_need_login)\033[0m\n"
        else
            echo -e "\033[1;33m$(agy_msg bashrc_banner_root_starting "$(_agy_hostname)")\033[0m"
        fi
    fi
elif _agy_root_lock_active; then
    if ! _agy_has_token; then
        echo -e "\033[1;33m$(agy_msg bashrc_banner_root_standby "$(_agy_hostname)")\033[0m"
        echo -e "\033[0;36m$(agy_msg bashrc_banner_run_agy_status)\033[0m\n"
    else
        echo -e "\033[1;32m$(agy_msg bashrc_banner_root_running "$(_agy_hostname)")\033[0m"
        echo -e "\033[0;36m$(agy_msg bashrc_banner_cmds)\033[0m\n"
    fi
elif _agy_start_lock_active; then
    if ! _agy_has_token; then
        echo -e "\033[1;33m$(agy_msg bashrc_banner_user_wait "$(_agy_hostname)")\033[0m"
        echo -e "\033[0;36m$(agy_msg bashrc_banner_run_agy)\033[0m\n"
    else
        echo -e "\033[1;33m$(agy_msg bashrc_banner_user_starting "$(_agy_hostname)")\033[0m"
    fi
else
    if ! _agy_has_token; then
        echo -e "\033[1;33m$(agy_msg bashrc_banner_user_standby "$(_agy_hostname)")\033[0m"
        echo -e "\033[0;36m$(agy_msg bashrc_banner_user_standby_hint)\033[0m\n"
    else
        echo -e "\033[1;32m$(agy_msg bashrc_banner_user_running "$(_agy_hostname)")\033[0m"
        echo -e "\033[0;36m$(agy_msg bashrc_banner_cmds)\033[0m\n"
    fi
fi
# <<< antigravity-remote-control <<<
