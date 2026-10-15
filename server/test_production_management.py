from __future__ import annotations

import json
import tempfile
import urllib.error
import urllib.request
import unittest
from pathlib import Path

from production_host_config import ProjectRuntimeConfig
from production_management import ProductionManagementServer
from session_store import ProjectSessionStore

# Loopback test servers must never be routed through an ambient HTTP(S)_PROXY.
_DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class TestProductionManagementServer(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.sessions = ProjectSessionStore(
            str(Path(self.directory.name) / "sessions.json"),
            projects=("claude-code", "codex"),
        )
        self.server = ProductionManagementServer(
            (
                ProjectRuntimeConfig(
                    name="claude-code",
                    agent_type="claudecode",
                    command=("/bin/true",),
                    workdir="/tmp",
                    capabilities=("stream", "skills_catalog"),
                    models=("claude-sonnet-4",),
                    channels=("anthropic",),
                    skills=("claude-review",),
                    mcp_servers=("claude-tools",),
                ),
                ProjectRuntimeConfig(
                    name="codex",
                    agent_type="codex",
                    command=("/bin/true",),
                    workdir="/tmp",
                    terminal_command=("/bin/bash",),
                    capabilities=("stream", "skills_catalog"),
                    models=("gpt-5-codex", "o4-mini"),
                    channels=("openai",),
                    skills=("codex-cli", "patch-review"),
                    mcp_servers=("openai-tools",),
                ),
            ),
            default_project="claude-code",
            token="mgmt-token",
            sessions=self.sessions,
            port=0,
        )
        self.server.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.directory.cleanup()

    def request(
        self,
        path: str,
        *,
        token: str = "mgmt-token",
        method: str = "GET",
        body: dict | None = None,
    ) -> dict:
        address = self.server.address
        self.assertIsNotNone(address)
        host, port = address or ("127.0.0.1", 0)
        request = urllib.request.Request(
            f"http://{host}:{port}/api/v1{path}",
            data=json.dumps(body).encode("utf-8") if body is not None else None,
            method=method,
            headers={"Authorization": f"Bearer {token}"},
        )
        with _DIRECT.open(request, timeout=2) as response:
            return json.loads(response.read().decode("utf-8"))

    def test_project_switch_changes_models_channels_skills_and_mcp(self) -> None:
        claude = self.request("/projects/claude-code")["data"]
        codex = self.request("/projects/codex")["data"]
        self.assertEqual(claude["models"], ["claude-sonnet-4"])
        self.assertEqual(claude["channels"], ["anthropic"])
        self.assertEqual(codex["models"], ["gpt-5-codex", "o4-mini"])
        self.assertEqual(codex["channels"], ["openai"])
        self.assertTrue(codex["terminal"])

        claude_skills = self.request("/skills?project=claude-code")["data"]["skills"]
        codex_skills = self.request("/skills?project=codex")["data"]["skills"]
        self.assertEqual([item["name"] for item in claude_skills], ["claude-review"])
        self.assertEqual([item["name"] for item in codex_skills], ["codex-cli", "patch-review"])
        codex_mcp = self.request("/mcp?project=codex")["data"]["servers"]
        self.assertEqual([item["name"] for item in codex_mcp], ["openai-tools"])

    def test_session_crud_supports_project_and_flat_paths(self) -> None:
        created = self.request(
            "/projects/codex/sessions",
            method="POST",
            body={"session_key": "session-codex-1", "title": "Codex task"},
        )["data"]
        self.assertEqual(created["project"], "codex")
        listed = self.request("/sessions?project=codex")["data"]["sessions"]
        self.assertEqual([item["session_key"] for item in listed], ["session-codex-1"])
        detail = self.request("/projects/codex/sessions/session-codex-1")["data"]
        self.assertEqual(detail["title"], "Codex task")
        renamed = self.request(
            "/sessions/session-codex-1",
            method="PATCH",
            body={"project": "codex", "title": "Renamed task"},
        )["data"]
        self.assertEqual(renamed["title"], "Renamed task")
        deleted = self.request(
            "/projects/codex/sessions/session-codex-1",
            method="DELETE",
        )["data"]
        self.assertEqual(deleted["deleted"], "session-codex-1")
        self.assertEqual(self.request("/sessions?project=codex")["data"]["sessions"], [])

        with self.assertRaises(urllib.error.HTTPError) as missing:
            self.request(
                "/projects/claude-code/sessions/session-codex-1",
                method="GET",
            )
        self.assertEqual(missing.exception.code, 404)

        self.request(
            "/projects/codex/sessions/session-codex-2",
            method="POST",
            body={"title": "keep"},
        )
        with self.assertRaises(urllib.error.HTTPError) as wrong_project:
            self.request(
                "/projects/claude-code/sessions/session-codex-2",
                method="DELETE",
            )
        self.assertEqual(wrong_project.exception.code, 404)
        self.assertEqual(
            self.request("/sessions/session-codex-2")["data"]["project"],
            "codex",
        )

    def test_rejects_wrong_token_and_unknown_project(self) -> None:
        with self.assertRaises(urllib.error.HTTPError) as unauthorized:
            self.request("/status", token="wrong")
        self.assertEqual(unauthorized.exception.code, 401)
        with self.assertRaises(urllib.error.HTTPError) as missing:
            self.request("/skills?project=missing")
        self.assertEqual(missing.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
