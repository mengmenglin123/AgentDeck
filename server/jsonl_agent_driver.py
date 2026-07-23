"""Translate a bounded JSONL agent stream into HuanHermes Bridge events.

This driver is deliberately format-neutral: it defines a small host-owned
fixture format instead of claiming compatibility with a Claude Code, Codex,
or Hermes private output stream. The host supplies session identity and
reply context; values from agent stdout cannot override either one.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Iterable


@dataclass(frozen=True)
class DriverConfig:
    max_line_bytes: int = 256 * 1024
    max_buffer_bytes: int = 512 * 1024

    def __post_init__(self) -> None:
        if self.max_line_bytes <= 0:
            raise ValueError("max_line_bytes must be positive")
        if self.max_buffer_bytes < self.max_line_bytes:
            raise ValueError("max_buffer_bytes must be at least max_line_bytes")


class JsonlAgentDriver:
    """Parse fixture JSONL and emit safe, protocol-shaped event dictionaries."""

    _TEXT_EVENTS = {"text_delta", "reply_stream"}

    def __init__(
        self,
        session_key: str,
        *,
        reply_ctx: str | None = None,
        config: DriverConfig = DriverConfig(),
    ) -> None:
        if not session_key.strip() or "\x00" in session_key:
            raise ValueError("session_key must be non-empty and NUL-free")
        if reply_ctx is not None and "\x00" in reply_ctx:
            raise ValueError("reply_ctx must not contain NUL bytes")
        self.session_key = session_key
        self.reply_ctx = reply_ctx
        self.config = config
        self._buffer = bytearray()
        self._closed = False
        self._line_number = 0

    @property
    def buffered_bytes(self) -> int:
        return len(self._buffer)

    def feed(self, data: bytes) -> list[dict[str, Any]]:
        """Consume available stdout bytes and return complete Bridge events."""
        if self._closed:
            raise RuntimeError("driver is closed")
        if not isinstance(data, bytes):
            raise TypeError("data must be bytes")
        if data:
            self._buffer.extend(data)
        return self._drain_lines()

    def finish(self) -> list[dict[str, Any]]:
        """Flush the final unterminated line and reject incomplete garbage."""
        if self._closed:
            return []
        self._closed = True
        if not self._buffer:
            return []
        line = bytes(self._buffer)
        self._buffer.clear()
        self._line_number += 1
        if len(line) > self.config.max_line_bytes:
            return [self._error("line_too_large", self._line_number)]
        return [self._decode_line(line, self._line_number)]

    def _drain_lines(self) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        while True:
            try:
                newline = self._buffer.index(10)
            except ValueError:
                break
            line = bytes(self._buffer[:newline])
            del self._buffer[: newline + 1]
            self._line_number += 1
            if line.endswith(b"\r"):
                line = line[:-1]
            if len(line) > self.config.max_line_bytes:
                events.append(self._error("line_too_large", self._line_number))
                continue
            if line.strip():
                events.append(self._decode_line(line, self._line_number))

        if len(self._buffer) > self.config.max_buffer_bytes:
            self._buffer.clear()
            events.append(self._error("buffer_too_large"))
        return events

    def _decode_line(self, line: bytes, line_number: int) -> dict[str, Any]:
        try:
            value = json.loads(line.decode("utf-8", errors="replace"))
        except json.JSONDecodeError:
            return self._error("malformed_json", line_number)
        if not isinstance(value, dict):
            return self._error("event_not_object", line_number)
        return self._map_event(value, line_number)

    def _map_event(self, value: dict[str, Any], line_number: int) -> dict[str, Any]:
        event_type = value.get("type")
        if not isinstance(event_type, str) or not event_type.strip():
            return self._error("missing_type", line_number)

        if event_type in self._TEXT_EVENTS:
            event = self._base("reply_stream")
            event["delta"] = self._text(value, "text", "delta", "content")
            event["done"] = bool(value.get("done", False))
            if isinstance(value.get("full_text"), str):
                event["full_text"] = value["full_text"]
            return self._copy_safe_metadata(
                event,
                value,
                ("done", "delta", "text", "content", "full_text"),
            )

        if event_type == "thinking":
            event = self._base("thinking")
            event["content"] = self._text(value, "content", "text")
            return self._copy_safe_metadata(event, value, ("content", "text"))

        if event_type == "tool_call":
            event = self._base("tool_call")
            event["name"] = self._text(value, "name") or "tool"
            event["input"] = value.get("input", "")
            return self._copy_safe_metadata(event, value, ("name", "input"))

        if event_type == "tool_result":
            event = self._base("tool_result")
            event["name"] = self._text(value, "name") or "tool"
            event["output"] = value.get("output", value.get("content", ""))
            return self._copy_safe_metadata(event, value, ("name", "output", "content"))

        if event_type == "permission":
            event = self._base("buttons")
            event["content"] = self._text(value, "content", "text", "prompt") or "Permission required"
            buttons = value.get("buttons")
            event["buttons"] = buttons if isinstance(buttons, list) else []
            return self._copy_safe_metadata(
                event,
                value,
                ("content", "text", "prompt", "buttons"),
            )

        if event_type == "done":
            event = self._base("run_done")
            event["status"] = value.get("status") if isinstance(value.get("status"), str) else "completed"
            if isinstance(value.get("content"), str):
                event["content"] = value["content"]
            return self._copy_safe_metadata(event, value, ("status", "content"))

        if event_type == "error":
            event = self._base("reply")
            event["content"] = self._text(value, "message", "content", "error") or "agent error"
            event["error"] = True
            return self._copy_safe_metadata(event, value, ("message", "content", "error"))

        return self._error("unsupported_event", line_number, event_type)

    def _base(self, event_type: str) -> dict[str, Any]:
        event: dict[str, Any] = {"type": event_type, "session_key": self.session_key}
        if self.reply_ctx is not None:
            event["reply_ctx"] = self.reply_ctx
        return event

    def _copy_safe_metadata(
        self,
        event: dict[str, Any],
        source: dict[str, Any],
        excluded: Iterable[str],
    ) -> dict[str, Any]:
        excluded_set = set(excluded) | {"type", "session_key", "reply_ctx"}
        for key, value in source.items():
            if key not in excluded_set and isinstance(key, str):
                event[key] = value
        return event

    @staticmethod
    def _text(source: dict[str, Any], *keys: str) -> str:
        for key in keys:
            value = source.get(key)
            if isinstance(value, str):
                return value
        return ""

    def _error(
        self,
        code: str,
        line_number: int | None = None,
        event_type: str | None = None,
    ) -> dict[str, Any]:
        event = self._base("reply")
        event.update({"content": "Agent output rejected", "error": True, "error_code": code})
        if line_number is not None:
            event["line"] = line_number
        if event_type is not None:
            event["event_type"] = event_type
        return event
