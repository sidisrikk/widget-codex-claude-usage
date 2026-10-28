#!/usr/bin/env python3
"""
fetch_usage.py - Codex / ChatGPT rate limit & usage fetcher for KDE Plasma widget
Fetches weekly rate limit window and individual reset credit expiration dates,
and outputs an enumerated resets list for a clean, minimal UI.
"""

import sys
import os
import json
import time
import ssl
import math
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from usage_common import (format_relative_time, parse_iso_time, parse_retry_after,  # noqa: E402,F401
                          failure, request_json, run)

CACHE_FILE = os.path.expanduser("~/.cache/codex_usage.json")
AUTH_FILE = os.path.expanduser("~/.codex/auth.json")
USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
CREDITS_URL = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"

def valid_cached_snapshot(data):
    """Match the frontend snapshot contract before attaching cached quota."""
    if not isinstance(data, dict) or not isinstance(data.get("resets"), list):
        return False
    def number(value):
        return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)
    if not all(isinstance(data.get(key), str) for key in
               ("plan", "reset_in", "reset_formatted", "updated_formatted")):
        return False
    if not all(number(data.get(key)) for key in
               ("used_percent", "left_percent", "cycle_elapsed_percent",
                "cycle_elapsed_days", "cycle_remaining_days", "updated_at")):
        return False
    if data["updated_at"] < 0 or not all(isinstance(data.get(key), bool) for key in ("allowed", "limit_reached")):
        return False
    for reset in data["resets"]:
        if not isinstance(reset, dict) or not all(isinstance(reset.get(key), str) for key in
                                                ("id", "label", "kind", "countdown", "date", "detail")):
            return False
        if not isinstance(reset.get("is_urgent"), bool) or "remaining_seconds" not in reset:
            return False
        if reset["remaining_seconds"] is not None and not number(reset["remaining_seconds"]):
            return False
    return True

def load_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                # Older successful snapshots used Infinity for unknown countdowns.
                # Migrate that sentinel without discarding the rest of the snapshot.
                if isinstance(data, dict) and isinstance(data.get("resets"), list):
                    for index, reset in enumerate(data["resets"]):
                        if isinstance(reset, dict) and reset.get("remaining_seconds") == float("inf"):
                            reset["remaining_seconds"] = None
                        if isinstance(reset, dict) and reset.get("kind") == "credit" and not isinstance(reset.get("id"), str):
                            reset["id"] = f"credit_{index}"
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

def build_snapshot(data, credits_list):
    # Extract primary rate limit window
    rate_limit = data.get("rate_limit", {})
    primary = rate_limit.get("primary_window", {}) or {}

    used_pct = primary["used_percent"]
    left_pct = max(0, 100 - used_pct)
    reset_at = primary.get("reset_at")
    reset_seconds = primary.get("reset_after_seconds", 0)
    limit_window = primary.get("limit_window_seconds", 604800)
    for value in (used_pct, reset_seconds, limit_window):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError("Invalid quota number")

    # 7-day cycle calculations
    elapsed_seconds = max(0, limit_window - reset_seconds)
    cycle_elapsed_pct = min(100.0, max(0.0, (elapsed_seconds / float(limit_window)) * 100.0)) if limit_window > 0 else 0
    elapsed_days = round(elapsed_seconds / 86400.0, 1)
    remaining_days = round(reset_seconds / 86400.0, 1)

    # Weekly reset format
    reset_formatted = "--"
    if reset_at:
        try:
            dt = datetime.fromtimestamp(reset_at, tz=timezone.utc).astimezone()
            reset_formatted = dt.strftime("%a, %d %b %H:%M")
        except Exception:
            pass

    reset_in_str = format_relative_time(reset_seconds) if reset_seconds else "--"

    # Enumerate all resets
    resets = []

    # Weekly Quota Window
    resets.append({
        "id": "reset_weekly",
        "label": "Weekly",
        "kind": "weekly",
        "countdown": reset_in_str,
        "date": reset_formatted,
        "detail": f"{left_pct}% quota left",
        "is_urgent": left_pct < 20,
        "remaining_seconds": reset_seconds if reset_seconds > 0 else None,
    })

    # Individual Credit Tokens
    now_utc = datetime.now(timezone.utc)
    credits_list = [credit for credit in credits_list if isinstance(credit, dict)] if isinstance(credits_list, list) else []
    for idx, credit in enumerate(credits_list):
        exp_iso = credit.get("expires_at")
        exp_countdown = "Available"
        exp_date_str = "--"
        sec_left = None

        if exp_iso:
            exp_dt = parse_iso_time(exp_iso)
            if exp_dt:
                sec_left = int((exp_dt - now_utc).total_seconds())
                exp_date_str = exp_dt.astimezone().strftime("%a, %d %b %H:%M")
                if sec_left > 0:
                    exp_countdown = format_relative_time(sec_left)
                else:
                    exp_countdown = "Expired"

        is_urgent = False
        remaining_sec = None
        if sec_left is not None:
            if sec_left > 0:
                remaining_sec = sec_left
                is_urgent = sec_left < 86400
            else:
                remaining_sec = None

        if sec_left is not None:
            exp_status = "Expired" if sec_left <= 0 else "Expires"
        else:
            exp_status = "Credit token"

        resets.append({
            "id": credit["id"] if isinstance(credit.get("id"), str) else f"credit_{idx}",
            "label": "Credit",
            "kind": "credit",
            "countdown": exp_countdown,
            "date": exp_date_str,
            "detail": exp_status,
            "is_urgent": is_urgent,
            "remaining_seconds": remaining_sec,
        })

    # If no individual credits fetched but count > 0, fallback to general items
    if not credits_list:
        credit_summary = data.get("rate_limit_reset_credits")
        available_credits = credit_summary.get("available_count", 0) if isinstance(credit_summary, dict) else 0
        if isinstance(available_credits, bool) or not isinstance(available_credits, int) or available_credits < 0:
            available_credits = 0
        for i in range(available_credits):
            resets.append({
                "id": f"credit_fallback_{i}",
                "label": "Credit",
                "kind": "credit",
                "countdown": "Ready",
                "date": "Available",
                "detail": "Credit token",
                "is_urgent": False,
                "remaining_seconds": None,
            })

    # Sort which resets will reach first (chronological order)
    resets.sort(key=lambda r: r["remaining_seconds"] if r["remaining_seconds"] is not None else float("inf"))

    now_ts = int(time.time())
    result = {
        "status": "ok",
        "cached": False,
        "has_data": True,
        "retryable": False,
        "retry_after_seconds": None,
        "attempted_at": now_ts,
        "plan": data.get("plan_type", "Standard"),
        "used_percent": used_pct,
        "left_percent": left_pct,
        "cycle_elapsed_percent": round(cycle_elapsed_pct, 1),
        "cycle_elapsed_days": elapsed_days,
        "cycle_remaining_days": remaining_days,
        "reset_in": reset_in_str,
        "reset_formatted": reset_formatted,
        "resets": resets,
        "allowed": rate_limit.get("allowed", True),
        "limit_reached": rate_limit.get("limit_reached", False),
        "updated_at": now_ts,
        "updated_formatted": datetime.fromtimestamp(now_ts).strftime("%H:%M:%S"),
    }

    json.dumps(result, allow_nan=False)
    return result


def fetch_result(cached):
    if not os.path.exists(AUTH_FILE):
        return failure(cached, "no_auth", "Codex credentials not found. Please run 'codex login'.")
    try:
        with open(AUTH_FILE, "r", encoding="utf-8") as f:
            auth = json.load(f)
        tokens = auth.get("tokens", {})
        token = tokens.get("access_token")
        account_id = tokens.get("account_id")
        if not token:
            return failure(cached, "no_token", "No access token found in Codex credentials.")
        if not isinstance(token, str) or (account_id is not None and not isinstance(account_id, str)):
            raise ValueError("Invalid credential fields")
    except Exception:
        return failure(cached, "auth_error", "Failed to read Codex credentials.")

    headers = {"Authorization": f"Bearer {token}", "User-Agent": "Codex/0.160.0",
               "Accept": "application/json"}
    if account_id:
        headers["chatgpt-account-id"] = account_id
    ctx = ssl.create_default_context()
    data = request_json(USAGE_URL, headers, ctx, 10)
    # Credits are optional: neither request nor parsing failure invalidates quota.
    try:
        credits = request_json(CREDITS_URL, headers, ctx, 6).get("credits", [])
        result = build_snapshot(data, credits)
    except Exception:
        result = build_snapshot(data, [])
    save_cache(result)
    return result


def fetch():
    run(load_cache, fetch_result, "Auth token expired. Please run 'codex login'.",
        "Access denied. Check your Codex account and log in again.")

if __name__ == "__main__":
    fetch()
