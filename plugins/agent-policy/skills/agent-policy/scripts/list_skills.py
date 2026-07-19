#!/usr/bin/env python3
"""List the Skills the current Codex runtime discovers for one working directory."""

from __future__ import annotations

import argparse
import json
import os
import queue
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Optional


CLIENT_NAME = "agent_policy_skill_inventory"
CLIENT_VERSION = "0.5.0"
REQUEST_TIMEOUT_SECONDS = 15
MAX_METADATA_BYTES = 1024 * 1024
SCOPE_ORDER = {"repo": 0, "user": 1, "admin": 2, "system": 3}


class InventoryError(RuntimeError):
    """Raised when a complete Codex Skill inventory cannot be produced."""


def read_utf8(path: Path) -> str:
    try:
        payload = path.read_bytes()
    except OSError as exc:
        raise InventoryError(f"unable to read metadata: {path}") from exc
    if len(payload) > MAX_METADATA_BYTES:
        raise InventoryError(f"metadata file is too large: {path}")
    try:
        return payload.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise InventoryError(f"metadata is not valid UTF-8: {path}") from exc


def invocation_policy(skill_dir: Path) -> tuple[str, str, Optional[str]]:
    metadata_path = skill_dir / "agents" / "openai.yaml"
    if not metadata_path.is_file():
        return "implicit_or_explicit", "default_true", None

    try:
        text = read_utf8(metadata_path)
    except InventoryError as exc:
        return "unknown", "invalid", str(exc)

    policy_indent: Optional[int] = None
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if policy_indent is None:
            if indent == 0 and stripped.startswith("policy:"):
                inline = stripped[len("policy:") :].strip()
                if inline:
                    marker = "allow_implicit_invocation:"
                    if marker in inline:
                        value = inline.split(marker, 1)[1].strip().rstrip("}").strip()
                        return parse_policy_value(value, metadata_path)
                policy_indent = indent
            continue
        if indent <= policy_indent:
            break
        if stripped.startswith("allow_implicit_invocation:"):
            value = stripped.split(":", 1)[1].split("#", 1)[0].strip()
            return parse_policy_value(value, metadata_path)

    return "implicit_or_explicit", "default_true", None


def parse_policy_value(
    value: str, metadata_path: Path
) -> tuple[str, str, Optional[str]]:
    normalized = value.lower()
    if normalized == "false":
        return "explicit_only", "declared_false", None
    if normalized == "true":
        return "implicit_or_explicit", "declared_true", None
    return (
        "unknown",
        "invalid",
        f"invalid allow_implicit_invocation value in {metadata_path}",
    )


def find_plugin_root(skill_dir: Path) -> Optional[Path]:
    for candidate in (skill_dir, *skill_dir.parents):
        if (candidate / ".codex-plugin" / "plugin.json").is_file():
            return candidate
    return None


def load_plugin_identity(
    plugin_root: Optional[Path],
) -> tuple[Optional[str], Optional[str], Optional[str]]:
    if plugin_root is None:
        return None, None, None
    manifest_path = plugin_root / ".codex-plugin" / "plugin.json"
    try:
        manifest = json.loads(read_utf8(manifest_path))
        if not isinstance(manifest, dict):
            raise InventoryError(f"plugin manifest is not an object: {manifest_path}")
        name = manifest.get("name")
        interface = manifest.get("interface")
        display_name = (
            interface.get("displayName") if isinstance(interface, dict) else None
        )
        if not isinstance(name, str) or not name.strip():
            raise InventoryError(f"plugin name is missing: {manifest_path}")
        return (
            name.strip(),
            display_name if isinstance(display_name, str) else None,
            None,
        )
    except (InventoryError, json.JSONDecodeError) as exc:
        return None, None, str(exc)


def find_readme(skill_dir: Path, plugin_root: Optional[Path]) -> Optional[str]:
    for root in (skill_dir, plugin_root):
        if root is None:
            continue
        try:
            candidates = [
                path
                for path in root.iterdir()
                if path.is_file()
                and (
                    path.name.casefold() == "readme.md"
                    or path.name.casefold().startswith("readme_")
                    or path.name.casefold().startswith("readme.")
                )
                and path.suffix.casefold() == ".md"
            ]
        except OSError:
            continue
        if candidates:
            candidates.sort(
                key=lambda path: (
                    path.name.casefold() != "readme.md",
                    path.name.casefold(),
                )
            )
            return str(candidates[0])
    return None


def skill_syntax(
    skill_name: str,
    plugin_name: Optional[str],
    plugin_display_name: Optional[str],
) -> list[str]:
    if plugin_name:
        namespaced = skill_name.split(":", 1)[0].casefold() == plugin_name.casefold()
        result = [
            f"${skill_name}" if namespaced else f"${plugin_name}:{skill_name}"
        ]
        if plugin_display_name:
            result.append(f"@{plugin_display_name}")
        return result
    return [f"${skill_name}"]


def compact_text(value: Any, limit: int = 180) -> str:
    if not isinstance(value, str):
        return ""
    text = " ".join(value.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def enrich_skill(skill: dict[str, Any]) -> dict[str, Any]:
    path_value = skill.get("path")
    path = Path(path_value) if isinstance(path_value, str) else Path()
    skill_dir = path.parent if path.name.lower() == "skill.md" else path
    plugin_root = find_plugin_root(skill_dir) if path_value else None
    plugin_name, plugin_display_name, plugin_error = load_plugin_identity(plugin_root)
    activation, policy_source, policy_error = invocation_policy(skill_dir)
    issues = [item for item in (plugin_error, policy_error) if item]

    interface = skill.get("interface")
    interface = interface if isinstance(interface, dict) else {}
    name = skill.get("name")
    name = name if isinstance(name, str) and name else skill_dir.name
    description = skill.get("description")

    return {
        "name": name,
        "display_name": interface.get("displayName") or name,
        "description": compact_text(description),
        "scope": skill.get("scope", "unknown"),
        "enabled": bool(skill.get("enabled", False)),
        "activation": activation,
        "policy_source": policy_source,
        "syntax": skill_syntax(name, plugin_name, plugin_display_name),
        "plugin": plugin_name,
        "path": str(path) if path_value else None,
        "readme": find_readme(skill_dir, plugin_root) if path_value else None,
        "issues": issues,
    }


def wait_for_response(
    messages: "queue.Queue[Optional[dict[str, Any]]]",
    request_id: int,
    timeout_seconds: float,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise InventoryError("Codex app-server timed out")
        try:
            message = messages.get(timeout=remaining)
        except queue.Empty as exc:
            raise InventoryError("Codex app-server timed out") from exc
        if message is None:
            raise InventoryError("Codex app-server closed before returning the Skill list")
        if message.get("id") == request_id:
            if "error" in message:
                error = message.get("error")
                detail = (
                    error.get("message") if isinstance(error, dict) else "unknown error"
                )
                raise InventoryError(f"Codex app-server error: {detail}")
            return message


def runtime_catalog(
    cwd: Path, timeout_seconds: float = REQUEST_TIMEOUT_SECONDS
) -> dict[str, Any]:
    executable = shutil.which("codex")
    if executable is None:
        raise InventoryError("codex executable was not found")

    try:
        process = subprocess.Popen(
            [executable, "app-server", "--stdio"],
            cwd=str(cwd),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except OSError as exc:
        raise InventoryError("unable to start Codex app-server") from exc
    if process.stdin is None or process.stdout is None:
        process.kill()
        raise InventoryError("unable to open Codex app-server pipes")

    messages: "queue.Queue[Optional[dict[str, Any]]]" = queue.Queue()

    def read_messages() -> None:
        try:
            for line in process.stdout:
                try:
                    value = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(value, dict):
                    messages.put(value)
        finally:
            messages.put(None)

    threading.Thread(target=read_messages, daemon=True).start()

    def send(message: dict[str, Any]) -> None:
        try:
            process.stdin.write(
                json.dumps(message, ensure_ascii=False, separators=(",", ":"))
                + "\n"
            )
            process.stdin.flush()
        except OSError as exc:
            raise InventoryError("Codex app-server input closed unexpectedly") from exc

    try:
        send(
            {
                "method": "initialize",
                "id": 1,
                "params": {
                    "clientInfo": {
                        "name": CLIENT_NAME,
                        "version": CLIENT_VERSION,
                    },
                    "capabilities": {"experimentalApi": True},
                },
            }
        )
        wait_for_response(messages, 1, timeout_seconds)
        send({"method": "initialized", "params": {}})
        send(
            {
                "method": "skills/list",
                "id": 2,
                "params": {
                    "cwds": [str(cwd)],
                    "forceReload": True,
                },
            }
        )
        response = wait_for_response(messages, 2, timeout_seconds)
        result = response.get("result")
        if not isinstance(result, dict) or not isinstance(result.get("data"), list):
            raise InventoryError("Codex app-server returned an invalid Skill list")
        return result
    finally:
        try:
            process.stdin.close()
        except OSError:
            pass
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)


def build_inventory(cwd: Path, catalog: dict[str, Any]) -> dict[str, Any]:
    entries = catalog.get("data")
    if not isinstance(entries, list) or not entries:
        raise InventoryError("Codex app-server returned no Skill catalog")
    entry = entries[0]
    if not isinstance(entry, dict):
        raise InventoryError("Codex app-server returned an invalid Skill catalog")
    raw_skills = entry.get("skills")
    raw_errors = entry.get("errors")
    if not isinstance(raw_skills, list) or not all(
        isinstance(item, dict) for item in raw_skills
    ):
        raise InventoryError("Codex app-server returned invalid Skill entries")
    if not isinstance(raw_errors, list):
        raise InventoryError("Codex app-server returned invalid Skill discovery errors")
    skills = [enrich_skill(item) for item in raw_skills]
    skills.sort(
        key=lambda item: (
            SCOPE_ORDER.get(str(item["scope"]), 9),
            str(item.get("plugin") or ""),
            str(item["name"]).casefold(),
            str(item.get("path") or "").casefold(),
        )
    )

    names: dict[str, list[str]] = {}
    for skill in skills:
        names.setdefault(str(skill["name"]).casefold(), []).append(
            str(skill.get("path") or "")
        )
    duplicates = [
        {"name": name, "paths": paths}
        for name, paths in sorted(names.items())
        if len(paths) > 1
    ]
    enabled_count = sum(item["enabled"] for item in skills)
    summary = {
        "total": len(skills),
        "enabled": enabled_count,
        "disabled": len(skills) - enabled_count,
        "implicit_or_explicit": sum(
            item["activation"] == "implicit_or_explicit" for item in skills
        ),
        "explicit_only": sum(
            item["activation"] == "explicit_only" for item in skills
        ),
        "unknown_activation": sum(
            item["activation"] == "unknown" for item in skills
        ),
        "discovery_errors": len(raw_errors),
        "duplicate_names": len(duplicates),
    }
    return {
        "status": "ok",
        "scan_method": "codex_app_server_skills_list",
        "cwd": str(cwd),
        "summary": summary,
        "skills": skills,
        "duplicates": duplicates,
        "discovery_errors": raw_errors,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="List Skills discovered by the current Codex runtime"
    )
    parser.add_argument(
        "--cwd",
        default=os.getcwd(),
        help="Working directory whose Skill scope is inspected",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cwd = Path(args.cwd).expanduser().resolve()
    if not cwd.is_dir():
        print(json.dumps({"status": "error", "message": "cwd is not a directory"}))
        return 1
    try:
        inventory = build_inventory(cwd, runtime_catalog(cwd))
    except InventoryError as exc:
        print(
            json.dumps(
                {"status": "error", "message": str(exc)},
                ensure_ascii=False,
            )
        )
        return 1
    print(json.dumps(inventory, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
