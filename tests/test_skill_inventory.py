from __future__ import annotations

import importlib.util
import json
import queue
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = (
    ROOT
    / "plugins"
    / "agent-tools"
    / "skills"
    / "agent-tools"
    / "scripts"
    / "list_skills.py"
)
SPEC = importlib.util.spec_from_file_location("agent_tools_skill_inventory", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Unable to load Skill inventory")
INVENTORY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INVENTORY)


class SkillInventoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_invocation_policy_defaults_true_and_honors_false(self) -> None:
        skill = self.root / "skill"
        skill.mkdir()
        self.assertEqual(
            INVENTORY.invocation_policy(skill),
            ("implicit_or_explicit", "default_true", None),
        )

        agents = skill / "agents"
        agents.mkdir()
        (agents / "openai.yaml").write_text(
            "policy:\n  allow_implicit_invocation: false\n",
            encoding="utf-8",
        )
        self.assertEqual(
            INVENTORY.invocation_policy(skill),
            ("explicit_only", "declared_false", None),
        )

    def test_invalid_invocation_policy_is_not_guessed(self) -> None:
        skill = self.root / "skill"
        agents = skill / "agents"
        agents.mkdir(parents=True)
        (agents / "openai.yaml").write_text(
            "policy:\n  allow_implicit_invocation: sometimes\n",
            encoding="utf-8",
        )
        activation, source, issue = INVENTORY.invocation_policy(skill)
        self.assertEqual(activation, "unknown")
        self.assertEqual(source, "invalid")
        self.assertIn("invalid allow_implicit_invocation", issue)

    def test_plugin_syntax_uses_runtime_namespace_once(self) -> None:
        self.assertEqual(
            INVENTORY.skill_syntax("demo:hello", "demo", "Demo"),
            ["$demo:hello", "@Demo"],
        )
        self.assertEqual(
            INVENTORY.skill_syntax("hello", "demo", "Demo"),
            ["$demo:hello", "@Demo"],
        )

    def test_build_inventory_enriches_all_runtime_skills(self) -> None:
        standalone = self.root / "standalone"
        (standalone / "agents").mkdir(parents=True)
        (standalone / "SKILL.md").write_text("---\nname: standalone\n---\n", encoding="utf-8")
        (standalone / "readme.md").write_text("# Standalone\n", encoding="utf-8")
        (standalone / "agents" / "openai.yaml").write_text(
            "policy:\n  allow_implicit_invocation: false\n",
            encoding="utf-8",
        )

        plugin = self.root / "plugin"
        skill = plugin / "skills" / "hello"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("---\nname: hello\n---\n", encoding="utf-8")
        (plugin / ".codex-plugin").mkdir()
        (plugin / ".codex-plugin" / "plugin.json").write_text(
            json.dumps(
                {
                    "name": "demo",
                    "interface": {"displayName": "Demo"},
                }
            ),
            encoding="utf-8",
        )
        (plugin / "README.md").write_text("# Demo\n", encoding="utf-8")

        catalog = {
            "data": [
                {
                    "cwd": str(self.root),
                    "errors": [],
                    "skills": [
                        {
                            "name": "standalone",
                            "description": "Standalone Skill.",
                            "enabled": True,
                            "path": str(standalone / "SKILL.md"),
                            "scope": "user",
                        },
                        {
                            "name": "demo:hello",
                            "description": "Plugin Skill.",
                            "enabled": False,
                            "interface": {"displayName": "Hello"},
                            "path": str(skill / "SKILL.md"),
                            "scope": "system",
                        },
                    ],
                }
            ]
        }
        result = INVENTORY.build_inventory(self.root, catalog)

        self.assertEqual(result["summary"]["total"], 2)
        self.assertEqual(result["summary"]["enabled"], 1)
        self.assertEqual(result["summary"]["disabled"], 1)
        self.assertEqual(result["summary"]["explicit_only"], 1)
        self.assertEqual(result["summary"]["implicit_or_explicit"], 1)
        by_name = {item["name"]: item for item in result["skills"]}
        self.assertEqual(by_name["standalone"]["syntax"], ["$standalone"])
        self.assertEqual(by_name["standalone"]["readme"], str(standalone / "readme.md"))
        self.assertEqual(
            by_name["demo:hello"]["syntax"],
            ["$demo:hello", "@Demo"],
        )
        self.assertEqual(by_name["demo:hello"]["readme"], str(plugin / "README.md"))

    def test_wait_for_response_ignores_notifications(self) -> None:
        messages = queue.Queue()
        messages.put({"method": "skills/changed", "params": {}})
        messages.put({"id": 2, "result": {"data": []}})
        response = INVENTORY.wait_for_response(messages, 2, 0.1)
        self.assertEqual(response["result"], {"data": []})

    def test_empty_runtime_catalog_is_an_error(self) -> None:
        with self.assertRaisesRegex(INVENTORY.InventoryError, "no Skill catalog"):
            INVENTORY.build_inventory(self.root, {"data": []})

    def test_non_object_plugin_manifest_is_reported(self) -> None:
        plugin = self.root / "plugin"
        skill = plugin / "skills" / "hello"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("---\nname: hello\n---\n", encoding="utf-8")
        (plugin / ".codex-plugin").mkdir()
        (plugin / ".codex-plugin" / "plugin.json").write_text(
            "[]\n",
            encoding="utf-8",
        )

        enriched = INVENTORY.enrich_skill(
            {
                "name": "hello",
                "description": "Plugin Skill.",
                "enabled": True,
                "path": str(skill / "SKILL.md"),
                "scope": "system",
            }
        )
        self.assertIn("plugin manifest is not an object", enriched["issues"][0])


if __name__ == "__main__":
    unittest.main()
