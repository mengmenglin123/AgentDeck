"""Opt-in Git write actions for the App (capability ``git_write``).

Off unless the Host config sets ``[workspace] git_write = true``. Every action runs
``git -C <project workdir>`` with fixed arguments (no shell), paths are checked to
stay inside the workdir, pushes never prompt for credentials, and each call is
recorded in the activity feed.
"""

from __future__ import annotations

import os
import subprocess
from typing import Any, Iterable

TIMEOUT = 20
PUSH_TIMEOUT = 90
MAX_MESSAGE = 4000
MAX_PATHS = 200


class GitWriteError(ValueError):
    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.status = status


def _is_repo(root: str) -> bool:
    return os.path.isdir(os.path.join(root, ".git")) or os.path.isfile(os.path.join(root, ".git"))


def _run(root: str, args: list[str], timeout: int = TIMEOUT) -> str:
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="true", SSH_ASKPASS="true")
    try:
        out = subprocess.run(["git", "-C", root, *args], capture_output=True, timeout=timeout, check=False, env=env,
                             stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired as exc:
        raise GitWriteError("git timed out", 504) from exc
    except OSError as exc:
        raise GitWriteError("git is not available", 500) from exc
    text = (out.stdout + out.stderr).decode("utf-8", "replace").strip()
    if out.returncode != 0:
        raise GitWriteError(text[-600:] or f"git exited {out.returncode}", 409)
    return text[-2000:]


def _paths(root: str, paths: Any) -> list[str]:
    if not isinstance(paths, list) or not paths or len(paths) > MAX_PATHS:
        raise GitWriteError("paths must be a non-empty list")
    real_root = os.path.realpath(root)
    out: list[str] = []
    for p in paths:
        if not isinstance(p, str) or not p.strip() or p.startswith("-") or "\x00" in p:
            raise GitWriteError("invalid path")
        full = os.path.realpath(os.path.join(real_root, p))
        if full != real_root and not full.startswith(real_root + os.sep):
            raise GitWriteError("path escapes the workspace", 403)
        out.append(os.path.relpath(full, real_root))
    return out


def perform(root: str, action: str, body: dict[str, Any]) -> dict[str, Any]:
    root = os.path.realpath(root)
    if not _is_repo(root):
        raise GitWriteError("not a git repository", 404)
    if action == "stage":
        _run(root, ["add", "--", *_paths(root, body.get("paths"))])
        return {"action": "stage"}
    if action == "unstage":
        _run(root, ["reset", "-q", "HEAD", "--", *_paths(root, body.get("paths"))])
        return {"action": "unstage"}
    if action == "commit":
        msg = body.get("message")
        if not isinstance(msg, str) or not msg.strip():
            raise GitWriteError("commit message is required")
        output = _run(root, ["commit", "-m", msg.strip()[:MAX_MESSAGE]])
        head = _run(root, ["rev-parse", "--short", "HEAD"])
        return {"action": "commit", "commit": head.splitlines()[-1] if head else "", "output": output}
    if action == "push":
        output = _run(root, ["push"], timeout=PUSH_TIMEOUT)
        return {"action": "push", "output": output}
    raise GitWriteError("unknown git action", 404)


ACTIONS: Iterable[str] = ("stage", "unstage", "commit", "push")
