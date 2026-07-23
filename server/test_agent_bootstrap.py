from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_bootstrap import (
    DiscoveredAgentRuntime,
    build_project_suggestions,
    discover_installed_agents,
    render_project_toml,
)


class TestAgentBootstrap(unittest.TestCase):
    def test_discovers_fixed_agents_without_shell(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = {name: str(Path(directory) / name) for name in ("codex", "claude", "hermes")}
            for path in paths.values():
                Path(path).touch()

            def which(name: str, path: str | None = None) -> str | None:
                return paths.get(name)

            calls: list[tuple[object, dict[str, object]]] = []

            def runner(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
                calls.append((args[0], kwargs))
                return subprocess.CompletedProcess(args[0], 0, "v1.2.3\n", "")

            with patch("agent_bootstrap.shutil.which", side_effect=which):
                agents = discover_installed_agents(version_runner=runner)

            self.assertEqual([agent.name for agent in agents], ["codex", "claude-code", "hermes"])
            self.assertEqual(agents[0].command[-1], "-")
            self.assertEqual(agents[1].driver, "claude_stream_json")
            self.assertFalse(agents[2].integration_ready)
            self.assertEqual(len(calls), 3)
            self.assertTrue(all(call[1]["shell"] is False for call in calls))

    def test_suggestions_validate_workdir_and_skip_unsafe_hermes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            agents = (
                DiscoveredAgentRuntime(
                    name="codex",
                    executable="/usr/bin/codex",
                    version="v1",
                    agent_type="codex",
                    driver="codex_exec_json",
                    command=("/usr/bin/codex", "exec", "--json", "-"),
                    capabilities=("stream",),
                    channels=("openai",),
                    close_stdin_after_send=True,
                    integration_ready=True,
                    integration_note="",
                ),
                DiscoveredAgentRuntime(
                    name="claude-code",
                    executable="/usr/bin/claude",
                    version="v1",
                    agent_type="claudecode",
                    driver="claude_stream_json",
                    command=("/usr/bin/claude", "-p"),
                    capabilities=("stream",),
                    channels=("anthropic",),
                    close_stdin_after_send=True,
                    integration_ready=True,
                    integration_note="",
                ),
                DiscoveredAgentRuntime(
                    name="hermes",
                    executable="/usr/bin/hermes",
                    version="v1",
                    agent_type="hermes",
                    driver="hermes_text",
                    command=("/usr/bin/hermes", "chat", "-Q"),
                    capabilities=("tools",),
                    channels=("hermes",),
                    close_stdin_after_send=True,
                    integration_ready=False,
                    integration_note="stdin-safe wrapper required",
                ),
            )
            suggestions = build_project_suggestions(
                agents,
                workdir=directory,
                workspace_roots=[directory],
            )
            self.assertIn("codex", suggestions)
            self.assertIn("claude-code", suggestions)
            self.assertNotIn("hermes", suggestions)
            self.assertEqual(suggestions["codex"]["workdir"], str(Path(directory).resolve()))
            toml = render_project_toml(suggestions)
            self.assertIn("[projects.codex]", toml)
            self.assertIn('driver = "codex_exec_json"', toml)
            self.assertIn("close_stdin_after_send = true", toml)

            with self.assertRaises(ValueError):
                build_project_suggestions(agents, workdir="/tmp", workspace_roots=[directory])


if __name__ == "__main__":
    unittest.main()
