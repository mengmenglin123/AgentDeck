from __future__ import annotations

import json
import os
import tempfile
import unittest
import urllib.request

import file_index
from production_host_config import ProjectRuntimeConfig
from production_management import ProductionManagementServer
from session_store import ProjectSessionStore

_DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class TestFileIndex(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        for rel in ("src/MgmtClient.kt", "src/main.py", "README.md", "node_modules/x/index.js", ".hidden/secret.txt", "docs/guide/main.md"):
            path = os.path.join(root, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write("x")
        outside = tempfile.mkdtemp()
        with open(os.path.join(outside, "leak.txt"), "w") as f:
            f.write("x")
        os.symlink(os.path.join(outside, "leak.txt"), os.path.join(root, "link.txt"))
        os.symlink(outside, os.path.join(root, "linkdir"))
        self.root = root

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_walk_skips_vendor_hidden_and_symlinks(self) -> None:
        files = file_index.list_files(self.root)
        self.assertIn("src/main.py", files)
        self.assertNotIn("node_modules/x/index.js", files)
        self.assertFalse(any(f.startswith(".hidden") for f in files))
        self.assertNotIn("link.txt", files)
        self.assertFalse(any("leak" in f for f in files))

    def test_ranking(self) -> None:
        files = file_index.list_files(self.root)
        self.assertEqual(file_index.rank(files, "main")[:2], ["src/main.py", "docs/guide/main.md"])
        self.assertEqual(file_index.rank(files, "@mgcl"), ["src/MgmtClient.kt"])
        self.assertEqual(file_index.rank(files, "zzz"), [])
        self.assertEqual(len(file_index.rank(files, "", limit=2)), 2)

    def test_management_endpoint_and_capability(self) -> None:
        project = ProjectRuntimeConfig(name="p", agent_type="claudecode", command=("/bin/true",), workdir=self.root)
        with tempfile.TemporaryDirectory() as store_dir:
            server = ProductionManagementServer(
                (project,), default_project="p", token="t" * 32,
                sessions=ProjectSessionStore(os.path.join(store_dir, "s.json"), projects=("p",)), port=0,
            )
            server.start()
            try:
                host, port = server.address
                def get(path: str):
                    req = urllib.request.Request(f"http://{host}:{port}/api/v1{path}", headers={"Authorization": "Bearer " + "t" * 32})
                    with _DIRECT.open(req, timeout=5) as r:
                        return json.loads(r.read())
                self.assertIn("file_search", get("/status")["data"]["capabilities"])
                files = get("/files/search?project=p&q=readme")["data"]["files"]
                self.assertEqual(files, [{"path": "README.md", "type": "file"}])
            finally:
                server.shutdown()


if __name__ == "__main__":
    unittest.main()
