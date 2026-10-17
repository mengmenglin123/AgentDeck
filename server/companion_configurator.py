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


def _existing_tokens(config_path: Path) -> tuple[str, str] | None:
    """Re-running the configurator keeps tokens so other paired devices keep working."""
    try:
        text = config_path.read_text(encoding="utf-8")
    except OSError:
        return None
    import re
    bridge = re.search(r'^bridge_token\s*=\s*"([A-Za-z0-9_\-]{16,})"', text, re.M)
    mgmt = re.search(r'^mgmt_token\s*=\s*"([A-Za-z0-9_\-]{16,})"', text, re.M)
    return (bridge.group(1), mgmt.group(1)) if bridge and mgmt else None


def _start_service() -> bool:
    import shutil
    import subprocess
    if not shutil.which("systemctl"):
        return False
    for args in (("daemon-reload",), ("enable", "huanhermes-host.service"), ("restart", "huanhermes-host.service")):
        try:
            if subprocess.run(["systemctl", "--user", *args], capture_output=True, timeout=20).returncode != 0:
                return False
        except (OSError, subprocess.TimeoutExpired):
            return False
    return True


def configure(*, prefix: str, workspace: str, bind: str = "127.0.0.1", start: bool = False) -> dict[str, object]:
    if bind not in {"127.0.0.1", "0.0.0.0", "::1", "::"}:
        raise CompanionConfigError("bind must be a loopback or wildcard address")
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
    existing = _existing_tokens(prefix_path / "config" / "host.toml")
    bridge_token, mgmt_token = existing or (secrets.token_urlsafe(32), secrets.token_urlsafe(32))
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
        bind=bind,
    )
    _write_private_file(config_path, content)
    started = _start_service() if start else False
    return {
        "config_path": str(config_path),
        "bridge_host": bind,
        "bridge_port": 9810,
        "mgmt_host": bind,
        "mgmt_port": 9820,
        "bridge_token": bridge_token,
        "mgmt_token": mgmt_token,
        "projects": list(projects),
        "service_started": started,
        "reused_tokens": existing is not None,
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
    bind: str = "127.0.0.1",
) -> str:
    default_project = next(iter(projects))
    return f'''[server]
bridge_host = "{bind}"
bridge_port = 9810
mgmt_host = "{bind}"
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
    parser.add_argument("--bind", default="127.0.0.1", help="listen address (0.0.0.0 for direct LAN access)")
    parser.add_argument("--start", action="store_true", help="(re)start the systemd user service")
    args = parser.parse_args(argv)
    result = configure(prefix=args.prefix, workspace=args.workspace, bind=args.bind, start=args.start)
    print("HH_COMPANION_CONFIG\t" + json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
