"""Transport-neutral Bridge routing for a Host-side AgentSessionRuntime."""

from __future__ import annotations

import threading
from collections.abc import Callable, Mapping
from typing import Any

from agent_session_runtime import AgentSessionRuntime
from production_adapter import AdapterError


class BridgeLoopError(ValueError):
    """Raised when an inbound Bridge message cannot start or route a run."""


WorkdirResolver = Callable[[Mapping[str, Any]], str]


class AgentBridgeLoop:
    """Translate canonical Bridge messages into Host runtime operations.

    A WebSocket transport owns authentication, framing, and writes. This module
    owns message validation and Agent lifecycle semantics so those concerns are
    tested without a live server.
    """

    def __init__(
        self,
        runtime: AgentSessionRuntime,
        *,
        workdir_resolver: WorkdirResolver,
        input_terminator: str = "\n",
    ) -> None:
        if not input_terminator:
            raise ValueError("input_terminator must not be empty")
        self.runtime = runtime
        self._workdir = workdir_resolver
        self._input_terminator = input_terminator
        self._lock = threading.RLock()

    @property
    def active_sessions(self) -> tuple[str, ...]:
        return self.runtime.active_sessions

    def handle(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        with self._lock:
            if not isinstance(message, Mapping):
                return [self._error("invalid_message")]
            try:
                message_type = message.get("type")
                if message_type == "message":
                    return self._handle_message(message)
                if message_type == "cancel":
                    return self._handle_cancel(message)
                if message_type == "card_action":
                    return self._handle_card_action(message)
                if message_type == "ping":
                    return [{"type": "pong", **self._safe_id(message)}]
                return [self._error("unsupported_message")]
            except BridgeLoopError:
                return [self._error("invalid_message")]

    def poll(self, session_key: str, *, max_bytes: int = 64 * 1024) -> list[dict[str, Any]]:
        with self._lock:
            try:
                return self.runtime.poll(session_key, max_bytes=max_bytes)
            except AdapterError:
                return [self._error("unknown_session", session_key=session_key)]

    def poll_all(self, *, max_bytes: int = 64 * 1024) -> list[dict[str, Any]]:
        with self._lock:
            return self.runtime.poll_all(max_bytes=max_bytes)

    def close_session(self, session_key: str) -> None:
        with self._lock:
            self.runtime.close(session_key)

    def close(self) -> None:
        with self._lock:
            self.runtime.close_all()

    def _handle_message(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key = self._required_text(message, "session_key")
        content = self._required_text(message, "content")
        reply_ctx = self._optional_text(message, "reply_ctx")
        try:
            if session_key not in self.runtime.active_sessions:
                self.runtime.start(
                    session_key,
                    workdir=self._workdir(message),
                    reply_ctx=reply_ctx,
                )
            elif not self.runtime.has_active_run(session_key):
                self.runtime.begin_run(session_key, reply_ctx=reply_ctx)
            self.runtime.send(session_key, content + self._input_terminator)
            return self.runtime.poll(session_key)
        except (AdapterError, OSError, ValueError):
            return [self._error("agent_start_or_send_failed", session_key=session_key)]

    def _handle_cancel(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key = self._required_text(message, "session_key")
        return self.runtime.cancel(session_key)

    def _handle_card_action(self, message: Mapping[str, Any]) -> list[dict[str, Any]]:
        session_key = self._required_text(message, "session_key")
        action = self._required_text(message, "action")
        reply_ctx = self._optional_text(message, "reply_ctx")
        try:
            return self.runtime.respond_permission(
                session_key,
                action=action,
                reply_ctx=reply_ctx,
            )
        except (AdapterError, ValueError):
            return [self._error("permission_action_rejected", session_key=session_key)]

    @staticmethod
    def _required_text(message: Mapping[str, Any], key: str) -> str:
        value = message.get(key)
        if not isinstance(value, str) or not value.strip():
            raise BridgeLoopError(f"{key} must be non-empty text")
        return value

    @staticmethod
    def _optional_text(message: Mapping[str, Any], key: str) -> str | None:
        value = message.get(key)
        return value if isinstance(value, str) and value else None

    @staticmethod
    def _safe_id(message: Mapping[str, Any]) -> dict[str, Any]:
        value = message.get("id", message.get("msg_id"))
        return {"id": value} if isinstance(value, (str, int)) else {}

    @staticmethod
    def _error(code: str, *, session_key: str | None = None) -> dict[str, Any]:
        event: dict[str, Any] = {
            "type": "reply",
            "content": "Bridge message rejected",
            "error": True,
            "error_code": code,
        }
        if session_key is not None:
            event["session_key"] = session_key
        return event
