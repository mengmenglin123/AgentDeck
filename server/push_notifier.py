"""Wake-up pushes for the App (UnifiedPush / ntfy endpoints).

The App registers a push endpoint URL over Management (authenticated). When
an Agent asks for permission, the Host POSTs a tiny reference-only payload to
every registered endpoint; the App then fetches the real details over its own
authenticated Management connection. Payloads never carry prompts, commands,
tokens or file contents.
"""
from __future__ import annotations

import json
import os
import threading
import time
import urllib.error
import urllib.request
from typing import Any, Callable, Mapping
from urllib.parse import urlparse

MAX_REGISTRATIONS = 32
MIN_INTERVAL_SECONDS = 10.0

Sender = Callable[[str, bytes], int]


def _default_sender(url: str, body: bytes) -> int:
    request = urllib.request.Request(url, data=body, method="POST", headers={
        "Content-Type": "application/json", "TTL": "3600", "Urgency": "high",
    })
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except (OSError, ValueError):
        return 0


def valid_endpoint(url: Any) -> bool:
    if not isinstance(url, str) or not (8 <= len(url) <= 2048):
        return False
    parsed = urlparse(url)
    return parsed.scheme in {"https", "http"} and bool(parsed.netloc) and not parsed.username and not parsed.password


class PushNotifier:
    def __init__(
        self,
        store_path: str | None = None,
        *,
        sender: Sender | None = None,
        clock: Callable[[], float] = time.monotonic,
        async_send: bool = True,
    ) -> None:
        self._path = store_path
        self._send = sender or _default_sender
        self._clock = clock
        self._async = async_send
        self._lock = threading.Lock()
        self._regs: dict[str, dict[str, Any]] = {}
        self._last: dict[str, float] = {}
        self._load()

    # --- registrations -------------------------------------------------

    def register(self, device_id: str, endpoint: str, kind: str = "unifiedpush") -> bool:
        if not isinstance(device_id, str) or not device_id.strip() or len(device_id) > 128 or not valid_endpoint(endpoint):
            return False
        with self._lock:
            if device_id not in self._regs and len(self._regs) >= MAX_REGISTRATIONS:
                oldest = min(self._regs, key=lambda k: self._regs[k].get("ts", 0))
                self._regs.pop(oldest, None)
            self._regs[device_id] = {"endpoint": endpoint, "kind": kind[:32], "ts": time.time()}
            self._save()
        return True

    def unregister(self, device_id: str) -> bool:
        with self._lock:
            removed = self._regs.pop(device_id, None) is not None
            if removed:
                self._save()
        return removed

    def registered(self, device_id: str) -> bool:
        with self._lock:
            return device_id in self._regs

    @property
    def count(self) -> int:
        with self._lock:
            return len(self._regs)

    # --- events ----------------------------------------------------------

    def observe(self, event: Mapping[str, Any]) -> None:
        """Journal observer: a permission request wakes every registered device."""
        if event.get("type") not in {"buttons", "card"}:
            return
        if "perm:" not in json.dumps(event.get("buttons") or event.get("card") or "", ensure_ascii=False):
            return
        session_key = event.get("session_key")
        if not isinstance(session_key, str):
            return
        now = self._clock()
        with self._lock:
            if now - self._last.get(session_key, -1e9) < MIN_INTERVAL_SECONDS:
                return
            self._last[session_key] = now
            targets = list(self._regs.items())
        body = json.dumps({"type": "approval", "session_key": session_key[:200], "ts": int(time.time())}).encode()
        for device_id, reg in targets:
            if self._async:
                threading.Thread(target=self._deliver, args=(device_id, reg["endpoint"], body), daemon=True).start()
            else:
                self._deliver(device_id, reg["endpoint"], body)

    def _deliver(self, device_id: str, endpoint: str, body: bytes) -> None:
        status = self._send(endpoint, body)
        if status in {404, 410}:
            # The distributor dropped this registration: forget it.
            with self._lock:
                if self._regs.get(device_id, {}).get("endpoint") == endpoint:
                    self._regs.pop(device_id, None)
                    self._save()

    # --- persistence -------------------------------------------------------

    def _load(self) -> None:
        if not self._path:
            return
        try:
            with open(self._path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            return
        if isinstance(data, dict):
            for device_id, reg in data.items():
                if isinstance(reg, dict) and valid_endpoint(reg.get("endpoint")):
                    self._regs[str(device_id)] = {"endpoint": reg["endpoint"], "kind": str(reg.get("kind", "unifiedpush")), "ts": reg.get("ts", 0)}

    def _save(self) -> None:
        if not self._path:
            return
        tmp = self._path + ".tmp"
        try:
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(self._regs, f)
            os.replace(tmp, self._path)
        except OSError:
            pass
