#!/usr/bin/env python3
"""Synchronize ownership (u0_a466) and SELinux MCS labels on ~/.gemini and
~/.config/antigravity when agy runs as root, so normal Termux can read/write
config.json, cli.log, and token metadata without Permission denied.
"""
import ctypes
import errno
import os
import select
import signal
import stat
import struct
import subprocess
import sys

IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
IN_Q_OVERFLOW = 0x00004000
IN_IGNORED = 0x00008000
IN_ISDIR = 0x40000000
IN_MASK = IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE_SELF | IN_MOVE_SELF

EVENT_HDR = struct.Struct("=iIII")

SECRET_NAMES = frozenset({"antigravity-oauth-token", "plugin-secrets.json", ".ls_csrf_token"})
READABLE_NAMES = frozenset({"config.json", "boot.log", "remote_control", "lang", ".system_lang"})


def _load_libc():
    for name in ("libc.so", "libc.so.6"):
        try:
            libc = ctypes.CDLL(name, use_errno=True)
            libc.lgetxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t]
            libc.lgetxattr.restype = ctypes.c_ssize_t
            libc.lsetxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
            libc.lsetxattr.restype = ctypes.c_int
            libc.inotify_init1.argtypes = [ctypes.c_int]
            libc.inotify_init1.restype = ctypes.c_int
            libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
            libc.inotify_add_watch.restype = ctypes.c_int
            libc.inotify_rm_watch.argtypes = [ctypes.c_int, ctypes.c_int]
            libc.inotify_rm_watch.restype = ctypes.c_int
            return libc
        except OSError:
            continue
    return None


LIBC = _load_libc()
XATTR_NAME = b"security.selinux"


def get_selinux_xattr(path_bytes: bytes):
    if LIBC is None:
        return None
    buf = ctypes.create_string_buffer(256)
    n = LIBC.lgetxattr(path_bytes, XATTR_NAME, buf, len(buf))
    if n <= 0:
        return None
    val = buf.raw[:n].rstrip(b"\x00")
    return val if val else None


def set_selinux_xattr(path_bytes: bytes, ctx_bytes: bytes) -> None:
    if not ctx_bytes or LIBC is None:
        return
    cur = get_selinux_xattr(path_bytes)
    if cur == ctx_bytes:
        return
    payload = ctx_bytes + b"\x00"
    LIBC.lsetxattr(path_bytes, XATTR_NAME, payload, len(payload), 0)


def resolve_termux_meta(home: str):
    st = os.stat(home)
    uid, gid = st.st_uid, st.st_gid
    ctx = get_selinux_xattr(os.fsencode(home))
    if ctx is None and os.path.exists("/system/bin/stat"):
        try:
            out = subprocess.check_output(
                ["/system/bin/stat", "-c", "%C", home],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            if out and out != "?":
                ctx = out.encode("utf-8")
        except Exception:
            pass
    return uid, gid, ctx


def fix_entry(path: str, uid: int, gid: int, ctx_bytes) -> None:
    try:
        st = os.lstat(path)
    except OSError:
        return

    if st.st_uid != uid or st.st_gid != gid:
        try:
            os.lchown(path, uid, gid)
        except OSError:
            pass

    if ctx_bytes:
        try:
            set_selinux_xattr(os.fsencode(path), ctx_bytes)
        except OSError:
            pass

    if stat.S_ISLNK(st.st_mode):
        return

    mode = stat.S_IMODE(st.st_mode)
    base = os.path.basename(path)
    if base in SECRET_NAMES:
        if mode != 0o600:
            try:
                os.chmod(path, 0o600)
            except OSError:
                pass
    elif stat.S_ISREG(st.st_mode) and (
        base in READABLE_NAMES or "/antigravity-cli/log/" in path
    ):
        desired = mode | 0o644
        if desired != mode:
            try:
                os.chmod(path, desired)
            except OSError:
                pass


class WatchManager:
    def __init__(self, uid: int, gid: int, ctx_bytes):
        self.uid = uid
        self.gid = gid
        self.ctx_bytes = ctx_bytes
        self.ifd = LIBC.inotify_init1(0) if LIBC is not None else -1
        self.wd_to_path = {}
        self.path_to_wd = {}

    def close(self):
        if self.ifd >= 0:
            try:
                os.close(self.ifd)
            except OSError:
                pass
            self.ifd = -1

    def add_watch(self, path: str, mask: int = IN_MASK) -> None:
        if self.ifd < 0:
            return
        norm = os.path.normpath(path)
        if norm in self.path_to_wd:
            return
        wd = LIBC.inotify_add_watch(self.ifd, os.fsencode(norm), mask)
        if wd >= 0:
            self.wd_to_path[wd] = norm
            self.path_to_wd[norm] = wd

    def remove_wd(self, wd: int) -> None:
        p = self.wd_to_path.pop(wd, None)
        if p is not None:
            self.path_to_wd.pop(p, None)

    def sync_tree(self, root: str, watch: bool = False) -> None:
        if not os.path.lexists(root):
            return
        fix_entry(root, self.uid, self.gid, self.ctx_bytes)
        try:
            st = os.lstat(root)
        except OSError:
            return
        if not stat.S_ISDIR(st.st_mode):
            return
        if watch:
            self.add_watch(root)
        stack = [root]
        while stack:
            cur = stack.pop()
            try:
                with os.scandir(cur) as it:
                    for entry in it:
                        p = entry.path
                        fix_entry(p, self.uid, self.gid, self.ctx_bytes)
                        try:
                            if entry.is_dir(follow_symlinks=False):
                                if watch:
                                    self.add_watch(p)
                                stack.append(p)
                        except OSError:
                            continue
            except OSError:
                continue


def sync_all(home: str, prefix: str, mgr: WatchManager, watch: bool = False, include_extra: bool = False) -> None:
    if watch:
        mgr.add_watch(home)
    mgr.sync_tree(os.path.join(home, ".gemini"), watch=watch)

    cfg_dir = os.path.join(home, ".config")
    if os.path.lexists(cfg_dir):
        fix_entry(cfg_dir, mgr.uid, mgr.gid, mgr.ctx_bytes)
        if watch and os.path.isdir(cfg_dir) and not os.path.islink(cfg_dir):
            mgr.add_watch(cfg_dir)
        mgr.sync_tree(os.path.join(cfg_dir, "antigravity"), watch=watch)

    if include_extra:
        mgr.sync_tree(os.path.join(home, ".local"), watch=False)
        for p in (
            os.path.join(prefix, "bin", "agy"),
            os.path.join(prefix, "bin", "agy.va39"),
            os.path.join(prefix, "var", "run", "agy_root.lock"),
            os.path.join(prefix, "var", "run", "agy_start.lock"),
        ):
            if os.path.lexists(p):
                fix_entry(p, mgr.uid, mgr.gid, mgr.ctx_bytes)


def watch_loop(home: str, prefix: str, mgr: WatchManager) -> None:
    stop = False

    def _on_sig(_signum, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, _on_sig)
    signal.signal(signal.SIGINT, _on_sig)
    signal.signal(signal.SIGHUP, _on_sig)

    sync_all(home, prefix, mgr, watch=True, include_extra=True)
    if mgr.ifd < 0:
        while not stop:
            select.select([], [], [], 5.0)
            sync_all(home, prefix, mgr, watch=False, include_extra=False)
        return

    buf = b""
    while not stop:
        try:
            r, _, _ = select.select([mgr.ifd], [], [], 15.0)
        except InterruptedError:
            continue
        except OSError:
            break

        if not r:
            sync_all(home, prefix, mgr, watch=True, include_extra=False)
            continue

        try:
            chunk = os.read(mgr.ifd, 65536)
        except OSError as e:
            if e.errno in (errno.EINTR, errno.EAGAIN):
                continue
            break
        if not chunk:
            break
        buf += chunk

        off = 0
        need_resync = False
        while off + EVENT_HDR.size <= len(buf):
            wd, mask, _cookie, name_len = EVENT_HDR.unpack_from(buf, off)
            if off + EVENT_HDR.size + name_len > len(buf):
                break
            raw_name = buf[off + EVENT_HDR.size : off + EVENT_HDR.size + name_len]
            off += EVENT_HDR.size + name_len
            name = os.fsdecode(raw_name.split(b"\x00", 1)[0])

            if mask & IN_Q_OVERFLOW:
                need_resync = True
                continue
            if mask & (IN_IGNORED | IN_DELETE_SELF | IN_MOVE_SELF):
                mgr.remove_wd(wd)
                continue

            parent = mgr.wd_to_path.get(wd)
            if not parent or not name:
                continue

            # On $HOME, only react to .gemini and .config; on ~/.config, only antigravity
            if parent == os.path.normpath(home):
                if name not in (".gemini", ".config"):
                    continue
                target = os.path.join(parent, name)
                if name == ".config":
                    fix_entry(target, mgr.uid, mgr.gid, mgr.ctx_bytes)
                    if os.path.isdir(target) and not os.path.islink(target):
                        mgr.add_watch(target)
                        mgr.sync_tree(os.path.join(target, "antigravity"), watch=True)
                else:
                    mgr.sync_tree(target, watch=True)
                continue

            if parent == os.path.normpath(os.path.join(home, ".config")):
                if name != "antigravity":
                    continue
                mgr.sync_tree(os.path.join(parent, name), watch=True)
                continue

            target = os.path.join(parent, name)
            if (mask & IN_ISDIR) or (os.path.isdir(target) and not os.path.islink(target)):
                mgr.sync_tree(target, watch=True)
            else:
                fix_entry(target, mgr.uid, mgr.gid, mgr.ctx_bytes)

        buf = buf[off:]
        if need_resync:
            sync_all(home, prefix, mgr, watch=True, include_extra=False)

    sync_all(home, prefix, mgr, watch=False, include_extra=True)


def main():
    if os.geteuid() != 0:
        return 0

    home = os.path.normpath(os.environ.get("HOME") or "/data/data/com.termux/files/home")
    prefix = os.path.normpath(os.environ.get("PREFIX") or "/data/data/com.termux/files/usr")
    if not os.path.isdir(home):
        return 0

    uid, gid, ctx_bytes = resolve_termux_meta(home)
    mgr = WatchManager(uid, gid, ctx_bytes)
    try:
        if "--watch" in sys.argv[1:]:
            watch_loop(home, prefix, mgr)
        else:
            sync_all(home, prefix, mgr, watch=False, include_extra=True)
    finally:
        mgr.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
