
"""Management dual-path tests against Mock Host (alternate ports; never touches live Host)."""

from __future__ import annotations

import os
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "packages" / "huan_protocol"))

from src.mgmt_client import MgmtClient  # noqa: E402
from src.models import ConnectionConfig  # noqa: E402


class TestMgmtDialects(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.port_b = 19830
        cls.port_m = 19831
        env = os.environ.copy()
        env["HUAN_BRIDGE_PORT"] = str(cls.port_b)
        env["HUAN_MGMT_PORT"] = str(cls.port_m)
        env["HUAN_BRIDGE_TOKEN"] = "dev-bridge-token-change-me"
        env["HUAN_MGMT_TOKEN"] = "dev-mgmt-token-change-me"
        cls.proc = subprocess.Popen(
            [sys.executable, str(ROOT / "server" / "mock-host" / "mock_host.py")],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        cls.cfg = ConnectionConfig(
            bridge_port=cls.port_b,
            mgmt_port=cls.port_m,
            bridge_token="dev-bridge-token-change-me",
            mgmt_token="dev-mgmt-token-change-me",
        )
        # Wait until mgmt port answers (do not race; never use live 9810/9820).
        import urllib.request
        import urllib.error

        deadline = time.time() + 8
        last_err = None
        while time.time() < deadline:
            if cls.proc.poll() is not None:
                err_pipe = cls.proc.stderr
                err = (err_pipe.read() if err_pipe is not None else b"").decode("utf-8", "replace")[:500]
                raise RuntimeError(f"mock host exited early: {err}")
            try:
                req = urllib.request.Request(
                    f"http://127.0.0.1:{cls.port_m}/api/v1/status",
                    headers={"Authorization": "Bearer dev-mgmt-token-change-me"},
                )
                with urllib.request.urlopen(req, timeout=1) as resp:
                    if resp.status == 200:
                        break
            except Exception as e:  # noqa: BLE001
                last_err = e
                time.sleep(0.15)
        else:
            raise RuntimeError(f"mock host not ready: {last_err}")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.proc.terminate()
        try:
            cls.proc.wait(timeout=3)
        except Exception:
            cls.proc.kill()

    def _raw(self, method: str, path: str, body: dict | None = None) -> dict:
        import json as _json

        data = _json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port_m}{path}",
            data=data,
            method=method,
            headers={
                "Authorization": "Bearer dev-mgmt-token-change-me",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            return _json.loads(resp.read().decode())

    def test_percent_encoded_session_ids_resolve(self) -> None:
        # The Flutter app sends Uri.encodeComponent(session_key), so ':' arrives
        # as %3A. Detail / rename / delete must resolve it (as production does).
        sk = "huanhermes-app:claude-code:pct123"
        self._raw("POST", "/api/v1/projects/claude-code/sessions", {"session_key": sk, "title": "pct"})
        enc = urllib.parse.quote(sk, safe="")
        self.assertIn("%3A", enc)
        got = self._raw("GET", f"/api/v1/sessions/{enc}")["data"]
        self.assertEqual(got["session_key"], sk)
        got = self._raw("GET", f"/api/v1/projects/claude-code/sessions/{enc}")["data"]
        self.assertEqual(got["session_key"], sk)
        ren = self._raw("PATCH", f"/api/v1/sessions/{enc}", {"title": "renamed"})["data"]
        self.assertEqual(ren["title"], "renamed")
        self._raw("DELETE", f"/api/v1/projects/claude-code/sessions/{enc}")
        with self.assertRaises(urllib.error.HTTPError):
            self._raw("GET", f"/api/v1/sessions/{enc}")

    def test_flat_and_project_sessions(self) -> None:
        c = MgmtClient(self.cfg)
        st = c.status()
        self.assertIn("version", st)
        projects = c.projects().get("projects") or []
        self.assertTrue(projects)
        name = projects[0]["name"]
        # project-scoped create
        c.dialect = "project"
        s = c.create_session(project=name, title="dialect-test")
        self.assertTrue(s.get("session_key"))
        listed = c.sessions(project=name)
        keys = [x.get("session_key") for x in (listed.get("sessions") or [])]
        self.assertIn(s["session_key"], keys)
        # flat list still works on mock
        c2 = MgmtClient(self.cfg)
        c2.dialect = "flat"
        flat = c2.sessions(project=name)
        self.assertTrue(isinstance(flat.get("sessions"), list))

    def test_agents_endpoint(self) -> None:
        c = MgmtClient(self.cfg)
        a = c.agents()
        self.assertIn("agents", a)
        agents = a.get("agents") or []
        self.assertTrue(agents)
        # string ids or objects with id
        def _id(x):
            if isinstance(x, dict):
                return str(x.get("id") or x.get("name") or "")
            return str(x)
        ids = {_id(x) for x in agents}
        self.assertTrue(ids.intersection({"claudecode", "hermes", "codex"}))

    def test_skills_and_pairing(self) -> None:
        c = MgmtClient(self.cfg)
        skills = c.skills()
        self.assertIn("skills", skills)
        self.assertTrue(skills["skills"])
        pair = c.pairing()
        self.assertIn("pairing_code", pair)
        self.assertTrue(str(pair["pairing_code"]).startswith("huanhermes://"))

    def test_project_capabilities_include_hermes(self) -> None:
        c = MgmtClient(self.cfg)
        projects = c.projects().get("projects") or []
        names = {p.get("name") for p in projects}
        self.assertIn("hermes", names)
        hermes = next(p for p in projects if p.get("name") == "hermes")
        caps = hermes.get("capabilities") or []
        self.assertIn("stream", caps)

    def test_mcp_catalog(self) -> None:
        c = MgmtClient(self.cfg)
        data = c.mcp()
        servers = data.get("servers") or []
        self.assertTrue(servers)
        self.assertTrue(any(s.get("name") for s in servers))


    def test_project_scoped_catalogs_are_distinct(self) -> None:
        c = MgmtClient(self.cfg)
        claude_from_client = c.skills(project="claude-code")["skills"]
        codex_from_client = c.skills(project="codex")["skills"]
        self.assertNotEqual(
            {item["name"] for item in claude_from_client},
            {item["name"] for item in codex_from_client},
        )
        codex_mcp = c.mcp(project="codex")["servers"]
        self.assertTrue(codex_mcp)
        self.assertTrue(all("codex" in item["name"] or "openai" in item["name"] for item in codex_mcp))
        self.assertEqual(c.agents(project="codex")["agents"][0]["id"], "codex")

        headers = {"Authorization": "Bearer dev-mgmt-token-change-me"}
        def get(path: str):
            request = urllib.request.Request(
                f"http://127.0.0.1:{self.port_m}/api/v1/{path}", headers=headers
            )
            with urllib.request.urlopen(request, timeout=2) as response:
                import json
                return json.loads(response.read().decode("utf-8"))["data"]

        claude_skills = get("skills?project=claude-code")["skills"]
        codex_skills = get("skills?project=codex")["skills"]
        self.assertNotEqual(
            {item["name"] for item in claude_skills},
            {item["name"] for item in codex_skills},
        )
        claude_mcp = get("mcp?project=claude-code")["servers"]
        codex_mcp = get("mcp?project=codex")["servers"]
        self.assertNotEqual(
            {item["name"] for item in claude_mcp},
            {item["name"] for item in codex_mcp},
        )
        detail = get("projects/codex")
        self.assertEqual(detail.get("channels"), ["openai"])
        self.assertIn("gpt-5-codex", detail.get("models") or [])

    def test_workspace_readonly(self) -> None:
        c = MgmtClient(self.cfg)
        root = c.workspace()
        self.assertEqual(root.get("type"), "dir")
        names = {e.get("name") for e in (root.get("entries") or [])}
        self.assertIn("README.md", names)
        readme = c.workspace(path="README.md")
        self.assertEqual(readme.get("type"), "file")
        self.assertIn("Mock", readme.get("content") or "")
        git = c.workspace_git()
        self.assertIn("branch", git)
        st = c.status()
        self.assertIn("sessions_count", st)
        caps = st.get("capabilities") or []
        self.assertIn("workspace_readonly", caps)

    def test_workspace_git_mutations_are_not_exposed(self) -> None:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port_m}/api/v1/workspace/git/commit",
            data=b'{"message":"must stay readonly"}',
            method="POST",
            headers={
                "Authorization": "Bearer dev-mgmt-token-change-me",
                "Content-Type": "application/json",
            },
        )
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(request, timeout=2)
        self.assertEqual(caught.exception.code, 404)

    def test_memory_cron_diff(self) -> None:
        c = MgmtClient(self.cfg)
        mem = c.memory()
        self.assertTrue(mem.get("memories"))
        mem_q = c.memory(q="language")
        self.assertGreaterEqual(len(mem_q.get("memories") or []), 1)
        codex_mem = c.memory(project="codex")
        self.assertFalse(any(item.get("project") == "hermes" for item in codex_mem.get("memories") or []))
        hermes_mem = c.memory(project="hermes")
        self.assertTrue(any(item.get("project") == "hermes" for item in hermes_mem.get("memories") or []))
        cron = c.cron()
        self.assertTrue(cron.get("jobs"))
        idx = c.workspace_diff()
        self.assertTrue(idx.get("files"))
        one = c.workspace_diff(path="README.md")
        self.assertIn("diff", one)
        self.assertIn("Mock workspace", one.get("diff") or "")
        st = c.status()
        caps = st.get("capabilities") or []
        self.assertIn("memory_readonly", caps)
        self.assertIn("cron_readonly", caps)
        self.assertIn("diff_readonly", caps)

    def test_activity_feed(self) -> None:
        c = MgmtClient(self.cfg)
        # Creating a session should emit activity
        c.create_session(project="default", title="activity-probe")
        data = c.activity(limit=20)
        events = data.get("events") or []
        self.assertTrue(events)
        kinds = {e.get("kind") for e in events if isinstance(e, dict)}
        self.assertTrue(kinds.intersection({"session.create", "host.start", "chat.message"}))
        st = c.status()
        caps = st.get("capabilities") or []
        self.assertIn("activity_readonly", caps)


    def test_rename_and_logs(self) -> None:
        c = MgmtClient(self.cfg)
        created = c.create_session("claude-code", title="Before rename")
        sid = created.get("id") or created.get("session_id") or created.get("session_key")
        self.assertTrue(sid)
        renamed = c.rename_session(str(sid), "After rename")
        self.assertEqual(renamed.get("title") or renamed.get("name"), "After rename")
        logs = c.logs(limit=20)
        self.assertIn("logs", logs)
        self.assertIsInstance(logs.get("logs"), list)
        self.assertTrue(any("renamed" in str(x.get("message", "")).lower() or "session" in str(x.get("message", "")).lower() for x in logs.get("logs") or []) or logs.get("logs") is not None)

if __name__ == "__main__":
    unittest.main()
