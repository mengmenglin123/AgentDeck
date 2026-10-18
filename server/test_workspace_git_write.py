from __future__ import annotations

import os
import subprocess
import tempfile
import unittest

import workspace_git_write as gw


def git(root: str, *args: str) -> str:
    return subprocess.run(["git", "-C", root, *args], capture_output=True, check=True, text=True).stdout


class TestGitWrite(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        git(self.root, "init", "-q")
        git(self.root, "config", "user.email", "t@example.com")
        git(self.root, "config", "user.name", "t")
        with open(os.path.join(self.root, "a.txt"), "w") as fh:
            fh.write("a\n")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_stage_commit_unstage(self) -> None:
        gw.perform(self.root, "stage", {"paths": ["a.txt"]})
        self.assertIn("A  a.txt", git(self.root, "status", "--porcelain"))
        out = gw.perform(self.root, "commit", {"message": "first"})
        self.assertTrue(out["commit"])
        self.assertIn("first", git(self.root, "log", "--oneline"))
        with open(os.path.join(self.root, "a.txt"), "a") as fh:
            fh.write("b\n")
        gw.perform(self.root, "stage", {"paths": ["a.txt"]})
        gw.perform(self.root, "unstage", {"paths": ["a.txt"]})
        self.assertIn(" M a.txt", git(self.root, "status", "--porcelain"))

    def test_rejects_bad_input(self) -> None:
        for body in ({"paths": ["../x"]}, {"paths": ["--all"]}, {"paths": []}, {}):
            with self.assertRaises(gw.GitWriteError):
                gw.perform(self.root, "stage", body)
        with self.assertRaises(gw.GitWriteError):
            gw.perform(self.root, "commit", {"message": "  "})
        with self.assertRaises(gw.GitWriteError) as ctx:
            gw.perform(self.root, "push", {})
        self.assertEqual(ctx.exception.status, 409)  # no remote configured
        with self.assertRaises(gw.GitWriteError):
            gw.perform(self.root, "rebase", {})


if __name__ == "__main__":
    unittest.main()
