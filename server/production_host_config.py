"""Typed TOML configuration for the production Host assembly."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

from host_security_config import HostSecurityConfig


class ProductionHostConfigError(ValueError):
    """Raised when production Host configuration is incomplete or unsafe."""


SUPPORTED_DRIVERS = frozenset({
    "fixture_jsonl",
    "jsonl",
    "codex_exec_json",
    "claude_stream_json",
    "hermes_text",
    "hermes_oneshot_text",
})


@dataclass(frozen=True)
class ProjectRuntimeConfig:
    name: str
    agent_type: str
    command: tuple[str, ...]
    workdir: str
    terminal_command: tuple[str, ...] | None = None
    capabilities: tuple[str, ...] = ()
    max_sessions: int = 8
    models: tuple[str, ...] = ()
    channels: tuple[str, ...] = ()
    skills: tuple[str, ...] = ()
    mcp_servers: tuple[str, ...] = ()
    driver: str = "fixture_jsonl"
    close_stdin_after_send: bool = False


MIN_RECOMMENDED_TOKEN_LENGTH = 24
LOOPBACK_HOSTS = frozenset({"127.0.0.1", "::1", "localhost"})


@dataclass(frozen=True)
class ProductionHostConfig:
    bridge_host: str
    bridge_port: int
    bridge_token: str
    mgmt_host: str
    mgmt_port: int
    mgmt_token: str
    workspace_roots: tuple[str, ...]
    session_store_path: str
    session_store_max_bytes: int
    projects: tuple[ProjectRuntimeConfig, ...]
    security: HostSecurityConfig
    default_project: str
    backlog: int = 16
    poll_interval: float = 0.05
    # Big enough for the App's small attachments (10 MB base64-encoded).
    max_frame_bytes: int = 16 * 1024 * 1024
    #: Opt-in: let the App stage / commit / push (``[workspace] git_write = true``).
    git_write: bool = False

    def security_warnings(self) -> tuple[str, ...]:
        """Non-fatal deployment risks; never includes secret values."""
        warnings: list[str] = []
        for label, token in (("auth.bridge_token", self.bridge_token), ("auth.mgmt_token", self.mgmt_token)):
            if "change-me" in token.lower():
                warnings.append(f"{label} is still a placeholder; generate a random token")
            elif len(token) < MIN_RECOMMENDED_TOKEN_LENGTH:
                warnings.append(
                    f"{label} is shorter than {MIN_RECOMMENDED_TOKEN_LENGTH} characters; use a longer random token"
                )
        if self.bridge_token == self.mgmt_token:
            warnings.append("auth.bridge_token and auth.mgmt_token are identical; use separate tokens")
        for label, host in (("server.bridge_host", self.bridge_host), ("server.mgmt_host", self.mgmt_host)):
            if host not in LOOPBACK_HOSTS:
                warnings.append(
                    f"{label} binds a non-loopback address; the Host has no TLS, put it behind a TLS proxy"
                )
        return tuple(warnings)

    @classmethod
    def load(cls, path: str) -> "ProductionHostConfig":
        if not isinstance(path, str) or not path:
            raise ProductionHostConfigError("config path must be non-empty text")
        try:
            with Path(path).open("rb") as handle:
                return cls.from_mapping(tomllib.load(handle))
        except OSError as exc:
            raise ProductionHostConfigError("cannot read Host config") from exc
        except tomllib.TOMLDecodeError as exc:
            raise ProductionHostConfigError("Host config is not valid TOML") from exc

    @classmethod
    def from_mapping(cls, config: Mapping[str, Any]) -> "ProductionHostConfig":
        server = cls._table(config, "server")
        auth = cls._table(config, "auth")
        workspace = cls._table(config, "workspace")
        management = cls._table(config, "management")
        raw_projects = cls._table(config, "projects")
        bridge_host = cls._text(server.get("bridge_host", "127.0.0.1"), "server.bridge_host")
        bridge_port = cls._integer(server.get("bridge_port", 9810), "server.bridge_port", minimum=0, maximum=65535)
        backlog = cls._integer(server.get("backlog", 16), "server.backlog", minimum=1)
        poll_interval = cls._number(server.get("poll_interval", 0.05), "server.poll_interval")
        max_frame_bytes = cls._integer(
            server.get("max_frame_bytes", 16 * 1024 * 1024),
            "server.max_frame_bytes",
            minimum=1,
        )
        bridge_token = cls._text(auth.get("bridge_token"), "auth.bridge_token")
        mgmt_host = cls._text(server.get("mgmt_host", "127.0.0.1"), "server.mgmt_host")
        mgmt_port = cls._integer(server.get("mgmt_port", 9820), "server.mgmt_port", minimum=0, maximum=65535)
        mgmt_token = cls._text(auth.get("mgmt_token"), "auth.mgmt_token")
        roots = cls._text_tuple(workspace.get("roots"), "workspace.roots")
        session_store_path = cls._text(
            management.get("session_store_path"),
            "management.session_store_path",
        )
        session_store_max_bytes = cls._integer(
            management.get("session_store_max_bytes", 4 * 1024 * 1024),
            "management.session_store_max_bytes",
            minimum=1,
        )
        projects = tuple(cls._project(name, value) for name, value in raw_projects.items())
        if not projects:
            raise ProductionHostConfigError("at least one project must be configured")
        names = {project.name for project in projects}
        default_project = cls._text(
            server.get("default_project", projects[0].name),
            "server.default_project",
        )
        if default_project not in names:
            raise ProductionHostConfigError("server.default_project is not configured")
        return cls(
            bridge_host=bridge_host,
            bridge_port=bridge_port,
            bridge_token=bridge_token,
            mgmt_host=mgmt_host,
            mgmt_port=mgmt_port,
            mgmt_token=mgmt_token,
            workspace_roots=roots,
            session_store_path=session_store_path,
            session_store_max_bytes=session_store_max_bytes,
            projects=projects,
            security=HostSecurityConfig.from_mapping(config),
            default_project=default_project,
            backlog=backlog,
            poll_interval=poll_interval,
            max_frame_bytes=max_frame_bytes,
            git_write=cls._flag(workspace.get("git_write", False), "workspace.git_write"),
        )

    @staticmethod
    def _flag(value: Any, label: str) -> bool:
        if not isinstance(value, bool):
            raise ProductionHostConfigError(f"{label} must be true or false")
        return value

    @classmethod
    def _project(cls, name: str, raw: Any) -> ProjectRuntimeConfig:
        if not isinstance(name, str) or not name.strip() or not isinstance(raw, Mapping):
            raise ProductionHostConfigError("projects must be named tables")
        return ProjectRuntimeConfig(
            name=name,
            agent_type=cls._text(raw.get("agent_type"), f"projects.{name}.agent_type"),
            command=cls._text_tuple(raw.get("command"), f"projects.{name}.command"),
            workdir=cls._text(raw.get("workdir"), f"projects.{name}.workdir"),
            terminal_command=(
                cls._text_tuple(raw.get("terminal_command"), f"projects.{name}.terminal_command")
                if raw.get("terminal_command") is not None
                else None
            ),
            capabilities=cls._text_tuple(
                raw.get("capabilities", []),
                f"projects.{name}.capabilities",
                allow_empty=True,
            ),
            max_sessions=cls._integer(
                raw.get("max_sessions", 8),
                f"projects.{name}.max_sessions",
                minimum=1,
            ),
            models=cls._text_tuple(raw.get("models", []), f"projects.{name}.models", allow_empty=True),
            channels=cls._text_tuple(raw.get("channels", []), f"projects.{name}.channels", allow_empty=True),
            skills=cls._text_tuple(raw.get("skills", []), f"projects.{name}.skills", allow_empty=True),
            mcp_servers=cls._text_tuple(raw.get("mcp_servers", []), f"projects.{name}.mcp_servers", allow_empty=True),
            driver=cls._driver(raw.get("driver", "fixture_jsonl"), f"projects.{name}.driver"),
            close_stdin_after_send=cls._boolean(
                raw.get("close_stdin_after_send", False),
                f"projects.{name}.close_stdin_after_send",
            ),
        )

    @staticmethod
    def _table(config: Mapping[str, Any], key: str) -> Mapping[str, Any]:
        value = config.get(key, {})
        if not isinstance(value, Mapping):
            raise ProductionHostConfigError(f"{key} must be a table")
        return value

    @staticmethod
    def _text(value: Any, key: str) -> str:
        if not isinstance(value, str) or not value.strip() or "\x00" in value:
            raise ProductionHostConfigError(f"{key} must be non-empty text")
        return value

    @staticmethod
    def _boolean(value: Any, key: str) -> bool:
        if not isinstance(value, bool):
            raise ProductionHostConfigError(f"{key} must be boolean")
        return value

    @classmethod
    def _driver(cls, value: Any, key: str) -> str:
        driver = cls._text(value, key).lower()
        if driver not in SUPPORTED_DRIVERS:
            raise ProductionHostConfigError(f"{key} is unsupported")
        return driver

    @classmethod
    def _text_tuple(cls, value: Any, key: str, *, allow_empty: bool = False) -> tuple[str, ...]:
        if not isinstance(value, list):
            raise ProductionHostConfigError(f"{key} must be an array")
        result = tuple(cls._text(item, key) for item in value)
        if not result and not allow_empty:
            raise ProductionHostConfigError(f"{key} must not be empty")
        return result

    @staticmethod
    def _integer(value: Any, key: str, *, minimum: int, maximum: int | None = None) -> int:
        if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
            raise ProductionHostConfigError(f"{key} is invalid")
        if maximum is not None and value > maximum:
            raise ProductionHostConfigError(f"{key} is invalid")
        return value

    @staticmethod
    def _number(value: Any, key: str) -> float:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
            raise ProductionHostConfigError(f"{key} must be positive")
        return float(value)
