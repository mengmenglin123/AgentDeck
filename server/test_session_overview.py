from __future__ import annotations

import json
import tempfile
import unittest
import urllib.request
from pathlib import Path

from permission_gate import PermissionGate
from production_host_config import ProjectRuntimeConfig
from production_management import ProductionManagementServer
from session_activity import SessionActivity
from session_journal import SessionJournal
from session_store import ProjectSessionStore

_DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def _project(name: str) -> ProjectRuntimeConfig:
    return ProjectRuntimeConfig(name=name, agent_type="claudecode", command=("/bin/true",), workdir="/tmp")


class TestPendingFor(unittest.TestCase):
    def test_pending_for_lists_only_that_session_and_clears_on_decide(self) -> None:
        ids = iter(("a", "b"))
        gate = PermissionGate(ttl_seconds=60, id_factory=lambda: next(ids))
        gate.issue(session_key="s1", reply_ctx="r1", scope="shell", prompt="rm token=xyz")
        gate.issue(session_key="s2", reply_ctx="r2", scope="shell", prompt="ls")
        pending = gate.pending_for("s1")
        self.assertEqual([p["id"] for p in pending], ["a"])
        self.assertEqual(pending[0]["reply_ctx"], "r1")
        self.assertNotIn("xyz", pending[0]["prompt"])
        self.assertEqual(pending[0]["buttons"][0][0]["data"], "perm:a:allow")
        gate.decide(session_key="s1", reply_ctx="r1", action="perm:a:deny")
        self.assertEqual(gate.pending_for("s1"), [])


class TestSessionActivity(unittest.TestCase):
    def test_journal_observer_builds_preview_and_running(self) -> None:
        activity = SessionActivity(clock=lambda: 50.0)
        journal = SessionJournal(observer=activity.observe)
        journal.record({"type": "reply_stream", "session_key": "s", "delta": "Hello "})
        journal.record({"type": "reply_stream", "session_key": "s", "delta": "world"})
        self.assertEqual(activity.get("s"), {"preview": "Hello world", "running": True, "updated_at": 50.0})
        journal.record({"type": "run_done", "session_key": "s", "status": "completed"})
        self.assertFalse(activity.get("s")["running"])
        self.assertEqual(activity.get("s")["preview"], "Hello world")

    def test_observer_failure_never_breaks_journal(self) -> None:
        def boom(_e):
            raise RuntimeError("x")
        journal = SessionJournal(observer=boom)
        self.assertEqual(journal.record({"type": "reply", "session_key": "s", "content": "x"})["seq"], 1)

    def test_preview_is_clipped_and_flattened(self) -> None:
        activity = SessionActivity()
        activity.observe({"type": "reply", "session_key": "s", "content": "a\n\n" + "b" * 400})
        preview = activity.get("s")["preview"]
        self.assertTrue(preview.startswith("a b"))
        self.assertLessEqual(len(preview), 160)


class TestSessionsOverview(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.sessions = ProjectSessionStore(str(Path(self.directory.name) / "s.json"), projects=("p",))
        self.gate = PermissionGate(ttl_seconds=60, id_factory=iter(("x1", "x2")).__next__)
        self.activity = SessionActivity(clock=lambda: 9_999_999_999.0)
        self.active: tuple[str, ...] = ()
        self.server = ProductionManagementServer(
            (_project("p"),), default_project="p", token="t", sessions=self.sessions,
            active_sessions=lambda: self.active,
            pending_permissions=self.gate.pending_for, session_activity=self.activity.get, port=0,
        )
        self.server.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.directory.cleanup()

    def get(self, path: str) -> dict:
        host, port = self.server.address
        req = urllib.request.Request(f"http://{host}:{port}/api/v1{path}", headers={"Authorization": "Bearer t"})
        with _DIRECT.open(req, timeout=2) as response:
            return json.loads(response.read().decode())

    def test_status_declares_capability(self) -> None:
        self.assertIn("session_overview", self.get("/status")["data"]["capabilities"])

    def test_sessions_report_status_preview_and_pending(self) -> None:
        a = self.sessions.create(project="p", session_key="a")
        self.sessions.create(project="p", session_key="b")
        self.sessions.create(project="p", session_key="c")
        self.gate.issue(session_key="a", reply_ctx="r", scope="shell", prompt="run ls")
        self.activity.observe({"type": "reply_stream", "session_key": "b", "delta": "working"})
        self.active = ("b",)
        rows = {r["session_key"]: r for r in self.get("/sessions")["data"]["sessions"]}
        self.assertEqual(rows["a"]["status"], "needs_you")
        self.assertEqual(rows["a"]["pending_permissions"][0]["id"], "x1")
        self.assertEqual(rows["b"]["status"], "running")
        self.assertEqual(rows["b"]["last_message_preview"], "working")
        self.assertEqual(rows["b"]["updated_at"], 9_999_999_999.0)
        self.assertEqual(rows["c"]["status"], "idle")
        self.assertNotIn("last_message_preview", rows["c"])
        self.assertGreaterEqual(rows["a"]["updated_at"], a["updated_at"])

    def test_without_overview_sources_records_are_unchanged(self) -> None:
        plain = ProductionManagementServer((_project("p"),), default_project="p", token="t", sessions=self.sessions, port=0)
        self.assertEqual(plain._capabilities(), ["projects", "sessions", "skills", "mcp", "agents", "pairing", "file_search", "workspace_readonly", "diff_readonly", "external_sessions"])
        recs = [{"session_key": "z"}]
        self.assertIs(plain._overview(recs), recs)


if __name__ == "__main__":
    unittest.main()
