#!/usr/bin/env python3
"""Shared Python i18n helper (zh-TW / zh-CN / en / ja) for Antigravity module."""
import os
import re

VALID_LOCALES = ("zh-TW", "zh-CN", "en", "ja")


def normalize_locale(raw: str):
    if not raw:
        return None
    s = raw.strip().strip('"').splitlines()[0].strip() if raw.strip() else ""
    if not s:
        return None
    tag = s.split(",", 1)[0].strip().lower().replace("_", "-")
    tag = tag.split(".", 1)[0].split("@", 1)[0]
    if not tag or tag in ("auto", "c", "posix", "system", "default") or tag.startswith("c-"):
        return None
    if (
        re.match(r"^zh-(?:.*-)?(?:tw|hk|mo|hant)\b", tag)
        or tag in ("tw", "zhtw", "hk", "mo", "hant", "tc", "traditional")
    ):
        return "zh-TW"
    if tag.startswith("zh") or tag in ("cn", "zhcn", "hans", "sc", "simplified"):
        return "zh-CN"
    if tag.startswith("ja") or tag in ("jp", "japanese"):
        return "ja"
    return "en"


def _read_first_line(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.readline().strip()
    except OSError:
        return ""


def get_locale(home=None) -> str:
    home = home or os.environ.get("HOME") or "/data/data/com.termux/files/home"
    candidates = [
        os.environ.get("AGY_LANG", ""),
        _read_first_line(os.path.join(home, ".gemini", "config", "lang")),
        _read_first_line("/data/adb/antigravity_lang"),
        os.environ.get("AGY_LOCALE", ""),
        _read_first_line(os.path.join(home, ".gemini", "config", ".system_lang")),
        os.environ.get("LC_ALL", ""),
        os.environ.get("LC_MESSAGES", ""),
        os.environ.get("LANG", ""),
    ]
    for c in candidates:
        norm = normalize_locale(c)
        if norm:
            return norm
    return "en"


def pick(table: dict, key: str, locale: str = None, **kwargs) -> str:
    loc = locale or get_locale()
    entry = table.get(key, {})
    tmpl = entry.get(loc) or entry.get("en") or key
    return tmpl.format(**kwargs) if kwargs else tmpl
