from __future__ import annotations

import sys
import tempfile
import time
import unittest
from pathlib import Path

from production_host_config import ProductionHostConfig, ProductionHostConfigError
from production_host_factory import build_production_host


class TestProductionHostConfig(unittest.TestCase):
    def mapping(self, directory: str) -> dict:
        script = (
            "import json, sys; "
            "line=sys.stdin.readline().strip(); "
            "print(json.dumps({'type':'text_delta','text':line}), flush=True); "
            "print(json.dumps({'type':'done'}), flush=True)"
        )
        return {
            "server": {"bridge_host": "127.0.0.1", "bridge_port": 0, "default_project": "codex"},
            "auth": {"bridge_token": "test-bridge-token", "mgmt_token": "test-mgmt-token"},
            "server": {"bridge_host": "127.0.0.1", "bridge_port": 0, "mgmt_host": "127.0.0.1", "mgmt_port": 0, "default_project": "codex"},
            "workspace": {"roots": [directory]},
            "management": {"session_store_path": str(Path(directory) / "sessions.json")},
            "permissions": {"ttl_seconds": 30},
            "audit": {"permission_log_path": str(Path(directory) / "permission.jsonl"), "permission_log_fsync": False},
            "projects": {
                "claude-code": {
                    "agent_type": "claudecode",
                    "command": [sys.executable, "-u", "-c", script],
                    "workdir": directory,
                },
                "codex": {
                    "agent_type": "codex",
                    "command": [sys.executable, "-u", "-c", script],
                    "terminal_command": [sys.executable, "-u", "-c", "print('ready', flush=True)"],
                    "workdir": directory,
                    "capabilities": ["stream", "terminal"],
                    "models": ["gpt-5-codex"],
                    "channels": ["openai"],
                    "skills": ["codex-cli"],
                    "mcp_servers": ["openai-tools"],
                },
            },
        }

    def test_builds_project_aware_agent_and_terminal_components(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = ProductionHostConfig.from_mapping(self.mapping(directory))
            components = build_production_host(config)
            try:
                events = components.agent_router.handle({
                    "type": "message",
                    "session_key": "s1",
                    "project": "codex",
                    "content": "hello",
                })
                deadline = time.monotonic() + 2
                while not any(event.get("type") == "run_done" for event in events) and time.monotonic() < deadline:
                    events.extend(components.agent_router.poll("s1"))
                    time.sleep(0.01)
                self.assertTrue(any(event.get("delta") == "hello" for event in events))
                self.assertIsNotNone(components.terminal_router)
                opened = components.terminal_router.handle({
                    "type": "terminal_open",
                    "session_key": "term-1",
                    "stream_id": "stream-1",
                    "project": "codex",
                    "cols": 80,
                    "rows": 24,
                })
                self.assertEqual(opened[0]["type"], "terminal_permission")
                opened = components.terminal_router.handle({
                    "type": "terminal_permission_action",
                    "session_key": "term-1",
                    "stream_id": "stream-1",
                    "project": "codex",
                    "action": opened[0]["buttons"][0][0]["data"],
                })
                self.assertTrue(opened[0]["ok"])
                self.assertEqual(components.server.port, 0)
                self.assertEqual(components.management.port, 0)
                self.assertEqual(config.projects[1].models, ("gpt-5-codex",))
            finally:
                components.close()

    def test_loads_toml_and_rejects_unknown_default_project(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audit = Path(directory) / "audit.jsonl"
            config_path = Path(directory) / "host.toml"
            config_path.write_text(
                f'''[server]
bridge_host = "127.0.0.1"
bridge_port = 0
mgmt_host = "127.0.0.1"
mgmt_port = 0
default_project = "codex"

[auth]
bridge_token = "token"
mgmt_token = "mgmt-token"

[workspace]
roots = ["{directory}"]

[management]
session_store_path = "{directory}/sessions.json"

[audit]
permission_log_path = "{audit}"
permission_log_fsync = false

[projects.codex]
agent_type = "codex"
command = ["{sys.executable}", "-c", "pass"]
workdir = "{directory}"
''',
                encoding="utf-8",
            )
            loaded = ProductionHostConfig.load(str(config_path))
            self.assertEqual(loaded.default_project, "codex")
            invalid = self.mapping(directory)
            invalid["server"]["default_project"] = "missing"
            with self.assertRaises(ProductionHostConfigError):
                ProductionHostConfig.from_mapping(invalid)


if __name__ == "__main__":
    unittest.main()
