"""Install the HuanHermes Host Companion into a user-owned prefix."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


class CompanionInstallError(ValueError):
    """Raised when an install request is unsafe or cannot be completed."""


_SAFE_RELEASE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


@dataclass(frozen=True)
class CompanionInstallPlan:
    version: str
    source: str
    prefix: str
    release_dir: str
    current_link: str
    service_path: str
    config_path: str
    files: tuple[str, ...]


def build_install_plan(*, source: str, prefix: str, version: str) -> CompanionInstallPlan:
    source_dir = _existing_directory(source, "source")
    server_dir = source_dir / "server"
    if not server_dir.is_dir():
        raise CompanionInstallError("source must contain the server directory")
    prefix_dir = _absolute_path(prefix, "prefix")
    safe_version = _safe_release(version)
    files = tuple(sorted(
        str(path.relative_to(source_dir))
        for path in server_dir.glob("*.py")
        if path.is_file()
        and "__pycache__" not in path.parts
        and not path.name.startswith("test_")
    ))
    if not files:
        raise CompanionInstallError("source contains no installable Python files")
    release_dir = prefix_dir / "releases" / safe_version
    return CompanionInstallPlan(
        version=safe_version,
        source=str(source_dir),
        prefix=str(prefix_dir),
        release_dir=str(release_dir),
        current_link=str(prefix_dir / "current"),
        service_path=str(Path.home() / ".config/systemd/user/huanhermes-host.service"),
        config_path=str(prefix_dir / "config/host.toml"),
        files=files,
    )


def install(plan: CompanionInstallPlan) -> CompanionInstallPlan:
    release_dir = Path(plan.release_dir)
    prefix = Path(plan.prefix)
    release_dir.parent.mkdir(parents=True, exist_ok=True)
    prefix.joinpath("config").mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{plan.version}.", dir=str(release_dir.parent)))
    try:
        for relative in plan.files:
            source = Path(plan.source, relative)
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            target.chmod(0o700 if target.name == "production_host.py" else 0o600)
        if release_dir.exists():
            raise CompanionInstallError("release version already exists")
        os.replace(staging, release_dir)
    except OSError as exc:
        raise CompanionInstallError("cannot install companion release") from exc
    finally:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
    return plan


def activate(plan: CompanionInstallPlan) -> CompanionInstallPlan:
    release_dir = Path(plan.release_dir)
    if not release_dir.is_dir():
        raise CompanionInstallError("release is not installed")
    current = Path(plan.current_link)
    temporary = current.with_name(f".{current.name}.{plan.version}.tmp")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(release_dir)
    os.replace(temporary, current)
    return plan


def render_user_service(plan: CompanionInstallPlan) -> str:
    prefix = _systemd_escape(plan.prefix)
    config = _systemd_escape(plan.config_path)
    return (
        "[Unit]\n"
        "Description=HuanHermes Host Companion\n"
        "After=network-online.target\n\n"
        "[Service]\n"
        f"WorkingDirectory={prefix}/current/server\n"
        f"ExecStart=/usr/bin/python3 {prefix}/current/server/production_host.py --config {config}\n"
        "Restart=on-failure\n"
        "RestartSec=3\n\n"
        "[Install]\n"
        "WantedBy=default.target\n"
    )


def write_user_service(plan: CompanionInstallPlan) -> str:
    path = Path(plan.service_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(render_user_service(plan), encoding="utf-8")
    temporary.chmod(0o600)
    os.replace(temporary, path)
    return str(path)


def _existing_directory(value: str, label: str) -> Path:
    path = _absolute_path(value, label)
    if not path.is_dir():
        raise CompanionInstallError(f"{label} must be a directory")
    return path


def _absolute_path(value: str, label: str) -> Path:
    if not isinstance(value, str) or not value.strip() or "\x00" in value:
        raise CompanionInstallError(f"{label} must be non-empty text")
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise CompanionInstallError(f"{label} must be absolute")
    return path.resolve()


def _safe_release(value: str) -> str:
    if not isinstance(value, str) or not _SAFE_RELEASE.fullmatch(value):
        raise CompanionInstallError("version contains unsafe characters")
    return value


def _systemd_escape(value: str) -> str:
    if any(character in value for character in "\n\r\x00"):
        raise CompanionInstallError("systemd value contains control characters")
    return value.replace("%", "%%")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Install HuanHermes Host Companion")
    parser.add_argument("action", choices=("plan", "install"))
    parser.add_argument("--source", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args(argv)
    plan = build_install_plan(source=args.source, prefix=args.prefix, version=args.version)
    if args.action == "install":
        install(plan)
        activate(plan)
        write_user_service(plan)
    print("HH_COMPANION\t" + json.dumps({
        "action": args.action,
        "version": plan.version,
        "release_dir": plan.release_dir,
        "service_path": plan.service_path,
        "config_path": plan.config_path,
        "activated": args.action == "install",
        "service_started": False,
    }, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
