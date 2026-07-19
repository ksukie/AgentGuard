from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = (
    ROOT
    / "plugins"
    / "agent-policy"
    / "skills"
    / "agent-policy"
    / "scripts"
    / "check_update.py"
)
SPEC = importlib.util.spec_from_file_location("agent_policy_update_check", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Unable to load update checker")
UPDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATE)
UTC = timezone.utc


class UpdateSchedulerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.release_path = root / "release.json"
        self.state_path = root / "state" / "update-state.json"
        self.release_path.write_text(
            json.dumps(
                {
                    "version": "0.3.0",
                    "released_at": "2026-07-17T00:00:00Z",
                    "release_sequence": 3,
                    "summary": {
                        "zh-CN": "本地版本。",
                        "en": "Local release.",
                    },
                }
            ),
            encoding="utf-8",
        )

    @staticmethod
    def remote(version: str = "0.3.0", sequence: int = 3):
        return {
            "version": version,
            "released_at": "2026-07-20T00:00:00Z",
            "release_sequence": sequence,
            "summary": {
                "zh-CN": "远端版本。",
                "en": "Remote release.",
            },
        }

    def run_scheduler(self, now: datetime, fetcher):
        return UPDATE.run_scheduler(
            local_release_path=self.release_path,
            state_path=self.state_path,
            now=now,
            fetcher=fetcher,
        )

    def read_state(self):
        return json.loads(self.state_path.read_text(encoding="utf-8"))

    def test_first_use_waits_72_hours_without_fetching(self) -> None:
        def unexpected_fetch():
            self.fail("repository must not be queried before next_check_at")

        result = self.run_scheduler(
            datetime(2026, 7, 19, tzinfo=UTC), unexpected_fetch
        )
        self.assertEqual(result["status"], "not_due")
        self.assertEqual(self.read_state()["next_check_at"], "2026-07-20T00:00:00Z")

    def test_no_update_schedules_another_72_hours(self) -> None:
        checked_at = datetime(2026, 7, 20, tzinfo=UTC)
        result = self.run_scheduler(checked_at, self.remote)
        self.assertEqual(result["status"], "no_update")
        self.assertEqual(self.read_state()["next_check_at"], "2026-07-23T00:00:00Z")

    def test_update_notice_uses_a_fixed_36_hour_interval(self) -> None:
        checked_at = datetime(2026, 7, 20, tzinfo=UTC)
        first = self.run_scheduler(
            checked_at, lambda: self.remote("0.4.0", 4)
        )
        self.assertEqual(first["status"], "update_available")
        self.assertEqual(first["notice"]["reminder_count"], 1)
        self.assertEqual(first["notice"]["automatic_update_performed"], False)
        self.assertEqual(
            self.read_state()["next_check_at"], "2026-07-21T12:00:00Z"
        )

        second_at = checked_at + timedelta(hours=36)
        second = self.run_scheduler(
            second_at, lambda: self.remote("0.4.1", 5)
        )
        self.assertEqual(second["notice"]["reminder_count"], 2)
        self.assertEqual(
            self.read_state()["next_check_at"], "2026-07-23T00:00:00Z"
        )

    def test_failed_check_retries_silently_in_12_hours(self) -> None:
        def fail():
            raise OSError("offline")

        checked_at = datetime(2026, 7, 20, tzinfo=UTC)
        result = self.run_scheduler(checked_at, fail)
        self.assertEqual(result["status"], "check_failed")
        self.assertEqual(self.read_state()["next_check_at"], "2026-07-20T12:00:00Z")

    def test_invocation_and_skip_detection_are_explicit(self) -> None:
        self.assertTrue(UPDATE.is_explicit_invocation("@AgentPolicy 你能做什么"))
        self.assertTrue(UPDATE.is_explicit_invocation("Use $agent-policy to inspect this repo"))
        self.assertFalse(UPDATE.is_explicit_invocation("AgentPolicy sounds useful"))
        self.assertTrue(
            UPDATE.prompt_skips_update_check("@AgentPolicy 本次不要检查更新")
        )

    def test_plugin_data_is_the_only_plugin_state_override(self) -> None:
        plugin_data = str(Path(self.temporary.name) / "plugin-data")
        with patch.dict(
            UPDATE.os.environ,
            {
                "PLUGIN_DATA": plugin_data,
                "AGENT_POLICY_UPDATE_STATE_DIR": "ignored",
            },
        ):
            self.assertEqual(
                UPDATE.resolve_state_path(),
                Path(plugin_data) / UPDATE.STATE_FILE_NAME,
            )


if __name__ == "__main__":
    unittest.main()
