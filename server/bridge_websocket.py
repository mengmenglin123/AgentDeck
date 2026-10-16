"""Minimal authenticated WebSocket transport for a production HuanHermes Host."""

from __future__ import annotations

import base64
import hashlib
import json
import select
import socket
import struct
import threading
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import parse_qs, urlparse

from bridge_agent_loop import AgentBridgeLoop
from session_journal import SessionJournal, handle_resume, negotiate, register_ack
from terminal_bridge_loop import TerminalBridgeLoop
from token_auth import tokens_match


class WebSocketProtocolError(ConnectionError):
    pass


@dataclass(frozen=True)
class WebSocketConfig:
    token: str
    path: str = "/bridge/ws"
    max_header_bytes: int = 16 * 1024
    max_frame_bytes: int = 1024 * 1024
    poll_interval: float = 0.05
    # Protocol v2: how long an Agent session outlives a dropped connection when
    # the client declared ``resume``. Legacy clients keep close-on-disconnect.
    detach_grace_seconds: float = 120.0

    def __post_init__(self) -> None:
        if self.detach_grace_seconds < 0:
            raise ValueError("detach_grace_seconds must not be negative")
        if not self.token:
            raise ValueError("token must not be empty")
        if not self.path.startswith("/"):
            raise ValueError("path must be absolute")
        if self.max_header_bytes <= 0 or self.max_frame_bytes <= 0:
            raise ValueError("size limits must be positive")
        if self.poll_interval <= 0:
            raise ValueError("poll_interval must be positive")


class BridgeWebSocketTransport:
    """Serve one authenticated WebSocket connection over an accepted socket."""

    _GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    def __init__(
        self,
        loop: AgentBridgeLoop,
        config: WebSocketConfig,
        *,
        terminal_loop: TerminalBridgeLoop | None = None,
        journal: SessionJournal | None = None,
        clock=time.monotonic,
    ) -> None:
        self.loop = loop
        self.config = config
        self.terminal_loop = terminal_loop
        self.journal = journal or SessionJournal()
        self._clock = clock
        # session_key -> deadline for Agent sessions whose v2 connection dropped.
        self._detached: dict[str, float] = {}
        self._detached_lock = threading.Lock()
        self._keeper: threading.Thread | None = None

    # -- protocol v2 helpers -------------------------------------------------

    def _emit(self, connection: socket.socket, event: dict[str, Any], caps: tuple[str, ...]) -> None:
        """Journal an Agent event and send it; only v2 clients see ``seq``."""
        stamped = self.journal.record(event)
        self._send_json(connection, stamped if "seq" in caps else event)

    def _claim(self, session_key: Any, owned: set[str]) -> None:
        if not isinstance(session_key, str):
            return
        with self._detached_lock:
            if self._detached.pop(session_key, None) is not None:
                owned.add(session_key)

    def _detach(self, session_keys: set[str]) -> None:
        deadline = self._clock() + self.config.detach_grace_seconds
        with self._detached_lock:
            for session_key in session_keys:
                self._detached[session_key] = deadline
            if self._keeper is None or not self._keeper.is_alive():
                self._keeper = threading.Thread(
                    target=self._keep_detached, name="huanhermes-detached", daemon=True,
                )
                self._keeper.start()

    def detached_sessions(self) -> tuple[str, ...]:
        with self._detached_lock:
            return tuple(self._detached)

    def _keep_detached(self) -> None:
        """Journal output of detached sessions so a resume can replay it."""
        while True:
            with self._detached_lock:
                if not self._detached:
                    self._keeper = None
                    return
                items = tuple(self._detached.items())
            now = self._clock()
            for session_key, deadline in items:
                # Hold the lock while polling so a concurrent claim + replay
                # can never miss an event journaled after the replay.
                with self._detached_lock:
                    if self._detached.get(session_key) != deadline:
                        continue  # claimed (or re-detached) meanwhile
                    if session_key not in self.loop.active_sessions or now >= deadline:
                        self._detached.pop(session_key, None)
                        if session_key in self.loop.active_sessions:
                            self.loop.close_session(session_key)
                        continue
                    for event in self.loop.poll(session_key):
                        self.journal.record(event)
            time.sleep(self.config.poll_interval)

    def _session_status(self, message: dict[str, Any]) -> dict[str, Any]:
        session_key = message.get("session_key")
        if not isinstance(session_key, str) or not session_key:
            return {"type": "error", "error": "invalid_session_status", "error_code": "invalid_session_status"}
        alive = session_key in self.loop.active_sessions
        has_run = getattr(self.loop, "has_active_run", None)
        running = bool(has_run(session_key)) if alive and callable(has_run) else alive
        return {
            "type": "session_status",
            "session_key": session_key,
            "alive": alive,
            "running": running,
            "last_seq": self.journal.last_seq(session_key),
            "epoch": self.journal.epoch,
        }

    def serve_connection(self, connection: socket.socket) -> None:
        registered = False
        caps: tuple[str, ...] = ()
        owned_sessions: set[str] = set()
        owned_terminal_sessions: set[str] = set()
        try:
            if not self._handshake(connection):
                return
            while True:
                if connection.fileno() < 0:
                    return
                try:
                    readable, _, _ = select.select(
                        [connection],
                        [],
                        [],
                        self.config.poll_interval,
                    )
                except (OSError, ValueError):
                    return
                if readable:
                    opcode, payload = self._recv_frame(connection)
                    if opcode == 0x8:
                        self._send_frame(connection, 0x8, payload[:125])
                        return
                    if opcode == 0x9:
                        self._send_frame(connection, 0xA, payload)
                    elif opcode == 0x1:
                        message = self._decode_message(payload)
                        message_type = message.get("type")
                        if message_type == "register":
                            registered = True
                            caps = negotiate(message.get("capabilities"))
                            self._send_json(
                                connection,
                                register_ack(message.get("capabilities"), epoch=self.journal.epoch),
                            )
                        elif not registered:
                            self._send_json(
                                connection,
                                {
                                    "type": "register_ack",
                                    "ok": False,
                                    "error": "send register first",
                                },
                            )
                        elif message_type == "resume" and "resume" in caps:
                                self._claim(message.get("session_key"), owned_sessions)
                                for event in handle_resume(self.journal, message):
                                    self._send_json(connection, event)
                        elif message_type == "session_status" and "session_status" in caps:
                                self._claim(message.get("session_key"), owned_sessions)
                                self._send_json(connection, self._session_status(message))
                        else:
                            session_key = message.get("session_key")
                            if message_type in {"message", "card_action", "cancel"} and "resume" in caps:
                                self._claim(session_key, owned_sessions)
                            if (
                                self.terminal_loop is not None
                                and isinstance(message_type, str)
                                and message_type.startswith("terminal_")
                            ):
                                was_active = (
                                    isinstance(session_key, str)
                                    and session_key in self.terminal_loop.active_sessions
                                )
                                if (
                                    was_active
                                    and isinstance(session_key, str)
                                    and session_key not in owned_terminal_sessions
                                ):
                                    if message_type == "terminal_open":
                                        event = {
                                            "type": "terminal_open_ack",
                                            "ok": False,
                                            "session_key": session_key,
                                            "stream_id": message.get("stream_id"),
                                            "error": "terminal_stream_in_use",
                                        }
                                    else:
                                        event = {
                                            "type": "terminal_ack",
                                            "ok": False,
                                            "session_key": session_key,
                                            "stream_id": message.get("stream_id"),
                                            "error": "terminal_stream_in_use",
                                        }
                                    self._send_json(connection, event)
                                    continue
                                for event in self.terminal_loop.handle(message):
                                    self._send_json(connection, event)
                                if (
                                    message_type == "terminal_open"
                                    and isinstance(session_key, str)
                                    and not was_active
                                    and session_key in self.terminal_loop.active_sessions
                                ):
                                    owned_terminal_sessions.add(session_key)
                            else:
                                was_active = (
                                    isinstance(session_key, str)
                                    and session_key in self.loop.active_sessions
                                )
                                if (
                                    message_type in {"message", "card_action"}
                                    and was_active
                                    and isinstance(session_key, str)
                                    and session_key not in owned_sessions
                                ):
                                    self._send_json(connection, {
                                        "type": "reply",
                                        "session_key": session_key,
                                        "content": "Agent session is owned by another connection",
                                        "error": True,
                                        "error_code": "session_in_use",
                                    })
                                    continue
                                for event in self.loop.handle(message):
                                    self._emit(connection, event, caps)
                                if (
                                    message_type == "message"
                                    and isinstance(session_key, str)
                                    and not was_active
                                    and session_key in self.loop.active_sessions
                                ):
                                    owned_sessions.add(session_key)
                if registered:
                    for session_key in tuple(owned_sessions):
                        if session_key not in self.loop.active_sessions:
                            owned_sessions.discard(session_key)
                            continue
                        for event in self.loop.poll(session_key):
                            self._emit(connection, event, caps)
                        if session_key not in self.loop.active_sessions:
                            owned_sessions.discard(session_key)
                    if self.terminal_loop is not None:
                        for session_key in tuple(owned_terminal_sessions):
                            if session_key not in self.terminal_loop.active_sessions:
                                owned_terminal_sessions.discard(session_key)
                                continue
                            for event in self.terminal_loop.poll(session_key):
                                self._send_json(connection, event)
                            if session_key not in self.terminal_loop.active_sessions:
                                owned_terminal_sessions.discard(session_key)
        except (ConnectionError, OSError, WebSocketProtocolError):
            return
        finally:
            live = {key for key in owned_sessions if key in self.loop.active_sessions}
            if live and "resume" in caps and self.config.detach_grace_seconds > 0:
                self._detach(live)
            else:
                for session_key in owned_sessions:
                    self.loop.close_session(session_key)
            if self.terminal_loop is not None:
                for session_key in owned_terminal_sessions:
                    self.terminal_loop.close_session(session_key)
            try:
                connection.close()
            except OSError:
                pass

    def _handshake(self, connection: socket.socket) -> bool:
        try:
            raw = self._read_headers(connection)
            request_line, headers = self._parse_headers(raw)
            method, target, version = request_line.split(" ", 2)
        except (ValueError, UnicodeError, ConnectionError):
            self._send_http_error(connection, 400, "Bad Request")
            return False

        parsed = urlparse(target)
        if method != "GET" or version != "HTTP/1.1" or parsed.path != self.config.path:
            self._send_http_error(connection, 404, "Not Found")
            return False
        if headers.get("upgrade", "").lower() != "websocket":
            self._send_http_error(connection, 400, "Bad Request")
            return False
        if "upgrade" not in headers.get("connection", "").lower():
            self._send_http_error(connection, 400, "Bad Request")
            return False
        if headers.get("sec-websocket-version") != "13":
            self._send_http_error(connection, 426, "Upgrade Required")
            return False

        token = self._extract_token(headers, parse_qs(parsed.query))
        if not tokens_match(token, self.config.token):
            self._send_http_error(connection, 401, "Unauthorized")
            return False

        key = headers.get("sec-websocket-key")
        if not self._valid_key(key):
            self._send_http_error(connection, 400, "Bad Request")
            return False
        accept = base64.b64encode(
            hashlib.sha1((key + self._GUID).encode("ascii")).digest()
        ).decode("ascii")
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n"
            "\r\n"
        )
        connection.sendall(response.encode("ascii"))
        return True

    def _read_headers(self, connection: socket.socket) -> bytes:
        data = bytearray()
        while b"\r\n\r\n" not in data:
            chunk = connection.recv(4096)
            if not chunk:
                raise ConnectionError("connection closed during handshake")
            data.extend(chunk)
            if len(data) > self.config.max_header_bytes:
                raise ValueError("request headers too large")
        head, remainder = bytes(data).split(b"\r\n\r\n", 1)
        if remainder:
            raise ValueError("pipelined websocket data is not supported")
        return head

    @staticmethod
    def _parse_headers(raw: bytes) -> tuple[str, dict[str, str]]:
        lines = raw.decode("latin1").split("\r\n")
        if not lines or not lines[0]:
            raise ValueError("missing request line")
        headers: dict[str, str] = {}
        for line in lines[1:]:
            if ":" not in line:
                raise ValueError("malformed header")
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()
        return lines[0], headers

    @staticmethod
    def _extract_token(headers: dict[str, str], query: dict[str, list[str]]) -> str | None:
        authorization = headers.get("authorization", "")
        if authorization.lower().startswith("bearer "):
            return authorization[7:].strip()
        header_token = headers.get("x-bridge-token")
        if header_token:
            return header_token.strip()
        values = query.get("token")
        return values[0] if values else None

    @staticmethod
    def _valid_key(key: str | None) -> bool:
        if not key:
            return False
        try:
            return len(base64.b64decode(key, validate=True)) == 16
        except (ValueError, base64.binascii.Error):
            return False

    def _recv_frame(self, connection: socket.socket) -> tuple[int, bytes]:
        first, second = self._recv_exact(connection, 2)
        final = bool(first & 0x80)
        opcode = first & 0x0F
        masked = bool(second & 0x80)
        length = second & 0x7F
        if not final:
            raise WebSocketProtocolError("fragmented frames are not supported")
        if not masked:
            raise WebSocketProtocolError("client frames must be masked")
        if length == 126:
            length = struct.unpack("!H", self._recv_exact(connection, 2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recv_exact(connection, 8))[0]
        if length > self.config.max_frame_bytes:
            raise WebSocketProtocolError("frame too large")
        if opcode >= 0x8 and length > 125:
            raise WebSocketProtocolError("control frame too large")
        mask = self._recv_exact(connection, 4)
        payload = self._recv_exact(connection, length)
        return opcode, bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))

    @staticmethod
    def _recv_exact(connection: socket.socket, length: int) -> bytes:
        data = bytearray()
        while len(data) < length:
            chunk = connection.recv(length - len(data))
            if not chunk:
                raise ConnectionError("connection closed")
            data.extend(chunk)
        return bytes(data)

    @staticmethod
    def _decode_message(payload: bytes) -> dict[str, Any]:
        try:
            value = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {"type": "invalid"}
        return value if isinstance(value, dict) else {"type": "invalid"}

    def _send_json(self, connection: socket.socket, value: dict[str, Any]) -> None:
        self._send_frame(
            connection,
            0x1,
            json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
        )

    @staticmethod
    def _send_frame(connection: socket.socket, opcode: int, payload: bytes) -> None:
        header = bytearray([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header.append(length)
        elif length < 1 << 16:
            header.append(126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(127)
            header.extend(struct.pack("!Q", length))
        connection.sendall(bytes(header) + payload)

    @staticmethod
    def _send_http_error(connection: socket.socket, status: int, reason: str) -> None:
        body = reason.encode("ascii")
        response = (
            f"HTTP/1.1 {status} {reason}\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n"
            "Content-Type: text/plain\r\n"
            "\r\n"
        ).encode("ascii") + body
        connection.sendall(response)

class BridgeWebSocketServer:
    """Small threaded listener for BridgeWebSocketTransport."""

    def __init__(
        self,
        transport: BridgeWebSocketTransport,
        *,
        host: str = "127.0.0.1",
        port: int = 9810,
        backlog: int = 16,
    ) -> None:
        if not host:
            raise ValueError("host must not be empty")
        if port < 0 or port > 65535:
            raise ValueError("port must be between 0 and 65535")
        if backlog <= 0:
            raise ValueError("backlog must be positive")
        self.transport = transport
        self.host = host
        self.port = port
        self.backlog = backlog
        self._stop = threading.Event()
        self._ready = threading.Event()
        self._lock = threading.Lock()
        self._listener: socket.socket | None = None
        self._clients: set[socket.socket] = set()
        self._threads: set[threading.Thread] = set()
        self._address: tuple[str, int] | None = None

    @property
    def address(self) -> tuple[str, int] | None:
        return self._address

    def wait_until_ready(self, timeout: float = 2.0) -> bool:
        return self._ready.wait(timeout)

    def serve_forever(self) -> None:
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((self.host, self.port))
        listener.listen(self.backlog)
        listener.settimeout(0.2)
        with self._lock:
            self._listener = listener
            bound_host, bound_port = listener.getsockname()[:2]
            self._address = (str(bound_host), int(bound_port))
        self._ready.set()
        try:
            while not self._stop.is_set():
                try:
                    connection, _ = listener.accept()
                except socket.timeout:
                    continue
                except OSError:
                    if self._stop.is_set():
                        break
                    raise
                with self._lock:
                    self._clients.add(connection)
                thread = threading.Thread(
                    target=self._serve_client,
                    args=(connection,),
                    daemon=True,
                )
                with self._lock:
                    self._threads.add(thread)
                thread.start()
        finally:
            try:
                listener.close()
            except OSError:
                pass
            with self._lock:
                self._listener = None
            self._close_clients()
            self._join_clients()

    def shutdown(self) -> None:
        self._stop.set()
        with self._lock:
            listener = self._listener
        if listener is not None:
            try:
                listener.close()
            except OSError:
                pass
        self._close_clients()

    def _serve_client(self, connection: socket.socket) -> None:
        try:
            self.transport.serve_connection(connection)
        finally:
            with self._lock:
                self._clients.discard(connection)
                self._threads.discard(threading.current_thread())

    def _close_clients(self) -> None:
        with self._lock:
            clients = tuple(self._clients)
        for connection in clients:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                connection.close()
            except OSError:
                pass

    def _join_clients(self) -> None:
        with self._lock:
            threads = tuple(self._threads)
        for thread in threads:
            if thread is not threading.current_thread():
                thread.join(timeout=2)
