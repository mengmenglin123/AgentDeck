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


def _lan_address() -> str:
    import socket
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))  # TEST-NET: no packet is sent for UDP connect
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def pairing_link(config: ProductionHostConfig, code: str, host: str | None = None) -> str:
    from urllib.parse import urlencode
    import socket
    advertised = host or (config.bridge_host if config.bridge_host not in {"0.0.0.0", "::", "127.0.0.1", "::1", "localhost"} else _lan_address())
    query = {"host": advertised, "bridge": config.bridge_port, "mgmt": config.mgmt_port, "tls": 0,
             "code": code, "name": socket.gethostname()[:40]}
    return "huanhermes://connect?" + urlencode(query)


def pair_main(argv: Sequence[str]) -> int:
    from device_tokens import DeviceTokenStore
    from production_host_factory import device_store_path
    import shutil
    import subprocess
    parser = argparse.ArgumentParser(prog="production_host.py pair", description="Mint a one-time pairing code for the App")
    parser.add_argument("--config", required=True)
    parser.add_argument("--host", help="address the phone should use (default: this machine's LAN address)")
    parser.add_argument("--list", action="store_true", help="list paired devices")
    parser.add_argument("--revoke", metavar="DEVICE_ID", help="revoke one device's tokens")
    args = parser.parse_args(argv)
    try:
        config = ProductionHostConfig.load(args.config)
    except (ProductionHostConfigError, ValueError) as exc:
        print(f"Host configuration rejected: {exc}", file=sys.stderr)
        return 2
    store = DeviceTokenStore(device_store_path(config))
    if args.list:
        for d in store.list():
            print(f"{d['device_id']}\t{d['name']}")
        return 0
    if args.revoke:
        ok = store.revoke(args.revoke)
        print("revoked" if ok else "no such device")
        return 0 if ok else 1
    code = store.issue_code()
    link = pairing_link(config, code, args.host)
    print(f"配对码 / pairing code: {code}（10 分钟内有效，只能使用一次）")
    print(link)
    if shutil.which("qrencode"):
        subprocess.run(["qrencode", "-t", "ANSIUTF8", link], check=False)
    else:
        print("（安装 qrencode 可直接显示二维码；也可以把上面的链接粘贴到 App）")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "pair":
        return pair_main(argv[1:])
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
