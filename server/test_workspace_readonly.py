from __future__ import annotations

import os
import subprocess
import tempfile
import unittest

import workspace_readonly as ws


class TestWorkspaceReadonly(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        os.makedirs(os.path.join(self.root, "src"))
        with open(os.path.join(self.root, "src", "a.py"), "w") as f:
            f.write("print(1)\n")
        with open(os.path.join(self.root, "bin.dat"), "wb") as f:
            f.write(b"\0\1\2")
        self.outside = tempfile.mkdtemp()
        os.symlink(self.outside, os.path.join(self.root, "out"))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_listing_and_file(self) -> None:
        d = ws.listing(self.root)
        self.assertEqual([e["name"] for e in d["entries"]], ["src", "bin.dat"])
        f = ws.listing(self.root, "src/a.py")
        self.assertEqual(f["content"], "print(1)\n")
        self.assertTrue(ws.listing(self.root, "bin.dat")["binary"])
        self.assertEqual(ws.listing(self.root, "src")["parent"], "")

    def test_escape_refused(self) -> None:
        for bad in ("../x", "src/../../etc", "out/x"):
            with self.assertRaises(ws.WorkspaceError):
                ws.listing(self.root, bad)

    def test_git_status_and_diff(self) -> None:
        if subprocess.run(["git", "--version"], capture_output=True).returncode != 0:
            self.skipTest("no git")
        os.remove(os.path.join(self.root, "out"))
        run = lambda *a: subprocess.run(["git", "-C", self.root, *a], capture_output=True, check=True)
        run("init", "-q", "-b", "main")
        run("-c", "user.email=a@b", "-c", "user.name=a", "add", "src/a.py")
        run("-c", "user.email=a@b", "-c", "user.name=a", "commit", "-qm", "init")
        with open(os.path.join(self.root, "src", "a.py"), "w") as f:
            f.write("print(2)\n")
        st = ws.git_status(self.root)
        self.assertEqual(st["branch"], "main")
        self.assertIn({"path": "src/a.py", "status": "M", "staged": False}, st["files"])
        self.assertIn("bin.dat", [f["path"] for f in st["files"]])
        d = ws.diff(self.root, "src/a.py")["diff"]
        self.assertIn("-print(1)", d)
        self.assertIn("+print(2)", d)
        self.assertEqual(len(ws.diff(self.root)["files"]), 2)

    def test_not_a_repo(self) -> None:
        self.assertEqual(ws.git_status(self.root)["files"], [])


if __name__ == "__main__":
    unittest.main()
