#!/usr/bin/env python3
"""Test environment for the phone-side local agent.

Starts two loopback services:
  * a tiny SSH server (paramiko, password auth) that runs exec requests with
    ``sh -c`` inside a scratch directory, and
  * a scripted OpenAI-compatible ``/v1/chat/completions`` endpoint that drives
    the agent through list_servers -> run_command -> final answer.

Only for tests and CI. Binds 127.0.0.1 by default (the Android emulator reaches
it as 10.0.2.2). Prints one JSON line with the ports and host key fingerprint.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import paramiko

USER = "hh"
PASSWORD = "hh-test"


class _Server(paramiko.ServerInterface):
    def __init__(self) -> None:
        self.command: bytes | None = None
        self.event = threading.Event()

    def check_auth_password(self, username: str, password: str) -> int:
        ok = username == USER and password == PASSWORD
        return paramiko.AUTH_SUCCESSFUL if ok else paramiko.AUTH_FAILED

    def get_allowed_auths(self, username: str) -> str:
        return "password"

    def check_channel_request(self, kind: str, chanid: int) -> int:
        return paramiko.OPEN_SUCCEEDED if kind == "session" else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_exec_request(self, channel, command: bytes) -> bool:
        self.command = command
        self.event.set()
        return True


def _run_exec(chan, srv: _Server, workdir: str) -> None:
    if not srv.event.wait(10):
        chan.close()
        return
    cmd = srv.command or b""
    srv.event.clear()
    env = dict(os.environ, HOME=workdir)
    try:
        p = subprocess.run(["sh", "-c", cmd.decode("utf-8", "replace")], cwd=workdir, env=env,
                           capture_output=True, timeout=60)
        chan.sendall(p.stdout)
        chan.sendall_stderr(p.stderr)
        chan.send_exit_status(p.returncode)
    except subprocess.TimeoutExpired:
        chan.sendall_stderr(b"timeout\n")
        chan.send_exit_status(124)
    finally:
        chan.shutdown_write()
        chan.close()


def ssh_loop(sock: socket.socket, host_key: paramiko.PKey, workdir: str) -> None:
    while True:
        client, _ = sock.accept()

        def handle(c=client):
            t = paramiko.Transport(c)
            t.add_server_key(host_key)
            srv = _Server()
            try:
                t.start_server(server=srv)
            except Exception:
                return
            while t.is_active():
                chan = t.accept(60)
                if chan is None:
                    break
                _run_exec(chan, srv, workdir)
            t.close()

        threading.Thread(target=handle, daemon=True).start()


def _reply(content: str = "", calls: list | None = None) -> dict:
    msg: dict = {"role": "assistant", "content": content}
    if calls:
        msg["tool_calls"] = [
            {"id": f"call_{i}_{abs(hash(json.dumps(c))) % 10**6}", "type": "function",
             "function": {"name": c["name"], "arguments": json.dumps(c["args"])}}
            for i, c in enumerate(calls)
        ]
    return {"id": "mock", "object": "chat.completion", "choices": [{"index": 0, "message": msg, "finish_reason": "tool_calls" if calls else "stop"}]}


def script(messages: list) -> dict:
    """User → list_servers → run_command(uname, then a write) → summary."""
    last = messages[-1]
    if last.get("role") == "user":
        return _reply("先看看有哪些服务器。", [{"name": "list_servers", "args": {}}])
    if last.get("role") == "tool":
        # Find which tool this result answers.
        names = {}
        for m in messages:
            for c in m.get("tool_calls") or []:
                names[c["id"]] = c["function"]["name"]
        name = names.get(last.get("tool_call_id"), "")
        content = last.get("content", "")
        if name == "list_servers":
            try:
                servers = json.loads(content)
                first = servers[0]["name"]
            except Exception:
                return _reply("没有可用的服务器。")
            return _reply("", [{"name": "run_command", "args": {"server": first, "command": "echo agent-ok && uname -s"}}])
        if name == "run_command":
            if "用户拒绝" in content:
                return _reply("好的，没有执行命令。")
            out = [ln for ln in content.splitlines() if ln and not ln.startswith(("exit_code", "stdout", "stderr"))]
            return _reply("完成：" + " / ".join(out[:2]))
    return _reply("完成。")


class LlmHandler(BaseHTTPRequestHandler):
    def log_message(self, *a) -> None:  # quiet
        pass

    def do_GET(self) -> None:
        if self.path.rstrip("/").endswith("/models"):
            self._send(200, {"object": "list", "data": [{"id": "mock"}, {"id": "mock-large"}]})
        else:
            self._send(404, {"error": {"message": "not found"}})

    def do_POST(self) -> None:
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        if self.headers.get("Authorization") != "Bearer mock-key":
            self._send(401, {"error": {"message": "bad key"}})
            return
        if not self.path.rstrip("/").endswith("/chat/completions"):
            self._send(404, {"error": {"message": "not found"}})
            return
        reply = script(body.get("messages") or [])
        if body.get("stream"):
            self._stream(reply)
        else:
            self._send(200, reply)

    def _stream(self, reply: dict) -> None:
        """OpenAI-style SSE: text in small pieces, tool call arguments split in two."""
        msg = reply["choices"][0]["message"]
        chunks = []
        text = msg.get("content") or ""
        for i in range(0, len(text), 3):
            chunks.append({"choices": [{"index": 0, "delta": {"content": text[i:i + 3]}}]})
        for n, c in enumerate(msg.get("tool_calls") or []):
            args = c["function"]["arguments"]
            half = len(args) // 2
            chunks.append({"choices": [{"index": 0, "delta": {"tool_calls": [{"index": n, "id": c["id"], "type": "function", "function": {"name": c["function"]["name"], "arguments": args[:half]}}]}}]})
            chunks.append({"choices": [{"index": 0, "delta": {"tool_calls": [{"index": n, "function": {"arguments": args[half:]}}]}}]})
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        for ch in chunks:
            self.wfile.write(b"data: " + json.dumps(ch).encode() + b"\n\n")
            self.wfile.flush()
            time.sleep(0.05)
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def _send(self, code: int, obj: dict) -> None:
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--ssh-port", type=int, default=0)
    ap.add_argument("--llm-port", type=int, default=0)
    args = ap.parse_args()
    key = paramiko.RSAKey.generate(2048)
    fp = "SHA256:" + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip("=")
    workdir = tempfile.mkdtemp(prefix="hh-mock-ssh-")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.bind, args.ssh_port))
    sock.listen(16)
    llm = ThreadingHTTPServer((args.bind, args.llm_port), LlmHandler)
    threading.Thread(target=llm.serve_forever, daemon=True).start()
    print(json.dumps({"ssh_port": sock.getsockname()[1], "llm_port": llm.server_address[1], "host_key": fp,
                      "user": USER, "password": PASSWORD, "workdir": workdir}), flush=True)
    ssh_loop(sock, key, workdir)


if __name__ == "__main__":
    main()
