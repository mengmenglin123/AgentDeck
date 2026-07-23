from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

from production_adapter import AgentSpec, ProductionAgentAdapter
from pty_terminal_adapter import PtySpec, PtyTerminalAdapter
from workspace_allowlist import WorkspaceAllowlist, WorkspacePolicyError


class TestWorkspaceAllowlist(unittest.TestCase):
    def test_resolves_root_and_nested_directory(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            nested = Path(root) / "project" / "src"
            nested.mkdir(parents=True)
            policy = WorkspaceAllowlist([root])
            self.assertEqual(policy.resolve(root), str(Path(root).resolve()))
            self.assertEqual(policy.resolve(str(nested)), str(nested.resolve()))
            self.assertEqual(policy.roots, (str(Path(root).resolve()),))

    def test_rejects_relative_missing_outside_and_nul_paths(self) -> None:
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as outside:
            policy = WorkspaceAllowlist([root])
            for requested in ("relative", str(Path(root) / "missing"), outside, "/tmp\x00bad"):
                with self.assertRaises(WorkspacePolicyError):
                    policy.resolve(requested)

    def test_rejects_symlink_escape(self) -> None:
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as outside:
            link = Path(root) / "escape"
            try:
                link.symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError) as exc:
                self.skipTest(f"symlink unavailable: {exc}")
            policy = WorkspaceAllowlist([root])
            with self.assertRaises(WorkspacePolicyError):
                policy.resolve(str(link))

    def test_message_resolver_uses_safe_default_and_validates_override(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            child = Path(root) / "child"
            child.mkdir()
            resolver = WorkspaceAllowlist([root]).message_resolver(default=str(child))
            self.assertEqual(resolver({}), str(child.resolve()))
            self.assertEqual(resolver({"workdir": str(child)}), str(child.resolve()))
            with self.assertRaises(WorkspacePolicyError):
                resolver({"workdir": "relative"})

    def test_production_adapter_accepts_only_allowlisted_workdir(self) -> None:
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as outside:
            policy = WorkspaceAllowlist([root])
            adapter = ProductionAgentAdapter(
                AgentSpec(
                    agent_type="guarded",
                    command=(sys.executable, "-u", "-c", "print('ok', flush=True)"),
                ),
                workdir_validator=policy.resolve,
            )
            try:
                adapter.start("allowed", workdir=root)
                with self.assertRaises(WorkspacePolicyError):
                    adapter.start("outside", workdir=outside)
            finally:
                adapter.close_all()

    def test_pty_adapter_accepts_only_allowlisted_workdir(self) -> None:
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as outside:
            policy = WorkspaceAllowlist([root])
            adapter = PtyTerminalAdapter(
                PtySpec(command=(sys.executable, "-u", "-c", "import time; time.sleep(60)")),
                workdir_validator=policy.resolve,
            )
            try:
                adapter.start("allowed", workdir=root)
                with self.assertRaises(WorkspacePolicyError):
                    adapter.start("outside", workdir=outside)
            finally:
                adapter.close_all()


if __name__ == "__main__":
    unittest.main()
