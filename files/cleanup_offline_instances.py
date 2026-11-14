#!/usr/bin/env python3
import sys

sys.dont_write_bytecode = True
import json
import os
import time
import urllib.request
import urllib.error

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
    "err_token": {
        "zh-TW": "[cleanup] 無法讀取登入憑證: {err}",
        "zh-CN": "[cleanup] 无法读取登录凭证: {err}",
        "ja": "[cleanup] 認証トークンを読み取れません: {err}",
        "en": "[cleanup] Cannot read token: {err}",
    },
    "token_expired": {
        "zh-TW": "[cleanup] 憑證已過期 (401)，等待 agy 自動重新整理 ({attempt}/{max_retries})...",
        "zh-CN": "[cleanup] 凭证已过期 (401)，等待 agy 自动刷新 ({attempt}/{max_retries})...",
        "ja": "[cleanup] トークン期限切れ (401)、agy の自動更新を待機中 ({attempt}/{max_retries})...",
        "en": "[cleanup] Token expired (401), waiting for agy to refresh ({attempt}/{max_retries})...",
    },
    "err_list": {
        "zh-TW": "[cleanup] 取得實例清單失敗: {err}",
        "zh-CN": "[cleanup] 获取实例列表失败: {err}",
        "ja": "[cleanup] インスタンス一覧の取得に失敗しました: {err}",
        "en": "[cleanup] ListInstances failed: {err}",
    },
    "err_net": {
        "zh-TW": "[cleanup] 網路或資料解析錯誤: {err}",
        "zh-CN": "[cleanup] 网络或数据解析错误: {err}",
        "ja": "[cleanup] ネットワークまたは解析エラー: {err}",
        "en": "[cleanup] Network or parsing error: {err}",
    },
    "found_offline": {
        "zh-TW": "[cleanup] 發現離線舊實例: {name} ({uuid}, {version})，正在刪除...",
        "zh-CN": "[cleanup] 发现离线旧实例: {name} ({uuid}, {version})，正在删除...",
        "ja": "[cleanup] オフラインの古いインスタンスを検出: {name} ({uuid}, {version})、削除中...",
        "en": "[cleanup] Found offline instance: {name} ({uuid}, {version}), deleting...",
    },
    "pruned": {
        "zh-TW": "[cleanup] 已清理離線實例 {name} ({uuid})",
        "zh-CN": "[cleanup] 已清理离线实例 {name} ({uuid})",
        "ja": "[cleanup] 古いインスタンスを削除しました {name} ({uuid})",
        "en": "[cleanup] Successfully pruned {name} ({uuid})",
    },
    "err_del": {
        "zh-TW": "[cleanup] 刪除 {uuid} 失敗: {err}",
        "zh-CN": "[cleanup] 删除 {uuid} 失败: {err}",
        "ja": "[cleanup] {uuid} の削除に失敗しました: {err}",
        "en": "[cleanup] Failed to delete {uuid}: {err}",
    },
    "finished": {
        "zh-TW": "[cleanup] 完成。共清理 {count} 個過期離線實例。",
        "zh-CN": "[cleanup] 完成。共清理 {count} 个过期离线实例。",
        "ja": "[cleanup] 完了。期限切れのオフラインインスタンスを {count} 件整理しました。",
        "en": "[cleanup] Finished. Cleaned {count} stale offline instance(s).",
    },
}

TOKEN_PATH = os.path.join(BASE_HOME, ".gemini/antigravity-cli/antigravity-oauth-token")
CONFIG_PATH = os.path.join(BASE_HOME, ".gemini/config/config.json")
LIST_URL = "https://antigravity.google.com/$rpc/devtools_jetski_boq_api_proto.ApiService/ListInstances"
DEL_URL = "https://antigravity.google.com/$rpc/devtools_jetski_boq_api_proto.ApiService/DeleteInstance"

# Built-in random slug wordlists extracted from Antigravity binary (worktreename & remote_control)
RANDOM_ADJS = {
    "astral", "blazing", "bright", "cosmic", "deep", "distant", "drifting",
    "fading", "fiery", "frozen", "galactic", "glowing", "golden", "hidden",
    "hollow", "lunar", "mighty", "misty", "noble", "orbital", "plasma",
    "polar", "quantum", "radiant", "rising", "roving", "silent", "solar",
    "spectral", "starlit", "stellar", "super", "turbo", "ultima", "vivid",
    "void", "zero",
}
RANDOM_NOUNS = {
    "aurora", "axis", "beacon", "bolt", "comet", "corona", "cosmos", "crater",
    "drift", "dust", "eclipse", "ember", "flare", "flux", "galaxy", "halo",
    "ion", "jade", "jet", "luna", "mars", "meteor", "nebula", "nova", "orbit",
    "photon", "planet", "plume", "pulsar", "quasar", "ray", "rocket", "shard",
    "sky", "sol", "spark", "star", "surge", "titan", "vapor", "vector",
    "venus", "vertex", "vortex", "wave", "zenith", "zone",
}


def get_current_hostname():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
            return cfg.get("userSettings", {}).get("cliRemoteControlHostname", "localhost-phone")
    except Exception:
        return "localhost-phone"


def get_access_token():
    try:
        with open(TOKEN_PATH, "r", encoding="utf-8") as f:
            token_data = json.load(f)
        return token_data.get("token", {}).get("access_token")
    except Exception as e:
        print(_pick(I18N_MSG, "err_token", LOCALE, err=e), file=sys.stderr)
        return None


def is_random_cli_slug(name: str, version: str) -> bool:
    if not version.startswith("cli-") or not name.startswith("localhost-"):
        return False
    rest = name[len("localhost-"):]
    if any(ch.isdigit() for ch in rest):
        return False
    parts = rest.split("-")
    return len(parts) == 2 and parts[0] in RANDOM_ADJS and parts[1] in RANDOM_NOUNS


def fetch_instances_with_retry(max_retries=6, delay=5):
    for attempt in range(1, max_retries + 1):
        token = get_access_token()
        if not token:
            if attempt < max_retries:
                time.sleep(delay)
                continue
            return None, None

        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json+protobuf",
        }
        req = urllib.request.Request(LIST_URL, headers=headers, data=b"[]")
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode())
                instances = data[0] if data and isinstance(data, list) else []
                return instances, token
        except urllib.error.HTTPError as e:
            if e.code == 401 and attempt < max_retries:
                print(
                    _pick(I18N_MSG, "token_expired", LOCALE, attempt=attempt, max_retries=max_retries),
                    file=sys.stderr,
                )
                time.sleep(delay)
                continue
            print(_pick(I18N_MSG, "err_list", LOCALE, err=e), file=sys.stderr)
            return None, None
        except Exception as e:
            print(_pick(I18N_MSG, "err_net", LOCALE, err=e), file=sys.stderr)
            if attempt < max_retries:
                time.sleep(delay)
                continue
            return None, None
    return None, None


def cleanup():
    current_hostname = get_current_hostname()
    result = fetch_instances_with_retry()
    if not result:
        return
    instances, token = result
    if instances is None:
        return

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json+protobuf",
    }

    cleaned_count = 0
    for inst in instances:
        if not isinstance(inst, list) or len(inst) < 3:
            continue
        uuid = inst[0]
        meta = inst[1] if isinstance(inst[1], list) else []
        name = meta[0] if len(meta) > 0 else ""
        version = meta[1] if len(meta) > 1 else ""
        status = inst[2]  # 1 = ONLINE, 2 = OFFLINE

        if status != 2:
            continue

        # Prune OFFLINE instances only if:
        # 1. Stale previous session matching this device's configured hostname
        # 2. Legacy "localhost-phone" placeholder
        # 3. Unpatched CLI random 2-word slug (e.g. localhost-blazing-drift)
        # Never touches pc-*, desktop-*, or other phones with distinct device models (e.g. localhost-pixel-8).
        should_prune = (
            name == current_hostname
            or name == "localhost-phone"
            or is_random_cli_slug(name, version)
        )

        if should_prune:
            print(_pick(I18N_MSG, "found_offline", LOCALE, name=name, uuid=uuid, version=version))
            try:
                dreq = urllib.request.Request(
                    DEL_URL,
                    headers=headers,
                    data=json.dumps([uuid]).encode("utf-8"),
                )
                with urllib.request.urlopen(dreq, timeout=10) as dresp:
                    if dresp.status == 200:
                        print(_pick(I18N_MSG, "pruned", LOCALE, name=name, uuid=uuid))
                        cleaned_count += 1
            except Exception as e:
                print(_pick(I18N_MSG, "err_del", LOCALE, uuid=uuid, err=e), file=sys.stderr)

    if cleaned_count > 0:
        print(_pick(I18N_MSG, "finished", LOCALE, count=cleaned_count))


if __name__ == "__main__":
    cleanup()
