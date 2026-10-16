"""Lightweight per-session activity summary fed by the Bridge journal.

Gives the Management catalog an optional overview (last message preview,
updated_at, running) without owning Agent state. Pure observer: it never
alters events and any failure inside it is swallowed by the journal.
"""

from __future__ import annotations

import threading
import time
from typing import Any, Callable, Mapping

PREVIEW_LIMIT = 160


class SessionActivity:
    def __init__(self, *, clock: Callable[[], float] = time.time, max_sessions: int = 512) -> None:
        self._clock = clock
        self._max = max_sessions
        self._lock = threading.Lock()
        self._state: dict[str, dict[str, Any]] = {}

    def observe(self, event: Mapping[str, Any]) -> None:
        key = event.get("session_key")
        if not isinstance(key, str) or not key:
            return
        kind = event.get("type")
        with self._lock:
            state = self._state.get(key)
            if state is None:
                if len(self._state) >= self._max:
                    oldest = min(self._state, key=lambda k: self._state[k]["updated_at"])
                    self._state.pop(oldest, None)
                state = {"preview": "", "buffer": "", "running": False, "updated_at": self._clock()}
                self._state[key] = state
            state["updated_at"] = self._clock()
            if kind == "reply_stream":
                state["running"] = True
                full = event.get("full_text")
                if isinstance(full, str):
                    state["buffer"] = full
                else:
                    state["buffer"] = (state["buffer"] + str(event.get("delta") or ""))[-4000:]
                state["preview"] = _clip(state["buffer"])
            elif kind == "reply":
                content = event.get("content")
                if isinstance(content, str) and content.strip():
                    state["preview"] = _clip(content)
            elif kind in {"thinking", "tool_call", "tool_result", "buttons", "card"}:
                state["running"] = True
            elif kind == "run_done":
                state["running"] = False
                state["buffer"] = ""

    def mark_user_message(self, session_key: str, text: str) -> None:
        with self._lock:
            state = self._state.setdefault(session_key, {"preview": "", "buffer": "", "running": False, "updated_at": 0.0})
            state["preview"] = _clip(text)
            state["buffer"] = ""
            state["running"] = True
            state["updated_at"] = self._clock()

    def get(self, session_key: str) -> dict[str, Any] | None:
        with self._lock:
            state = self._state.get(session_key)
            if state is None:
                return None
            return {"preview": state["preview"], "running": state["running"], "updated_at": state["updated_at"]}

    def forget(self, session_key: str) -> None:
        with self._lock:
            self._state.pop(session_key, None)


def _clip(text: str) -> str:
    flat = " ".join(text.split())
    if len(flat) <= PREVIEW_LIMIT:
        return flat
    return flat[: PREVIEW_LIMIT - 1] + "…"
