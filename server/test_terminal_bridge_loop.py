from __future__ import annotations

import sys
import time
import unittest

from pty_terminal_adapter import PtySpec, PtyTerminalAdapter
from permission_gate import PermissionGate
from terminal_bridge_loop import TerminalBridgeLoop


class TestTerminalBridgeLoop(unittest.TestCase):
    def setUp(self) -> None:
        self.loops: list[TerminalBridgeLoop] = []

    def tearDown(self) -> None:
        for loop in self.loops:
            loop.close()

    def loop_for(self, script: str) -> TerminalBridgeLoop:
        adapter = PtyTerminalAdapter(
            PtySpec(command=(sys.executable, "-u", "-c", script))
        )
        loop = TerminalBridgeLoop(adapter, workdir_resolver=lambda message: "/tmp")
        self.loops.append(loop)
        return loop

    def permission_loop_for(self, script: str) -> TerminalBridgeLoop:
        adapter = PtyTerminalAdapter(
            PtySpec(command=(sys.executable, "-u", "-c", script))
        )
        loop = TerminalBridgeLoop(
            adapter,
            workdir_resolver=lambda message: "/tmp",
            permission_gate=PermissionGate(id_factory=iter(("perm-terminal-1", "perm-terminal-2")).__next__),
            require_open_permission=True,
        )
        self.loops.append(loop)
        return loop

    @staticmethod
    def poll_until(loop: TerminalBridgeLoop, session_key: str, event_type: str) -> list[dict]:
        events: list[dict] = []
        deadline = time.monotonic() + 2
        while not any(event.get("type") == event_type for event in events) and time.monotonic() < deadline:
            events.extend(loop.poll(session_key))
            time.sleep(0.01)
        return events

    def test_open_input_output_and_exit_keep_stream_identity(self) -> None:
        loop = self.loop_for(
            "import sys; print('ready', flush=True); line=sys.stdin.readline(); print('got:'+line.strip(), flush=True)"
        )
        ack = loop.handle({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1", "cols": 80, "rows": 24,
        })[0]
        self.assertTrue(ack["ok"])
        ready = self.poll_until(loop, "s1", "terminal_out")
        self.assertTrue(any("ready" in event.get("data", "") for event in ready))
        events = loop.handle({
            "type": "terminal_input", "session_key": "s1", "stream_id": "t1", "data": "hello\n",
        })
        deadline = time.monotonic() + 2
        while not any(event.get("type") == "terminal_exit" for event in events) and time.monotonic() < deadline:
            events.extend(loop.poll("s1"))
            time.sleep(0.01)
        self.assertTrue(any("got:hello" in event.get("data", "") for event in events))
        self.assertEqual({event.get("stream_id") for event in events}, {"t1"})
        self.assertEqual(events[-1]["type"], "terminal_exit")
        self.assertEqual(events[-1]["exit_code"], 0)

    def test_resize_ack_and_stale_stream_rejection(self) -> None:
        loop = self.loop_for("import time; time.sleep(60)")
        loop.handle({"type": "terminal_open", "session_key": "s1", "stream_id": "t1"})
        stale = loop.handle({
            "type": "terminal_resize", "session_key": "s1", "stream_id": "old", "cols": 100, "rows": 40,
        })[0]
        self.assertFalse(stale["ok"])
        self.assertEqual(stale["error"], "stale_terminal_stream")
        ack = loop.handle({
            "type": "terminal_resize", "session_key": "s1", "stream_id": "t1", "cols": 100, "rows": 40,
        })[0]
        self.assertEqual((ack["cols"], ack["rows"]), (100, 40))

    def test_reopening_same_stream_applies_new_geometry(self) -> None:
        loop = self.loop_for("import time; time.sleep(60)")
        loop.handle({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1", "cols": 80, "rows": 24,
        })
        ack = loop.handle({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1", "cols": 120, "rows": 50,
        })[0]
        record = loop.adapter._processes["s1"]
        self.assertEqual((ack["cols"], ack["rows"]), (120, 50))
        self.assertEqual((record.cols, record.rows), (120, 50))

    def test_new_stream_replaces_old_process(self) -> None:
        loop = self.loop_for("import time; time.sleep(60)")
        loop.handle({"type": "terminal_open", "session_key": "s1", "stream_id": "t1"})
        first_pid = loop.adapter._processes["s1"].pid
        ack = loop.handle({"type": "terminal_open", "session_key": "s1", "stream_id": "t2"})[0]
        self.assertTrue(ack["ok"])
        self.assertNotEqual(loop.adapter._processes["s1"].pid, first_pid)
        stale = loop.handle({
            "type": "terminal_input", "session_key": "s1", "stream_id": "t1", "data": "x",
        })[0]
        self.assertEqual(stale["error"], "stale_terminal_stream")

    def test_close_returns_exit_and_removes_session(self) -> None:
        loop = self.loop_for("import time; time.sleep(60)")
        loop.handle({"type": "terminal_open", "session_key": "s1", "stream_id": "t1"})
        event = loop.handle({"type": "terminal_close", "session_key": "s1", "stream_id": "t1"})[0]
        self.assertEqual(event["type"], "terminal_exit")
        self.assertEqual(loop.active_sessions, ())

    def test_invalid_messages_fail_closed(self) -> None:
        loop = self.loop_for("pass")
        event = loop.handle({"type": "terminal_open", "session_key": "", "stream_id": "t1"})[0]
        self.assertFalse(event["ok"])
        self.assertEqual(event["error"], "invalid_terminal_message")

    def test_open_requires_audited_permission_before_starting_pty(self) -> None:
        loop = self.permission_loop_for("import time; time.sleep(60)")
        challenge = loop.handle({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1",
        })[0]
        self.assertEqual(challenge["type"], "terminal_permission")
        self.assertEqual(loop.adapter._processes, {})
        repeated = loop.handle({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1",
        })[0]
        self.assertEqual(repeated["permission_id"], challenge["permission_id"])
        allowed = loop.handle({
            "type": "terminal_permission_action",
            "session_key": "s1", "stream_id": "t1",
            "action": challenge["buttons"][0][0]["data"],
        })[0]
        self.assertTrue(allowed["ok"])
        self.assertIn("s1", loop.adapter._processes)

    def test_denied_terminal_permission_does_not_start_pty(self) -> None:
        loop = self.permission_loop_for("pass")
        challenge = loop.handle({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1",
        })[0]
        denied = loop.handle({
            "type": "terminal_permission_action",
            "session_key": "s1", "stream_id": "t1",
            "action": challenge["buttons"][0][2]["data"],
        })[0]
        self.assertFalse(denied["ok"])
        self.assertEqual(denied["error"], "terminal_permission_denied")
        self.assertEqual(loop.active_sessions, ())

    def test_terminal_permission_action_is_bound_to_stream(self) -> None:
        loop = self.permission_loop_for("pass")
        challenge = loop.handle({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1",
        })[0]
        rejected = loop.handle({
            "type": "terminal_permission_action",
            "session_key": "s1", "stream_id": "wrong",
            "action": challenge["buttons"][0][0]["data"],
        })[0]
        self.assertEqual(rejected["error"], "terminal_permission_missing")
        self.assertEqual(loop.adapter._processes, {})


if __name__ == "__main__":
    unittest.main()
