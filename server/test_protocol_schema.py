"""Bridge frames from the Host must match docs/protocol/schema (single source)."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from session_journal import SessionJournal, handle_resume, register_ack

ROOT = Path(__file__).resolve().parent.parent / "docs" / "protocol" / "schema"
SCHEMA = json.loads((ROOT / "bridge.v2.schema.json").read_text(encoding="utf-8"))
SAMPLES = json.loads((ROOT / "samples" / "bridge-samples.json").read_text(encoding="utf-8"))

try:
    import jsonschema
except ImportError:  # pragma: no cover - CI installs it; keep stdlib-only runs working
    jsonschema = None


def validate(direction: str, frame: dict) -> None:
    definition = SCHEMA["$defs"][direction].get(frame["type"])
    if definition is None:
        raise AssertionError(f"unknown {direction} type {frame['type']!r}")
    if jsonschema is None:
        missing = [key for key in definition.get("required", []) if key not in frame]
        if missing:
            raise AssertionError(f"{frame['type']} missing {missing}")
        return
    resolver_schema = {**definition, "$defs": SCHEMA["$defs"]}
    jsonschema.Draft202012Validator(resolver_schema).validate(frame)


class TestProtocolSchema(unittest.TestCase):
    def test_every_sample_validates(self) -> None:
        for direction in ("host_to_app", "app_to_host"):
            for frame in SAMPLES[direction]:
                with self.subTest(direction=direction, type=frame["type"]):
                    validate(direction, frame)

    def test_unknown_samples_are_really_unknown(self) -> None:
        for frame in SAMPLES["host_to_app_unknown"]:
            self.assertNotIn(frame["type"], SCHEMA["$defs"]["host_to_app"])

    def test_every_documented_event_has_a_sample(self) -> None:
        sampled = {frame["type"] for frame in SAMPLES["host_to_app"]}
        self.assertEqual(set(SCHEMA["$defs"]["host_to_app"]) - sampled, set())

    def test_host_v2_outputs_match_schema(self) -> None:
        journal = SessionJournal()
        validate("host_to_app", register_ack(["seq", "resume"], epoch=journal.epoch))
        validate("host_to_app", register_ack(["text"], epoch=journal.epoch))
        stamped = journal.record({"type": "reply_stream", "session_key": "s", "delta": "x", "done": False})
        validate("host_to_app", stamped)
        for frame in handle_resume(journal, {"type": "resume", "session_key": "s", "after_seq": 0}):
            validate("host_to_app", frame)
        for frame in handle_resume(journal, {"type": "resume", "session_key": "s", "after_seq": 0, "epoch": "x"}):
            validate("host_to_app", frame)

    def test_schema_bad_frames_are_rejected(self) -> None:
        if jsonschema is None:
            self.skipTest("jsonschema not installed")
        with self.assertRaises(jsonschema.ValidationError):
            validate("app_to_host", {"type": "resume", "session_key": "s", "after_seq": -1})
        with self.assertRaises(jsonschema.ValidationError):
            validate("host_to_app", {"type": "run_done", "session_key": "s", "status": "exploded"})


if __name__ == "__main__":
    unittest.main()
