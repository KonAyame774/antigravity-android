#!/data/data/com.termux/files/usr/bin/bash
export HOME="/data/data/com.termux/files/home"
cd "$HOME" 2>/dev/null || cd / 2>/dev/null || true
export PREFIX="/data/data/com.termux/files/usr"
export SHELL="$PREFIX/bin/bash"
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) export PATH="$PREFIX/bin:$PATH" ;;
esac
export PATH="$PATH:/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk"
export TMUX_TMPDIR="$PREFIX/var/run"
export TMPDIR="$PREFIX/tmp"
export LANG="${LANG:-en_US.UTF-8}"
export PYTHONDONTWRITEBYTECODE=1
if [ -z "${TERMUX_VERSION:-}" ]; then
    TERMUX_VERSION=$(dumpsys package com.termux 2>/dev/null | sed -n 's/.*versionName=//p' | head -n 1 | tr -d '\r')
    export TERMUX_VERSION="${TERMUX_VERSION:-0.118.3}"
else
    export TERMUX_VERSION
fi
if [ "$(id -u)" -eq 0 ]; then
    export USER="root"
else
    export USER="$(id -un 2>/dev/null || echo u0_a466)"
fi
if [ -f "$PREFIX/lib/libtermux-exec-ld-preload.so" ]; then
    export LD_PRELOAD="$PREFIX/lib/libtermux-exec-ld-preload.so"
fi

LOGFILE="$HOME/.gemini/antigravity-cli/boot.log"
LOCKFILE="$TMUX_TMPDIR/agy_root.lock"
STARTLOCK="$TMUX_TMPDIR/agy_start.lock"

if [ -f "$HOME/.local/bin/agy_i18n.sh" ]; then
    . "$HOME/.local/bin/agy_i18n.sh"
    agy_i18n_init "$HOME"
else
    agy_msg() { local _k="$1"; shift; printf '%s%s\n' "$_k" "${*:+: $*}"; }
fi
RUNNER_STATE="$TMUX_TMPDIR/agy_runner.state"
RUNNER_PGREP_RE='[a]gy_boot_service\.sh --runner'
TMUX_PGREP_RE='[t]mux new-session -d -s agy'
AGY_PGREP_RE='[a]gy(\.va39|-va39)? --remote-control'
CLEANUP_PGREP_RE='[c]leanup_offline_instances\.py'
CLEANUP_EMPTY_PGREP_RE='[c]leanup_empty_conversations\.py'
PERM_PGREP_RE='[s]ync_gemini_perms\.py'
LS_CSRF_FILE="$HOME/.gemini/antigravity-cli/.ls_csrf_token"

_token_sig() {
    "$PREFIX/bin/python3" -B -c '
import hashlib, json, os, sys
p = os.path.join(sys.argv[1], ".gemini/antigravity-cli/antigravity-oauth-token")
try:
    with open(p, "r", encoding="utf-8") as f:
        d = json.load(f)
    if not isinstance(d, dict):
        sys.exit(1)
    t = d.get("token") if isinstance(d.get("token"), dict) else {}
    acc = t.get("access_token") or d.get("access_token") or ""
    ref = t.get("refresh_token") or d.get("refresh_token") or ""
    if not (isinstance(acc, str) and acc.strip()) and not (isinstance(ref, str) and ref.strip()):
        sys.exit(1)
    print(hashlib.sha256((acc + "\n" + ref).encode("utf-8")).hexdigest())
except Exception:
    sys.exit(1)
' "$HOME" 2>/dev/null
}

_pkill_cmd() {
    if [ -x "$PREFIX/bin/pkill" ]; then
        "$PREFIX/bin/pkill" "$@"
    else
        pkill "$@"
    fi
}

_pgrep_cmd() {
    if [ -x "$PREFIX/bin/pgrep" ]; then
        "$PREFIX/bin/pgrep" "$@"
    else
        pgrep "$@"
    fi
}

_stop_procs_present() {
    if TMUX_TMPDIR="$TMUX_TMPDIR" "$PREFIX/bin/tmux" has-session -t agy 2>/dev/null; then
        return 0
    fi
    _pgrep_cmd -f "$RUNNER_PGREP_RE" >/dev/null 2>&1 && return 0
    _pgrep_cmd -f "$TMUX_PGREP_RE" >/dev/null 2>&1 && return 0
    _pgrep_cmd -f "$AGY_PGREP_RE" >/dev/null 2>&1 && return 0
    _pgrep_cmd -f "$CLEANUP_EMPTY_PGREP_RE" >/dev/null 2>&1 && return 0
    _pgrep_cmd -f "$PERM_PGREP_RE" >/dev/null 2>&1 && return 0
    if [ "$(id -u)" -eq 0 ]; then
        if [ -f "$LOCKFILE" ] && ! flock -n -s "$LOCKFILE" true 2>/dev/null; then
            return 0
        fi
        if [ -f "$STARTLOCK" ] && ! flock -n -s "$STARTLOCK" true 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

_stop_service() {
    mkdir -p "$(dirname "$LOGFILE")" "$TMUX_TMPDIR" "$TMPDIR" 2>/dev/null || true
    TMUX_TMPDIR="$TMUX_TMPDIR" "$PREFIX/bin/tmux" kill-session -t agy 2>/dev/null || true
    _pkill_cmd -TERM -f "$RUNNER_PGREP_RE" 2>/dev/null || true
    _pkill_cmd -TERM -f "$TMUX_PGREP_RE" 2>/dev/null || true
    _pkill_cmd -TERM -f "$AGY_PGREP_RE" 2>/dev/null || true
    _pkill_cmd -TERM -f "$CLEANUP_PGREP_RE" 2>/dev/null || true
    _pkill_cmd -TERM -f "$CLEANUP_EMPTY_PGREP_RE" 2>/dev/null || true
    _pkill_cmd -TERM -f "$PERM_PGREP_RE" 2>/dev/null || true

    local _i=0
    while [ "$_i" -lt 10 ]; do
        _stop_procs_present || break
        sleep 0.5 2>/dev/null || sleep 1
        _i=$((_i + 1))
    done

    if _stop_procs_present; then
        TMUX_TMPDIR="$TMUX_TMPDIR" "$PREFIX/bin/tmux" kill-session -t agy 2>/dev/null || true
        _pkill_cmd -KILL -f "$RUNNER_PGREP_RE" 2>/dev/null || true
        _pkill_cmd -KILL -f "$TMUX_PGREP_RE" 2>/dev/null || true
        _pkill_cmd -KILL -f "$AGY_PGREP_RE" 2>/dev/null || true
        _pkill_cmd -KILL -f "$CLEANUP_PGREP_RE" 2>/dev/null || true
        _pkill_cmd -KILL -f "$CLEANUP_EMPTY_PGREP_RE" 2>/dev/null || true
        _pkill_cmd -KILL -f "$PERM_PGREP_RE" 2>/dev/null || true
        _i=0
        while [ "$_i" -lt 6 ]; do
            _stop_procs_present || break
            sleep 0.5 2>/dev/null || sleep 1
            _i=$((_i + 1))
        done
    fi

    rm -f "$LS_CSRF_FILE" "${LS_CSRF_FILE}.tmp" 2>/dev/null || true
    if [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/sync_gemini_perms.py" ] && [ -x "$PREFIX/bin/python3" ]; then
        "$PREFIX/bin/python3" -B "$HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 || true
    fi
    _stop_procs_present && return 1 || return 0
}

_runner_main() {
    cd "$HOME" 2>/dev/null || cd / 2>/dev/null || true
    mkdir -p "$(dirname "$LOGFILE")" "$TMUX_TMPDIR" "$TMPDIR"
    if [ "$(id -u)" -eq 0 ]; then
        # Hold exclusive flock in the tmux controller process only; close FD 9 before spawning children
        exec 9<"$LOCKFILE"
        flock -x -n 9 || true
    fi

    PERM_PID=""
    if [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/sync_gemini_perms.py" ]; then
        "$PREFIX/bin/python3" -B "$HOME/.local/bin/sync_gemini_perms.py" --watch >> "$LOGFILE" 2>&1 9>&- &
        PERM_PID=$!
    fi

    # Background monitor:
    # 1) Inspect THIS runner's actual child PID + per-PID log and token signature (never shared cli.log symlink)
    # 2) Auto-reload agy --remote-control if OAuth token signature changes externally or launched unauth with valid token
    # 3) Periodically prune stale offline instances (15s after startup, then every 30m)
    (
        _child=""
        _cleanup_on_sig() {
            [ -n "$_child" ] && kill "$_child" 2>/dev/null || true
            exit 0
        }
        trap _cleanup_on_sig INT TERM HUP

        _inspect_runner_child() {
            "$PREFIX/bin/python3" -B -c '
import glob, hashlib, json, os, re, sys

state_path, home = sys.argv[1], sys.argv[2]

def read_token_sig():
    p = os.path.join(home, ".gemini", "antigravity-cli", "antigravity-oauth-token")
    try:
        with open(p, "r", encoding="utf-8") as f:
            d = json.load(f)
        if not isinstance(d, dict):
            return "-"
        t = d.get("token") if isinstance(d.get("token"), dict) else {}
        acc = t.get("access_token") or d.get("access_token") or ""
        ref = t.get("refresh_token") or d.get("refresh_token") or ""
        if not (isinstance(acc, str) and acc.strip()) and not (isinstance(ref, str) and ref.strip()):
            return "-"
        return hashlib.sha256((acc + "\n" + ref).encode("utf-8")).hexdigest()
    except Exception:
        return "-"

cur_sig = read_token_sig()
try:
    with open(state_path, "r", encoding="utf-8") as f:
        parts = f.read().strip().split("\t")
    launch_ts = int(parts[0])
    launch_sig = parts[1] if parts[1] else "-"
    runner_pid = int(parts[2])
except Exception:
    print(f"0 {cur_sig} - 0 none")
    sys.exit(0)

children = {}
cmds = {}
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    pid = int(name)
    try:
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8", errors="ignore") as f:
            st = f.read()
        rp = st.rfind(")")
        if rp < 0:
            continue
        ppid = int(st[rp + 2:].split()[1])
        children.setdefault(ppid, []).append(pid)
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmds[pid] = f.read().replace(b"\x00", b" ").decode("utf-8", "ignore").strip()
    except Exception:
        continue

pat = re.compile(r"(?:^|[/\s])agy(?:\.va39|-va39)?\s+--remote-control(?:\s|$)")
matched = []
queue = [runner_pid]
seen = {runner_pid}
while queue:
    cur = queue.pop(0)
    for ch in children.get(cur, ()):
        if ch in seen:
            continue
        seen.add(ch)
        queue.append(ch)
        if pat.search(cmds.get(ch, "")):
            matched.append(ch)

if not matched:
    print(f"0 {cur_sig} {launch_sig} {launch_ts} none")
    sys.exit(0)

matched_set = set(matched)
leaf_pid = matched[-1]
for cand in reversed(matched):
    has_matched_desc = False
    q = [cand]
    s = {cand}
    while q:
        cur = q.pop(0)
        for ch in children.get(cur, ()):
            if ch in s:
                continue
            s.add(ch)
            q.append(ch)
            if ch in matched_set:
                has_matched_desc = True
                break
        if has_matched_desc:
            break
    if not has_matched_desc:
        leaf_pid = cand
        break

log_dir = os.path.join(home, ".gemini", "antigravity-cli", "log")
ordered_pids = [leaf_pid] + [p for p in reversed(matched) if p != leaf_pid]
log_text = ""

for pid in ordered_pids:
    fd_dir = f"/proc/{pid}/fd"
    try:
        fds = os.listdir(fd_dir)
    except Exception:
        continue
    for fd in fds:
        try:
            target = os.readlink(f"{fd_dir}/{fd}")
        except Exception:
            continue
        if target.startswith(log_dir + "/cli-") and ".log" in target:
            read_path = target if os.path.isfile(target) else f"{fd_dir}/{fd}"
            try:
                with open(read_path, "r", encoding="utf-8", errors="ignore") as lf:
                    log_text = lf.read()
                if log_text:
                    break
            except Exception:
                pass
    if log_text:
        break

if not log_text and os.path.isdir(log_dir):
    candidates = []
    for lp in glob.glob(os.path.join(log_dir, "cli-*.log")):
        try:
            mt = os.stat(lp).st_mtime
        except Exception:
            continue
        if mt >= launch_ts - 5:
            candidates.append((mt, lp))
    candidates.sort(reverse=True)
    for _, lp in candidates:
        try:
            with open(lp, "r", encoding="utf-8", errors="ignore") as lf:
                txt = lf.read()
        except Exception:
            continue
        if any(f"with pid {p}" in txt for p in ordered_pids):
            log_text = txt
            break

log_state = "unknown"
has_startup_conv = 0
if log_text:
    if ("OAuth: authenticated successfully" in log_text) or ("Connection status:" in log_text):
        log_state = "auth"
    elif (
        ("Select login method" in log_text)
        or ("You are not logged into Antigravity." in log_text)
        or ("[RemoteControl] RemoteControlEnabled value: false" in log_text)
    ):
        log_state = "unauth"
    if ("Created conversation " in log_text) and ("listening on random port at " in log_text):
        has_startup_conv = 1

print(f"{leaf_pid} {cur_sig} {launch_sig} {launch_ts} {log_state} {has_startup_conv}")
' "$RUNNER_STATE" "$HOME" 2>/dev/null
        }

        _cleanup_elapsed=0
        _cleaned_once=0
        _empty_startup_done_ts=""
        _last_reload_ts=0
        _last_unauth_sig=""
        while true; do
            _step=10
            if [ -s "$RUNNER_STATE" ]; then
                _info=$(_inspect_runner_child)
                set -- ${_info:-0 - - 0 none 0}
                _child_pid="${1:-0}"
                _cur_sig="${2:--}"
                _launch_sig="${3:--}"
                _launch_ts="${4:-0}"
                _log_state="${5:-none}"
                _has_startup_conv="${6:-0}"

                if [ "$_child_pid" -gt 0 ] 2>/dev/null; then
                    _now_ts=$(date +%s 2>/dev/null || echo 0)
                    _need_reload=0
                    if [ "$_cur_sig" != "-" ]; then
                        if [ "$_launch_sig" = "-" ] || [ "$_cur_sig" != "$_launch_sig" ]; then
                            if [ $((_now_ts - _last_reload_ts)) -ge 20 ]; then
                                _need_reload=1
                            fi
                        elif [ "$_log_state" = "unauth" ] && [ $((_now_ts - _launch_ts)) -ge 15 ] && [ "$_cur_sig" != "$_last_unauth_sig" ]; then
                            if [ $((_now_ts - _last_reload_ts)) -ge 20 ]; then
                                _need_reload=1
                                _last_unauth_sig="$_cur_sig"
                            fi
                        fi
                    fi

                    if [ "$_need_reload" -eq 1 ]; then
                        if [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/sync_gemini_perms.py" ]; then
                            "$PREFIX/bin/python3" -B "$HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 || true
                        fi
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg boot_auto_reload "$_child_pid" "$_log_state")" >> "$LOGFILE"
                        _last_reload_ts="$_now_ts"
                        kill -TERM "$_child_pid" 2>/dev/null || true
                        _w=0
                        while [ "$_w" -lt 6 ] && kill -0 "$_child_pid" 2>/dev/null; do
                            sleep 0.5 &
                            _child=$!
                            wait "$_child" 2>/dev/null || exit 0
                            _w=$((_w + 1))
                        done
                        if kill -0 "$_child_pid" 2>/dev/null; then
                            kill -KILL "$_child_pid" 2>/dev/null || true
                        fi
                        _step=6
                    else
                        if [ "$_cur_sig" != "-" ] && [ "$_cur_sig" = "$_launch_sig" ] && [ "$_log_state" != "unauth" ]; then
                            if [ "$_log_state" = "auth" ] && [ "$_launch_ts" -gt 0 ] 2>/dev/null && [ "$_empty_startup_done_ts" != "$_launch_ts" ]; then
                                _up_secs=$((_now_ts - _launch_ts))
                                if { [ "$_has_startup_conv" -eq 1 ] && [ "$_up_secs" -ge 4 ]; } || [ "$_up_secs" -ge 20 ]; then
                                    if [ -f "$HOME/.local/bin/cleanup_empty_conversations.py" ]; then
                                        if "$PREFIX/bin/python3" -B "$HOME/.local/bin/cleanup_empty_conversations.py" --pid "$_child_pid" --min-age 60 --include-startup --token-file "$LS_CSRF_FILE" >> "$LOGFILE" 2>&1; then
                                            _empty_startup_done_ts="$_launch_ts"
                                        elif [ "$_up_secs" -ge 35 ]; then
                                            _empty_startup_done_ts="$_launch_ts"
                                        fi
                                    else
                                        _empty_startup_done_ts="$_launch_ts"
                                    fi
                                fi
                            fi
                            if [ "$_cleaned_once" -eq 0 ] && [ "$_cleanup_elapsed" -ge 15 ]; then
                                "$PREFIX/bin/python3" -B "$HOME/.local/bin/cleanup_offline_instances.py" >> "$LOGFILE" 2>&1
                                _cleaned_once=1
                                _cleanup_elapsed=0
                            elif [ "$_cleaned_once" -eq 1 ] && [ "$_cleanup_elapsed" -ge 1800 ]; then
                                "$PREFIX/bin/python3" -B "$HOME/.local/bin/cleanup_offline_instances.py" >> "$LOGFILE" 2>&1
                                if [ -f "$HOME/.local/bin/cleanup_empty_conversations.py" ]; then
                                    "$PREFIX/bin/python3" -B "$HOME/.local/bin/cleanup_empty_conversations.py" --pid "$_child_pid" --min-age 600 --token-file "$LS_CSRF_FILE" >> "$LOGFILE" 2>&1 || true
                                fi
                                _cleanup_elapsed=0
                            fi
                        fi

                        if [ "$_log_state" != "auth" ]; then
                            _step=3
                        elif [ "$_empty_startup_done_ts" != "$_launch_ts" ] && [ "$_launch_ts" -gt 0 ] 2>/dev/null; then
                            _step=3
                        elif [ "$_cleaned_once" -eq 0 ]; then
                            _step=$((15 - _cleanup_elapsed))
                            [ "$_step" -lt 2 ] && _step=2
                        else
                            _step=30
                        fi
                    fi
                else
                    _step=5
                fi
            else
                _cleanup_elapsed=0
            fi

            sleep "$_step" &
            _child=$!
            wait "$_child" 2>/dev/null || exit 0
            _child=""
            if [ -s "$RUNNER_STATE" ]; then
                _cleanup_elapsed=$((_cleanup_elapsed + _step))
            fi
        done
    ) 9>&- &
    CLEANUP_PID=$!

    _STOP_REQUESTED=0
    _WAIT_PID=""
    _ON_EXIT_RAN=0
    _on_exit() {
        [ "$_ON_EXIT_RAN" -eq 1 ] && return 0
        _ON_EXIT_RAN=1
        [ -n "${_WAIT_PID:-}" ] && kill "$_WAIT_PID" 2>/dev/null || true
        [ -n "${CLEANUP_PID:-}" ] && kill "$CLEANUP_PID" 2>/dev/null || true
        [ -n "${PERM_PID:-}" ] && kill "$PERM_PID" 2>/dev/null || true
        _pkill_cmd -TERM -P $$ 2>/dev/null || true
        rm -f "$RUNNER_STATE" "${RUNNER_STATE}.tmp" "$LS_CSRF_FILE" "${LS_CSRF_FILE}.tmp" 2>/dev/null || true
        if [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/sync_gemini_perms.py" ]; then
            "$PREFIX/bin/python3" -B "$HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 || true
        fi
    }
    trap _on_exit EXIT
    trap "_STOP_REQUESTED=1; _on_exit; exit 0" INT TERM HUP

    while true; do
        _agy_bin=$(command -v agy 2>/dev/null || echo "$PREFIX/bin/agy")
        _agy_real=$(readlink -f "$_agy_bin" 2>/dev/null || echo "$_agy_bin")
        _agy_dir=$(dirname "$_agy_real")
        _is_wallentx=0
        if [ -x "$_agy_dir/agy.va39" ] && [ "$(wc -c < "$_agy_real" 2>/dev/null || echo 0)" -lt 2097152 ]; then
            _is_wallentx=1
            # 若為 wallentx 雙二進位，先非互動完成檢查更新再打固定名稱補丁，避免卡在 tmux 更新提示或跑出隨機名稱
            if command -v timeout >/dev/null 2>&1; then
                AGY_AUTO_UPDATE=1 timeout 90 "$_agy_bin" update -y </dev/null >> "$LOGFILE" 2>&1 9>&- || true
            else
                AGY_AUTO_UPDATE=1 "$_agy_bin" update -y </dev/null >> "$LOGFILE" 2>&1 9>&- || true
            fi
        fi

        # Ensure agy / agy.va39 respects cliRemoteControlHostname even after automatic CLI updates
        if [ -f "$HOME/.local/bin/patch_agy_hostname.py" ]; then
            "$PREFIX/bin/python3" -B "$HOME/.local/bin/patch_agy_hostname.py" >> "$LOGFILE" 2>&1 9>&- || true
        fi

        [ "${_STOP_REQUESTED:-0}" -eq 1 ] && break

        if ! _token_sig >/dev/null; then
            rm -f "$RUNNER_STATE" "${RUNNER_STATE}.tmp" "$LS_CSRF_FILE" "${LS_CSRF_FILE}.tmp" 2>/dev/null || true
            echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg boot_wait_token)"
            while [ "${_STOP_REQUESTED:-0}" -eq 0 ] && ! _token_sig >/dev/null; do
                sleep 2 &
                _WAIT_PID=$!
                wait "$_WAIT_PID" 2>/dev/null || true
                _WAIT_PID=""
            done
            [ "${_STOP_REQUESTED:-0}" -eq 1 ] && break
            echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg boot_token_detected)"
            sleep 1 &
            _WAIT_PID=$!
            wait "$_WAIT_PID" 2>/dev/null || true
            _WAIT_PID=""
            [ "${_STOP_REQUESTED:-0}" -eq 1 ] && break
        fi

        rm -f "$LS_CSRF_FILE" "${LS_CSRF_FILE}.tmp" 2>/dev/null || true
        if [ -f "$HOME/.local/bin/cleanup_empty_conversations.py" ]; then
            "$PREFIX/bin/python3" -B "$HOME/.local/bin/cleanup_empty_conversations.py" --offline-only --min-age 0 >> "$LOGFILE" 2>&1 9>&- || true
        fi

        _ls_csrf=$(
            "$PREFIX/bin/python3" -B -c 'import os, secrets, sys
p = sys.argv[1]
t = secrets.token_hex(16)
os.makedirs(os.path.dirname(p), exist_ok=True)
tmp = p + ".tmp"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    f.write(t)
os.chmod(tmp, 0o600)
os.replace(tmp, p)
print(t)' "$LS_CSRF_FILE" 2>/dev/null || true
        )

        if [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/sync_gemini_perms.py" ]; then
            "$PREFIX/bin/python3" -B "$HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 9>&- || true
        fi

        _launch_sig=$(_token_sig || true)
        _launch_ts=$(date +%s 2>/dev/null || echo 0)
        printf '%s\t%s\t%s\n' "$_launch_ts" "${_launch_sig:--}" "${BASHPID:-$$}" > "${RUNNER_STATE}.tmp" 2>/dev/null && \
            mv -f "${RUNNER_STATE}.tmp" "$RUNNER_STATE" 2>/dev/null || true

        echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg boot_launching "$(id -u)" "$_is_wallentx")"
        if [ "$_is_wallentx" -eq 1 ]; then
            AGY_AUTO_UPDATE=1 ANTIGRAVITY_SERVER_CSRF_TOKEN="$_ls_csrf" agy --remote-control 9>&-
        else
            ANTIGRAVITY_SERVER_CSRF_TOKEN="$_ls_csrf" agy --remote-control 9>&-
        fi
        EXIT_CODE=$?
        rm -f "$RUNNER_STATE" "${RUNNER_STATE}.tmp" "$LS_CSRF_FILE" "${LS_CSRF_FILE}.tmp" 2>/dev/null || true
        if [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/sync_gemini_perms.py" ]; then
            "$PREFIX/bin/python3" -B "$HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 9>&- || true
        fi
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] $(agy_msg boot_exited "$EXIT_CODE")"
        [ "${_STOP_REQUESTED:-0}" -eq 1 ] && break
        sleep 5 &
        _WAIT_PID=$!
        wait "$_WAIT_PID" 2>/dev/null || true
        _WAIT_PID=""
    done
}

_AGY_FORCE_FLAG=0
case "${1:-}" in
    --stop)
        _stop_service
        exit $?
        ;;
    --runner)
        _runner_main
        exit $?
        ;;
    --force)
        _AGY_FORCE_FLAG=1
        ;;
esac

mkdir -p "$(dirname "$LOGFILE")" "$TMUX_TMPDIR" "$TMPDIR"

ensure_shared_file() {
    local target="$1"
    local mode="$2"
    [ -f "$target" ] || : > "$target"
    if [ "$(id -u)" -eq 0 ]; then
        local uid gid ctx
        uid=$(/system/bin/stat -c "%u" "$HOME" 2>/dev/null || echo 10466)
        gid=$(/system/bin/stat -c "%g" "$HOME" 2>/dev/null || echo 10466)
        chown "$uid:$gid" "$target" 2>/dev/null || true
        ctx=$(/system/bin/stat -c "%C" "$HOME" 2>/dev/null || true)
        [ -n "$ctx" ] && [ -x /system/bin/chcon ] && /system/bin/chcon "$ctx" "$target" 2>/dev/null || true
    fi
    chmod "$mode" "$target" 2>/dev/null || true
}

ensure_shared_file "$LOGFILE" 0644
ensure_shared_file "$LOCKFILE" 0644
ensure_shared_file "$STARTLOCK" 0644

RC_FLAG_FILE="$HOME/.gemini/config/remote_control"
_rc_flag=""
if [ -r "$RC_FLAG_FILE" ]; then
    _rc_flag=$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "$RC_FLAG_FILE" 2>/dev/null)
fi
if [ "${AGY_FORCE_START:-0}" != "1" ] && [ "$_AGY_FORCE_FLAG" -ne 1 ] && [ "$_rc_flag" = "0" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(agy_msg boot_rc_disabled)" >> "$LOGFILE"
    exit 0
fi

# Prevent concurrent startup race between service.sh and .bashrc
exec 8<"$STARTLOCK"
if ! flock -x -n 8; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(agy_msg boot_startup_in_progress)" >> "$LOGFILE"
    exit 0
fi

# Quick duplicate check before waiting for network
if tmux has-session -t agy 2>/dev/null || _pgrep_cmd -f "$RUNNER_PGREP_RE" >/dev/null 2>&1 || _pgrep_cmd -f "$AGY_PGREP_RE" >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(agy_msg boot_already_running "$(id -u)")" >> "$LOGFILE"
    exec 8<&-
    exit 0
fi
if [ "$(id -u)" -ne 0 ] && [ -f "$LOCKFILE" ] && ! flock -n -s "$LOCKFILE" true 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(agy_msg boot_root_lock_active)" >> "$LOGFILE"
    exec 8<&-
    exit 0
fi

# Acquire Termux wake lock to prevent CPU deep sleep (bounded timeout to avoid am hang)
if command -v termux-wake-lock >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
        timeout 4 termux-wake-lock </dev/null >/dev/null 2>&1 || true
    else
        termux-wake-lock </dev/null >/dev/null 2>&1 || true
    fi
fi

# Wait for internet connectivity up to 30s (6s when launched immediately from flash)
_net_tries=15
[ "${AGY_FROM_FLASH:-0}" = "1" ] && _net_tries=3
for i in $(seq 1 "$_net_tries"); do
    if curl -s -I --connect-timeout 2 --max-time 4 https://www.google.com >/dev/null 2>&1 || \
       curl -s -I --connect-timeout 2 --max-time 4 https://antigravity.google.com >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(agy_msg boot_net_verified "$(id -u)")" >> "$LOGFILE"
        break
    fi
    sleep 2
done

# If tmux session "agy" already exists, do not duplicate
if tmux has-session -t agy 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(agy_msg boot_tmux_running)" >> "$LOGFILE"
    exec 8<&-
    exit 0
fi

# If another agy --remote-control or runner process is already running, do not duplicate
if _pgrep_cmd -f "$RUNNER_PGREP_RE" >/dev/null 2>&1 || _pgrep_cmd -f "$AGY_PGREP_RE" >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(agy_msg boot_running_outside)" >> "$LOGFILE"
    exec 8<&-
    exit 0
fi

# Auto-provision environment if needed before startup
if [ "${AGY_SKIP_ENV_CHECK:-0}" != "1" ] && [ -f "$HOME/.local/bin/ensure_antigravity_env.sh" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        /system/bin/sh "$HOME/.local/bin/ensure_antigravity_env.sh" --quiet-ok >> "$LOGFILE" 2>&1 8>&- || true
    else
        /system/bin/sh "$HOME/.local/bin/ensure_antigravity_env.sh" --net-only --quiet-ok >> "$LOGFILE" 2>&1 8>&- || true
    fi
fi

# Ensure ~/.gemini & ~/.config/antigravity permissions and SELinux MCS labels
if [ "$(id -u)" -eq 0 ] && [ -f "$HOME/.local/bin/sync_gemini_perms.py" ] && [ -x "$PREFIX/bin/python3" ]; then
    "$PREFIX/bin/python3" -B "$HOME/.local/bin/sync_gemini_perms.py" --once >/dev/null 2>&1 8>&- || true
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(agy_msg boot_tmux_starting "$(id -u)" "$USER")" >> "$LOGFILE"

tmux new-session -d -s agy "$PREFIX/bin/bash" "$HOME/.local/bin/agy_boot_service.sh" --runner </dev/null >/dev/null 2>&1 8>&-

# Wait briefly for tmux runner to acquire root lock so immediate agy-status reflects active state
for _w in 1 2 3 4; do
    if [ "$(id -u)" -eq 0 ]; then
        if [ -f "$LOCKFILE" ] && ! flock -n -s "$LOCKFILE" true 2>/dev/null; then
            break
        fi
    elif tmux has-session -t agy 2>/dev/null; then
        break
    fi
    sleep 0.5 2>/dev/null || sleep 1
done

exec 8<&-
