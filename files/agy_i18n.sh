#!/bin/sh
# Shared POSIX-compatible i18n helper (zh-TW / zh-CN / en / ja)
# Compatible with KernelSU/Magisk BusyBox ash, Android mksh, and Termux bash.

agy_i18n_normalize() {
    local _raw _tag
    _raw=$(printf '%s' "${1:-}" | tr -d '\r\n"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$_raw" ] && return 1
    _tag=${_raw%%,*}
    _tag=$(printf '%s' "$_tag" | tr '[:upper:]_' '[:lower:]-')
    _tag=${_tag%%.*}
    _tag=${_tag%%@*}

    case "$_tag" in
        ''|auto|c|c-*|posix|system|default)
            return 1
            ;;
        zh-tw*|zh-hk*|zh-mo*|zh-hant*|zh-*-tw*|zh-*-hk*|zh-*-mo*|zh-*-hant*|tw|zhtw|hk|mo|hant|tc|traditional)
            printf '%s\n' 'zh-TW'
            ;;
        zh-cn*|zh-sg*|zh-hans*|zh-*-cn*|zh-*-sg*|zh-*-hans*|zh*|cn|zhcn|hans|sc|simplified)
            printf '%s\n' 'zh-CN'
            ;;
        ja*|jp|japanese)
            printf '%s\n' 'ja'
            ;;
        en*|english)
            printf '%s\n' 'en'
            ;;
        *)
            printf '%s\n' 'en'
            ;;
    esac
}

_agy_read_trimmed() {
    local _f="$1"
    [ -r "$_f" ] || return 1
    sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "$_f" 2>/dev/null
}

_agy_query_settings() {
    if [ -x /system/bin/cmd ]; then
        if [ -x /system/bin/timeout ]; then
            /system/bin/timeout 2 /system/bin/cmd settings "$@" </dev/null 2>/dev/null
        else
            /system/bin/cmd settings "$@" </dev/null 2>/dev/null
        fi
    elif [ -x /system/bin/settings ]; then
        if [ -x /system/bin/timeout ]; then
            /system/bin/timeout 2 /system/bin/settings "$@" </dev/null 2>/dev/null
        else
            /system/bin/settings "$@" </dev/null 2>/dev/null
        fi
    else
        return 1
    fi
}

_agy_probe_live_android_locale() {
    local _uid _raw _norm _lang_p _cntry_p
    _uid=$(id -u 2>/dev/null || echo 1)

    if [ "$_uid" = "0" ] && { [ -x /system/bin/cmd ] || [ -x /system/bin/settings ]; }; then
        _raw=$(_agy_query_settings get system system_locales)
        if [ -z "$_raw" ] || [ "$_raw" = "null" ]; then
            _raw=$(_agy_query_settings --user 0 get system system_locales)
        fi
        if [ -n "$_raw" ] && [ "$_raw" != "null" ]; then
            _norm=$(agy_i18n_normalize "$_raw")
            if [ -n "$_norm" ]; then
                printf '%s\n' "$_norm"
                return 0
            fi
        fi
    fi

    if command -v getprop >/dev/null 2>&1; then
        _raw=$(getprop persist.sys.locale 2>/dev/null)
        if [ -n "$_raw" ]; then
            _norm=$(agy_i18n_normalize "$_raw")
            if [ -n "$_norm" ]; then
                printf '%s\n' "$_norm"
                return 0
            fi
        fi
        _lang_p=$(getprop persist.sys.language 2>/dev/null)
        _cntry_p=$(getprop persist.sys.country 2>/dev/null)
        if [ -n "$_lang_p" ]; then
            _norm=$(agy_i18n_normalize "${_lang_p}${_cntry_p:+-$_cntry_p}")
            if [ -n "$_norm" ]; then
                printf '%s\n' "$_norm"
                return 0
            fi
        fi
    fi
    return 1
}

agy_i18n_detect() {
    local _home _raw _norm
    _home=${1:-${TERMUX_HOME:-${HOME:-/data/data/com.termux/files/home}}}

    # 1. Explicit env override
    if [ -n "${AGY_LANG:-}" ]; then
        _norm=$(agy_i18n_normalize "$AGY_LANG")
        if [ -n "$_norm" ]; then
            printf '%s\n' "$_norm"
            return 0
        fi
    fi

    # 2. Persistent Termux config override (~/.gemini/config/lang)
    _raw=$(_agy_read_trimmed "$_home/.gemini/config/lang" 2>/dev/null)
    if [ -n "$_raw" ]; then
        _norm=$(agy_i18n_normalize "$_raw")
        if [ -n "$_norm" ]; then
            printf '%s\n' "$_norm"
            return 0
        fi
    fi

    # 3. Module-level override (/data/adb/antigravity_lang)
    _raw=$(_agy_read_trimmed "/data/adb/antigravity_lang" 2>/dev/null)
    if [ -n "$_raw" ]; then
        _norm=$(agy_i18n_normalize "$_raw")
        if [ -n "$_norm" ]; then
            printf '%s\n' "$_norm"
            return 0
        fi
    fi

    # 4. Already-resolved locale exported by parent process unless AGY_I18N_REPROBE=1
    if [ "${AGY_I18N_REPROBE:-0}" != "1" ] && [ -n "${AGY_LOCALE:-}" ]; then
        _norm=$(agy_i18n_normalize "$AGY_LOCALE")
        if [ -n "$_norm" ]; then
            printf '%s\n' "$_norm"
            return 0
        fi
    fi

    # 5. Live Android UI locale (when running as root or via persist.sys.locale)
    _norm=$(_agy_probe_live_android_locale 2>/dev/null)
    if [ -n "$_norm" ]; then
        printf '%s\n' "$_norm"
        return 0
    fi

    # 6. Cached system locale written by customize.sh / service.sh (readable by non-root Termux)
    _raw=$(_agy_read_trimmed "$_home/.gemini/config/.system_lang" 2>/dev/null)
    if [ -n "$_raw" ]; then
        _norm=$(agy_i18n_normalize "$_raw")
        if [ -n "$_norm" ]; then
            printf '%s\n' "$_norm"
            return 0
        fi
    fi

    # 7. Factory ROM default locale (only if neither live settings nor cache exists)
    if command -v getprop >/dev/null 2>&1; then
        _raw=$(getprop ro.product.locale 2>/dev/null)
        if [ -n "$_raw" ]; then
            _norm=$(agy_i18n_normalize "$_raw")
            if [ -n "$_norm" ]; then
                printf '%s\n' "$_norm"
                return 0
            fi
        fi
    fi

    # 8. POSIX shell env fallback
    for _raw in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
        if [ -n "$_raw" ]; then
            _norm=$(agy_i18n_normalize "$_raw")
            if [ -n "$_norm" ]; then
                printf '%s\n' "$_norm"
                return 0
            fi
        fi
    done

    printf '%s\n' 'en'
}

agy_i18n_refresh_cache() {
    local _home _uid _gid _ctx _cfg_dir _cache_file _detected
    _home=${1:-${TERMUX_HOME:-${HOME:-/data/data/com.termux/files/home}}}
    _uid=${2:-}
    _gid=${3:-}
    _ctx=${4:-}
    [ -d "$_home" ] || return 0

    _detected=$(_agy_probe_live_android_locale 2>/dev/null)
    if [ -z "$_detected" ]; then
        if [ ! -s "$_home/.gemini/config/.system_lang" ] && command -v getprop >/dev/null 2>&1; then
            _detected=$(agy_i18n_normalize "$(getprop ro.product.locale 2>/dev/null)")
        fi
    fi
    [ -n "$_detected" ] || return 0

    if [ -z "$_uid" ] && [ -x /system/bin/stat ]; then
        _uid=$(/system/bin/stat -c '%u' "$_home" 2>/dev/null)
        _gid=$(/system/bin/stat -c '%g' "$_home" 2>/dev/null)
        _ctx=$(/system/bin/stat -c '%C' "$_home" 2>/dev/null)
    fi

    _cfg_dir="$_home/.gemini/config"
    _cache_file="$_cfg_dir/.system_lang"
    mkdir -p "$_cfg_dir" 2>/dev/null || return 0
    printf '%s\n' "$_detected" > "${_cache_file}.tmp.$$" 2>/dev/null && \
        mv -f "${_cache_file}.tmp.$$" "$_cache_file" 2>/dev/null || \
        rm -f "${_cache_file}.tmp.$$" 2>/dev/null

    chmod 700 "$_home/.gemini" "$_cfg_dir" 2>/dev/null || true
    chmod 644 "$_cache_file" 2>/dev/null || true
    if [ "$(id -u 2>/dev/null || echo 1)" = "0" ] && [ -n "$_uid" ]; then
        chown "$_uid:${_gid:-$_uid}" "$_home/.gemini" "$_cfg_dir" "$_cache_file" 2>/dev/null || true
        if [ -n "$_ctx" ] && [ "$_ctx" != "?" ] && [ -x /system/bin/chcon ]; then
            /system/bin/chcon "$_ctx" "$_home/.gemini" "$_cfg_dir" "$_cache_file" 2>/dev/null || true
        fi
    fi
}

agy_i18n_init() {
    local _home _force
    _home=${1:-${TERMUX_HOME:-${HOME:-/data/data/com.termux/files/home}}}
    _force=${2:-0}
    if [ "$_force" = "1" ]; then
        AGY_I18N_REPROBE=1 AGY_LOCALE=$(agy_i18n_detect "$_home")
    else
        AGY_LOCALE=$(agy_i18n_detect "$_home")
    fi
    export AGY_LOCALE
}

agy_msg() {
    local _k _lang _fmt
    _k=$1
    shift
    _lang=${AGY_LOCALE:-}
    if [ -z "$_lang" ]; then
        _lang=$(agy_i18n_detect 2>/dev/null)
        AGY_LOCALE=${_lang:-en}
        export AGY_LOCALE
    fi

    case "$_k" in
        module_desc)
            case "$_lang" in
                zh-TW) _fmt='讓 Antigravity CLI 在 Android 上於開機後自動以 root 啟動 Remote Control，支援固定裝置名稱、Termux/glibc 環境補全、~/.gemini 權限與 SELinux 即時同步、重啟空白對話與離線實例自動清理、四語切換及刷入音量鍵開關。' ;;
                zh-CN) _fmt='让 Antigravity CLI 在 Android 上开机自动以 root 启动 Remote Control，支持固定设备名称、Termux/glibc 环境补全、~/.gemini 权限与 SELinux 实时同步、重启空白对话与离线实例自动清理、四语切换及刷入音量键开关。' ;;
                ja)    _fmt='Android 起動時に Antigravity CLI の Remote Control を root で自動起動し、端末固定ホスト名設定、Termux/glibc 環境補完、~/.gemini 権限と SELinux の即時同期、起動時の空会話・古い接続の自動整理、4言語切替、導入時の音量キー開閉に対応します。' ;;
                *)     _fmt='Runs Antigravity CLI Remote Control as root on Android at boot with a fixed device hostname, auto Termux/glibc provisioning, live ~/.gemini permission & SELinux sync, automatic blank/offline cleanup, 4-language UI, and volume-key toggle.' ;;
            esac
            ;;

        # --- customize.sh ---
        cust_detected_device)
            case "$_lang" in
                zh-TW) _fmt='- 偵測到裝置型號: %s' ;;
                zh-CN) _fmt='- 检测到设备型号: %s' ;;
                ja)    _fmt='- 検出された端末モデル: %s' ;;
                *)     _fmt='- Detected device model: %s' ;;
            esac
            ;;
        cust_set_hostname)
            case "$_lang" in
                zh-TW) _fmt='- 設定固定連線名稱: %s' ;;
                zh-CN) _fmt='- 设置固定连接名称: %s' ;;
                ja)    _fmt='- 固定接続ホスト名を設定: %s' ;;
                *)     _fmt='- Configured persistent hostname: %s' ;;
            esac
            ;;
        cust_detected_locale)
            case "$_lang" in
                zh-TW) _fmt='- 模組顯示語言: %s' ;;
                zh-CN) _fmt='- 模块显示语言: %s' ;;
                ja)    _fmt='- モジュール表示言語: %s' ;;
                *)     _fmt='- Module language: %s' ;;
            esac
            ;;
        cust_err_no_termux)
            case "$_lang" in
                zh-TW) _fmt='! 錯誤: 未找到完整的 Termux 環境 (%s)' ;;
                zh-CN) _fmt='! 错误: 未找到完整的 Termux 环境 (%s)' ;;
                ja)    _fmt='! エラー: 完全な Termux 環境が見つかりません (%s)' ;;
                *)     _fmt='! Error: Complete Termux environment not found (%s)' ;;
            esac
            ;;
        cust_err_init_termux)
            case "$_lang" in
                zh-TW) _fmt='! 請先安裝並至少開啟一次 Termux 完成初始化，再重新刷入本模組。' ;;
                zh-CN) _fmt='! 请先安装并至少打开一次 Termux 完成初始化，再重新刷入本模块。' ;;
                ja)    _fmt='! 先に Termux をインストールし、少なくとも1回起動して初期化を完了してから再フラッシュしてください。' ;;
                *)     _fmt='! Please install Termux and open it at least once to finish initialization, then re-flash this module.' ;;
            esac
            ;;
        cust_abort_termux)
            case "$_lang" in
                zh-TW) _fmt='! Termux 尚未初始化' ;;
                zh-CN) _fmt='! Termux 尚未初始化' ;;
                ja)    _fmt='! Termux は未初期化です' ;;
                *)     _fmt='! Termux is not initialized' ;;
            esac
            ;;
        cust_termux_uid)
            case "$_lang" in
                zh-TW) _fmt='- Termux 使用者 UID: %s' ;;
                zh-CN) _fmt='- Termux 用户 UID: %s' ;;
                ja)    _fmt='- Termux ユーザー UID: %s' ;;
                *)     _fmt='- Termux user UID: %s' ;;
            esac
            ;;
        cust_check_env)
            case "$_lang" in
                zh-TW) _fmt='- 檢查 Termux 與 wallentx/antigravity-cli-termux 執行環境...' ;;
                zh-CN) _fmt='- 检查 Termux 与 wallentx/antigravity-cli-termux 运行环境...' ;;
                ja)    _fmt='- Termux および wallentx/antigravity-cli-termux 実行環境を確認中...' ;;
                *)     _fmt='- Checking Termux and wallentx/antigravity-cli-termux runtime environment...' ;;
            esac
            ;;
        cust_env_offline_later)
            case "$_lang" in
                zh-TW) _fmt='! 部分線上元件尚未即時下載完成，開機連網後 service.sh 將自動補裝' ;;
                zh-CN) _fmt='! 部分在线组件尚未即时下载完成，开机联网后 service.sh 将自动补装' ;;
                ja)    _fmt='! 一部のオンラインコンポーネントを今すぐダウンロードできませんでした。起動後にネットワーク接続され次第 service.sh が自動で補完します' ;;
                *)     _fmt='! Some online components could not be downloaded now; service.sh will install them automatically after boot once online' ;;
            esac
            ;;
        cust_env_warn)
            case "$_lang" in
                zh-TW) _fmt='! 警告: 環境檢查遇到問題 (代碼: %s)' ;;
                zh-CN) _fmt='! 警告: 环境检查遇到问题 (代码: %s)' ;;
                ja)    _fmt='! 警告: 環境チェックで問題が発生しました (コード: %s)' ;;
                *)     _fmt='! Warning: Environment check encountered an issue (code: %s)' ;;
            esac
            ;;
        cust_warn_no_python_cfg)
            case "$_lang" in
                zh-TW) _fmt='! 警告: 暫缺 python3，保留既有 config.json，將於開機補全後由 service.sh 更新' ;;
                zh-CN) _fmt='! 警告: 暂缺 python3，保留现有 config.json，将于开机补全后由 service.sh 更新' ;;
                ja)    _fmt='! 警告: python3 がまだ利用できないため既存の config.json を保持し、起動後の補完時に service.sh が更新します' ;;
                *)     _fmt='! Warning: python3 not available yet; keeping existing config.json for service.sh to update after boot' ;;
            esac
            ;;
        cust_cfg_updated)
            case "$_lang" in
                zh-TW) _fmt='- 已設定 config.json: cliRemoteControlHostname -> %s' ;;
                zh-CN) _fmt='- 已设置 config.json: cliRemoteControlHostname -> %s' ;;
                ja)    _fmt='- config.json を設定しました: cliRemoteControlHostname -> %s' ;;
                *)     _fmt='- Updated config.json: cliRemoteControlHostname -> %s' ;;
            esac
            ;;
        cust_scripts_installed)
            case "$_lang" in
                zh-TW) _fmt='- 已安裝多語言、環境補全、啟動、修補、清理與權限同步腳本至 ~/.local/bin/' ;;
                zh-CN) _fmt='- 已安装多语言、环境补全、启动、修补、清理与权限同步脚本至 ~/.local/bin/' ;;
                ja)    _fmt='- 多言語・環境補完・起動・パッチ・整理・権限同期スクリプトを ~/.local/bin/ に配置しました' ;;
                *)     _fmt='- Installed i18n, env, boot, patch, cleanup, and permission sync scripts to ~/.local/bin/' ;;
            esac
            ;;
        cust_check_patch)
            case "$_lang" in
                zh-TW) _fmt='- 檢查 agy / agy.va39 固定名稱補丁...' ;;
                zh-CN) _fmt='- 检查 agy / agy.va39 固定名称补丁...' ;;
                ja)    _fmt='- agy / agy.va39 固定ホスト名パッチを確認中...' ;;
                *)     _fmt='- Checking agy / agy.va39 persistent hostname patch...' ;;
            esac
            ;;
        cust_bashrc_updated)
            case "$_lang" in
                zh-TW) _fmt='- 已更新 ~/.bashrc root 模式與多語言捷徑指令' ;;
                zh-CN) _fmt='- 已更新 ~/.bashrc root 模式与多语言快捷指令' ;;
                ja)    _fmt='- ~/.bashrc の root モードおよび言語切替コマンドを更新しました' ;;
                *)     _fmt='- Updated ~/.bashrc root-mode and language shortcut commands' ;;
            esac
            ;;
        cust_bashrc_added)
            case "$_lang" in
                zh-TW) _fmt='- 已配置 ~/.bashrc 捷徑指令' ;;
                zh-CN) _fmt='- 已配置 ~/.bashrc 快捷指令' ;;
                ja)    _fmt='- ~/.bashrc にショートカットコマンドを設定しました' ;;
                *)     _fmt='- Configured ~/.bashrc shortcut commands' ;;
            esac
            ;;
        cust_removed_serviced)
            case "$_lang" in
                zh-TW) _fmt='- 已移除獨立 service.d 腳本，改由本模組統一管理' ;;
                zh-CN) _fmt='- 已移除独立 service.d 脚本，改由本模块统一管理' ;;
                ja)    _fmt='- 独立した service.d スクリプトを削除し、本モジュールで一元管理します' ;;
                *)     _fmt='- Removed standalone service.d script; managed centrally by this module' ;;
            esac
            ;;
        cust_recovery_skip)
            case "$_lang" in
                zh-TW) _fmt='- 非開機模式 (Recovery)，將於重開機並解鎖後自動啟動 Remote Control' ;;
                zh-CN) _fmt='- 非开机模式 (Recovery)，将于重启并解锁后自动启动 Remote Control' ;;
                ja)    _fmt='- 非起動モード (Recovery) のため、再起動とロック解除後に Remote Control を自動起動します' ;;
                *)     _fmt='- Non-boot mode (Recovery); Remote Control will auto-start after reboot and unlock' ;;
            esac
            ;;
        cust_deferred_offline)
            case "$_lang" in
                zh-TW) _fmt='- 尚有離線待補完的執行元件，將於開機連網後自動補全並啟動 Remote Control' ;;
                zh-CN) _fmt='- 尚有离线待补完的运行组件，将于开机联网后自动补全并启动 Remote Control' ;;
                ja)    _fmt='- オフラインのため未完了のコンポーネントがあります。再起動後にオンラインになると自動で補完して起動します' ;;
                *)     _fmt='- Some offline components are still pending; they will finish installing after reboot once online' ;;
            esac
            ;;
        cust_ask_restart)
            case "$_lang" in
                zh-TW) _fmt='- Remote Control 目前已在開啟中，要套用新設定重新打開嗎？' ;;
                zh-CN) _fmt='- Remote Control 当前已在开启中，要应用新设置重新打开吗？' ;;
                ja)    _fmt='- Remote Control は現在すでに起動中です。新しい設定で開き直しますか？' ;;
                *)     _fmt='- Remote Control is already open. Reopen it with the updated settings?' ;;
            esac
            ;;
        cust_vol_up_restart)
            case "$_lang" in
                zh-TW) _fmt='  [音量 +] 是（立即重新打開，重開機後也會自動打開）' ;;
                zh-CN) _fmt='  [音量 +] 是（立即重新打开，重启后也会自动打开）' ;;
                ja)    _fmt='  [音量 +] はい（今すぐ開き直し、再起動後も自動で開く）' ;;
                *)     _fmt='  [Vol +] Yes (reopen now, and auto-open after reboot)' ;;
            esac
            ;;
        cust_vol_down_keep)
            case "$_lang" in
                zh-TW) _fmt='  [音量 -] 否（立即關閉 Remote Control，重開機後也不會打開）' ;;
                zh-CN) _fmt='  [音量 -] 否（立即关闭 Remote Control，重启后也不会打开）' ;;
                ja)    _fmt='  [音量 -] いいえ（今すぐ Remote Control を閉じ、再起動後も開かない）' ;;
                *)     _fmt='  [Vol -] No (close Remote Control now, and do not auto-open after reboot)' ;;
            esac
            ;;
        cust_ask_start)
            case "$_lang" in
                zh-TW) _fmt='- 是否打開 Remote Control？' ;;
                zh-CN) _fmt='- 是否打开 Remote Control？' ;;
                ja)    _fmt='- Remote Control を開きますか？' ;;
                *)     _fmt='- Open Remote Control?' ;;
            esac
            ;;
        cust_vol_up_start)
            case "$_lang" in
                zh-TW) _fmt='  [音量 +] 是（立即打開 Remote Control，重開機後也會自動打開）' ;;
                zh-CN) _fmt='  [音量 +] 是（立即打开 Remote Control，重启后也会自动打开）' ;;
                ja)    _fmt='  [音量 +] はい（今すぐ開き、再起動後も自動で開く）' ;;
                *)     _fmt='  [Vol +] Yes (open now, and auto-open after reboot)' ;;
            esac
            ;;
        cust_vol_down_later)
            case "$_lang" in
                zh-TW) _fmt='  [音量 -] 否（不打開 Remote Control，重開機後也不會打開）' ;;
                zh-CN) _fmt='  [音量 -] 否（不打开 Remote Control，重启后也不会打开）' ;;
                ja)    _fmt='  [音量 -] いいえ（今は開かず、再起動後も自動では開かない）' ;;
                *)     _fmt='  [Vol -] No (keep off now, and do not auto-open after reboot)' ;;
            esac
            ;;
        cust_vol_timeout_hint)
            case "$_lang" in
                zh-TW) _fmt='  (請於 15 秒內按音量鍵選擇，逾時預設為否)' ;;
                zh-CN) _fmt='  (请在 15 秒内按音量键选择，超时默认为否)' ;;
                ja)    _fmt='  (15秒以内に音量キーで選択してください。タイムアウト時は「いいえ」になります)' ;;
                *)     _fmt='  (Press Volume key within 15s to choose; defaults to No on timeout)' ;;
            esac
            ;;
        cust_vol_timeout_hint_keep)
            case "$_lang" in
                zh-TW) _fmt='  (請於 15 秒內按音量鍵選擇，逾時將維持目前開啟狀態)' ;;
                zh-CN) _fmt='  (请在 15 秒内按音量键选择，超时将维持当前开启状态)' ;;
                ja)    _fmt='  (15秒以内に音量キーで選択してください。タイムアウト時は現在の稼働状態を維持します)' ;;
                *)     _fmt='  (Press Volume key within 15s to choose; keeps active session on timeout)' ;;
            esac
            ;;
        cust_yes_starting)
            case "$_lang" in
                zh-TW) _fmt='- 已選擇「是」，正在打開 Remote Control...' ;;
                zh-CN) _fmt='- 已选择“是”，正在打开 Remote Control...' ;;
                ja)    _fmt='- 「はい」が選択されました。Remote Control を開いています...' ;;
                *)     _fmt='- Selected "Yes". Opening Remote Control...' ;;
            esac
            ;;
        cust_stopping_old)
            case "$_lang" in
                zh-TW) _fmt='  - 正在關閉舊的 Remote Control...' ;;
                zh-CN) _fmt='  - 正在关闭旧的 Remote Control...' ;;
                ja)    _fmt='  - 以前の Remote Control を終了中...' ;;
                *)     _fmt='  - Closing previous Remote Control...' ;;
            esac
            ;;
        cust_warn_old_slow)
            case "$_lang" in
                zh-TW) _fmt='  ! 提示: 舊的 Remote Control 關閉較慢，將直接啟動新版' ;;
                zh-CN) _fmt='  ! 提示: 旧的 Remote Control 关闭较慢，将直接启动新版' ;;
                ja)    _fmt='  ! ヒント: 以前の Remote Control の終了に時間がかかっています。新しい起動を続行します' ;;
                *)     _fmt='  ! Notice: Previous Remote Control took too long to close; starting the new one' ;;
            esac
            ;;
        cust_hint_no_token_wait)
            case "$_lang" in
                zh-TW) _fmt="  [提示] 尚未登入 Google，會先在背景待命，請到 Termux 執行 'agy' 完成登入後即自動上線" ;;
                zh-CN) _fmt="  [提示] 尚未登录 Google，会先在后台待命，请到 Termux 执行 'agy' 完成登录后即自动上线" ;;
                ja)    _fmt="  [ヒント] Google 未ログインのため待機状態で開始します。Termux で 'agy' ログイン後に自動接続します" ;;
                *)     _fmt="  [Tip] Not signed in to Google yet; waiting in standby until you run 'agy' in Termux to log in" ;;
            esac
            ;;
        cust_ok_started)
            case "$_lang" in
                zh-TW) _fmt='  [OK] Remote Control 已在背景打開！(tmux 會話: agy)' ;;
                zh-CN) _fmt='  [OK] Remote Control 已在后台打开！(tmux 会话: agy)' ;;
                ja)    _fmt='  [OK] Remote Control がバックグラウンドで開きました！(tmux セッション: agy)' ;;
                *)     _fmt='  [OK] Remote Control is now open in the background! (tmux session: agy)' ;;
            esac
            ;;
        cust_hint_started_use)
            case "$_lang" in
                zh-TW) _fmt='  [提示] 若暫不重開機，現在即可使用；在 Termux 輸入 agy-status / agy-attach 可查看狀態' ;;
                zh-CN) _fmt='  [提示] 若暂不重启，现在即可使用；在 Termux 输入 agy-status / agy-attach 可查看状态' ;;
                ja)    _fmt='  [ヒント] 再起動なしですぐ利用できます。Termux で agy-status / agy-attach を入力すると状態を確認できます' ;;
                *)     _fmt='  [Tip] Ready to use now without rebooting; run agy-status / agy-attach in Termux to check status' ;;
            esac
            ;;
        cust_ok_standby_ready)
            case "$_lang" in
                zh-TW) _fmt='  [OK] Remote Control 已開啟背景待命！(tmux 會話: agy)' ;;
                zh-CN) _fmt='  [OK] Remote Control 已开启后台待命！(tmux 会话: agy)' ;;
                ja)    _fmt='  [OK] Remote Control がバックグラウンド待機状態で起動しました！(tmux セッション: agy)' ;;
                *)     _fmt='  [OK] Remote Control standby mode is active! (tmux session: agy)' ;;
            esac
            ;;
        cust_hint_standby_login)
            case "$_lang" in
                zh-TW) _fmt="  [提示] 請開啟 Termux 執行 'agy' 完成 Google 帳號登入，登入後數秒內將自動啟動上線" ;;
                zh-CN) _fmt="  [提示] 请打开 Termux 执行 'agy' 完成 Google 账号登录，登录后数秒内将自动启动上线" ;;
                ja)    _fmt="  [ヒント] Termux を開いて 'agy' を実行し Google アカウントでログインすると、数秒以内に自動起動します" ;;
                *)     _fmt="  [Tip] Open Termux and run 'agy' to sign in with Google; Remote Control will connect within seconds" ;;
            esac
            ;;
        cust_hint_scheduled)
            case "$_lang" in
                zh-TW) _fmt='  [提示] 正在背景打開 Remote Control，待連網檢查完成後數秒內即就緒' ;;
                zh-CN) _fmt='  [提示] 正在后台打开 Remote Control，待联网检查完成后数秒内即就绪' ;;
                ja)    _fmt='  [ヒント] バックグラウンドで Remote Control を開いています（ネットワーク確認後数秒で完了します）' ;;
                *)     _fmt='  [Tip] Opening Remote Control in the background (ready shortly after network check)' ;;
            esac
            ;;
        cust_hint_check_log)
            case "$_lang" in
                zh-TW) _fmt='  [提示] 稍後可於 Termux 輸入 agy-status 或 agy-log 確認啟動狀態' ;;
                zh-CN) _fmt='  [提示] 稍后可在 Termux 输入 agy-status 或 agy-log 确认启动状态' ;;
                ja)    _fmt='  [ヒント] 後ほど Termux で agy-status または agy-log を入力して起動状況を確認できます' ;;
                *)     _fmt='  [Tip] Run agy-status or agy-log in Termux later to verify startup status' ;;
            esac
            ;;
        cust_choice_no)
            case "$_lang" in
                zh-TW) _fmt='- 已選擇「否」，不會打開 Remote Control（重開機後也不會自動打開）' ;;
                zh-CN) _fmt='- 已选择“否”，不会打开 Remote Control（重启后也不会自动打开）' ;;
                ja)    _fmt='- 「いいえ」が選択されたため、Remote Control は開きません（再起動後も自動では開きません）' ;;
                *)     _fmt='- Selected "No". Remote Control will stay off (and will not auto-open after reboot)' ;;
            esac
            ;;
        cust_choice_no_stopped)
            case "$_lang" in
                zh-TW) _fmt='- 已選擇「否」，已關閉 Remote Control（重開機後也不會自動打開）' ;;
                zh-CN) _fmt='- 已选择“否”，已关闭 Remote Control（重启后也不会自动打开）' ;;
                ja)    _fmt='- 「いいえ」が選択されたため、Remote Control を閉じました（再起動後も自動では開きません）' ;;
                *)     _fmt='- Selected "No". Closed Remote Control (and it will not auto-open after reboot)' ;;
            esac
            ;;
        cust_choice_timeout)
            case "$_lang" in
                zh-TW) _fmt='- 15 秒內未偵測到按鍵輸入，預設為「否」（不打開，重開機後也不會自動打開）' ;;
                zh-CN) _fmt='- 15 秒内未检测到按键输入，默认为“否”（不打开，重启后也不会自动打开）' ;;
                ja)    _fmt='- 15秒以内にキー入力が検出されなかったため「いいえ」になりました（起動せず、再起動後も自動では開きません）' ;;
                *)     _fmt='- No key press detected within 15s; defaulted to "No" (stays off now and after reboot)' ;;
            esac
            ;;
        cust_choice_timeout_keep)
            case "$_lang" in
                zh-TW) _fmt='- 15 秒內未偵測到按鍵輸入，維持原本開啟中的狀態不中斷' ;;
                zh-CN) _fmt='- 15 秒内未检测到按键输入，维持原本开启中的状态不中断' ;;
                ja)    _fmt='- 15秒以内にキー入力が検出されなかったため、現在起動中の状態をそのまま維持します' ;;
                *)     _fmt='- No key press detected within 15s; keeping the already-running session active' ;;
            esac
            ;;
        cust_choice_keep)
            case "$_lang" in
                zh-TW) _fmt='- 已保留目前的 Remote Control 狀態不變' ;;
                zh-CN) _fmt='- 已保留当前的 Remote Control 状态不变' ;;
                ja)    _fmt='- 現在の Remote Control 状態をそのまま保持しました' ;;
                *)     _fmt='- Preserved current Remote Control state' ;;
            esac
            ;;
        cust_choice_no_ev)
            case "$_lang" in
                zh-TW) _fmt='- 無法讀取音量鍵事件，略過立即開啟（可於 Termux 執行 agy-start 手動開啟）' ;;
                zh-CN) _fmt='- 无法读取音量键事件，跳过立即开启（可在 Termux 执行 agy-start 手动开启）' ;;
                ja)    _fmt='- 音量キーイベントを読み取れないため即時起動をスキップします（Termux で agy-start を手動実行できます）' ;;
                *)     _fmt='- Unable to read volume key events; skipping immediate start (run agy-start in Termux manually)' ;;
            esac
            ;;
        cust_done_title)
            case "$_lang" in
                zh-TW) _fmt='* antigravity-android 安裝成功！(%s Root + 多語言)' ;;
                zh-CN) _fmt='* antigravity-android 安装成功！(%s Root + 多语言)' ;;
                ja)    _fmt='* antigravity-android のインストールに成功しました！(%s Root + 多言語)' ;;
                *)     _fmt='* antigravity-android installed! (%s Root + i18n)' ;;
            esac
            ;;
        cust_done_sub)
            case "$_lang" in
                zh-TW) _fmt='* 重開機並解鎖後將以 root 自動上線為:' ;;
                zh-CN) _fmt='* 重启并解锁后将以 root 自动上线为:' ;;
                ja)    _fmt='* 再起動・ロック解除後に root で自動接続されます:' ;;
                *)     _fmt='* After reboot & unlock, will come online as root:' ;;
            esac
            ;;
        cust_done_sub_disabled)
            case "$_lang" in
                zh-TW) _fmt='* Remote Control 目前已設定為關閉（重開機後不會自動開啟）' ;;
                zh-CN) _fmt='* Remote Control 当前已设置为关闭（重启后不会自动开启）' ;;
                ja)    _fmt='* Remote Control は現在オフに設定されています（再起動後も自動で開きません）' ;;
                *)     _fmt='* Remote Control is currently disabled (will not auto-open after reboot)' ;;
            esac
            ;;
        cust_done_sub_disabled_hint)
            case "$_lang" in
                zh-TW) _fmt='* 如需重新開啟，請在 Termux 執行 agy-start 或重刷模組選「是」' ;;
                zh-CN) _fmt='* 如需重新开启，请在 Termux 执行 agy-start 或重刷模块选“是”' ;;
                ja)    _fmt='* 再開する場合は Termux で agy-start を実行するか、再フラッシュ時に「はい」を選択してください' ;;
                *)     _fmt='* To re-enable later, run agy-start in Termux or re-flash and choose Yes' ;;
            esac
            ;;

        # --- service.sh ---
        svc_started)
            case "$_lang" in
                zh-TW) _fmt='Antigravity 開機服務已啟動 (PID: %s, UID: %s)' ;;
                zh-CN) _fmt='Antigravity 开机服务已启动 (PID: %s, UID: %s)' ;;
                ja)    _fmt='Antigravity ブートサービスを開始しました (PID: %s, UID: %s)' ;;
                *)     _fmt='Antigravity Boot Service started (PID: %s, UID: %s)' ;;
            esac
            ;;
        svc_boot_completed)
            case "$_lang" in
                zh-TW) _fmt='Android 系統開機完成 (sys.boot_completed=1)' ;;
                zh-CN) _fmt='Android 系统开机完成 (sys.boot_completed=1)' ;;
                ja)    _fmt='Android の起動が完了しました (sys.boot_completed=1)' ;;
                *)     _fmt='Android boot completed (sys.boot_completed=1)' ;;
            esac
            ;;
        svc_ce_unlocked)
            case "$_lang" in
                zh-TW) _fmt='使用者資料庫已解鎖，Termux 可正常讀取！' ;;
                zh-CN) _fmt='用户数据库已解锁，Termux 可正常读取！' ;;
                ja)    _fmt='ユーザーデータベースのロックが解除され、Termux が読み取り可能になりました！' ;;
                *)     _fmt='User CE storage unlocked; Termux paths readable!' ;;
            esac
            ;;
        svc_wait_net)
            case "$_lang" in
                zh-TW) _fmt='等待網路就緒...' ;;
                zh-CN) _fmt='等待网络就绪...' ;;
                ja)    _fmt='ネットワーク接続を待機中...' ;;
                *)     _fmt='Waiting for network connectivity...' ;;
            esac
            ;;
        svc_net_ready)
            case "$_lang" in
                zh-TW) _fmt='網路已連通！' ;;
                zh-CN) _fmt='网络已连通！' ;;
                ja)    _fmt='ネットワークに接続しました！' ;;
                *)     _fmt='Network is online!' ;;
            esac
            ;;
        svc_env_warn)
            case "$_lang" in
                zh-TW) _fmt='[警告] 環境檢查回傳非 0 (%s)' ;;
                zh-CN) _fmt='[警告] 环境检查返回非 0 (%s)' ;;
                ja)    _fmt='[警告] 環境チェックが 0 以外を返しました (%s)' ;;
                *)     _fmt='[WARN] Environment check returned non-zero (%s)' ;;
            esac
            ;;
        svc_hostname)
            case "$_lang" in
                zh-TW) _fmt='本機固定名稱: %s' ;;
                zh-CN) _fmt='本机固定名称: %s' ;;
                ja)    _fmt='端末の固定ホスト名: %s' ;;
                *)     _fmt='Persistent device hostname: %s' ;;
            esac
            ;;
        svc_launching)
            case "$_lang" in
                zh-TW) _fmt='正在以 root 身分啟動 Antigravity 遠端守護行程 (UID: %s)...' ;;
                zh-CN) _fmt='正在以 root 身份启动 Antigravity 远程守护进程 (UID: %s)...' ;;
                ja)    _fmt='Antigravity リモートデーモンを root 権限で起動中 (UID: %s)...' ;;
                *)     _fmt='Starting Antigravity remote-control daemon as root (UID: %s)...' ;;
            esac
            ;;
        svc_launch_done)
            case "$_lang" in
                zh-TW) _fmt='服務啟動完成 (回傳碼: %s)' ;;
                zh-CN) _fmt='服务启动完成 (返回码: %s)' ;;
                ja)    _fmt='サービスの起動が完了しました (終了コード: %s)' ;;
                *)     _fmt='Service launch finished (exit code: %s)' ;;
            esac
            ;;
        svc_err_no_bash)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 缺少 Termux bash，無法啟動服務！' ;;
                zh-CN) _fmt='[ERR] 缺少 Termux bash，无法启动服务！' ;;
                ja)    _fmt='[ERR] Termux の bash が見つからないため、サービスを起動できません！' ;;
                *)     _fmt='[ERR] Termux bash missing; cannot start service!' ;;
            esac
            ;;
        svc_rc_disabled)
            case "$_lang" in
                zh-TW) _fmt='使用者已設定關閉 Remote Control (~/.gemini/config/remote_control=0)，本次開機不自動啟動。' ;;
                zh-CN) _fmt='用户已设置关闭 Remote Control (~/.gemini/config/remote_control=0)，本次开机不自动启动。' ;;
                ja)    _fmt='ユーザー設定により Remote Control は無効化されているため (~/.gemini/config/remote_control=0)、起動時の自動起動をスキップします。' ;;
                *)     _fmt='Remote Control is disabled by user choice (~/.gemini/config/remote_control=0); skipping boot auto-start.' ;;
            esac
            ;;

        # --- ensure_antigravity_env.sh ---
        env_err_no_priv)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 找不到可用的降權工具 (setpriv / python3 / su -G)' ;;
                zh-CN) _fmt='[ERR] 找不到可用的降权工具 (setpriv / python3 / su -G)' ;;
                ja)    _fmt='[ERR] 利用可能な権限降格ツールが見つかりません (setpriv / python3 / su -G)' ;;
                *)     _fmt='[ERR] No privilege-drop helper available (setpriv / python3 / su -G)' ;;
            esac
            ;;
        env_warn_resolv_perm)
            case "$_lang" in
                zh-TW) _fmt='[警告] resolv.conf 權限受限，無法讀取或更新（需 root 權限修正）' ;;
                zh-CN) _fmt='[警告] resolv.conf 权限受限，无法读取或更新（需 root 权限修正）' ;;
                ja)    _fmt='[警告] resolv.conf の権限が制限されており読み書きできません (root 権限が必要)' ;;
                *)     _fmt='[WARN] resolv.conf permission denied; cannot read or update (root required)' ;;
            esac
            ;;
        env_fix_resolv)
            case "$_lang" in
                zh-TW) _fmt='[補全] 已寫入備援 DNS 設定至 resolv.conf' ;;
                zh-CN) _fmt='[补全] 已写入备用 DNS 设置至 resolv.conf' ;;
                ja)    _fmt='[補完] resolv.conf にフォールバック DNS 設定を書き込みました' ;;
                *)     _fmt='[Provision] Wrote fallback DNS servers to resolv.conf' ;;
            esac
            ;;
        env_warn_hosts_perm)
            case "$_lang" in
                zh-TW) _fmt='[警告] %s 權限受限，無法讀取或更新' ;;
                zh-CN) _fmt='[警告] %s 权限受限，无法读取或更新' ;;
                ja)    _fmt='[警告] %s の権限が制限されており読み書きできません' ;;
                *)     _fmt='[WARN] %s permission denied; cannot read or update' ;;
            esac
            ;;
        env_fix_hosts)
            case "$_lang" in
                zh-TW) _fmt='[補全] 已補全本機解析設定: %s' ;;
                zh-CN) _fmt='[补全] 已补全本机解析设置: %s' ;;
                ja)    _fmt='[補完] ローカルホスト解決設定を補完しました: %s' ;;
                *)     _fmt='[Provision] Updated localhost entries in: %s' ;;
            esac
            ;;
        env_warn_nss_perm)
            case "$_lang" in
                zh-TW) _fmt='[警告] glibc/etc/nsswitch.conf 權限受限，無法讀取或更新' ;;
                zh-CN) _fmt='[警告] glibc/etc/nsswitch.conf 权限受限，无法读取或更新' ;;
                ja)    _fmt='[警告] glibc/etc/nsswitch.conf の権限が制限されており読み書きできません' ;;
                *)     _fmt='[WARN] glibc/etc/nsswitch.conf permission denied; cannot read or update' ;;
            esac
            ;;
        env_fix_nss)
            case "$_lang" in
                zh-TW) _fmt='[補全] 已設定 glibc/etc/nsswitch.conf (hosts: files dns)' ;;
                zh-CN) _fmt='[补全] 已设置 glibc/etc/nsswitch.conf (hosts: files dns)' ;;
                ja)    _fmt='[補完] glibc/etc/nsswitch.conf (hosts: files dns) を設定しました' ;;
                *)     _fmt='[Provision] Configured glibc/etc/nsswitch.conf (hosts: files dns)' ;;
            esac
            ;;
        env_warn_glibc_resolv_perm)
            case "$_lang" in
                zh-TW) _fmt='[警告] glibc/etc/resolv.conf 權限受限，無法讀取或更新' ;;
                zh-CN) _fmt='[警告] glibc/etc/resolv.conf 权限受限，无法读取或更新' ;;
                ja)    _fmt='[警告] glibc/etc/resolv.conf の権限が制限されており読み書きできません' ;;
                *)     _fmt='[WARN] glibc/etc/resolv.conf permission denied; cannot read or update' ;;
            esac
            ;;
        env_fix_glibc_resolv)
            case "$_lang" in
                zh-TW) _fmt='[補全] 已連結 glibc/etc/resolv.conf -> etc/resolv.conf' ;;
                zh-CN) _fmt='[补全] 已链接 glibc/etc/resolv.conf -> etc/resolv.conf' ;;
                ja)    _fmt='[補完] glibc/etc/resolv.conf -> etc/resolv.conf をリンクしました' ;;
                *)     _fmt='[Provision] Linked glibc/etc/resolv.conf -> etc/resolv.conf' ;;
            esac
            ;;
        env_ok_glibc_net)
            case "$_lang" in
                zh-TW) _fmt='[OK] glibc DNS/hosts/NSS 設定就緒' ;;
                zh-CN) _fmt='[OK] glibc DNS/hosts/NSS 设置就绪' ;;
                ja)    _fmt='[OK] glibc DNS/hosts/NSS 設定の準備が完了しました' ;;
                *)     _fmt='[OK] glibc DNS/hosts/NSS configuration ready' ;;
            esac
            ;;
        env_install_pkgs)
            case "$_lang" in
                zh-TW) _fmt='[補全] 安裝缺失套件: %s' ;;
                zh-CN) _fmt='[补全] 安装缺失软件包: %s' ;;
                ja)    _fmt='[補完] 不足しているパッケージをインストール中: %s' ;;
                *)     _fmt='[Provision] Installing missing packages: %s' ;;
            esac
            ;;
        env_mode_wallentx)
            case "$_lang" in
                zh-TW) _fmt='%s (wallentx 雙二進位 agy + agy.va39)' ;;
                zh-CN) _fmt='%s (wallentx 双二进制 agy + agy.va39)' ;;
                ja)    _fmt='%s (wallentx ツインバイナリ agy + agy.va39)' ;;
                *)     _fmt='%s (wallentx twin-binary agy + agy.va39)' ;;
            esac
            ;;
        env_mode_native)
            case "$_lang" in
                zh-TW) _fmt='%s (Android 原生單檔)' ;;
                zh-CN) _fmt='%s (Android 原生单文件)' ;;
                ja)    _fmt='%s (Android ネイティブ単一バイナリ)' ;;
                *)     _fmt='%s (Android native single binary)' ;;
            esac
            ;;
        env_dl_wallentx)
            case "$_lang" in
                zh-TW) _fmt='[補全] 正在從 %s 下載 wallentx 雙二進位包...' ;;
                zh-CN) _fmt='[补全] 正在从 %s 下载 wallentx 双二进制包...' ;;
                ja)    _fmt='[補完] %s から wallentx パッケージをダウンロード中...' ;;
                *)     _fmt='[Provision] Downloading wallentx twin-binary tarball from %s...' ;;
            esac
            ;;
        env_err_dl_wallentx)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 下載 antigravity-termux-standalone.tar.gz 失敗' ;;
                zh-CN) _fmt='[ERR] 下载 antigravity-termux-standalone.tar.gz 失败' ;;
                ja)    _fmt='[ERR] antigravity-termux-standalone.tar.gz のダウンロードに失敗しました' ;;
                *)     _fmt='[ERR] Failed to download antigravity-termux-standalone.tar.gz' ;;
            esac
            ;;
        env_err_extract_wallentx)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 解壓 agy / agy.va39 失敗' ;;
                zh-CN) _fmt='[ERR] 解压 agy / agy.va39 失败' ;;
                ja)    _fmt='[ERR] agy / agy.va39 の展開に失敗しました' ;;
                *)     _fmt='[ERR] Failed to extract agy / agy.va39' ;;
            esac
            ;;
        env_ok_wallentx)
            case "$_lang" in
                zh-TW) _fmt='[OK] 已補全安裝 wallentx Antigravity CLI: %s' ;;
                zh-CN) _fmt='[OK] 已补全安装 wallentx Antigravity CLI: %s' ;;
                ja)    _fmt='[OK] wallentx Antigravity CLI を補完インストールしました: %s' ;;
                *)     _fmt='[OK] Installed wallentx Antigravity CLI: %s' ;;
            esac
            ;;
        env_err_verify_agy)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 新安裝的 agy 驗證執行失敗，還原舊檔...' ;;
                zh-CN) _fmt='[ERR] 新安装的 agy 验证运行失败，还原旧文件...' ;;
                ja)    _fmt='[ERR] 新規インストールした agy の検証に失敗しました。旧ファイルを復元します...' ;;
                *)     _fmt='[ERR] Newly installed agy verification failed; restoring backup...' ;;
            esac
            ;;
        env_err_arch)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 僅支援 aarch64 架構 (目前為 %s)' ;;
                zh-CN) _fmt='[ERR] 仅支持 aarch64 架构 (当前为 %s)' ;;
                ja)    _fmt='[ERR] aarch64 アーキテクチャのみサポートされています (現在: %s)' ;;
                *)     _fmt='[ERR] Only aarch64 architecture is supported (current: %s)' ;;
            esac
            ;;
        env_err_no_termux_home)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 找不到完整的 Termux 目錄環境 (%s)' ;;
                zh-CN) _fmt='[ERR] 找不到完整的 Termux 目录环境 (%s)' ;;
                ja)    _fmt='[ERR] 完全な Termux ディレクトリ環境が見つかりません (%s)' ;;
                *)     _fmt='[ERR] Complete Termux directory not found (%s)' ;;
            esac
            ;;
        env_err_init_termux)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 找不到完整的 Termux 環境，請先開啟 Termux App 完成初始化。' ;;
                zh-CN) _fmt='[ERR] 找不到完整的 Termux 环境，请先打开 Termux App 完成初始化。' ;;
                ja)    _fmt='[ERR] Termux 環境が不完全です。先に Termux アプリを起動して初期化してください。' ;;
                *)     _fmt='[ERR] Termux environment incomplete; open Termux App first to initialize.' ;;
            esac
            ;;
        env_ok_pkg)
            case "$_lang" in
                zh-TW) _fmt='[OK] 套件與元件就緒: %s' ;;
                zh-CN) _fmt='[OK] 软件包与组件就绪: %s' ;;
                ja)    _fmt='[OK] パッケージ・コンポーネント準備完了: %s' ;;
                *)     _fmt='[OK] Package and component ready: %s' ;;
            esac
            ;;
        env_miss_pkg)
            case "$_lang" in
                zh-TW) _fmt='[缺失] %s' ;;
                zh-CN) _fmt='[缺失] %s' ;;
                ja)    _fmt='[不足] %s' ;;
                *)     _fmt='[Missing] %s' ;;
            esac
            ;;
        env_ok_glibc)
            case "$_lang" in
                zh-TW) _fmt='[OK] glibc 執行庫就緒' ;;
                zh-CN) _fmt='[OK] glibc 运行库就绪' ;;
                ja)    _fmt='[OK] glibc ランタイムライブラリ準備完了' ;;
                *)     _fmt='[OK] glibc runtime library ready' ;;
            esac
            ;;
        env_miss_glibc)
            case "$_lang" in
                zh-TW) _fmt='[缺失] glibc (ld-linux-aarch64.so.1)' ;;
                zh-CN) _fmt='[缺失] glibc (ld-linux-aarch64.so.1)' ;;
                ja)    _fmt='[不足] glibc (ld-linux-aarch64.so.1)' ;;
                *)     _fmt='[Missing] glibc (ld-linux-aarch64.so.1)' ;;
            esac
            ;;
        env_ok_lse)
            case "$_lang" in
                zh-TW) _fmt='[OK] CPU 支援 ARMv8.1 LSE (atomics)，無需 QEMU' ;;
                zh-CN) _fmt='[OK] CPU 支持 ARMv8.1 LSE (atomics)，无需 QEMU' ;;
                ja)    _fmt='[OK] CPU は ARMv8.1 LSE (atomics) 対応のため QEMU は不要です' ;;
                *)     _fmt='[OK] CPU supports ARMv8.1 LSE (atomics); QEMU not needed' ;;
            esac
            ;;
        env_ok_qemu)
            case "$_lang" in
                zh-TW) _fmt='[OK] CPU 缺少 LSE，已就緒 QEMU 模擬器 (qemu-aarch64)' ;;
                zh-CN) _fmt='[OK] CPU 缺少 LSE，已就绪 QEMU 模拟器 (qemu-aarch64)' ;;
                ja)    _fmt='[OK] CPU が LSE 非対応のため QEMU エミュレータ準備完了 (qemu-aarch64)' ;;
                *)     _fmt='[OK] CPU lacks LSE; QEMU user-mode ready (qemu-aarch64)' ;;
            esac
            ;;
        env_miss_qemu)
            case "$_lang" in
                zh-TW) _fmt='[缺失] CPU 缺少 LSE，需要補裝 qemu-user-aarch64' ;;
                zh-CN) _fmt='[缺失] CPU 缺少 LSE，需要补装 qemu-user-aarch64' ;;
                ja)    _fmt='[不足] CPU が LSE 非対応のため qemu-user-aarch64 の導入が必要です' ;;
                *)     _fmt='[Missing] CPU lacks LSE; need to install qemu-user-aarch64' ;;
            esac
            ;;
        env_warn_offline_pkgs)
            case "$_lang" in
                zh-TW) _fmt='[警告] 目前無可用網路，略過線上補裝套件，將於開機連網後自動完成。' ;;
                zh-CN) _fmt='[警告] 当前无可用网络，跳过在线补装软件包，将于开机联网后自动完成。' ;;
                ja)    _fmt='[警告] ネットワークに接続できないためパッケージ導入をスキップします（起動後の接続時に自動完了します）。' ;;
                *)     _fmt='[WARN] Network unavailable now; skipping online packages (will complete after boot once online).' ;;
            esac
            ;;
        env_apt_update)
            case "$_lang" in
                zh-TW) _fmt='[補全] 正在更新 Termux apt 套件索引...' ;;
                zh-CN) _fmt='[补全] 正在更新 Termux apt 软件包索引...' ;;
                ja)    _fmt='[補完] Termux apt パッケージインデックスを更新中...' ;;
                *)     _fmt='[Provision] Updating Termux apt package index...' ;;
            esac
            ;;
        env_err_apt_stage1)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 安裝基礎套件失敗: %s' ;;
                zh-CN) _fmt='[ERR] 安装基础软件包失败: %s' ;;
                ja)    _fmt='[ERR] 基本パッケージのインストールに失敗しました: %s' ;;
                *)     _fmt='[ERR] Failed to install base packages: %s' ;;
            esac
            ;;
        env_apt_glibc)
            case "$_lang" in
                zh-TW) _fmt='[補全] 同步 termux-glibc 套件庫索引...' ;;
                zh-CN) _fmt='[补全] 同步 termux-glibc 软件源索引...' ;;
                ja)    _fmt='[補完] termux-glibc リポジトリインデックスを同期中...' ;;
                *)     _fmt='[Provision] Syncing termux-glibc repository index...' ;;
            esac
            ;;
        env_err_apt_stage2)
            case "$_lang" in
                zh-TW) _fmt='[ERR] 安裝 glibc/QEMU 套件失敗: %s' ;;
                zh-CN) _fmt='[ERR] 安装 glibc/QEMU 软件包失败: %s' ;;
                ja)    _fmt='[ERR] glibc/QEMU パッケージのインストールに失敗しました: %s' ;;
                *)     _fmt='[ERR] Failed to install glibc/QEMU packages: %s' ;;
            esac
            ;;
        env_ok_agy)
            case "$_lang" in
                zh-TW) _fmt='[OK] agy 就緒: %s' ;;
                zh-CN) _fmt='[OK] agy 就绪: %s' ;;
                ja)    _fmt='[OK] agy 準備完了: %s' ;;
                *)     _fmt='[OK] agy ready: %s' ;;
            esac
            ;;
        env_force_wallentx)
            case "$_lang" in
                zh-TW) _fmt='[補全] 依設定強制重裝 wallentx 雙二進位版本...' ;;
                zh-CN) _fmt='[补全] 按设置强制重装 wallentx 双二进制版本...' ;;
                ja)    _fmt='[補完] 指定により wallentx ツインバイナリ版を強制再インストール中...' ;;
                *)     _fmt='[Provision] Forcing reinstall of wallentx twin-binary build as requested...' ;;
            esac
            ;;
        env_miss_va39)
            case "$_lang" in
                zh-TW) _fmt='[缺失] 偵測到 wallentx 啟動器缺少主程式 agy.va39，準備重新補全...' ;;
                zh-CN) _fmt='[缺失] 检测到 wallentx 启动器缺少主程序 agy.va39，准备重新补全...' ;;
                ja)    _fmt='[不足] wallentx ランチャーの本体 agy.va39 が欠落しているため再補完を準備中...' ;;
                *)     _fmt='[Missing] wallentx launcher is missing agy.va39 main binary; preparing reinstall...' ;;
            esac
            ;;
        env_miss_agy)
            case "$_lang" in
                zh-TW) _fmt='[缺失] 尚未安裝可用的 Antigravity CLI (agy)，準備從 wallentx/antigravity-cli-termux 下載...' ;;
                zh-CN) _fmt='[缺失] 尚未安装可用的 Antigravity CLI (agy)，准备从 wallentx/antigravity-cli-termux 下载...' ;;
                ja)    _fmt='[不足] 使用可能な Antigravity CLI (agy) が見つかりません。wallentx/antigravity-cli-termux からの取得を準備中...' ;;
                *)     _fmt='[Missing] No usable Antigravity CLI (agy) installed; preparing download from wallentx/antigravity-cli-termux...' ;;
            esac
            ;;
        env_warn_offline_agy)
            case "$_lang" in
                zh-TW) _fmt='[警告] 目前無可用網路，無法下載 agy，將於開機連網後自動完成。' ;;
                zh-CN) _fmt='[警告] 当前无可用网络，无法下载 agy，将于开机联网后自动完成。' ;;
                ja)    _fmt='[警告] ネットワークに接続できないため agy をダウンロードできません（起動後の接続時に自動完了します）。' ;;
                *)     _fmt='[WARN] Network unavailable now; cannot download agy (will complete after boot once online).' ;;
            esac
            ;;

        # --- agy_boot_service.sh ---
        boot_auto_reload)
            case "$_lang" in
                zh-TW) _fmt='[auto-reload] 偵測到登入憑證變更或未認證狀態 (pid=%s, state=%s)，正在重啟 agy...' ;;
                zh-CN) _fmt='[auto-reload] 检测到登录凭证变更或未认证状态 (pid=%s, state=%s)，正在重启 agy...' ;;
                ja)    _fmt='[auto-reload] 認証トークンの変更または未認証状態を検出 (pid=%s, state=%s)。agy を再起動中...' ;;
                *)     _fmt='[auto-reload] Detected token change or unauth state for pid=%s (state=%s); restarting agy...' ;;
            esac
            ;;
        boot_wait_token)
            case "$_lang" in
                zh-TW) _fmt="[waiting-login] 等待有效的 antigravity-oauth-token（請於 Termux 執行 'agy' 完成登入）..." ;;
                zh-CN) _fmt="[waiting-login] 等待有效的 antigravity-oauth-token（请在 Termux 执行 'agy' 完成登录）..." ;;
                ja)    _fmt="[waiting-login] 有効な antigravity-oauth-token を待機中（Termux で 'agy' を実行してログインしてください）..." ;;
                *)     _fmt="[waiting-login] Waiting for valid antigravity-oauth-token (please run 'agy' in Termux to sign in)..." ;;
            esac
            ;;
        boot_token_detected)
            case "$_lang" in
                zh-TW) _fmt='[waiting-login] 偵測到有效 antigravity-oauth-token，1 秒後啟動 Remote Control...' ;;
                zh-CN) _fmt='[waiting-login] 检测到有效 antigravity-oauth-token，1 秒后启动 Remote Control...' ;;
                ja)    _fmt='[waiting-login] 有効な antigravity-oauth-token を検出しました。1秒後に Remote Control を起動します...' ;;
                *)     _fmt='[waiting-login] Detected valid antigravity-oauth-token; waiting 1s before launching Remote Control...' ;;
            esac
            ;;
        boot_launching)
            case "$_lang" in
                zh-TW) _fmt='正在啟動 agy --remote-control (uid=%s, wallentx=%s)...' ;;
                zh-CN) _fmt='正在启动 agy --remote-control (uid=%s, wallentx=%s)...' ;;
                ja)    _fmt='agy --remote-control を起動中 (uid=%s, wallentx=%s)...' ;;
                *)     _fmt='Launching agy --remote-control (uid=%s, wallentx=%s)...' ;;
            esac
            ;;
        boot_exited)
            case "$_lang" in
                zh-TW) _fmt='agy 已結束（代碼 %s），5 秒後重新連線...' ;;
                zh-CN) _fmt='agy 已退出（代码 %s），5 秒后重新连接...' ;;
                ja)    _fmt='agy が終了しました (コード %s)。5秒後に再接続します...' ;;
                *)     _fmt='agy exited with code %s. Reconnecting in 5 seconds...' ;;
            esac
            ;;
        boot_startup_in_progress)
            case "$_lang" in
                zh-TW) _fmt='啟動程序已在進行中。' ;;
                zh-CN) _fmt='启动流程已在进行中。' ;;
                ja)    _fmt='起動処理はすでに進行中です。' ;;
                *)     _fmt='Startup already in progress.' ;;
            esac
            ;;
        boot_already_running)
            case "$_lang" in
                zh-TW) _fmt='agy --remote-control 已在執行中 (uid=%s)。' ;;
                zh-CN) _fmt='agy --remote-control 已在运行中 (uid=%s)。' ;;
                ja)    _fmt='agy --remote-control はすでに稼働中です (uid=%s)。' ;;
                *)     _fmt='agy --remote-control is already running (uid=%s).' ;;
            esac
            ;;
        boot_root_lock_active)
            case "$_lang" in
                zh-TW) _fmt='Root 守護鎖定已處於啟用狀態。' ;;
                zh-CN) _fmt='Root 守护锁定已处于启用状态。' ;;
                ja)    _fmt='Root 保護ロックはすでに有効です。' ;;
                *)     _fmt='Root agy service lock is already active.' ;;
            esac
            ;;
        boot_net_verified)
            case "$_lang" in
                zh-TW) _fmt='已確認網際網路連線正常 (uid=%s)。' ;;
                zh-CN) _fmt='已确认网络连接正常 (uid=%s)。' ;;
                ja)    _fmt='インターネット接続を確認しました (uid=%s)。' ;;
                *)     _fmt='Internet connectivity verified (uid=%s).' ;;
            esac
            ;;
        boot_tmux_running)
            case "$_lang" in
                zh-TW) _fmt="tmux 會話 'agy' 已在執行中。" ;;
                zh-CN) _fmt="tmux 会话 'agy' 已在运行中。" ;;
                ja)    _fmt="tmux セッション 'agy' はすでに稼働中です。" ;;
                *)     _fmt="tmux session 'agy' already running." ;;
            esac
            ;;
        boot_running_outside)
            case "$_lang" in
                zh-TW) _fmt="agy --remote-control 已在 tmux 會話 'agy' 之外執行。" ;;
                zh-CN) _fmt="agy --remote-control 已在 tmux 会话 'agy' 之外运行。" ;;
                ja)    _fmt="agy --remote-control は tmux セッション 'agy' の外で稼働中です。" ;;
                *)     _fmt="agy --remote-control is already running outside tmux session 'agy'." ;;
            esac
            ;;
        boot_tmux_starting)
            case "$_lang" in
                zh-TW) _fmt="正在於 tmux 會話 'agy' 中啟動 agy remote-control (uid=%s, user=%s)..." ;;
                zh-CN) _fmt="正在 tmux 会话 'agy' 中启动 agy remote-control (uid=%s, user=%s)..." ;;
                ja)    _fmt="tmux セッション 'agy' で agy remote-control を起動中 (uid=%s, user=%s)..." ;;
                *)     _fmt="Starting agy remote-control in tmux session 'agy' (uid=%s, user=%s)..." ;;
            esac
            ;;
        boot_rc_disabled)
            case "$_lang" in
                zh-TW) _fmt="Remote Control 目前已設定為關閉 (remote_control=0)，略過啟動。若要重新開啟請在 Termux 執行 agy-start。" ;;
                zh-CN) _fmt="Remote Control 当前已设置为关闭 (remote_control=0)，跳过启动。若要重新开启请在 Termux 执行 agy-start。" ;;
                ja)    _fmt="Remote Control は現在無効 (remote_control=0) のため起動をスキップします。再開するには Termux で agy-start を実行してください。" ;;
                *)     _fmt="Remote Control is disabled (remote_control=0); skipping startup. Run agy-start in Termux to re-enable." ;;
            esac
            ;;

        # --- bashrc_block.sh ---
        bashrc_su_fail)
            case "$_lang" in
                zh-TW) _fmt='su 提權失敗，改以目前使用者啟動...' ;;
                zh-CN) _fmt='su 提权失败，改以当前用户启动...' ;;
                ja)    _fmt='su による権限昇格に失敗しました。現在のユーザーで起動します...' ;;
                *)     _fmt='su elevation failed; starting as current user instead...' ;;
            esac
            ;;
        bashrc_status_wait_root)
            case "$_lang" in
                zh-TW) _fmt="⏳ Antigravity Remote Control Root 待機中 (尚未登入，請於 Termux 執行 'agy' 完成 Google 登入)" ;;
                zh-CN) _fmt="⏳ Antigravity Remote Control Root 待机中 (尚未登录，请在 Termux 执行 'agy' 完成 Google 登录)" ;;
                ja)    _fmt="⏳ Antigravity Remote Control Root 待機中 (未ログインです。Termux で 'agy' を実行して Google ログインしてください)" ;;
                *)     _fmt="⏳ Antigravity Remote Control Root in standby (not signed in; run 'agy' in Termux to sign in with Google)" ;;
            esac
            ;;
        bashrc_not_running)
            case "$_lang" in
                zh-TW) _fmt='Antigravity remote-control 尚未運行' ;;
                zh-CN) _fmt='Antigravity remote-control 尚未运行' ;;
                ja)    _fmt='Antigravity remote-control はまだ起動していません' ;;
                *)     _fmt='Antigravity remote-control is not running' ;;
            esac
            ;;
        bashrc_root_locked)
            case "$_lang" in
                zh-TW) _fmt='● Root 守護鎖定中 (%s)' ;;
                zh-CN) _fmt='● Root 守护锁定中 (%s)' ;;
                ja)    _fmt='● Root デーモンロック有効 (%s)' ;;
                *)     _fmt='● Root daemon lock active (%s)' ;;
            esac
            ;;
        bashrc_conn_wait_oauth)
            case "$_lang" in
                zh-TW) _fmt="  連線狀態: 等待 Google OAuth 登入 (請於 Termux 執行 'agy' 完成登入，完成後將自動上線)" ;;
                zh-CN) _fmt="  连接状态: 等待 Google OAuth 登录 (请在 Termux 执行 'agy' 完成登录，完成后将自动上线)" ;;
                ja)    _fmt="  接続状態: Google OAuth ログイン待機中 (Termux で 'agy' を実行すると自動で接続されます)" ;;
                *)     _fmt="  Connection: Waiting for Google OAuth sign-in (run 'agy' in Termux; will come online automatically)" ;;
            esac
            ;;
        bashrc_starting)
            case "$_lang" in
                zh-TW) _fmt='✦ Antigravity remote-control 正在啟動中...' ;;
                zh-CN) _fmt='✦ Antigravity remote-control 正在启动中...' ;;
                ja)    _fmt='✦ Antigravity remote-control を起動中です...' ;;
                *)     _fmt='✦ Antigravity remote-control is starting...' ;;
            esac
            ;;
        bashrc_conn_not_logged_in)
            case "$_lang" in
                zh-TW) _fmt="  連線狀態: 尚未登入 (請於 Termux 執行 'agy' 完成登入)" ;;
                zh-CN) _fmt="  连接状态: 尚未登录 (请在 Termux 执行 'agy' 完成登录)" ;;
                ja)    _fmt="  接続状態: 未ログイン (Termux で 'agy' を実行してログインしてください)" ;;
                *)     _fmt="  Connection: Not signed in (run 'agy' in Termux to sign in)" ;;
            esac
            ;;
        bashrc_conn_state)
            case "$_lang" in
                zh-TW) _fmt='  連線狀態: %s' ;;
                zh-CN) _fmt='  连接状态: %s' ;;
                ja)    _fmt='  接続状態: %s' ;;
                *)     _fmt='  Connection: %s' ;;
            esac
            ;;
        bashrc_conn_verifying)
            case "$_lang" in
                zh-TW) _fmt='  連線狀態: 正在驗證連線初始化中...' ;;
                zh-CN) _fmt='  连接状态: 正在验证连接初始化中...' ;;
                ja)    _fmt='  接続状態: 初期接続を確認中...' ;;
                *)     _fmt='  Connection: Verifying initial connection...' ;;
            esac
            ;;
        bashrc_banner_root_wait)
            case "$_lang" in
                zh-TW) _fmt='✦ Antigravity Remote Control 正在背景以 root 待機等待登入 (%s)' ;;
                zh-CN) _fmt='✦ Antigravity Remote Control 正在后台以 root 待机等待登录 (%s)' ;;
                ja)    _fmt='✦ Antigravity Remote Control は root でバックグラウンド待機に移行中 (%s)' ;;
                *)     _fmt='✦ Antigravity Remote Control entering root standby in background (%s)' ;;
            esac
            ;;
        bashrc_banner_need_login)
            case "$_lang" in
                zh-TW) _fmt="  尚未偵測到 Google 登入憑證，請直接執行 'agy' 完成登入（完成後將自動上線）" ;;
                zh-CN) _fmt="  尚未检测到 Google 登录凭证，请直接执行 'agy' 完成登录（完成后将自动上线）" ;;
                ja)    _fmt="  Google ログイン情報が未検出です。'agy' を実行してログインしてください（完了後に自動接続されます）" ;;
                *)     _fmt="  No Google sign-in token found yet; run 'agy' to sign in (comes online automatically)" ;;
            esac
            ;;
        bashrc_banner_root_starting)
            case "$_lang" in
                zh-TW) _fmt='✦ 正在背景以 root 啟動 Antigravity Remote Control (%s)...' ;;
                zh-CN) _fmt='✦ 正在后台以 root 启动 Antigravity Remote Control (%s)...' ;;
                ja)    _fmt='✦ Antigravity Remote Control を root でバックグラウンド起動中 (%s)...' ;;
                *)     _fmt='✦ Starting Antigravity Remote Control as root in background (%s)...' ;;
            esac
            ;;
        bashrc_banner_root_standby)
            case "$_lang" in
                zh-TW) _fmt='⏳ Antigravity Remote Control Root 守護待機中，等待 Google 登入 (%s)' ;;
                zh-CN) _fmt='⏳ Antigravity Remote Control Root 守护待机中，等待 Google 登录 (%s)' ;;
                ja)    _fmt='⏳ Antigravity Remote Control Root は Google ログイン待機中です (%s)' ;;
                *)     _fmt='⏳ Antigravity Remote Control Root in standby waiting for Google sign-in (%s)' ;;
            esac
            ;;
        bashrc_banner_run_agy_status)
            case "$_lang" in
                zh-TW) _fmt="  請在 Termux 執行 'agy' 完成登入（完成後將自動啟動 Remote Control），或輸入 'agy-status' 查看狀態" ;;
                zh-CN) _fmt="  请在 Termux 执行 'agy' 完成登录（完成后将自动启动 Remote Control），或输入 'agy-status' 查看状态" ;;
                ja)    _fmt="  Termux で 'agy' を実行してログインしてください（ログイン後に自動起動）、または 'agy-status' で状態確認できます" ;;
                *)     _fmt="  Run 'agy' in Termux to sign in (Remote Control auto-starts after login), or run 'agy-status' to check status" ;;
            esac
            ;;
        bashrc_banner_root_running)
            case "$_lang" in
                zh-TW) _fmt='● Antigravity Remote Control 正在背景以 root 執行中 (%s)' ;;
                zh-CN) _fmt='● Antigravity Remote Control 正在后台以 root 运行中 (%s)' ;;
                ja)    _fmt='● Antigravity Remote Control はバックグラウンドで root 稼働中 (%s)' ;;
                *)     _fmt='● Antigravity Remote Control running as root in background (%s)' ;;
            esac
            ;;
        bashrc_banner_cmds)
            case "$_lang" in
                zh-TW) _fmt="  輸入 'agy-attach' 查看終端，'agy-stop' 停止，'agy-restart' 重啟，'agy-clean' 清理，'agy-lang' 切換語言" ;;
                zh-CN) _fmt="  输入 'agy-attach' 查看终端，'agy-stop' 停止，'agy-restart' 重启，'agy-clean' 清理，'agy-lang' 切换语言" ;;
                ja)    _fmt="  操作: 'agy-attach' 表示、'agy-stop' 停止、'agy-restart' 再起動、'agy-clean' 整理、'agy-lang' 言語切替" ;;
                *)     _fmt="  Commands: 'agy-attach' view, 'agy-stop' stop, 'agy-restart' restart, 'agy-clean' clean, 'agy-lang' language" ;;
            esac
            ;;
        bashrc_banner_user_wait)
            case "$_lang" in
                zh-TW) _fmt='⏳ Antigravity Remote Control 正在背景進入待機等待登入 (%s)...' ;;
                zh-CN) _fmt='⏳ Antigravity Remote Control 正在后台进入待机等待登录 (%s)...' ;;
                ja)    _fmt='⏳ Antigravity Remote Control はバックグラウンド待機に移行中 (%s)...' ;;
                *)     _fmt='⏳ Antigravity Remote Control entering standby in background (%s)...' ;;
            esac
            ;;
        bashrc_banner_run_agy)
            case "$_lang" in
                zh-TW) _fmt="  請在 Termux 執行 'agy' 完成 Google 登入" ;;
                zh-CN) _fmt="  请在 Termux 执行 'agy' 完成 Google 登录" ;;
                ja)    _fmt="  Termux で 'agy' を実行して Google ログインを完了してください" ;;
                *)     _fmt="  Please run 'agy' in Termux to complete Google sign-in" ;;
            esac
            ;;
        bashrc_banner_user_starting)
            case "$_lang" in
                zh-TW) _fmt='✦ Antigravity Remote Control 正在背景啟動中 (%s)...' ;;
                zh-CN) _fmt='✦ Antigravity Remote Control 正在后台启动中 (%s)...' ;;
                ja)    _fmt='✦ Antigravity Remote Control をバックグラウンド起動中 (%s)...' ;;
                *)     _fmt='✦ Starting Antigravity Remote Control in background (%s)...' ;;
            esac
            ;;
        bashrc_banner_user_standby)
            case "$_lang" in
                zh-TW) _fmt='⏳ Antigravity Remote Control 待機中，等待 Google 登入 (%s)' ;;
                zh-CN) _fmt='⏳ Antigravity Remote Control 待机中，等待 Google 登录 (%s)' ;;
                ja)    _fmt='⏳ Antigravity Remote Control は Google ログイン待機中です (%s)' ;;
                *)     _fmt='⏳ Antigravity Remote Control in standby waiting for Google sign-in (%s)' ;;
            esac
            ;;
        bashrc_banner_user_standby_hint)
            case "$_lang" in
                zh-TW) _fmt="  請在 Termux 執行 'agy' 完成登入（完成後將自動啟動 Remote Control）" ;;
                zh-CN) _fmt="  请在 Termux 执行 'agy' 完成登录（完成后将自动启动 Remote Control）" ;;
                ja)    _fmt="  Termux で 'agy' を実行してログインしてください（ログイン後に自動起動します）" ;;
                *)     _fmt="  Run 'agy' in Termux to sign in (Remote Control auto-starts after login)" ;;
            esac
            ;;
        bashrc_banner_user_running)
            case "$_lang" in
                zh-TW) _fmt='● Antigravity Remote Control 正在背景執行中 (%s)' ;;
                zh-CN) _fmt='● Antigravity Remote Control 正在后台运行中 (%s)' ;;
                ja)    _fmt='● Antigravity Remote Control はバックグラウンドで稼働中 (%s)' ;;
                *)     _fmt='● Antigravity Remote Control running in background (%s)' ;;
            esac
            ;;
        bashrc_banner_disabled)
            case "$_lang" in
                zh-TW) _fmt='○ Antigravity Remote Control 目前已設定為關閉（不會自動打開，重開機後也不會）' ;;
                zh-CN) _fmt='○ Antigravity Remote Control 当前已设置为关闭（不会自动打开，重启后也不会）' ;;
                ja)    _fmt='○ Antigravity Remote Control は現在オフに設定されています（自動起動しません）' ;;
                *)     _fmt='○ Antigravity Remote Control is disabled (will not auto-open now or on reboot)' ;;
            esac
            ;;
        bashrc_banner_disabled_hint)
            case "$_lang" in
                zh-TW) _fmt="  如需重新開啟並恢復自動啟動，請輸入 'agy-start'（或輸入 'agy-status' 查看狀態）" ;;
                zh-CN) _fmt="  如需重新开启并恢复自动启动，请输入 'agy-start'（或输入 'agy-status' 查看状态）" ;;
                ja)    _fmt="  再開して自動起動を有効にするには 'agy-start' を実行してください（状態確認: 'agy-status'）" ;;
                *)     _fmt="  Run 'agy-start' to open and re-enable auto-start (or 'agy-status' to check status)" ;;
            esac
            ;;
        bashrc_status_disabled)
            case "$_lang" in
                zh-TW) _fmt="Antigravity remote-control 目前已設定為關閉（不會於開機或啟動 Termux 時自動打開；輸入 'agy-start' 可重新開啟）" ;;
                zh-CN) _fmt="Antigravity remote-control 当前已设置为关闭（不会在开机或打开 Termux 时自动打开；输入 'agy-start' 可重新开启）" ;;
                ja)    _fmt="Antigravity remote-control は現在無効です（起動時・Termux起動時に自動起動しません。'agy-start' で再開できます）" ;;
                *)     _fmt="Antigravity remote-control is disabled (will not auto-open at boot or in Termux; run 'agy-start' to re-enable)" ;;
            esac
            ;;
        bashrc_lang_current)
            case "$_lang" in
                zh-TW) _fmt='目前語言: %s (設定模式: %s)' ;;
                zh-CN) _fmt='当前语言: %s (设置模式: %s)' ;;
                ja)    _fmt='現在の言語: %s (設定モード: %s)' ;;
                *)     _fmt='Current language: %s (mode: %s)' ;;
            esac
            ;;
        bashrc_lang_usage)
            case "$_lang" in
                zh-TW) _fmt='用法: agy-lang [auto|zh-TW|zh-CN|en|ja]' ;;
                zh-CN) _fmt='用法: agy-lang [auto|zh-TW|zh-CN|en|ja]' ;;
                ja)    _fmt='使い方: agy-lang [auto|zh-TW|zh-CN|en|ja]' ;;
                *)     _fmt='Usage: agy-lang [auto|zh-TW|zh-CN|en|ja]' ;;
            esac
            ;;
        bashrc_lang_set_auto)
            case "$_lang" in
                zh-TW) _fmt='已切換為自動偵測 Android 系統語言 (目前偵測: %s)' ;;
                zh-CN) _fmt='已切换为自动检测 Android 系统语言 (当前检测: %s)' ;;
                ja)    _fmt='Android システム言語の自動検出に切り替えました (現在の検出結果: %s)' ;;
                *)     _fmt='Switched to automatic Android system language detection (detected: %s)' ;;
            esac
            ;;
        bashrc_lang_set)
            case "$_lang" in
                zh-TW) _fmt='已設定 Antigravity 模組語言為: %s' ;;
                zh-CN) _fmt='已设置 Antigravity 模块语言为: %s' ;;
                ja)    _fmt='Antigravity モジュール言語を設定しました: %s' ;;
                *)     _fmt='Antigravity module language set to: %s' ;;
            esac
            ;;
        bashrc_lang_invalid)
            case "$_lang" in
                zh-TW) _fmt='不支援的語言選項: %s（可選: auto, zh-TW, zh-CN, en, ja）' ;;
                zh-CN) _fmt='不支持的语言选项: %s（可选: auto, zh-TW, zh-CN, en, ja）' ;;
                ja)    _fmt='未対応の言語オプションです: %s（有効値: auto, zh-TW, zh-CN, en, ja）' ;;
                *)     _fmt='Unsupported language option: %s (valid: auto, zh-TW, zh-CN, en, ja)' ;;
            esac
            ;;

        *)
            if [ "$#" -gt 0 ]; then
                printf '%s: %s\n' "$_k" "$*"
            else
                printf '%s\n' "$_k"
            fi
            return 0
            ;;
    esac

    if [ "$#" -gt 0 ]; then
        # shellcheck disable=SC2059
        printf "${_fmt}\n" "$@"
    else
        printf '%s\n' "$_fmt"
    fi
}
