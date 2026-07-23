"""Durable project-scoped session metadata for a production Host."""

from __future__ import annotations

import json
import os
import stat
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable


class SessionStoreError(ValueError):
    """Raised when session metadata is invalid, conflicting, or unavailable."""


IdFactory = Callable[[], str]


class ProjectSessionStore:
    def __init__(
        self,
        path: str,
        *,
        projects: tuple[str, ...],
        max_bytes: int = 4 * 1024 * 1024,
        id_factory: IdFactory | None = None,
    ) -> None:
        if not isinstance(path, str) or not path or not os.path.isabs(path):
            raise SessionStoreError("session store path must be absolute")
        if not projects or any(not isinstance(item, str) or not item for item in projects):
            raise SessionStoreError("session store projects are invalid")
        if max_bytes <= 0:
            raise SessionStoreError("session store max_bytes must be positive")
        self.path = Path(path)
        try:
            parent = self.path.parent.resolve(strict=True)
        except OSError as exc:
            raise SessionStoreError("session store parent is unavailable") from exc
        if not parent.is_dir():
            raise SessionStoreError("session store parent is not a directory")
        if self.path.is_symlink():
            raise SessionStoreError("session store cannot be a symlink")
        self.projects = frozenset(projects)
        self.max_bytes = max_bytes
        self._id_factory = id_factory or (lambda: f"huanhermes:{uuid.uuid4().hex[:16]}")
        self._lock = threading.RLock()
        self._records = self._load()

    @property
    def count(self) -> int:
        with self._lock:
            return len(self._records)

    def project_for(self, session_key: str) -> str | None:
        with self._lock:
            record = self._records.get(session_key)
            return str(record["project"]) if record is not None else None

    def bind(self, session_key: str, project: str) -> dict[str, Any]:
        key = self._session_key(session_key)
        project_name = self._project(project)
        with self._lock:
            existing = self._records.get(key)
            if existing is not None:
                if existing["project"] != project_name:
                    raise SessionStoreError("session belongs to another project")
                return dict(existing)
            return self._create_locked(project_name, None, key)

    def create(
        self,
        *,
        project: str,
        title: str | None = None,
        session_key: str | None = None,
    ) -> dict[str, Any]:
        project_name = self._project(project)
        key = self._session_key(session_key or self._id_factory())
        with self._lock:
            existing = self._records.get(key)
            if existing is not None:
                if existing["project"] != project_name:
                    raise SessionStoreError("session belongs to another project")
                raise SessionStoreError("session already exists")
            return self._create_locked(project_name, title, key)

    def list(self, *, project: str | None = None) -> list[dict[str, Any]]:
        project_name = self._project(project) if project is not None else None
        with self._lock:
            records = [
                dict(record)
                for record in self._records.values()
                if project_name is None or record["project"] == project_name
            ]
        records.sort(key=lambda item: float(item["updated_at"]), reverse=True)
        return records

    def get(self, session_key: str, *, project: str | None = None) -> dict[str, Any]:
        key = self._session_key(session_key)
        project_name = self._project(project) if project is not None else None
        with self._lock:
            record = self._records.get(key)
            if record is None or (project_name is not None and record["project"] != project_name):
                raise SessionStoreError("session not found")
            return dict(record)

    def rename(self, session_key: str, title: str, *, project: str | None = None) -> dict[str, Any]:
        key = self._session_key(session_key)
        name = self._title(title)
        project_name = self._project(project) if project is not None else None
        with self._lock:
            record = self._records.get(key)
            if record is None or (project_name is not None and record["project"] != project_name):
                raise SessionStoreError("session not found")
            updated = dict(record)
            updated.update({"title": name, "name": name, "updated_at": time.time()})
            self._records[key] = updated
            self._persist_locked()
            return dict(updated)

    def delete(self, session_key: str, *, project: str | None = None) -> dict[str, Any]:
        key = self._session_key(session_key)
        project_name = self._project(project) if project is not None else None
        with self._lock:
            record = self._records.get(key)
            if record is None or (project_name is not None and record["project"] != project_name):
                raise SessionStoreError("session not found")
            removed = self._records.pop(key)
            self._persist_locked()
            return dict(removed)

    def _create_locked(self, project: str, title: str | None, session_key: str) -> dict[str, Any]:
        now = time.time()
        name = self._title(title or "New session")
        record = {
            "id": session_key,
            "session_key": session_key,
            "project": project,
            "title": name,
            "name": name,
            "created_at": now,
            "updated_at": now,
            "mode": "default",
            "model": "",
            "workdir": "",
        }
        self._records[session_key] = record
        try:
            self._persist_locked()
        except Exception:
            self._records.pop(session_key, None)
            raise
        return dict(record)

    def _load(self) -> dict[str, dict[str, Any]]:
        if not self.path.exists():
            return {}
        try:
            metadata = self.path.stat()
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > self.max_bytes:
                raise SessionStoreError("session store file is invalid")
            raw = self.path.read_bytes()
            value = json.loads(raw.decode("utf-8")) if raw else []
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise SessionStoreError("cannot read session store") from exc
        if not isinstance(value, list):
            raise SessionStoreError("session store root must be an array")
        records: dict[str, dict[str, Any]] = {}
        for item in value:
            if not isinstance(item, dict):
                raise SessionStoreError("session store record is invalid")
            key = self._session_key(item.get("session_key"))
            project = self._project(item.get("project"))
            title = self._title(item.get("title") or item.get("name") or "New session")
            created_at = self._timestamp(item.get("created_at"))
            updated_at = self._timestamp(item.get("updated_at"))
            if key in records:
                raise SessionStoreError("session store contains duplicate keys")
            records[key] = {
                "id": key,
                "session_key": key,
                "project": project,
                "title": title,
                "name": title,
                "created_at": created_at,
                "updated_at": updated_at,
                "mode": str(item.get("mode") or "default")[:64],
                "model": str(item.get("model") or "")[:200],
                "workdir": str(item.get("workdir") or "")[:4096],
            }
        return records

    def _persist_locked(self) -> None:
        payload = json.dumps(
            list(self._records.values()),
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        if len(payload) > self.max_bytes:
            raise SessionStoreError("session store size limit reached")
        temporary = self.path.with_name(f".{self.path.name}.{uuid.uuid4().hex}.tmp")
        descriptor = -1
        try:
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            view = memoryview(payload)
            while view:
                written = os.write(descriptor, view)
                if written <= 0:
                    raise SessionStoreError("session store write failed")
                view = view[written:]
            os.fsync(descriptor)
            os.close(descriptor)
            descriptor = -1
            os.replace(temporary, self.path)
            os.chmod(self.path, 0o600)
        except OSError as exc:
            raise SessionStoreError("cannot persist session store") from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass

    def _project(self, value: Any) -> str:
        if not isinstance(value, str) or value not in self.projects:
            raise SessionStoreError("project not found")
        return value

    @staticmethod
    def _session_key(value: Any) -> str:
        if not isinstance(value, str) or not value.strip() or len(value) > 256 or "\x00" in value:
            raise SessionStoreError("session_key is invalid")
        return value

    @staticmethod
    def _title(value: Any) -> str:
        if not isinstance(value, str) or not value.strip() or "\x00" in value:
            raise SessionStoreError("session title is invalid")
        return value.strip()[:200]

    @staticmethod
    def _timestamp(value: Any) -> float:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
            raise SessionStoreError("session timestamp is invalid")
        return float(value)
