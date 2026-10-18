from __future__ import annotations

import json
import sys
import time
import unittest

from bridge_agent_loop import AgentBridgeLoop
from agent_session_runtime import AgentSessionRuntime
from production_adapter import AgentSpec, ProductionAgentAdapter


class TestAgentBridgeLoop(unittest.TestCase):
    def setUp(self) -> None:
        self.adapters: list[ProductionAgentAdapter] = []

    def tearDown(self) -> None:
        for adapter in self.adapters:
            adapter.close_all()

    def loop_for(self, script: str) -> AgentBridgeLoop:
        adapter = ProductionAgentAdapter(
            AgentSpec(agent_type="bridge-fixture", command=(sys.executable, "-u", "-c", script))
        )
        self.adapters.append(adapter)
        runtime = AgentSessionRuntime(adapter)
        return AgentBridgeLoop(runtime, workdir_resolver=lambda message: "/tmp")

    def poll_until_done(self, loop: AgentBridgeLoop, session_key: str) -> list[dict]:
        events: list[dict] = []
        deadline = time.monotonic() + 2
        while session_key in loop.runtime.active_sessions and time.monotonic() < deadline:
            events.extend(loop.poll(session_key))
            if any(event.get("type") == "run_done" for event in events):
                break
            time.sleep(0.01)
        return events

    def test_message_routes_content_and_context(self) -> None:
        script = (
            "import json, sys; "
            "line=sys.stdin.readline().rstrip(); "
            "print(json.dumps({'type':'text_delta','text':line}), flush=True); "
            "print(json.dumps({'type':'done'}), flush=True)"
        )
        loop = self.loop_for(script)
        events = loop.handle({
            "type": "message",
            "session_key": "s1",
            "reply_ctx": "r1",
            "content": "hello",
        })
        events.extend(self.poll_until_done(loop, "s1"))
        self.assertTrue(any(event.get("delta") == "hello" for event in events))
        self.assertEqual([event["type"] for event in events].count("run_done"), 1)
        self.assertEqual(events[0]["reply_ctx"], "r1")

    def test_attachments_are_saved_and_paths_appended(self) -> None:
        import base64, tempfile
        script = (
            "import json, sys; "
            "line=sys.stdin.readline().rstrip(); "
            "print(json.dumps({'type':'text_delta','text':line}), flush=True); "
            "print(json.dumps({'type':'done'}), flush=True)"
        )
        with tempfile.TemporaryDirectory() as root:
            adapter = ProductionAgentAdapter(AgentSpec(agent_type="bridge-fixture", command=(sys.executable, "-u", "-c", script)))
            self.adapters.append(adapter)
            loop = AgentBridgeLoop(AgentSessionRuntime(adapter), workdir_resolver=lambda message: root)
            events = loop.handle({"type": "message", "session_key": "s9", "content": "",
                                  "images": [{"name": "a.png", "data_base64": base64.b64encode(b"x").decode()}]})
            events.extend(self.poll_until_done(loop, "s9"))
            self.assertTrue(any("a.png" in str(e.get("delta", "")) for e in events))
            bad = loop.handle({"type": "message", "session_key": "s9", "content": "x", "files": [{"data_base64": "%%%"}]})
            self.assertEqual(bad[0].get("error_code") or bad[0].get("code"), "attachment_rejected")

    def test_second_message_starts_new_run_context(self) -> None:
        script = (
            "import json, sys; "
            "[print(json.dumps({'type':'text_delta','text':line.rstrip()}), flush=True) or "
            "print(json.dumps({'type':'done'}), flush=True) for line in sys.stdin]"
        )
        loop = self.loop_for(script)
        first = loop.handle({"type": "message", "session_key": "s1", "reply_ctx": "r1", "content": "one"})
        first.extend(self.poll_until_done(loop, "s1"))
        second = loop.handle({"type": "message", "session_key": "s1", "reply_ctx": "r2", "content": "two"})
        second.extend(self.poll_until_done(loop, "s1"))
        self.assertTrue(any(event.get("reply_ctx") == "r1" for event in first))
        self.assertTrue(any(event.get("reply_ctx") == "r2" for event in second))

    def test_cancel_and_ping_are_routed(self) -> None:
        loop = self.loop_for("import time; time.sleep(60)")
        loop.handle({"type": "message", "session_key": "s1", "content": "hello"})
        cancelled = loop.handle({"type": "cancel", "session_key": "s1"})
        self.assertEqual(cancelled[0]["status"], "cancelled")
        self.assertEqual(loop.handle({"type": "ping", "id": "p1"}), [{"type": "pong", "id": "p1"}])

    def test_invalid_or_unknown_messages_fail_closed(self) -> None:
        loop = self.loop_for("pass")
        self.assertTrue(loop.handle({"type": "unknown"})[0]["error"])
        self.assertEqual(
            loop.handle({"type": "message", "session_key": "s1", "content": ""})[0]["error_code"],
            "invalid_message",
        )

    def test_poll_unknown_session_returns_protocol_error(self) -> None:
        loop = self.loop_for("pass")
        event = loop.poll("missing")[0]
        self.assertEqual(event["error_code"], "unknown_session")
        self.assertEqual(event["session_key"], "missing")


if __name__ == "__main__":
    unittest.main()
