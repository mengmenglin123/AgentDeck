from __future__ import annotations

import json
import os
import tempfile
import unittest
import urllib.error
import urllib.request

from device_tokens import DeviceTokenStore, normalize_code
from production_host_config import ProjectRuntimeConfig
from production_management import ProductionManagementServer
from session_store import ProjectSessionStore

_DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class TestDeviceTokens(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "devices.json")
        self.now = 1000.0
        self.store = DeviceTokenStore(self.path, clock=lambda: self.now)

    def tearDown(self) -> None:
        self.dir.cleanup()

    def test_code_is_single_use_and_tokens_hashed(self) -> None:
        code = self.store.issue_code()
        tokens = self.store.claim(code.lower()[:4] + "-" + code.lower()[4:], "dev1", "Pixel")
        self.assertIsNotNone(tokens)
        self.assertIsNone(self.store.claim(code, "dev2"))
        raw = open(self.path).read()
        self.assertNotIn(tokens["bridge_token"], raw)
        self.assertNotIn(code, raw)
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)
        self.assertEqual(self.store.check(tokens["bridge_token"], "bridge"), "dev1")
        self.assertIsNone(self.store.check(tokens["bridge_token"], "mgmt"))
        # A second process (the CLI) sees the same devices.
        self.assertEqual(DeviceTokenStore(self.path).check(tokens["mgmt_token"], "mgmt"), "dev1")
        self.assertTrue(self.store.revoke("dev1"))
        self.assertIsNone(self.store.check(tokens["mgmt_token"], "mgmt"))

    def test_expiry_and_rate_limit(self) -> None:
        code = self.store.issue_code(ttl=60)
        self.now += 61
        self.assertIsNone(self.store.claim(code, "d"))
        good = self.store.issue_code()
        for _ in range(10):
            self.store.claim("WRONGCOD", "d")
        self.assertIsNone(self.store.claim(good, "d"))  # locked for a minute
        self.now += 61
        self.assertIsNotNone(self.store.claim(good, "d"))

    def test_normalize(self) -> None:
        self.assertEqual(normalize_code(" ab-cd 23 "), "ABCD23")
        self.assertEqual(normalize_code(None), "")

    def test_management_claim_and_device_auth(self) -> None:
        project = ProjectRuntimeConfig(name="p", agent_type="claudecode", command=("/bin/true",), workdir=self.dir.name)
        server = ProductionManagementServer(
            (project,), default_project="p", token="m" * 32,
            sessions=ProjectSessionStore(os.path.join(self.dir.name, "s.json"), projects=("p",)), port=0,
            devices=self.store,
        )
        server.start()
        try:
            host, port = server.address
            def call(path, method="GET", body=None, token=None):
                req = urllib.request.Request(f"http://{host}:{port}/api/v1{path}", method=method,
                    data=json.dumps(body).encode() if body is not None else None,
                    headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})})
                try:
                    with _DIRECT.open(req, timeout=5) as r:
                        return r.status, json.loads(r.read())
                except urllib.error.HTTPError as e:
                    return e.code, json.loads(e.read())
            self.assertEqual(call("/pairing/claim", "POST", {"code": "NOPE1234", "device_id": "x"})[0], 403)
            code = self.store.issue_code()
            status, payload = call("/pairing/claim", "POST", {"code": code, "device_id": "phone"})
            self.assertEqual(status, 200)
            mgmt = payload["data"]["mgmt_token"]
            self.assertEqual(call("/status", token=mgmt)[0], 200)
            self.assertIn("device_tokens", call("/status", token=mgmt)[1]["data"]["capabilities"])
            self.assertEqual(call("/devices", token=mgmt)[1]["data"]["devices"][0]["device_id"], "phone")
            self.assertEqual(call("/devices/phone", "DELETE", {}, token="m" * 32)[0], 200)
            self.assertEqual(call("/status", token=mgmt)[0], 401)
        finally:
            server.shutdown()


if __name__ == "__main__":
    unittest.main()
