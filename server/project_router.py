"""Route Bridge Agent/PTY messages to project-specific Host runtimes."""

from __future__ import annotations

from typing import Mapping, Protocol


class _AgentLoop(Protocol):
    @property
    def active_sessions(self) -> tuple[str, ...]: ...

    def handle(self, message: Mapping[str, object]) -> list[dict]: ...
    def poll(self, session_key: str) -> list[dict]: ...
    def close_session(self, session_key: str) -> None: ...
    def close(self) -> None: ...


class _TerminalLoop(Protocol):
    @property
    def active_sessions(self) -> tuple[str, ...]: ...

    def handle(self, message: Mapping[str, object]) -> list[dict]: ...
    def poll(self, session_key: str) -> list[dict]: ...
    def close_session(self, session_key: str) -> None: ...
    def close(self) -> None: ...


class _SessionRegistry(Protocol):
    def project_for(self, session_key: str) -> str | None: ...
    def bind(self, session_key: str, project: str) -> object: ...


class ProjectRouterError(ValueError):
    """Raised when a project route is missing or conflicts with a session."""


class ProjectAgentRouter:
    """Keep Agent session ownership and project selection in one Host seam."""

    def __init__(
        self,
        loops: Mapping[str, _AgentLoop],
        *,
        default_project: str | None = None,
        session_registry: _SessionRegistry | None = None,
    ) -> None:
        self._loops = dict(loops)
        if not self._loops:
            raise ValueError("at least one Agent project is required")
        self._default = default_project or next(iter(self._loops))
        if self._default not in self._loops:
            raise ValueError("default project is not configured")
        self._sessions: dict[str, str] = {}
        self._session_registry = session_registry

    @property
    def active_sessions(self) -> tuple[str, ...]:
        sessions: list[str] = []
        for loop in self._loops.values():
            sessions.extend(loop.active_sessions)
        return tuple(sessions)

    def handle(self, message: Mapping[str, object]) -> list[dict]:
        try:
            project = self._route(message)
            session_key = message.get("session_key")
            if (
                self._session_registry is not None
                and message.get("type") == "message"
                and isinstance(session_key, str)
            ):
                self._session_registry.bind(session_key, project)
        except (ProjectRouterError, ValueError):
            return [self._error(message)]
        loop = self._loops[project]
        events = loop.handle(message)
        session_key = message.get("session_key")
        if isinstance(session_key, str) and session_key in loop.active_sessions:
            self._sessions[session_key] = project
        if isinstance(session_key, str) and session_key not in loop.active_sessions:
            self._sessions.pop(session_key, None)
        return events

    @staticmethod
    def _error(message: Mapping[str, object]) -> dict:
        event = {
            "type": "reply",
            "content": "Project route rejected",
            "error": True,
            "error_code": "project_route_rejected",
        }
        session_key = message.get("session_key")
        if isinstance(session_key, str):
            event["session_key"] = session_key
        return event

    def poll(self, session_key: str) -> list[dict]:
        project = self._sessions.get(session_key)
        if project is None:
            return [{
                "type": "reply",
                "session_key": session_key,
                "content": "Unknown Agent session",
                "error": True,
                "error_code": "unknown_session",
            }]
        events = self._loops[project].poll(session_key)
        if session_key not in self._loops[project].active_sessions:
            self._sessions.pop(session_key, None)
        return events

    def poll_all(self) -> list[dict]:
        events: list[dict] = []
        for session_key in tuple(self._sessions):
            events.extend(self.poll(session_key))
        return events

    def close_session(self, session_key: str) -> None:
        project = self._sessions.pop(session_key, None)
        if project is not None:
            self._loops[project].close_session(session_key)

    def close(self) -> None:
        self._sessions.clear()
        for loop in self._loops.values():
            loop.close()

    def _route(self, message: Mapping[str, object]) -> str:
        session_key = message.get("session_key")
        known = session_key if isinstance(session_key, str) else None
        mapped = self._sessions.get(known) if known is not None else None
        persisted = (
            self._session_registry.project_for(known)
            if self._session_registry is not None and known is not None
            else None
        )
        if mapped is not None and persisted is not None and mapped != persisted:
            raise ProjectRouterError("active session route conflicts with registry")
        mapped = mapped or persisted
        requested = message.get("project")
        if requested is not None and (not isinstance(requested, str) or not requested.strip()):
            raise ProjectRouterError("project must be non-empty text")
        project = requested if isinstance(requested, str) and requested else mapped or self._default
        if project not in self._loops:
            raise ProjectRouterError("project is not configured")
        if mapped is not None and mapped != project:
            raise ProjectRouterError("session belongs to another project")
        return project


class ProjectTerminalRouter:
    """Route terminal streams with the same project/session invariant."""

    def __init__(
        self,
        loops: Mapping[str, _TerminalLoop],
        *,
        default_project: str | None = None,
    ) -> None:
        self._loops = dict(loops)
        if not self._loops:
            raise ValueError("at least one terminal project is required")
        self._default = default_project
        if self._default is not None and self._default not in self._loops:
            raise ValueError("default project is not configured")
        self._sessions: dict[str, str] = {}

    @property
    def active_sessions(self) -> tuple[str, ...]:
        sessions: list[str] = []
        for loop in self._loops.values():
            sessions.extend(loop.active_sessions)
        return tuple(sessions)

    def handle(self, message: Mapping[str, object]) -> list[dict]:
        try:
            project = self._route(message)
        except ProjectRouterError:
            return [self._error(message)]
        loop = self._loops[project]
        events = loop.handle(message)
        session_key = message.get("session_key")
        if isinstance(session_key, str) and session_key in loop.active_sessions:
            self._sessions[session_key] = project
        if isinstance(session_key, str) and session_key not in loop.active_sessions:
            self._sessions.pop(session_key, None)
        return events

    @staticmethod
    def _error(message: Mapping[str, object]) -> dict:
        event = {
            "type": "terminal_ack",
            "ok": False,
            "error": "project_route_rejected",
        }
        for key in ("session_key", "stream_id"):
            value = message.get(key)
            if isinstance(value, str):
                event[key] = value
        return event

    def poll(self, session_key: str) -> list[dict]:
        project = self._sessions.get(session_key)
        if project is None:
            return [{
                "type": "terminal_ack",
                "session_key": session_key,
                "ok": False,
                "error": "unknown_terminal",
            }]
        events = self._loops[project].poll(session_key)
        if session_key not in self._loops[project].active_sessions:
            self._sessions.pop(session_key, None)
        return events

    def poll_all(self) -> list[dict]:
        events: list[dict] = []
        for session_key in tuple(self._sessions):
            events.extend(self.poll(session_key))
        return events

    def close_session(self, session_key: str) -> None:
        project = self._sessions.pop(session_key, None)
        if project is not None:
            self._loops[project].close_session(session_key)

    def close(self) -> None:
        self._sessions.clear()
        for loop in self._loops.values():
            loop.close()

    def _route(self, message: Mapping[str, object]) -> str:
        session_key = message.get("session_key")
        known = session_key if isinstance(session_key, str) else None
        mapped = self._sessions.get(known) if known is not None else None
        requested = message.get("project")
        if requested is not None and (not isinstance(requested, str) or not requested.strip()):
            raise ProjectRouterError("project must be non-empty text")
        project = requested if isinstance(requested, str) and requested else mapped or self._default
        if project is None:
            raise ProjectRouterError("project is required for a new terminal session")
        if project not in self._loops:
            raise ProjectRouterError("project is not configured")
        if mapped is not None and mapped != project:
            raise ProjectRouterError("terminal session belongs to another project")
        return project
