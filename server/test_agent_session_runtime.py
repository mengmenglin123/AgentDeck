from __future__ import annotations

import json
import sys
import time
import unittest

from agent_session_runtime import AgentSessionRuntime
from permission_gate import PermissionGate
from production_adapter import AdapterError, AgentSpec, ProductionAgentAdapter


class TestAgentSessionRuntime(unittest.TestCase):
    def setUp(self) -> None:
        self.runtimes: list[AgentSessionRuntime] = []

    def tearDown(self) -> None:
        for runtime in self.runtimes:
            runtime.close_all()

    def runtime_for(self, script: str) -> AgentSessionRuntime:
        adapter = ProductionAgentAdapter(
            AgentSpec(agent_type="fixture", command=(sys.executable, "-u", "-c", script))
        )
        runtime = AgentSessionRuntime(adapter)
        self.runtimes.append(runtime)
        return runtime

    def permission_runtime_for(self, script: str) -> AgentSessionRuntime:
        adapter = ProductionAgentAdapter(
            AgentSpec(agent_type="fixture", command=(sys.executable, "-u", "-c", script))
        )
        gate = PermissionGate(id_factory=iter(("perm-1", "perm-2")).__next__)
        runtime = AgentSessionRuntime(adapter, permission_gate=gate)
        self.runtimes.append(runtime)
        return runtime

    def collect_until_done(
        self,
        runtime: AgentSessionRuntime,
        session_key: str,
        *,
        timeout: float = 2.0,
    ) -> list[dict]:
        events: list[dict] = []
        deadline = time.monotonic() + timeout
        while session_key in runtime.active_sessions and time.monotonic() < deadline:
            events.extend(runtime.poll(session_key, max_bytes=32))
            time.sleep(0.01)
        self.assertNotIn(session_key, runtime.active_sessions)
        return events

    def test_drains_stdout_after_process_exit_and_adds_done(self) -> None:
        payload = json.dumps({"type": "text_delta", "text": "hello"})
        runtime = self.runtime_for(f"print({payload!r}, flush=True)")
        runtime.start("s1", workdir="/tmp", reply_ctx="r1")
        events = self.collect_until_done(runtime, "s1")
        self.assertEqual([event["type"] for event in events], ["reply_stream", "run_done"])
        self.assertEqual(events[0]["delta"], "hello")
        self.assertEqual(events[-1]["status"], "completed")
        self.assertEqual(events[-1]["exit_code"], 0)
        self.assertEqual(events[-1]["reply_ctx"], "r1")

    def test_preserves_agent_done_without_duplicate(self) -> None:
        payload = json.dumps({"type": "done", "status": "completed"})
        runtime = self.runtime_for(f"print({payload!r}, flush=True)")
        runtime.start("s1", workdir="/tmp")
        events = self.collect_until_done(runtime, "s1")
        self.assertEqual([event["type"] for event in events].count("run_done"), 1)

    def test_nonzero_exit_maps_to_failed_done(self) -> None:
        runtime = self.runtime_for("raise SystemExit(7)")
        runtime.start("s1", workdir="/tmp")
        events = self.collect_until_done(runtime, "s1")
        self.assertEqual(events[-1]["type"], "run_done")
        self.assertEqual(events[-1]["status"], "failed")
        self.assertEqual(events[-1]["exit_code"], 7)

    def test_send_routes_stdin_to_driver_output(self) -> None:
        script = (
            "import json, sys; "
            "line = sys.stdin.readline().rstrip(); "
            "print(json.dumps({'type':'text_delta','text':line}), flush=True)"
        )
        runtime = self.runtime_for(script)
        runtime.start("s1", workdir="/tmp")
        runtime.send("s1", "prompt\n")
        events = self.collect_until_done(runtime, "s1")
        self.assertEqual(events[0]["delta"], "prompt")

    def test_cancel_emits_cancelled_done_once(self) -> None:
        runtime = self.runtime_for("import time; time.sleep(60)")
        runtime.start("s1", workdir="/tmp", reply_ctx="r1")
        events = runtime.cancel("s1", timeout=0.2)
        self.assertEqual(events, [{
            "type": "run_done",
            "session_key": "s1",
            "reply_ctx": "r1",
            "status": "cancelled",
        }])
        self.assertEqual(runtime.cancel("s1"), [])
        self.assertEqual(runtime.active_sessions, ())

    def test_persistent_process_accepts_multiple_run_contexts(self) -> None:
        script = (
            "import json, sys; "
            "[(print(json.dumps({'type':'text_delta','text':line.rstrip()}), flush=True), "
            "print(json.dumps({'type':'done','status':'completed'}), flush=True)) "
            "for line in sys.stdin]"
        )
        runtime = self.runtime_for(script)
        runtime.start("s1", workdir="/tmp", reply_ctx="r1")
        runtime.send("s1", "first\n")
        first: list[dict] = []
        deadline = time.monotonic() + 2
        while not any(event.get("type") == "run_done" for event in first) and time.monotonic() < deadline:
            first.extend(runtime.poll("s1"))
            time.sleep(0.01)
        self.assertEqual({event.get("reply_ctx") for event in first}, {"r1"})

        runtime.begin_run("s1", reply_ctx="r2", timeout_seconds=1)
        runtime.send("s1", "second\n")
        second: list[dict] = []
        deadline = time.monotonic() + 2
        while not any(event.get("type") == "run_done" for event in second) and time.monotonic() < deadline:
            second.extend(runtime.poll("s1"))
            time.sleep(0.01)
        self.assertEqual({event.get("reply_ctx") for event in second}, {"r2"})
        self.assertIn("s1", runtime.active_sessions)

    def test_begin_run_rejects_overlapping_run(self) -> None:
        runtime = self.runtime_for("import time; time.sleep(60)")
        runtime.start("s1", workdir="/tmp")
        with self.assertRaisesRegex(AdapterError, "already active"):
            runtime.begin_run("s1", reply_ctx="r2")

    def test_timeout_stops_process_and_emits_timeout_done(self) -> None:
        runtime = self.runtime_for("import time; time.sleep(60)")
        runtime.start("s1", workdir="/tmp", timeout_seconds=0.01)
        time.sleep(0.02)
        events = runtime.poll("s1")
        self.assertEqual(events, [{
            "type": "run_done",
            "session_key": "s1",
            "status": "timeout",
        }])
        self.assertEqual(runtime.active_sessions, ())

    def test_rejects_nonpositive_timeout(self) -> None:
        runtime = self.runtime_for("pass")
        with self.assertRaises(ValueError):
            runtime.start("s1", workdir="/tmp", timeout_seconds=0)

    def test_malformed_output_is_safe_and_run_fails_only_on_exit_code(self) -> None:
        runtime = self.runtime_for("print('not-json', flush=True)")
        runtime.start("s1", workdir="/tmp")
        events = self.collect_until_done(runtime, "s1")
        self.assertTrue(events[0]["error"])
        self.assertEqual(events[0]["error_code"], "malformed_json")
        self.assertEqual(events[-1]["status"], "completed")

    def test_permission_request_is_host_owned_and_redacted(self) -> None:
        payload = json.dumps({
            "type": "permission",
            "scope": "shell",
            "prompt": "Run Bearer secret token=abc",
            "buttons": [[{"text": "Agent supplied", "data": "unsafe"}]],
        })
        runtime = self.permission_runtime_for(
            f"import json; print({payload!r}, flush=True)"
        )
        runtime.start("s1", workdir="/tmp", reply_ctx="r1")
        events = self.collect_until_done(runtime, "s1")
        card = next(event for event in events if event["type"] == "card")
        self.assertEqual(card["permission_id"], "perm-1")
        self.assertNotIn("secret", card["content"])
        self.assertNotIn("abc", card["content"])
        self.assertEqual(card["buttons"][0][0]["data"], "perm:perm-1:allow")

    def test_permission_action_is_sent_to_agent_and_bound_to_context(self) -> None:
        script = (
            "import json, sys; "
            "print(json.dumps({'type':'permission','scope':'shell','content':'run'}), flush=True); "
            "line=sys.stdin.readline(); "
            "print(json.dumps({'type':'text_delta','text':line.strip()}), flush=True); "
            "print(json.dumps({'type':'done'}), flush=True)"
        )
        runtime = self.permission_runtime_for(script)
        runtime.start("s1", workdir="/tmp", reply_ctx="r1")
        pending: list[dict] = []
        deadline = time.monotonic() + 2
        while not any(event.get("type") == "card" for event in pending) and time.monotonic() < deadline:
            pending.extend(runtime.poll("s1"))
            time.sleep(0.01)
        card = next(event for event in pending if event["type"] == "card")
        with self.assertRaises(AdapterError):
            runtime.respond_permission("s1", action=card["buttons"][0][1]["data"], reply_ctx="wrong")
        events = runtime.respond_permission(
            "s1", action=card["buttons"][0][0]["data"], reply_ctx="r1"
        )
        deadline = time.monotonic() + 2
        while "s1" in runtime.active_sessions and time.monotonic() < deadline:
            events.extend(runtime.poll("s1"))
            time.sleep(0.01)
        reply = next(event for event in events if event.get("type") == "reply_stream")
        self.assertIn('"decision":"allow"', reply["delta"])


if __name__ == "__main__":
    unittest.main()
