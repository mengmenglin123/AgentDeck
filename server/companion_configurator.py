"""Generate a local-only Host config from installed Agent CLIs."""

from __future__ import annotations

import argparse
import json
import os
import secrets
from pathlib import Path
from typing import Sequence

from agent_bootstrap import build_project_suggestions, discover_installed_agents, render_project_toml


class CompanionConfigError(ValueError):
    pass


def configure(*, prefix: str, workspace: str) -> dict[str, object]:
    prefix_path = _absolute(prefix, "prefix")
    workspace_path = _absolute(workspace, "workspace")
    if not workspace_path.is_dir():
        raise CompanionConfigError("workspace must be an existing directory")
    agents = discover_installed_agents()
    projects = build_project_suggestions(
        agents,
        workdir=str(workspace_path),
        workspace_roots=[str(workspace_path)],
    )
    if not projects:
        raise CompanionConfigError("no stdin-safe supported Agent was discovered")
    bridge_token = secrets.token_urlsafe(32)
    mgmt_token = secrets.token_urlsafe(32)
    data = prefix_path / "data"
    config_dir = prefix_path / "config"
    data.mkdir(mode=0o700, parents=True, exist_ok=True)
    config_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Config, session store and permission audit are private to the Host user.
    data.chmod(0o700)
    config_dir.chmod(0o700)
    config_path = config_dir / "host.toml"
    content = _render_config(
        projects,
        workspace=str(workspace_path),
        data=str(data),
        bridge_token=bridge_token,
        mgmt_token=mgmt_token,
    )
    _write_private_file(config_path, content)
    return {
        "config_path": str(config_path),
        "bridge_host": "127.0.0.1",
        "bridge_port": 9810,
        "mgmt_host": "127.0.0.1",
        "mgmt_port": 9820,
        "bridge_token": bridge_token,
        "mgmt_token": mgmt_token,
        "projects": list(projects),
        "service_started": False,
    }


def _write_private_file(path: Path, content: str) -> None:
    """Atomically write a secret-bearing file that is never readable by others.

    The temporary file is created with mode 0600 up front (``O_EXCL``), so the
    tokens are never exposed through a umask-dependent window before chmod.
    """
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(8)}.tmp")
    payload = content.encode("utf-8")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        try:
            view = memoryview(payload)
            while view:
                written = os.write(descriptor, view)
                view = view[written:]
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass


def _render_config(
    projects: dict[str, dict[str, object]],
    *,
    workspace: str,
    data: str,
    bridge_token: str,
    mgmt_token: str,
) -> str:
    default_project = next(iter(projects))
    return f'''[server]
bridge_host = "127.0.0.1"
bridge_port = 9810
mgmt_host = "127.0.0.1"
mgmt_port = 9820
default_project = {json.dumps(default_project)}

[auth]
bridge_token = "{bridge_token}"
mgmt_token = "{mgmt_token}"

[workspace]
roots = [{json.dumps(workspace)}]

[management]
session_store_path = {json.dumps(data + "/sessions.json")}

[permissions]
ttl_seconds = 120
terminal_open_required = true

[audit]
permission_log_path = {json.dumps(data + "/permission-audit.jsonl")}
permission_log_fsync = true

{render_project_toml(projects)}'''


def _absolute(value: str, label: str) -> Path:
    if not value or "\x00" in value:
        raise CompanionConfigError(f"{label} must be non-empty text")
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise CompanionConfigError(f"{label} must be absolute")
    return path.resolve()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Configure HuanHermes Host Companion")
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--workspace", required=True)
    args = parser.parse_args(argv)
    result = configure(prefix=args.prefix, workspace=args.workspace)
    print("HH_COMPANION_CONFIG\t" + json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
