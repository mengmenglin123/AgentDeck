from __future__ import annotations

import hashlib
import tarfile
import unittest
from pathlib import Path


class TestCompanionBundle(unittest.TestCase):
    def test_mobile_bundle_is_pinned_and_contains_installer(self) -> None:
        bundle = (
            Path(__file__).resolve().parents[1]
            / "apps/mobile/assets/companion/huanhermes-host-0.1.204.tar.gz"
        )
        digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
        self.assertEqual(
            digest,
            "28baff5f2df0d371c4aca3770661db913e56c050759fd20ad8271c28c3bbb31a",
        )
        with tarfile.open(bundle, "r:gz") as archive:
            names = archive.getnames()
        self.assertTrue(any(name.endswith("/server/companion_installer.py") for name in names))
        self.assertTrue(any(name.endswith("/server/production_host.py") for name in names))
        self.assertFalse(any("/__pycache__/" in name for name in names))


if __name__ == "__main__":
    unittest.main()
