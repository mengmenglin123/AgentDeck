"""Constant-time shared-secret comparison helpers for Host listeners."""

from __future__ import annotations

import hmac


def tokens_match(presented: object, expected: str) -> bool:
    """Compare a client-presented token with the configured secret.

    ``hmac.compare_digest`` raises ``TypeError`` for ``str`` inputs that are
    not pure ASCII, which would let a crafted header crash a request handler
    instead of being rejected. Comparing UTF-8 bytes keeps the check
    constant-time for any text and fails closed for non-text input.
    """
    if not isinstance(presented, str) or not isinstance(expected, str) or not expected:
        return False
    try:
        left = presented.encode("utf-8", "surrogatepass")
        right = expected.encode("utf-8", "surrogatepass")
    except UnicodeError:
        return False
    return hmac.compare_digest(left, right)
