"""Bridge terminal routing on top of a safe PTY adapter."""

from __future__ import annotations

import threading
import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any

from pty_terminal_adapter import PtyTerminalAdapter
from production_adapter import AdapterError
from permission_gate import PermissionDecision, PermissionGate, PermissionGateError


WorkdirResolver = Callable[[Mapping[str, Any]], str]


@dataclass
class _TerminalState:
    stream_id: str
    exit_sent: bool = False
    # True between a terminal_input and the terminal_out that carries done=True.
    awaiting_done: bool = False
    last_activity: float = 0.0


class TerminalBridgeLoop:
    """Own terminal stream identity and translate PTY I/O to Bridge events."""

    def __init__(
        self,
        adapter: PtyTerminalAdapter,
        *,
        workdir_resolver: WorkdirResolver,
        permission_gate: PermissionGate | None = None,
        require_open_permission: bool = False,
        quiet_seconds: float = 0.25,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if quiet_seconds < 0:
            raise ValueError("quiet_seconds must not be negative")
        self.adapter = adapter
        self._quiet_seconds = quiet_seconds
        self._clock = clock
        self._workdir = workdir_resolver
        self._permission_gate = permission_gate
        self._require_open_permission = require_open_permission
        self._states: dict[str, _TerminalState] = {}
        self._pending: dict[str, tuple[str, dict[str, Any], dict[str, Any]]] = {}
        self._lock = threading.RLock()

    @property
    def active_sessions(self) -> tuple[str, ...]:
        with self._lock:
            return tuple(dict.fromkeys((*self._states, *self._pending)))

    def handle(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        with self._lock:
            try:
                message_type = message.get("type")
                if message_type == "terminal_open":
                    return self._open(message)
                if message_type == "terminal_permission_action":
                    return self._permission_action(message)
                if message_type == "terminal_input":
                    return self._input(message)
                if message_type == "terminal_resize":
                    return self._resize(message)
                if message_type == "terminal_close":
                    return self._close(message)
                return [self._error("unsupported_terminal_message")]
            except (TypeError, ValueError):
                return [self._error("invalid_terminal_message")]

    def poll(self, session_key: str) -> list[dict[str, Any]]:
        with self._lock:
            state = self._states.get(session_key)
            if state is None and session_key in self._pending:
                return []
            if state is None:
                return [self._error("unknown_terminal", session_key=session_key)]
            try:
                data = self.adapter.read_available(session_key)
            except AdapterError:
                return [self._error("terminal_read_failed", session_key=session_key)]
            events: list[dict[str, Any]] = []
            now = self._clock()
            if data:
                state.last_activity = now
                events.append(self._out(session_key, state.stream_id, data, done=False))
            exit_code = self.adapter.exit_code(session_key)
            if exit_code is not None and not data and not state.exit_sent:
                state.exit_sent = True
                if state.awaiting_done:
                    state.awaiting_done = False
                    events.append(self._out(
                        session_key, state.stream_id, b"", done=True, exit_code=exit_code,
                    ))
                events.append(self._exit(session_key, state.stream_id, exit_code))
                self._remove(session_key)
                return events
            # A PTY shell never says "command finished"; the output going quiet
            # after an input is the end of that burst. Clients (Flutter 0.1.206
            # included) clear their busy state on done=True.
            if (
                not data
                and state.awaiting_done
                and now - state.last_activity >= self._quiet_seconds
            ):
                state.awaiting_done = False
                events.append(self._out(session_key, state.stream_id, b"", done=True))
            return events

    def poll_all(self) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        for session_key in tuple(self.active_sessions):
            events.extend(self.poll(session_key))
        return events

    def close_session(self, session_key: str) -> None:
        with self._lock:
            state = self._states.pop(session_key, None)
            self._pending.pop(session_key, None)
            self.adapter.close(session_key)
            if state is not None and not state.exit_sent:
                state.exit_sent = True

    def close(self) -> None:
        with self._lock:
            self._states.clear()
            self._pending.clear()
            self.adapter.close_all()

    def _open(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key = self._required(message, "session_key")
        stream_id = self._required(message, "stream_id")
        cols, rows = self._geometry(message)
        old = self._states.get(session_key)
        if old is not None and old.stream_id == stream_id:
            try:
                self.adapter.resize(session_key, cols=cols, rows=rows)
            except (AdapterError, OSError, ValueError):
                return [self._open_ack(session_key, stream_id, ok=False, error="terminal_open_failed")]
            return [self._open_ack(session_key, stream_id, ok=True, cols=cols, rows=rows)]
        if self._permission_gate is not None and self._require_open_permission:
            pending = self._pending.get(session_key)
            if pending is not None:
                if pending[0] == stream_id:
                    return [self._permission_event(session_key, stream_id, pending[2])]
                self._pending.pop(session_key, None)
            issued = self._permission_gate.issue(
                session_key=session_key,
                reply_ctx=stream_id,
                scope="terminal.open",
                prompt="Allow opening a terminal for the selected project?",
            )
            if isinstance(issued, PermissionDecision):
                if issued.decision not in {"allow", "allow_all"}:
                    return [self._open_ack(session_key, stream_id, ok=False, error="terminal_permission_denied")]
            else:
                self._pending[session_key] = (stream_id, dict(message), dict(issued))
                return [self._permission_event(session_key, stream_id, issued)]
        if old is not None:
            self.adapter.close(session_key)
            self._states.pop(session_key, None)
        try:
            self.adapter.start(
                session_key,
                workdir=self._workdir(message),
                cols=cols,
                rows=rows,
            )
        except (AdapterError, OSError, ValueError):
            return [self._open_ack(session_key, stream_id, ok=False, error="terminal_open_failed")]
        self._states[session_key] = _TerminalState(stream_id=stream_id)
        return [self._open_ack(session_key, stream_id, ok=True, cols=cols, rows=rows)]

    def _permission_action(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key = self._required(message, "session_key")
        stream_id = self._required(message, "stream_id")
        action = self._required(message, "action")
        pending = self._pending.get(session_key)
        if pending is None or pending[0] != stream_id:
            return [self._error("terminal_permission_missing", session_key=session_key, stream_id=stream_id)]
        if self._permission_gate is None:
            return [self._error("terminal_permission_unavailable", session_key=session_key, stream_id=stream_id)]
        try:
            decision = self._permission_gate.decide(
                session_key=session_key,
                reply_ctx=stream_id,
                action=action,
            )
        except PermissionGateError:
            return [self._error("terminal_permission_rejected", session_key=session_key, stream_id=stream_id)]
        pending_message = self._pending.pop(session_key)[1]
        if decision.decision not in {"allow", "allow_all"}:
            return [self._open_ack(session_key, stream_id, ok=False, error="terminal_permission_denied")]
        return self._open_without_permission(pending_message)

    def _open_without_permission(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key = self._required(message, "session_key")
        stream_id = self._required(message, "stream_id")
        cols, rows = self._geometry(message)
        old = self._states.get(session_key)
        if old is not None:
            self.adapter.close(session_key)
            self._states.pop(session_key, None)
        try:
            self.adapter.start(
                session_key,
                workdir=self._workdir(message),
                cols=cols,
                rows=rows,
            )
        except (AdapterError, OSError, ValueError):
            return [self._open_ack(session_key, stream_id, ok=False, error="terminal_open_failed")]
        self._states[session_key] = _TerminalState(stream_id=stream_id)
        return [self._open_ack(session_key, stream_id, ok=True, cols=cols, rows=rows)]

    @staticmethod
    def _permission_event(session_key: str, stream_id: str, card: Mapping[str, Any]) -> dict[str, Any]:
        event = dict(card)
        event["type"] = "terminal_permission"
        event["session_key"] = session_key
        event["stream_id"] = stream_id
        return event

    def _input(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key, state = self._state_for(message)
        if state is None:
            return [self._error("stale_terminal_stream", session_key=session_key)]
        data = message.get("data")
        if not isinstance(data, str):
            return [self._error("invalid_terminal_input", session_key=session_key)]
        try:
            self.adapter.send(session_key, data)
        except AdapterError:
            return [self._error("terminal_write_failed", session_key=session_key)]
        state.awaiting_done = True
        state.last_activity = self._clock()
        return self.poll(session_key)

    def _resize(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key, state = self._state_for(message)
        if state is None:
            return [self._error("stale_terminal_stream", session_key=session_key)]
        cols, rows = self._geometry(message)
        try:
            self.adapter.resize(session_key, cols=cols, rows=rows)
        except (AdapterError, ValueError):
            return [self._error("terminal_resize_failed", session_key=session_key)]
        return [{
            "type": "terminal_ack",
            "ok": True,
            "session_key": session_key,
            "stream_id": state.stream_id,
            "cols": cols,
            "rows": rows,
        }]

    def _close(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key, state = self._state_for(message)
        if state is None:
            return [self._error("stale_terminal_stream", session_key=session_key)]
        self.adapter.close(session_key)
        self._states.pop(session_key, None)
        return [self._exit(session_key, state.stream_id, 0)]

    def _state_for(self, message: Mapping[str, Any]) -> tuple[str, _TerminalState | None]:
        session_key = self._required(message, "session_key")
        stream_id = self._optional(message, "stream_id")
        state = self._states.get(session_key)
        if state is None or stream_id != state.stream_id:
            return session_key, None
        return session_key, state

    @staticmethod
    def _required(message: Mapping[str, Any], key: str) -> str:
        value = message.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{key} must be non-empty text")
        return value

    @staticmethod
    def _optional(message: Mapping[str, Any], key: str) -> str | None:
        value = message.get(key)
        return value if isinstance(value, str) else None

    @staticmethod
    def _geometry(message: Mapping[str, Any]) -> tuple[int, int]:
        try:
            cols = int(message.get("cols", 80))
            rows = int(message.get("rows", 24))
        except (TypeError, ValueError) as exc:
            raise ValueError("terminal geometry must be integers") from exc
        if not (1 <= cols <= 1000 and 1 <= rows <= 500):
            raise ValueError("terminal geometry is outside supported limits")
        return cols, rows

    @staticmethod
    def _open_ack(
        session_key: str,
        stream_id: str,
        *,
        ok: bool,
        error: str | None = None,
        cols: int | None = None,
        rows: int | None = None,
    ) -> dict[str, Any]:
        event: dict[str, Any] = {
            "type": "terminal_open_ack",
            "ok": ok,
            "session_key": session_key,
            "stream_id": stream_id,
        }
        if cols is not None:
            event["cols"] = cols
        if rows is not None:
            event["rows"] = rows
        if error is not None:
            event["error"] = error
        return event

    @staticmethod
    def _out(
        session_key: str,
        stream_id: str,
        data: bytes,
        *,
        done: bool,
        exit_code: int | None = None,
    ) -> dict[str, Any]:
        event: dict[str, Any] = {
            "type": "terminal_out",
            "session_key": session_key,
            "stream_id": stream_id,
            "data": data.decode("utf-8", errors="replace"),
            "done": done,
        }
        if exit_code is not None:
            event["exit_code"] = exit_code
        return event

    @staticmethod
    def _exit(session_key: str, stream_id: str, exit_code: int) -> dict[str, Any]:
        return {
            "type": "terminal_exit",
            "session_key": session_key,
            "stream_id": stream_id,
            "exit_code": exit_code,
        }

    @staticmethod
    def _error(
        code: str,
        *,
        session_key: str | None = None,
        stream_id: str | None = None,
    ) -> dict[str, Any]:
        event: dict[str, Any] = {"type": "terminal_ack", "ok": False, "error": code}
        if session_key is not None:
            event["session_key"] = session_key
        if stream_id is not None:
            event["stream_id"] = stream_id
        return event

    def _remove(self, session_key: str) -> None:
        self._states.pop(session_key, None)
        self.adapter.close(session_key)
