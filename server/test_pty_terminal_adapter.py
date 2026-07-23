from __future__ import annotations

import sys
import time
import unittest

from production_adapter import AdapterError
from pty_terminal_adapter import PtySpec, PtyTerminalAdapter, TerminalAdapter


class TestPtyTerminalAdapter(unittest.TestCase):
    def setUp(self) -> None:
        self.adapters: list[PtyTerminalAdapter] = []

    def tearDown(self) -> None:
        for adapter in self.adapters:
            adapter.close_all()

    def adapter_for(self, script: str) -> PtyTerminalAdapter:
        adapter = PtyTerminalAdapter(
            PtySpec(command=(sys.executable, "-u", "-c", script))
        )
        self.adapters.append(adapter)
        return adapter

    @staticmethod
    def read_until(adapter: PtyTerminalAdapter, session_key: str, needle: bytes) -> bytes:
        output = b""
        deadline = time.monotonic() + 2
        while needle not in output and time.monotonic() < deadline:
            output += adapter.read_available(session_key)
            time.sleep(0.01)
        return output

    def test_implements_terminal_adapter_and_round_trips_input(self) -> None:
        adapter = self.adapter_for(
            "import sys; print('ready', flush=True); line=sys.stdin.readline(); print('got:'+line.strip(), flush=True)"
        )
        self.assertIsInstance(adapter, TerminalAdapter)
        adapter.start("term-1", workdir="/tmp", cols=80, rows=24)
        output = self.read_until(adapter, "term-1", b"ready")
        self.assertIn(b"ready", output)
        adapter.send("term-1", "hello\n")
        output += self.read_until(adapter, "term-1", b"got:hello")
        self.assertIn(b"got:hello", output)
        deadline = time.monotonic() + 2
        while adapter.exit_code("term-1") is None and time.monotonic() < deadline:
            adapter.read_available("term-1")
            time.sleep(0.01)
        self.assertEqual(adapter.exit_code("term-1"), 0)

    def test_resize_reaches_child_terminal_geometry(self) -> None:
        adapter = self.adapter_for(
            "import sys; sys.stdin.readline(); import subprocess; "
            "subprocess.run(['stty','size']); sys.stdin.readline(); subprocess.run(['stty','size'])"
        )
        adapter.start("term-1", workdir="/tmp", cols=80, rows=24)
        adapter.send("term-1", "stty size\n")
        output = self.read_until(adapter, "term-1", b"24 80")
        self.assertIn(b"24 80", output)
        adapter.resize("term-1", cols=100, rows=40)
        adapter.send("term-1", "stty size\n")
        output += self.read_until(adapter, "term-1", b"40 100")
        self.assertIn(b"40 100", output)

    def test_cancel_is_idempotent_and_reaps_process(self) -> None:
        adapter = self.adapter_for("import time; time.sleep(60)")
        adapter.start("term-1", workdir="/tmp")
        adapter.cancel("term-1", timeout=0.2)
        adapter.cancel("term-1")
        self.assertEqual(adapter.active_sessions, ())
        with self.assertRaises(AdapterError):
            adapter.send("term-1", "late")

    def test_limits_geometry_and_workdir(self) -> None:
        adapter = self.adapter_for("pass")
        with self.assertRaises(AdapterError):
            adapter.start("term-1", workdir="relative")
        with self.assertRaises(ValueError):
            adapter.start("term-1", workdir="/tmp", cols=0)
        with self.assertRaises(ValueError):
            adapter.start("", workdir="/tmp")

    def test_reads_output_buffered_before_exit(self) -> None:
        adapter = self.adapter_for("print('final', flush=True)")
        adapter.start("term-1", workdir="/tmp")
        deadline = time.monotonic() + 2
        while adapter.exit_code("term-1") is None and time.monotonic() < deadline:
            time.sleep(0.01)
        output = self.read_until(adapter, "term-1", b"final")
        self.assertIn(b"final", output)
        self.assertEqual(adapter.exit_code("term-1"), 0)


if __name__ == "__main__":
    unittest.main()
