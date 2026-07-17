"""Minimal Management REST client (Python stdlib)."""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any, Dict, Optional

from .models import AuthError, ConnectionConfig, ProtocolError


class MgmtClient:
    def __init__(self, config: Optional[ConnectionConfig] = None):
        self.config = config or ConnectionConfig()

    def _request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        url = self.config.mgmt_base_url.rstrip("/") + path
        data = None
        headers = {
            "Authorization": f"Bearer {self.config.mgmt_token}",
            "Accept": "application/json",
        }
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                raw = resp.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", errors="replace")
            if e.code == 401:
                raise AuthError(raw or "unauthorized") from e
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError as je:
                raise ProtocolError(f"HTTP {e.code}: {raw}") from je
            raise ProtocolError(payload.get("error") or raw) from e
        except urllib.error.URLError as e:
            raise ProtocolError(str(e)) from e

        try:
            payload = json.loads(raw) if raw else {"ok": True, "data": {}}
        except json.JSONDecodeError as e:
            raise ProtocolError(f"invalid json: {raw[:200]}") from e
        if not payload.get("ok", False):
            raise ProtocolError(payload.get("error") or "request failed")
        return payload.get("data") or {}

    def status(self) -> Dict[str, Any]:
        return self._request("GET", "/status")

    def projects(self) -> Dict[str, Any]:
        return self._request("GET", "/projects")

    def project(self, name: str) -> Dict[str, Any]:
        return self._request("GET", f"/projects/{name}")

    def sessions(self, project: Optional[str] = None) -> Dict[str, Any]:
        q = f"?project={project}" if project else ""
        return self._request("GET", f"/sessions{q}")

    def create_session(self, project: str, title: Optional[str] = None) -> Dict[str, Any]:
        body: Dict[str, Any] = {"project": project}
        if title:
            body["title"] = title
        return self._request("POST", "/sessions", body)

    def delete_session(self, session_id: str) -> Dict[str, Any]:
        return self._request("DELETE", f"/sessions/{session_id}")
