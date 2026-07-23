from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from companion_installer import (
    CompanionInstallError,
    activate,
    build_install_plan,
    install,
    render_user_service,
    write_user_service,
)


class TestCompanionInstaller(unittest.TestCase):
    def _source(self, root: str) -> Path:
        source = Path(root, "source")
        server = source / "server"
        server.mkdir(parents=True)
        server.joinpath("production_host.py").write_text("print('host')\n", encoding="utf-8")
        server.joinpath("bridge.py").write_text("VALUE = 1\n", encoding="utf-8")
        server.joinpath("test_bridge.py").write_text("raise RuntimeError\n", encoding="utf-8")
        return source

    def test_installs_atomic_release_and_can_roll_back_current_link(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = self._source(directory)
            prefix = str(Path(directory, "install"))
            first = build_install_plan(source=str(source), prefix=prefix, version="0.1.201")
            first = replace(
                first,
                service_path=str(Path(directory, "systemd/huanhermes-host.service")),
            )
            install(first)
            activate(first)
            write_user_service(first)

            self.assertTrue(Path(first.release_dir, "server/production_host.py").is_file())
            self.assertFalse(Path(first.release_dir, "server/test_bridge.py").exists())
            self.assertEqual(Path(first.current_link).resolve(), Path(first.release_dir))
            self.assertIn("production_host.py --config", Path(first.service_path).read_text())

            second = build_install_plan(source=str(source), prefix=prefix, version="0.1.202")
            install(second)
            activate(second)
            self.assertEqual(Path(second.current_link).resolve(), Path(second.release_dir))
            activate(first)
            self.assertEqual(Path(first.current_link).resolve(), Path(first.release_dir))

    def test_rejects_unsafe_source_prefix_version_and_duplicate_release(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = self._source(directory)
            prefix = str(Path(directory, "install"))
            with self.assertRaises(CompanionInstallError):
                build_install_plan(source=str(source), prefix="relative", version="v1")
            with self.assertRaises(CompanionInstallError):
                build_install_plan(source=str(source), prefix=prefix, version="../../escape")
            with self.assertRaises(CompanionInstallError):
                build_install_plan(source=directory, prefix=prefix, version="v1")

            plan = build_install_plan(source=str(source), prefix=prefix, version="v1")
            install(plan)
            with self.assertRaises(CompanionInstallError):
                install(plan)

    def test_service_never_enables_or_uses_sudo(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = self._source(directory)
            plan = build_install_plan(
                source=str(source),
                prefix=str(Path(directory, "install")),
                version="v1",
            )
            service = render_user_service(plan)
            self.assertNotIn("sudo", service)
            self.assertNotIn("systemctl", service)
            self.assertIn("Restart=on-failure", service)


if __name__ == "__main__":
    unittest.main()
