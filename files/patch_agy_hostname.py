#!/usr/bin/env python3
"""Dynamically patch Antigravity CLI (aarch64 Go ELF) so --remote-control
uses userSettings.cliRemoteControlHostname instead of generating random slugs.
Supports both single native ELF (`agy`) and wallentx twin-binary (`agy` + `agy.va39`).
"""
import sys

sys.dont_write_bytecode = True
import os
import stat
import struct
import subprocess

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


I18N_MSG = {
    "skip_missing": {
        "zh-TW": "略過 (檔案不存在): {path}",
        "zh-CN": "跳过 (文件不存在): {path}",
        "ja": "スキップ (ファイル未検出): {path}",
        "en": "skip (missing): {path}",
    },
    "skip_small": {
        "zh-TW": "略過 (啟動器/過小): {path}",
        "zh-CN": "跳过 (启动器/过小): {path}",
        "ja": "スキップ (ブートストラップ/小型): {path}",
        "en": "skip (bootstrapper/too small): {path}",
    },
    "patched": {
        "zh-TW": "已修補 {real_path} ({offset}): {old} -> {new}",
        "zh-CN": "已修补 {real_path} ({offset}): {old} -> {new}",
        "ja": "パッチ適用完了 {real_path} ({offset}): {old} -> {new}",
        "en": "patched {real_path} at {offset}: {old} -> {new}",
    },
    "already_patched": {
        "zh-TW": "已套用補丁 {real_path} ({offset}): {cur}",
        "zh-CN": "已应用补丁 {real_path} ({offset}): {cur}",
        "ja": "パッチ適用済み {real_path} ({offset}): {cur}",
        "en": "already patched {real_path} at {offset}: {cur}",
    },
    "patched_legacy": {
        "zh-TW": "已修補 (相容模式) {real_path} ({offset})",
        "zh-CN": "已修补 (兼容模式) {real_path} ({offset})",
        "ja": "パッチ適用完了 (レガシー) {real_path} ({offset})",
        "en": "patched (legacy) {real_path} at {offset}",
    },
    "warn_pattern": {
        "zh-TW": "警告: 未在 {real_path} 找到目標指令特徵",
        "zh-CN": "警告: 未在 {real_path} 找到目标指令特征",
        "ja": "警告: {real_path} に対象命令パターンが見つかりません",
        "en": "warning: target instruction pattern not found in {real_path}",
    },
    "error": {
        "zh-TW": "[patch_agy] {path} 發生錯誤: {err}",
        "zh-CN": "[patch_agy] {path} 发生错误: {err}",
        "ja": "[patch_agy] {path} でエラー: {err}",
        "en": "[patch_agy] error on {path}: {err}",
    },
}


GO_STACK_CHECK = b"\x90\x0b\x40\xf9\xff\x63\x30\xeb"
GO_STACK_LDR = b"\x90\x0b\x40\xf9"


def restore_selinux_context(real_path: str) -> None:
    if not os.path.exists("/system/bin/chcon") or not os.path.exists("/system/bin/stat"):
        return
    try:
        dir_ctx = subprocess.check_output(
            ["/system/bin/stat", "-c", "%C", os.path.dirname(real_path)],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if dir_ctx:
            subprocess.run(
                ["/system/bin/chcon", dir_ctx, real_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
    except Exception:
        pass


def find_text_section(data: bytes):
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise ValueError("Not a 64-bit little-endian ELF")
    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 58)
    shstr_off = struct.unpack_from("<Q", data, e_shoff + e_shstrndx * e_shentsize + 24)[0]
    for i in range(e_shnum):
        base = e_shoff + i * e_shentsize
        nm_off, _, _, va, off, sz = struct.unpack_from("<IIQQQQ", data, base)
        end = data.find(b"\x00", shstr_off + nm_off)
        nm = data[shstr_off + nm_off : end].decode("latin1", "replace")
        if nm == ".text":
            return va, off, sz
    raise ValueError(".text section not found")


def find_target_function(data: bytes, text_off: int, text_sz: int):
    for magic in (b"\xf1\xff\xff\xff\x00\x00\x04\x08", b"\xf1\xff\xff\xff\x00\x00\x01\x08"):
        pos = 0
        while True:
            idx = data.find(magic, pos)
            if idx == -1:
                break
            nfunc = struct.unpack_from("<Q", data, idx + 8)[0]
            if 1000 < nfunc < 500000:
                _, funcname_offset, _, _, _, pcln_offset = struct.unpack_from("<6Q", data, idx + 24)
                ftab_off = idx + pcln_offset
                funcnames_off = idx + funcname_offset
                if ftab_off + (nfunc + 1) * 8 <= len(data):
                    target_e = target_ne = None
                    neighbors = []
                    for k in range(nfunc):
                        e, fo = struct.unpack_from("<II", data, ftab_off + k * 8)
                        ne = struct.unpack_from("<I", data, ftab_off + (k + 1) * 8)[0]
                        if target_e is None:
                            noff = struct.unpack_from("<i", data, ftab_off + fo + 4)[0]
                            s = funcnames_off + noff
                            nm = data[s : data.find(b"\x00", s)].decode("utf-8", "replace")
                            if nm.endswith(".(*Server).remoteControlDisplayHostname"):
                                target_e, target_ne = e, ne
                        if target_e is not None:
                            if ne - e >= 0x80:
                                neighbors.append(e)
                            if len(neighbors) >= 25:
                                break
                    if target_e is not None and len(neighbors) >= 20:
                        base_e = neighbors[0]
                        scan = text_off + base_e
                        end_text = text_off + text_sz
                        threshold = max(20, len(neighbors) - 2)
                        while True:
                            hit = data.find(GO_STACK_CHECK, scan, end_text)
                            if hit == -1:
                                break
                            cand = hit - base_e
                            matches = sum(
                                1
                                for e in neighbors
                                if text_off <= cand + e < end_text
                                and data[cand + e : cand + e + 4] == GO_STACK_LDR
                            )
                            if matches >= threshold:
                                fn_start = cand + target_e
                                fn_end = cand + target_ne
                                if data[fn_start : fn_start + 4] == GO_STACK_LDR:
                                    return fn_start, fn_end
                            scan = hit + 4
            pos = idx + 4
    raise ValueError("remoteControlDisplayHostname not located via .gopclntab")


def atomic_write_binary(real_path: str, data: bytearray) -> None:
    st = os.stat(real_path)
    tmp = real_path + ".mod_patch"
    with open(tmp, "wb") as wf:
        wf.write(data)
    os.chmod(tmp, stat.S_IMODE(st.st_mode) | 0o755)
    try:
        os.chown(tmp, st.st_uid, st.st_gid)
    except OSError:
        pass
    os.replace(tmp, real_path)
    restore_selinux_context(real_path)


def patch_binary(path: str, locale: str = None) -> str:
    loc = locale or get_locale()
    real_path = os.path.realpath(path)
    if not os.path.isfile(real_path):
        return _pick(I18N_MSG, "skip_missing", loc, path=path)
    if os.path.getsize(real_path) < 2 * 1024 * 1024:
        return _pick(I18N_MSG, "skip_small", loc, path=path)

    with open(real_path, "rb") as f:
        data = bytearray(f.read())

    _, text_off, text_sz = find_text_section(data)
    fn_start, fn_end = find_target_function(data, text_off, text_sz)

    insns = [struct.unpack_from("<I", data, off)[0] for off in range(fn_start, fn_end, 4)]
    for i in range(len(insns) - 7):
        if (
            (insns[i] & 0xFFC003FF) == 0x39400043
            and (insns[i + 2] & 0xFFC003FF) == 0x39400044
            and (insns[i + 3] & 0xFFF8001F) == 0x37000004
            and (insns[i + 4] & 0xFC000000) == 0x94000000
        ):
            patch_off = fn_start + (i + 1) * 4
            cur = insns[i + 1]
            if (cur & 0xFFF8001F) == 0x36000003:
                imm14 = (cur >> 5) & 0x3FFF
                if imm14 >= 0x2000:
                    imm14 -= 0x4000
                target_idx = i + 1 + imm14
                if 0 <= target_idx < len(insns) and (insns[target_idx] & 0xFF00001F) == 0xB4000001:
                    new_insn = 0x14000000 | (imm14 & 0x03FFFFFF)
                    struct.pack_into("<I", data, patch_off, new_insn)
                    atomic_write_binary(real_path, data)
                    return _pick(
                        I18N_MSG,
                        "patched",
                        loc,
                        real_path=real_path,
                        offset=hex(patch_off),
                        old=f"{cur:08x}",
                        new=f"{new_insn:08x}",
                    )
            elif (cur & 0xFC000000) == 0x14000000:
                return _pick(
                    I18N_MSG,
                    "already_patched",
                    loc,
                    real_path=real_path,
                    offset=hex(patch_off),
                    cur=f"{cur:08x}",
                )

    legacy = b"\x43\x20\x4f\x39\xe3\x00\x00\x36"
    idx = data.find(legacy)
    if idx != -1:
        data[idx + 4 : idx + 8] = b"\x07\x00\x00\x14"
        atomic_write_binary(real_path, data)
        return _pick(
            I18N_MSG,
            "patched_legacy",
            loc,
            real_path=real_path,
            offset=hex(idx + 4),
        )

    return _pick(I18N_MSG, "warn_pattern", loc, real_path=real_path)


def expand_candidates(raw_paths):
    expanded = []
    for p in raw_paths:
        expanded.append(p)
        if not p.endswith(".va39") and not p.endswith("-va39"):
            expanded.append(p + ".va39")
            if os.path.exists(p):
                sibling = os.path.join(os.path.dirname(os.path.realpath(p)), "agy.va39")
                expanded.append(sibling)
    return expanded


def main():
    home = os.environ.get("HOME") or "/data/data/com.termux/files/home"
    prefix = os.environ.get("PREFIX") or "/data/data/com.termux/files/usr"
    loc = get_locale(home)
    raw = sys.argv[1:] or [
        os.path.join(prefix, "bin", "agy"),
        os.path.join(home, ".local", "bin", "agy"),
    ]
    seen = set()
    for p in expand_candidates(raw):
        if not os.path.exists(p):
            continue
        rp = os.path.realpath(p)
        if rp in seen:
            continue
        seen.add(rp)
        try:
            msg = patch_binary(rp, loc)
            print(f"[patch_agy] {msg}")
        except Exception as e:
            print(_pick(I18N_MSG, "error", loc, path=rp, err=e), file=sys.stderr)


if __name__ == "__main__":
    main()
