from __future__ import annotations

import unittest
import tempfile
from pathlib import Path

from project_router import ProjectAgentRouter, ProjectTerminalRouter
from session_store import ProjectSessionStore


class _AgentLoop:
    def __init__(self, project: str) -> None:
        self.project = project
        self.sessions: set[str] = set()

    @property
    def active_sessions(self) -> tuple[str, ...]:
        return tuple(self.sessions)

    def handle(self, message) -> list[dict]:
        session = str(message.get("session_key") or "")
        if message.get("type") == "message":
            self.sessions.add(session)
        elif message.get("type") == "cancel":
            self.sessions.discard(session)
        return [{"type": "reply", "session_key": session, "project": self.project}]

    def poll(self, session_key: str) -> list[dict]:
        return [{"type": "reply_stream", "session_key": session_key, "project": self.project}]

    def close_session(self, session_key: str) -> None:
        self.sessions.discard(session_key)

    def close(self) -> None:
        self.sessions.clear()


class _TerminalLoop:
    def __init__(self, project: str) -> None:
        self.project = project
        self.sessions: set[str] = set()

    @property
    def active_sessions(self) -> tuple[str, ...]:
        return tuple(self.sessions)

    def handle(self, message) -> list[dict]:
        session = str(message.get("session_key") or "")
        if message.get("type") == "terminal_open":
            self.sessions.add(session)
        elif message.get("type") == "terminal_close":
            self.sessions.discard(session)
        return [{"type": "terminal_ack", "session_key": session, "project": self.project, "ok": True}]

    def poll(self, session_key: str) -> list[dict]:
        return [{"type": "terminal_out", "session_key": session_key, "project": self.project}]

    def close_session(self, session_key: str) -> None:
        self.sessions.discard(session_key)

    def close(self) -> None:
        self.sessions.clear()


class TestProjectAgentRouter(unittest.TestCase):
    def test_routes_new_sessions_and_followups_to_selected_project(self) -> None:
        claude = _AgentLoop("claude-code")
        codex = _AgentLoop("codex")
        router = ProjectAgentRouter({"claude-code": claude, "codex": codex})
        opened = router.handle({"type": "message", "session_key": "s1", "project": "codex"})
        followup = router.handle({"type": "cancel", "session_key": "s1"})
        self.assertEqual(opened[0]["project"], "codex")
        self.assertEqual(followup[0]["project"], "codex")
        self.assertNotIn("s1", router.active_sessions)

    def test_rejects_unknown_project_and_session_project_switch(self) -> None:
        router = ProjectAgentRouter({
            "claude-code": _AgentLoop("claude-code"),
            "codex": _AgentLoop("codex"),
        })
        unknown = router.handle({"type": "message", "session_key": "s1", "project": "missing"})
        self.assertEqual(unknown[0]["error_code"], "project_route_rejected")
        router.handle({"type": "message", "session_key": "s2", "project": "codex"})
        switched = router.handle({"type": "message", "session_key": "s2", "project": "claude-code"})
        self.assertEqual(switched[0]["error_code"], "project_route_rejected")

    def test_persistent_registry_rejects_switch_after_runtime_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            registry = ProjectSessionStore(
                str(Path(directory) / "sessions.json"),
                projects=("claude-code", "codex"),
            )
            codex = _AgentLoop("codex")
            router = ProjectAgentRouter(
                {"claude-code": _AgentLoop("claude-code"), "codex": codex},
                session_registry=registry,
            )
            router.handle({"type": "message", "session_key": "s1", "project": "codex"})
            router.handle({"type": "cancel", "session_key": "s1"})
            self.assertNotIn("s1", router.active_sessions)
            switched = router.handle({
                "type": "message", "session_key": "s1", "project": "claude-code",
            })
            self.assertEqual(switched[0]["error_code"], "project_route_rejected")
            self.assertEqual(registry.project_for("s1"), "codex")


class TestProjectTerminalRouter(unittest.TestCase):
    def test_routes_terminal_stream_and_rejects_cross_project_reuse(self) -> None:
        router = ProjectTerminalRouter({
            "claude-code": _TerminalLoop("claude-code"),
            "codex": _TerminalLoop("codex"),
        })
        opened = router.handle({
            "type": "terminal_open",
            "session_key": "term-1",
            "stream_id": "stream-1",
            "project": "codex",
        })
        self.assertEqual(opened[0]["project"], "codex")
        self.assertEqual(router.poll("term-1")[0]["project"], "codex")
        rejected = router.handle({
            "type": "terminal_input",
            "session_key": "term-1",
            "stream_id": "stream-1",
            "project": "claude-code",
        })
        self.assertEqual(rejected[0]["error"], "project_route_rejected")

    def test_requires_project_when_default_agent_has_no_terminal(self) -> None:
        router = ProjectTerminalRouter({"codex": _TerminalLoop("codex")})
        rejected = router.handle({
            "type": "terminal_open",
            "session_key": "term-2",
            "stream_id": "stream-2",
        })
        self.assertFalse(rejected[0]["ok"])
        self.assertEqual(rejected[0]["error"], "project_route_rejected")


if __name__ == "__main__":
    unittest.main()
