from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from session_store import ProjectSessionStore, SessionStoreError


class TestProjectSessionStore(unittest.TestCase):
    def test_persists_project_scoped_create_rename_delete(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "sessions.json")
            store = ProjectSessionStore(path, projects=("claude-code", "codex"))
            created = store.create(project="codex", title="Codex work", session_key="s1")
            self.assertEqual(created["project"], "codex")
            renamed = store.rename("s1", "Renamed", project="codex")
            self.assertEqual(renamed["title"], "Renamed")
            reloaded = ProjectSessionStore(path, projects=("claude-code", "codex"))
            self.assertEqual(reloaded.get("s1")["title"], "Renamed")
            reloaded.delete("s1", project="codex")
            self.assertEqual(reloaded.list(), [])

    def test_bind_rejects_cross_project_session_reuse(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = ProjectSessionStore(
                str(Path(directory) / "sessions.json"),
                projects=("claude-code", "codex"),
            )
            store.bind("s1", "codex")
            with self.assertRaises(SessionStoreError):
                store.bind("s1", "claude-code")
            self.assertEqual(store.project_for("s1"), "codex")

    def test_rejects_unknown_project_symlink_and_oversized_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sessions.json"
            store = ProjectSessionStore(str(path), projects=("codex",), max_bytes=120)
            with self.assertRaises(SessionStoreError):
                store.create(project="missing", session_key="s1")
            with self.assertRaises(SessionStoreError):
                store.create(project="codex", title="x" * 200, session_key="s2")
            target = Path(directory) / "target.json"
            target.write_text("[]", encoding="utf-8")
            link = Path(directory) / "link.json"
            link.symlink_to(target)
            with self.assertRaises(SessionStoreError):
                ProjectSessionStore(str(link), projects=("codex",))


if __name__ == "__main__":
    unittest.main()
