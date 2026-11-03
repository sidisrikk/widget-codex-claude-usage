#!/usr/bin/env python3
"""
fetch_claude_usage.py - Claude subscription usage fetcher for KDE Plasma widget
Reads the Claude Code OAuth token (read-only; never refreshed or written) and
outputs one quota/time pair per rate-limit window (5-hour session, weekly, ...).
"""

import sys
import os
import json
import time
import ssl
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from usage_common import (number, parse_iso_time, failure, request_json, run,  # noqa: E402
                          valid_windows_snapshot, window_entry, windows_snapshot, write_json_atomic)

CACHE_FILE = os.path.expanduser("~/.cache/claude_usage.json")
AUTH_FILE = os.path.expanduser("~/.claude/.credentials.json")
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
EXPIRED_MESSAGE = "Claude token expired. Open Claude Code to refresh it."

# (response key, window id, label, window length in seconds)
WINDOWS = (
    ("five_hour", "session", "Session (5h)", 5 * 3600),
    ("seven_day", "weekly", "Weekly", 7 * 86400),
    ("seven_day_sonnet", "weekly_sonnet", "Weekly Sonnet", 7 * 86400),
    ("seven_day_opus", "weekly_opus", "Weekly Opus", 7 * 86400),
)


# Shared windows contract; the old name stays for callers and tests.
valid_cached_snapshot = valid_windows_snapshot


def load_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            json.dumps(data, allow_nan=False)
            if valid_cached_snapshot(data):
                return data
        except Exception:
            return None
    return None


def save_cache(data):
    write_json_atomic(CACHE_FILE, data)


def build_window(raw, window_id, label, window_seconds, now_utc):
    reset_dt = parse_iso_time(raw["resets_at"]) if isinstance(raw.get("resets_at"), str) else None
    return window_entry(window_id, label, window_seconds, raw["utilization"], reset_dt, now_utc,
                        bool(raw.get("locked_reason")))


def build_snapshot(data, plan):
    if not isinstance(data, dict):
        raise ValueError("Invalid usage response")
    now_utc = datetime.now(timezone.utc)
    windows = []
    for key, window_id, label, window_seconds in WINDOWS:
        raw = data.get(key)
        if isinstance(raw, dict) and number(raw.get("utilization")):
            windows.append(build_window(raw, window_id, label, window_seconds, now_utc))
    if not any(window["id"] in ("session", "weekly") for window in windows):
        raise ValueError("No session or weekly usage window")

    return windows_snapshot(windows, plan, int(time.time()))


def fetch_result(cached):
    if not os.path.exists(AUTH_FILE):
        return failure(cached, "no_auth", "Claude Code credentials not found. Run 'claude' and log in.")
    try:
        with open(AUTH_FILE, "r", encoding="utf-8") as f:
            oauth = json.load(f).get("claudeAiOauth", {})
        token = oauth.get("accessToken")
        expires_at = oauth.get("expiresAt")
        plan = oauth.get("subscriptionType")
        if not token:
            return failure(cached, "no_token", "No access token found in Claude Code credentials.")
        if not isinstance(token, str):
            raise ValueError("Invalid credential fields")
    except Exception:
        return failure(cached, "auth_error", "Failed to read Claude Code credentials.")
    # Claude Code owns token refresh; an expired token is reported, never renewed here.
    if number(expires_at) and expires_at / 1000.0 <= time.time():
        return failure(cached, "auth_expired", EXPIRED_MESSAGE)

    headers = {"Authorization": f"Bearer {token}", "anthropic-beta": "oauth-2025-04-20",
               "User-Agent": "codex-usage-widget/1.0", "Accept": "application/json"}
    data = request_json(USAGE_URL, headers, ssl.create_default_context(), 10)
    result = build_snapshot(data, plan.capitalize() if isinstance(plan, str) and plan else "Claude")
    save_cache(result)
    return result


def fetch():
    run(load_cache, fetch_result, EXPIRED_MESSAGE,
        "Access denied. Log in to Claude Code again.")


if __name__ == "__main__":
    fetch()
