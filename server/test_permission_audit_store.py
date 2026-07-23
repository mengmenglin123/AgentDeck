from __future__ import annotations

import json
import stat
import tempfile
import unittest
from pathlib import Path

from permission_audit_store import JsonlPermissionAuditStore, PermissionAuditStoreError
from permission_gate import PermissionAuditRecord


class TestJsonlPermissionAuditStore(unittest.TestCase):
    @staticmethod
    def record(session_key: str = "s1") -> PermissionAuditRecord:
        return PermissionAuditRecord(
            action="permission.decided",
            request_id="p1",
            session_key=session_key,
            scope="shell",
            decision="allow",
            ts=100.0,
        )

    def test_appends_redacted_record_with_private_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "permissions.jsonl"
            store = JsonlPermissionAuditStore(str(path), fsync=False)
            store(self.record())
            store(self.record("s2"))
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 2)
            self.assertEqual(json.loads(lines[0])["decision"], "allow")
            self.assertNotIn("prompt", lines[0])
            self.assertNotIn("reply_ctx", lines[0])
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_rejects_symlink_and_size_overflow(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "target.jsonl"
            link = Path(directory) / "permissions.jsonl"
            link.symlink_to(target)
            with self.assertRaises(PermissionAuditStoreError):
                JsonlPermissionAuditStore(str(link), fsync=False).append(self.record())

            path = Path(directory) / "limited.jsonl"
            store = JsonlPermissionAuditStore(str(path), max_bytes=10, fsync=False)
            with self.assertRaises(PermissionAuditStoreError):
                store.append(self.record())

    def test_rejects_relative_path(self) -> None:
        with self.assertRaises(ValueError):
            JsonlPermissionAuditStore("audit.jsonl")


if __name__ == "__main__":
    unittest.main()
