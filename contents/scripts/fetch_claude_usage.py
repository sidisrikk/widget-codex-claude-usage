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
import math
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from usage_common import format_relative_time, parse_iso_time, failure, request_json, run  # noqa: E402

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


def number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)


def valid_window(window):
    if not isinstance(window, dict):
        return False
    if not all(isinstance(window.get(key), str) for key in
               ("id", "label", "reset_in", "reset_formatted", "time_left_text")):
        return False
    if not all(number(window.get(key)) for key in
               ("used_percent", "left_percent", "window_seconds", "time_left_percent")):
        return False
    if not isinstance(window.get("limit_reached"), bool) or "remaining_seconds" not in window:
        return False
    return window["remaining_seconds"] is None or number(window["remaining_seconds"])


def valid_cached_snapshot(data):
    """Match the frontend snapshot contract before attaching cached quota."""
    if not isinstance(data, dict) or not isinstance(data.get("windows"), list) or not data["windows"]:
        return False
    if not all(isinstance(data.get(key), str) for key in ("plan", "updated_formatted")):
        return False
    if not all(number(data.get(key)) for key in ("used_percent", "left_percent", "updated_at")):
        return False
    if data["updated_at"] < 0 or not isinstance(data.get("limit_reached"), bool):
        return False
    return all(valid_window(window) for window in data["windows"])


def load_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            json.dumps(data, allow_nan=False)
            if valid_cached_snapshot(data) and data.get("has_data", True):
                return data
        except Exception:
            return None
    return None


def save_cache(data):
    try:
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, allow_nan=False)
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to write cache: {e}\n")


def format_time_left(seconds):
    if seconds >= 86400:
        return f"{round(seconds / 86400.0, 1)}d left"
    if seconds >= 3600:
        return f"{round(seconds / 3600.0, 1)}h left"
    return f"{max(1, math.ceil(seconds / 60.0))}m left"


def build_window(raw, window_id, label, window_seconds, now_utc):
    used = raw["utilization"]
    used = min(100.0, max(0.0, float(used)))
    left = int(max(0, min(100, round(100 - used))))
    reset_in, reset_formatted, time_left_text = "Not started", "--", "—"
    remaining, time_left_pct = None, 0.0
    reset_dt = parse_iso_time(raw["resets_at"]) if isinstance(raw.get("resets_at"), str) else None
    if reset_dt:
        seconds = int((reset_dt - now_utc).total_seconds())
        reset_formatted = reset_dt.astimezone().strftime("%a, %d %b %H:%M")
        reset_in = format_relative_time(seconds)
        if seconds > 0:
            remaining = seconds
            time_left_pct = round(min(100.0, seconds * 100.0 / window_seconds), 1)
            time_left_text = format_time_left(seconds)
    return {
        "id": window_id,
        "label": label,
        "used_percent": round(used, 1),
        "left_percent": left,
        "window_seconds": window_seconds,
        "reset_in": reset_in,
        "reset_formatted": reset_formatted,
        "remaining_seconds": remaining,
        "time_left_percent": time_left_pct,
        "time_left_text": time_left_text,
        "limit_reached": used >= 100 or bool(raw.get("locked_reason")),
    }


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

    now_ts = int(time.time())
    result = {
        "status": "ok",
        "cached": False,
        "has_data": True,
        "retryable": False,
        "retry_after_seconds": None,
        "attempted_at": now_ts,
        "plan": plan,
        "used_percent": max(window["used_percent"] for window in windows),
        "left_percent": min(window["left_percent"] for window in windows),
        "limit_reached": any(window["limit_reached"] for window in windows),
        "windows": windows,
        "updated_at": now_ts,
        "updated_formatted": datetime.fromtimestamp(now_ts).strftime("%H:%M:%S"),
    }
    json.dumps(result, allow_nan=False)
    return result


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
