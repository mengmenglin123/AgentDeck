"""Command-line entry point for the production Bridge Host."""

from __future__ import annotations

import argparse
import os
import stat
import sys
from collections.abc import Sequence

from host_security_config import HostSecurityConfigError
from permission_audit_store import PermissionAuditStoreError
from production_host_config import ProductionHostConfig, ProductionHostConfigError
from production_host_factory import ProductionHostComponents, build_production_host


def load_components(config_path: str) -> ProductionHostComponents:
    return build_production_host(ProductionHostConfig.load(config_path))


def config_file_warnings(config_path: str) -> tuple[str, ...]:
    """Warn when the token-bearing config is readable by group or others."""
    try:
        mode = os.stat(config_path).st_mode
    except OSError:
        return ()
    if mode & (stat.S_IRWXG | stat.S_IRWXO):
        return (f"config file permissions are {oct(mode & 0o777)}; run chmod 600 on it",)
    return ()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the HuanHermes production Bridge Host")
    parser.add_argument("--config", required=True, help="absolute or relative Host TOML path")
    args = parser.parse_args(argv)
    try:
        components = load_components(args.config)
    except (
        HostSecurityConfigError,
        PermissionAuditStoreError,
        ProductionHostConfigError,
        ValueError,
    ) as exc:
        print(f"Host configuration rejected: {exc}", file=sys.stderr)
        return 2
    for warning in (*components.config.security_warnings(), *config_file_warnings(args.config)):
        print(f"Host security warning: {warning}", file=sys.stderr)
    try:
        components.management.start()
        components.server.serve_forever()
    except KeyboardInterrupt:
        return 0
    except OSError as exc:
        print(f"Host listener failed: {exc}", file=sys.stderr)
        return 1
    finally:
        components.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
