#!/usr/bin/env python3
"""
fetch_agy_usage.py - Antigravity (agy) quota fetcher for KDE Plasma widget
Runs the documented headless `agy -p /usage --output-format json` command and keeps
only the Gemini 5-hour, Gemini weekly and Gemini Argon weekly buckets; Claude/GPT
(third-party) buckets are ignored. agy owns its sign-in; credentials are never read here.
"""

import sys
import os
import json
import time
import shutil
import tempfile
import subprocess
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from usage_common import (number, parse_iso_time, failure, run,  # noqa: E402
                          valid_windows_snapshot, window_entry, windows_snapshot, write_json_atomic)

CACHE_FILE = os.path.expanduser("~/.cache/agy_usage.json")
FALLBACK_AGY = os.path.expanduser("~/.local/bin/agy")  # plasmashell PATH may lack ~/.local/bin
COMMAND_ARGS = ("-p", "/usage", "--output-format", "json")
TIMEOUT_SECONDS = 30
SIGN_IN_MESSAGE = "Antigravity sign-in required. Run 'agy' and sign in."

# Display order: (window id, label, window length in seconds)
GEMINI_5H = ("gemini_5h", "Gemini · 5h", 5 * 3600)
GEMINI_WEEKLY = ("gemini_weekly", "Gemini · Weekly", 7 * 86400)
ARGON_WEEKLY = ("argon_weekly", "Argon · Weekly", 7 * 86400)
ORDER = (GEMINI_5H[0], GEMINI_WEEKLY[0], ARGON_WEEKLY[0])


def window_spec(bucket):
    """Map an agy bucket to a displayed window; anything else (e.g. 3p-*) is ignored."""
    bucket_id = bucket.get("id")
    if bucket_id == "gemini-5h":
        return GEMINI_5H
    if bucket_id == "gemini-weekly":
        return GEMINI_WEEKLY
    if isinstance(bucket_id, str) and bucket_id.startswith("gemini-argon") and bucket.get("window") == "weekly":
        return ARGON_WEEKLY
    return None


def load_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            json.dumps(data, allow_nan=False)
            if valid_windows_snapshot(data):
                return data
        except Exception:
            return None
    return None


def save_cache(data):
    write_json_atomic(CACHE_FILE, data)


def build_snapshot(groups):
    if not isinstance(groups, list):
        raise ValueError("Invalid usage response")
    now_utc = datetime.now(timezone.utc)
    windows = {}
    for group in groups:
        buckets = group.get("buckets") if isinstance(group, dict) else None
        for bucket in buckets if isinstance(buckets, list) else ():
            spec = window_spec(bucket) if isinstance(bucket, dict) else None
            fraction = bucket.get("remaining_fraction") if spec else None
            if spec is None or spec[0] in windows or not number(fraction) or not 0 <= fraction <= 1:
                continue
            # A full bucket has a floating reset time (now + window), so it counts as not started.
            reset_raw = bucket.get("reset_time")
            reset_dt = parse_iso_time(reset_raw) if fraction < 1 and isinstance(reset_raw, str) else None
            window_id, label, window_seconds = spec
            windows[window_id] = window_entry(window_id, label, window_seconds, (1 - fraction) * 100,
                                              reset_dt, now_utc, fraction <= 0)
    # Argon is optional: Ultra plans fold it into the larger Gemini bucket.
    if GEMINI_5H[0] not in windows and GEMINI_WEEKLY[0] not in windows:
        raise ValueError("No Gemini quota in agy usage output")
    return windows_snapshot([windows[key] for key in ORDER if key in windows], "Antigravity", int(time.time()))


def find_agy():
    found = shutil.which("agy")
    if found:
        return found
    return FALLBACK_AGY if os.access(FALLBACK_AGY, os.X_OK) else None


def first_line(text):
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()[:200]
    return ""


def fetch_result(cached):
    agy = find_agy()
    if not agy:
        return failure(cached, "error", "Antigravity CLI (agy) not found.")
    try:
        proc = subprocess.run([agy, *COMMAND_ARGS], stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, cwd=tempfile.gettempdir(), timeout=TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        return failure(cached, "offline", "agy /usage timed out.", True)
    except OSError:
        return failure(cached, "error", "Failed to run Antigravity CLI (agy).")
    if proc.returncode != 0:
        message = first_line(proc.stderr) or first_line(proc.stdout) or "agy /usage failed."
        lowered = message.lower()
        if "sign in" in lowered or "sign-in" in lowered or "log in" in lowered or "login" in lowered:
            return failure(cached, "no_auth", SIGN_IN_MESSAGE)
        return failure(cached, "error", message, True)
    data = json.loads(proc.stdout)
    command = data.get("command") if isinstance(data, dict) else None
    if not isinstance(command, dict) or command.get("name") != "usage" or not isinstance(command.get("data"), dict):
        raise ValueError("Invalid usage response")
    result = build_snapshot(command["data"].get("groups"))
    save_cache(result)
    return result


def fetch():
    run(load_cache, fetch_result, SIGN_IN_MESSAGE, SIGN_IN_MESSAGE)


if __name__ == "__main__":
    fetch()
