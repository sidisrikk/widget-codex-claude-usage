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
import urllib.request
import urllib.error
import ssl
import math
import http.client
import tempfile
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone

CACHE_FILE = os.path.expanduser("~/.cache/codex_usage.json")
AUTH_FILE = os.path.expanduser("~/.codex/auth.json")
USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
CREDITS_URL = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"

def valid_cached_snapshot(data):
    """Match the frontend snapshot contract before attaching cached quota."""
    if (not isinstance(data, dict) or data.get("has_data") is not True
            or not isinstance(data.get("resets"), list)):
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
    if not all(0 <= data[key] <= 100 for key in ("used_percent", "left_percent")):
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
                if valid_cached_snapshot(data):
                    return data
        except Exception:
            return None
    return None

def save_cache(data):
    temporary_path = None
    try:
        cache_directory = os.path.dirname(CACHE_FILE) or "."
        os.makedirs(cache_directory, exist_ok=True)
        with tempfile.NamedTemporaryFile(
                "w", encoding="utf-8", dir=cache_directory,
                prefix=f".{os.path.basename(CACHE_FILE)}.", suffix=".tmp",
                delete=False) as f:
            temporary_path = f.name
            json.dump(data, f, indent=2, allow_nan=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary_path, CACHE_FILE)
        temporary_path = None
    except Exception as e:
        if temporary_path is not None:
            try:
                os.unlink(temporary_path)
            except OSError:
                pass
        sys.stderr.write(f"Warning: Failed to write cache: {e}\n")

def format_relative_time(seconds):
    # API durations can be fractional. Keep the user-facing countdown compact.
    seconds = int(seconds)
    if seconds <= 0:
        return "now"
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    mins = (seconds % 3600) // 60
    parts = []
    if days > 0:
        parts.append(f"{days}d")
    if hours > 0 or days > 0:
        parts.append(f"{hours}h")
    parts.append(f"{mins}m")
    return " ".join(parts)

def parse_iso_time(iso_str):
    try:
        # Handles 2026-10-05T04:21:09.385270Z
        clean_iso = iso_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(clean_iso)
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except Exception:
        return None

def build_snapshot(data, credits_list):
    # Extract primary rate limit window
    rate_limit = data.get("rate_limit", {})
    primary = rate_limit.get("primary_window", {}) or {}

    plan = data.get("plan_type", "Standard")
    allowed = rate_limit.get("allowed", True)
    limit_reached = rate_limit.get("limit_reached", False)
    if not isinstance(plan, str) or not isinstance(allowed, bool) or not isinstance(limit_reached, bool):
        raise ValueError("Invalid quota metadata")

    used_pct = primary["used_percent"]
    reset_at = primary.get("reset_at")
    reset_seconds = primary.get("reset_after_seconds", 0)
    limit_window = primary.get("limit_window_seconds", 604800)
    for value in (used_pct, reset_seconds, limit_window):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError("Invalid quota number")
    if not 0.0 <= used_pct <= 100.0:
        raise ValueError("Invalid used percentage")
    if reset_seconds < 0 or limit_window <= 0:
        raise ValueError("Invalid quota duration")
    left_pct = 100 - used_pct

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
        "plan": plan,
        "used_percent": used_pct,
        "left_percent": left_pct,
        "cycle_elapsed_percent": round(cycle_elapsed_pct, 1),
        "cycle_elapsed_days": elapsed_days,
        "cycle_remaining_days": remaining_days,
        "reset_in": reset_in_str,
        "reset_formatted": reset_formatted,
        "resets": resets,
        "allowed": allowed,
        "limit_reached": limit_reached,
        "updated_at": now_ts,
        "updated_formatted": datetime.fromtimestamp(now_ts).strftime("%H:%M:%S"),
    }

    json.dumps(result, allow_nan=False)
    return result


def parse_retry_after(value):
    """Return finite nonnegative seconds, or None for an invalid header."""
    if not isinstance(value, str):
        return None
    value = value.strip()
    try:
        if value.isascii() and value.isdigit():
            seconds = int(value)
            return seconds if math.isfinite(seconds) else None
        dt = parsedate_to_datetime(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return max(0, math.ceil(dt.timestamp() - time.time()))
    except (ValueError, TypeError, OverflowError):
        return None


def failure(cached, status, message, retryable=False, retry_after=None):
    result = dict(cached) if cached else {"updated_at": None, "updated_formatted": None}
    result.update(status=status, error_message=message, cached=bool(cached),
                  has_data=bool(cached), retryable=retryable,
                  retry_after_seconds=retry_after, attempted_at=int(time.time()))
    return result


def request_json(url, headers, ctx, timeout):
    req = urllib.request.Request(url, headers=headers, method="GET")
    with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    json.dumps(data, allow_nan=False)
    return data


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
    cached = None
    try:
        cached = load_cache()
        result = fetch_result(cached)
    except urllib.error.HTTPError as e:
        retryable = e.code in (408, 429) or 500 <= e.code <= 599
        retry_after = parse_retry_after(e.headers.get("Retry-After")) if e.code == 429 and e.headers else None
        message = f"HTTP Error {e.code}"
        if e.code == 401:
            message = "Auth token expired. Please run 'codex login'."
        elif e.code == 403:
            message = "Access denied. Check your Codex account and log in again."
        status = "auth_expired" if e.code == 401 else "auth_error" if e.code == 403 else "error"
        result = failure(cached, status,
                         message, retryable, retry_after)
    except (http.client.IncompleteRead, ssl.SSLEOFError):
        result = failure(cached, "offline", "Network connection interrupted.", True)
    except (ssl.SSLError, ssl.CertificateError):
        result = failure(cached, "error", "TLS verification failed.")
    except urllib.error.URLError as e:
        permanent = (isinstance(e.reason, (ssl.SSLError, ssl.CertificateError))
                     and not isinstance(e.reason, ssl.SSLEOFError))
        result = failure(cached, "error" if permanent else "offline",
                         "TLS verification failed." if permanent else "Network unreachable.", not permanent)
    except (TimeoutError, ConnectionError, OSError):
        result = failure(cached, "offline", "Network unreachable or timed out.", True)
    except Exception:
        result = failure(cached, "error", "Invalid response or unexpected fetch failure.")
    print(json.dumps(result, allow_nan=False))

if __name__ == "__main__":
    fetch()
