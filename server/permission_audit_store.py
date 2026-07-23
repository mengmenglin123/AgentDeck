"""Durable, redacted permission audit sink for a Host process."""

from __future__ import annotations

import json
import os
import stat
import threading
from pathlib import Path

from permission_gate import PermissionAuditRecord


class PermissionAuditStoreError(OSError):
    """Raised when an audit record cannot be durably appended."""


class JsonlPermissionAuditStore:
    """Append permission audit records to a private JSONL file."""

    def __init__(
        self,
        path: str,
        *,
        max_bytes: int = 10 * 1024 * 1024,
        fsync: bool = True,
    ) -> None:
        if not isinstance(path, str) or not path or not os.path.isabs(path):
            raise ValueError("audit path must be an absolute path")
        if max_bytes <= 0:
            raise ValueError("max_bytes must be positive")
        self.path = Path(path)
        try:
            parent = self.path.parent.resolve(strict=True)
        except OSError as exc:
            raise PermissionAuditStoreError("audit parent directory is unavailable") from exc
        if not parent.is_dir():
            raise PermissionAuditStoreError("audit parent is not a directory")
        self.max_bytes = max_bytes
        self.fsync = fsync
        self._lock = threading.RLock()

    def __call__(self, record: PermissionAuditRecord) -> None:
        self.append(record)

    def append(self, record: PermissionAuditRecord) -> None:
        payload = self._encode(record)
        with self._lock:
            flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
            flags |= getattr(os, "O_NOFOLLOW", 0)
            try:
                descriptor = os.open(self.path, flags, 0o600)
            except OSError as exc:
                raise PermissionAuditStoreError("cannot open audit store") from exc
            try:
                metadata = os.fstat(descriptor)
                if not stat.S_ISREG(metadata.st_mode):
                    raise PermissionAuditStoreError("audit target is not a regular file")
                os.fchmod(descriptor, 0o600)
                if metadata.st_size + len(payload) > self.max_bytes:
                    raise PermissionAuditStoreError("audit store size limit reached")
                view = memoryview(payload)
                while view:
                    written = os.write(descriptor, view)
                    if written <= 0:
                        raise PermissionAuditStoreError("audit store write failed")
                    view = view[written:]
                if self.fsync:
                    os.fsync(descriptor)
            except PermissionAuditStoreError:
                raise
            except OSError as exc:
                raise PermissionAuditStoreError("audit store append failed") from exc
            finally:
                os.close(descriptor)

    @staticmethod
    def _encode(record: PermissionAuditRecord) -> bytes:
        if not isinstance(record, PermissionAuditRecord):
            raise TypeError("record must be PermissionAuditRecord")
        value = {
            "action": record.action,
            "request_id": record.request_id,
            "session_key": record.session_key,
            "scope": record.scope,
            "decision": record.decision,
            "ts": record.ts,
        }
        return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
