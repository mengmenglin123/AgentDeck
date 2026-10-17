"""Per-device tokens and one-time pairing codes (M5).

* ``production_host.py pair --config X`` mints a short one-time code and prints
  a ``huanhermes://connect?...&code=...`` link / QR.
* The App POSTs ``/api/v1/pairing/claim`` with the code (no other secret) and
  receives its own Bridge + Management tokens. Only SHA-256 hashes are stored.
* A device can be revoked without rotating the master tokens.

The store is a private JSON file shared by the running Host and the CLI, so it
is re-read on each claim/check (cheap: a few KB, mtime-cached).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import threading
import time
from typing import Any, Callable

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I
CODE_LENGTH = 8
CODE_TTL_SECONDS = 600
MAX_DEVICES = 64
MAX_FAILURES_PER_MINUTE = 10


def _hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def normalize_code(code: Any) -> str:
    if not isinstance(code, str):
        return ""
    return "".join(ch for ch in code.upper() if ch.isalnum())[:32]


class DeviceTokenStore:
    def __init__(self, path: str | None, *, clock: Callable[[], float] = time.time) -> None:
        self._path = path
        self._clock = clock
        self._lock = threading.Lock()
        self._data: dict[str, Any] = {"devices": {}, "codes": []}
        self._mtime: float | None = None
        self._failures: list[float] = []

    # --- persistence -----------------------------------------------------

    def _reload(self) -> None:
        if not self._path:
            return
        try:
            mtime = os.stat(self._path).st_mtime
        except OSError:
            return
        if mtime == self._mtime:
            return
        try:
            with open(self._path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            return
        if isinstance(data, dict):
            self._data = {"devices": dict(data.get("devices") or {}), "codes": list(data.get("codes") or [])}
            self._mtime = mtime

    def _save(self) -> None:
        if not self._path:
            return
        tmp = f"{self._path}.{os.getpid()}.tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(self._data, f)
        os.replace(tmp, self._path)
        try:
            self._mtime = os.stat(self._path).st_mtime
        except OSError:
            self._mtime = None

    # --- pairing codes ----------------------------------------------------

    def issue_code(self, ttl: float = CODE_TTL_SECONDS) -> str:
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        now = self._clock()
        with self._lock:
            self._reload()
            codes = [c for c in self._data["codes"] if c.get("expires", 0) > now]
            codes.append({"hash": _hash(code), "expires": now + ttl})
            self._data["codes"] = codes[-8:]
            self._save()
        return code

    def claim(self, code: Any, device_id: Any, name: Any = None) -> dict[str, str] | None:
        """Single-use: returns fresh tokens, or None (wrong/expired code, rate limited)."""
        now = self._clock()
        code_n = normalize_code(code)
        if not isinstance(device_id, str) or not device_id.strip() or len(device_id) > 128:
            return None
        with self._lock:
            self._failures = [t for t in self._failures if now - t < 60]
            if len(self._failures) >= MAX_FAILURES_PER_MINUTE:
                return None
            self._reload()
            wanted = _hash(code_n) if len(code_n) == CODE_LENGTH else ""
            match = None
            for entry in self._data["codes"]:
                if entry.get("expires", 0) > now and wanted and hmac.compare_digest(str(entry.get("hash", "")), wanted):
                    match = entry
            if match is None:
                self._failures.append(now)
                return None
            self._data["codes"] = [c for c in self._data["codes"] if c is not match and c.get("expires", 0) > now]
            bridge_token = secrets.token_urlsafe(32)
            mgmt_token = secrets.token_urlsafe(32)
            devices = self._data["devices"]
            if device_id not in devices and len(devices) >= MAX_DEVICES:
                oldest = min(devices, key=lambda k: devices[k].get("created", 0))
                devices.pop(oldest, None)
            devices[device_id] = {
                "name": (str(name)[:64] if name else "Android"),
                "bridge": _hash(bridge_token), "mgmt": _hash(mgmt_token),
                "created": now, "last_seen": now,
            }
            self._save()
        return {"bridge_token": bridge_token, "mgmt_token": mgmt_token}

    # --- auth ---------------------------------------------------------------

    def check(self, token: Any, kind: str) -> str | None:
        """Device id owning this token (``kind`` = bridge | mgmt), else None."""
        if not isinstance(token, str) or not token or kind not in {"bridge", "mgmt"}:
            return None
        digest = _hash(token)
        with self._lock:
            self._reload()
            found = None
            for device_id, info in self._data["devices"].items():
                if hmac.compare_digest(str(info.get(kind, "")), digest):
                    found = device_id
            return found

    def touch(self, device_id: str) -> None:
        with self._lock:
            info = self._data["devices"].get(device_id)
            if info is not None:
                info["last_seen"] = self._clock()

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            self._reload()
            return [
                {"device_id": d, "name": i.get("name"), "created": i.get("created"), "last_seen": i.get("last_seen")}
                for d, i in sorted(self._data["devices"].items(), key=lambda kv: -float(kv[1].get("created", 0)))
            ]

    def revoke(self, device_id: str) -> bool:
        with self._lock:
            self._reload()
            removed = self._data["devices"].pop(device_id, None) is not None
            if removed:
                self._save()
            return removed
