"""Host-side permission challenge and one-shot decision state machine."""

from __future__ import annotations

import re
import time
import uuid
from dataclasses import dataclass
from typing import Callable


class PermissionGateError(ValueError):
    """Raised when a permission request or decision is invalid."""


@dataclass(frozen=True)
class PermissionDecision:
    request_id: str
    session_key: str
    reply_ctx: str | None
    scope: str
    decision: str
    automatic: bool = False


@dataclass(frozen=True)
class PermissionAuditRecord:
    action: str
    request_id: str
    session_key: str
    scope: str
    decision: str | None
    ts: float


@dataclass
class _PendingPermission:
    request_id: str
    session_key: str
    reply_ctx: str | None
    scope: str
    expires_at: float


AuditSink = Callable[[PermissionAuditRecord], None]
Clock = Callable[[], float]
IdFactory = Callable[[], str]


class PermissionGate:
    """Issue and consume short-lived permission challenges on the Host."""

    _DECISIONS = {"allow", "deny", "allow_all"}
    _SAFE_TEXT = re.compile(r"(bearer\s+|token=|api[_-]?key\s*[:=])\S*", re.IGNORECASE)

    def __init__(
        self,
        *,
        ttl_seconds: float = 120.0,
        clock: Clock = time.monotonic,
        id_factory: IdFactory | None = None,
        audit_sink: AuditSink | None = None,
    ) -> None:
        if ttl_seconds <= 0:
            raise ValueError("ttl_seconds must be positive")
        self.ttl_seconds = ttl_seconds
        self._clock = clock
        self._id_factory = id_factory or (lambda: f"perm-{uuid.uuid4().hex[:16]}")
        self._audit = audit_sink
        self._pending: dict[str, _PendingPermission] = {}
        self._allow_all: dict[tuple[str, str], float] = {}

    @property
    def pending_ids(self) -> tuple[str, ...]:
        self._expire()
        return tuple(self._pending)

    def issue(
        self,
        *,
        session_key: str,
        reply_ctx: str | None,
        scope: str,
        prompt: str,
    ) -> dict[str, object] | PermissionDecision:
        self._validate_context(session_key, scope)
        request_id = self._new_id()
        now = self._clock()
        allowed_until = self._allow_all.get((session_key, scope))
        if allowed_until is not None and allowed_until > now:
            decision = PermissionDecision(
                request_id=request_id,
                session_key=session_key,
                reply_ctx=reply_ctx,
                scope=scope,
                decision="allow",
                automatic=True,
            )
            self._record("permission.auto_allow", decision, "allow")
            return decision

        self._expire(now)
        pending = _PendingPermission(
            request_id=request_id,
            session_key=session_key,
            reply_ctx=reply_ctx,
            scope=scope,
            expires_at=now + self.ttl_seconds,
        )
        self._record(
            "permission.requested",
            PermissionDecision(request_id, session_key, reply_ctx, scope, "pending"),
            None,
        )
        self._pending[request_id] = pending
        return {
            "type": "card",
            "session_key": session_key,
            "reply_ctx": reply_ctx,
            "permission_id": request_id,
            "scope": scope,
            "content": self._safe_prompt(prompt, scope),
            "buttons": [[
                {"text": "Allow", "data": f"perm:{request_id}:allow"},
                {"text": "Allow all", "data": f"perm:{request_id}:allow_all"},
                {"text": "Deny", "data": f"perm:{request_id}:deny"},
            ]],
        }

    def decide(
        self,
        *,
        session_key: str,
        reply_ctx: str | None,
        action: str,
    ) -> PermissionDecision:
        request_id, decision_name = self._parse_action(action)
        self._expire()
        pending = self._pending.get(request_id)
        if pending is None:
            raise PermissionGateError("permission request is missing or expired")
        if pending.session_key != session_key:
            raise PermissionGateError("permission request belongs to another session")
        if pending.reply_ctx != reply_ctx:
            raise PermissionGateError("permission reply context does not match")
        decision = PermissionDecision(
            request_id=request_id,
            session_key=session_key,
            reply_ctx=reply_ctx,
            scope=pending.scope,
            decision=decision_name,
        )
        allow_all_until = (
            self._clock() + self.ttl_seconds
            if decision_name == "allow_all"
            else None
        )
        self._record("permission.decided", decision, decision_name)
        self._pending.pop(request_id, None)
        if allow_all_until is not None:
            self._allow_all[(session_key, pending.scope)] = allow_all_until
        return decision

    def _expire(self, now: float | None = None) -> None:
        current = self._clock() if now is None else now
        expired = [key for key, value in self._pending.items() if value.expires_at <= current]
        for key in expired:
            pending = self._pending[key]
            self._record(
                "permission.expired",
                PermissionDecision(pending.request_id, pending.session_key, pending.reply_ctx, pending.scope, "expired"),
                "expired",
            )
            self._pending.pop(key, None)
        expired_scopes = [key for key, until in self._allow_all.items() if until <= current]
        for key in expired_scopes:
            self._allow_all.pop(key, None)

    def _record(self, action: str, decision: PermissionDecision, outcome: str | None) -> None:
        if self._audit is None:
            return
        self._audit(PermissionAuditRecord(
            action=action,
            request_id=decision.request_id,
            session_key=decision.session_key,
            scope=decision.scope,
            decision=outcome,
            ts=time.time(),
        ))

    def _new_id(self) -> str:
        request_id = self._id_factory()
        if not isinstance(request_id, str) or not request_id.strip() or ":" in request_id:
            raise PermissionGateError("permission id factory returned an invalid id")
        if request_id in self._pending:
            raise PermissionGateError("permission id collision")
        return request_id

    @classmethod
    def _parse_action(cls, action: str) -> tuple[str, str]:
        if not isinstance(action, str):
            raise PermissionGateError("permission action must be text")
        parts = action.split(":")
        if len(parts) != 3 or parts[0] != "perm" or not parts[1] or parts[2] not in cls._DECISIONS:
            raise PermissionGateError("permission action is invalid")
        return parts[1], parts[2]

    @staticmethod
    def _validate_context(session_key: str, scope: str) -> None:
        if not isinstance(session_key, str) or not session_key.strip() or "\x00" in session_key:
            raise PermissionGateError("session_key is invalid")
        if not isinstance(scope, str) or not scope.strip() or "\x00" in scope:
            raise PermissionGateError("permission scope is invalid")

    @classmethod
    def _safe_prompt(cls, prompt: str, scope: str) -> str:
        text = prompt if isinstance(prompt, str) and prompt.strip() else f"Agent requests permission for {scope}"
        text = cls._SAFE_TEXT.sub("[redacted]", text)
        return text[:1000]
