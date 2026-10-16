"""Per-session event journal for Bridge protocol v2 ``seq`` / ``resume``.

Protocol v2 is opt-in: a client that lists ``seq`` in ``register.capabilities``
gets a monotonically increasing ``seq`` on every Host -> App event that carries a
``session_key``. After a reconnect it sends ``resume`` with the last ``seq`` it
applied and the Host replays what it missed from this journal, or answers
``resync_required`` when the gap is outside the retained window (or the Host
restarted, which changes ``epoch``). Clients that do not declare the capability
(Flutter 0.1.206) never see ``seq`` and never send ``resume``.
"""

from __future__ import annotations

import secrets
import threading
from collections import deque
from collections.abc import Iterable, Mapping
from typing import Callable, Any

PROTOCOL_VERSION = 2
# Capabilities this Host can offer when the client asks for them.
HOST_V2_CAPABILITIES = ("seq", "resume", "session_status")


def negotiate(client_capabilities: Any) -> tuple[str, ...]:
    """Return the v2 capabilities both sides support, in a stable order."""
    if not isinstance(client_capabilities, (list, tuple)):
        return ()
    declared = {item for item in client_capabilities if isinstance(item, str)}
    return tuple(cap for cap in HOST_V2_CAPABILITIES if cap in declared)


def register_ack(client_capabilities: Any, *, epoch: str) -> dict[str, Any]:
    """Build ``register_ack``; v2 fields only appear for v2 clients."""
    ack: dict[str, Any] = {"type": "register_ack", "ok": True, "error": ""}
    agreed = negotiate(client_capabilities)
    if agreed:
        ack["protocol"] = PROTOCOL_VERSION
        ack["capabilities"] = list(agreed)
        ack["epoch"] = epoch
    return ack


class SessionJournal:
    """Thread-safe ring buffer of recent events, one sequence per session_key."""

    def __init__(
        self,
        *,
        max_events_per_session: int = 1000,
        max_sessions: int = 256,
        observer: "Callable[[Mapping[str, Any]], None] | None" = None,
    ) -> None:
        if max_events_per_session <= 0 or max_sessions <= 0:
            raise ValueError("journal limits must be positive")
        self.epoch = secrets.token_hex(6)
        self._max_events = max_events_per_session
        self._max_sessions = max_sessions
        self._events: dict[str, deque[dict[str, Any]]] = {}
        self._last_seq: dict[str, int] = {}
        self._lock = threading.Lock()
        self._observer = observer

    def record(self, event: Mapping[str, Any]) -> dict[str, Any]:
        """Return a copy of ``event`` stamped with the next ``seq``.

        Events without a ``session_key`` (pong, register_ack, connection-level
        errors) are not journaled and are returned unchanged.
        """
        stamped = dict(event)
        session_key = stamped.get("session_key")
        if not isinstance(session_key, str) or not session_key:
            return stamped
        stamped.pop("seq", None)
        stamped.pop("replayed", None)
        with self._lock:
            seq = self._last_seq.get(session_key, 0) + 1
            self._last_seq[session_key] = seq
            stamped["seq"] = seq
            ring = self._events.get(session_key)
            if ring is None:
                self._evict_if_full()
                ring = deque(maxlen=self._max_events)
                self._events[session_key] = ring
            ring.append(dict(stamped))
        if self._observer is not None:
            try:
                self._observer(stamped)
            except Exception:  # noqa: BLE001 - observers must never break delivery
                pass
        return stamped

    def last_seq(self, session_key: str) -> int:
        with self._lock:
            return self._last_seq.get(session_key, 0)

    def replay(self, session_key: str, after_seq: int, *, epoch: str | None = None) -> list[dict[str, Any]] | None:
        """Events with ``seq > after_seq``; ``None`` means the client must resync."""
        if epoch is not None and epoch != self.epoch:
            return None
        with self._lock:
            last = self._last_seq.get(session_key, 0)
            if after_seq > last:
                # Client is ahead of us: a Host restart without epoch, or a bug.
                return None
            if after_seq == last:
                return []
            ring = self._events.get(session_key)
            if not ring:
                return None
            oldest = ring[0]["seq"]
            if after_seq < oldest - 1:
                return None
            return [dict(item, replayed=True) for item in ring if item["seq"] > after_seq]

    def forget(self, session_key: str) -> None:
        with self._lock:
            self._events.pop(session_key, None)
            self._last_seq.pop(session_key, None)

    def sessions(self) -> Iterable[str]:
        with self._lock:
            return tuple(self._last_seq)

    def _evict_if_full(self) -> None:
        while len(self._events) >= self._max_sessions:
            oldest = next(iter(self._events))
            self._events.pop(oldest, None)
            # Keep the counter so seq never goes backwards for that session;
            # a later resume will get resync_required (empty ring).


def handle_resume(journal: SessionJournal, message: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Answer a v2 ``resume`` request: replayed events then ``resume_ack``."""
    session_key = message.get("session_key")
    after = message.get("after_seq", 0)
    epoch = message.get("epoch")
    if not isinstance(session_key, str) or not session_key:
        return [{"type": "error", "error": "invalid_resume", "error_code": "invalid_resume"}]
    if isinstance(after, bool) or not isinstance(after, int) or after < 0:
        return [{
            "type": "error", "session_key": session_key,
            "error": "invalid_resume", "error_code": "invalid_resume",
        }]
    events = journal.replay(session_key, after, epoch=epoch if isinstance(epoch, str) else None)
    last = journal.last_seq(session_key)
    if events is None:
        return [{
            "type": "resync_required",
            "session_key": session_key,
            "last_seq": last,
            "epoch": journal.epoch,
        }]
    return [*events, {
        "type": "resume_ack",
        "ok": True,
        "session_key": session_key,
        "last_seq": last,
        "replayed": len(events),
        "epoch": journal.epoch,
    }]
