from __future__ import annotations

import os
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest.mock import patch

from companion_configurator import CompanionConfigError, configure


class TestCompanionConfigurator(unittest.TestCase):
    def test_generates_private_local_config_and_tokens(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            prefix = str(Path(directory, "install"))
            projects = {"codex": {
                "agent_type": "codex", "driver": "codex_exec_json",
                "command": ["/usr/bin/codex", "exec", "--json", "-"],
                "close_stdin_after_send": True, "terminal_command": ["/bin/bash"],
                "capabilities": ["stream"], "models": [], "channels": ["openai"],
                "skills": [], "mcp_servers": [], "workdir": directory,
            }}
            with patch("companion_configurator.discover_installed_agents", return_value=()), patch(
                "companion_configurator.build_project_suggestions", return_value=projects
            ):
                result = configure(prefix=prefix, workspace=directory)
            config_path = Path(result["config_path"])
            parsed = tomllib.loads(config_path.read_text(encoding="utf-8"))
            self.assertEqual(parsed["server"]["bridge_host"], "127.0.0.1")
            self.assertEqual(parsed["server"]["default_project"], "codex")
            self.assertEqual(parsed["auth"]["bridge_token"], result["bridge_token"])
            self.assertEqual(config_path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(config_path.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(Path(prefix, "data").stat().st_mode & 0o777, 0o700)
            self.assertEqual(list(config_path.parent.glob(".*.tmp")), [])

    def test_secret_file_is_private_before_it_is_published(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            prefix = str(Path(directory, "install"))
            projects = {"codex": {
                "agent_type": "codex", "driver": "codex_exec_json",
                "command": ["/usr/bin/codex", "exec", "--json", "-"],
                "close_stdin_after_send": True, "terminal_command": ["/bin/bash"],
                "capabilities": ["stream"], "models": [], "channels": [],
                "skills": [], "mcp_servers": [], "workdir": directory,
            }}
            modes: list[int] = []
            real_replace = os.replace

            def spy_replace(source, target):  # type: ignore[no-untyped-def]
                modes.append(os.stat(source).st_mode & 0o777)
                return real_replace(source, target)

            previous = os.umask(0)
            try:
                with patch("companion_configurator.discover_installed_agents", return_value=()), patch(
                    "companion_configurator.build_project_suggestions", return_value=projects
                ), patch("companion_configurator.os.replace", side_effect=spy_replace):
                    configure(prefix=prefix, workspace=directory)
            finally:
                os.umask(previous)
            self.assertEqual(modes, [0o600])

    def test_rejects_missing_workspace_and_empty_agent_set(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(CompanionConfigError):
                configure(prefix=directory, workspace=str(Path(directory, "missing")))
            with patch("companion_configurator.discover_installed_agents", return_value=()), patch(
                "companion_configurator.build_project_suggestions", return_value={}
            ):
                with self.assertRaises(CompanionConfigError):
                    configure(prefix=directory, workspace=directory)


if __name__ == "__main__":
    unittest.main()
