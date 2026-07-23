"""Host-side lifecycle coordinator for an AgentAdapter and JSONL Driver.

The runtime is intentionally transport-neutral. A Bridge WebSocket handler can
call start/send/poll/cancel and forward the returned protocol dictionaries.
It does not log prompts, tokens, or raw agent stdout.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Callable

from jsonl_agent_driver import JsonlAgentDriver
from permission_gate import PermissionDecision, PermissionGate, PermissionGateError
from production_adapter import AgentAdapter, AdapterError


DriverFactory = Callable[[str, str | None], JsonlAgentDriver]


@dataclass
class _SessionState:
    driver: JsonlAgentDriver
    started_at: float
    timeout_seconds: float | None
    done_emitted: bool = False


class AgentSessionRuntime:
    """Coordinate process output, protocol events, exit, and cancellation."""

    def __init__(
        self,
        adapter: AgentAdapter,
        *,
        driver_factory: DriverFactory | None = None,
        permission_gate: PermissionGate | None = None,
    ) -> None:
        self.adapter = adapter
        self._driver_factory = driver_factory or self._new_driver
        self.permission_gate = permission_gate
        self._sessions: dict[str, _SessionState] = {}

    @property
    def active_sessions(self) -> tuple[str, ...]:
        return tuple(self._sessions)

    def has_active_run(self, session_key: str) -> bool:
        state = self._sessions.get(session_key)
        return state is not None and not state.done_emitted

    def start(
        self,
        session_key: str,
        *,
        workdir: str,
        reply_ctx: str | None = None,
        timeout_seconds: float | None = None,
    ) -> None:
        if timeout_seconds is not None and timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        if session_key in self._sessions:
            return
        self.adapter.start(session_key, workdir=workdir)
        try:
            driver = self._driver_factory(session_key, reply_ctx)
        except Exception:
            self.adapter.close(session_key)
            raise
        self._sessions[session_key] = _SessionState(
            driver=driver,
            started_at=time.monotonic(),
            timeout_seconds=timeout_seconds,
        )

    def begin_run(
        self,
        session_key: str,
        *,
        reply_ctx: str | None = None,
        timeout_seconds: float | None = None,
    ) -> None:
        if timeout_seconds is not None and timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        state = self._require_state(session_key)
        if not state.done_emitted:
            raise AdapterError("agent run is already active")
        state.driver = self._driver_factory(session_key, reply_ctx)
        state.started_at = time.monotonic()
        state.timeout_seconds = timeout_seconds
        state.done_emitted = False

    def send(self, session_key: str, data: str) -> None:
        self._require_state(session_key)
        self.adapter.send(session_key, data)

    def poll(self, session_key: str, *, max_bytes: int = 64 * 1024) -> list[dict]:
        state = self._require_state(session_key)
        if (
            not state.done_emitted
            and state.timeout_seconds is not None
            and time.monotonic() - state.started_at >= state.timeout_seconds
        ):
            return self._terminate(session_key, state, status="timeout")
        output = self.adapter.read_available(session_key, max_bytes=max_bytes)
        events = self._permission_events(state, state.driver.feed(output))
        self._note_done(state, events)

        exit_code = self.adapter.exit_code(session_key)
        if exit_code is None or output:
            return events

        final_events = self._permission_events(state, state.driver.finish())
        events.extend(final_events)
        self._note_done(state, final_events)
        if not state.done_emitted:
            events.append(
                self._run_done(
                    state.driver,
                    status="completed" if exit_code == 0 else "failed",
                    exit_code=exit_code,
                )
            )
            state.done_emitted = True
        self.adapter.close(session_key)
        self._sessions.pop(session_key, None)
        return events

    def respond_permission(
        self,
        session_key: str,
        *,
        action: str,
        reply_ctx: str | None,
    ) -> list[dict]:
        if self.permission_gate is None:
            raise AdapterError("permission gate is not configured")
        state = self._require_state(session_key)
        try:
            decision = self.permission_gate.decide(
                session_key=session_key,
                reply_ctx=reply_ctx,
                action=action,
            )
        except PermissionGateError as exc:
            raise AdapterError(str(exc)) from exc
        self._send_permission_decision(decision)
        return self.poll(session_key)

    def poll_all(self, *, max_bytes: int = 64 * 1024) -> list[dict]:
        events: list[dict] = []
        for session_key in tuple(self._sessions):
            events.extend(self.poll(session_key, max_bytes=max_bytes))
        return events

    def cancel(self, session_key: str, *, timeout: float = 2.0) -> list[dict]:
        state = self._sessions.get(session_key)
        if state is None:
            self.adapter.cancel(session_key, timeout=timeout)
            return []
        return self._terminate(session_key, state, status="cancelled", timeout=timeout)

    def close(self, session_key: str) -> None:
        self._sessions.pop(session_key, None)
        self.adapter.close(session_key)

    def close_all(self) -> None:
        self._sessions.clear()
        self.adapter.close_all()

    def _terminate(
        self,
        session_key: str,
        state: _SessionState,
        *,
        status: str,
        timeout: float = 2.0,
    ) -> list[dict]:
        self._sessions.pop(session_key, None)
        self.adapter.cancel(session_key, timeout=timeout)
        if state.done_emitted:
            return []
        state.driver.finish()
        state.done_emitted = True
        return [self._run_done(state.driver, status=status)]

    def _permission_events(
        self,
        state: _SessionState,
        events: list[dict],
    ) -> list[dict]:
        if self.permission_gate is None:
            return events
        transformed: list[dict] = []
        for event in events:
            if event.get("type") != "buttons":
                transformed.append(event)
                continue
            try:
                challenge = self.permission_gate.issue(
                    session_key=state.driver.session_key,
                    reply_ctx=state.driver.reply_ctx,
                    scope=str(event.get("scope") or event.get("name") or "agent.permission"),
                    prompt=str(event.get("content") or "Agent requests permission"),
                )
                if isinstance(challenge, PermissionDecision):
                    self._send_permission_decision(challenge)
                else:
                    transformed.append(challenge)
            except PermissionGateError:
                transformed.append({
                    "type": "reply",
                    "session_key": state.driver.session_key,
                    "reply_ctx": state.driver.reply_ctx,
                    "content": "Permission request rejected",
                    "error": True,
                    "error_code": "permission_request_rejected",
                })
        return transformed

    def _send_permission_decision(self, decision: PermissionDecision) -> None:
        payload = json.dumps({
            "type": "permission_response",
            "permission_id": decision.request_id,
            "decision": decision.decision,
            "scope": decision.scope,
        }, separators=(",", ":"))
        self.adapter.send(decision.session_key, payload + "\n")

    def _require_state(self, session_key: str) -> _SessionState:
        state = self._sessions.get(session_key)
        if state is None:
            raise AdapterError("agent runtime session is not known")
        return state

    @staticmethod
    def _new_driver(session_key: str, reply_ctx: str | None) -> JsonlAgentDriver:
        return JsonlAgentDriver(session_key, reply_ctx=reply_ctx)

    @staticmethod
    def _note_done(state: _SessionState, events: list[dict]) -> None:
        if any(event.get("type") == "run_done" for event in events):
            state.done_emitted = True

    @staticmethod
    def _run_done(
        driver: JsonlAgentDriver,
        *,
        status: str,
        exit_code: int | None = None,
    ) -> dict:
        event = {"type": "run_done", "session_key": driver.session_key, "status": status}
        if driver.reply_ctx is not None:
            event["reply_ctx"] = driver.reply_ctx
        if exit_code is not None:
            event["exit_code"] = exit_code
        return event
