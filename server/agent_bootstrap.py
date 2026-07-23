"""Discover supported Agent CLIs and build safe Host project suggestions.

Discovery is read-only. It only resolves a fixed executable allowlist and runs
the corresponding ``--version`` command without a shell. Generated project
suggestions still require an operator to review and merge them into Host TOML.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable, Sequence

from workspace_allowlist import WorkspaceAllowlist


@dataclass(frozen=True)
class AgentBootstrapDefinition:
    name: str
    executable_name: str
    agent_type: str
    driver: str
    command_suffix: tuple[str, ...]
    capabilities: tuple[str, ...]
    channels: tuple[str, ...]
    close_stdin_after_send: bool
    integration_ready: bool = True
    integration_note: str = ""


@dataclass(frozen=True)
class DiscoveredAgentRuntime:
    name: str
    executable: str
    version: str
    agent_type: str
    driver: str
    command: tuple[str, ...]
    capabilities: tuple[str, ...]
    channels: tuple[str, ...]
    close_stdin_after_send: bool
    integration_ready: bool
    integration_note: str


DEFINITIONS = (
    AgentBootstrapDefinition(
        name="codex",
        executable_name="codex",
        agent_type="codex",
        driver="codex_exec_json",
        command_suffix=("exec", "--json", "-"),
        capabilities=("stream", "model", "tools", "terminal"),
        channels=("openai",),
        close_stdin_after_send=True,
    ),
    AgentBootstrapDefinition(
        name="claude-code",
        executable_name="claude",
        agent_type="claudecode",
        driver="claude_stream_json",
        command_suffix=(
            "-p",
            "--verbose",
            "--output-format",
            "stream-json",
            "--permission-mode",
            "dontAsk",
            "--no-session-persistence",
        ),
        capabilities=("stream", "model", "tools", "terminal"),
        channels=("anthropic",),
        close_stdin_after_send=True,
    ),
    AgentBootstrapDefinition(
        name="hermes",
        executable_name="hermes",
        agent_type="hermes",
        driver="hermes_text",
        command_suffix=("chat", "-Q"),
        capabilities=("tools", "terminal"),
        channels=("hermes",),
        close_stdin_after_send=True,
        integration_ready=False,
        integration_note=(
            "Hermes chat currently accepts one-shot prompts through -q QUERY; "
            "HuanHermes will not place message content in process argv."
        ),
    ),
)


VersionRunner = Callable[..., subprocess.CompletedProcess[str]]


def discover_installed_agents(
    *,
    search_path: str | None = None,
    version_runner: VersionRunner = subprocess.run,
) -> tuple[DiscoveredAgentRuntime, ...]:
    """Return fixed, recognized Agent executables available on PATH."""
    discovered: list[DiscoveredAgentRuntime] = []
    for definition in DEFINITIONS:
        resolved = shutil.which(definition.executable_name, path=search_path)
        if resolved is None:
            continue
        executable = str(Path(resolved).resolve(strict=True))
        version = _read_version(executable, version_runner)
        discovered.append(DiscoveredAgentRuntime(
            name=definition.name,
            executable=executable,
            version=version,
            agent_type=definition.agent_type,
            driver=definition.driver,
            command=(executable, *definition.command_suffix),
            capabilities=definition.capabilities,
            channels=definition.channels,
            close_stdin_after_send=definition.close_stdin_after_send,
            integration_ready=definition.integration_ready,
            integration_note=definition.integration_note,
        ))
    return tuple(discovered)


def build_project_suggestions(
    agents: Sequence[DiscoveredAgentRuntime],
    *,
    workdir: str,
    workspace_roots: Sequence[str],
) -> dict[str, dict[str, object]]:
    """Build project mappings only for integrations safe to enable."""
    canonical_workdir = WorkspaceAllowlist(workspace_roots).resolve(workdir)
    projects: dict[str, dict[str, object]] = {}
    for agent in agents:
        if not agent.integration_ready:
            continue
        projects[agent.name] = {
            "agent_type": agent.agent_type,
            "driver": agent.driver,
            "command": list(agent.command),
            "close_stdin_after_send": agent.close_stdin_after_send,
            "terminal_command": ["/bin/bash"],
            "capabilities": list(agent.capabilities),
            "models": [],
            "channels": list(agent.channels),
            "skills": [],
            "mcp_servers": [],
            "workdir": canonical_workdir,
        }
    return projects


def discovery_document(agents: Sequence[DiscoveredAgentRuntime]) -> dict[str, object]:
    return {
        "schema": "huanhermes.agent-discovery.v1",
        "agents": [asdict(agent) for agent in agents],
    }


def render_project_toml(projects: dict[str, dict[str, object]]) -> str:
    """Render reviewed project suggestions as a TOML fragment."""
    lines: list[str] = []
    for name, project in projects.items():
        lines.append(f"[projects.{name}]")
        for key, value in project.items():
            lines.append(f"{key} = {_toml_value(value)}")
        lines.append("")
    return "\n".join(lines)


def _toml_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(_toml_value(item) for item in value) + "]"
    raise TypeError(f"unsupported TOML value: {type(value).__name__}")


def _read_version(executable: str, runner: VersionRunner) -> str:
    try:
        result = runner(
            [executable, "--version"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
            shell=False,
        )
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    output = (result.stdout or result.stderr or "unknown").strip().splitlines()
    return output[0][:256] if output else "unknown"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Discover supported Agent CLIs safely")
    parser.add_argument("--path", help="PATH value used only for executable lookup")
    parser.add_argument("--workdir", help="Generate reviewed project suggestions for this directory")
    parser.add_argument("--workspace-root", action="append", default=[])
    parser.add_argument("--format", choices=("json", "toml"), default="json")
    args = parser.parse_args(argv)
    agents = discover_installed_agents(search_path=args.path)
    document = discovery_document(agents)
    if args.workdir is not None:
        if not args.workspace_root:
            parser.error("--workspace-root is required with --workdir")
        document["project_suggestions"] = build_project_suggestions(
            agents,
            workdir=args.workdir,
            workspace_roots=args.workspace_root,
        )
    if args.format == "toml":
        if "project_suggestions" not in document:
            parser.error("--workdir and --workspace-root are required with --format toml")
        print(render_project_toml(document["project_suggestions"]))
    else:
        print(json.dumps(document, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
