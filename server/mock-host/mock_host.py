#!/usr/bin/env python3
"""HuanHermes Mock Host: Bridge WebSocket + Management REST (stdlib only).

Env:
  HUAN_BRIDGE_HOST (default 0.0.0.0)
  HUAN_BRIDGE_PORT (default 9810)
  HUAN_MGMT_PORT   (default 9820)
  HUAN_BRIDGE_TOKEN
  HUAN_MGMT_TOKEN
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import socket
import struct
import threading
import time
import traceback
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlparse


BRIDGE_HOST = os.environ.get("HUAN_BRIDGE_HOST", "0.0.0.0")
BRIDGE_PORT = int(os.environ.get("HUAN_BRIDGE_PORT", "9810"))
MGMT_PORT = int(os.environ.get("HUAN_MGMT_PORT", "9820"))
BRIDGE_TOKEN = os.environ.get("HUAN_BRIDGE_TOKEN", "dev-bridge-token-change-me")
MGMT_TOKEN = os.environ.get("HUAN_MGMT_TOKEN", "dev-mgmt-token-change-me")
START_TS = time.time()

PROJECTS = [
    {
        "name": "claude-code",
        "agent_type": "claudecode",
        "platforms": ["bridge"],
        "sessions_count": 0,
    },
    {
        "name": "codex",
        "agent_type": "codex",
        "platforms": ["bridge"],
        "sessions_count": 0,
    },
    {
        "name": "hermes",
        "agent_type": "hermes",
        "platforms": ["bridge"],
        "sessions_count": 0,
        "note": "stub — adapter not implemented",
    },
]

SESSIONS: Dict[str, Dict[str, Any]] = {}
SESSIONS_LOCK = threading.Lock()
SESSION_STATE: Dict[str, Dict[str, Any]] = {}
ACTIVE_RUNS: Dict[str, threading.Event] = {}
ACTIVE_LOCK = threading.Lock()


def log(msg: str) -> None:
    print(f"[mock-host] {msg}", flush=True)


def json_bytes(obj: Any) -> bytes:
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")


# ---------- WebSocket helpers ----------

def _ws_accept_key(key: str) -> str:
    guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    digest = hashlib.sha1((key + guid).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def _recv_exact(conn: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("closed")
        buf += chunk
    return buf


def ws_recv_text(conn: socket.socket) -> str:
    hdr = _recv_exact(conn, 2)
    b1, b2 = hdr[0], hdr[1]
    opcode = b1 & 0x0F
    masked = (b2 & 0x80) != 0
    ln = b2 & 0x7F
    if ln == 126:
        ln = struct.unpack("!H", _recv_exact(conn, 2))[0]
    elif ln == 127:
        ln = struct.unpack("!Q", _recv_exact(conn, 8))[0]
    mask = _recv_exact(conn, 4) if masked else b""
    payload = _recv_exact(conn, ln)
    if masked:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    if opcode == 0x8:
        raise ConnectionError("client close")
    if opcode == 0x9:
        ws_send_frame(conn, 0xA, payload)
        return ws_recv_text(conn)
    if opcode != 0x1:
        return ws_recv_text(conn)
    return payload.decode("utf-8")


def ws_send_frame(conn: socket.socket, opcode: int, payload: bytes) -> None:
    header = bytearray([0x80 | opcode])
    ln = len(payload)
    if ln < 126:
        header.append(ln)
    elif ln < (1 << 16):
        header.append(126)
        header.extend(struct.pack("!H", ln))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", ln))
    conn.sendall(header + payload)


def ws_send_text(conn: socket.socket, text: str) -> None:
    ws_send_frame(conn, 0x1, text.encode("utf-8"))


def extract_token(headers: Dict[str, str], query: Dict[str, List[str]]) -> Optional[str]:
    auth = headers.get("authorization") or headers.get("Authorization")
    if auth and auth.lower().startswith("bearer "):
        return auth[7:].strip()
    xt = headers.get("x-bridge-token") or headers.get("X-Bridge-Token")
    if xt:
        return xt.strip()
    if "token" in query and query["token"]:
        return query["token"][0]
    return None


def handle_bridge_client(conn: socket.socket, addr: Tuple[str, int]) -> None:
    conn.settimeout(120)
    try:
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                return
            data += chunk
        header_blob, _ = data.split(b"\r\n\r\n", 1)
        lines = header_blob.decode("latin1", errors="replace").split("\r\n")
        req = lines[0]
        method, path, _ = req.split(" ", 2)
        headers: Dict[str, str] = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        parsed = urlparse(path)
        query = parse_qs(parsed.query)

        if method != "GET" or parsed.path != "/bridge/ws":
            body = b"not found"
            conn.sendall(
                b"HTTP/1.1 404 Not Found\r\nContent-Length: "
                + str(len(body)).encode()
                + b"\r\nConnection: close\r\n\r\n"
                + body
            )
            return

        token = extract_token(headers, query)
        if token != BRIDGE_TOKEN:
            body = b"unauthorized"
            conn.sendall(
                b"HTTP/1.1 401 Unauthorized\r\nContent-Length: "
                + str(len(body)).encode()
                + b"\r\nConnection: close\r\n\r\n"
                + body
            )
            return

        key = headers.get("sec-websocket-key")
        if not key:
            conn.sendall(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
            return
        accept = _ws_accept_key(key)
        conn.sendall(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n"
                "\r\n"
            ).encode("ascii")
        )
        log(f"bridge connected from {addr}")

        registered = False
        platform = "unknown"

        while True:
            raw = ws_recv_text(conn)
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                ws_send_text(conn, json.dumps({"type": "error", "error": "invalid json"}))
                continue
            mtype = msg.get("type")

            if mtype == "ping":
                ws_send_text(conn, json.dumps({"type": "pong", "ts": msg.get("ts")}))
                continue

            if mtype == "register":
                platform = msg.get("platform") or "unknown"
                registered = True
                ws_send_text(conn, json.dumps({"type": "register_ack", "ok": True, "error": ""}))
                log(f"registered platform={platform}")
                continue

            if not registered:
                ws_send_text(
                    conn,
                    json.dumps({"type": "register_ack", "ok": False, "error": "send register first"}),
                )
                continue

            if mtype == "card_action":
                _handle_card_action(conn, msg)
                continue

            if mtype == "cancel":
                _handle_cancel(conn, msg)
                continue

            if mtype == "message":
                _handle_message(conn, msg)
                continue

            ws_send_text(
                conn,
                json.dumps(
                    {
                        "type": "reply",
                        "session_key": msg.get("session_key"),
                        "reply_ctx": msg.get("reply_ctx"),
                        "content": f"mock: unknown type {mtype}",
                        "format": "text",
                    }
                ),
            )
    except ConnectionError:
        log(f"bridge disconnected {addr}")
    except Exception:
        log(f"bridge error:\n{traceback.format_exc()}")
    finally:
        try:
            conn.close()
        except OSError:
            pass


def _session_state(sk: str) -> Dict[str, Any]:
    st = SESSION_STATE.get(sk)
    if not st:
        st = {
            "mode": "default",
            "model": "mock-sonnet",
            "workdir": "/workspace",
            "project": "claude-code",
            "allow_all": False,
            "transcript": [],
        }
        SESSION_STATE[sk] = st
    return st


def _append_transcript(sk: str, role: str, content: str) -> None:
    st = _session_state(sk)
    st["transcript"].append({"role": role, "content": content[:4000]})
    if len(st["transcript"]) > 200:
        st["transcript"] = st["transcript"][-200:]


def _touch_session(sk: str, content: str = "", project: Optional[str] = None) -> None:
    st = _session_state(sk)
    if project:
        st["project"] = project
    with SESSIONS_LOCK:
        prev = SESSIONS.get(sk) or {}
        rec = {
            "id": sk,
            "session_key": sk,
            "project": project or prev.get("project") or st.get("project") or "claude-code",
            "title": prev.get("title") or "Session",
            "updated_at": time.time(),
            "last_user": (content[:200] if content else prev.get("last_user")),
            "mode": st["mode"],
            "model": st["model"],
            "workdir": st["workdir"],
            "running": False,
        }
        SESSIONS[sk] = rec
        for p in PROJECTS:
            p["sessions_count"] = sum(1 for s in SESSIONS.values() if s.get("project") == p["name"])


def _set_running(sk: str, running: bool) -> None:
    with SESSIONS_LOCK:
        if sk in SESSIONS:
            SESSIONS[sk]["running"] = running
            SESSIONS[sk]["updated_at"] = time.time()


def _handle_cancel(conn: socket.socket, msg: Dict[str, Any]) -> None:
    sk = msg.get("session_key") or ""
    ctx = msg.get("reply_ctx") or ""
    cancelled = False
    with ACTIVE_LOCK:
        keys = list(ACTIVE_RUNS.keys())
        for k in keys:
            if k == ctx or (not ctx and k.startswith(sk + "|")) or (ctx and k.endswith("|" + ctx)):
                ACTIVE_RUNS[k].set()
                cancelled = True
        if ctx in ACTIVE_RUNS:
            ACTIVE_RUNS[ctx].set()
            cancelled = True
    text = "run cancelled (mock)." if cancelled else "no active run to cancel (mock)."
    ws_send_text(
        conn,
        json.dumps(
            {
                "type": "run_done",
                "session_key": sk,
                "reply_ctx": ctx,
                "status": "cancelled" if cancelled else "idle",
                "content": text,
            },
            ensure_ascii=False,
        ),
    )
    if cancelled:
        _set_running(sk, False)
        _stream_reply(conn, sk, ctx or "cancel", text, cancellable=False)


def _handle_message(conn: socket.socket, msg: Dict[str, Any]) -> None:
    content = (msg.get("content") or "").strip()
    sk = msg.get("session_key") or "huan:unknown:unknown"
    ctx = msg.get("reply_ctx") or str(uuid.uuid4())
    project = _project_hint(content)
    with SESSIONS_LOCK:
        if sk in SESSIONS and SESSIONS[sk].get("project"):
            project = SESSIONS[sk]["project"]
    _touch_session(sk, content=content, project=project)
    _append_transcript(sk, "user", content)

    if content.lower() in ("/stop", "/cancel"):
        _handle_cancel(conn, {"session_key": sk, "reply_ctx": ctx})
        return

    if content.startswith("/perm") or content.lower() == "need permission":
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "buttons",
                    "session_key": sk,
                    "reply_ctx": ctx,
                    "content": "Mock agent wants to run: `echo hello` — allow?",
                    "buttons": [
                        [
                            {"text": "Allow", "data": "perm:demo:allow"},
                            {"text": "Deny", "data": "perm:demo:deny"},
                            {"text": "Allow all", "data": "perm:demo:allow_all"},
                        ]
                    ],
                }
            ),
        )
        return

    if content.startswith("/"):
        reply = _mock_slash(sk, content)
        _stream_reply(conn, sk, ctx, reply, cancellable=False)
        return

    st = _session_state(sk)
    reply = (
        f"[mock:{st.get('project')}|{st.get('model')}|mode={st.get('mode')}] 收到：{content}\n\n"
        "这是 HuanHermes Mock Host 的流式回复。\n"
        "真连服务器时，此处将由 Claude Code / Codex / Hermes 产生。\n"
        f"workdir={st.get('workdir')}"
    )
    cancel_ev = threading.Event()
    run_key = f"{sk}|{ctx}"
    with ACTIVE_LOCK:
        ACTIVE_RUNS[run_key] = cancel_ev
        ACTIVE_RUNS[ctx] = cancel_ev
    _set_running(sk, True)

    ws_send_text(conn, json.dumps({"type": "typing_start", "session_key": sk, "reply_ctx": ctx}))
    time.sleep(0.03)
    ws_send_text(
        conn,
        json.dumps(
            {
                "type": "thinking",
                "session_key": sk,
                "reply_ctx": ctx,
                "content": "planning mock response…",
            },
            ensure_ascii=False,
        ),
    )
    time.sleep(0.03)
    ws_send_text(
        conn,
        json.dumps(
            {
                "type": "tool_call",
                "session_key": sk,
                "reply_ctx": ctx,
                "name": "echo",
                "input": content[:80],
            },
            ensure_ascii=False,
        ),
    )
    time.sleep(0.03)
    if not cancel_ev.is_set():
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "tool_result",
                    "session_key": sk,
                    "reply_ctx": ctx,
                    "name": "echo",
                    "output": "ok",
                },
                ensure_ascii=False,
            ),
        )

    cancelled = _stream_reply(conn, sk, ctx, reply, cancellable=True, cancel_ev=cancel_ev)
    ws_send_text(conn, json.dumps({"type": "typing_stop", "session_key": sk, "reply_ctx": ctx}))
    status = "cancelled" if cancelled else "completed"
    ws_send_text(
        conn,
        json.dumps({"type": "run_done", "session_key": sk, "reply_ctx": ctx, "status": status}),
    )
    _set_running(sk, False)
    with ACTIVE_LOCK:
        ACTIVE_RUNS.pop(run_key, None)
        ACTIVE_RUNS.pop(ctx, None)


def _project_hint(content: str) -> str:
    c = content.lower()
    if "codex" in c:
        return "codex"
    if "hermes" in c:
        return "hermes"
    return "claude-code"


def _mock_slash(sk: str, content: str) -> str:
    parts = content.split()
    cmd = parts[0].lower()
    st = _session_state(sk)
    if cmd in ("/help", "/h"):
        return "mock commands: /help /status /mode /model /dir /cd /stop /cancel /perm"
    if cmd == "/status":
        return (
            f"mock host uptime={int(time.time()-START_TS)}s projects={len(PROJECTS)} "
            f"mode={st['mode']} model={st['model']} dir={st['workdir']}"
        )
    if cmd == "/mode":
        if len(parts) > 1:
            st["mode"] = parts[1]
            _touch_session(sk)
            return f"mode set to: {st['mode']}"
        return f"current mode: {st['mode']} (options: default, plan, acceptEdits, bypassPermissions)"
    if cmd == "/model":
        if len(parts) > 1:
            st["model"] = parts[1]
            _touch_session(sk)
            return f"model set to: {st['model']}"
        return f"current model: {st['model']} (options: mock-sonnet, mock-codex, mock-hermes)"
    if cmd in ("/dir", "/cd"):
        if len(parts) > 1:
            path = parts[1]
            if not path.startswith("/"):
                return f"rejected path (must be absolute): {path}"
            st["workdir"] = path
            _touch_session(sk)
            return f"work_dir set to: {st['workdir']}"
        return f"work_dir: {st['workdir']}"
    if cmd in ("/stop", "/cancel"):
        return "use Bridge cancel or /stop while a run is active"
    return f"unknown command {cmd} (mock)"


def _stream_reply(
    conn: socket.socket,
    sk: str,
    ctx: str,
    text: str,
    *,
    cancellable: bool = True,
    cancel_ev: Optional[threading.Event] = None,
) -> bool:
    acc = ""
    step = max(1, len(text) // 12)
    cancelled = False
    for i in range(0, len(text), step):
        if cancellable and cancel_ev is not None and cancel_ev.is_set():
            cancelled = True
            break
        piece = text[i : i + step]
        acc += piece
        done = (i + step >= len(text)) and not cancelled
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "reply_stream",
                    "session_key": sk,
                    "reply_ctx": ctx,
                    "delta": piece,
                    "full_text": acc + ("…[cancelled]" if cancelled else ""),
                    "preview_handle": "",
                    "done": done or cancelled,
                },
                ensure_ascii=False,
            ),
        )
        time.sleep(0.04 if cancellable else 0.015)
    if cancelled:
        final = acc + "…[cancelled]"
        _append_transcript(sk, "assistant", final)
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "reply",
                    "session_key": sk,
                    "reply_ctx": ctx,
                    "content": final,
                    "format": "markdown",
                },
                ensure_ascii=False,
            ),
        )
        return True
    _append_transcript(sk, "assistant", text)
    ws_send_text(
        conn,
        json.dumps(
            {
                "type": "reply",
                "session_key": sk,
                "reply_ctx": ctx,
                "content": text,
                "format": "markdown",
            },
            ensure_ascii=False,
        ),
    )
    return False


def _handle_card_action(conn: socket.socket, msg: Dict[str, Any]) -> None:
    action = msg.get("action") or ""
    sk = msg.get("session_key") or "huan:unknown"
    ctx = msg.get("reply_ctx") or str(uuid.uuid4())
    st = _session_state(sk)
    if action.endswith(":deny"):
        text = "Permission denied (mock)."
    elif action.endswith(":allow_all"):
        st["allow_all"] = True
        text = "allowed_all: mock will auto-approve subsequent tools in this session."
    else:
        text = "allowed: mock ran `echo hello` → hello"
    _stream_reply(conn, sk, ctx, text, cancellable=False)


def bridge_server() -> None:
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((BRIDGE_HOST, BRIDGE_PORT))
    srv.listen(50)
    log(f"Bridge WS listening on ws://{BRIDGE_HOST}:{BRIDGE_PORT}/bridge/ws")
    while True:
        conn, addr = srv.accept()
        t = threading.Thread(target=handle_bridge_client, args=(conn, addr), daemon=True)
        t.start()



def _create_session_rec(project: str, body: Dict[str, Any]) -> Dict[str, Any]:
    """Create session record (shared by flat + project-scoped POST)."""
    sid = (body.get("session_key") or body.get("id") or "").strip()
    if not sid:
        sid = f"huanhermes-app:mock:{uuid.uuid4().hex[:10]}"
    st = _session_state(sid)
    st["project"] = project
    if body.get("title"):
        title = body["title"]
    else:
        title = "New session"
    rec = {
        "id": body.get("id") or sid,
        "session_key": sid,
        "project": project,
        "title": title,
        "name": title,
        "updated_at": time.time(),
        "created_at": time.time(),
        "mode": st["mode"],
        "model": st["model"],
        "workdir": st["workdir"],
        "running": False,
        "live": False,
        "active": False,
        "platform": "bridge",
        "agent_type": next((p.get("agent_type") for p in PROJECTS if p["name"] == project), "claudecode"),
    }
    with SESSIONS_LOCK:
        SESSIONS[sid] = rec
        for p in PROJECTS:
            p["sessions_count"] = sum(1 for s in SESSIONS.values() if s.get("project") == p["name"])
    return rec


# ---------- Management HTTP ----------

class MgmtHandler(BaseHTTPRequestHandler):
    server_version = "HuanMockMgmt/0.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        log("mgmt " + (fmt % args))

    def _auth_ok(self) -> bool:
        auth = self.headers.get("Authorization") or ""
        if auth.startswith("Bearer ") and auth[7:].strip() == MGMT_TOKEN:
            return True
        q = parse_qs(urlparse(self.path).query)
        if q.get("token", [None])[0] == MGMT_TOKEN:
            return True
        return False

    def _send(self, code: int, obj: Any) -> None:
        body = json_bytes(obj)
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if not self._auth_ok():
            self._send(401, {"ok": False, "error": "unauthorized: missing or invalid token"})
            return
        path = urlparse(self.path).path
        if path == "/api/v1/status":
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "version": "mock-0.1.0",
                        "uptime_seconds": int(time.time() - START_TS),
                        "connected_platforms": ["bridge"],
                        "projects_count": len(PROJECTS),
                        "bridge_adapters": [
                            {
                                "platform": "huanhermes-app",
                                "project": "*",
                                "capabilities": ["text", "buttons", "typing", "preview"],
                            }
                        ],
                    },
                },
            )
            return
        if path == "/api/v1/projects":
            self._send(200, {"ok": True, "data": {"projects": PROJECTS}})
            return
        m = re.match(r"^/api/v1/projects/([^/]+)$", path)
        if m:
            name = m.group(1)
            for p in PROJECTS:
                if p["name"] == name:
                    with SESSIONS_LOCK:
                        keys = [s["session_key"] for s in SESSIONS.values() if s.get("project") == name]
                    data = dict(p)
                    data["active_session_keys"] = keys
                    data["platforms"] = [{"type": "bridge", "connected": True}]
                    data["mode"] = "default"
                    self._send(200, {"ok": True, "data": data})
                    return
            self._send(404, {"ok": False, "error": "project not found"})
            return
        # cc-connect shape: /projects/{name}/sessions
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions$", path)
        if m:
            name = m.group(1)
            with SESSIONS_LOCK:
                items = [s for s in SESSIONS.values() if s.get("project") == name]
            self._send(200, {"ok": True, "data": {"sessions": items, "active_keys": {}}})
            return
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions/(.+)$", path)
        if m:
            name, sid = m.group(1), m.group(2)
            with SESSIONS_LOCK:
                rec = SESSIONS.get(sid)
            if not rec or rec.get("project") != name:
                self._send(404, {"ok": False, "error": "session not found"})
                return
            st = SESSION_STATE.get(sid) or {}
            data = dict(rec)
            data["transcript"] = list(st.get("transcript") or [])
            self._send(200, {"ok": True, "data": data})
            return
        if path == "/api/v1/agents":
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "agents": ["claudecode", "codex", "hermes", "cursor", "opencode"],
                        "platforms": ["bridge", "telegram"],
                    },
                },
            )
            return
        if path == "/api/v1/bridge/adapters":
            self._send(200, {"ok": True, "data": {"adapters": []}})
            return
        if path == "/api/v1/sessions":
            q = parse_qs(urlparse(self.path).query)
            project = q.get("project", [None])[0]
            with SESSIONS_LOCK:
                items = list(SESSIONS.values())
            if project:
                items = [s for s in items if s.get("project") == project]
            self._send(200, {"ok": True, "data": {"sessions": items}})
            return
        m = re.match(r"^/api/v1/sessions/(.+)$", path)
        if m:
            sid = m.group(1)
            with SESSIONS_LOCK:
                rec = SESSIONS.get(sid)
            if not rec:
                self._send(404, {"ok": False, "error": "session not found"})
                return
            st = SESSION_STATE.get(sid) or {}
            data = dict(rec)
            data["transcript"] = list(st.get("transcript") or [])
            data["mode"] = st.get("mode", rec.get("mode"))
            data["model"] = st.get("model", rec.get("model"))
            data["workdir"] = st.get("workdir", rec.get("workdir"))
            self._send(200, {"ok": True, "data": data})
            return
        self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._auth_ok():
            self._send(401, {"ok": False, "error": "unauthorized: missing or invalid token"})
            return
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, {"ok": False, "error": "invalid json"})
            return
        # Flat MVP: POST /sessions
        if path == "/api/v1/sessions":
            project = body.get("project") or "claude-code"
            rec = _create_session_rec(project, body)
            self._send(200, {"ok": True, "data": rec})
            return
        # cc-connect shape: POST /projects/{name}/sessions  (session_key optional; generated if missing)
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions$", path)
        if m:
            project = m.group(1)
            rec = _create_session_rec(project, body)
            self._send(200, {"ok": True, "data": rec})
            return
        self._send(404, {"ok": False, "error": "not found"})

    def do_DELETE(self) -> None:  # noqa: N802
        if not self._auth_ok():
            self._send(401, {"ok": False, "error": "unauthorized: missing or invalid token"})
            return
        path = urlparse(self.path).path
        m = re.match(r"^/api/v1/sessions/(.+)$", path)
        if m:
            sid = m.group(1)
            with SESSIONS_LOCK:
                SESSIONS.pop(sid, None)
            SESSION_STATE.pop(sid, None)
            self._send(200, {"ok": True, "data": {"deleted": sid}})
            return
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions/(.+)$", path)
        if m:
            _name, sid = m.group(1), m.group(2)
            with SESSIONS_LOCK:
                SESSIONS.pop(sid, None)
            SESSION_STATE.pop(sid, None)
            self._send(200, {"ok": True, "data": {"deleted": sid}})
            return
        self._send(404, {"ok": False, "error": "not found"})


def mgmt_server() -> None:
    httpd = ThreadingHTTPServer((BRIDGE_HOST, MGMT_PORT), MgmtHandler)
    log(f"Management HTTP listening on http://{BRIDGE_HOST}:{MGMT_PORT}/api/v1")
    httpd.serve_forever()


def main() -> None:
    log("starting HuanHermes Mock Host")
    log(f"BRIDGE_TOKEN set (len={len(BRIDGE_TOKEN)}) MGMT_TOKEN set (len={len(MGMT_TOKEN)})")
    t = threading.Thread(target=mgmt_server, name="mgmt", daemon=True)
    t.start()
    bridge_server()


if __name__ == "__main__":
    main()
