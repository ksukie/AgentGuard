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
    / "agent-tools"
    / "skills"
    / "agent-tools"
    / "scripts"
    / "check_update.py"
)
SKILL_PATH = SCRIPT_PATH.parent.parent / "SKILL.md"
OPENAI_YAML_PATH = (
    ROOT
    / "plugins"
    / "agent-tools"
    / "skills"
    / "agent-tools"
    / "agents"
    / "openai.yaml"
)
HOOK_PATH = ROOT / "plugins" / "agent-tools" / "hooks" / "hooks.json"
PLUGIN_MANIFEST_PATH = ROOT / "plugins" / "agent-tools" / ".codex-plugin" / "plugin.json"
MARKETPLACE_PATH = ROOT / ".agents" / "plugins" / "marketplace.json"
RELEASE_PATH = SCRIPT_PATH.parent.parent / "release.json"
SPEC = importlib.util.spec_from_file_location("agent_tools_update_check", SCRIPT_PATH)
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

    def test_plugin_is_dormant_until_explicit_invocation(self) -> None:
        self.assertFalse(HOOK_PATH.exists())
        metadata = OPENAI_YAML_PATH.read_text(encoding="utf-8")
        self.assertIn("allow_implicit_invocation: false", metadata)

    def test_public_identity_is_agent_tools(self) -> None:
        manifest = json.loads(PLUGIN_MANIFEST_PATH.read_text(encoding="utf-8"))
        marketplace = json.loads(MARKETPLACE_PATH.read_text(encoding="utf-8"))
        release = json.loads(RELEASE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(manifest["name"], "agent-tools")
        self.assertEqual(manifest["interface"]["displayName"], "AgentTools")
        self.assertEqual(manifest["version"], release["version"])
        self.assertEqual(marketplace["name"], "agenttools")
        self.assertEqual(marketplace["plugins"][0]["name"], "agent-tools")
        self.assertEqual(
            marketplace["plugins"][0]["source"]["path"],
            "./plugins/agent-tools",
        )

    def test_legacy_update_disable_variable_remains_supported(self) -> None:
        with patch.dict(
            UPDATE.os.environ,
            {"AGENT_POLICY_UPDATE_CHECK": "0"},
            clear=True,
        ):
            self.assertTrue(UPDATE.update_checks_disabled())
        with patch.dict(
            UPDATE.os.environ,
            {
                "AGENT_TOOLS_UPDATE_CHECK": "1",
                "AGENT_POLICY_UPDATE_CHECK": "0",
            },
            clear=True,
        ):
            self.assertFalse(UPDATE.update_checks_disabled())

    def test_menu_has_exactly_four_public_capabilities(self) -> None:
        skill = SKILL_PATH.read_text(encoding="utf-8")
        catalog = skill.split("```text", 1)[1].split("```", 1)[0]
        numbered = [
            line.strip()
            for line in catalog.splitlines()
            if len(line.strip()) > 2
            and line.strip()[0].isdigit()
            and line.strip()[1:3] == ". "
        ]
        self.assertEqual(
            [line[:2] for line in numbered],
            ["1.", "2.", "3.", "4."],
        )
        self.assertIn("Agent/Codex 诊断", catalog)
        self.assertIn("AGENTS.md 策略模板", catalog)
        self.assertIn("任务上下文梳理与续接", catalog)
        self.assertIn("Codex Skill 清单与调用审计", catalog)
        fourth = catalog.split("4. Codex Skill 清单与调用审计", 1)[1]
        self.assertEqual(fourth.count("用法："), 1)

    def test_skill_inventory_uses_one_intent_route_not_one_exact_phrase(self) -> None:
        skill = SKILL_PATH.read_text(encoding="utf-8")
        workflow = skill.split("## List current Codex Skills", 1)[1]
        self.assertIn("Use this single workflow for any explicitly invoked request", workflow)
        self.assertIn("not an exact-match command", workflow)
        self.assertIn("Always start from `<skill-root>/scripts/list_skills.py`", workflow)

    def test_plugin_data_is_the_only_plugin_state_override(self) -> None:
        plugin_data = str(Path(self.temporary.name) / "plugin-data")
        with patch.dict(
            UPDATE.os.environ,
            {
                "PLUGIN_DATA": plugin_data,
                "AGENT_TOOLS_UPDATE_STATE_DIR": "ignored",
            },
        ):
            self.assertEqual(
                UPDATE.resolve_state_path(),
                Path(plugin_data) / UPDATE.STATE_FILE_NAME,
            )


if __name__ == "__main__":
    unittest.main()
