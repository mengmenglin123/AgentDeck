
"""Management REST client (Python stdlib) — Mock flat + cc-connect project-scoped."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
import uuid
from typing import Any, Dict, Optional

from .models import AuthError, ConnectionConfig, ProtocolError


class MgmtClient:
    def __init__(self, config: Optional[ConnectionConfig] = None):
        self.config = config or ConnectionConfig()
        self.dialect: Optional[str] = None  # "flat" | "project"

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
            raise ProtocolError(payload.get("error") or raw or f"HTTP {e.code}") from e
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

    def agents(self) -> Dict[str, Any]:
        try:
            return self._request("GET", "/agents")
        except ProtocolError:
            return {"agents": [], "platforms": []}

    def sessions(self, project: Optional[str] = None) -> Dict[str, Any]:
        if self.dialect == "project" and project:
            return self._request("GET", f"/projects/{project}/sessions")
        if self.dialect == "flat":
            q = f"?project={project}" if project else ""
            return self._request("GET", f"/sessions{q}")

        if project:
            try:
                data = self._request("GET", f"/projects/{project}/sessions")
                self.dialect = "project"
                return data
            except ProtocolError as e:
                if "not found" not in str(e).lower() and "404" not in str(e):
                    raise
        q = f"?project={project}" if project else ""
        data = self._request("GET", f"/sessions{q}")
        self.dialect = "flat"
        return data

    def create_session(
        self,
        project: str,
        title: Optional[str] = None,
        session_key: Optional[str] = None,
    ) -> Dict[str, Any]:
        body: Dict[str, Any] = {"project": project}
        if title:
            body["title"] = title
            body["name"] = title
        sk = session_key or f"huanhermes-app:{project}:{uuid.uuid4().hex[:10]}"
        body["session_key"] = sk

        if self.dialect == "flat":
            return self._request("POST", "/sessions", body)
        if self.dialect == "project":
            return self._request("POST", f"/projects/{project}/sessions", body)

        try:
            data = self._request("POST", f"/projects/{project}/sessions", body)
            self.dialect = "project"
            return data
        except ProtocolError as e:
            msg = str(e).lower()
            if "not found" not in msg and "404" not in msg and "session_key" not in msg:
                # try still flat
                pass
        data = self._request("POST", "/sessions", body)
        self.dialect = "flat"
        return data

    def delete_session(self, session_id: str, project: Optional[str] = None) -> Dict[str, Any]:
        if self.dialect == "project" and project:
            return self._request("DELETE", f"/projects/{project}/sessions/{session_id}")
        try:
            return self._request("DELETE", f"/sessions/{session_id}")
        except ProtocolError as e:
            if project and ("not found" in str(e).lower() or "404" in str(e)):
                self.dialect = "project"
                return self._request("DELETE", f"/projects/{project}/sessions/{session_id}")
            raise

    def session_detail(self, session_id: str, project: Optional[str] = None) -> Dict[str, Any]:
        try:
            return self._request("GET", f"/sessions/{session_id}")
        except ProtocolError as e:
            if project and ("not found" in str(e).lower() or "404" in str(e)):
                return self._request("GET", f"/projects/{project}/sessions/{session_id}")
            raise
