import contextlib
import copy
import importlib.util
import io
import http.client
import json
from pathlib import Path
import ssl
import tempfile
import unittest
import urllib.error
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location(
    "fetch_usage", Path(__file__).resolve().parents[1] / "contents/scripts/fetch_usage.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

NOW = 1800000000
USAGE = {
    "plan_type": "Plus",
    "rate_limit": {
        "primary_window": {"used_percent": 25, "reset_after_seconds": 86400,
                           "reset_at": NOW + 86400, "limit_window_seconds": 604800},
        "allowed": True, "limit_reached": False,
    },
    "rate_limit_reset_credits": {"available_count": 2},
}


def response(data):
    resp = Mock()
    resp.__enter__ = Mock(return_value=resp)
    resp.__exit__ = Mock(return_value=False)
    resp.read.return_value = data if isinstance(data, bytes) else json.dumps(data).encode()
    return resp


def http_error(code, retry_after=None):
    headers = {} if retry_after is None else {"Retry-After": retry_after}
    return urllib.error.HTTPError(backend.USAGE_URL, code, "mock", headers, None)


class FetchUsageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.auth = Path(self.temp.name) / "auth.json"
        self.cache = Path(self.temp.name) / "cache.json"
        self.auth.write_text(json.dumps({"tokens": {"access_token": "mock-token"}}))
        for target, value in (("AUTH_FILE", str(self.auth)), ("CACHE_FILE", str(self.cache))):
            p = patch.object(backend, target, value)
            p.start()
            self.addCleanup(p.stop)
        self.clock = patch.object(backend.time, "time", return_value=NOW)
        self.clock.start()
        self.addCleanup(self.clock.stop)
        self.tls = patch.object(backend.ssl, "create_default_context", return_value=Mock())
        self.tls.start()
        self.addCleanup(self.tls.stop)
        self.network = patch.object(backend.urllib.request, "urlopen")
        self.urlopen = self.network.start()
        self.addCleanup(self.network.stop)
        self.urlopen.side_effect = AssertionError("Unconfigured mock request")

    def run_fetch(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            backend.fetch()
        text = stdout.getvalue()
        self.assertEqual(len(text.splitlines()), 1)
        def reject_constant(value):
            raise AssertionError(f"Nonfinite JSON: {value}")
        result = json.loads(text, parse_constant=reject_constant)
        json.dumps(result, allow_nan=False)
        self.assertIsInstance(result["retryable"], bool)
        self.assertIsInstance(result["has_data"], bool)
        self.assertEqual(result["attempted_at"], NOW)
        delay = result["retry_after_seconds"]
        self.assertTrue(delay is None or delay >= 0)
        return result

    def seed_cache(self):
        snapshot = backend.build_snapshot(copy.deepcopy(USAGE), [])
        snapshot.update(updated_at=NOW - 100, updated_formatted="old time",
                        future_snapshot_field={"nested": [1, 2, 3]})
        self.cache.write_text(json.dumps(snapshot))
        return snapshot

    def test_legacy_credit_id_is_normalized_without_losing_network_retry(self):
        snapshot = self.seed_cache()
        snapshot["resets"].append({"id": None, "label": "Credit", "kind": "credit",
                                  "countdown": "Available", "date": "--", "detail": "Credit token",
                                  "is_urgent": False, "remaining_seconds": float("inf")})
        self.cache.write_text(json.dumps(snapshot))
        self.urlopen.side_effect = TimeoutError()
        result = self.run_fetch()
        self.assertTrue(result["retryable"])
        self.assertTrue(result["has_data"])
        self.assertEqual(result["updated_at"], snapshot["updated_at"])
        self.assertIsInstance(result["resets"][-1]["id"], str)
        self.assertIsNone(result["resets"][-1]["remaining_seconds"])

    def test_invalid_cache_schema_does_not_poison_network_retry(self):
        for field, value in (("plan", None), ("updated_at", -1), ("used_percent", True),
                             ("allowed", "yes"), ("resets", [None]), ("cycle_elapsed_days", "old")):
            with self.subTest(field=field):
                snapshot = self.seed_cache()
                snapshot[field] = value
                self.cache.write_text(json.dumps(snapshot))
                self.urlopen.side_effect = TimeoutError()
                result = self.run_fetch()
                self.assertTrue(result["retryable"])
                self.assertFalse(result["has_data"])
                self.assertIsNone(result["updated_at"])

    def assert_preserved(self, result, snapshot):
        overrides = {"status", "error_message", "cached", "has_data", "retryable",
                     "retry_after_seconds", "attempted_at"}
        for key, value in snapshot.items():
            if key not in overrides:
                self.assertEqual(result[key], value, key)
        self.assertTrue(result["cached"])
        self.assertTrue(result["has_data"])
        self.assertEqual(json.loads(self.cache.read_text()), snapshot)

    def test_success_and_strict_json_credit_fallback(self):
        self.urlopen.side_effect = [response(USAGE), http_error(503)]
        result = self.run_fetch()
        self.assertEqual(result["status"], "ok")
        self.assertFalse(result["retryable"])
        self.assertFalse(result["cached"])
        self.assertTrue(result["has_data"])
        self.assertEqual(result["updated_at"], NOW)
        self.assertEqual(result["left_percent"], 75)
        self.assertEqual(len(result["resets"]), 3)
        self.assertIsNone(result["resets"][-1]["remaining_seconds"])
        self.assertEqual(json.loads(self.cache.read_text()), result)
        self.assertEqual(self.urlopen.call_count, 2)
        self.assertEqual([call.kwargs["timeout"] for call in self.urlopen.call_args_list], [10, 6])

    def test_optional_credit_failures_do_not_invalidate_quota(self):
        for credit in (TimeoutError(), response(b"bad json"), response({"credits": [None]}),
                       response({"credits": None}), response({"credits": [{"expires_at": "invalid"}]})):
            with self.subTest(credit=credit):
                self.urlopen.side_effect = [response(USAGE), credit]
                self.assertEqual(self.run_fetch()["status"], "ok")

    def test_http_classification_and_full_snapshot_preservation(self):
        snapshot = self.seed_cache()
        for code in (408, 429, 500, 502, 503, 599, 401, 403, 400, 404, 302):
            with self.subTest(code=code):
                self.urlopen.reset_mock()
                self.urlopen.side_effect = http_error(code, "60")
                result = self.run_fetch()
                self.assertEqual(result["retryable"], code in (408, 429) or 500 <= code <= 599)
                self.assertEqual(result["status"], "auth_expired" if code == 401 else "error")
                self.assertEqual(result["retry_after_seconds"], 60 if code == 429 else None)
                if code in (401, 403):
                    self.assertIn("log", result["error_message"])
                self.assertEqual(self.urlopen.call_count, 1)
                self.assert_preserved(result, snapshot)

    def test_malformed_optional_credit_ids_and_details_preserve_quota(self):
        for credit_id in (None, 42, True, [], {}, "valid"):
            with self.subTest(credit_id=credit_id):
                self.urlopen.side_effect = [response(USAGE), response({"credits": [
                    None, {"id": credit_id, "expires_at": {"invalid": "date"}},
                ]})]
                result = self.run_fetch()
                self.assertEqual(result["status"], "ok")
                self.assertEqual(result["left_percent"], 75)
                credit = next(item for item in result["resets"] if item["kind"] == "credit")
                self.assertIsInstance(credit["id"], str)
                self.assertEqual(json.loads(self.cache.read_text()), result)

    def test_malformed_optional_credit_fallback_preserves_quota(self):
        for summary in (None, [], "bad", {"available_count": None},
                        {"available_count": "2"}, {"available_count": 2.5},
                        {"available_count": True}, {"available_count": -1},
                        {"available_count": {}}):
            with self.subTest(summary=summary):
                usage = copy.deepcopy(USAGE)
                usage["rate_limit_reset_credits"] = summary
                self.urlopen.side_effect = [response(usage), http_error(503)]
                result = self.run_fetch()
                self.assertEqual(result["status"], "ok")
                self.assertEqual(result["left_percent"], 75)
                self.assertEqual(len(result["resets"]), 1)

    def test_network_timeout_tls_and_unexpected_errors(self):
        snapshot = self.seed_cache()
        for error, retryable in (
            (urllib.error.URLError("DNS unavailable"), True),
            (urllib.error.URLError(TimeoutError()), True),
            (TimeoutError(), True), (ConnectionResetError(), True),
            (http.client.IncompleteRead(b"partial", 10), True),
            (urllib.error.URLError(http.client.IncompleteRead(b"partial", 10)), True),
            (ssl.SSLEOFError("interrupted"), True),
            (urllib.error.URLError(ssl.SSLEOFError("interrupted")), True),
            (ssl.SSLError("TLS validation"), False),
            (urllib.error.URLError(ssl.SSLError("TLS validation")), False),
            (ssl.SSLCertVerificationError("certificate"), False),
            (urllib.error.URLError(ssl.SSLCertVerificationError("certificate")), False),
            (ValueError("parse failure"), False), (RuntimeError("unexpected"), False),
        ):
            with self.subTest(error=error):
                self.urlopen.side_effect = error
                result = self.run_fetch()
                self.assertEqual(result["retryable"], retryable)
                self.assertIsNone(result["retry_after_seconds"])
                self.assert_preserved(result, snapshot)

    def test_credentials_failures_preserve_cache_without_requests(self):
        snapshot = self.seed_cache()
        for text, status in ((None, "no_auth"), ("bad json", "auth_error"),
                             ('{"tokens": {}}', "no_token"), ('[]', "auth_error"),
                             ('{"tokens": null}', "auth_error")):
            with self.subTest(text=text):
                if text is None:
                    self.auth.unlink()
                else:
                    self.auth.write_text(text)
                result = self.run_fetch()
                self.assertEqual(result["status"], status)
                self.assertFalse(result["retryable"])
                self.assert_preserved(result, snapshot)
        self.urlopen.assert_not_called()

    def test_unreadable_auth(self):
        self.auth.unlink()
        self.auth.mkdir()
        result = self.run_fetch()
        self.assertEqual(result["status"], "auth_error")
        self.assertFalse(result["has_data"])
        self.urlopen.assert_not_called()

    def test_missing_corrupt_unreadable_cache_has_no_pretend_quota(self):
        for kind in ("missing", "corrupt", "unreadable", "nonfinite", "empty"):
            with self.subTest(kind=kind):
                if self.cache.is_dir():
                    self.cache.rmdir()
                elif self.cache.exists():
                    self.cache.unlink()
                if kind == "unreadable":
                    self.cache.mkdir()
                elif kind == "corrupt":
                    self.cache.write_text("bad json")
                elif kind == "nonfinite":
                    self.cache.write_text('{"left_percent": NaN, "used_percent": 0}')
                elif kind == "empty":
                    self.cache.write_text("{}")
                self.urlopen.side_effect = http_error(429)
                result = self.run_fetch()
                self.assertFalse(result["has_data"])
                self.assertFalse(result["cached"])
                self.assertNotIn("left_percent", result)
                self.assertNotIn("used_percent", result)
                self.assertIsNone(result["updated_at"])
                self.assertIsNone(result["updated_formatted"])

    def test_parsing_and_nonfinite_responses_are_permanent(self):
        for data in (b"not json", b"\xff", [], {},
                     {"rate_limit": {"primary_window": {"used_percent": float("nan")}}},
                     {"rate_limit": {"primary_window": {"used_percent": "25"}}}):
            with self.subTest(data=data):
                self.urlopen.side_effect = [response(data), response({"credits": []})]
                result = self.run_fetch()
                self.assertEqual(result["status"], "error")
                self.assertFalse(result["retryable"])
                self.assertFalse(result["has_data"])
                self.assertFalse(self.cache.exists())

    def test_retry_after_seconds_date_past_and_invalid(self):
        from email.utils import formatdate
        for header, expected in (("120", 120), (" 0 ", 0),
                                 (formatdate(NOW + 90, usegmt=True), 90),
                                 (formatdate(NOW - 90, usegmt=True), 0),
                                 ("-1", None), ("1.5", None), ("NaN", None),
                                 ("tomorrow", None), (None, None), ("", None)):
            with self.subTest(header=header):
                self.urlopen.side_effect = http_error(429, header)
                self.assertEqual(self.run_fetch()["retry_after_seconds"], expected)

    def test_zero_reset_and_credit_dates_emit_finite_json(self):
        usage = copy.deepcopy(USAGE)
        usage["rate_limit"]["primary_window"]["reset_after_seconds"] = 0
        self.urlopen.side_effect = [response(usage), response({"credits": [
            {"id": "expired", "expires_at": "2020-01-01T00:00:00Z"},
            {"id": "naive", "expires_at": "2099-01-01T00:00:00"},
            {"id": "unknown"},
        ]})]
        result = self.run_fetch()
        self.assertEqual(result["status"], "ok")
        self.assertEqual(len(result["resets"]), 4)

    def test_cache_write_failure_logs_only_stderr(self):
        self.cache.mkdir()
        self.urlopen.side_effect = [response(USAGE), response({"credits": []})]
        self.assertEqual(self.run_fetch()["status"], "ok")

    def test_unexpected_failure_is_json(self):
        with patch.object(backend, "load_cache", side_effect=RuntimeError("unexpected")):
            result = self.run_fetch()
        self.assertEqual(result["status"], "error")
        self.assertFalse(result["retryable"])
        self.assertFalse(result["has_data"])

    def test_legacy_infinite_countdowns_preserve_snapshot(self):
        snapshot = self.seed_cache()
        legacy = copy.deepcopy(snapshot)
        for reset in legacy["resets"]:
            if reset["remaining_seconds"] is None:
                reset["remaining_seconds"] = float("inf")
        self.cache.write_text(json.dumps(legacy))
        before = self.cache.read_text()
        self.urlopen.side_effect = http_error(503)
        result = self.run_fetch()
        for key, value in snapshot.items():
            if key not in {"status", "cached", "retryable", "attempted_at"}:
                self.assertEqual(result[key], value, key)
        self.assertTrue(result["has_data"])
        self.assertEqual(self.cache.read_text(), before)


if __name__ == "__main__":
    unittest.main()
