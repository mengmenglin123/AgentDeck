"""Minimal WebSocket Bridge client (Python stdlib)."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import socket
import ssl
import struct
import threading
import time
from typing import Any, Callable, Dict, Optional
from urllib.parse import urlparse

from .models import (
    AuthError,
    ConnectionConfig,
    DisconnectedError,
    ProtocolError,
    new_id,
)


OnMessage = Callable[[Dict[str, Any]], None]
OnError = Callable[[Exception], None]
OnClose = Callable[[], None]


class _WsConnection:
    """Very small RFC6455 client enough for text JSON frames."""

    def __init__(self, url: str, headers: Optional[Dict[str, str]] = None, timeout: float = 10.0):
        self.url = url
        self.headers = headers or {}
        self.timeout = timeout
        self.sock: Optional[socket.socket] = None
        self._closed = False

    def connect(self) -> None:
        u = urlparse(self.url)
        if u.scheme not in ("ws", "wss"):
            raise ProtocolError(f"unsupported scheme: {u.scheme}")
        host = u.hostname or "127.0.0.1"
        port = u.port or (443 if u.scheme == "wss" else 80)
        path = u.path or "/"
        if u.query:
            path = f"{path}?{u.query}"

        raw = socket.create_connection((host, port), timeout=self.timeout)
        if u.scheme == "wss":
            ctx = ssl.create_default_context()
            raw = ctx.wrap_socket(raw, server_hostname=host)
        self.sock = raw
        self.sock.settimeout(self.timeout)

        key = base64.b64encode(os.urandom(16)).decode("ascii")
        req = [
            f"GET {path} HTTP/1.1",
            f"Host: {host}:{port}",
            "Upgrade: websocket",
            "Connection: Upgrade",
            f"Sec-WebSocket-Key: {key}",
            "Sec-WebSocket-Version: 13",
        ]
        for hk, hv in self.headers.items():
            req.append(f"{hk}: {hv}")
        req.append("")
        req.append("")
        self.sock.sendall("\r\n".join(req).encode("utf-8"))

        # read response headers
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise DisconnectedError("handshake closed")
            data += chunk
        header, _rest = data.split(b"\r\n\r\n", 1)
        status_line = header.split(b"\r\n", 1)[0].decode("latin1", errors="replace")
        if "101" not in status_line:
            # surface body-ish for auth errors
            raise AuthError(f"websocket handshake failed: {status_line}")

        # leftover bytes after headers — for simplicity discard; server shouldn't send early
        # (real clients should buffer; mock waits for register)

    def send_text(self, text: str) -> None:
        if not self.sock or self._closed:
            raise DisconnectedError("not connected")
        payload = text.encode("utf-8")
        header = bytearray([0x81])  # FIN + text
        ln = len(payload)
        mask_bit = 0x80
        if ln < 126:
            header.append(mask_bit | ln)
        elif ln < (1 << 16):
            header.append(mask_bit | 126)
            header.extend(struct.pack("!H", ln))
        else:
            header.append(mask_bit | 127)
            header.extend(struct.pack("!Q", ln))
        mask = os.urandom(4)
        header.extend(mask)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + masked)

    def recv_text(self) -> str:
        if not self.sock or self._closed:
            raise DisconnectedError("not connected")
        # may block
        self.sock.settimeout(None)
        hdr = self._recv_exact(2)
        b1, b2 = hdr[0], hdr[1]
        opcode = b1 & 0x0F
        masked = (b2 & 0x80) != 0
        ln = b2 & 0x7F
        if ln == 126:
            ln = struct.unpack("!H", self._recv_exact(2))[0]
        elif ln == 127:
            ln = struct.unpack("!Q", self._recv_exact(8))[0]
        mask = self._recv_exact(4) if masked else b""
        payload = self._recv_exact(ln)
        if masked:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if opcode == 0x8:
            self._closed = True
            raise DisconnectedError("server closed")
        if opcode == 0x9:  # ping
            self._send_raw(0xA, payload)  # pong
            return self.recv_text()
        if opcode != 0x1:
            # ignore binary/continue for MVP
            return self.recv_text()
        return payload.decode("utf-8")

    def _send_raw(self, opcode: int, payload: bytes) -> None:
        assert self.sock
        header = bytearray([0x80 | opcode])
        ln = len(payload)
        mask_bit = 0x80
        if ln < 126:
            header.append(mask_bit | ln)
        elif ln < (1 << 16):
            header.append(mask_bit | 126)
            header.extend(struct.pack("!H", ln))
        else:
            header.append(mask_bit | 127)
            header.extend(struct.pack("!Q", ln))
        mask = os.urandom(4)
        header.extend(mask)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + masked)

    def _recv_exact(self, n: int) -> bytes:
        assert self.sock
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise DisconnectedError("socket closed")
            buf += chunk
        return buf

    def close(self) -> None:
        self._closed = True
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None


class BridgeClient:
    def __init__(
        self,
        config: Optional[ConnectionConfig] = None,
        on_message: Optional[OnMessage] = None,
        on_error: Optional[OnError] = None,
        on_close: Optional[OnClose] = None,
    ):
        self.config = config or ConnectionConfig()
        self.on_message = on_message
        self.on_error = on_error
        self.on_close = on_close
        self._ws: Optional[_WsConnection] = None
        self._reader: Optional[threading.Thread] = None
        self._heartbeat: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._registered = threading.Event()
        self._lock = threading.Lock()

    @property
    def connected(self) -> bool:
        return self._ws is not None and not self._stop.is_set()

    def connect(self, wait_register: bool = True, timeout: float = 10.0) -> None:
        self._stop.clear()
        self._registered.clear()
        headers = {
            "Authorization": f"Bearer {self.config.bridge_token}",
            "X-Bridge-Token": self.config.bridge_token,
        }
        # token also in query via config.bridge_ws_url
        # redact: never log full url with token in production callers
        ws = _WsConnection(self.config.bridge_ws_url, headers=headers, timeout=timeout)
        ws.connect()
        self._ws = ws
        self._reader = threading.Thread(target=self._read_loop, name="bridge-reader", daemon=True)
        self._reader.start()
        self.register()
        if wait_register and not self._registered.wait(timeout=timeout):
            raise ProtocolError("register_ack timeout")
        self._heartbeat = threading.Thread(target=self._heartbeat_loop, name="bridge-hb", daemon=True)
        self._heartbeat.start()

    def close(self) -> None:
        self._stop.set()
        if self._ws:
            self._ws.close()
            self._ws = None
        if self.on_close:
            self.on_close()

    def register(self) -> None:
        self.send(
            {
                "type": "register",
                "platform": self.config.platform_name,
                "capabilities": ["text", "buttons", "typing", "preview"],
                "metadata": {"version": "0.1.0", "device_id": self.config.device_id},
            }
        )

    def send_user_message(
        self,
        content: str,
        *,
        conversation_id: str,
        user_id: str = "user",
        user_name: str = "User",
        session_key_override: Optional[str] = None,
        images: Optional[list] = None,
        files: Optional[list] = None,
    ) -> Dict[str, str]:
        from .models import session_key

        sk = session_key_override or session_key(self.config.device_id, conversation_id)
        reply_ctx = new_id("ctx")
        msg_id = new_id("msg")
        self.send(
            {
                "type": "message",
                "msg_id": msg_id,
                "session_key": sk,
                "user_id": user_id,
                "user_name": user_name,
                "content": content,
                "reply_ctx": reply_ctx,
                "images": images or [],
                "files": files or [],
                "audio": None,
            }
        )
        return {"session_key": sk, "reply_ctx": reply_ctx, "msg_id": msg_id}

    def send_card_action(self, session_key: str, action: str, reply_ctx: str) -> None:
        self.send(
            {
                "type": "card_action",
                "session_key": session_key,
                "action": action,
                "reply_ctx": reply_ctx,
            }
        )

    def cancel(self, session_key: str, reply_ctx: str = "") -> None:
        self.send(
            {
                "type": "cancel",
                "session_key": session_key,
                "reply_ctx": reply_ctx or "",
            }
        )

    def ping(self) -> None:
        self.send({"type": "ping", "ts": int(time.time() * 1000)})

    def send(self, payload: Dict[str, Any]) -> None:
        with self._lock:
            if not self._ws:
                raise DisconnectedError("not connected")
            self._ws.send_text(json.dumps(payload, ensure_ascii=False))

    def _read_loop(self) -> None:
        assert self._ws
        try:
            while not self._stop.is_set():
                raw = self._ws.recv_text()
                try:
                    data = json.loads(raw)
                except json.JSONDecodeError as e:
                    if self.on_error:
                        self.on_error(ProtocolError(str(e)))
                    continue
                if data.get("type") == "register_ack":
                    if data.get("ok"):
                        self._registered.set()
                    else:
                        if self.on_error:
                            self.on_error(AuthError(data.get("error") or "register denied"))
                if data.get("type") == "pong":
                    continue
                if self.on_message:
                    self.on_message(data)
        except Exception as e:  # noqa: BLE001
            if not self._stop.is_set() and self.on_error:
                self.on_error(e)
        finally:
            self._stop.set()
            if self.on_close:
                self.on_close()

    def _heartbeat_loop(self) -> None:
        while not self._stop.wait(30.0):
            try:
                self.ping()
            except Exception as e:  # noqa: BLE001
                if self.on_error:
                    self.on_error(e)
                break
