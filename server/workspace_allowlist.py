"""Canonical workspace path policy for Host process launchers."""

from __future__ import annotations

import os
from collections.abc import Callable, Iterable, Mapping
from pathlib import Path
from typing import Any


class WorkspacePolicyError(ValueError):
    """Raised when a requested workdir violates the Host workspace policy."""


WorkdirResolver = Callable[[str | None], str]
MessageWorkdirResolver = Callable[[Mapping[str, Any]], str]


class WorkspaceAllowlist:
    """Allow only existing directories below configured canonical roots."""

    def __init__(self, roots: Iterable[str]) -> None:
        canonical: list[str] = []
        for root in roots:
            if not isinstance(root, str) or not root.strip():
                raise WorkspacePolicyError("workspace root must be non-empty text")
            if "\x00" in root:
                raise WorkspacePolicyError("workspace root must not contain NUL bytes")
            path = self._canonical_directory(root, "workspace root")
            if path not in canonical:
                canonical.append(path)
        if not canonical:
            raise WorkspacePolicyError("at least one workspace root is required")
        self._roots = tuple(canonical)

    @property
    def roots(self) -> tuple[str, ...]:
        return self._roots

    def resolve(self, requested: str) -> str:
        """Return a canonical allowed directory or raise a policy error."""
        if not isinstance(requested, str) or not requested.strip():
            raise WorkspacePolicyError("workdir must be non-empty text")
        if "\x00" in requested:
            raise WorkspacePolicyError("workdir must not contain NUL bytes")
        if not os.path.isabs(requested):
            raise WorkspacePolicyError("workdir must be absolute")
        candidate = self._canonical_directory(requested, "workdir")
        if not any(self._is_within(candidate, root) for root in self._roots):
            raise WorkspacePolicyError("workdir is outside the workspace allowlist")
        return candidate

    def resolver(self, *, default: str | None = None) -> WorkdirResolver:
        """Create a resolver for a trusted Host config or adapter seam."""
        default_path = default
        if default_path is None:
            default_path = self._roots[0]
        canonical_default = self.resolve(default_path)
        return self.resolve_with_default(canonical_default)

    def message_resolver(self, *, default: str | None = None) -> MessageWorkdirResolver:
        """Create a resolver that reads optional client workdir safely."""
        canonical_default = self.resolve(default or self._roots[0])

        def resolve_message(message: Mapping[str, Any]) -> str:
            requested = message.get("workdir")
            if requested is None:
                return canonical_default
            if not isinstance(requested, str):
                raise WorkspacePolicyError("workdir must be text")
            return self.resolve(requested)

        return resolve_message

    def resolve_with_default(self, default: str) -> WorkdirResolver:
        canonical_default = self.resolve(default)

        def resolve_or_default(requested: str | None) -> str:
            if requested is None or not requested.strip():
                return canonical_default
            return self.resolve(requested)

        return resolve_or_default

    @staticmethod
    def _canonical_directory(value: str, label: str) -> str:
        try:
            path = Path(value).resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise WorkspacePolicyError(f"{label} must be an existing directory") from exc
        if not path.is_dir():
            raise WorkspacePolicyError(f"{label} must be a directory")
        return str(path)

    @staticmethod
    def _is_within(candidate: str, root: str) -> bool:
        try:
            return os.path.commonpath((candidate, root)) == root
        except ValueError:
            return False
