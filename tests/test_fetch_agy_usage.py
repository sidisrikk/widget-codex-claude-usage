import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    "fetch_agy_usage", Path(__file__).resolve().parents[1] / "contents/scripts/fetch_agy_usage.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

NOW = 1800000000
SAMPLE_GROUPS = [
    {
        "name": "Gemini Models",
        "buckets": [
            {
                "id": "gemini-weekly",
                "name": "Weekly Limit Remaining",
                "window": "weekly",
                "remaining_fraction": 0.85,
                "reset_time": "2027-01-20T08:00:00Z"
            },
            {
                "id": "gemini-5h",
                "name": "Five Hour Limit Remaining",
                "window": "5h",
                "remaining_fraction": 0.60,
                "reset_time": "2027-01-15T11:00:00Z"
            }
        ]
    },
    {
        "name": "Claude and GPT models",
        "buckets": [
            {
                "id": "3p-weekly",
                "remaining_fraction": 0.50,
                "reset_time": "2027-01-22T08:00:00Z"
            },
            {
                "id": "3p-5h",
                "remaining_fraction": 0.40,
                "reset_time": "2027-01-15T12:00:00Z"
            }
        ]
    },
    {
        "name": "Gemini 4 Argon",
        "buckets": [
            {
                "id": "gemini-argon-wtu-weekly",
                "name": "Gemini 4 Argon Weekly Limit",
                "window": "weekly",
                "remaining_fraction": 0.95,
                "reset_time": "2027-01-19T08:00:00Z"
            }
        ]
    }
]


def completed_process(returncode=0, stdout=None, stderr=""):
    data = {"status": "SUCCESS", "command": {"name": "usage", "data": {"groups": stdout if stdout is not None else SAMPLE_GROUPS}}}
    return subprocess.CompletedProcess(
        args=["agy", "-p", "/usage", "--output-format", "json"],
        returncode=returncode,
        stdout=json.dumps(data) if isinstance(stdout, list) or stdout is None else stdout,
        stderr=stderr
    )


class FetchAgyUsageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cache = Path(self.temp.name) / "cache.json"
        p = patch.object(backend, "CACHE_FILE", str(self.cache))
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

        self.which = patch.object(backend.shutil, "which", return_value="/usr/bin/agy")
        self.mock_which = self.which.start()
        self.addCleanup(self.which.stop)

        self.subproc = patch.object(backend.subprocess, "run")
        self.run_proc = self.subproc.start()
        self.addCleanup(self.subproc.stop)
        self.run_proc.side_effect = AssertionError("Unconfigured mock subprocess")

    def run_fetch(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            backend.fetch()
        text = stdout.getvalue()
        self.assertEqual(len(text.splitlines()), 1)
        result = json.loads(text)
        json.dumps(result, allow_nan=False)
        self.assertIsInstance(result["retryable"], bool)
        self.assertIsInstance(result["has_data"], bool)
        self.assertEqual(result["attempted_at"], NOW)
        return result

    def seed_cache(self):
        snapshot = backend.build_snapshot(copy.deepcopy(SAMPLE_GROUPS))
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

    def test_success_extracts_gemini_and_argon_and_ignores_3p(self):
        self.run_proc.side_effect = [completed_process()]
        result = self.run_fetch()
        self.assertEqual(result["status"], "ok")
        self.assertFalse(result["cached"])
        self.assertEqual(result["plan"], "Antigravity")
        self.assertEqual(result["updated_at"], NOW)
        
        # Only 3 windows, strictly in order: Gemini 5h, Gemini Weekly, Argon Weekly
        self.assertEqual([w["id"] for w in result["windows"]], ["gemini_5h", "gemini_weekly", "argon_weekly"])
        gemini_5h, gemini_weekly, argon = result["windows"]

        # Gemini 5h: remaining 0.60 -> 60% left, 40% used
        self.assertEqual((gemini_5h["left_percent"], gemini_5h["used_percent"]), (60, 40.0))
        self.assertEqual(gemini_5h["window_seconds"], 5 * 3600)
        self.assertEqual(gemini_5h["remaining_seconds"], 10800) # 3 hours
        self.assertEqual(gemini_5h["time_left_text"], "3.0h left")
        self.assertFalse(gemini_5h["limit_reached"])

        # Gemini weekly: remaining 0.85 -> 85% left, 15% used
        self.assertEqual((gemini_weekly["left_percent"], gemini_weekly["used_percent"]), (85, 15.0))
        self.assertEqual(gemini_weekly["window_seconds"], 7 * 86400)
        self.assertEqual(gemini_weekly["remaining_seconds"], 5 * 86400) # 5 days
        self.assertEqual(gemini_weekly["time_left_text"], "5.0d left")

        # Argon: remaining 0.95 -> 95% left, 5% used
        self.assertEqual((argon["left_percent"], argon["used_percent"]), (95, 5.0))
        self.assertEqual(argon["window_seconds"], 7 * 86400)

        # Top-level: lowest left_percent (60%), highest used_percent (40.0%)
        self.assertEqual(result["left_percent"], 60)
        self.assertEqual(result["used_percent"], 40.0)
        self.assertFalse(result["limit_reached"])
        self.assertTrue(backend.valid_windows_snapshot(result))
        self.assertEqual(json.loads(self.cache.read_text()), result)

        call_args, call_kwargs = self.run_proc.call_args
        self.assertEqual(call_args[0], ["/usr/bin/agy", "-p", "/usage", "--output-format", "json"])
        self.assertEqual(call_kwargs["stdin"], subprocess.DEVNULL)
        self.assertEqual(call_kwargs["timeout"], backend.TIMEOUT_SECONDS)

    def test_full_bucket_reports_not_started(self):
        groups = copy.deepcopy(SAMPLE_GROUPS)
        groups[0]["buckets"][1]["remaining_fraction"] = 1.0
        self.run_proc.side_effect = [completed_process(stdout=groups)]
        result = self.run_fetch()
        gemini_5h = result["windows"][0]
        self.assertEqual(gemini_5h["left_percent"], 100)
        self.assertEqual(gemini_5h["used_percent"], 0.0)
        self.assertEqual(gemini_5h["reset_in"], "Not started")
        self.assertEqual(gemini_5h["reset_formatted"], "--")
        self.assertIsNone(gemini_5h["remaining_seconds"])
        self.assertEqual(gemini_5h["time_left_text"], "—")

    def test_exhausted_bucket_reports_limit_reached(self):
        groups = copy.deepcopy(SAMPLE_GROUPS)
        groups[0]["buckets"][1]["remaining_fraction"] = 0.0
        self.run_proc.side_effect = [completed_process(stdout=groups)]
        result = self.run_fetch()
        gemini_5h = result["windows"][0]
        self.assertEqual(gemini_5h["left_percent"], 0)
        self.assertEqual(gemini_5h["used_percent"], 100.0)
        self.assertTrue(gemini_5h["limit_reached"])
        self.assertTrue(result["limit_reached"])
        self.assertEqual(result["left_percent"], 0)

    def test_argon_optional_when_missing(self):
        groups = [SAMPLE_GROUPS[0], SAMPLE_GROUPS[1]] # no Argon
        self.run_proc.side_effect = [completed_process(stdout=groups)]
        result = self.run_fetch()
        self.assertEqual(result["status"], "ok")
        self.assertEqual([w["id"] for w in result["windows"]], ["gemini_5h", "gemini_weekly"])

    def test_missing_gemini_buckets_fails(self):
        groups = [SAMPLE_GROUPS[1], SAMPLE_GROUPS[2]] # only 3p and Argon
        self.run_proc.side_effect = [completed_process(stdout=groups)]
        result = self.run_fetch()
        self.assertEqual(result["status"], "error")
        self.assertFalse(result["retryable"])

    def test_agy_cli_missing(self):
        self.mock_which.return_value = None
        with patch.object(backend.os, "access", return_value=False):
            result = self.run_fetch()
        self.assertEqual(result["status"], "error")
        self.assertIn("not found", result["error_message"])
        self.assertFalse(result["retryable"])

    def test_timeout_reports_offline(self):
        snapshot = self.seed_cache()
        self.run_proc.side_effect = subprocess.TimeoutExpired(cmd=["agy"], timeout=30)
        result = self.run_fetch()
        self.assertEqual(result["status"], "offline")
        self.assertTrue(result["retryable"])
        self.assert_preserved(result, snapshot)

    def test_nonzero_exit_and_auth_detection(self):
        snapshot = self.seed_cache()
        # Normal error
        self.run_proc.side_effect = [completed_process(returncode=1, stderr="Network failure reaching service\nSecond line")]
        result = self.run_fetch()
        self.assertEqual(result["status"], "error")
        self.assertTrue(result["retryable"])
        self.assertEqual(result["error_message"], "Network failure reaching service")
        self.assert_preserved(result, snapshot)

        # Auth error
        self.run_proc.side_effect = [completed_process(returncode=1, stderr="Please log in with 'agy' to proceed")]
        result = self.run_fetch()
        self.assertEqual(result["status"], "no_auth")
        self.assertFalse(result["retryable"])
        self.assertIn("sign-in required", result["error_message"].lower())
        self.assert_preserved(result, snapshot)

    def test_invalid_json_output(self):
        for bad in ("not json", "{}", json.dumps({"command": {"name": "other"}}),
                    json.dumps({"command": {"name": "usage", "data": {"groups": "bad"}}})):
            with self.subTest(bad=bad):
                self.run_proc.side_effect = [completed_process(returncode=0, stdout=bad)]
                result = self.run_fetch()
                self.assertEqual(result["status"], "error")
                self.assertFalse(result["retryable"])

    def test_cache_write_failure_still_succeeds(self):
        self.cache.mkdir()
        self.run_proc.side_effect = [completed_process()]
        result = self.run_fetch()
        self.assertEqual(result["status"], "ok")


if __name__ == "__main__":
    unittest.main()
