"""
usage_common.py - Shared helpers for the Codex and Claude usage fetchers.
Stdlib only; each fetcher prints exactly one finite JSON object via run().
"""

import json
import time
import urllib.request
import urllib.error
import ssl
import math
import http.client
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone


def format_relative_time(seconds):
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
        result = failure(cached, "auth_expired" if e.code == 401 else "error",
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
