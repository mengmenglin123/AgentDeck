"""Mock Host speaks Bridge protocol v2 only to clients that ask for it."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
import unittest
from pathlib import Path

import test_bridge_websocket as _wsmod
from test_bridge_websocket import client_frame, read_server_frame
from test_protocol_schema import SCHEMA, validate

MOCK = Path(__file__).resolve().parent / "mock-host" / "mock_host.py"
LEGACY_CAPS = ["text", "buttons", "typing", "preview", "terminal"]
V2_CAPS = [*LEGACY_CAPS, "seq", "resume", "session_status"]


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class TestMockHostProtocolV2(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.port = _free_port()
        env = {
            **os.environ,
            "HUAN_BRIDGE_HOST": "127.0.0.1",
            "HUAN_BRIDGE_PORT": str(cls.port),
            "HUAN_MGMT_PORT": str(_free_port()),
            "HUAN_BRIDGE_TOKEN": "t-bridge",
            "HUAN_MGMT_TOKEN": "t-mgmt",
        }
        cls.proc = subprocess.Popen(
            [sys.executable, str(MOCK)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                socket.create_connection(("127.0.0.1", cls.port), timeout=0.2).close()
                return
            except OSError:
                time.sleep(0.1)
        cls.proc.kill()
        raise RuntimeError("mock host did not start")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.proc.terminate()
        cls.proc.wait(timeout=5)

    def connect(self, caps: list[str]) -> tuple[socket.socket, dict]:
        client = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        response = _wsmod.TestBridgeWebSocketTransport.handshake(client, token="t-bridge")
        self.assertIn(b"101", response)
        client.sendall(client_frame(0x1, json.dumps({"type": "register", "capabilities": caps}).encode()))
        return client, json.loads(read_server_frame(client)[1])

    @staticmethod
    def read_until(client: socket.socket, predicate, timeout: float = 10) -> list[dict]:
        events: list[dict] = []
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            opcode, payload = read_server_frame(client)
            if opcode == 1:
                events.append(json.loads(payload))
                if predicate(events[-1]):
                    return events
        raise AssertionError(events)

    def test_legacy_register_and_events_are_unchanged(self) -> None:
        client, ack = self.connect(LEGACY_CAPS)
        self.assertEqual(ack, {"type": "register_ack", "ok": True, "error": ""})
        client.sendall(client_frame(0x1, json.dumps({
            "type": "message", "session_key": "huan:legacy:1", "reply_ctx": "c1", "content": "hello",
        }).encode()))
        events = self.read_until(client, lambda e: e.get("type") == "run_done")
        self.assertFalse(any("seq" in e for e in events))
        client.close()

    def test_v2_seq_resume_and_session_status(self) -> None:
        client, ack = self.connect(V2_CAPS)
        self.assertEqual(ack["protocol"], 2)
        sk = "huan:v2:1"
        client.sendall(client_frame(0x1, json.dumps({
            "type": "message", "session_key": sk, "reply_ctx": "c1", "content": "hello",
        }).encode()))
        events = self.read_until(client, lambda e: e.get("type") == "run_done")
        for event in events:  # mock-host must stay consistent with the schema
            if event["type"] in SCHEMA["$defs"]["host_to_app"]:
                validate("host_to_app", event)
        seqs = [e["seq"] for e in events if e.get("session_key") == sk]
        self.assertEqual(seqs, list(range(seqs[0], seqs[0] + len(seqs))))
        client.close()

        again, ack2 = self.connect(V2_CAPS)
        self.assertEqual(ack2["epoch"], ack["epoch"])
        again.sendall(client_frame(0x1, json.dumps({
            "type": "resume", "session_key": sk, "after_seq": seqs[0], "epoch": ack["epoch"],
        }).encode()))
        replay = self.read_until(again, lambda e: e.get("type") == "resume_ack")
        for event in replay:
            validate("host_to_app", event)
        self.assertEqual([e["seq"] for e in replay[:-1]], seqs[1:])
        self.assertEqual(replay[-1]["last_seq"], seqs[-1])
        again.sendall(client_frame(0x1, json.dumps({"type": "session_status", "session_key": sk}).encode()))
        status = self.read_until(again, lambda e: e.get("type") == "session_status")[-1]
        self.assertEqual(status["last_seq"], seqs[-1])
        again.sendall(client_frame(0x1, json.dumps({
            "type": "resume", "session_key": sk, "after_seq": 0, "epoch": "previous-run",
        }).encode()))
        self.assertEqual(self.read_until(again, lambda e: e.get("type") == "resync_required")[-1]["session_key"], sk)
        again.close()


if __name__ == "__main__":
    unittest.main()
