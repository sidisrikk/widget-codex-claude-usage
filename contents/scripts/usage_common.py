"""
usage_common.py - Shared helpers for the Codex, Claude and Antigravity usage fetchers.
Stdlib only; each fetcher prints exactly one finite JSON object via run().
"""

import os
import sys
import json
import time
import tempfile
import urllib.request
import urllib.error
import ssl
import math
import http.client
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone


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


def number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)


# --- Windows snapshot contract (Claude and Antigravity): one quota/time pair per window ---

def valid_window(window):
    if not isinstance(window, dict):
        return False
    if not all(isinstance(window.get(key), str) for key in
               ("id", "label", "reset_in", "reset_formatted", "time_left_text")):
        return False
    if not all(number(window.get(key)) for key in
               ("used_percent", "left_percent", "window_seconds", "time_left_percent")):
        return False
    if not all(0 <= window[key] <= 100 for key in ("used_percent", "left_percent", "time_left_percent")):
        return False
    if not isinstance(window.get("limit_reached"), bool) or "remaining_seconds" not in window:
        return False
    return window["remaining_seconds"] is None or number(window["remaining_seconds"])


def valid_windows_snapshot(data):
    """Match the frontend windows snapshot contract before attaching cached quota."""
    if (not isinstance(data, dict) or data.get("has_data") is not True
            or not isinstance(data.get("windows"), list) or not data["windows"]):
        return False
    if not all(isinstance(data.get(key), str) for key in ("plan", "updated_formatted")):
        return False
    if not all(number(data.get(key)) for key in ("used_percent", "left_percent", "updated_at")):
        return False
    if not all(0 <= data[key] <= 100 for key in ("used_percent", "left_percent")):
        return False
    if data["updated_at"] < 0 or not isinstance(data.get("limit_reached"), bool):
        return False
    return all(valid_window(window) for window in data["windows"])


def format_time_left(seconds):
    if seconds >= 86400:
        return f"{round(seconds / 86400.0, 1)}d left"
    if seconds >= 3600:
        return f"{round(seconds / 3600.0, 1)}h left"
    return f"{max(1, math.ceil(seconds / 60.0))}m left"


def window_entry(window_id, label, window_seconds, used, reset_dt, now_utc, limit_reached=False):
    """One quota/time pair; reset_dt=None means the window has not started (no countdown)."""
    used = min(100.0, max(0.0, float(used)))
    left = int(max(0, min(100, round(100 - used))))
    reset_in, reset_formatted, time_left_text = "Not started", "--", "—"
    remaining, time_left_pct = None, 0.0
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
        "limit_reached": used >= 100 or bool(limit_reached),
    }


def windows_snapshot(windows, plan, now_ts):
    """Top-level windows snapshot; the binding (lowest) window drives the gauge."""
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


def write_json_atomic(path, data):
    """Write a cache file via fsynced temporary file and atomic replace; warn on stderr."""
    temporary_path = None
    try:
        cache_directory = os.path.dirname(path) or "."
        os.makedirs(cache_directory, exist_ok=True)
        with tempfile.NamedTemporaryFile(
                "w", encoding="utf-8", dir=cache_directory,
                prefix=f".{os.path.basename(path)}.", suffix=".tmp",
                delete=False) as f:
            temporary_path = f.name
            json.dump(data, f, indent=2, allow_nan=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
    except Exception as e:
        if temporary_path is not None:
            try:
                os.unlink(temporary_path)
            except OSError:
                pass
        sys.stderr.write(f"Warning: Failed to write cache: {e}\n")


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


def run(load_cache, fetch_result, expired_message, denied_message):
    """Classify failures and print one JSON result for the frontend."""
    cached = None
    try:
        cached = load_cache()
        result = fetch_result(cached)
    except urllib.error.HTTPError as e:
        retryable = e.code in (408, 429) or 500 <= e.code <= 599
        retry_after = parse_retry_after(e.headers.get("Retry-After")) if e.code == 429 and e.headers else None
        message = f"HTTP Error {e.code}"
        if e.code == 401:
            message = expired_message
        elif e.code == 403:
            message = denied_message
        status = "auth_expired" if e.code == 401 else "auth_error" if e.code == 403 else "error"
        result = failure(cached, status, message, retryable, retry_after)
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
