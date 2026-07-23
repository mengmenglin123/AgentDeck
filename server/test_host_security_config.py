from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from host_security_config import HostSecurityConfig, HostSecurityConfigError


class TestHostSecurityConfig(unittest.TestCase):
    def test_parses_and_builds_durable_permission_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config = HostSecurityConfig.from_mapping({
                "permissions": {"ttl_seconds": 30, "terminal_open_required": True},
                "audit": {
                    "permission_log_path": str(Path(directory) / "permissions.jsonl"),
                    "permission_log_max_bytes": 4096,
                    "permission_log_fsync": False,
                },
            })
            gate = config.build_permission_gate()
            card = gate.issue(session_key="s1", reply_ctx=None, scope="shell", prompt="run")
            self.assertEqual(card["type"], "card")
            self.assertTrue(config.terminal_open_required)
            self.assertTrue(Path(config.permission_audit_path or "").exists())

    def test_requires_audit_path_when_building_production_gate(self) -> None:
        with self.assertRaises(HostSecurityConfigError):
            HostSecurityConfig().build_permission_gate()

    def test_rejects_invalid_values(self) -> None:
        with self.assertRaises(HostSecurityConfigError):
            HostSecurityConfig.from_mapping({"permissions": {"ttl_seconds": 0}})
        with self.assertRaises(HostSecurityConfigError):
            HostSecurityConfig.from_mapping({"audit": {"permission_log_max_bytes": 0}})
        with self.assertRaises(HostSecurityConfigError):
            HostSecurityConfig.from_mapping({"permissions": {"terminal_open_required": "yes"}})


if __name__ == "__main__":
    unittest.main()
