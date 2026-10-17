"""Read-only feeds for the App's Activity / Logs / Audit pages.

* ActivityFeed  - ring buffer fed by the Bridge journal (one line per notable event).
* RingLogHandler - keeps recent Host log records in memory (redacted).
* read_audit_tail - newest permission decisions from the JSONL audit store.

Nothing here can alter delivery: the journal swallows observer errors.
"""
from __future__ import annotations

import collections
import json
import logging
import os
import re
import threading
import time
import uuid
from typing import Any, Callable, Mapping

_SECRET = re.compile(r"(bearer\s+|token=|api[_-]?key\s*[:=]|password\s*[:=])\S+", re.IGNORECASE)


def redact(text: str, limit: int = 300) -> str:
    text = _SECRET.sub(lambda m: m.group(1) + "***", str(text))
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _combine(*observers: Callable[[Mapping[str, Any]], None]) -> Callable[[Mapping[str, Any]], None]:
    def observe(event: Mapping[str, Any]) -> None:
        for fn in observers:
            try:
                fn(event)
            except Exception:  # noqa: BLE001 - one observer must not starve the next
                pass
    return observe


combine_observers = _combine


class ActivityFeed:
    def __init__(self, *, clock: Callable[[], float] = time.time, max_events: int = 300) -> None:
        self._clock = clock
        self._lock = threading.Lock()
        self._events: collections.deque[dict[str, Any]] = collections.deque(maxlen=max_events)

    def add(self, kind: str, summary: str, *, source: str = "host", level: str = "info", session_key: str | None = None) -> None:
        event = {
            "id": "act-" + uuid.uuid4().hex[:10], "ts": self._clock(), "kind": kind,
            "summary": redact(summary, 200), "source": source, "level": level,
        }
        if session_key:
            event["session_key"] = session_key
        with self._lock:
            self._events.append(event)

    def observe(self, event: Mapping[str, Any]) -> None:
        kind = event.get("type")
        key = event.get("session_key") if isinstance(event.get("session_key"), str) else None
        if kind == "run_done":
            status = str(event.get("status") or "done")
            self.add("run." + status, f"运行结束（{status}）", source="agent", level="info" if status in {"completed", "done", "ok"} else "warn", session_key=key)
        elif kind in {"buttons", "card"}:
            text = event.get("content") or event.get("title") or "请求权限"
            self.add("permission.requested", str(text), source="permission", level="warn", session_key=key)
        elif kind == "reply" and event.get("error"):
            self.add("agent.error", str(event.get("content") or "error"), source="agent", level="error", session_key=key)
        elif kind == "tool_call":
            name = event.get("name") or event.get("tool") or "tool"
            self.add("tool.call", f"调用工具 {name}", source="agent", session_key=key)

    def list(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._lock:
            items = list(self._events)
        items.reverse()
        return items[: max(1, min(int(limit), 300))]


class RingLogHandler(logging.Handler):
    def __init__(self, capacity: int = 500, *, clock: Callable[[], float] = time.time) -> None:
        super().__init__(level=logging.INFO)
        self._clock = clock
        self._records: collections.deque[dict[str, Any]] = collections.deque(maxlen=capacity)
        self._ring_lock = threading.Lock()

    def emit(self, record: logging.LogRecord) -> None:
        try:
            item = {
                "ts": record.created, "level": record.levelname.lower().replace("warning", "warn"),
                "message": redact(record.getMessage(), 500), "source": record.name,
            }
        except Exception:  # noqa: BLE001
            return
        with self._ring_lock:
            self._records.append(item)

    def list(self, limit: int = 80, level: str = "", source: str = "") -> list[dict[str, Any]]:
        with self._ring_lock:
            items = list(self._records)
        if level:
            items = [x for x in items if x["level"] == level.lower()]
        if source:
            items = [x for x in items if source.lower() in x["source"].lower()]
        items = items[-max(1, min(int(limit), 200)):]
        items.reverse()
        return items


def read_audit_tail(path: str | None, limit: int = 100, *, max_bytes: int = 256 * 1024) -> list[dict[str, Any]]:
    if not path:
        return []
    try:
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(path, flags)
    except OSError:
        return []
    try:
        size = os.fstat(fd).st_size
        start = max(0, size - max_bytes)
        os.lseek(fd, start, os.SEEK_SET)
        chunk = b""
        while len(chunk) < size - start:
            part = os.read(fd, 65536)
            if not part:
                break
            chunk += part
    finally:
        os.close(fd)
    lines = chunk.decode("utf-8", "replace").splitlines()
    if start > 0 and lines:
        lines = lines[1:]  # first line may be partial
    out: list[dict[str, Any]] = []
    for line in reversed(lines):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            out.append({k: rec.get(k) for k in ("action", "request_id", "session_key", "scope", "decision", "ts")})
        if len(out) >= max(1, min(int(limit), 500)):
            break
    return out
