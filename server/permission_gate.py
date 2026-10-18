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
    kind: str | None = None
    #: Free-text feedback ("keep planning: …") from a plan card; never logged.
    text: str | None = None
    #: AskUserQuestion answers: question key -> chosen option labels.
    answers: dict | None = None


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
    prompt: str = ""
    buttons: tuple = ()
    kind: str | None = None
    questions: tuple = ()


AuditSink = Callable[[PermissionAuditRecord], None]
Clock = Callable[[], float]
IdFactory = Callable[[], str]


class PermissionGate:
    """Issue and consume short-lived permission challenges on the Host."""

    _DECISIONS = {"allow", "deny", "allow_all", "accept", "accept_clear", "keep", "submit"}
    #: Card kinds (protocol v2 ``plan_cards``) and the decisions each accepts.
    _KIND_DECISIONS = {
        None: {"allow", "deny", "allow_all"},
        "plan": {"accept", "accept_clear", "keep", "deny"},
        "question": {"submit", "deny"},
    }
    MAX_TEXT = 4000
    MAX_QUESTIONS = 6
    MAX_OPTIONS = 8
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
        kind: str | None = None,
        questions: object = None,
    ) -> dict[str, object] | PermissionDecision:
        self._validate_context(session_key, scope)
        if kind not in self._KIND_DECISIONS:
            kind = None
        request_id = self._new_id()
        now = self._clock()
        allowed_until = self._allow_all.get((session_key, scope))
        # "Allow all" only covers tool permissions, never plans or questions.
        if kind is None and allowed_until is not None and allowed_until > now:
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
        # Plans are long Markdown; tool prompts stay short.
        content = self._safe_prompt(prompt, scope, limit=12000 if kind == "plan" else 1000)
        safe_questions = self._safe_questions(questions) if kind == "question" else ()
        if kind == "plan":
            buttons = [[
                {"text": "Accept", "data": f"perm:{request_id}:accept"},
                {"text": "Accept & clear context", "data": f"perm:{request_id}:accept_clear"},
                {"text": "Keep planning", "data": f"perm:{request_id}:keep"},
            ]]
        elif kind == "question":
            buttons = [[
                {"text": "Submit", "data": f"perm:{request_id}:submit"},
                {"text": "Skip", "data": f"perm:{request_id}:deny"},
            ]]
        else:
            buttons = [[
                {"text": "Allow", "data": f"perm:{request_id}:allow"},
                {"text": "Allow all", "data": f"perm:{request_id}:allow_all"},
                {"text": "Deny", "data": f"perm:{request_id}:deny"},
            ]]
        pending = _PendingPermission(
            request_id=request_id,
            session_key=session_key,
            reply_ctx=reply_ctx,
            scope=scope,
            expires_at=now + self.ttl_seconds,
            prompt=content,
            buttons=tuple(tuple(dict(b) for b in row) for row in buttons),
            kind=kind,
            questions=safe_questions,
        )
        self._record(
            "permission.requested",
            PermissionDecision(request_id, session_key, reply_ctx, scope, "pending"),
            None,
        )
        self._pending[request_id] = pending
        card: dict[str, object] = {
            "type": "card",
            "session_key": session_key,
            "reply_ctx": reply_ctx,
            "permission_id": request_id,
            "scope": scope,
            "content": content,
            "buttons": buttons,
        }
        if kind is not None:
            card["kind"] = kind
        if safe_questions:
            card["questions"] = [dict(q) for q in safe_questions]
        return card

    def pending_for(self, session_key: str) -> list[dict[str, object]]:
        """Pending, unexpired challenges for one session (oldest first)."""
        self._expire()
        return [
            {
                "id": p.request_id,
                "prompt": p.prompt,
                "scope": p.scope,
                "reply_ctx": p.reply_ctx,
                "buttons": [[dict(b) for b in row] for row in p.buttons],
                **({"kind": p.kind} if p.kind else {}),
                **({"questions": [dict(q) for q in p.questions]} if p.questions else {}),
            }
            for p in self._pending.values()
            if p.session_key == session_key
        ]

    def decide(
        self,
        *,
        session_key: str,
        reply_ctx: str | None,
        action: str,
        text: object = None,
        answers: object = None,
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
        if decision_name not in self._KIND_DECISIONS[pending.kind]:
            raise PermissionGateError("decision does not fit this card")
        decision = PermissionDecision(
            request_id=request_id,
            session_key=session_key,
            reply_ctx=reply_ctx,
            scope=pending.scope,
            decision=decision_name,
            kind=pending.kind,
            text=self._safe_feedback(text) if decision_name in {"keep", "submit"} else None,
            answers=self._safe_answers(answers, pending.questions) if decision_name == "submit" else None,
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

    @classmethod
    def _safe_feedback(cls, text: object) -> str | None:
        if not isinstance(text, str) or not text.strip():
            return None
        return text.replace("\x00", "")[: cls.MAX_TEXT]

    @classmethod
    def _safe_questions(cls, raw: object) -> tuple:
        if not isinstance(raw, list):
            return ()
        out = []
        for i, q in enumerate(raw[: cls.MAX_QUESTIONS]):
            if not isinstance(q, dict) or not isinstance(q.get("question"), str):
                continue
            options = []
            for o in (q.get("options") or [])[: cls.MAX_OPTIONS]:
                if isinstance(o, dict) and isinstance(o.get("label"), str):
                    opt = {"label": o["label"][:120]}
                    if isinstance(o.get("description"), str):
                        opt["description"] = o["description"][:300]
                    options.append(opt)
            item = {
                "id": str(q.get("id") or i),
                "question": q["question"][:500],
                "multi_select": bool(q.get("multi_select") or q.get("multiSelect")),
                "options": options,
            }
            if isinstance(q.get("header"), str):
                item["header"] = q["header"][:40]
            out.append(item)
        return tuple(out)

    @classmethod
    def _safe_answers(cls, raw: object, questions: tuple) -> dict:
        if not isinstance(raw, dict):
            return {}
        by_id = {q["id"]: q for q in questions}
        out: dict[str, list[str]] = {}
        for key, value in raw.items():
            q = by_id.get(str(key))
            if q is None:
                continue
            values = value if isinstance(value, list) else [value]
            labels = [v[:500] for v in values if isinstance(v, str) and v.strip()]
            if not q["multi_select"]:
                labels = labels[:1]
            if labels:
                out[q["id"]] = labels
        return out

    @staticmethod
    def _validate_context(session_key: str, scope: str) -> None:
        if not isinstance(session_key, str) or not session_key.strip() or "\x00" in session_key:
            raise PermissionGateError("session_key is invalid")
        if not isinstance(scope, str) or not scope.strip() or "\x00" in scope:
            raise PermissionGateError("permission scope is invalid")

    @classmethod
    def _safe_prompt(cls, prompt: str, scope: str, limit: int = 1000) -> str:
        text = prompt if isinstance(prompt, str) and prompt.strip() else f"Agent requests permission for {scope}"
        text = cls._SAFE_TEXT.sub("[redacted]", text)
        return text[:limit]
