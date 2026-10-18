from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import external_sessions as ext


class TestExternalSessions(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.root = base / "claude"
        self.work = base / "work" / "app"
        self.work.mkdir(parents=True)
        (base / "other").mkdir()
        d = self.root / "-work-app"
        d.mkdir(parents=True)
        lines = [
            {"type": "user", "cwd": str(self.work), "message": {"role": "user", "content": "修复登录 bug"}},
            {"type": "assistant", "cwd": str(self.work), "message": {"content": [{"type": "text", "text": "好的"}, {"type": "tool_use", "name": "Edit", "input": {}}]}},
        ]
        (d / "abc-123.jsonl").write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in lines) + "\nnot json\n")
        outside = self.root / "-other"
        outside.mkdir()
        (outside / "zzz.jsonl").write_text(json.dumps({"type": "user", "cwd": str(base / "other"), "message": {"content": "secret"}}))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_lists_only_sessions_inside_workdir(self) -> None:
        got = ext.list_sessions(str(self.work), root=self.root)
        self.assertEqual([s["id"] for s in got], ["abc-123"])
        self.assertEqual(got[0]["title"], "修复登录 bug")
        self.assertEqual(got[0]["resume_command"], "claude --resume abc-123")
        self.assertEqual(got[0]["cwd"], ".")

    def test_transcript_and_rejections(self) -> None:
        t = ext.transcript(str(self.work), "abc-123", root=self.root)
        self.assertEqual([r["role"] for r in t["transcript"]], ["user", "assistant", "tool"])
        self.assertIsNone(ext.transcript(str(self.work), "zzz", root=self.root))
        self.assertIsNone(ext.transcript(str(self.work), "../etc/passwd", root=self.root))
        self.assertEqual(ext.list_sessions(str(self.work), root=self.root / "missing"), [])


if __name__ == "__main__":
    unittest.main()
