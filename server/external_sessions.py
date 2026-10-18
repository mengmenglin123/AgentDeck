"""Read-only discovery of Claude Code CLI sessions already on this Host.

Claude Code keeps one JSONL file per session under ``~/.claude/projects/<dir>/<id>.jsonl``.
Only sessions whose recorded ``cwd`` lies inside a configured project's workdir are
shown, so the App never sees files outside the workspace allowlist. Nothing is written.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

_ID = re.compile(r"^[A-Za-z0-9_-]{1,80}$")
MAX_FILES = 400
MAX_BYTES = 8 * 1024 * 1024
MAX_ROWS = 400
MAX_TEXT = 8000


def default_root() -> Path:
    return Path(os.environ.get("HUAN_CLAUDE_PROJECTS") or Path.home() / ".claude" / "projects")


def _within(child: str, parent: str) -> bool:
    try:
        c = os.path.realpath(child)
        p = os.path.realpath(parent)
    except (OSError, ValueError):
        return False
    return c == p or c.startswith(p.rstrip(os.sep) + os.sep)


def _text_of(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        return "\n".join(p for p in parts if isinstance(p, str))
    return ""


def _iter_lines(path: Path):
    try:
        with path.open("rb") as fh:
            read = 0
            for raw in fh:
                read += len(raw)
                if read > MAX_BYTES:
                    return
                try:
                    obj = json.loads(raw)
                except (ValueError, UnicodeDecodeError):
                    continue
                if isinstance(obj, dict):
                    yield obj
    except OSError:
        return


def _summary(path: Path) -> dict[str, Any] | None:
    cwd = title = None
    messages = 0
    for obj in _iter_lines(path):
        if obj.get("type") == "summary" and isinstance(obj.get("summary"), str) and not title:
            title = obj["summary"]
        if obj.get("type") in ("user", "assistant"):
            messages += 1
            if cwd is None and isinstance(obj.get("cwd"), str):
                cwd = obj["cwd"]
            if title is None and obj.get("type") == "user":
                text = _text_of((obj.get("message") or {}).get("content")).strip()
                if text and not text.startswith("<"):
                    title = text.splitlines()[0][:80]
    if cwd is None or messages == 0:
        return None
    return {
        "id": path.stem,
        "title": title or path.stem[:8],
        "cwd": cwd,
        "messages": messages,
        "updated_at": path.stat().st_mtime,
        "resume_command": f"claude --resume {path.stem}",
    }


def list_sessions(workdir: str, root: Path | None = None, limit: int = 50) -> list[dict[str, Any]]:
    base = root or default_root()
    if not base.is_dir():
        return []
    files = sorted(base.glob("*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)[:MAX_FILES]
    out: list[dict[str, Any]] = []
    for f in files:
        if not _ID.match(f.stem):
            continue
        info = _summary(f)
        if info and _within(info["cwd"], workdir):
            info["cwd"] = os.path.relpath(os.path.realpath(info["cwd"]), os.path.realpath(workdir))
            out.append(info)
            if len(out) >= limit:
                break
    return out


def transcript(workdir: str, session_id: str, root: Path | None = None) -> dict[str, Any] | None:
    if not _ID.match(session_id or ""):
        return None
    base = root or default_root()
    matches = list(base.glob(f"*/{session_id}.jsonl")) if base.is_dir() else []
    if not matches:
        return None
    path = matches[0]
    info = _summary(path)
    if info is None or not _within(info["cwd"], workdir):
        return None
    rows: list[dict[str, Any]] = []
    for obj in _iter_lines(path):
        kind = obj.get("type")
        msg = obj.get("message") or {}
        content = msg.get("content")
        if kind == "user":
            text = _text_of(content).strip()
            if text and not text.startswith("<"):
                rows.append({"role": "user", "content": text[:MAX_TEXT]})
        elif kind == "assistant":
            text = _text_of(content).strip()
            if text:
                rows.append({"role": "assistant", "content": text[:MAX_TEXT]})
            if isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "tool_use" and isinstance(b.get("name"), str):
                        rows.append({"role": "tool", "content": b["name"]})
        if len(rows) >= MAX_ROWS:
            break
    info["cwd"] = os.path.relpath(os.path.realpath(info["cwd"]), os.path.realpath(workdir))
    return {**info, "transcript": rows}
