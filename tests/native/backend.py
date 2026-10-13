"""Synthetic executable-engine response; never reads auth or calls the network."""
import json
import time

time.sleep(0.2)  # Leave a real in-flight window for the native assertions.
print(json.dumps({
    "status": "no_auth", "retryable": False, "has_data": False,
    "cached": False, "attempted_at": time.time(), "retry_after_seconds": None,
    "updated_at": None, "updated_formatted": None,
    "error_message": "Synthetic unavailable",
}))
