"""Read-only file name search for the App's `@` mentions.

Only paths are returned (never contents). Results stay inside the project
workdir: symlinks are not followed and `..` never appears in output.
"""
from __future__ import annotations

import os
import subprocess
import time
from typing import Iterable

SKIP_DIRS = frozenset({
    ".git", "node_modules", ".gradle", "build", "dist", "out", ".idea", ".venv", "venv",
    "__pycache__", ".mypy_cache", ".pytest_cache", "target", ".next", ".dart_tool", ".cache",
})
MAX_FILES = 20_000
MAX_SECONDS = 2.0
MAX_LIMIT = 100


def _git_files(root: str) -> list[str] | None:
    if not os.path.isdir(os.path.join(root, ".git")):
        return None
    try:
        out = subprocess.run(
            ["git", "-C", root, "ls-files", "-co", "--exclude-standard", "-z"],
            capture_output=True, timeout=MAX_SECONDS, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    return [p for p in out.stdout.decode("utf-8", "replace").split("\0") if p][:MAX_FILES]


def _walk_files(root: str) -> list[str]:
    files: list[str] = []
    deadline = time.monotonic() + MAX_SECONDS
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.startswith("."))
        rel_dir = os.path.relpath(dirpath, root)
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                continue
            files.append(name if rel_dir == "." else os.path.join(rel_dir, name).replace(os.sep, "/"))
            if len(files) >= MAX_FILES or time.monotonic() > deadline:
                return files
    return files


def list_files(root: str) -> list[str]:
    root = os.path.realpath(root)
    if not os.path.isdir(root):
        return []
    files = _git_files(root)
    if files is None:
        files = _walk_files(root)
    return [f for f in files if not f.startswith("../") and "/../" not in f and not os.path.isabs(f)]


def _score(path: str, q: str) -> int | None:
    p = path.lower()
    base = p.rsplit("/", 1)[-1]
    if not q:
        return 1000 + path.count("/") * 10 + len(path)
    if base == q:
        return 0
    if base.startswith(q):
        return 100 + len(base)
    if q in base:
        return 200 + base.index(q) + len(base)
    if q in p:
        return 400 + p.index(q) + len(p)
    # Subsequence on the whole path ("mgcl" -> MgmtClient).
    i = 0
    for ch in p:
        if i < len(q) and ch == q[i]:
            i += 1
    return 800 + len(p) if i == len(q) else None


def rank(files: Iterable[str], query: str, limit: int = 30) -> list[str]:
    q = query.strip().lower().lstrip("@").lstrip("./")
    limit = max(1, min(int(limit), MAX_LIMIT))
    scored = [(s, f) for f in files if (s := _score(f, q)) is not None]
    scored.sort(key=lambda x: (x[0], x[1].count("/"), x[1]))
    return [f for _, f in scored[:limit]]


def search(root: str, query: str, limit: int = 30) -> list[dict[str, str]]:
    return [{"path": p, "type": "file"} for p in rank(list_files(root), query, limit)]
