from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

from production_host import load_components, main


class TestProductionHostEntryPoint(unittest.TestCase):
    def test_loads_components_from_typed_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "host.toml"
            config.write_text(
                f'''[server]
bridge_host = "127.0.0.1"
bridge_port = 0
mgmt_host = "127.0.0.1"
mgmt_port = 0
default_project = "codex"

[auth]
bridge_token = "test-token"
mgmt_token = "test-mgmt-token"

[workspace]
roots = ["{root}"]

[management]
session_store_path = "{root / 'sessions.json'}"

[audit]
permission_log_path = "{root / 'audit.jsonl'}"
permission_log_fsync = false

[projects.codex]
agent_type = "codex"
command = ["{sys.executable}", "-c", "pass"]
workdir = "{root}"
''',
                encoding="utf-8",
            )
            components = load_components(str(config))
            try:
                self.assertEqual(components.config.default_project, "codex")
                self.assertEqual(components.server.port, 0)
            finally:
                components.close()

    def test_rejects_missing_config_without_traceback(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = main(["--config", "/missing/huanhermes-host.toml"])
        self.assertEqual(result, 2)
        self.assertIn("Host configuration rejected", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
