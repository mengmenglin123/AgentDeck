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
        "capabilities": [
            "stream",
            "buttons",
            "cancel",
            "workdir",
            "mode",
            "model",
            "tools_visible",
        ],
    },
    {
        "name": "codex",
        "agent_type": "codex",
        "platforms": ["bridge"],
        "sessions_count": 0,
        "capabilities": [
            "stream",
            "buttons",
            "cancel",
            "workdir",
            "mode",
            "model",
            "tools_visible",
        ],
    },
    {
        "name": "hermes",
        "agent_type": "hermes",
        "platforms": ["bridge"],
        "sessions_count": 0,
        "capabilities": [
            "stream",
            "buttons",
            "cancel",
            "workdir",
            "mode",
            "model",
            "tools_visible",
            "memory_readonly",
            "skills_catalog",
            "mcp_catalog",
        ],
        "note": "Mock Hermes — real adapter is ADR-002; not a live Hermes process",
        "adapter": "mock",
        "process": False,
    },
]

SESSIONS: Dict[str, Dict[str, Any]] = {}
SESSIONS_LOCK = threading.Lock()
SESSION_STATE: Dict[str, Dict[str, Any]] = {}
ACTIVE_RUNS: Dict[str, threading.Event] = {}
ACTIVE_LOCK = threading.Lock()

# Readonly mock workspace tree for GET /workspace (console file browser demo).
WORKSPACE_TREE: Dict[str, Any] = {
    "type": "dir",
    "name": "",
    "children": {
        "AGENTS.md": {
            "type": "file",
            "content": "# AGENTS\n\nMock workspace. Host is source of truth.\n",
            "size": 48,
        },
        "README.md": {
            "type": "file",
            "content": "# Demo project\n\nHuanHermes Mock workspace (readonly).\n",
            "size": 52,
        },
        "src": {
            "type": "dir",
            "children": {
                "main.py": {
                    "type": "file",
                    "content": "def main():\n    print('hello from mock workspace')\n\nif __name__ == '__main__':\n    main()\n",
                    "size": 90,
                },
                "util.py": {
                    "type": "file",
                    "content": "def greet(name: str) -> str:\n    return f'hi {name}'\n",
                    "size": 50,
                },
            },
        },
        "docs": {
            "type": "dir",
            "children": {
                "notes.md": {
                    "type": "file",
                    "content": "Console notes.\n- status dashboard\n- prompt history\n- workspace browse\n",
                    "size": 70,
                },
                "protocol.md": {
                    "type": "file",
                    "content": "# Protocol\n\nBridge WS + Management REST.\nSee repo docs/protocol (Host owns runtime).\n",
                    "size": 90,
                },
            },
        },
        "hermes": {
            "type": "dir",
            "children": {
                "README.md": {
                    "type": "file",
                    "content": (
                        "# Hermes project (mock)\n\n"
                        "App is console-only. Real Hermes agent loop stays on Host (ADR-002).\n\n"
                        "## Status\n\n"
                        "- adapter: mock\n"
                        "- process: false\n"
                    ),
                    "size": 160,
                },
                "AGENTS.md": {
                    "type": "file",
                    "content": (
                        "# Hermes agents\n\n"
                        "Mock catalog only — Host will map Bridge → process later.\n"
                    ),
                    "size": 80,
                },
                "skills": {
                    "type": "dir",
                    "children": {
                        "hermes-agent.md": {
                            "type": "file",
                            "content": "Skill stub: hermes-agent (catalog surface).\n",
                            "size": 48,
                        },
                    },
                },
            },
        },
    },
}



def _ws_walk_files(node: Optional[Dict[str, Any]], prefix: str = "") -> List[Tuple[str, Dict[str, Any]]]:
    """Yield (relpath, file_node) for all files under node."""
    out: List[Tuple[str, Dict[str, Any]]] = []
    if not node or not isinstance(node, dict):
        return out
    if node.get("type") == "file":
        out.append((prefix, node))
        return out
    kids = node.get("children") or {}
    if not isinstance(kids, dict):
        return out
    for name, child in sorted(kids.items()):
        p = f"{prefix}/{name}" if prefix else name
        out.extend(_ws_walk_files(child, p))
    return out

def _ws_resolve(path: str) -> Tuple[Optional[Dict[str, Any]], str]:
    """Resolve relative path under WORKSPACE_TREE. Returns (node, cleaned_path)."""
    raw = (path or "").strip().replace("\\", "/")
    while raw.startswith("./"):
        raw = raw[2:]
    if raw.startswith("/"):
        raw = raw[1:]
    if ".." in raw.split("/"):
        return None, raw
    node: Dict[str, Any] = WORKSPACE_TREE
    if not raw or raw in {".", "/"}:
        return node, ""
    parts = [p for p in raw.split("/") if p]
    for part in parts:
        kids = node.get("children") if isinstance(node, dict) else None
        if not isinstance(kids, dict) or part not in kids:
            return None, raw
        node = kids[part]
    return node, "/".join(parts)


def workspace_list(path: str = "") -> Dict[str, Any]:
    node, cleaned = _ws_resolve(path)
    if node is None:
        return {"error": "not found", "path": path}
    if node.get("type") == "file":
        return {
            "path": cleaned,
            "type": "file",
            "name": cleaned.split("/")[-1] if cleaned else "",
            "size": node.get("size", len(node.get("content") or "")),
            "content": node.get("content") or "",
        }
    kids = node.get("children") or {}
    entries = []
    for name, child in sorted(kids.items(), key=lambda x: (x[1].get("type") != "dir", x[0])):
        entries.append(
            {
                "name": name,
                "type": child.get("type"),
                "size": child.get("size") if child.get("type") == "file" else None,
            }
        )
    parent = ""
    if cleaned:
        parts = cleaned.split("/")
        parent = "/".join(parts[:-1])
    return {
        "path": cleaned,
        "type": "dir",
        "parent": parent,
        "entries": entries,
    }


def workspace_git_status() -> Dict[str, Any]:
    return {
        "branch": "main",
        "clean": False,
        "files": [
            {"path": "src/main.py", "status": "M"},
            {"path": "docs/notes.md", "status": "?"},
            {"path": "docs/protocol.md", "status": "A"},
            {"path": "hermes/README.md", "status": "A"},
            {"path": "hermes/AGENTS.md", "status": "A"},
        ],
        "note": "Mock git status — readonly demo (includes hermes/ tree)",
    }




# Host-side memory catalog (readonly demo for console; Host is source of truth)
MEMORY_ENTRIES: List[Dict[str, Any]] = [
    {
        "id": "mem-user-pref-lang",
        "scope": "global",
        "type": "user",
        "title": "Preferred language",
        "content": "User prefers concise Chinese UI labels with English technical terms.",
        "confidence": "high",
        "updated_at": time.time() - 3600,
        "tags": ["preference", "i18n"],
    },
    {
        "id": "mem-project-layout",
        "scope": "project",
        "type": "project",
        "title": "Repo layout",
        "content": "HuanHermes App is console-only; Mock Host owns sessions and workspace demo tree.",
        "confidence": "high",
        "project": "claude-code",
        "updated_at": time.time() - 7200,
        "tags": ["architecture"],
    },
    {
        "id": "mem-feedback-brief",
        "scope": "global",
        "type": "feedback",
        "title": "Response style",
        "content": "Prefer short summaries + tables; avoid long preambles.",
        "confidence": "medium",
        "updated_at": time.time() - 86400,
        "tags": ["style"],
    },
    {
        "id": "mem-hermes-console",
        "scope": "project",
        "type": "project",
        "title": "Hermes console boundary",
        "content": "App is console-only; Hermes agent loop stays on Host (ADR-002 mock).",
        "confidence": "high",
        "project": "hermes",
        "updated_at": time.time() - 1800,
        "tags": ["hermes", "architecture", "console"],
    },
    {
        "id": "mem-hermes-pairing",
        "scope": "global",
        "type": "policy",
        "title": "Pairing tokens",
        "content": "Pairing URI and paste card must never embed tokens.",
        "confidence": "high",
        "updated_at": time.time() - 900,
        "tags": ["security", "pairing", "hermes"],
    },
]

CRON_JOBS: List[Dict[str, Any]] = [
    {
        "id": "cron-daily-status",
        "name": "Daily host status",
        "kind": "prompt",
        "schedule": "0 9 * * *",
        "enabled": True,
        "next_run_at": time.time() + 3600,
        "last_run_at": time.time() - 86400,
        "last_status": "ok",
        "description": "Ask agent for a short host health summary",
    },
    {
        "id": "cron-git-digest",
        "name": "Workspace git digest",
        "kind": "http",
        "schedule": "every 6h",
        "enabled": True,
        "next_run_at": time.time() + 7200,
        "last_run_at": time.time() - 20000,
        "last_status": "ok",
        "description": "GET /workspace/git and store summary (mock)",
    },
    {
        "id": "cron-cleanup",
        "name": "Session hygiene note",
        "kind": "bash",
        "schedule": "0 3 * * 0",
        "enabled": False,
        "next_run_at": None,
        "last_run_at": time.time() - 604800,
        "last_status": "skipped",
        "description": "Disabled mock job — Host would run cleanup scripts",
    },
    {
        "id": "cron-hermes-memory",
        "name": "Hermes memory digest",
        "kind": "prompt",
        "schedule": "every 12h",
        "enabled": True,
        "project": "hermes",
        "next_run_at": time.time() + 12 * 3600,
        "last_run_at": time.time() - 12 * 3600,
        "last_status": "ok",
        "description": "Mock: summarize hermes project memories (ADR-002 · no real process)",
        "tags": ["hermes", "memory"],
    },
    {
        "id": "cron-hermes-skills-scan",
        "name": "Hermes skills catalog scan",
        "kind": "prompt",
        "schedule": "0 8 * * 1",
        "enabled": False,
        "project": "hermes",
        "next_run_at": None,
        "last_run_at": time.time() - 7 * 86400,
        "last_status": "skipped",
        "description": "Disabled mock: refresh skills list for Hermes project",
        "tags": ["hermes", "skills"],
    },
]

MOCK_DIFFS: Dict[str, str] = {
    "README.md": """--- a/README.md
+++ b/README.md
@@ -1,5 +1,8 @@
 # Demo Workspace
-Placeholder readme
+Mock workspace for HuanHermes console.
+
+Host is the source of truth; App is remote control only.
""",
    "src/main.py": """--- a/src/main.py
+++ b/src/main.py
@@ -1,4 +1,7 @@
 def main():
-    print("hello")
+    print("hello from mock workspace")
+    # demo change for diff viewer
 
 if __name__ == "__main__":
     main()
""",
    "hermes/README.md": """--- /dev/null
+++ b/hermes/README.md
@@ -0,0 +1,8 @@
+# Hermes project (mock)
+
+App is console-only. Real Hermes agent loop stays on Host (ADR-002).
+
+## Status
+
+- adapter: mock
+- process: false
""",
    "docs/protocol.md": """--- /dev/null
+++ b/docs/protocol.md
@@ -0,0 +1,5 @@
+# Protocol
+
+Bridge WS + Management REST.
+See repo docs/protocol (Host owns runtime).
""",
}



# Recent host activity ring buffer (readonly console feed)
ACTIVITY_EVENTS: List[Dict[str, Any]] = []
ACTIVITY_LOCK = threading.Lock()
ACTIVITY_MAX = 100



# Host log lines (readonly console feed)
HOST_LOGS: list[dict] = []
HOST_LOGS_LOCK = threading.Lock()
HOST_LOGS_MAX = 200


def host_log(level: str, message: str, **extra) -> None:
    entry = {
        "ts": int(extra.pop("ts", time.time())),
        "level": level,
        "message": message,
        **extra,
    }
    with HOST_LOGS_LOCK:
        HOST_LOGS.append(entry)
        del HOST_LOGS[: max(0, len(HOST_LOGS) - HOST_LOGS_MAX)]


def seed_host_logs() -> None:
    """Idempotent demo log lines for Logs screen."""
    with HOST_LOGS_LOCK:
        if HOST_LOGS:
            return
    samples = [
        ("info", "Mock Host listening (bridge+mgmt)", "mock-host"),
        ("info", "Hermes adapter=mock (ADR-002) — no live process", "hermes"),
        ("debug", "Terminal geometry default 80x24", "terminal"),
        ("warn", "Pairing URI must never embed tokens", "bridge"),
        ("info", "Activity seed events ready", "mock-host"),
        ("info", "Session channel accepted", "session"),
        ("debug", "Bridge ping/pong ok", "bridge"),
        ("error", "Simulated tool timeout (demo)", "hermes"),
        ("warn", "Workspace readonly for console", "session"),
        ("info", "Logs source filter demo seed", "mock-host"),
    ]
    now = int(time.time())
    for i, (level, msg, src) in enumerate(samples):
        host_log(level, msg, source=src, ts=now - (len(samples) - i) * 15)


seed_host_logs()


def activity_push(kind: str, summary: str, **extra: Any) -> None:
    evt = {
        "id": f"act-{uuid.uuid4().hex[:10]}",
        "ts": time.time(),
        "kind": kind,
        "summary": summary,
        **extra,
    }
    # defaults for console filter chips when caller omits
    if "level" not in evt:
        k = (kind or "").lower()
        if "error" in k or "fail" in k:
            evt["level"] = "error"
        elif "warn" in k or "security" in k:
            evt["level"] = "warn"
        elif "debug" in k or "geometry" in k:
            evt["level"] = "debug"
        else:
            evt["level"] = "info"
    if "source" not in evt:
        k = (kind or "").lower()
        if "hermes" in k:
            evt["source"] = "hermes"
        elif "bridge" in k:
            evt["source"] = "bridge"
        elif "terminal" in k:
            evt["source"] = "terminal"
        elif "session" in k or "chat" in k:
            evt["source"] = "session"
        else:
            evt["source"] = "mock-host"
    with ACTIVITY_LOCK:
        ACTIVITY_EVENTS.append(evt)
        if len(ACTIVITY_EVENTS) > ACTIVITY_MAX:
            del ACTIVITY_EVENTS[: len(ACTIVITY_EVENTS) - ACTIVITY_MAX]




def seed_demo_activity() -> None:
    """Idempotent demo events for Host activity screen (P4 console depth)."""
    with ACTIVITY_LOCK:
        if ACTIVITY_EVENTS:
            return
    samples = [
        ("host.started", "Mock Host ready", "info", "mock-host"),
        ("hermes.adapter.mock", "Hermes project uses mock adapter (ADR-002)", "info", "hermes"),
        ("bridge.listening", "Bridge WebSocket accepting console clients", "info", "bridge"),
        ("terminal.geometry", "Default geometry 80x24 (client may resize)", "debug", "terminal"),
        ("security.pairing", "Pairing URI must never embed tokens", "warn", "session"),
        ("session.seed", "Demo session catalog loaded", "info", "session"),
    ]
    for kind, summary, level, source in samples:
        activity_push(kind, summary, source=source, level=level)


seed_demo_activity()

def activity_list(limit: int = 50) -> List[Dict[str, Any]]:
    with ACTIVITY_LOCK:
        items = list(ACTIVITY_EVENTS)
    items.reverse()
    return items[: max(1, min(limit, ACTIVITY_MAX))]


def workspace_diff(path: str = "") -> Dict[str, Any]:
    """Readonly unified diff snapshot for a path (or all)."""
    cleaned = (path or "").strip().lstrip("./")
    if cleaned:
        body = MOCK_DIFFS.get(cleaned)
        if body is None:
            return {"path": cleaned, "diff": "", "note": "no changes"}
        return {"path": cleaned, "diff": body, "note": "mock unified diff"}
    files = [{"path": k, "has_diff": True} for k in MOCK_DIFFS]
    return {"files": files, "note": "mock diff index"}



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

            if mtype == "terminal_input":
                _handle_terminal_input(conn, msg)
                continue

            if mtype == "terminal_resize":
                # store geometry for demo; Host real PTY would apply ioctl
                sk_r = msg.get("session_key") or ""
                st_r = _session_state(sk_r)
                try:
                    st_r["term_cols"] = int(msg.get("cols") or st_r.get("term_cols") or 80)
                except (TypeError, ValueError):
                    st_r["term_cols"] = 80
                try:
                    st_r["term_rows"] = int(msg.get("rows") or st_r.get("term_rows") or 24)
                except (TypeError, ValueError):
                    st_r["term_rows"] = 24
                ws_send_text(
                    conn,
                    json.dumps(
                        {
                            "type": "terminal_ack",
                            "session_key": sk_r,
                            "cols": st_r["term_cols"],
                            "rows": st_r["term_rows"],
                        }
                    ),
                )
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



def _handle_terminal_input(conn: socket.socket, msg: Dict[str, Any]) -> None:
    """Lightweight terminal channel over Bridge (not a full PTY).

    Host-side real shells would spawn PTY; Mock echoes + fake command results.
    """
    sk = msg.get("session_key") or ""
    data = (msg.get("data") or msg.get("content") or "").rstrip("\r\n")
    stream_id = msg.get("stream_id") or f"term-{uuid.uuid4().hex[:8]}"

    def out(chunk: str, *, done: bool = False, exit_code: Optional[int] = None) -> None:
        payload: Dict[str, Any] = {
            "type": "terminal_out",
            "session_key": sk,
            "stream_id": stream_id,
            "data": chunk,
        }
        if done:
            payload["done"] = True
        if exit_code is not None:
            payload["exit_code"] = exit_code
        ws_send_text(conn, json.dumps(payload))

    if not data:
        out("", done=True, exit_code=0)
        return

    lower = data.strip().lower()
    # local echo (skip raw ctrl chars)
    if data != "\x03":
        out(f"$ {data}\n")

    # Ctrl-C / soft interrupt
    if data == "\x03" or lower in {"^c", "ctrl-c", "ctrl+c"}:
        out("^C\n", done=True, exit_code=130)
        return
    if lower in {"y", "n", "yes", "no"}:
        out(f"(ack) {data.strip()}\n", done=True, exit_code=0)
        return
    if lower in {"help", "?"}:
        st_h = _session_state(sk)
        cols_h = st_h.get("term_cols") or 80
        rows_h = st_h.get("term_rows") or 24
        out(
            "HuanHermes Mock terminal (Bridge terminal_input).\n"
            "Commands: help, pwd, cd, ls, tree, mkdir, whoami, which, uname, hostname, id, date, env, export, cat, head, tail, wc, stat, du, basename, dirname, realpath, grep, find, seq, sort, uniq, cut, nl, fold, tr, rev, cmp, yes, tee, xargs, hexdump, xxd, od, jq, md5sum, sha1sum, sha256sum, base64, file, type, expr, test, factor, bc, nproc, arch, getconf, numfmt, df, free, ps, uptime, true, false, printf, sleep, touch, history, echo <text>, stty size, y/n, clear, exit\n"
            f"Geometry: {cols_h}x{rows_h} (from terminal_resize)\n"
            "Quick interrupt: Ctrl-C (^C)\n"
            "This is protocol demo only — not a real remote shell.\n",
            done=True,
            exit_code=0,
        )
    elif lower == "pwd":
        st = _session_state(sk)
        out((st.get("workdir") or "/workspace") + "\n", done=True, exit_code=0)
    elif lower == "cd" or lower.startswith("cd "):
        st = _session_state(sk)
        cur = st.get("workdir") or "/workspace"
        arg = data.strip()[2:].strip() if lower.startswith("cd") else ""
        if not arg or arg == "~":
            target = "/workspace"
        elif arg == "-":
            target = st.get("prev_workdir") or "/workspace"
        elif arg.startswith("/"):
            target = arg.rstrip("/") or "/"
            if not target.startswith("/workspace"):
                # allow absolute under /workspace only
                if target == "/":
                    target = "/workspace"
                else:
                    out(f"cd: {arg}: permission denied (mock stays under /workspace)\n", done=True, exit_code=1)
                    return
        else:
            # relative
            base = cur.rstrip("/")
            parts = [p for p in (base + "/" + arg).split("/") if p and p != "."]
            stack = []
            for p in parts:
                if p == "..":
                    if stack:
                        stack.pop()
                else:
                    stack.append(p)
            target = "/" + "/".join(stack) if stack else "/workspace"
            if not target.startswith("/workspace"):
                target = "/workspace"
        rel = target.replace("/workspace", "").lstrip("/")
        node, cleaned = _ws_resolve(rel)
        if target != "/workspace" and (node is None or node.get("type") != "dir"):
            out(f"cd: {arg}: No such directory\n", done=True, exit_code=1)
        else:
            st["prev_workdir"] = cur
            st["workdir"] = target if target.startswith("/workspace") else "/workspace"
            if target == "/workspace" or (node and node.get("type") == "dir"):
                if target != "/workspace" and cleaned:
                    st["workdir"] = "/workspace/" + cleaned
                out("", done=True, exit_code=0)
            else:
                out(f"cd: {arg}: No such directory\n", done=True, exit_code=1)
    elif lower.startswith("mkdir "):
        # Readonly mock tree — report intent only
        name = data.strip()[6:].strip() or "(empty)"
        out(f"[mock-mkdir] refused (readonly workspace): {name}\n", done=True, exit_code=1)
    elif lower in {"ls", "ls -la"} or lower.startswith("ls "):
        st_ls = _session_state(sk)
        rel = (st_ls.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
        node, _ = _ws_resolve(rel)
        if node is None or node.get("type") == "file":
            out("ls: cannot access workdir\n", done=True, exit_code=1)
        else:
            kids = node.get("children") or {}
            names = []
            for name, child in sorted(kids.items(), key=lambda x: (x[1].get("type") != "dir", x[0])):
                names.append(name + ("/" if child.get("type") == "dir" else ""))
            out(("\n".join(names) + ("\n" if names else "")), done=True, exit_code=0)
    elif lower == "whoami":
        out("huanhermes-mock\n", done=True, exit_code=0)
    elif lower.startswith("which "):
        name = data.strip()[6:].strip()
        known = {
            "ls", "pwd", "cd", "cat", "head", "tail", "wc", "echo", "env", "date",
            "uname", "hostname", "id", "clear", "mkdir", "stty", "whoami", "help",
            "tree", "df", "free", "ps", "uptime", "stat", "du", "basename", "dirname", "realpath", "which", "true", "false", "printf", "sleep", "touch", "history", "grep", "find", "seq", "sort", "export", "uniq", "cut", "nl", "fold", "tr", "rev", "cmp", "yes", "tee", "xargs", "hexdump", "xxd", "od", "jq", "md5sum", "sha1sum", "sha256sum", "base64", "file", "type", "expr", "test", "factor", "bc", "nproc", "arch", "getconf", "numfmt",
        }
        if name in known:
            out(f"/usr/bin/{name}\n", done=True, exit_code=0)
        else:
            out(f"which: no {name} in mock PATH\n", done=True, exit_code=1)
    elif lower in {"clear", "reset", "cls"}:
        out("\x1b[2J\x1b[H[mock-clear]\n", done=True, exit_code=0)
    elif lower in {"uname", "uname -a"}:
        out("HuanHermes-Mock 0.1 kernel mock-arch\n", done=True, exit_code=0)
    elif lower in {"hostname", "hostname -f"}:
        out("mock-host\n", done=True, exit_code=0)
    elif lower in {"id", "id -u"}:
        out("uid=1000(huanhermes-mock) gid=1000(mock) groups=1000(mock)\n", done=True, exit_code=0)
    elif lower.startswith("cat ") or lower.startswith("head ") or lower.startswith("tail ") or lower.startswith("wc "):
        st_c = _session_state(sk)
        parts = data.strip().split()
        cmd = parts[0].lower() if parts else "cat"
        n_lines = 10
        arg_tokens = parts[1:] if len(parts) > 1 else []
        path_bits = []
        i = 0
        while i < len(arg_tokens):
            t = arg_tokens[i]
            if t in {"-n", "--lines"} and i + 1 < len(arg_tokens):
                try:
                    n_lines = max(1, min(500, int(arg_tokens[i + 1])))
                except Exception:
                    pass
                i += 2
                continue
            if t.startswith("-n") and len(t) > 2 and t[2:].isdigit():
                n_lines = max(1, min(500, int(t[2:])))
                i += 1
                continue
            if t.startswith("-") and t not in {"-"}:
                i += 1
                continue
            path_bits.append(t)
            i += 1
        arg = " ".join(path_bits)
        path = arg or "(empty)"
        wd = st_c.get("workdir") or "/workspace"
        # resolve relative to workdir
        if path.startswith("/"):
            rel = path.replace("/workspace", "").lstrip("/")
        else:
            base = wd.replace("/workspace", "").lstrip("/")
            rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
        node, cleaned = _ws_resolve(rel)
        if node is None or node.get("type") != "file":
            out(f"{cmd}: {path}: No such file\n", done=True, exit_code=1)
        else:
            content = node.get("content") or ""
            if cmd == "wc":
                lines = content.count("\n") + (0 if content.endswith("\n") or not content else 1)
                words = len(content.split())
                out(f"{lines} {words} {len(content)} {cleaned or path}\n", done=True, exit_code=0)
            elif cmd == "head":
                out("\n".join(content.splitlines()[:n_lines]) + ("\n" if content else ""), done=True, exit_code=0)
            elif cmd == "tail":
                out("\n".join(content.splitlines()[-n_lines:]) + ("\n" if content else ""), done=True, exit_code=0)
            else:
                out(content if content.endswith("\n") or not content else content + "\n", done=True, exit_code=0)
    elif lower == "date" or lower.startswith("date ") or lower.startswith("date+"):
        # Limited date formats (mock): default ISO; supports -u and +FMT subset
        use_utc = "-u" in lower.split() or lower.startswith("date -u")
        fmt = None
        raw = data.strip()
        if "+" in raw:
            fmt = raw[raw.index("+") + 1 :].strip()
        tstruct = time.gmtime() if use_utc else time.localtime()
        if not fmt:
            out(time.strftime("%Y-%m-%dT%H:%M:%SZ" if use_utc else "%Y-%m-%d %H:%M:%S %z", tstruct) + "\n", done=True, exit_code=0)
        else:
            # map common tokens
            mapping = {
                "%Y": "%Y", "%m": "%m", "%d": "%d", "%H": "%H", "%M": "%M", "%S": "%S",
                "%F": "%Y-%m-%d", "%T": "%H:%M:%S", "%s": str(int(time.time())),
            }
            out_s = fmt
            if "%s" in out_s:
                out_s = out_s.replace("%s", str(int(time.mktime(tstruct)) if not use_utc else int(time.time())))
            try:
                # convert remaining via strftime if looks like strftime
                py_fmt = out_s
                for k in ("%F", "%T", "%Y", "%m", "%d", "%H", "%M", "%S"):
                    pass
                rendered = time.strftime(py_fmt.replace("%F", "%Y-%m-%d").replace("%T", "%H:%M:%S"), tstruct)
                out(rendered + "\n", done=True, exit_code=0)
            except Exception:
                out(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n", done=True, exit_code=0)
    elif lower in {"env", "printenv"}:
        st_e = _session_state(sk)
        lines = [
            "TERM=huanhermes-mock",
            "USER=huanhermes-mock",
            f"PWD={st_e.get('workdir') or '/workspace'}",
            f"COLUMNS={st_e.get('term_cols') or 80}",
            f"LINES={st_e.get('term_rows') or 24}",
            f"HH_SESSION={sk}",
        ]
        extra = st_e.get("env") if isinstance(st_e.get("env"), dict) else {}
        for k in sorted(extra.keys()):
            lines.append(f"{k}={extra[k]}")
        out("\n".join(lines) + "\n", done=True, exit_code=0)
    elif lower in {"stty size", "stty", "tty size", "size"}:
        st_g = _session_state(sk)
        cols_g = st_g.get("term_cols") or 80
        rows_g = st_g.get("term_rows") or 24
        # stty size prints rows cols
        out(f"{rows_g} {cols_g}\n", done=True, exit_code=0)

    elif lower in {"tree", "tree -L 2", "tree -L 3"} or lower.startswith("tree "):
        st_t = _session_state(sk)
        rel = (st_t.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
        node, _ = _ws_resolve(rel)
        if node is None or node.get("type") != "dir":
            out("tree: invalid workdir\n", done=True, exit_code=1)
        else:
            lines = ["."]
            def walk(n, prefix=""):
                kids = n.get("children") or {}
                items = sorted(kids.items(), key=lambda x: (x[1].get("type") != "dir", x[0]))
                for idx, (name, child) in enumerate(items):
                    last = idx == len(items) - 1
                    branch = "└── " if last else "├── "
                    lines.append(prefix + branch + name + ("/" if child.get("type") == "dir" else ""))
                    if child.get("type") == "dir" and len(prefix) < 12:
                        walk(child, prefix + ("    " if last else "│   "))
            walk(node)
            out("\n".join(lines) + "\n", done=True, exit_code=0)
    elif lower in {"df", "df -h"}:
        out(
            "Filesystem      Size  Used Avail Use% Mounted on\n"
            "mockfs           8.0G  1.2G  6.8G  15% /workspace\n",
            done=True,
            exit_code=0,
        )
    elif lower in {"free", "free -h", "free -m"}:
        out(
            "              total        used        free\n"
            "Mem:           5.8G        2.1G        3.7G\n"
            "Swap:            0B          0B          0B\n",
            done=True,
            exit_code=0,
        )
    elif lower in {"ps", "ps aux", "ps -ef"}:
        out(
            "PID TTY          TIME CMD\n"
            "  1 ?        00:00:01 mock-host\n"
            " 42 ?        00:00:00 bridge-ws\n"
            " 43 ?        00:00:00 mgmt-http\n",
            done=True,
            exit_code=0,
        )
    elif lower in {"uptime"}:
        out(" 12:00:00 up 3 days,  4:12,  1 user,  load average: 0.12, 0.08, 0.05\n", done=True, exit_code=0)


    elif lower.startswith("basename ") or lower.startswith("dirname ") or lower.startswith("realpath "):
        parts = data.strip().split(None, 1)
        cmd = parts[0].lower() if parts else ""
        arg = parts[1].strip() if len(parts) > 1 else ""
        st_p = _session_state(sk)
        wd = st_p.get("workdir") or "/workspace"
        if not arg:
            out(f"{cmd}: missing operand\n", done=True, exit_code=1)
        else:
            if arg.startswith("/"):
                path = arg
            else:
                path = (wd.rstrip("/") + "/" + arg).replace("//", "/")
            # normalize ..
            segs = []
            for p in path.split("/"):
                if not p or p == ".":
                    continue
                if p == "..":
                    if segs:
                        segs.pop()
                else:
                    segs.append(p)
            norm = "/" + "/".join(segs) if segs else "/"
            if cmd == "basename":
                out((segs[-1] if segs else "/") + "\n", done=True, exit_code=0)
            elif cmd == "dirname":
                out(("/" + "/".join(segs[:-1]) if len(segs) > 1 else "/") + "\n", done=True, exit_code=0)
            else:
                # realpath — stay under /workspace when relative
                if not norm.startswith("/workspace") and not arg.startswith("/"):
                    norm = "/workspace" + (norm if norm != "/" else "")
                out(norm + "\n", done=True, exit_code=0)
    elif lower.startswith("stat ") or lower == "stat":
        st_s = _session_state(sk)
        arg = data.strip()[4:].strip() if lower.startswith("stat") else ""
        if not arg:
            out("stat: missing operand\n", done=True, exit_code=1)
        else:
            wd = st_s.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None:
                out(f"stat: cannot stat '{arg}': No such file or directory\n", done=True, exit_code=1)
            else:
                typ = node.get("type") or "?"
                size = node.get("size")
                if size is None and typ == "file":
                    size = len(node.get("content") or "")
                if size is None:
                    size = 0
                out(
                    f"  File: {cleaned or arg}\n"
                    f"  Type: {typ}\n"
                    f"  Size: {size}\n"
                    f"  Mock: readonly workspace node\n",
                    done=True,
                    exit_code=0,
                )
    elif lower in {"du", "du -h", "du -sh", "du -s"} or lower.startswith("du "):
        st_d = _session_state(sk)
        rel = (st_d.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
        node, cleaned = _ws_resolve(rel)

        def du_size(n):
            if not n:
                return 0
            if n.get("type") == "file":
                return int(n.get("size") or len(n.get("content") or "") or 0)
            total = 0
            for child in (n.get("children") or {}).values():
                total += du_size(child)
            return total

        sz = du_size(node)
        label = cleaned or "."
        out(f"{sz}\t{label}\n", done=True, exit_code=0)


    elif lower in {"true", ":", "true -"}:
        out("", done=True, exit_code=0)
    elif lower in {"false"}:
        out("", done=True, exit_code=1)
    elif lower.startswith("printf "):
        # minimal printf — no full format parser; strip outer quotes
        arg = data.strip()[7:].strip()
        if (arg.startswith('"') and arg.endswith('"')) or (arg.startswith("'") and arg.endswith("'")):
            arg = arg[1:-1]
        arg = arg.replace("\\n", "\n").replace("\\t", "\t")
        out(arg, done=True, exit_code=0)


    elif lower.startswith("sleep "):
        # Non-blocking mock: report intent only (no real delay — keeps Bridge responsive)
        arg = data.strip()[6:].strip() or "0"
        out(f"[mock-sleep] skipped ({arg}s) — mock does not block\n", done=True, exit_code=0)
    elif lower.startswith("touch "):
        name = data.strip()[6:].strip() or "(empty)"
        out(f"[mock-touch] refused (readonly workspace): {name}\n", done=True, exit_code=1)
    elif lower in {"history", "history 10"}:
        out(
            "    1  help\n"
            "    2  pwd\n"
            "    3  ls\n"
            "    4  tree\n"
            "    5  cat hermes/README.md\n",
            done=True,
            exit_code=0,
        )


    elif lower.startswith("grep ") or lower.startswith("grep -"):
        # Minimal: grep <pattern> [path] over workspace file contents (mock)
        parts = data.strip().split()
        # drop flags like -n -i -r for mock simplicity but honor -i
        flags = {p for p in parts[1:] if p.startswith("-")}
        args = [p for p in parts[1:] if not p.startswith("-")]
        if not args:
            out("grep: missing pattern\n", done=True, exit_code=2)
        else:
            pattern = args[0]
            path_arg = args[1] if len(args) > 1 else ""
            st_g = _session_state(sk)
            wd = st_g.get("workdir") or "/workspace"
            if path_arg:
                if path_arg.startswith("/"):
                    rel = path_arg.replace("/workspace", "").lstrip("/")
                else:
                    base = wd.replace("/workspace", "").lstrip("/")
                    rel = "/".join(p for p in (base + "/" + path_arg).split("/") if p and p != ".")
            else:
                rel = wd.replace("/workspace", "").lstrip("/")
            node, cleaned = _ws_resolve(rel)
            if node is None:
                out(f"grep: {path_arg or rel}: No such file or directory\n", done=True, exit_code=2)
            else:
                files = _ws_walk_files(node, cleaned)
                if node.get("type") == "file":
                    files = [(cleaned, node)]
                ignore_case = any(f in {"-i", "--ignore-case"} for f in flags) or "-i" in lower
                lines_out = []
                try:
                    import re as _re
                    rx = _re.compile(pattern, _re.I if ignore_case else 0)
                except Exception:
                    rx = None
                for fpath, fnode in files:
                    content = fnode.get("content") or ""
                    for i, line in enumerate(content.splitlines(), 1):
                        hit = False
                        if rx is not None:
                            hit = rx.search(line) is not None
                        else:
                            hay = line.lower() if ignore_case else line
                            needle = pattern.lower() if ignore_case else pattern
                            hit = needle in hay
                        if hit:
                            lines_out.append(f"{fpath}:{i}:{line}")
                if not lines_out:
                    out("", done=True, exit_code=1)
                else:
                    out("\n".join(lines_out[:200]) + "\n", done=True, exit_code=0)
    elif lower.startswith("find ") or lower == "find" or lower.startswith("find ."):
        parts = data.strip().split()
        path_arg = "."
        name_pat = None
        type_f = None
        i = 1
        while i < len(parts):
            p = parts[i]
            if p == "-name" and i + 1 < len(parts):
                name_pat = parts[i + 1].strip("'\"")
                i += 2
                continue
            if p == "-type" and i + 1 < len(parts):
                type_f = parts[i + 1]
                i += 2
                continue
            if not p.startswith("-") and path_arg == ".":
                path_arg = p
            i += 1
        st_f = _session_state(sk)
        wd = st_f.get("workdir") or "/workspace"
        if path_arg in {".", "./"}:
            rel = wd.replace("/workspace", "").lstrip("/")
        elif path_arg.startswith("/"):
            rel = path_arg.replace("/workspace", "").lstrip("/")
        else:
            base = wd.replace("/workspace", "").lstrip("/")
            rel = "/".join(p for p in (base + "/" + path_arg).split("/") if p and p != ".")
        node, cleaned = _ws_resolve(rel)
        if node is None:
            out(f"find: '{path_arg}': No such file or directory\n", done=True, exit_code=1)
        else:
            results = []

            def walk(n, prefix):
                if not n:
                    return
                typ = n.get("type")
                if typ == "file":
                    if type_f in (None, "f"):
                        base = prefix.split("/")[-1] if prefix else ""
                        if name_pat is None or _fnmatch(base, name_pat):
                            results.append(prefix or ".")
                    return
                # dir
                if type_f in (None, "d") and prefix:
                    base = prefix.split("/")[-1]
                    if name_pat is None or _fnmatch(base, name_pat):
                        if type_f == "d" or name_pat:
                            results.append(prefix)
                kids = n.get("children") or {}
                for name, child in sorted(kids.items()):
                    p = f"{prefix}/{name}" if prefix else name
                    walk(child, p)

            def _fnmatch(name, pat):
                import fnmatch
                return fnmatch.fnmatch(name, pat)

            walk(node, cleaned)
            if not results and node.get("type") != "file":
                # always list files if no filter
                for fpath, _ in _ws_walk_files(node, cleaned):
                    if name_pat is None or _fnmatch(fpath.split("/")[-1], name_pat):
                        if type_f in (None, "f"):
                            results.append(fpath)
            out(("\n".join(results[:200]) + ("\n" if results else "")), done=True, exit_code=0)
    elif lower.startswith("seq "):
        parts = data.strip().split()
        try:
            if len(parts) == 2:
                end = int(parts[1]); start = 1; step = 1
            elif len(parts) == 3:
                start = int(parts[1]); end = int(parts[2]); step = 1
            elif len(parts) >= 4:
                start = int(parts[1]); step = int(parts[2]); end = int(parts[3])
            else:
                raise ValueError("args")
            if step == 0:
                raise ValueError("step")
            vals = []
            x = start
            if step > 0:
                while x <= end and len(vals) < 500:
                    vals.append(str(x)); x += step
            else:
                while x >= end and len(vals) < 500:
                    vals.append(str(x)); x += step
            out("\n".join(vals) + ("\n" if vals else ""), done=True, exit_code=0)
        except Exception:
            out("seq: invalid arguments\n", done=True, exit_code=1)


    elif lower.startswith("sort") or lower == "sort":
        # sort lines from stdin not available — sort mock list args or help
        args = data.strip().split(None, 1)
        payload = args[1] if len(args) > 1 else ""
        if not payload:
            out("sort: (mock) pass space-separated tokens to sort\n", done=True, exit_code=0)
        else:
            # if multiline use lines else tokens
            if "\n" in payload:
                lines = payload.splitlines()
            else:
                lines = payload.split()
            reverse = "-r" in lower
            lines = sorted(lines, reverse=reverse)
            out("\n".join(lines) + ("\n" if lines else ""), done=True, exit_code=0)
    elif lower.startswith("export "):
        # mock env set — session-local only
        assign = data.strip()[7:].strip()
        if "=" not in assign:
            out("export: mock expects NAME=value\n", done=True, exit_code=1)
        else:
            name, _, val = assign.partition("=")
            name = name.strip()
            val = val.strip().strip("'\"")
            st_x = _session_state(sk)
            env = st_x.setdefault("env", {})
            if not isinstance(env, dict):
                env = {}
                st_x["env"] = env
            env[name] = val
            out("", done=True, exit_code=0)


    elif lower.startswith("base64 ") or lower in {"base64", "base64 --help"}:
        import base64 as _b64
        parts = data.strip().split(None, 1)
        args = parts[1] if len(parts) > 1 else ""
        decode = "-d" in lower or "--decode" in lower or "-D" in lower
        # strip flags
        tokens = args.split()
        path = None
        raw_bits = []
        for t in tokens:
            if t.startswith("-"):
                continue
            if path is None:
                path = t
            else:
                raw_bits.append(t)
        if path is None and not raw_bits:
            out("base64: missing input (mock: path or literal)\n", done=True, exit_code=1)
        else:
            content = None
            if path:
                st_b = _session_state(sk)
                wd = st_b.get("workdir") or "/workspace"
                if path.startswith("/"):
                    rel = path.replace("/workspace", "").lstrip("/")
                else:
                    base = wd.replace("/workspace", "").lstrip("/")
                    rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
                node, _ = _ws_resolve(rel)
                if node and node.get("type") == "file":
                    content = node.get("content") or ""
                elif raw_bits:
                    content = " ".join([path] + raw_bits)
                else:
                    # treat path as literal string
                    content = path
            else:
                content = " ".join(raw_bits)
            try:
                if decode:
                    pad = (-len(content.strip())) % 4
                    raw = _b64.b64decode(content.strip() + ("=" * pad))
                    out(raw.decode("utf-8", errors="replace"), done=True, exit_code=0)
                else:
                    out(_b64.b64encode(content.encode("utf-8")).decode("ascii") + "\n", done=True, exit_code=0)
            except Exception as e:
                out(f"base64: {e}\n", done=True, exit_code=1)
    elif lower.startswith("file ") or lower == "file":
        arg = data.strip()[4:].strip() if lower.startswith("file") else ""
        if not arg:
            out("file: missing operand\n", done=True, exit_code=1)
        else:
            st_f = _session_state(sk)
            wd = st_f.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None:
                out(f"{arg}: cannot open (No such file or directory)\n", done=True, exit_code=1)
            elif node.get("type") == "dir":
                out(f"{cleaned or arg}: directory\n", done=True, exit_code=0)
            else:
                name = cleaned or arg
                content = node.get("content") or ""
                if name.endswith((".py",)):
                    kind = "Python script text"
                elif name.endswith((".md", ".markdown")):
                    kind = "Markdown text"
                elif name.endswith((".json",)):
                    kind = "JSON text"
                elif name.endswith((".sh", ".bash")):
                    kind = "Bourne-Again shell script text"
                else:
                    kind = "ASCII text" if content.isascii() else "UTF-8 text"
                out(f"{name}: {kind}\n", done=True, exit_code=0)
    elif lower.startswith("uniq") or lower == "uniq":
        args = data.strip().split(None, 1)
        payload = args[1] if len(args) > 1 else ""
        if not payload:
            out("uniq: (mock) pass tokens/lines to dedupe\n", done=True, exit_code=0)
        else:
            lines = payload.splitlines() if "\n" in payload else payload.split()
            out_lines = []
            prev = object()
            for ln in lines:
                if ln != prev:
                    out_lines.append(ln)
                    prev = ln
            out("\n".join(out_lines) + ("\n" if out_lines else ""), done=True, exit_code=0)
    elif lower.startswith("type ") or lower == "type":
        # bash type/command -v style
        name = data.strip()[4:].strip() if lower.startswith("type") else ""
        if not name:
            out("type: missing operand\n", done=True, exit_code=1)
        else:
            builtins = {
                "ls", "pwd", "cd", "cat", "head", "tail", "wc", "echo", "env", "export", "date",
                "uname", "hostname", "id", "clear", "mkdir", "stty", "whoami", "help", "tree",
                "df", "free", "ps", "uptime", "stat", "du", "basename", "dirname", "realpath",
                "which", "true", "false", "printf", "sleep", "touch", "history", "grep", "find",
                "seq", "sort", "base64", "file", "uniq", "type", "cut", "nl", "fold", "tr", "rev",
                "cmp", "yes", "tee", "xargs", "hexdump", "xxd", "od", "jq", "md5sum", "sha1sum",
                                "sha256sum", "expr", "test", "factor", "bc", "nproc", "arch", "getconf", "numfmt",
                            }
            if name.split()[0] in builtins:
                out(f"{name.split()[0]} is a shell builtin\n", done=True, exit_code=0)
            else:
                out(f"type: {name}: not found\n", done=True, exit_code=1)


    elif lower.startswith("md5sum") or lower.startswith("sha256sum") or lower.startswith("sha1sum"):
        import hashlib as _hl
        parts = data.strip().split()
        cmd = parts[0].lower() if parts else "md5sum"
        algo = "md5" if "md5" in cmd else ("sha1" if "sha1" in cmd else "sha256")
        targets = [p for p in parts[1:] if not p.startswith("-")]
        if not targets:
            out(f"{cmd}: missing file operand\n", done=True, exit_code=1)
        else:
            lines_out = []
            st_h = _session_state(sk)
            wd = st_h.get("workdir") or "/workspace"
            for path in targets:
                if path.startswith("/"):
                    rel = path.replace("/workspace", "").lstrip("/")
                else:
                    base = wd.replace("/workspace", "").lstrip("/")
                    rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
                node, cleaned = _ws_resolve(rel)
                if node is None or node.get("type") != "file":
                    lines_out.append(f"{cmd}: {path}: No such file or directory")
                    continue
                content = (node.get("content") or "").encode("utf-8")
                h = getattr(_hl, algo)(content).hexdigest()
                lines_out.append(f"{h}  {cleaned or path}")
            out("\n".join(lines_out) + "\n", done=True, exit_code=0)
    elif lower.startswith("nl ") or lower == "nl":
        arg = data.strip()[2:].strip() if lower.startswith("nl") else ""
        # strip -ba style flags
        while arg.startswith("-"):
            bits = arg.split(None, 1)
            arg = bits[1] if len(bits) > 1 else ""
        if not arg:
            out("nl: missing file operand\n", done=True, exit_code=1)
        else:
            st_n = _session_state(sk)
            wd = st_n.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"nl: {arg}: No such file or directory\n", done=True, exit_code=1)
            else:
                content = node.get("content") or ""
                numbered = []
                for i, line in enumerate(content.splitlines(), 1):
                    numbered.append(f"{i:6}\t{line}")
                out("\n".join(numbered) + ("\n" if numbered else ""), done=True, exit_code=0)
    elif lower.startswith("cut ") or lower == "cut":
        # cut -dSEP -fN  TEXT  or cut -cN- path
        parts = data.strip().split()
        delim = "\t"
        fields = None
        chars = None
        rest = []
        i = 1
        while i < len(parts):
            t = parts[i]
            if t == "-d" and i + 1 < len(parts):
                delim = parts[i + 1]
                i += 2
                continue
            if t.startswith("-d") and len(t) > 2:
                delim = t[2:]
                i += 1
                continue
            if t == "-f" and i + 1 < len(parts):
                fields = parts[i + 1]
                i += 2
                continue
            if t.startswith("-f") and len(t) > 2:
                fields = t[2:]
                i += 1
                continue
            if t == "-c" and i + 1 < len(parts):
                chars = parts[i + 1]
                i += 2
                continue
            if t.startswith("-c") and len(t) > 2:
                chars = t[2:]
                i += 1
                continue
            if t.startswith("-"):
                i += 1
                continue
            rest.append(t)
            i += 1
        payload = " ".join(rest)
        if not payload:
            out("cut: missing operand\n", done=True, exit_code=1)
        else:
            # try resolve as file else use as text
            st_c = _session_state(sk)
            wd = st_c.get("workdir") or "/workspace"
            path = payload
            if path.startswith("/"):
                rel = path.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
            node, _ = _ws_resolve(rel)
            text = (node.get("content") if node and node.get("type") == "file" else payload) or ""
            out_lines = []
            for line in text.splitlines() or [text]:
                if chars:
                    # simple N or N-M
                    try:
                        if "-" in chars:
                            a, b = chars.split("-", 1)
                            a_i = int(a) - 1 if a else 0
                            b_i = int(b) if b else len(line)
                            out_lines.append(line[max(0, a_i):b_i])
                        else:
                            ci = int(chars) - 1
                            out_lines.append(line[ci] if 0 <= ci < len(line) else "")
                    except Exception:
                        out_lines.append(line)
                elif fields:
                    cols = line.split(delim)
                    idxs = []
                    for part in fields.split(","):
                        part = part.strip()
                        if not part:
                            continue
                        try:
                            if "-" in part:
                                a, b = part.split("-", 1)
                                a_i = int(a) if a else 1
                                b_i = int(b) if b else len(cols)
                                idxs.extend(range(a_i, b_i + 1))
                            else:
                                idxs.append(int(part))
                        except Exception:
                            continue
                    picked = []
                    for ix in idxs:
                        if 1 <= ix <= len(cols):
                            picked.append(cols[ix - 1])
                    out_lines.append(delim.join(picked))
                else:
                    out_lines.append(line)
            out("\n".join(out_lines) + ("\n" if out_lines else ""), done=True, exit_code=0)


    elif lower.startswith("fold ") or lower == "fold":
        parts = data.strip().split()
        width = 80
        path = None
        i = 1
        while i < len(parts):
            t = parts[i]
            if t in {"-w", "--width"} and i + 1 < len(parts):
                try:
                    width = max(8, min(200, int(parts[i + 1])))
                except Exception:
                    pass
                i += 2
                continue
            if t.startswith("-w") and len(t) > 2 and t[2:].isdigit():
                width = max(8, min(200, int(t[2:])))
                i += 1
                continue
            if t.startswith("-"):
                i += 1
                continue
            path = t
            i += 1
        if not path:
            out("fold: missing file operand\n", done=True, exit_code=1)
        else:
            st_f = _session_state(sk)
            wd = st_f.get("workdir") or "/workspace"
            if path.startswith("/"):
                rel = path.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
            node, _ = _ws_resolve(rel)
            text = (node.get("content") if node and node.get("type") == "file" else path) or ""
            out_lines = []
            for line in text.splitlines() or [text]:
                if not line:
                    out_lines.append("")
                    continue
                for j in range(0, len(line), width):
                    out_lines.append(line[j : j + width])
            out("\n".join(out_lines) + ("\n" if out_lines else ""), done=True, exit_code=0)
    elif lower.startswith("hexdump") or lower.startswith("xxd ") or lower == "xxd" or lower == "hexdump":
        parts = data.strip().split()
        path = next((p for p in parts[1:] if not p.startswith("-")), None)
        if not path:
            out("hexdump: missing file operand\n", done=True, exit_code=1)
        else:
            st_x = _session_state(sk)
            wd = st_x.get("workdir") or "/workspace"
            if path.startswith("/"):
                rel = path.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"hexdump: {path}: No such file or directory\n", done=True, exit_code=1)
            else:
                raw = (node.get("content") or "").encode("utf-8")
                lines = []
                for off in range(0, min(len(raw), 256), 16):
                    chunk = raw[off : off + 16]
                    hexpart = " ".join(f"{b:02x}" for b in chunk)
                    asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
                    lines.append(f"{off:08x}  {hexpart:<48}  |{asc}|")
                if len(raw) > 256:
                    lines.append(f"... ({len(raw)} bytes total, showing first 256)")
                out("\n".join(lines) + "\n", done=True, exit_code=0)
    elif lower.startswith("jq ") or lower == "jq":
        # minimal: jq . path  or jq . <<< json
        parts = data.strip().split(None, 2)
        # jq . file
        expr = "."
        path = None
        tokens = data.strip().split()
        for t in tokens[1:]:
            if t.startswith("-"):
                continue
            if t.startswith(".") and path is None and expr == ".":
                expr = t
                continue
            if path is None and not t.startswith("."):
                path = t
        if path is None:
            out("jq: (mock) usage: jq . <file.json>\n", done=True, exit_code=1)
        else:
            st_j = _session_state(sk)
            wd = st_j.get("workdir") or "/workspace"
            if path.startswith("/"):
                rel = path.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
            node, _ = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"jq: {path}: No such file or directory\n", done=True, exit_code=1)
            else:
                content = node.get("content") or ""
                try:
                    import json as _json
                    obj = _json.loads(content)
                    if expr in {".", ""}:
                        out(_json.dumps(obj, indent=2, ensure_ascii=False) + "\n", done=True, exit_code=0)
                    elif expr.startswith(".") and len(expr) > 1:
                        key = expr[1:].split(".")[0].split("[")[0]
                        if isinstance(obj, dict) and key in obj:
                            out(_json.dumps(obj[key], indent=2, ensure_ascii=False) + "\n", done=True, exit_code=0)
                        else:
                            out("null\n", done=True, exit_code=0)
                    else:
                        out(_json.dumps(obj, indent=2, ensure_ascii=False) + "\n", done=True, exit_code=0)
                except Exception as e:
                    out(f"jq: parse error: {e}\n", done=True, exit_code=1)


    elif lower.startswith("tr ") or lower == "tr":
        parts = data.strip().split()
        delete = False
        args = []
        for t in parts[1:]:
            if t in {"-d", "--delete"}:
                delete = True
                continue
            if t.startswith("-"):
                continue
            args.append(t)
        if len(args) < 1:
            out("tr: missing operand\n", done=True, exit_code=1)
        else:
            if delete:
                s1 = args[0]
                text = " ".join(args[1:]) if len(args) > 1 else ""
                out("".join(ch for ch in text if ch not in s1) + "\n", done=True, exit_code=0)
            else:
                if len(args) < 2:
                    out("tr: missing operand\n", done=True, exit_code=1)
                else:
                    s1, s2 = args[0], args[1]
                    text = " ".join(args[2:]) if len(args) > 2 else ""
                    table = {}
                    for i, ch in enumerate(s1):
                        table[ch] = s2[i] if i < len(s2) else (s2[-1] if s2 else ch)
                    out("".join(table.get(ch, ch) for ch in text) + "\n", done=True, exit_code=0)
    elif lower.startswith("rev ") or lower == "rev":
        arg = data.strip()[3:].strip() if lower.startswith("rev") else ""
        while arg.startswith("-"):
            bits = arg.split(None, 1)
            arg = bits[1] if len(bits) > 1 else ""
        if not arg:
            out("rev: missing operand\n", done=True, exit_code=1)
        else:
            st_r = _session_state(sk)
            wd = st_r.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, _ = _ws_resolve(rel)
            text = (node.get("content") if node and node.get("type") == "file" else arg) or ""
            out("\n".join(line[::-1] for line in text.splitlines()) + ("\n" if text else ""), done=True, exit_code=0)
    elif lower.startswith("cmp ") or lower == "cmp":
        parts = [p for p in data.strip().split()[1:] if not p.startswith("-")]
        if len(parts) < 2:
            out("cmp: missing operand\n", done=True, exit_code=1)
        else:
            st_c = _session_state(sk)
            wd = st_c.get("workdir") or "/workspace"
            contents = []
            ok = True
            for path in parts[:2]:
                if path.startswith("/"):
                    rel = path.replace("/workspace", "").lstrip("/")
                else:
                    base = wd.replace("/workspace", "").lstrip("/")
                    rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
                node, cleaned = _ws_resolve(rel)
                if node is None or node.get("type") != "file":
                    out(f"cmp: {path}: No such file or directory\n", done=True, exit_code=2)
                    ok = False
                    break
                contents.append((cleaned or path, node.get("content") or ""))
            if ok:
                (n1, c1), (n2, c2) = contents
                if c1 == c2:
                    out("", done=True, exit_code=0)
                else:
                    lim = min(len(c1), len(c2))
                    pos = lim
                    for i in range(lim):
                        if c1[i] != c2[i]:
                            pos = i
                            break
                    out(f"{n1} {n2} differ: byte {pos + 1}\n", done=True, exit_code=1)


    elif lower.startswith("yes ") or lower == "yes":
        # mock: print a few lines only (avoid infinite)
        arg = data.strip()[3:].strip() if lower.startswith("yes") else ""
        msg = arg if arg else "y"
        out(("\n".join([msg] * 5) + "\n"), done=True, exit_code=0)
    elif lower.startswith("tee ") or lower == "tee":
        # mock: echo stdin-like args to output; "write" note only
        parts = data.strip().split()
        paths = [p for p in parts[1:] if not p.startswith("-")]
        # remaining treated as content if no file resolve
        content = " ".join(paths) if paths else ""
        note = f"(mock tee wrote {len(content)} bytes"
        if paths:
            note += f" → {paths[0]}"
        note += ")\n"
        out((content + ("\n" if content and not content.endswith("\n") else "")) + note, done=True, exit_code=0)
    elif lower.startswith("xargs ") or lower == "xargs":
        # mock: xargs echo a b c  → echo a b c once
        parts = data.strip().split()
        # drop xargs flags
        i = 1
        cmd_parts = []
        while i < len(parts):
            t = parts[i]
            if t.startswith("-") and t not in {"-"}:
                if t in {"-n", "-I", "-i", "-d"} and i + 1 < len(parts):
                    i += 2
                    continue
                i += 1
                continue
            cmd_parts = parts[i:]
            break
        if not cmd_parts:
            out("xargs: (mock) missing command\n", done=True, exit_code=1)
        else:
            out(" ".join(cmd_parts) + "\n", done=True, exit_code=0)
    elif lower.startswith("od ") or lower == "od":
        # mock octal dump (first 64 bytes)
        parts = data.strip().split()
        targets = [p for p in parts[1:] if not p.startswith("-")]
        if not targets:
            out("od: missing file operand\n", done=True, exit_code=1)
        else:
            st_od = _session_state(sk)
            wd = (st_od.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
            path = targets[0]
            rel = path
            if not path.startswith("/"):
                rel = (wd + "/" + path).strip("/") if wd else path
            else:
                rel = path.replace("/workspace", "").lstrip("/")
            node, cleaned = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"od: {path}: No such file or directory\n", done=True, exit_code=1)
            else:
                raw = (node.get("content") or "")[:64].encode("utf-8", errors="replace")
                lines = []
                for off in range(0, len(raw), 8):
                    chunk = raw[off : off + 8]
                    octs = " ".join(f"{b:03o}" for b in chunk)
                    lines.append(f"{off:07o} {octs}")
                out(("\n".join(lines) + ("\n" if lines else "")), done=True, exit_code=0)
    elif lower.startswith("expr ") or lower == "expr":
        # mock: expr N + M / - / *  (integers only)
        parts = data.strip().split()
        if len(parts) < 4:
            out("expr: (mock) usage: expr N OP M\n", done=True, exit_code=1)
        else:
            try:
                a = int(parts[1])
                op = parts[2]
                b = int(parts[3])
                if op == "+":
                    r = a + b
                elif op == "-":
                    r = a - b
                elif op in {"*", "\\*", "x"}:
                    r = a * b
                elif op == "/":
                    if b == 0:
                        out("expr: division by zero\n", done=True, exit_code=2)
                        r = None
                    else:
                        r = a // b
                elif op == "%":
                    if b == 0:
                        out("expr: division by zero\n", done=True, exit_code=2)
                        r = None
                    else:
                        r = a % b
                else:
                    out(f"expr: (mock) unsupported op {op}\n", done=True, exit_code=1)
                    r = None
                if r is not None:
                    out(f"{r}\n", done=True, exit_code=0)
            except Exception:
                out("expr: non-integer argument\n", done=True, exit_code=1)
    elif lower.startswith("test ") or lower == "test" or lower.startswith("[ ") or lower == "[":
        # mock test/[ : -n/-z string, -eq/-ne/-lt/-gt numbers, -f/-d path
        raw = data.strip()
        if raw.startswith("["):
            raw = raw[1:].strip()
            if raw.endswith("]"):
                raw = raw[:-1].strip()
        elif raw.lower().startswith("test"):
            raw = raw[4:].strip()
        parts = raw.split()
        if not parts:
            out("", done=True, exit_code=1)
        else:
            ok = False
            try:
                if parts[0] == "-n" and len(parts) >= 2:
                    ok = len(parts[1]) > 0
                elif parts[0] == "-z" and len(parts) >= 2:
                    ok = len(parts[1]) == 0
                elif parts[0] in {"-f", "-d"} and len(parts) >= 2:
                    st_t = _session_state(sk)
                    wd = (st_t.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
                    path = parts[1]
                    rel = path
                    if not path.startswith("/"):
                        rel = (wd + "/" + path).strip("/") if wd else path
                    else:
                        rel = path.replace("/workspace", "").lstrip("/")
                    node, _ = _ws_resolve(rel)
                    if parts[0] == "-f":
                        ok = bool(node and node.get("type") == "file")
                    else:
                        ok = bool(node and node.get("type") == "dir") or (rel == "" or path in {"/workspace", "."})
                elif len(parts) >= 3 and parts[1] in {"-eq", "-ne", "-lt", "-gt", "-le", "-ge"}:
                    a = int(parts[0])
                    b = int(parts[2])
                    op = parts[1]
                    ok = {
                        "-eq": a == b,
                        "-ne": a != b,
                        "-lt": a < b,
                        "-gt": a > b,
                        "-le": a <= b,
                        "-ge": a >= b,
                    }[op]
                elif len(parts) >= 3 and parts[1] in {"=", "!="}:
                    ok = (parts[0] == parts[2]) if parts[1] == "=" else (parts[0] != parts[2])
                else:
                    ok = bool(parts[0])
            except Exception:
                ok = False
            out("", done=True, exit_code=0 if ok else 1)

    elif lower == "nproc" or lower == "nproc --all":
        # mock fixed CPU count (demo only — not real nproc)
        out("4\n", done=True, exit_code=0)
    elif lower.startswith("factor ") or lower == "factor":
        # mock factor: trial division; refuse |N| > 10**12
        parts = data.strip().split()
        if len(parts) < 2:
            out("factor: missing operand\nUsage: factor NUMBER\n", done=True, exit_code=1)
        else:
            raw_n = parts[1]
            try:
                n = int(raw_n)
            except ValueError:
                out(f"factor: '{raw_n}' is not a valid positive integer\n", done=True, exit_code=1)
            else:
                if abs(n) > 10**12:
                    out(f"factor: '{raw_n}' is too large (mock cap 10^12)\n", done=True, exit_code=1)
                elif n == 0:
                    out("0:\n", done=True, exit_code=0)
                else:
                    # factor positive magnitude; keep sign only for display of original
                    m = abs(n)
                    factors: List[int] = []
                    d = 2
                    while d * d <= m:
                        while m % d == 0:
                            factors.append(d)
                            m //= d
                        d += 1 if d == 2 else 2
                    if m > 1:
                        factors.append(m)
                    out(f"{n}: {' '.join(str(p) for p in factors)}\n", done=True, exit_code=0)
    elif lower.startswith("bc ") or lower == "bc" or lower.startswith("bc -e ") or lower.startswith("bc -e"):
        # simple mock calculator: integers + - * / % and parentheses via sanitized eval
        raw = data.strip()
        expr = ""
        # support: bc EXPR | bc -e EXPR | bc -e 'EXPR'
        if lower == "bc":
            expr = ""
        else:
            rest = raw[2:].strip()  # after "bc"
            if rest.lower().startswith("-e"):
                rest = rest[2:].strip()
            # strip one layer of matching quotes
            if (rest.startswith("'") and rest.endswith("'")) or (rest.startswith('"') and rest.endswith('"')):
                if len(rest) >= 2:
                    rest = rest[1:-1]
            expr = rest
        # join is already via rest; allow spaces in expression
        if not expr or not expr.strip():
            out("bc: (mock) empty expression\n", done=True, exit_code=1)
        else:
            sanitized = expr.strip()
            if not re.fullmatch(r"[0-9+\-*/%() \t]+", sanitized):
                out("bc: (mock) invalid characters (only digits and + - * / % ( ) allowed)\n", done=True, exit_code=1)
            else:
                try:
                    # integer-only arithmetic; use // for / via custom? keep Python / for floats then int if whole
                    # Prefer integer ops: replace bare / with // only between numbers is hard; eval then require int
                    val = eval(sanitized, {"__builtins__": {}}, {})  # noqa: S307 — sanitized digits/ops only
                    if isinstance(val, float):
                        if val != int(val):
                            # still report float as int truncation? reject non-int results for mock simplicity
                            out(f"{val}\n", done=True, exit_code=0)
                        else:
                            out(f"{int(val)}\n", done=True, exit_code=0)
                    else:
                        out(f"{int(val)}\n", done=True, exit_code=0)
                except ZeroDivisionError:
                    out("bc: division by zero\n", done=True, exit_code=1)
                except Exception:
                    out("bc: (mock) expression error\n", done=True, exit_code=1)

    elif lower == "arch":
        # mock fixed arch (demo only — not real arch)
        out("x86_64\n", done=True, exit_code=0)
    elif lower.startswith("getconf ") or lower == "getconf":
        # mock getconf: only a few keys (NPROCESSORS_ONLN / PAGE_SIZE family)
        parts = data.strip().split()
        if len(parts) < 2:
            out("getconf: missing operand\nUsage: getconf NAME\n", done=True, exit_code=1)
        else:
            key = parts[1]
            if key in {"NPROCESSORS_ONLN", "_NPROCESSORS_ONLN"}:
                out("4\n", done=True, exit_code=0)
            elif key in {"PAGE_SIZE", "PAGESIZE"}:
                out("4096\n", done=True, exit_code=0)
            else:
                out("getconf: (mock) unknown key\n", done=True, exit_code=1)
    elif lower.startswith("numfmt ") or lower == "numfmt":
        # mock numfmt: simple humanize --to=iec (1024) / --to=si (1000)
        parts = data.strip().split()
        to = "iec"
        n_raw = None
        if len(parts) == 1:
            out("numfmt: missing operand\n", done=True, exit_code=1)
        else:
            i = 1
            while i < len(parts):
                p = parts[i]
                if p.startswith("--to="):
                    to = p.split("=", 1)[1].lower()
                    i += 1
                elif p == "--to" and i + 1 < len(parts):
                    to = parts[i + 1].lower()
                    i += 2
                else:
                    n_raw = p
                    break
            if n_raw is None:
                out("numfmt: missing operand\n", done=True, exit_code=1)
            else:
                try:
                    n = int(n_raw)
                except ValueError:
                    out("numfmt: invalid number\n", done=True, exit_code=1)
                else:
                    if to not in {"iec", "si"}:
                        out("numfmt: (mock) unsupported --to\n", done=True, exit_code=1)
                    else:
                        base = 1024 if to == "iec" else 1000
                        units = ["", "K", "M", "G", "T", "P"]
                        v = float(abs(n))
                        u = 0
                        while v >= base and u < len(units) - 1:
                            v /= base
                            u += 1
                        sign = "-" if n < 0 else ""
                        if u == 0:
                            out(f"{sign}{int(v)}\n", done=True, exit_code=0)
                        else:
                            out(f"{sign}{v:.1f}{units[u]}\n", done=True, exit_code=0)

    elif lower.startswith("echo "):
        out(data.strip()[5:] + "\n", done=True, exit_code=0)
    elif lower in {"clear", "cls"}:
        ws_send_text(
            conn,
            json.dumps({"type": "terminal_clear", "session_key": sk, "stream_id": stream_id}),
        )
        out("", done=True, exit_code=0)
    elif lower in {"exit", "quit"}:
        out("logout\n", done=True, exit_code=0)
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "terminal_exit",
                    "session_key": sk,
                    "stream_id": stream_id,
                    "exit_code": 0,
                }
            ),
        )
    else:
        out(f"mock-sh: command not found: {data.strip()}\n", done=True, exit_code=127)


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
    images = msg.get("images") or []
    files = msg.get("files") or []
    project = _project_hint(content)
    with SESSIONS_LOCK:
        if sk in SESSIONS and SESSIONS[sk].get("project"):
            project = SESSIONS[sk]["project"]
    # session_key platform:scope:user may include project-ish scopes
    if ":hermes" in sk or sk.startswith("huanhermes-app:hermes"):
        project = "hermes"
    _touch_session(sk, content=content, project=project)
    attach_note = ""
    if images or files:
        attach_note = f" [attachments: {len(images)} image(s), {len(files)} file(s)]"
    _append_transcript(sk, "user", (content or "(attachment)") + attach_note)

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

    activity_push("chat.message", f"message in {sk}", session_key=sk, preview=(content or "")[:80])
    if content.startswith("/"):
        reply = _mock_slash(sk, content)
        _stream_reply(conn, sk, ctx, reply, cancellable=False)
        return

    st = _session_state(sk)
    st_project = st.get("project") or project
    if st_project == "hermes":
        st["model"] = st.get("model") if st.get("model") not in ("mock-sonnet",) else "mock-hermes"
        q = (content or "").strip()
        mem_hits = 0
        mem_preview = "(no query)"
        if q:
            # Fake memory.search over a tiny local store for protocol demos.
            store = [
                "user prefers concise ship notes",
                "app is console-only; agent loop stays on Host",
                "never embed tokens in pairing URI",
                "mock hermes project demonstrates ADR-002 shape",
            ]
            hits = [m for m in store if any(w in m.lower() for w in q.lower().split() if len(w) > 2)]
            mem_hits = len(hits)
            mem_preview = "; ".join(hits[:3]) if hits else "0 hits"
        reply = (
            f"[hermes-mock|model={st.get('model')}|mode={st.get('mode')}]\n"
            f"Hermes-shaped session (ADR-002). User said: {content or '(no text)'}\n"
            f"{attach_note.strip()}\n\n"
            "### Hermes mock\n"
            "- **memory.search** stub over in-process phrases\n"
            f"- hits={mem_hits}: `{mem_preview}`\n"
            "- skills: hermes-agent (readonly catalog)\n\n"
            "| Agent | Status |\n"
            "| --- | --- |\n"
            "| hermes | mock |\n"
            "| claude-code | mock |\n\n"
            "- [x] memory.search stub\n"
            "- [ ] ~~real process~~ still mock (Host adapter later)\n"
            "- [ ] system notifications\n\n"
            "Docs: [ADR-002](docs/adr/002-hermes-adapter.md)\n\n"
            "```dart\n"
            "final caps = ['stream','tools','cancel','memory'];\n"
            "// Host maps Bridge → real Hermes later\n"
            "```\n\n"
            "This is NOT a live Hermes process.\n"
            f"workdir={st.get('workdir')}"
        )
        # hermes-flavored tool name
        tool_name = "memory.search"
        tool_out = f"{mem_hits} memories · {mem_preview}"
    else:
        reply = (
            f"[mock:{st_project}|{st.get('model')}|mode={st.get('mode')}] 收到：{content or '(attachment)'}\n"
            f"{attach_note}\n\n"
            "### Mock markdown\n"
            "这是 **HuanHermes Mock Host** 的流式回复，用于验证控制台 Markdown 渲染。\n\n"
            "- 列表项 · 粗体 · `inline code`\n"
            "- 真连服务器时，此处将由 Claude Code / Codex / Hermes 产生\n\n"
            "```\n"
            f"workdir={st.get('workdir')}\n"
            "```\n"
            f"> workdir={st.get('workdir')}"
        )
        tool_name = "echo"
        tool_out = "ok"
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
                "name": tool_name,
                "input": (content or attach_note)[:80],
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
                    "name": tool_name,
                    "output": tool_out,
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
    activity_push("session.create", f"session {sid}", project=project, title=title)
    host_log("info", f"session created {sid}", project=project, title=title)
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
                        "version": "mock-0.1.116",
                        "uptime_seconds": int(time.time() - START_TS),
                        "connected_platforms": ["bridge"],
                        "projects_count": len(PROJECTS),
                        "sessions_count": len(SESSIONS),
                        "active_runs": len(ACTIVE_RUNS),
                        "capabilities": [
                            "sessions",
                            "workspace_readonly",
                            "skills",
                            "mcp",
                            "pairing",
                            "terminal",
                            "memory_readonly",
                            "cron_readonly",
                            "diff_readonly",
                            "activity_readonly",
                            "logs_readonly",
                            "agents_catalog",
                        ],
                        "hermes": {
                            "adapter": "mock",
                            "process": False,
                            "adr": "002",
                            "note": "Bridge shape only — real Hermes process is Host-side later",
                        },
                        "bridge_adapters": [
                            {
                                "platform": "huanhermes-app",
                                "project": "*",
                                "capabilities": ["text", "buttons", "typing", "preview", "terminal"],
                            },
                            {
                                "platform": "hermes-mock",
                                "project": "hermes",
                                "capabilities": ["text", "buttons", "tools", "memory", "cancel"],
                                "status": "mock",
                            },
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
        # project-scoped: /projects/{name}/sessions
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
                        "agents": [
                            {
                                "id": "claudecode",
                                "name": "Claude Code",
                                "status": "mock",
                                "type": "claude-code",
                                "model": "mock-sonnet",
                                "provider": "mock",
                                "version": "0.1-mock",
                                "capabilities": ["stream", "tools", "cancel", "workdir", "mode"],
                                "description": "Project-scoped coding agent (mock)",
                            },
                            {
                                "id": "codex",
                                "name": "Codex",
                                "status": "mock",
                                "type": "codex",
                                "model": "mock-codex",
                                "provider": "mock",
                                "version": "0.1-mock",
                                "capabilities": ["stream", "tools", "cancel"],
                                "description": "Codex-style agent (mock)",
                            },
                            {
                                "id": "hermes",
                                "name": "Hermes",
                                "status": "mock",
                                "type": "hermes",
                                "model": "mock-hermes",
                                "provider": "mock",
                                "version": "0.1-mock",
                                "adapter": "mock",
                                "process": False,
                                "capabilities": ["stream", "tools", "cancel", "memory", "skills", "mcp"],
                                "description": "Mock Hermes shape (ADR-002); Host maps Bridge → real process later",
                                "note": "Not a live Hermes agent loop",
                            },
                            {
                                "id": "cursor",
                                "name": "Cursor",
                                "status": "mock",
                            },
                            {
                                "id": "opencode",
                                "name": "OpenCode",
                                "status": "mock",
                            },
                        ],
                        "platforms": ["bridge", "telegram"],
                        "note": "Catalog only — App does not run agents locally",
                    },
                },
            )
            return
        if path == "/api/v1/bridge/adapters":
            self._send(200, {"ok": True, "data": {"adapters": []}})
            return
        if path == "/api/v1/mcp":
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "servers": [
                            {
                                "name": "filesystem",
                                "status": "mock",
                                "kind": "stdio",
                                "enabled": True,
                                "tools": ["read_file", "list_dir"],
                                "description": "Readonly MCP catalog demo",
                            },
                            {
                                "name": "git",
                                "status": "mock",
                                "kind": "stdio",
                                "enabled": True,
                                "tools": ["status", "log"],
                                "description": "Readonly MCP catalog demo",
                            },
                            {
                                "name": "hermes-memory",
                                "status": "mock",
                                "kind": "inprocess",
                                "enabled": True,
                                "tools": ["memory.search", "memory.list"],
                                "description": "Mock Hermes memory tools (ADR-002 shape · not live process)",
                                "note": "Host maps to real Hermes memory later",
                            },
                            {
                                "name": "hermes-skills",
                                "status": "mock",
                                "kind": "inprocess",
                                "enabled": True,
                                "tools": ["skills.list", "skills.view"],
                                "description": "Readonly skills catalog surface for Hermes project",
                            },
                            {
                                "name": "offline-demo",
                                "status": "disabled",
                                "kind": "stdio",
                                "enabled": False,
                                "tools": [],
                                "description": "Sample disabled MCP server (catalog only)",
                                "note": "Not started by App",
                            },
                        ]
                    },
                },
            )
            return
        if path == "/api/v1/skills":
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "skills": [
                            {
                                "name": "hermes-agent",
                                "description": "Configure Hermes Agent (readonly mock)",
                                "source": "mock",
                                "category": "autonomous-ai-agents",
                                "version": "0.1-mock",
                                "tags": ["hermes", "console"],
                            },
                            {
                                "name": "github-pr-workflow",
                                "description": "PR lifecycle helpers (readonly mock)",
                                "source": "mock",
                                "category": "github",
                                "version": "0.1-mock",
                                "tags": ["git", "pr"],
                            },
                            {
                                "name": "systematic-debugging",
                                "description": "4-phase debugging checklist (readonly mock)",
                                "source": "mock",
                                "category": "software-development",
                                "version": "0.1-mock",
                                "tags": ["debug"],
                            },
                            {
                                "name": "writing-plans",
                                "description": "Implementation plans (readonly mock)",
                                "source": "mock",
                                "category": "software-development",
                                "version": "0.1-mock",
                                "tags": ["plan"],
                            },
                            {
                                "name": "memory-management",
                                "description": "Long-term memory prefs (readonly mock · ADR-002 shape)",
                                "source": "mock",
                                "category": "memory-management",
                                "version": "0.1-mock",
                                "tags": ["hermes", "memory"],
                            },
                        ]
                    },
                },
            )
            return
        if path == "/api/v1/pairing":
            # Device pairing payload for QR/text share (no secrets in repo defaults)
            token_hint = "use-app-stored-tokens"
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "scheme": "huanhermes",
                        "version": 1,
                        "host": BRIDGE_HOST if BRIDGE_HOST != "0.0.0.0" else "127.0.0.1",
                        "bridge_port": BRIDGE_PORT,
                        "mgmt_port": MGMT_PORT,
                        "use_tls": False,
                        "note": "Fill tokens on device; Host does not return live secrets here",
                        "pairing_code": f"huanhermes://connect?host=127.0.0.1&bridge={BRIDGE_PORT}&mgmt={MGMT_PORT}&tls=0",
                    },
                },
            )
            return
        if path == "/api/v1/workspace" or path == "/api/v1/workspace/":
            qs = parse_qs(urlparse(self.path).query)
            p = (qs.get("path") or [""])[0]
            data = workspace_list(p)
            if data.get("error"):
                self._send(404, {"ok": False, "error": data["error"], "path": p})
            else:
                self._send(200, {"ok": True, "data": data})
            return
        if path == "/api/v1/workspace/git":
            self._send(200, {"ok": True, "data": workspace_git_status()})
            return

        if path == "/api/v1/memory":
            q = parse_qs(urlparse(self.path).query)
            scope = (q.get("scope") or [None])[0]
            qtext = ((q.get("q") or [""])[0] or "").lower()
            items = list(MEMORY_ENTRIES)
            if scope:
                items = [m for m in items if m.get("scope") == scope]
            if qtext:
                items = [
                    m
                    for m in items
                    if qtext in (m.get("title") or "").lower()
                    or qtext in (m.get("content") or "").lower()
                    or qtext in " ".join(m.get("tags") or []).lower()
                ]
            self._send(200, {"ok": True, "data": {"memories": items, "count": len(items)}})
            return
        m = re.match(r"^/api/v1/memory/([^/]+)$", path)
        if m:
            mid = m.group(1)
            for ent in MEMORY_ENTRIES:
                if ent.get("id") == mid:
                    self._send(200, {"ok": True, "data": ent})
                    return
            self._send(404, {"ok": False, "error": "memory not found"})
            return

        if path == "/api/v1/logs":
            qs = parse_qs(urlparse(self.path).query)
            try:
                limit = int((qs.get("limit") or ["80"])[0])
            except ValueError:
                limit = 80
            limit = max(1, min(limit, 200))
            level = ((qs.get("level") or [""])[0] or "").lower()
            source = ((qs.get("source") or [""])[0] or "").lower()
            with HOST_LOGS_LOCK:
                items = list(HOST_LOGS)
            if level:
                items = [x for x in items if str(x.get("level", "")).lower() == level]
            if source:
                items = [
                    x
                    for x in items
                    if source in str(x.get("source") or x.get("logger") or x.get("component") or "").lower()
                ]
            items = items[-limit:]
            items = list(reversed(items))
            self._send(200, {"ok": True, "data": {"logs": items, "count": len(items)}})
            return
        if path == "/api/v1/activity":
            qs = parse_qs(urlparse(self.path).query)
            try:
                lim = int((qs.get("limit") or ["50"])[0])
            except ValueError:
                lim = 50
            self._send(200, {"ok": True, "data": {"events": activity_list(lim)}})
            return
        if path == "/api/v1/cron":
            self._send(200, {"ok": True, "data": {"jobs": CRON_JOBS}})
            return
        m = re.match(r"^/api/v1/cron/([^/]+)$", path)
        if m:
            jid = m.group(1)
            for job in CRON_JOBS:
                if job.get("id") == jid:
                    self._send(200, {"ok": True, "data": job})
                    return
            self._send(404, {"ok": False, "error": "cron job not found"})
            return
        if path == "/api/v1/workspace/diff":
            qs = parse_qs(urlparse(self.path).query)
            p = (qs.get("path") or [""])[0]
            self._send(200, {"ok": True, "data": workspace_diff(p)})
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
        # project-scoped POST /projects/{name}/sessions  (session_key optional; generated if missing)
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions$", path)
        if m:
            project = m.group(1)
            rec = _create_session_rec(project, body)
            self._send(200, {"ok": True, "data": rec})
            return
        self._send(404, {"ok": False, "error": "not found"})

    def do_PATCH(self) -> None:  # noqa: N802
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
        m = re.match(r"^/api/v1/sessions/(.+)$", path)
        proj_m = re.match(r"^/api/v1/projects/([^/]+)/sessions/(.+)$", path)
        sid = None
        if m:
            sid = m.group(1)
        elif proj_m:
            sid = proj_m.group(2)
        if sid:
            title = body.get("title") or body.get("name")
            if not title or not str(title).strip():
                self._send(400, {"ok": False, "error": "title required"})
                return
            title = str(title).strip()
            with SESSIONS_LOCK:
                rec = SESSIONS.get(sid)
                if not rec:
                    self._send(404, {"ok": False, "error": "session not found"})
                    return
                rec["title"] = title
                rec["name"] = title
                rec["updated_at"] = int(time.time())
                SESSIONS[sid] = rec
                out = dict(rec)
            activity_push("session.rename", f"renamed {sid}", session_id=sid, title=title)
            host_log("info", f"session renamed {sid} -> {title}", session_id=sid)
            self._send(200, {"ok": True, "data": out})
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
    activity_push("host.start", "Mock Host started", bridge=BRIDGE_PORT, mgmt=MGMT_PORT)
    host_log("info", "Mock Host started", bridge=BRIDGE_PORT, mgmt=MGMT_PORT)
    host_log("info", "Management HTTP ready")
    host_log("debug", "Seed demo log lines for console")
    log("starting HuanHermes Mock Host")
    log(f"BRIDGE_TOKEN set (len={len(BRIDGE_TOKEN)}) MGMT_TOKEN set (len={len(MGMT_TOKEN)})")
    t = threading.Thread(target=mgmt_server, name="mgmt", daemon=True)
    t.start()
    bridge_server()


if __name__ == "__main__":
    main()
