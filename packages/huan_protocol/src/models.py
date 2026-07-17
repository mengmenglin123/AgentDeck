"""Protocol DTOs and transcript reducer (UI-agnostic)."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional
import time
import uuid


class BridgeErrors:
    AUTH = "auth"
    DISCONNECTED = "disconnected"
    PROTOCOL = "protocol"
    AGENT = "agent"


class AuthError(Exception):
    pass


class DisconnectedError(Exception):
    pass


class ProtocolError(Exception):
    pass


def new_id(prefix: str = "id") -> str:
    return f"{prefix}-{uuid.uuid4().hex[:12]}"


def session_key(device_id: str, conversation_id: str) -> str:
    return f"huan:{device_id}:{conversation_id}"


@dataclass
class ConnectionConfig:
    host: str = "127.0.0.1"
    bridge_port: int = 9810
    mgmt_port: int = 9820
    bridge_token: str = "dev-bridge-token-change-me"
    mgmt_token: str = "dev-mgmt-token-change-me"
    use_tls: bool = False
    platform_name: str = "huanhermes-app"
    device_id: str = field(default_factory=lambda: new_id("dev"))

    @property
    def bridge_ws_url(self) -> str:
        scheme = "wss" if self.use_tls else "ws"
        return f"{scheme}://{self.host}:{self.bridge_port}/bridge/ws?token={self.bridge_token}"

    @property
    def mgmt_base_url(self) -> str:
        scheme = "https" if self.use_tls else "http"
        return f"{scheme}://{self.host}:{self.mgmt_port}/api/v1"


class EventKind(str, Enum):
    USER = "user"
    ASSISTANT_DELTA = "assistant_delta"
    ASSISTANT_FINAL = "assistant_final"
    THINKING = "thinking"
    TOOL_CALL = "tool_call"
    TOOL_RESULT = "tool_result"
    PERMISSION = "permission"
    SYSTEM = "system"
    ERROR = "error"
    RUN_DONE = "run_done"


@dataclass
class TranscriptEvent:
    kind: EventKind
    text: str = ""
    meta: Dict[str, Any] = field(default_factory=dict)
    ts: float = field(default_factory=time.time)


@dataclass
class TranscriptMessage:
    role: str  # user | assistant | system | tool | permission
    content: str
    streaming: bool = False
    meta: Dict[str, Any] = field(default_factory=dict)


class TranscriptReducer:
    """Reduce bridge host events into a list of UI messages."""

    def __init__(self) -> None:
        self.messages: List[TranscriptMessage] = []
        self._streaming_idx: Optional[int] = None

    def reset(self) -> None:
        self.messages.clear()
        self._streaming_idx = None

    def apply(self, event: TranscriptEvent) -> List[TranscriptMessage]:
        k = event.kind
        if k == EventKind.USER:
            self._streaming_idx = None
            self.messages.append(TranscriptMessage("user", event.text, meta=event.meta))
        elif k == EventKind.ASSISTANT_DELTA:
            if self._streaming_idx is None:
                self.messages.append(
                    TranscriptMessage("assistant", event.text, streaming=True, meta=event.meta)
                )
                self._streaming_idx = len(self.messages) - 1
            else:
                msg = self.messages[self._streaming_idx]
                # prefer full_text if provided
                full = event.meta.get("full_text")
                if full is not None:
                    msg.content = full
                else:
                    msg.content += event.text
                msg.streaming = not event.meta.get("done", False)
                if event.meta.get("done"):
                    self._streaming_idx = None
        elif k == EventKind.ASSISTANT_FINAL:
            if self._streaming_idx is not None:
                self.messages[self._streaming_idx].content = event.text
                self.messages[self._streaming_idx].streaming = False
                self._streaming_idx = None
            else:
                self.messages.append(TranscriptMessage("assistant", event.text, meta=event.meta))
        elif k == EventKind.THINKING:
            self.messages.append(TranscriptMessage("system", f"thinking: {event.text}", meta=event.meta))
        elif k == EventKind.TOOL_CALL:
            self.messages.append(TranscriptMessage("tool", f"call: {event.text}", meta=event.meta))
        elif k == EventKind.TOOL_RESULT:
            self.messages.append(TranscriptMessage("tool", f"result: {event.text}", meta=event.meta))
        elif k == EventKind.PERMISSION:
            self.messages.append(
                TranscriptMessage("permission", event.text, meta=event.meta)
            )
        elif k == EventKind.ERROR:
            self.messages.append(TranscriptMessage("system", f"error: {event.text}", meta=event.meta))
        elif k == EventKind.RUN_DONE:
            if self._streaming_idx is not None:
                self.messages[self._streaming_idx].streaming = False
                self._streaming_idx = None
            self.messages.append(TranscriptMessage("system", event.text or "run done", meta=event.meta))
        else:
            self.messages.append(TranscriptMessage("system", event.text, meta=event.meta))
        return self.messages

    def apply_bridge_payload(self, payload: Dict[str, Any]) -> List[TranscriptMessage]:
        """Map raw bridge host JSON into reducer events."""
        t = payload.get("type")
        if t == "reply_stream":
            return self.apply(
                TranscriptEvent(
                    EventKind.ASSISTANT_DELTA,
                    text=payload.get("delta") or "",
                    meta={
                        "full_text": payload.get("full_text"),
                        "done": bool(payload.get("done")),
                        "session_key": payload.get("session_key"),
                        "reply_ctx": payload.get("reply_ctx"),
                    },
                )
            )
        if t == "reply":
            return self.apply(
                TranscriptEvent(
                    EventKind.ASSISTANT_FINAL,
                    text=payload.get("content") or "",
                    meta={
                        "session_key": payload.get("session_key"),
                        "reply_ctx": payload.get("reply_ctx"),
                        "format": payload.get("format"),
                    },
                )
            )
        if t == "buttons":
            return self.apply(
                TranscriptEvent(
                    EventKind.PERMISSION,
                    text=payload.get("content") or "Permission required",
                    meta={
                        "buttons": payload.get("buttons") or [],
                        "session_key": payload.get("session_key"),
                        "reply_ctx": payload.get("reply_ctx"),
                    },
                )
            )
        if t == "thinking":
            return self.apply(
                TranscriptEvent(
                    EventKind.THINKING,
                    text=payload.get("content") or payload.get("text") or "",
                    meta=payload,
                )
            )
        if t == "tool_call":
            name = payload.get("name") or "tool"
            inp = payload.get("input") or ""
            return self.apply(TranscriptEvent(EventKind.TOOL_CALL, text=f"{name} {inp}", meta=payload))
        if t == "tool_result":
            name = payload.get("name") or "tool"
            out = payload.get("output") or payload.get("content") or ""
            return self.apply(TranscriptEvent(EventKind.TOOL_RESULT, text=f"{name} -> {out}", meta=payload))
        if t == "run_done":
            return self.apply(
                TranscriptEvent(
                    EventKind.RUN_DONE,
                    text=payload.get("content") or "",
                    meta={"status": payload.get("status") or "completed", **{k: payload.get(k) for k in ("session_key", "reply_ctx")}},
                )
            )
        if t == "typing_start":
            return self.apply(TranscriptEvent(EventKind.SYSTEM, "typing…", meta=payload))
        if t == "typing_stop":
            return self.apply(TranscriptEvent(EventKind.SYSTEM, "typing stopped", meta=payload))
        if t == "register_ack":
            ok = payload.get("ok")
            return self.apply(
                TranscriptEvent(
                    EventKind.SYSTEM if ok else EventKind.ERROR,
                    "registered" if ok else (payload.get("error") or "register failed"),
                    meta=payload,
                )
            )
        return self.apply(TranscriptEvent(EventKind.SYSTEM, f"event:{t}", meta=payload))
