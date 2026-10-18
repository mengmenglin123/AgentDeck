from __future__ import annotations

import json
import os
import sys
import tempfile
import textwrap
import unittest

from agent_extensions import AgentExtensions, ExtensionError

FAKE_MCP = textwrap.dedent('''
    import json, sys
    for line in sys.stdin:
        msg = json.loads(line)
        if msg.get("method") == "initialize":
            print(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {"protocolVersion": "2025-06-18", "capabilities": {}}}), flush=True)
        elif msg.get("method") == "tools/list":
            print(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {"tools": [{"name": "echo", "description": "Echo text"}]}}), flush=True)
''')


class TestAgentExtensions(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.tmp.name, "home")
        self.work = os.path.join(self.tmp.name, "work")
        os.makedirs(self.home); os.makedirs(self.work)
        self.ext = AgentExtensions(home=self.home, write=True)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_discovers_claude_skills_and_mcp_without_secrets(self) -> None:
        d = os.path.join(self.home, ".claude", "skills", "pdf")
        os.makedirs(d)
        with open(os.path.join(d, "SKILL.md"), "w") as fh:
            fh.write("---\nname: pdf\ndescription: Work with PDFs\n---\nbody")
        with open(os.path.join(self.home, ".claude.json"), "w") as fh:
            json.dump({"mcpServers": {"gh": {"type": "http", "url": "https://x.example/mcp?k=1", "headers": {"Authorization": "Bearer SECRET"}}}}, fh)
        skills = self.ext.skills(self.work, "claudecode")
        self.assertEqual([(s["name"], s["scope"], s["editable"]) for s in skills], [("pdf", "user", False)])
        self.assertIn("body", self.ext.skill_content(self.work, "claudecode", "pdf")["content"])
        servers = self.ext.servers(self.work, "claudecode", "p")
        self.assertEqual(servers[0]["target"], "https://x.example/mcp")
        self.assertEqual(servers[0]["secret_keys"], ["Authorization"])
        self.assertNotIn("SECRET", json.dumps(servers))

    def test_add_probe_remove_project_mcp(self) -> None:
        self.ext.add_server(self.work, "claudecode", {"name": "fake", "kind": "stdio", "command": sys.executable, "args": ["-c", FAKE_MCP], "env": {"TOKEN": "t"}})
        with open(os.path.join(self.work, ".mcp.json")) as fh:
            self.assertEqual(json.load(fh)["mcpServers"]["fake"]["env"], {"TOKEN": "t"})
        with self.assertRaises(ExtensionError):
            self.ext.add_server(self.work, "claudecode", {"name": "fake", "command": "x"})
        tools = self.ext.probe(self.work, "claudecode", "p", "fake")["tools"]
        self.assertEqual(tools, [{"name": "echo", "description": "Echo text"}])
        self.assertEqual(self.ext.servers(self.work, "claudecode", "p")[0]["tools"], ["echo"])
        self.ext.remove_server(self.work, "claudecode", "p", "fake")
        self.assertEqual(self.ext.servers(self.work, "claudecode", "p"), [])

    def test_codex_toml_round_trip(self) -> None:
        cfg = os.path.join(self.home, ".codex", "config.toml")
        os.makedirs(os.path.dirname(cfg))
        with open(cfg, "w") as fh:
            fh.write('model = "gpt-5"\n\n[mcp_servers.keep]\ncommand = "a"\n')
        self.ext.add_server(self.work, "codex", {"name": "web", "kind": "http", "url": "https://w.example/mcp", "headers": {"X-Key": "v"}})
        names = [s["name"] for s in self.ext.servers(self.work, "codex", "p")]
        self.assertEqual(sorted(names), ["keep", "web"])
        self.ext.remove_server(self.work, "codex", "p", "web")
        with open(cfg) as fh:
            text = fh.read()
        self.assertIn("[mcp_servers.keep]", text)
        self.assertNotIn("web", text)
        self.assertIn('model = "gpt-5"', text)

    def test_project_skill_create_delete_and_write_gate(self) -> None:
        out = self.ext.create_skill(self.work, "claudecode", {"name": "deploy", "description": "Deploy the app", "body": "Run make deploy"})
        self.assertTrue(os.path.isfile(os.path.join(self.work, ".claude", "skills", "deploy", "SKILL.md")))
        self.assertIn("deploy", out["path"])
        self.assertTrue(self.ext.skills(self.work, "claudecode")[0]["editable"])
        with self.assertRaises(ExtensionError):
            self.ext.create_skill(self.work, "claudecode", {"name": "Bad Name", "description": "x"})
        self.ext.delete_skill(self.work, "claudecode", "deploy")
        self.assertEqual(self.ext.skills(self.work, "claudecode"), [])
        ro = AgentExtensions(home=self.home, write=False)
        with self.assertRaises(ExtensionError) as ctx:
            ro.add_server(self.work, "claudecode", {"name": "x", "command": "y"})
        self.assertEqual(ctx.exception.status, 404)


if __name__ == "__main__":
    unittest.main()
