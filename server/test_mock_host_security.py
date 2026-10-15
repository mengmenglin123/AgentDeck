from __future__ import annotations

import contextlib
import importlib.util
import io
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "mock_host_under_test", Path(__file__).resolve().parent / "mock-host" / "mock_host.py"
)
assert _SPEC is not None and _SPEC.loader is not None
mock_host = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(mock_host)


class TestMockHostSecurity(unittest.TestCase):
    def test_token_matches_is_exact_and_fails_closed(self) -> None:
        self.assertTrue(mock_host.token_matches("dev-token", "dev-token"))
        self.assertFalse(mock_host.token_matches("dev-toke", "dev-token"))
        self.assertFalse(mock_host.token_matches("d\u00e9v-token", "dev-token"))
        self.assertFalse(mock_host.token_matches(None, "dev-token"))
        self.assertFalse(mock_host.token_matches("", ""))

    def test_log_redacts_query_and_bearer_tokens(self) -> None:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            mock_host.log('mgmt "GET /api/v1/status?token=abc123&x=1 HTTP/1.1" 200')
            mock_host.log("Authorization: Bearer sekret-value")
        output = buffer.getvalue()
        self.assertNotIn("abc123", output)
        self.assertNotIn("sekret-value", output)
        self.assertIn("token=[redacted]&x=1", output)


if __name__ == "__main__":
    unittest.main()
