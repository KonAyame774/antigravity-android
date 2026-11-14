#!/usr/bin/env python3
"""Safely remove genuinely empty 'Untitled Conversation' entries created
automatically by Antigravity CLI restarts or abandoned new tabs.

Supports:
  1. Online mode (preferred): calls LanguageServerService/DeleteCascadeTrajectory
     over localhost HTTP using the per-session ANTIGRAVITY_SERVER_CSRF_TOKEN,
     updating in-memory state, WebChannel UI, SQLite, and jetbox proto cleanly.
  2. Offline fallback: ONLY when no agy process is running, safely deletes
     verified-empty entries from conversation_summaries.db, conversations/*.db,
     annotations/*.pbtxt, empty brain/<cid>/ dirs, unlocked presence/*.lock,
     and jetbox_summaries_proto.pb.
"""
import sys

sys.dont_write_bytecode = True
import argparse
import datetime
import fcntl
import glob
import json
import os
import re
import shutil
import sqlite3
import tempfile
import time
import urllib.error
import urllib.request

DEFAULT_TERMUX_HOME = "/data/data/com.termux/files/home"
BASE_HOME = os.environ.get("HOME")
if not BASE_HOME or not os.path.isdir(os.path.join(BASE_HOME, ".gemini")):
    if os.path.isdir(os.path.join(DEFAULT_TERMUX_HOME, ".gemini")):
        BASE_HOME = DEFAULT_TERMUX_HOME
    else:
        BASE_HOME = os.path.expanduser("~")

_SELF_DIR = os.path.dirname(os.path.abspath(__file__))
if _SELF_DIR not in sys.path:
    sys.path.insert(0, _SELF_DIR)
try:
    from agy_py_i18n import get_locale, pick as _pick
except ImportError:
    def get_locale(home=None):
        return os.environ.get("AGY_LOCALE", "en") or "en"

    def _pick(table, key, locale=None, **kwargs):
        tmpl = table.get(key, {}).get("en", key)
        return tmpl.format(**kwargs) if kwargs else tmpl


LOCALE = get_locale(BASE_HOME)

I18N_MSG = {
    "found_empty": {
        "zh-TW": "[empty-cleanup] 發現 {count} 個空白對話 ({mode})，正在清理...",
        "zh-CN": "[empty-cleanup] 发现 {count} 个空白对话 ({mode})，正在清理...",
        "ja": "[empty-cleanup] 空の会話を {count} 件検出 ({mode})、整理中...",
        "en": "[empty-cleanup] Found {count} empty conversation(s) ({mode}), cleaning...",
    },
    "deleted_one": {
        "zh-TW": "[empty-cleanup] 已刪除空白對話: {cid}",
        "zh-CN": "[empty-cleanup] 已删除空白对话: {cid}",
        "ja": "[empty-cleanup] 空の会話を削除しました: {cid}",
        "en": "[empty-cleanup] Deleted empty conversation: {cid}",
    },
    "dry_run_one": {
        "zh-TW": "[empty-cleanup] [預覽] 將刪除空白對話: {cid}",
        "zh-CN": "[empty-cleanup] [预览] 将删除空白对话: {cid}",
        "ja": "[empty-cleanup] [ドライラン] 削除対象の空の会話: {cid}",
        "en": "[empty-cleanup] [dry-run] Would delete empty conversation: {cid}",
    },
    "finished": {
        "zh-TW": "[empty-cleanup] 完成，共清理 {count} 個空白對話。",
        "zh-CN": "[empty-cleanup] 完成，共清理 {count} 个空白对话。",
        "ja": "[empty-cleanup] 完了。空の会話を {count} 件整理しました。",
        "en": "[empty-cleanup] Finished. Cleaned {count} empty conversation(s).",
    },
    "none_found": {
        "zh-TW": "[empty-cleanup] 沒有發現需要清理的空白對話。",
        "zh-CN": "[empty-cleanup] 没有发现需要清理的空白对话。",
        "ja": "[empty-cleanup] 整理対象の空の会話はありません。",
        "en": "[empty-cleanup] No empty conversations to clean.",
    },
    "skip_online_offline_only": {
        "zh-TW": "[empty-cleanup] 偵測到 agy 正在執行中，略過離線資料庫清理。",
        "zh-CN": "[empty-cleanup] 检测到 agy 正在运行中，跳过离线数据库清理。",
        "ja": "[empty-cleanup] agy が実行中のため、オフラインクリーンアップをスキップします。",
        "en": "[empty-cleanup] agy process active; skipping offline cleanup.",
    },
    "err_rpc": {
        "zh-TW": "[empty-cleanup] RPC 刪除 {cid} 失敗: {err}",
        "zh-CN": "[empty-cleanup] RPC 删除 {cid} 失败: {err}",
        "ja": "[empty-cleanup] RPC での {cid} 削除に失敗しました: {err}",
        "en": "[empty-cleanup] RPC delete failed for {cid}: {err}",
    },
    "err_offline": {
        "zh-TW": "[empty-cleanup] 離線清理失敗: {err}",
        "zh-CN": "[empty-cleanup] 离线清理失败: {err}",
        "ja": "[empty-cleanup] オフラインクリーンアップに失敗しました: {err}",
        "en": "[empty-cleanup] Offline cleanup failed: {err}",
    },
}

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
ANN_TITLE_RE = re.compile(r"(?:^|\s)title\s*:")
HTTP_PORT_RE = re.compile(r"listening on random port at (\d+) for HTTP\b")
STARTUP_CONV_RE = re.compile(
    r"Starting new conversation \(agent=false\)[\s\S]{0,1500}?Created conversation ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b"
)
AGY_EXE_NAMES = frozenset({"agy", "agy.va39", "agy-va39"})


def _cli_dir(home: str = BASE_HOME) -> str:
    return os.path.join(home, ".gemini", "antigravity-cli")


def _default_token_file(cli_dir: str) -> str:
    return os.path.join(cli_dir, ".ls_csrf_token")


def _extract_agy_argv(cmd_bytes: bytes):
    parts = [p.decode("utf-8", "ignore") for p in cmd_bytes.split(b"\x00") if p]
    if not parts:
        return None
    base0 = os.path.basename(parts[0])
    if base0 in AGY_EXE_NAMES:
        return parts
    if base0.startswith("ld-linux"):
        for idx, arg in enumerate(parts[1:8], start=1):
            if os.path.basename(arg) in AGY_EXE_NAMES:
                return parts[idx:]
    return None


def _list_agy_pids(remote_control_only: bool = False):
    pids = []
    self_pid = os.getpid()
    try:
        names = os.listdir("/proc")
    except OSError:
        return pids
    for name in names:
        if not name.isdigit():
            continue
        pid = int(name)
        if pid == self_pid:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = _extract_agy_argv(f.read())
        except OSError:
            continue
        if not argv:
            continue
        if remote_control_only and "--remote-control" not in argv[1:]:
            continue
        pids.append(pid)
    pids.sort(reverse=True)
    return pids


def _find_pid_log_text(pid: int, log_dir: str) -> str:
    norm_log_dir = os.path.normpath(log_dir)
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith(norm_log_dir + "/cli-") and ".log" in target:
                read_path = target if os.path.isfile(target) else f"{fd_dir}/{fd}"
                try:
                    with open(read_path, "r", encoding="utf-8", errors="ignore") as lf:
                        return lf.read()
                except OSError:
                    pass
    except OSError:
        pass

    if os.path.isdir(log_dir):
        candidates = []
        for lp in glob.glob(os.path.join(log_dir, "cli-*.log")):
            try:
                candidates.append((os.stat(lp).st_mtime, lp))
            except OSError:
                continue
        candidates.sort(reverse=True)
        marker = f"with pid {pid}"
        for _, lp in candidates[:8]:
            try:
                with open(lp, "r", encoding="utf-8", errors="ignore") as lf:
                    txt = lf.read()
                if marker in txt:
                    return txt
            except OSError:
                continue
    return ""


def _resolve_live_endpoint(
    cli_dir: str, target_pid: int = 0, token_file: str = "", include_startup: bool = False
):
    csrf_tok = ""
    if token_file:
        try:
            with open(token_file, "r", encoding="utf-8") as f:
                csrf_tok = f.read().strip()
        except OSError:
            csrf_tok = ""
    if not csrf_tok:
        csrf_tok = (
            os.environ.get("ANTIGRAVITY_CSRF_TOKEN")
            or os.environ.get("ANTIGRAVITY_SERVER_CSRF_TOKEN")
            or ""
        ).strip()
    if not csrf_tok:
        try:
            with open(_default_token_file(cli_dir), "r", encoding="utf-8") as f:
                csrf_tok = f.read().strip()
        except OSError:
            csrf_tok = ""

    ls_addr = (os.environ.get("ANTIGRAVITY_LS_ADDRESS") or "").strip()
    log_dir = os.path.join(cli_dir, "log")
    startup_cids = set()

    if ls_addr and csrf_tok and target_pid <= 0:
        if include_startup:
            for pid in _list_agy_pids(remote_control_only=True):
                txt = _find_pid_log_text(pid, log_dir)
                if txt:
                    m_start = STARTUP_CONV_RE.search(txt)
                    if m_start:
                        startup_cids.add(m_start.group(1))
            if not startup_cids:
                cli_log = os.path.join(cli_dir, "cli.log")
                try:
                    with open(cli_log, "r", encoding="utf-8", errors="ignore") as f:
                        m_start = STARTUP_CONV_RE.search(f.read())
                        if m_start:
                            startup_cids.add(m_start.group(1))
                except OSError:
                    pass
        return ls_addr, csrf_tok, startup_cids

    pids = [target_pid] if target_pid > 0 else _list_agy_pids(remote_control_only=True)
    if not pids and target_pid <= 0:
        pids = _list_agy_pids(remote_control_only=False)

    for pid in pids:
        txt = _find_pid_log_text(pid, log_dir)
        if not txt:
            continue
        m = HTTP_PORT_RE.search(txt)
        if m and csrf_tok:
            if include_startup:
                m_start = STARTUP_CONV_RE.search(txt)
                if m_start:
                    startup_cids.add(m_start.group(1))
            return f"127.0.0.1:{m.group(1)}", csrf_tok, startup_cids

    # Fallback when hidepid hides root's /proc entries from non-root callers
    if target_pid <= 0 and csrf_tok and os.path.isdir(log_dir):
        candidates = []
        for lp in glob.glob(os.path.join(log_dir, "cli-*.log")):
            try:
                candidates.append((os.stat(lp).st_mtime, lp))
            except OSError:
                continue
        candidates.sort(reverse=True)
        seen_ports = set()
        for _, lp in candidates[:6]:
            try:
                with open(lp, "r", encoding="utf-8", errors="ignore") as lf:
                    txt = lf.read()
            except OSError:
                continue
            m = HTTP_PORT_RE.search(txt)
            if not m:
                continue
            port = m.group(1)
            if port in seen_ports:
                continue
            seen_ports.add(port)
            addr = f"127.0.0.1:{port}"
            try:
                _rpc_post(addr, csrf_tok, "Heartbeat", {}, timeout=1.2)
                if include_startup:
                    m_start = STARTUP_CONV_RE.search(txt)
                    if m_start:
                        startup_cids.add(m_start.group(1))
                return addr, csrf_tok, startup_cids
            except Exception:
                continue

    return None, csrf_tok, startup_cids


def _rpc_post(addr: str, csrf_tok: str, method: str, payload: dict, timeout: float = 5.0) -> dict:
    req = urllib.request.Request(
        f"http://{addr}/exa.language_server_pb.LanguageServerService/{method}",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-codeium-csrf-token": csrf_tok,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8", errors="replace").strip()
        return json.loads(raw) if raw else {}


def _is_unset_time(val) -> bool:
    if not val:
        return True
    s = str(val).strip()
    return not s or s.startswith("0001-01-01")


def _parse_iso_epoch(ts: str) -> float:
    if not ts:
        return 0.0
    try:
        s = ts.strip()
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        m = re.match(r"^(.+)\.(\d+)([+-]\d\d:\d\d)$", s)
        if m:
            s = f"{m.group(1)}.{m.group(2)[:6].ljust(6, '0')}{m.group(3)}"
        return datetime.datetime.fromisoformat(s).timestamp()
    except Exception:
        return 0.0


def _brain_has_files(brain_dir: str) -> bool:
    if not os.path.isdir(brain_dir):
        return False
    for _, _, files in os.walk(brain_dir):
        if files:
            return True
    return False


def _readonly_sqlite_uri(db_path: str) -> str:
    wal_path = db_path + "-wal"
    try:
        if os.path.isfile(wal_path) and os.path.getsize(wal_path) > 0:
            return f"file:{db_path}?mode=ro"
    except OSError:
        return f"file:{db_path}?mode=ro"
    return f"file:{db_path}?mode=ro&immutable=1"


def _is_conv_db_empty(conv_db_path: str) -> bool:
    if not os.path.isfile(conv_db_path):
        return False
    conn = None
    try:
        conn = sqlite3.connect(_readonly_sqlite_uri(conv_db_path), uri=True, timeout=1.0)
        tables = {
            r[0]
            for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        if "steps" not in tables:
            return False
        for tbl in ("steps", "gen_metadata", "executor_metadata", "battle_mode_infos"):
            if tbl in tables:
                cnt = conn.execute(f'SELECT COUNT(*) FROM "{tbl}"').fetchone()[0]
                if cnt != 0:
                    return False
        return True
    except sqlite3.Error:
        return False
    finally:
        if conn is not None:
            try:
                conn.close()
            except sqlite3.Error:
                pass


def _is_lock_held(lock_path: str) -> bool:
    if not os.path.exists(lock_path):
        return False
    fd = None
    try:
        fd = os.open(lock_path, os.O_RDONLY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(fd, fcntl.LOCK_UN)
            return False
        except OSError:
            return True
    except OSError:
        return True
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass


def _conv_newest_ts(cli_dir: str, cid: str, traj_meta: dict = None) -> float:
    ts = 0.0
    for path in (
        os.path.join(cli_dir, "conversations", f"{cid}.db"),
        os.path.join(cli_dir, "conversations", f"{cid}.db-wal"),
        os.path.join(cli_dir, "annotations", f"{cid}.pbtxt"),
        os.path.join(cli_dir, "brain", cid),
    ):
        try:
            st = os.stat(path)
            if path.endswith(".db-wal") and st.st_size == 0:
                continue
            ts = max(ts, st.st_mtime)
        except OSError:
            pass
    if isinstance(traj_meta, dict):
        ts = max(ts, _parse_iso_epoch(traj_meta.get("createdTime", "")))
    return ts


def find_empty_candidates(
    cli_dir: str,
    min_age: int = 0,
    live_trajs: dict = None,
    startup_cids: set = None,
    check_lock: bool = False,
):
    """Return sorted list of verified-empty conversation UUIDs eligible for removal."""
    summaries_db = os.path.join(cli_dir, "conversation_summaries.db")
    if not os.path.isfile(summaries_db):
        return []

    rows = []
    conn = None
    try:
        conn = sqlite3.connect(_readonly_sqlite_uri(summaries_db), uri=True, timeout=2.0)
        rows = conn.execute(
            """
            SELECT conversation_id, title, preview, step_count,
                   last_modified_time, last_user_input_time,
                   last_user_input_step_index, status,
                   parent_conversation_id, battle_id, not_fully_idle
            FROM conversation_summaries
            """
        ).fetchall()
    except sqlite3.Error:
        return []
    finally:
        if conn is not None:
            try:
                conn.close()
            except sqlite3.Error:
                pass

    now_ts = time.time()
    seen = set()
    candidates = []
    row_map = {r[0]: r for r in rows}

    # Evaluate DB rows plus any strictly live empty trajectory not yet synced into DB
    eval_ids = list(row_map.keys())
    if live_trajs:
        for cid in live_trajs:
            if cid not in row_map:
                eval_ids.append(cid)

    for cid in eval_ids:
        if cid in seen or not UUID_RE.match(cid):
            continue
        seen.add(cid)

        r = row_map.get(cid)
        if r is not None:
            (
                _,
                title,
                preview,
                step_count,
                lmt,
                luit,
                luisi,
                status,
                parent_cid,
                battle_id,
                not_idle,
            ) = r
            if title or preview:
                continue
            if step_count != 0 or (luisi is not None and luisi >= 0):
                continue
            if not _is_unset_time(lmt) or not _is_unset_time(luit):
                continue
            if parent_cid or battle_id or not_idle:
                continue
            if status not in ("", "CASCADE_RUN_STATUS_IDLE"):
                continue

        live_meta = live_trajs.get(cid) if live_trajs else None
        if live_meta is not None:
            if live_meta.get("stepCount") not in (None, 0):
                continue
            if live_meta.get("summary"):
                continue
            if live_meta.get("status", "CASCADE_RUN_STATUS_IDLE") not in (
                "",
                "CASCADE_RUN_STATUS_IDLE",
            ):
                continue

        conv_db = os.path.join(cli_dir, "conversations", f"{cid}.db")
        if not _is_conv_db_empty(conv_db):
            continue

        ann_path = os.path.join(cli_dir, "annotations", f"{cid}.pbtxt")
        if os.path.isfile(ann_path):
            try:
                with open(ann_path, "r", encoding="utf-8", errors="ignore") as af:
                    if ANN_TITLE_RE.search(af.read()):
                        continue
            except OSError:
                continue

        if _brain_has_files(os.path.join(cli_dir, "brain", cid)):
            continue

        if check_lock and _is_lock_held(os.path.join(cli_dir, "presence", f"{cid}.lock")):
            continue

        if min_age > 0 and (not startup_cids or cid not in startup_cids):
            newest_ts = _conv_newest_ts(cli_dir, cid, live_meta)
            if newest_ts > 0 and (now_ts - newest_ts) < min_age:
                continue

        candidates.append(cid)

    return sorted(candidates)


def _read_varint(buf: bytes, pos: int):
    val = 0
    shift = 0
    n = len(buf)
    while pos < n:
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            return val, pos
        shift += 7
        if shift > 63:
            raise ValueError("varint overflow")
    raise ValueError("truncated varint")


def _skip_field(buf: bytes, pos: int, wt: int) -> int:
    if wt == 0:
        _, pos = _read_varint(buf, pos)
        return pos
    if wt == 1:
        if pos + 8 > len(buf):
            raise ValueError("truncated fixed64")
        return pos + 8
    if wt == 2:
        ln, pos = _read_varint(buf, pos)
        if pos + ln > len(buf):
            raise ValueError("truncated length-delimited")
        return pos + ln
    if wt == 5:
        if pos + 4 > len(buf):
            raise ValueError("truncated fixed32")
        return pos + 4
    raise ValueError(f"unsupported wire type {wt}")


def _extract_map_entry_key(chunk: bytes):
    pos = 0
    n = len(chunk)
    while pos < n:
        tag, pos = _read_varint(chunk, pos)
        fn, wt = tag >> 3, tag & 7
        if fn == 1 and wt == 2:
            ln, p2 = _read_varint(chunk, pos)
            if p2 + ln > n:
                return None
            return chunk[p2 : p2 + ln].decode("utf-8", "ignore")
        pos = _skip_field(chunk, pos, wt)
    return None


def prune_jetbox_proto(proto_path: str, delete_ids: set) -> bool:
    """Prune deleted conversation IDs from jetbox_summaries_proto.pb atomically."""
    if not delete_ids or not os.path.isfile(proto_path):
        return False
    with open(proto_path, "rb") as f:
        data = f.read()
    if not data:
        return False

    pos = 0
    n = len(data)
    kept = []
    removed = 0
    while pos < n:
        entry_start = pos
        tag, pos = _read_varint(data, pos)
        fn, wt = tag >> 3, tag & 7
        if wt == 2:
            ln, p2 = _read_varint(data, pos)
            if p2 + ln > n:
                raise ValueError("truncated top-level entry")
            chunk = data[p2 : p2 + ln]
            pos = p2 + ln
            key = _extract_map_entry_key(chunk) if fn == 1 else None
            if key in delete_ids:
                removed += 1
                continue
            kept.append(data[entry_start:pos])
        else:
            pos = _skip_field(data, pos, wt)
            kept.append(data[entry_start:pos])

    if pos != n or removed == 0:
        return False

    new_data = b"".join(kept)
    st = os.stat(proto_path)
    fd, tmp_path = tempfile.mkstemp(
        prefix=".jetbox_prune_", dir=os.path.dirname(proto_path)
    )
    try:
        with os.fdopen(fd, "wb") as wf:
            wf.write(new_data)
        os.chmod(tmp_path, stat_mode(st.st_mode))
        try:
            os.chown(tmp_path, st.st_uid, st.st_gid)
        except OSError:
            pass
        os.replace(tmp_path, proto_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    return True


def stat_mode(st_mode: int) -> int:
    return st_mode & 0o777


def _remove_presence_lock(cli_dir: str, cid: str) -> None:
    lp = os.path.join(cli_dir, "presence", f"{cid}.lock")
    if os.path.exists(lp) and not _is_lock_held(lp):
        try:
            os.unlink(lp)
        except OSError:
            pass


def _cleanup_online(
    cli_dir: str,
    addr: str,
    csrf_tok: str,
    startup_cids: set,
    min_age: int,
    dry_run: bool,
    verbose: bool,
) -> int:
    trajs = _rpc_post(addr, csrf_tok, "GetAllCascadeTrajectories", {}).get(
        "trajectorySummaries", {}
    )
    candidates = find_empty_candidates(
        cli_dir, min_age=min_age, live_trajs=trajs, startup_cids=startup_cids
    )
    if not candidates:
        if verbose:
            print(_pick(I18N_MSG, "none_found", LOCALE))
        return 0

    print(_pick(I18N_MSG, "found_empty", LOCALE, count=len(candidates), mode="RPC"))
    deleted = 0
    for cid in candidates:
        if dry_run:
            print(_pick(I18N_MSG, "dry_run_one", LOCALE, cid=cid))
            deleted += 1
            continue
        try:
            _rpc_post(addr, csrf_tok, "DeleteCascadeTrajectory", {"cascadeId": cid})
            _remove_presence_lock(cli_dir, cid)
            print(_pick(I18N_MSG, "deleted_one", LOCALE, cid=cid))
            deleted += 1
        except Exception as e:
            print(_pick(I18N_MSG, "err_rpc", LOCALE, cid=cid, err=e), file=sys.stderr)

    if not dry_run and deleted > 0:
        time.sleep(0.35)
    print(_pick(I18N_MSG, "finished", LOCALE, count=deleted))
    return deleted


def _pid_env_home(pid: int) -> str:
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            for item in f.read().split(b"\x00"):
                if item.startswith(b"HOME="):
                    return item[5:].decode("utf-8", "ignore").strip()
    except OSError:
        return ""
    return ""


def _is_agy_active_for_cli_dir(cli_dir: str) -> bool:
    expected_home = os.path.realpath(os.path.dirname(os.path.dirname(os.path.realpath(cli_dir))))
    for pid in _list_agy_pids(remote_control_only=False):
        env_home = _pid_env_home(pid)
        if env_home:
            if os.path.realpath(env_home) == expected_home:
                return True
            continue
        return True
    pdir = os.path.join(cli_dir, "presence")
    if os.path.isdir(pdir):
        for lp in glob.glob(os.path.join(pdir, "*.lock")):
            if _is_lock_held(lp):
                return True
    if os.path.isfile(_default_token_file(cli_dir)):
        return True
    return False


def _cleanup_offline(
    cli_dir: str, min_age: int, dry_run: bool, verbose: bool
) -> int:
    if _is_agy_active_for_cli_dir(cli_dir):
        if verbose:
            print(_pick(I18N_MSG, "skip_online_offline_only", LOCALE))
        return 0

    candidates = find_empty_candidates(cli_dir, min_age=min_age, check_lock=True)
    if not candidates:
        if verbose:
            print(_pick(I18N_MSG, "none_found", LOCALE))
        return 0

    print(_pick(I18N_MSG, "found_empty", LOCALE, count=len(candidates), mode="offline"))
    if dry_run:
        for cid in candidates:
            print(_pick(I18N_MSG, "dry_run_one", LOCALE, cid=cid))
        print(_pick(I18N_MSG, "finished", LOCALE, count=len(candidates)))
        return len(candidates)

    delete_set = set(candidates)
    summaries_db = os.path.join(cli_dir, "conversation_summaries.db")
    conn = None
    try:
        if os.path.isfile(summaries_db):
            conn = sqlite3.connect(summaries_db, timeout=5.0)
            tables = {
                r[0]
                for r in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                ).fetchall()
            }
            for cid in candidates:
                conn.execute(
                    "DELETE FROM conversation_summaries WHERE conversation_id = ?",
                    (cid,),
                )
                if "conversation_parents" in tables:
                    conn.execute(
                        "DELETE FROM conversation_parents WHERE conversation_id = ?",
                        (cid,),
                    )
                if "conversations_fts" in tables:
                    try:
                        conn.execute(
                            "DELETE FROM conversations_fts WHERE conversation_id = ?",
                            (cid,),
                        )
                    except sqlite3.Error:
                        pass
            conn.commit()
    except Exception as e:
        print(_pick(I18N_MSG, "err_offline", LOCALE, err=e), file=sys.stderr)
        return 0
    finally:
        if conn is not None:
            try:
                conn.close()
            except sqlite3.Error:
                pass

    try:
        prune_jetbox_proto(os.path.join(cli_dir, "jetbox_summaries_proto.pb"), delete_set)
    except Exception as e:
        print(_pick(I18N_MSG, "err_offline", LOCALE, err=e), file=sys.stderr)

    deleted = 0
    for cid in candidates:
        for suffix in (".db", ".db-wal", ".db-shm"):
            p = os.path.join(cli_dir, "conversations", cid + suffix)
            if os.path.exists(p):
                try:
                    os.unlink(p)
                except OSError:
                    pass
        ann = os.path.join(cli_dir, "annotations", f"{cid}.pbtxt")
        if os.path.exists(ann):
            try:
                os.unlink(ann)
            except OSError:
                pass
        bdir = os.path.join(cli_dir, "brain", cid)
        if os.path.isdir(bdir) and not _brain_has_files(bdir):
            shutil.rmtree(bdir, ignore_errors=True)
        _remove_presence_lock(cli_dir, cid)
        print(_pick(I18N_MSG, "deleted_one", LOCALE, cid=cid))
        deleted += 1

    print(_pick(I18N_MSG, "finished", LOCALE, count=deleted))
    return deleted


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Clean genuinely empty Antigravity conversations")
    ap.add_argument("--home", default=BASE_HOME, help="Target Termux home directory")
    ap.add_argument("--pid", type=int, default=0, help="Specific running agy PID")
    ap.add_argument("--min-age", type=int, default=0, help="Skip conversations newer than N seconds (except startup)")
    ap.add_argument("--token-file", default="", help="Path to ephemeral CSRF token file")
    ap.add_argument("--include-startup", action="store_true", help="Bypass min-age for initial startup empty conversation")
    ap.add_argument("--offline-only", action="store_true", help="Only run offline cleanup when agy is stopped")
    ap.add_argument("--dry-run", action="store_true", help="Show empty conversations without deleting")
    ap.add_argument("--verbose", action="store_true", help="Always print status even when 0 empty chats exist")
    args = ap.parse_args(argv)

    cli_dir = _cli_dir(args.home)
    if not os.path.isdir(cli_dir):
        if args.verbose:
            print(_pick(I18N_MSG, "none_found", LOCALE))
        return 0

    if args.offline_only:
        _cleanup_offline(cli_dir, args.min_age, args.dry_run, args.verbose)
        return 0

    addr, csrf_tok, startup_cids = _resolve_live_endpoint(
        cli_dir,
        target_pid=args.pid,
        token_file=args.token_file,
        include_startup=args.include_startup,
    )
    if addr and csrf_tok:
        try:
            _cleanup_online(
                cli_dir, addr, csrf_tok, startup_cids, args.min_age, args.dry_run, args.verbose
            )
            return 0
        except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError) as e:
            if _list_agy_pids(remote_control_only=False):
                print(_pick(I18N_MSG, "err_rpc", LOCALE, cid="list", err=e), file=sys.stderr)
                return 1

    _cleanup_offline(cli_dir, args.min_age, args.dry_run, args.verbose)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
