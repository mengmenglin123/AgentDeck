"""Integration-ish tests against local Mock Host (or in-process skip)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
import unittest
from pathlib import Path

# test/ -> huan_protocol -> packages -> repo root
ROOT = Path(__file__).resolve().parents[3]
PROTO = ROOT / "packages" / "huan_protocol"
MOCK = ROOT / "server" / "mock-host" / "mock_host.py"

sys.path.insert(0, str(PROTO))

from src.bridge_client import BridgeClient  # noqa: E402
from src.mgmt_client import MgmtClient  # noqa: E402
from src.models import ConnectionConfig, EventKind, TranscriptEvent, TranscriptReducer  # noqa: E402


class TestTranscriptReducer(unittest.TestCase):
    def test_stream_then_done(self) -> None:
        r = TranscriptReducer()
        r.apply_bridge_payload(
            {"type": "reply_stream", "delta": "Hel", "full_text": "Hel", "done": False}
        )
        r.apply_bridge_payload(
            {"type": "reply_stream", "delta": "lo", "full_text": "Hello", "done": True}
        )
        self.assertEqual(len(r.messages), 1)
        self.assertEqual(r.messages[0].content, "Hello")
        self.assertFalse(r.messages[0].streaming)

    def test_permission_buttons(self) -> None:
        r = TranscriptReducer()
        r.apply_bridge_payload(
            {
                "type": "buttons",
                "content": "Allow bash?",
                "buttons": [[{"text": "allow", "data": "perm:1:allow"}]],
            }
        )
        self.assertEqual(r.messages[0].role, "permission")


class TestWithMockHost(unittest.TestCase):
    proc: subprocess.Popen | None = None

    @classmethod
    def setUpClass(cls) -> None:
        env = os.environ.copy()
        env["HUAN_BRIDGE_TOKEN"] = "dev-bridge-token-change-me"
        env["HUAN_MGMT_TOKEN"] = "dev-mgmt-token-change-me"
        env["HUAN_BRIDGE_PORT"] = "19810"
        env["HUAN_MGMT_PORT"] = "19820"
        cls.proc = subprocess.Popen(
            [sys.executable, str(MOCK)],
            cwd=str(MOCK.parent),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        # wait for listen
        deadline = time.time() + 8
        while time.time() < deadline:
            try:
                cfg = ConnectionConfig(
                    bridge_port=19810,
                    mgmt_port=19820,
                )
                MgmtClient(cfg).status()
                break
            except Exception:
                time.sleep(0.2)
        else:
            out = cls.proc.stdout.read().decode() if cls.proc.stdout else ""
            cls.tearDownClass()
            raise RuntimeError(f"mock host failed to start:\n{out}")

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.proc:
            if cls.proc.stdout:
                try:
                    cls.proc.stdout.close()
                except Exception:
                    pass
            cls.proc.terminate()
            try:
                cls.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                cls.proc.kill()
            cls.proc = None

    def test_mgmt_status(self) -> None:
        cfg = ConnectionConfig(bridge_port=19810, mgmt_port=19820)
        data = MgmtClient(cfg).status()
        self.assertIn("version", data)
        self.assertTrue(data.get("projects_count", 0) >= 1)

    def test_bridge_roundtrip(self) -> None:
        cfg = ConnectionConfig(bridge_port=19810, mgmt_port=19820)
        events: list[dict] = []
        done = threading.Event()

        def on_msg(p: dict) -> None:
            events.append(p)
            if p.get("type") == "reply_stream" and p.get("done"):
                done.set()
            if p.get("type") == "reply":
                done.set()

        client = BridgeClient(cfg, on_message=on_msg)
        client.connect()
        client.send_user_message("ping test", conversation_id="t1")
        self.assertTrue(done.wait(10), f"timeout events={events}")
        types = [e.get("type") for e in events]
        self.assertTrue("reply_stream" in types or "reply" in types)
        client.close()

    def test_permission_flow(self) -> None:
        cfg = ConnectionConfig(bridge_port=19810, mgmt_port=19820)
        got_buttons = threading.Event()
        got_after = threading.Event()
        session_key = ""
        reply_ctx = ""

        def on_msg(p: dict) -> None:
            nonlocal session_key, reply_ctx
            if p.get("type") == "buttons":
                session_key = p.get("session_key") or session_key
                reply_ctx = p.get("reply_ctx") or reply_ctx
                got_buttons.set()
            if p.get("type") in ("reply", "reply_stream") and "allowed" in (
                (p.get("content") or "") + (p.get("full_text") or "")
            ):
                got_after.set()

        client = BridgeClient(cfg, on_message=on_msg)
        client.connect()
        meta = client.send_user_message("/perm demo", conversation_id="t-perm")
        session_key = meta["session_key"]
        reply_ctx = meta["reply_ctx"]
        self.assertTrue(got_buttons.wait(8), "no permission buttons")
        client.send_card_action(session_key, "perm:demo:allow", reply_ctx)
        self.assertTrue(got_after.wait(8), "no follow-up after allow")
        client.close()


if __name__ == "__main__":
    unittest.main()
