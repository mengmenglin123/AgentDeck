from __future__ import annotations

import json
import os
import tempfile
import unittest

from push_notifier import PushNotifier, valid_endpoint


class TestPushNotifier(unittest.TestCase):
    def setUp(self) -> None:
        self.sent: list[tuple[str, bytes]] = []
        self.status = 200
        self.now = 100.0
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "push.json")

    def tearDown(self) -> None:
        self.dir.cleanup()

    def notifier(self) -> PushNotifier:
        def sender(url: str, body: bytes) -> int:
            self.sent.append((url, body))
            return self.status
        return PushNotifier(self.path, sender=sender, clock=lambda: self.now, async_send=False)

    def perm(self, sk: str = "s1") -> dict:
        return {"type": "buttons", "session_key": sk, "content": "Run rm -rf token=abc",
                "buttons": [[{"text": "Allow", "data": "perm:x:allow"}]]}

    def test_register_validates_and_persists(self) -> None:
        n = self.notifier()
        self.assertFalse(n.register("d1", "ftp://x"))
        self.assertFalse(n.register("", "https://ntfy.sh/up1"))
        self.assertFalse(n.register("d1", "https://user:pw@ntfy.sh/up"))
        self.assertTrue(n.register("d1", "https://ntfy.sh/up1"))
        self.assertTrue(self.notifier().registered("d1"))
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)

    def test_permission_wakes_devices_with_reference_only(self) -> None:
        n = self.notifier()
        n.register("d1", "https://ntfy.sh/up1")
        n.observe({"type": "reply", "session_key": "s1", "content": "hi"})
        n.observe({"type": "buttons", "session_key": "s1", "buttons": [[{"text": "Yes", "data": "choice:1"}]]})
        self.assertEqual(self.sent, [])
        n.observe(self.perm())
        self.assertEqual(len(self.sent), 1)
        payload = json.loads(self.sent[0][1])
        self.assertEqual(payload["type"], "approval")
        self.assertNotIn("abc", self.sent[0][1].decode())
        self.assertNotIn("rm", self.sent[0][1].decode())

    def test_rate_limit_per_session_and_gone_endpoint(self) -> None:
        n = self.notifier()
        n.register("d1", "https://ntfy.sh/up1")
        n.observe(self.perm()); n.observe(self.perm())
        self.assertEqual(len(self.sent), 1)
        n.observe(self.perm("s2"))
        self.assertEqual(len(self.sent), 2)
        self.now += 11
        self.status = 410
        n.observe(self.perm())
        self.assertFalse(n.registered("d1"))

    def test_valid_endpoint(self) -> None:
        self.assertTrue(valid_endpoint("http://192.168.1.2:8080/upX"))
        self.assertFalse(valid_endpoint("javascript:alert(1)"))
        self.assertFalse(valid_endpoint(None))


if __name__ == "__main__":
    unittest.main()
