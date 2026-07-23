"""Typed Host security configuration for permission handling."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from permission_audit_store import JsonlPermissionAuditStore
from permission_gate import PermissionGate


class HostSecurityConfigError(ValueError):
    """Raised when deployment security configuration is invalid."""


@dataclass(frozen=True)
class HostSecurityConfig:
    permission_ttl_seconds: float = 120.0
    permission_audit_path: str | None = None
    permission_audit_max_bytes: int = 10 * 1024 * 1024
    permission_audit_fsync: bool = True
    terminal_open_required: bool = True

    @classmethod
    def from_mapping(cls, config: Mapping[str, Any]) -> "HostSecurityConfig":
        permissions = config.get("permissions", {})
        audit = config.get("audit", {})
        if not isinstance(permissions, Mapping) or not isinstance(audit, Mapping):
            raise HostSecurityConfigError("permissions and audit must be tables")
        ttl = permissions.get("ttl_seconds", cls.permission_ttl_seconds)
        path = audit.get("permission_log_path")
        max_bytes = audit.get("permission_log_max_bytes", cls.permission_audit_max_bytes)
        fsync = audit.get("permission_log_fsync", cls.permission_audit_fsync)
        terminal_open_required = permissions.get("terminal_open_required", cls.terminal_open_required)
        if isinstance(ttl, bool) or not isinstance(ttl, (int, float)) or ttl <= 0:
            raise HostSecurityConfigError("permissions.ttl_seconds must be positive")
        if path is not None and (not isinstance(path, str) or not path):
            raise HostSecurityConfigError("audit.permission_log_path must be text")
        if isinstance(max_bytes, bool) or not isinstance(max_bytes, int) or max_bytes <= 0:
            raise HostSecurityConfigError("audit.permission_log_max_bytes must be positive")
        if not isinstance(fsync, bool):
            raise HostSecurityConfigError("audit.permission_log_fsync must be boolean")
        if not isinstance(terminal_open_required, bool):
            raise HostSecurityConfigError("permissions.terminal_open_required must be boolean")
        return cls(float(ttl), path, max_bytes, fsync, terminal_open_required)

    def build_permission_gate(self) -> PermissionGate:
        if not self.permission_audit_path:
            raise HostSecurityConfigError(
                "permission audit path is required for a production PermissionGate"
            )
        store = JsonlPermissionAuditStore(
            self.permission_audit_path,
            max_bytes=self.permission_audit_max_bytes,
            fsync=self.permission_audit_fsync,
        )
        return PermissionGate(ttl_seconds=self.permission_ttl_seconds, audit_sink=store)
