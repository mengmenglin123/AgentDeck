from __future__ import annotations

import hashlib
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/build_companion.sh"


def _build(out: str) -> Path:
    env = dict(os.environ, HH_COMPANION_OUT=out)
    res = subprocess.run(["bash", str(SCRIPT), "9.9.9", "2026-01-01"], env=env, capture_output=True, text=True, check=True)
    return Path(res.stdout.splitlines()[0])


class TestCompanionBundle(unittest.TestCase):
    """The native app packages the companion at build time; it must be reproducible and clean."""

    def test_bundle_is_reproducible_and_contains_installer(self) -> None:
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            first, second = _build(a), _build(b)
            self.assertEqual(hashlib.sha256(first.read_bytes()).hexdigest(), hashlib.sha256(second.read_bytes()).hexdigest())
            with tarfile.open(first, "r:gz") as archive:
                names = archive.getnames()
        self.assertTrue(all(n.startswith("huanhermes-host-9.9.9/server") for n in names))
        self.assertTrue(any(n.endswith("/server/companion_installer.py") for n in names))
        self.assertTrue(any(n.endswith("/server/production_host.py") for n in names))
        self.assertFalse(any("/__pycache__/" in n for n in names))


if __name__ == "__main__":
    unittest.main()
