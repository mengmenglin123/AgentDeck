"""The Agents' real MCP servers and skills, as the App sees them.

Read side (always on): finds what Claude Code / Codex / Hermes would load for a
project, from their own config files, and lists it without secret values (env and
header values are masked). Write side (``[workspace] extensions_write = true``,
capability ``extensions_write``): add / remove MCP servers in the project's own
config file, create / delete project skills, and probe an MCP server for its tools.

Where things live (the agents' documented locations):

* Claude Code: project MCP ``<workdir>/.mcp.json`` (``mcpServers``), user MCP in
  ``~/.claude.json`` (top-level and ``projects[<workdir>]``); skills in
  ``<workdir>/.claude/skills/<name>/SKILL.md`` and ``~/.claude/skills``.
* Codex: MCP in ``~/.codex/config.toml`` (``[mcp_servers.<name>]``); skills in
  ``<workdir>/.agents/skills`` and ``~/.codex/skills``.
* Hermes: skills in ``~/.hermes/skills`` (read only here).
"""

from __future__ import annotations

import json
import os
import re
import select
import shutil
import subprocess
import threading
import time
import tomllib
import urllib.error
import urllib.request
from typing import Any, Mapping

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
SKILL_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
MAX_SKILL_BYTES = 64 * 1024
PROBE_TIMEOUT = 15.0
MCP_PROTOCOL = "2025-06-18"


class ExtensionError(ValueError):
    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.status = status


def family(agent_type: str) -> str:
    a = (agent_type or "").lower()
    if "claude" in a:
        return "claude"
    if "codex" in a:
        return "codex"
    if "hermes" in a:
        return "hermes"
    return "any"


class AgentExtensions:
    def __init__(self, *, home: str | None = None, write: bool = False) -> None:
        self.home = os.path.realpath(home or os.path.expanduser("~"))
        self.write = bool(write)
        self._tools: dict[tuple[str, str], list[dict[str, str]]] = {}
        self._lock = threading.Lock()

    # ------------------------------------------------------------------ helpers
    def _display(self, path: str) -> str:
        return "~" + path[len(self.home):] if path.startswith(self.home + os.sep) else path

    @staticmethod
    def _read_json(path: str) -> dict[str, Any]:
        try:
            with open(path, encoding="utf-8") as fh:
                value = json.load(fh)
            return value if isinstance(value, dict) else {}
        except (OSError, ValueError):
            return {}

    def _require_write(self) -> None:
        if not self.write:
            raise ExtensionError("extension changes are disabled on this Host", 404)

    # ------------------------------------------------------------------- skills
    def _skill_dirs(self, workdir: str, fam: str) -> list[tuple[str, str, bool]]:
        """(directory, scope, editable) in priority order."""
        dirs: list[tuple[str, str, bool]] = []
        if fam in ("claude", "any"):
            dirs += [(os.path.join(workdir, ".claude", "skills"), "project", True),
                     (os.path.join(self.home, ".claude", "skills"), "user", False)]
        if fam in ("codex", "any"):
            dirs += [(os.path.join(workdir, ".agents", "skills"), "project", True),
                     (os.path.join(self.home, ".codex", "skills"), "user", False)]
        if fam in ("hermes", "any"):
            dirs += [(os.path.join(self.home, ".hermes", "skills"), "user", False)]
        return dirs

    def project_skill_dir(self, workdir: str, fam: str) -> str:
        return os.path.join(workdir, ".agents" if fam == "codex" else ".claude", "skills")

    @staticmethod
    def _frontmatter(text: str) -> dict[str, str]:
        if not text.startswith("---"):
            return {}
        end = text.find("\n---", 3)
        if end < 0:
            return {}
        out: dict[str, str] = {}
        for line in text[3:end].splitlines():
            if ":" in line and not line.startswith((" ", "\t")):
                k, _, v = line.partition(":")
                out[k.strip()] = v.strip().strip("\"'")
        return out

    def skills(self, workdir: str, agent_type: str) -> list[dict[str, Any]]:
        fam = family(agent_type)
        seen: set[str] = set()
        out: list[dict[str, Any]] = []
        for base, scope, editable in self._skill_dirs(workdir, fam):
            try:
                names = sorted(os.listdir(base))
            except OSError:
                continue
            for name in names:
                path = os.path.join(base, name, "SKILL.md")
                if name in seen or not os.path.isfile(path):
                    continue
                try:
                    with open(path, encoding="utf-8", errors="replace") as fh:
                        head = fh.read(4096)
                except OSError:
                    continue
                meta = self._frontmatter(head)
                seen.add(name)
                out.append({
                    "name": meta.get("name") or name,
                    "id": name,
                    "description": meta.get("description", ""),
                    "source": scope,
                    "scope": scope,
                    "category": "skill",
                    "path": self._display(path),
                    "editable": editable and self.write,
                    "tags": [scope, fam] if fam != "any" else [scope],
                })
        return out

    def skill_content(self, workdir: str, agent_type: str, name: str) -> dict[str, Any]:
        for base, scope, _ in self._skill_dirs(workdir, family(agent_type)):
            path = os.path.join(base, name, "SKILL.md")
            if os.path.isfile(path) and os.path.realpath(path).startswith(os.path.realpath(base) + os.sep):
                with open(path, encoding="utf-8", errors="replace") as fh:
                    content = fh.read(MAX_SKILL_BYTES)
                return {"name": name, "scope": scope, "path": self._display(path), "content": content}
        raise ExtensionError("skill not found", 404)

    def create_skill(self, workdir: str, agent_type: str, body: Mapping[str, Any]) -> dict[str, Any]:
        self._require_write()
        name = str(body.get("name") or "").strip()
        if not SKILL_RE.match(name):
            raise ExtensionError("skill name: lowercase letters, digits and '-', up to 64")
        description = " ".join(str(body.get("description") or "").split())[:1024]
        if not description:
            raise ExtensionError("description is required")
        text = str(body.get("body") or "").strip()
        content = f"---\nname: {name}\ndescription: {description}\n---\n\n{text}\n"
        if len(content.encode()) > MAX_SKILL_BYTES:
            raise ExtensionError("skill too large")
        base = self.project_skill_dir(workdir, family(agent_type))
        target = os.path.join(base, name)
        if os.path.exists(target):
            raise ExtensionError("a skill with this name already exists", 409)
        os.makedirs(target)
        with open(os.path.join(target, "SKILL.md"), "w", encoding="utf-8") as fh:
            fh.write(content)
        return {"name": name, "path": self._display(os.path.join(target, "SKILL.md"))}

    def delete_skill(self, workdir: str, agent_type: str, name: str) -> dict[str, Any]:
        self._require_write()
        if not SKILL_RE.match(name):
            raise ExtensionError("invalid skill name")
        base = os.path.realpath(self.project_skill_dir(workdir, family(agent_type)))
        target = os.path.realpath(os.path.join(base, name))
        if not target.startswith(base + os.sep) or not os.path.isfile(os.path.join(target, "SKILL.md")):
            raise ExtensionError("only project skills can be deleted here", 404)
        shutil.rmtree(target)
        return {"deleted": name}

    # ---------------------------------------------------------------------- MCP
    def _codex_config(self) -> str:
        return os.path.join(self.home, ".codex", "config.toml")

    def _raw_servers(self, workdir: str, agent_type: str) -> list[tuple[str, dict[str, Any], str, bool]]:
        """(name, spec, scope, editable)."""
        fam = family(agent_type)
        out: list[tuple[str, dict[str, Any], str, bool]] = []
        if fam in ("claude", "any"):
            project = self._read_json(os.path.join(workdir, ".mcp.json")).get("mcpServers")
            for n, spec in (project or {}).items():
                if isinstance(spec, dict):
                    out.append((n, spec, "project", True))
            user = self._read_json(os.path.join(self.home, ".claude.json"))
            local = ((user.get("projects") or {}).get(workdir) or {}).get("mcpServers") if isinstance(user.get("projects"), dict) else None
            for scope, table in (("local", local), ("user", user.get("mcpServers"))):
                for n, spec in (table or {}).items():
                    if isinstance(spec, dict):
                        out.append((n, spec, scope, False))
        if fam in ("codex", "any"):
            try:
                with open(self._codex_config(), "rb") as fh:
                    table = tomllib.load(fh).get("mcp_servers") or {}
            except (OSError, tomllib.TOMLDecodeError):
                table = {}
            for n, spec in table.items():
                if isinstance(spec, dict):
                    out.append((n, spec, "user", fam == "codex"))
        return out

    @staticmethod
    def _kind(spec: Mapping[str, Any]) -> str:
        t = str(spec.get("type") or spec.get("transport") or "").lower()
        if t in ("http", "streamable-http", "sse"):
            return "sse" if t == "sse" else "http"
        return "http" if spec.get("url") and not spec.get("command") else "stdio"

    def servers(self, workdir: str, agent_type: str, project: str) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        seen: set[str] = set()
        for name, spec, scope, editable in self._raw_servers(workdir, agent_type):
            if name in seen:
                continue
            seen.add(name)
            kind = self._kind(spec)
            if kind == "stdio":
                target = " ".join([str(spec.get("command") or "")] + [str(a) for a in spec.get("args") or []]).strip()
            else:
                target = str(spec.get("url") or "").split("?", 1)[0]
            secrets = sorted({*(spec.get("env") or {}).keys(), *(spec.get("headers") or {}).keys(), *(spec.get("http_headers") or {}).keys()})
            with self._lock:
                tools = self._tools.get((project, name), [])
            out.append({
                "name": name,
                "status": "configured" if spec.get("enabled", True) is not False else "disabled",
                "kind": kind,
                "enabled": spec.get("enabled", True) is not False,
                "scope": scope,
                "target": target[:300],
                "secret_keys": secrets,
                "editable": editable and self.write,
                "tools": [t["name"] for t in tools],
                "description": f"{scope} · {target[:120]}" if target else scope,
            })
        return out

    @staticmethod
    def _spec_from(body: Mapping[str, Any]) -> tuple[str, dict[str, Any]]:
        name = str(body.get("name") or "").strip()
        if not NAME_RE.match(name):
            raise ExtensionError("server name: letters, digits, '_', '-', '.'")
        kind = str(body.get("kind") or "stdio").lower()
        def str_map(key: str) -> dict[str, str]:
            raw = body.get(key) or {}
            if not isinstance(raw, Mapping):
                raise ExtensionError(f"{key} must be an object")
            return {str(k): str(v) for k, v in raw.items() if str(k).strip()}
        if kind == "stdio":
            command = str(body.get("command") or "").strip()
            args = body.get("args") or []
            if not command or not isinstance(args, list):
                raise ExtensionError("command is required")
            spec: dict[str, Any] = {"command": command, "args": [str(a) for a in args]}
            env = str_map("env")
            if env:
                spec["env"] = env
        elif kind in ("http", "sse"):
            url = str(body.get("url") or "").strip()
            if not url.startswith(("https://", "http://")):
                raise ExtensionError("url must start with http(s)://")
            spec = {"type": kind, "url": url}
            headers = str_map("headers")
            if headers:
                spec["headers"] = headers
        else:
            raise ExtensionError("kind must be stdio, http or sse")
        return name, spec

    def add_server(self, workdir: str, agent_type: str, body: Mapping[str, Any]) -> dict[str, Any]:
        self._require_write()
        name, spec = self._spec_from(body)
        if any(n == name for n, *_ in self._raw_servers(workdir, agent_type)):
            raise ExtensionError("a server with this name already exists", 409)
        if family(agent_type) == "codex":
            self._codex_append(name, spec)
            return {"name": name, "file": self._display(self._codex_config())}
        path = os.path.join(workdir, ".mcp.json")
        data = self._read_json(path)
        servers = data.setdefault("mcpServers", {})
        if not isinstance(servers, dict):
            raise ExtensionError(".mcp.json has an unexpected shape", 409)
        servers[name] = spec
        self._write_json(path, data)
        return {"name": name, "file": self._display(path)}

    def remove_server(self, workdir: str, agent_type: str, project: str, name: str) -> dict[str, Any]:
        self._require_write()
        if family(agent_type) == "codex":
            if not self._codex_remove(name):
                raise ExtensionError("server not found in ~/.codex/config.toml", 404)
        else:
            path = os.path.join(workdir, ".mcp.json")
            data = self._read_json(path)
            servers = data.get("mcpServers")
            if not isinstance(servers, dict) or name not in servers:
                raise ExtensionError("only servers in the project's .mcp.json can be removed here", 404)
            del servers[name]
            self._write_json(path, data)
        with self._lock:
            self._tools.pop((project, name), None)
        return {"removed": name}

    @staticmethod
    def _write_json(path: str, data: Mapping[str, Any]) -> None:
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        os.replace(tmp, path)

    @staticmethod
    def _toml_str(v: str) -> str:
        return json.dumps(v, ensure_ascii=False)

    def _codex_append(self, name: str, spec: Mapping[str, Any]) -> None:
        lines = ["", f"[mcp_servers.{self._toml_key(name)}]"]
        if "command" in spec:
            lines.append(f"command = {self._toml_str(spec['command'])}")
            lines.append("args = [" + ", ".join(self._toml_str(a) for a in spec.get("args", [])) + "]")
        else:
            lines.append(f"url = {self._toml_str(spec['url'])}")
        for table, key in (("env", "env"), ("http_headers", "headers")):
            values = spec.get(key) or {}
            if values:
                lines.append(f"[mcp_servers.{self._toml_key(name)}.{table}]")
                lines += [f"{self._toml_key(k)} = {self._toml_str(v)}" for k, v in values.items()]
        path = self._codex_config()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")

    @staticmethod
    def _toml_key(k: str) -> str:
        return k if re.match(r"^[A-Za-z0-9_-]+$", k) else json.dumps(k)

    def _codex_remove(self, name: str) -> bool:
        path = self._codex_config()
        try:
            with open(path, encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError:
            return False
        key = self._toml_key(name)
        own = re.compile(r"^\s*\[mcp_servers\." + re.escape(key) + r"(\.[^\]]+)?\]\s*$")
        header = re.compile(r"^\s*\[")
        out: list[str] = []
        skipping = removed = False
        for line in lines:
            if header.match(line):
                skipping = bool(own.match(line))
                removed = removed or skipping
            if not skipping:
                out.append(line)
        if removed:
            with open(path + ".tmp", "w", encoding="utf-8") as fh:
                fh.write("\n".join(out).rstrip() + "\n")
            os.replace(path + ".tmp", path)
        return removed

    # -------------------------------------------------------------------- probe
    def probe(self, workdir: str, agent_type: str, project: str, name: str) -> dict[str, Any]:
        self._require_write()
        spec = next((s for n, s, *_ in self._raw_servers(workdir, agent_type) if n == name), None)
        if spec is None:
            raise ExtensionError("server not found", 404)
        kind = self._kind(spec)
        tools = self._probe_stdio(workdir, spec) if kind == "stdio" else self._probe_http(spec)
        with self._lock:
            self._tools[(project, name)] = tools
        return {"name": name, "tools": tools}

    @staticmethod
    def _rpc(i: int, method: str, params: Mapping[str, Any] | None = None) -> dict[str, Any]:
        msg: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if i:
            msg["id"] = i
        if params is not None:
            msg["params"] = dict(params)
        return msg

    def _init_params(self) -> dict[str, Any]:
        return {"protocolVersion": MCP_PROTOCOL, "capabilities": {}, "clientInfo": {"name": "huanhermes-host", "version": "0.5"}}

    @staticmethod
    def _tool_list(result: Any) -> list[dict[str, str]]:
        items = (result or {}).get("tools") if isinstance(result, dict) else None
        return [{"name": str(t.get("name")), "description": str(t.get("description") or "")[:300]}
                for t in items or [] if isinstance(t, dict) and t.get("name")][:200]

    def _probe_stdio(self, workdir: str, spec: Mapping[str, Any]) -> list[dict[str, str]]:
        cmd = [str(spec.get("command"))] + [str(a) for a in spec.get("args") or []]
        env = dict(os.environ, **{str(k): str(v) for k, v in (spec.get("env") or {}).items()})
        try:
            proc = subprocess.Popen(cmd, cwd=workdir if os.path.isdir(workdir) else None, env=env,
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError as exc:
            raise ExtensionError(f"cannot start {cmd[0]}: {exc.strerror or exc}", 502) from exc
        deadline = time.monotonic() + PROBE_TIMEOUT
        buf = b""

        def send(msg: Mapping[str, Any]) -> None:
            assert proc.stdin is not None
            proc.stdin.write((json.dumps(msg) + "\n").encode())
            proc.stdin.flush()

        def wait_for(i: int) -> Any:
            nonlocal buf
            assert proc.stdout is not None
            while time.monotonic() < deadline:
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    try:
                        msg = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(msg, dict) and msg.get("id") == i:
                        if "error" in msg:
                            raise ExtensionError(f"server error: {str(msg['error'])[:200]}", 502)
                        return msg.get("result")
                ready, _, _ = select.select([proc.stdout], [], [], max(0.0, deadline - time.monotonic()))
                if not ready:
                    break
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    raise ExtensionError("server exited before answering", 502)
                buf += chunk
            raise ExtensionError("server did not answer in time", 504)

        try:
            send(self._rpc(1, "initialize", self._init_params()))
            wait_for(1)
            send(self._rpc(0, "notifications/initialized"))
            send(self._rpc(2, "tools/list", {}))
            return self._tool_list(wait_for(2))
        except (BrokenPipeError, OSError) as exc:
            raise ExtensionError("server closed its input", 502) from exc
        finally:
            proc.kill()
            proc.wait(timeout=5)
            for stream in (proc.stdin, proc.stdout):
                if stream is not None:
                    stream.close()

    def _probe_http(self, spec: Mapping[str, Any]) -> list[dict[str, str]]:
        url = str(spec.get("url"))
        headers = {str(k): str(v) for k, v in {**(spec.get("headers") or {}), **(spec.get("http_headers") or {})}.items()}
        session: dict[str, str] = {}

        def call(msg: Mapping[str, Any]) -> Any:
            h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                 "MCP-Protocol-Version": MCP_PROTOCOL, **headers, **session}
            req = urllib.request.Request(url, data=json.dumps(msg).encode(), headers=h, method="POST")
            try:
                with urllib.request.urlopen(req, timeout=PROBE_TIMEOUT) as resp:
                    sid = resp.headers.get("Mcp-Session-Id")
                    if sid:
                        session["Mcp-Session-Id"] = sid
                    raw = resp.read(2 * 1024 * 1024).decode("utf-8", "replace")
            except urllib.error.HTTPError as exc:
                raise ExtensionError("server needs sign-in (401)" if exc.code == 401 else f"server answered HTTP {exc.code}", 502) from exc
            except (urllib.error.URLError, OSError) as exc:
                raise ExtensionError(f"cannot reach server: {getattr(exc, 'reason', exc)}", 502) from exc
            if "id" not in msg:
                return None
            payloads = [raw] if raw.lstrip().startswith("{") else [l[5:].strip() for l in raw.splitlines() if l.startswith("data:")]
            for p in payloads:
                try:
                    obj = json.loads(p)
                except ValueError:
                    continue
                if isinstance(obj, dict) and obj.get("id") == msg["id"]:
                    if "error" in obj:
                        raise ExtensionError(f"server error: {str(obj['error'])[:200]}", 502)
                    return obj.get("result")
            raise ExtensionError("server sent no answer", 502)

        call(self._rpc(1, "initialize", self._init_params()))
        try:
            call(self._rpc(0, "notifications/initialized"))
        except ExtensionError:
            pass
        return self._tool_list(call(self._rpc(2, "tools/list", {})))
