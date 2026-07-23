from __future__ import annotations

import sys
import time
import unittest

from production_adapter import (
    AdapterError,
    AgentAdapter,
    AgentSpec,
    ProductionAgentAdapter,
)


class TestProductionAgentAdapter(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = ProductionAgentAdapter(
            AgentSpec(
                agent_type="test-agent",
                command=(
                    sys.executable,
                    "-u",
                    "-c",
                    "import sys; print('ready', flush=True); [print(line.rstrip(), flush=True) for line in sys.stdin]",
                ),
            )
        )

    def tearDown(self) -> None:
        self.adapter.close_all()

    def test_implements_agent_adapter_protocol(self) -> None:
        self.assertIsInstance(self.adapter, AgentAdapter)

    def test_start_send_and_read_without_shell(self) -> None:
        self.adapter.start("session-1", workdir="/tmp")
        deadline = time.monotonic() + 2
        output = b""
        while b"ready\n" not in output and time.monotonic() < deadline:
            output += self.adapter.read_available("session-1")
            time.sleep(0.01)
        self.assertIn(b"ready\n", output)
        self.adapter.send("session-1", "hello\n")
        deadline = time.monotonic() + 2
        while b"hello\n" not in output and time.monotonic() < deadline:
            output += self.adapter.read_available("session-1")
            time.sleep(0.01)
        self.assertIn(b"hello\n", output)
        self.assertEqual(self.adapter.active_sessions, ("session-1",))

    def test_reads_buffered_stdout_after_process_exit(self) -> None:
        adapter = ProductionAgentAdapter(
            AgentSpec(
                agent_type="short-lived",
                command=(sys.executable, "-u", "-c", "print('final', flush=True)"),
            )
        )
        try:
            adapter.start("short", workdir="/tmp")
            deadline = time.monotonic() + 2
            while adapter.exit_code("short") is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertEqual(adapter.exit_code("short"), 0)
            self.assertEqual(adapter.read_available("short"), b"final\n")
        finally:
            adapter.close_all()

    def test_cancel_kills_process_group_and_is_idempotent(self) -> None:
        self.adapter.start(
            "session-1",
            workdir="/tmp",
        )
        self.adapter.cancel("session-1")
        self.adapter.cancel("session-1")
        self.assertEqual(self.adapter.active_sessions, ())
        with self.assertRaises(AdapterError):
            self.adapter.send("session-1", "late")

    def test_rejects_relative_workdir_and_empty_session(self) -> None:
        with self.assertRaises(AdapterError):
            self.adapter.start("session-1", workdir="relative")
        with self.assertRaises(ValueError):
            self.adapter.start("", workdir="/tmp")

    def test_session_limit(self) -> None:
        adapter = ProductionAgentAdapter(self.adapter.spec, max_sessions=1)
        try:
            adapter.start("one", workdir="/tmp")
            with self.assertRaises(AdapterError):
                adapter.start("two", workdir="/tmp")
        finally:
            adapter.close_all()


if __name__ == "__main__":
    unittest.main()
