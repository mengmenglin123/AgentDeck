"""Read-only authenticated Management catalog for a production Host."""

from __future__ import annotations

import external_sessions
import file_index
import workspace_git_write
import host_feeds
import workspace_readonly

import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable
from urllib.parse import parse_qs, unquote, urlparse

from production_host_config import ProjectRuntimeConfig
from session_store import ProjectSessionStore, SessionStoreError
from token_auth import tokens_match


class ProductionManagementServer:
    """Expose project-scoped catalogs without owning Agent session state."""

    def __init__(
        self,
        projects: tuple[ProjectRuntimeConfig, ...],
        *,
        default_project: str,
        token: str,
        sessions: ProjectSessionStore,
        close_session: Callable[[str], None] | None = None,
        active_sessions: Callable[[], tuple[str, ...]] | None = None,
        pending_permissions: Callable[[str], list[dict[str, Any]]] | None = None,
        session_activity: Callable[[str], dict[str, Any] | None] | None = None,
        activity_feed: Any = None,
        log_ring: Any = None,
        audit_path: str | None = None,
        push: Any = None,
        devices: Any = None,
        git_write: bool = False,
        bridge_port: int = 9810,
        host: str = "127.0.0.1",
        port: int = 9820,
        request_timeout: float = 30.0,
    ) -> None:
        if request_timeout <= 0:
            raise ValueError("Management request timeout must be positive")
        self.request_timeout = float(request_timeout)
        if not projects:
            raise ValueError("at least one Management project is required")
        if not token:
            raise ValueError("Management token must not be empty")
        if not host:
            raise ValueError("Management host must not be empty")
        if port < 0 or port > 65535:
            raise ValueError("Management port must be between 0 and 65535")
        if bridge_port < 0 or bridge_port > 65535:
            raise ValueError("Bridge port must be between 0 and 65535")
        self.projects = {project.name: project for project in projects}
        if default_project not in self.projects:
            raise ValueError("Management default project is not configured")
        self.default_project = default_project
        self._git_write = bool(git_write)
        self.token = token
        self.sessions = sessions
        self._close_session = close_session or (lambda session_key: None)
        self._active_sessions = active_sessions or (lambda: ())
        self._pending_permissions = pending_permissions
        self._session_activity = session_activity
        self._activity_feed = activity_feed
        self._log_ring = log_ring
        self._audit_path = audit_path
        self._push = push
        self._devices = devices
        self.bridge_port = bridge_port
        self.host = host
        self.port = port
        self.started_at = time.monotonic()
        self._server: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None
        self._lock = threading.Lock()

    @property
    def address(self) -> tuple[str, int] | None:
        with self._lock:
            if self._server is None:
                return None
            address = self._server.server_address
            return str(address[0]), int(address[1])

    def start(self) -> None:
        with self._lock:
            if self._server is not None:
                return
            handler = self._handler_type()
            server = ThreadingHTTPServer((self.host, self.port), handler)
            server.daemon_threads = True
            self._server = server
            self._thread = threading.Thread(
                target=server.serve_forever,
                name="huanhermes-management",
                daemon=True,
            )
            self._thread.start()

    def shutdown(self) -> None:
        with self._lock:
            server = self._server
            thread = self._thread
            self._server = None
            self._thread = None
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=2)

    def _handler_type(self) -> type[BaseHTTPRequestHandler]:
        owner = self

        class Handler(BaseHTTPRequestHandler):
            server_version = "HuanHermesManagement/1"
            # Idle/slow clients (slowloris) must not pin a handler thread forever.
            timeout = owner.request_timeout

            def _authorized_or_401(self) -> bool:
                if owner._authorized(self.headers.get("Authorization", "")):
                    return True
                owner._send(self, 401, {"ok": False, "error": "unauthorized"})
                return False

            def do_GET(self) -> None:  # noqa: N802
                if self._authorized_or_401():
                    owner._handle_get(self)

            def do_POST(self) -> None:  # noqa: N802
                if urlparse(self.path).path == "/api/v1/pairing/claim":
                    owner._claim(self)  # code-gated, no bearer token yet
                    return
                if self._authorized_or_401():
                    owner._handle_mutation(self, "POST")

            def do_PATCH(self) -> None:  # noqa: N802
                if self._authorized_or_401():
                    owner._handle_mutation(self, "PATCH")

            def do_DELETE(self) -> None:  # noqa: N802
                if self._authorized_or_401():
                    owner._handle_mutation(self, "DELETE")

            def do_OPTIONS(self) -> None:  # noqa: N802
                self.send_response(204)
                self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
                self.end_headers()

            def log_message(self, format: str, *args: object) -> None:
                return

        return Handler

    def _handle_get(self, request: BaseHTTPRequestHandler) -> None:
        parsed = urlparse(request.path)
        if not parsed.path.startswith("/api/v1"):
            self._send(request, 404, {"ok": False, "error": "not found"})
            return
        path = parsed.path[len("/api/v1"):] or "/"
        query = parse_qs(parsed.query)
        if path == "/status":
            self._send(request, 200, {
                "ok": True,
                "data": {
                    "version": "production-host-0.1",
                    "uptime_seconds": int(time.monotonic() - self.started_at),
                    "projects_count": len(self.projects),
                    "sessions_count": self.sessions.count,
                    "active_sessions": len(self._active_sessions()),
                    "capabilities": self._capabilities(),
                },
            })
            return
        if path == "/projects":
            self._send(request, 200, {"ok": True, "data": {"projects": [self._project(item) for item in self.projects.values()]}})
            return
        if path == "/sessions":
            project = query.get("project", [None])[0]
            try:
                records = self.sessions.list(project=project)
            except SessionStoreError:
                self._send(request, 404, {"ok": False, "error": "project not found"})
                return
            self._send(request, 200, {"ok": True, "data": {"sessions": self._overview(records), "active_keys": self._active_keys(records)}})
            return
        if path.startswith("/sessions/"):
            self._send_session_detail(request, unquote(path[len("/sessions/"):]), None)
            return
        project_session_prefix = "/projects/"
        if path.startswith(project_session_prefix) and path.endswith("/sessions"):
            project = unquote(path[len(project_session_prefix):-len("/sessions")].rstrip("/"))
            try:
                records = self.sessions.list(project=project)
            except SessionStoreError:
                self._send(request, 404, {"ok": False, "error": "project not found"})
                return
            self._send(request, 200, {"ok": True, "data": {"sessions": self._overview(records), "active_keys": self._active_keys(records)}})
            return
        if path.startswith(project_session_prefix) and "/sessions/" in path:
            prefix, session_key = path.split("/sessions/", 1)
            project = unquote(prefix[len(project_session_prefix):])
            self._send_session_detail(request, unquote(session_key), project)
            return
        if path.startswith("/projects/"):
            name = unquote(path[len("/projects/"):])
            project = self.projects.get(name)
            if project is None:
                self._send(request, 404, {"ok": False, "error": "project not found"})
                return
            self._send(request, 200, {"ok": True, "data": self._project(project)})
            return
        if path in {"/skills", "/mcp", "/agents"}:
            project = self._selected(query.get("project", [None])[0])
            if project is None:
                self._send(request, 404, {"ok": False, "error": "project not found"})
                return
            if path == "/skills":
                data = {"skills": [self._skill(project, name) for name in project.skills]}
            elif path == "/mcp":
                data = {"servers": [self._mcp(project, name) for name in project.mcp_servers]}
            else:
                data = {"agents": [self._agent(project)], "platforms": [{"type": "bridge", "connected": True}]}
            self._send(request, 200, {"ok": True, "data": data})
            return
        if path in {"/activity", "/logs", "/audit"}:
            def num(name: str, default: int) -> int:
                try:
                    return int(query.get(name, [str(default)])[0])
                except ValueError:
                    return default
            if path == "/activity" and self._activity_feed is not None:
                self._send(request, 200, {"ok": True, "data": {"events": self._activity_feed.list(num("limit", 50))}})
            elif path == "/logs" and self._log_ring is not None:
                items = self._log_ring.list(num("limit", 80), query.get("level", [""])[0], query.get("source", [""])[0])
                self._send(request, 200, {"ok": True, "data": {"logs": items, "count": len(items)}})
            elif path == "/audit" and self._audit_path:
                records = host_feeds.read_audit_tail(self._audit_path, num("limit", 100))
                self._send(request, 200, {"ok": True, "data": {"records": records, "count": len(records)}})
            else:
                self._send(request, 404, {"ok": False, "error": "not found"})
            return
        if path in {"/workspace", "/workspace/", "/workspace/git", "/workspace/diff"}:
            project = self._selected(query.get("project", [None])[0])
            if project is None:
                self._send(request, 404, {"ok": False, "error": "project not found"})
                return
            rel = query.get("path", [""])[0][:1024]
            try:
                if path == "/workspace/git":
                    data = workspace_readonly.git_status(project.workdir)
                elif path == "/workspace/diff":
                    data = workspace_readonly.diff(project.workdir, rel)
                else:
                    data = workspace_readonly.listing(project.workdir, rel)
            except workspace_readonly.WorkspaceError as exc:
                self._send(request, exc.status, {"ok": False, "error": str(exc)})
                return
            self._send(request, 200, {"ok": True, "data": data})
            return
        if path == "/files/search":
            project = self._selected(query.get("project", [None])[0])
            if project is None:
                self._send(request, 404, {"ok": False, "error": "project not found"})
                return
            try:
                limit = int(query.get("limit", ["30"])[0])
            except ValueError:
                limit = 30
            q = query.get("q", [""])[0][:200]
            self._send(request, 200, {"ok": True, "data": {"files": file_index.search(project.workdir, q, limit)}})
            return
        if path == "/external-sessions" or path.startswith("/external-sessions/"):
            project = self._selected(query.get("project", [None])[0])
            if project is None:
                self._send(request, 404, {"ok": False, "error": "project not found"})
                return
            if path == "/external-sessions":
                self._send(request, 200, {"ok": True, "data": {"sessions": external_sessions.list_sessions(project.workdir)}})
                return
            detail = external_sessions.transcript(project.workdir, path.rsplit("/", 1)[1])
            if detail is None:
                self._send(request, 404, {"ok": False, "error": "session not found"})
            else:
                self._send(request, 200, {"ok": True, "data": detail})
            return
        if path == "/devices" and self._devices is not None:
            self._send(request, 200, {"ok": True, "data": {"devices": self._devices.list()}})
            return
        if path == "/pairing":
            self._send(request, 200, {"ok": True, "data": {
                "scheme": "huanhermes", "version": 1, "bridge_port": self.bridge_port,
                "mgmt_port": self.port, "use_tls": False,
            }})
            return
        self._send(request, 404, {"ok": False, "error": "not found"})

    def _handle_mutation(self, request: BaseHTTPRequestHandler, method: str) -> None:
        parsed = urlparse(request.path)
        if not parsed.path.startswith("/api/v1"):
            self._send(request, 404, {"ok": False, "error": "not found"})
            return
        path = parsed.path[len("/api/v1"):] or "/"
        body = self._read_json(request)
        if body is None:
            return
        if path.startswith("/devices/") and method == "DELETE" and self._devices is not None:
            removed = self._devices.revoke(unquote(path[len("/devices/"):]))
            self._send(request, 200 if removed else 404, {"ok": removed, "data": {"removed": removed}})
            return
        if path.startswith("/workspace/git/") and method == "POST":
            action = path[len("/workspace/git/"):]
            if not self._git_write or action not in workspace_git_write.ACTIONS:
                self._send(request, 404, {"ok": False, "error": "git write is disabled on this Host"})
                return
            project = self._selected(parse_qs(parsed.query).get("project", [None])[0])
            if project is None:
                self._send(request, 404, {"ok": False, "error": "project not found"})
                return
            try:
                data = workspace_git_write.perform(project.workdir, action, body)
            except workspace_git_write.GitWriteError as exc:
                self._feed("git", f"git {action} failed in {project.name}", level="warning")
                self._send(request, exc.status, {"ok": False, "error": str(exc)})
                return
            self._feed("git", f"git {action} in {project.name}" + (f" ({data.get('commit')})" if data.get("commit") else ""))
            self._send(request, 200, {"ok": True, "data": data})
            return
        if path == "/push/register":
            if self._push is None:
                self._send(request, 404, {"ok": False, "error": "not found"})
                return
            device_id = body.get("device_id")
            if method == "DELETE":
                removed = self._push.unregister(device_id) if isinstance(device_id, str) else False
                self._send(request, 200, {"ok": True, "data": {"removed": removed}})
            elif method == "POST":
                ok = self._push.register(device_id, body.get("endpoint"), str(body.get("kind") or "unifiedpush"))
                if ok:
                    self._send(request, 200, {"ok": True, "data": {"registered": True}})
                else:
                    self._send(request, 400, {"ok": False, "error": "invalid device_id or endpoint"})
            else:
                self._send(request, 405, {"ok": False, "error": "method not allowed"})
            return
        project: str | None = None
        session_key: str | None = None
        if path.startswith("/projects/") and "/sessions" in path:
            prefix, _, suffix = path.partition("/sessions")
            if suffix not in {"", "/"} and not suffix.startswith("/"):
                self._send(request, 404, {"ok": False, "error": "not found"})
                return
            project = unquote(prefix[len("/projects/"):])
            session_key = unquote(suffix[len("/"):]) if suffix.startswith("/") else None
        elif path == "/sessions":
            project_value = body.get("project")
            project = project_value if isinstance(project_value, str) else None
        elif path.startswith("/sessions/"):
            session_key = unquote(path[len("/sessions/"):])
            project_value = body.get("project")
            project = project_value if isinstance(project_value, str) else None
        else:
            self._send(request, 404, {"ok": False, "error": "not found"})
            return
        try:
            if method == "POST":
                record = self.sessions.create(
                    project=project or self.default_project,
                    title=body.get("title") or body.get("name"),
                    session_key=session_key or body.get("session_key"),
                )
                self._send(request, 201, {"ok": True, "data": record})
                return
            if not session_key:
                self._send(request, 400, {"ok": False, "error": "session key is required"})
                return
            if method == "PATCH":
                title = body.get("title") or body.get("name")
                record = self.sessions.rename(session_key, title, project=project)
                self._send(request, 200, {"ok": True, "data": record})
                return
            # Verify existence and project ownership before touching a live
            # Agent session, so a wrong-project DELETE cannot kill it.
            self.sessions.get(session_key, project=project)
            self._close_session(session_key)
            record = self.sessions.delete(session_key, project=project)
            self._send(request, 200, {"ok": True, "data": {"deleted": record["session_key"]}})
        except SessionStoreError as exc:
            error_text = str(exc)
            status = 409 if "already exists" in error_text or "another project" in error_text else 404
            if "invalid" in error_text:
                status = 400
            self._send(request, status, {"ok": False, "error": error_text})

    def _send_session_detail(
        self,
        request: BaseHTTPRequestHandler,
        session_key: str,
        project: str | None,
    ) -> None:
        try:
            record = self.sessions.get(session_key, project=project)
        except SessionStoreError:
            self._send(request, 404, {"ok": False, "error": "session not found"})
            return
        record["transcript"] = []
        record["active"] = session_key in self._active_sessions()
        self._send(request, 200, {"ok": True, "data": record})

    def _feed(self, kind: str, summary: str, *, level: str = "info") -> None:
        if self._activity_feed is not None:
            try:
                self._activity_feed.add(kind, summary, source="app", level=level)
            except Exception:  # noqa: BLE001 - the feed must never break a request
                pass

    def _capabilities(self) -> list[str]:
        caps = ["projects", "sessions", "skills", "mcp", "agents", "pairing", "file_search",
                "workspace_readonly", "diff_readonly", "external_sessions"]
        if self._activity_feed is not None:
            caps.append("activity_readonly")
        if self._log_ring is not None:
            caps.append("logs_readonly")
        if self._audit_path:
            caps.append("audit_readonly")
        if self._push is not None:
            caps.append("push")
        if self._devices is not None:
            caps.append("device_tokens")
        if self._git_write:
            caps.append("git_write")
        if self._pending_permissions is not None or self._session_activity is not None:
            caps.append("session_overview")
        return caps

    def _overview(self, records: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Add optional overview fields; older clients ignore unknown keys."""
        if self._pending_permissions is None and self._session_activity is None:
            return records
        active = set(self._active_sessions())
        enriched: list[dict[str, Any]] = []
        for item in records:
            out = dict(item)
            key = str(item.get("session_key") or "")
            pending: list[dict[str, Any]] = []
            if self._pending_permissions is not None and key:
                try:
                    pending = list(self._pending_permissions(key))
                except Exception:  # noqa: BLE001
                    pending = []
            activity = None
            if self._session_activity is not None and key:
                try:
                    activity = self._session_activity(key)
                except Exception:  # noqa: BLE001
                    activity = None
            running = bool(activity and activity.get("running")) and key in active
            out["pending_permissions"] = pending
            out["status"] = "needs_you" if pending else "running" if running else "idle"
            if activity and activity.get("preview"):
                out["last_message_preview"] = activity["preview"]
            if activity and activity.get("updated_at"):
                ts = float(activity["updated_at"])
                current = out.get("updated_at")
                if not isinstance(current, (int, float)) or ts > float(current):
                    out["updated_at"] = ts
            enriched.append(out)
        return enriched

    def _active_keys(self, records: list[dict[str, Any]]) -> dict[str, bool]:
        active = set(self._active_sessions())
        return {str(item["session_key"]): item["session_key"] in active for item in records}

    @staticmethod
    def _read_json(request: BaseHTTPRequestHandler) -> dict[str, Any] | None:
        raw_length = request.headers.get("Content-Length", "0")
        try:
            length = int(raw_length)
        except ValueError:
            length = -1
        if length < 0 or length > 64 * 1024:
            ProductionManagementServer._send(request, 413, {"ok": False, "error": "request body too large"})
            return None
        try:
            value = json.loads(request.rfile.read(length).decode("utf-8")) if length else {}
        except (UnicodeDecodeError, json.JSONDecodeError):
            ProductionManagementServer._send(request, 400, {"ok": False, "error": "invalid json"})
            return None
        if not isinstance(value, dict):
            ProductionManagementServer._send(request, 400, {"ok": False, "error": "json object required"})
            return None
        return value

    def _selected(self, name: str | None) -> ProjectRuntimeConfig | None:
        return self.projects.get(name or self.default_project)

    @staticmethod
    def _project(project: ProjectRuntimeConfig) -> dict[str, Any]:
        capabilities = list(project.capabilities)
        if project.terminal_command is not None and "terminal" not in capabilities:
            capabilities.append("terminal")
        return {
            "name": project.name,
            "agent_type": project.agent_type,
            "capabilities": capabilities,
            "models": list(project.models),
            "channels": list(project.channels),
            "terminal": project.terminal_command is not None,
        }

    @staticmethod
    def _agent(project: ProjectRuntimeConfig) -> dict[str, Any]:
        return {
            "id": project.name,
            "name": project.name,
            "status": "configured",
            "type": project.agent_type,
            "model": project.models[0] if project.models else "",
            "provider": project.channels[0] if project.channels else "",
            "capabilities": list(project.capabilities),
        }

    @staticmethod
    def _skill(project: ProjectRuntimeConfig, name: str) -> dict[str, Any]:
        return {
            "name": name,
            "description": f"{project.name} Host-configured skill",
            "source": project.name,
            "category": "agent",
            "version": "configured",
            "tags": [project.name, "agent"],
        }

    @staticmethod
    def _mcp(project: ProjectRuntimeConfig, name: str) -> dict[str, Any]:
        return {
            "name": name,
            "status": "configured",
            "kind": "host",
            "enabled": True,
            "tools": [],
            "description": f"{project.name} Host-configured MCP server",
        }

    def _authorized(self, value: str) -> bool:
        prefix = "Bearer "
        if not isinstance(value, str) or not value.startswith(prefix):
            return False
        presented = value[len(prefix):]
        if tokens_match(presented, self.token):
            return True
        if self._devices is not None:
            device = self._devices.check(presented, "mgmt")
            if device is not None:
                self._devices.touch(device)
                return True
        return False

    def _claim(self, request: BaseHTTPRequestHandler) -> None:
        if self._devices is None:
            self._send(request, 404, {"ok": False, "error": "not found"})
            return
        body = self._read_json(request)
        if body is None:
            return
        tokens = self._devices.claim(body.get("code"), body.get("device_id"), body.get("name"))
        if tokens is None:
            self._send(request, 403, {"ok": False, "error": "invalid or expired pairing code"})
            return
        self._send(request, 200, {"ok": True, "data": {**tokens, "bridge_port": self.bridge_port, "mgmt_port": self.port}})

    @staticmethod
    def _send(request: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        request.send_response(status)
        request.send_header("Content-Type", "application/json; charset=utf-8")
        request.send_header("Content-Length", str(len(body)))
        request.end_headers()
        request.wfile.write(body)
