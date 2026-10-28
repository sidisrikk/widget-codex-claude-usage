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
import urllib.request
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location(
    "fetch_claude_usage", Path(__file__).resolve().parents[1] / "contents/scripts/fetch_claude_usage.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

# 2027-01-15T08:00:00Z: the session resets in 2h, the weekly window in 3d.
NOW = 1800000000
USAGE = {
    "five_hour": {"utilization": 64.0, "resets_at": "2027-01-15T10:00:00+00:00", "locked_reason": None},
    "seven_day": {"utilization": 18.4, "resets_at": "2027-01-18T08:00:00.123456+00:00"},
    "seven_day_oauth_apps": None,
    "seven_day_opus": None,
    "seven_day_sonnet": None,
    "extra_usage": {"is_enabled": False, "utilization": None},
    "limits": [{"kind": "session", "percent": 64}],
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


def credentials(**overrides):
    oauth = {"accessToken": "mock-token", "refreshToken": "mock-refresh",
             "expiresAt": (NOW + 3600) * 1000, "subscriptionType": "pro"}
    oauth.update(overrides)
    return json.dumps({"claudeAiOauth": oauth})


class FetchClaudeUsageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.auth = Path(self.temp.name) / ".credentials.json"
        self.cache = Path(self.temp.name) / "cache.json"
        self.auth.write_text(credentials())
        for target, value in (("AUTH_FILE", str(self.auth)), ("CACHE_FILE", str(self.cache))):
            p = patch.object(backend, target, value)
            p.start()
            self.addCleanup(p.stop)
        self.clock = patch.object(backend.time, "time", return_value=NOW)
        self.clock.start()
        self.addCleanup(self.clock.stop)
        now_dt = backend.datetime.fromtimestamp(NOW, tz=backend.timezone.utc)
        fixed = Mock(wraps=backend.datetime)
        fixed.now = Mock(return_value=now_dt)
        self.dates = patch.object(backend, "datetime", fixed)
        self.dates.start()
        self.addCleanup(self.dates.stop)
        self.tls = patch.object(backend.ssl, "create_default_context", return_value=Mock())
        self.tls.start()
        self.addCleanup(self.tls.stop)
        self.network = patch.object(urllib.request, "urlopen")
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
        return result

    def seed_cache(self):
        snapshot = backend.build_snapshot(copy.deepcopy(USAGE), "Pro")
        snapshot.update(updated_at=NOW - 100, updated_formatted="old time")
        self.cache.write_text(json.dumps(snapshot))
        return snapshot

    def assert_preserved(self, result, snapshot):
        overrides = {"status", "error_message", "cached", "has_data", "retryable",
                     "retry_after_seconds", "attempted_at"}
        for key, value in snapshot.items():
            if key not in overrides:
                self.assertEqual(result[key], value, key)
        self.assertTrue(result["cached"])
        self.assertTrue(result["has_data"])

    def test_success_maps_each_window_and_binding_limit(self):
        self.urlopen.side_effect = [response(USAGE)]
        result = self.run_fetch()
        self.assertEqual(result["status"], "ok")
        self.assertFalse(result["cached"])
        self.assertEqual(result["plan"], "Pro")
        self.assertEqual(result["updated_at"], NOW)
        self.assertEqual([w["id"] for w in result["windows"]], ["session", "weekly"])
        session, weekly = result["windows"]
        self.assertEqual((session["left_percent"], session["used_percent"]), (36, 64.0))
        self.assertEqual(session["remaining_seconds"], 7200)
        self.assertEqual(session["reset_in"], "2h 0m")
        self.assertEqual(session["time_left_percent"], 40.0)
        self.assertEqual(session["time_left_text"], "2.0h left")
        self.assertEqual(weekly["left_percent"], 82)
        self.assertEqual(weekly["remaining_seconds"], 3 * 86400)
        self.assertEqual(weekly["time_left_text"], "3.0d left")
        self.assertEqual(result["left_percent"], 36)
        self.assertEqual(result["used_percent"], 64.0)
        self.assertFalse(result["limit_reached"])
        self.assertTrue(backend.valid_cached_snapshot(result))
        self.assertEqual(json.loads(self.cache.read_text()), result)
        request = self.urlopen.call_args.args[0]
        self.assertEqual(request.full_url, backend.USAGE_URL)
        self.assertEqual(request.get_header("Authorization"), "Bearer mock-token")
        self.assertEqual(request.get_header("Anthropic-beta"), "oauth-2025-04-20")
        self.assertEqual(self.urlopen.call_args.kwargs["timeout"], 10)

    def test_optional_model_windows_unstarted_and_limits(self):
        usage = copy.deepcopy(USAGE)
        usage["five_hour"] = {"utilization": 0.0, "resets_at": None}
        usage["seven_day_sonnet"] = {"utilization": 100, "resets_at": "2027-01-18T08:00:00Z"}
        usage["seven_day_opus"] = {"utilization": 12, "resets_at": "2020-01-01T00:00:00Z",
                                   "locked_reason": "policy"}
        usage["seven_day_cowork"] = {"utilization": 99}
        self.urlopen.side_effect = [response(usage)]
        result = self.run_fetch()
        self.assertEqual([w["id"] for w in result["windows"]],
                         ["session", "weekly", "weekly_sonnet", "weekly_opus"])
        session, _, sonnet, opus = result["windows"]
        self.assertEqual((session["reset_in"], session["reset_formatted"]), ("Not started", "--"))
        self.assertIsNone(session["remaining_seconds"])
        self.assertEqual((session["time_left_percent"], session["time_left_text"]), (0.0, "—"))
        self.assertTrue(sonnet["limit_reached"])
        self.assertEqual(sonnet["left_percent"], 0)
        self.assertTrue(opus["limit_reached"])
        self.assertEqual(opus["reset_in"], "now")
        self.assertIsNone(opus["remaining_seconds"])
        self.assertEqual(result["left_percent"], 0)
        self.assertTrue(result["limit_reached"])

    def test_malformed_windows_are_ignored_or_permanent(self):
        for usage, ok in (
            ({**USAGE, "seven_day_opus": {"utilization": "5"}}, True),
            ({**USAGE, "seven_day_sonnet": {"utilization": True}}, True),
            ({**USAGE, "five_hour": {"utilization": float("nan")}}, False),  # Nonfinite JSON is rejected.
            ({**USAGE, "five_hour": {"utilization": 5, "resets_at": {"bad": 1}}}, True),
            ({**USAGE, "five_hour": {"utilization": 5, "resets_at": "garbage"}}, True),
            ({"five_hour": None, "seven_day": None, "seven_day_opus": {"utilization": 3}}, False),
            ({}, False), ([], False), (b"not json", False),
        ):
            with self.subTest(usage=usage):
                if self.cache.exists():
                    self.cache.unlink()
                self.urlopen.side_effect = [response(usage)]
                result = self.run_fetch()
                self.assertEqual(result["status"], "ok" if ok else "error")
                self.assertFalse(result["retryable"])
                self.assertEqual(self.cache.exists(), ok)
                if ok:
                    self.assertTrue(backend.valid_cached_snapshot(result))

    def test_expired_token_is_reported_without_requests_or_refresh(self):
        snapshot = self.seed_cache()
        before = self.auth.read_text()
        for expires in (NOW * 1000, (NOW - 60) * 1000):
            with self.subTest(expires=expires):
                self.auth.write_text(credentials(expiresAt=expires))
                result = self.run_fetch()
                self.assertEqual(result["status"], "auth_expired")
                self.assertIn("Open Claude Code", result["error_message"])
                self.assertFalse(result["retryable"])
                self.assert_preserved(result, snapshot)
        self.urlopen.assert_not_called()
        self.auth.write_text(before)
        self.urlopen.side_effect = [response(USAGE)]
        self.assertEqual(self.run_fetch()["status"], "ok")
        self.assertEqual(self.auth.read_text(), before)

    def test_missing_expiry_still_requests(self):
        for expires in (None, "soon", True):
            with self.subTest(expires=expires):
                self.auth.write_text(credentials(expiresAt=expires))
                self.urlopen.side_effect = [response(USAGE)]
                self.assertEqual(self.run_fetch()["status"], "ok")

    def test_credentials_failures_preserve_cache_without_requests(self):
        snapshot = self.seed_cache()
        for text, status in ((None, "no_auth"), ("bad json", "auth_error"), ("[]", "auth_error"),
                             ('{"claudeAiOauth": null}', "auth_error"), ("{}", "no_token"),
                             ('{"claudeAiOauth": {}}', "no_token"),
                             ('{"claudeAiOauth": {"accessToken": 42}}', "auth_error")):
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

    def test_credentials_file_is_only_read(self):
        real_open = open
        modes = []
        def tracking_open(path, mode="r", *args, **kwargs):
            if str(path) == str(self.auth):
                modes.append(mode)
            return real_open(path, mode, *args, **kwargs)
        self.urlopen.side_effect = [response(USAGE), http_error(401)]
        with patch("builtins.open", side_effect=tracking_open):
            self.run_fetch()
            self.run_fetch()
        self.assertEqual(modes, ["r", "r"])

    def test_http_classification_and_snapshot_preservation(self):
        snapshot = self.seed_cache()
        for code in (408, 429, 500, 503, 529, 401, 403, 400, 404):
            with self.subTest(code=code):
                self.urlopen.reset_mock()
                self.urlopen.side_effect = http_error(code, "60")
                result = self.run_fetch()
                self.assertEqual(result["retryable"], code in (408, 429) or 500 <= code <= 599)
                self.assertEqual(result["status"], "auth_expired" if code == 401 else "error")
                self.assertEqual(result["retry_after_seconds"], 60 if code == 429 else None)
                if code in (401, 403):
                    self.assertIn("Claude Code", result["error_message"])
                self.assertEqual(self.urlopen.call_count, 1)
                self.assert_preserved(result, snapshot)
                self.assertEqual(json.loads(self.cache.read_text()), snapshot)

    def test_network_and_tls_failures(self):
        snapshot = self.seed_cache()
        for error, status, retryable in (
            (urllib.error.URLError("DNS unavailable"), "offline", True),
            (TimeoutError(), "offline", True),
            (http.client.IncompleteRead(b"partial", 10), "offline", True),
            (ssl.SSLEOFError("interrupted"), "offline", True),
            (urllib.error.URLError(ssl.SSLCertVerificationError("certificate")), "error", False),
            (RuntimeError("unexpected"), "error", False),
        ):
            with self.subTest(error=error):
                self.urlopen.side_effect = error
                result = self.run_fetch()
                self.assertEqual((result["status"], result["retryable"]), (status, retryable))
                self.assert_preserved(result, snapshot)

    def test_invalid_or_missing_cache_has_no_pretend_quota(self):
        for content in (None, "bad json", "{}", '{"left_percent": NaN}',
                        json.dumps({**backend.build_snapshot(USAGE, "Pro"), "windows": []}),
                        json.dumps({**backend.build_snapshot(USAGE, "Pro"), "windows": [{"id": "x"}]})):
            with self.subTest(content=content):
                if self.cache.exists():
                    self.cache.unlink()
                if content is not None:
                    self.cache.write_text(content)
                self.urlopen.side_effect = http_error(503)
                result = self.run_fetch()
                self.assertFalse(result["has_data"])
                self.assertFalse(result["cached"])
                self.assertNotIn("windows", result)
                self.assertIsNone(result["updated_at"])

    def test_cache_write_failure_still_reports_success(self):
        self.cache.mkdir()
        self.urlopen.side_effect = [response(USAGE)]
        self.assertEqual(self.run_fetch()["status"], "ok")


if __name__ == "__main__":
    unittest.main()
