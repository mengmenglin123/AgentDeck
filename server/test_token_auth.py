from __future__ import annotations

import unittest

from token_auth import tokens_match


class TestTokensMatch(unittest.TestCase):
    def test_matches_exact_token(self) -> None:
        self.assertTrue(tokens_match("secret", "secret"))

    def test_rejects_mismatch_and_prefix(self) -> None:
        self.assertFalse(tokens_match("secre", "secret"))
        self.assertFalse(tokens_match("secret2", "secret"))

    def test_non_ascii_input_fails_closed_without_type_error(self) -> None:
        self.assertFalse(tokens_match("s\u00e9cret", "secret"))
        self.assertTrue(tokens_match("s\u00e9cret", "s\u00e9cret"))
        self.assertFalse(tokens_match("\udcff", "secret"))

    def test_rejects_non_text_and_empty_expected(self) -> None:
        self.assertFalse(tokens_match(None, "secret"))
        self.assertFalse(tokens_match(b"secret", "secret"))
        self.assertFalse(tokens_match("", ""))


if __name__ == "__main__":
    unittest.main()
