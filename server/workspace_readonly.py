"""Read-only workspace browsing, git status and diff for the App (M4).

Paths are relative to the project workdir; anything resolving outside it
(``..``, absolute paths, symlinks pointing out) is refused. File content is
capped and binary files are reported, never sent.
"""
from __future__ import annotations

import os
import subprocess
from typing import Any

MAX_FILE_BYTES = 256 * 1024
MAX_DIFF_BYTES = 512 * 1024
MAX_ENTRIES = 2000
GIT_TIMEOUT = 5.0


class WorkspaceError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


def _resolve(root: str, rel: str) -> tuple[str, str]:
    root_real = os.path.realpath(root)
    cleaned = (rel or "").strip().replace("\\", "/").lstrip("/")
    while cleaned.startswith("./"):
        cleaned = cleaned[2:]
    cleaned = cleaned.rstrip("/")
    if cleaned in {"", "."}:
        return root_real, ""
    if ".." in cleaned.split("/"):
        raise WorkspaceError(400, "path escapes workspace")
    full = os.path.realpath(os.path.join(root_real, cleaned))
    if full != root_real and not full.startswith(root_real + os.sep):
        raise WorkspaceError(403, "path escapes workspace")
    return full, cleaned


def listing(root: str, rel: str = "") -> dict[str, Any]:
    full, cleaned = _resolve(root, rel)
    if not os.path.exists(full):
        raise WorkspaceError(404, "not found")
    if os.path.isfile(full):
        size = os.path.getsize(full)
        with open(full, "rb") as f:
            raw = f.read(MAX_FILE_BYTES + 1)
        binary = b"\0" in raw[:8192]
        data: dict[str, Any] = {
            "path": cleaned, "type": "file", "name": os.path.basename(full), "size": size,
            "truncated": len(raw) > MAX_FILE_BYTES, "binary": binary,
        }
        data["content"] = "" if binary else raw[:MAX_FILE_BYTES].decode("utf-8", "replace")
        return data
    entries = []
    try:
        names = sorted(os.listdir(full))
    except OSError as exc:
        raise WorkspaceError(403, "cannot list directory") from exc
    for name in names:
        if name == ".git":
            continue
        child = os.path.join(full, name)
        if os.path.islink(child):
            target = os.path.realpath(child)
            root_real = os.path.realpath(root)
            if target != root_real and not target.startswith(root_real + os.sep):
                continue
        is_dir = os.path.isdir(child)
        entry: dict[str, Any] = {"name": name, "type": "dir" if is_dir else "file"}
        if not is_dir:
            try:
                entry["size"] = os.path.getsize(child)
            except OSError:
                entry["size"] = None
        entries.append(entry)
        if len(entries) >= MAX_ENTRIES:
            break
    entries.sort(key=lambda e: (e["type"] != "dir", e["name"].lower()))
    parent = "/".join(cleaned.split("/")[:-1]) if cleaned else ""
    return {"path": cleaned, "type": "dir", "parent": parent, "entries": entries}


def _git(root: str, *args: str, limit: int = MAX_DIFF_BYTES) -> str | None:
    if not os.path.isdir(os.path.join(root, ".git")) and not os.path.isfile(os.path.join(root, ".git")):
        return None
    try:
        out = subprocess.run(["git", "-C", root, *args], capture_output=True, timeout=GIT_TIMEOUT, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    return out.stdout[:limit].decode("utf-8", "replace")


def git_status(root: str) -> dict[str, Any]:
    root = os.path.realpath(root)
    text = _git(root, "status", "--porcelain=v1", "-b", "--untracked-files=normal")
    if text is None:
        return {"branch": None, "clean": True, "files": [], "note": "not a git repository"}
    branch = None
    files = []
    for line in text.splitlines():
        if line.startswith("## "):
            branch = line[3:].split("...")[0].strip()
            continue
        if len(line) < 4:
            continue
        code = line[:2]
        path = line[3:].split(" -> ")[-1].strip().strip('"')
        status = "?" if code == "??" else (code[0] if code[0] != " " else code[1])
        files.append({"path": path, "status": status, "staged": code[0] not in {" ", "?"}})
    return {"branch": branch, "clean": not files, "files": files}


def diff(root: str, rel: str = "") -> dict[str, Any]:
    root = os.path.realpath(root)
    if rel:
        _, cleaned = _resolve(root, rel)
        body = _git(root, "diff", "HEAD", "--no-color", "--", cleaned)
        if body is None:
            body = _git(root, "diff", "--no-color", "--", cleaned) or ""
        truncated = len(body.encode("utf-8")) >= MAX_DIFF_BYTES
        if not body:
            full, _ = _resolve(root, cleaned)
            # Untracked file: show it as an all-added diff.
            if os.path.isfile(full) and _git(root, "ls-files", "--error-unmatch", "--", cleaned) is None:
                try:
                    with open(full, "rb") as f:
                        raw = f.read(MAX_FILE_BYTES)
                    if b"\0" not in raw[:8192]:
                        lines = raw.decode("utf-8", "replace").splitlines()
                        body = f"--- /dev/null\n+++ b/{cleaned}\n@@ -0,0 +1,{len(lines)} @@\n" + "".join("+" + l + "\n" for l in lines)
                except OSError:
                    body = ""
        return {"path": cleaned, "diff": body, "truncated": truncated}
    status = git_status(root)
    return {"files": [{"path": f["path"], "has_diff": True, "status": f["status"]} for f in status["files"]]}
