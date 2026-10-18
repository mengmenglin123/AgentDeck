"""Small attachments from the App (``images[]`` / ``files[]``) saved into the workdir.

The Agent gets the saved paths appended to the message, so any CLI agent can read
them with its normal file tools. Files land in ``<workdir>/.huanhermes/uploads`` (a
directory with its own ``.gitignore``) and nothing outside the workdir is touched.
"""

from __future__ import annotations

import base64
import binascii
import os
import re
import time
from typing import Any, Iterable, Mapping

MAX_ITEMS = 4
MAX_ITEM_BYTES = 5 * 1024 * 1024
MAX_TOTAL_BYTES = 10 * 1024 * 1024
UPLOAD_DIR = os.path.join(".huanhermes", "uploads")
_SAFE = re.compile(r"[^A-Za-z0-9._\-\u4e00-\u9fff]+")


class UploadError(ValueError):
    pass


def _items(message: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    out: list[Mapping[str, Any]] = []
    for key in ("images", "files"):
        value = message.get(key)
        if isinstance(value, list):
            out.extend(v for v in value if isinstance(v, Mapping))
    return out


def has_attachments(message: Mapping[str, Any]) -> bool:
    return any(isinstance(i.get("data_base64"), str) and i["data_base64"] for i in _items(message))


def safe_name(name: Any, index: int, mime: Any = None) -> str:
    raw = os.path.basename(str(name or "")).strip()
    cleaned = _SAFE.sub("_", raw).strip("._")[:80]
    if not cleaned:
        ext = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "text/plain": ".txt"}.get(str(mime or ""), ".bin")
        cleaned = f"attachment-{index + 1}{ext}"
    return cleaned


def save(workdir: str, message: Mapping[str, Any], *, clock=time.time) -> list[str]:
    """Decode and write attachments; returns paths relative to ``workdir``."""
    items = [i for i in _items(message) if isinstance(i.get("data_base64"), str) and i["data_base64"]]
    if not items:
        return []
    if len(items) > MAX_ITEMS:
        raise UploadError("too many attachments")
    decoded: list[tuple[str, bytes]] = []
    total = 0
    for index, item in enumerate(items):
        try:
            data = base64.b64decode(item["data_base64"], validate=True)
        except (binascii.Error, ValueError) as exc:
            raise UploadError("attachment is not valid base64") from exc
        if len(data) > MAX_ITEM_BYTES:
            raise UploadError("attachment too large")
        total += len(data)
        if total > MAX_TOTAL_BYTES:
            raise UploadError("attachments too large")
        decoded.append((safe_name(item.get("name"), index, item.get("mime")), data))
    root = os.path.realpath(workdir)
    target = os.path.join(root, UPLOAD_DIR)
    os.makedirs(target, exist_ok=True)
    ignore = os.path.join(target, ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8") as fh:
            fh.write("*\n")
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(clock()))
    paths: list[str] = []
    for name, data in decoded:
        path = os.path.join(target, f"{stamp}-{name}")
        n = 1
        while os.path.exists(path):
            n += 1
            path = os.path.join(target, f"{stamp}-{n}-{name}")
        if not os.path.realpath(path).startswith(root + os.sep):
            raise UploadError("attachment path escapes workdir")
        with open(path, "wb") as fh:
            fh.write(data)
        paths.append(os.path.relpath(path, root))
    return paths


def annotate(content: str, paths: Iterable[str]) -> str:
    """One line, so line-oriented agent drivers still read the message whole."""
    listed = list(paths)
    if not listed:
        return content
    note = "[附件已保存到工作区: " + ", ".join(listed) + "]"
    return f"{content.rstrip()} {note}" if content.strip() else note
