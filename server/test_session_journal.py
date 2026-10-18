from __future__ import annotations

import unittest

from session_journal import SessionJournal, handle_resume, negotiate, register_ack


class TestSessionJournal(unittest.TestCase):
    def test_seq_is_monotonic_per_session_and_skips_sessionless_events(self) -> None:
        journal = SessionJournal()
        a1 = journal.record({"type": "reply_stream", "session_key": "a", "delta": "x"})
        b1 = journal.record({"type": "reply_stream", "session_key": "b", "delta": "y"})
        a2 = journal.record({"type": "run_done", "session_key": "a", "seq": 99})
        pong = journal.record({"type": "pong"})
        self.assertEqual((a1["seq"], b1["seq"], a2["seq"]), (1, 1, 2))
        self.assertNotIn("seq", pong)
        self.assertEqual(journal.last_seq("a"), 2)

    def test_replay_returns_missing_events_marked_replayed(self) -> None:
        journal = SessionJournal()
        for index in range(5):
            journal.record({"type": "reply_stream", "session_key": "s", "delta": str(index)})
        replay = journal.replay("s", 3)
        self.assertEqual([event["seq"] for event in replay], [4, 5])
        self.assertTrue(all(event["replayed"] for event in replay))
        self.assertEqual(journal.replay("s", 5), [])

    def test_gap_outside_window_epoch_change_or_future_seq_require_resync(self) -> None:
        journal = SessionJournal(max_events_per_session=3)
        for index in range(6):
            journal.record({"type": "reply_stream", "session_key": "s", "delta": str(index)})
        self.assertIsNone(journal.replay("s", 1))  # oldest kept is seq 4
        self.assertEqual([e["seq"] for e in journal.replay("s", 3)], [4, 5, 6])
        self.assertIsNone(journal.replay("s", 7))
        self.assertIsNone(journal.replay("s", 5, epoch="other-host-run"))
        self.assertIsNone(journal.replay("unknown", 0) or None)

    def test_evicted_session_keeps_counter_and_forces_resync(self) -> None:
        journal = SessionJournal(max_sessions=1)
        journal.record({"type": "reply", "session_key": "a"})
        journal.record({"type": "reply", "session_key": "b"})
        self.assertIsNone(journal.replay("a", 0))
        self.assertEqual(journal.record({"type": "reply", "session_key": "a"})["seq"], 2)

    def test_handle_resume_ack_and_resync_and_validation(self) -> None:
        journal = SessionJournal()
        journal.record({"type": "reply", "session_key": "s", "content": "1"})
        journal.record({"type": "reply", "session_key": "s", "content": "2"})
        events = handle_resume(journal, {"type": "resume", "session_key": "s", "after_seq": 1})
        self.assertEqual(events[0]["content"], "2")
        self.assertEqual(events[-1], {
            "type": "resume_ack", "ok": True, "session_key": "s", "last_seq": 2,
            "replayed": 1, "epoch": journal.epoch,
        })
        resync = handle_resume(journal, {"type": "resume", "session_key": "s", "after_seq": 0, "epoch": "x"})
        self.assertEqual(resync[0]["type"], "resync_required")
        self.assertEqual(resync[0]["last_seq"], 2)
        for bad in ({"type": "resume"}, {"type": "resume", "session_key": "s", "after_seq": -1},
                    {"type": "resume", "session_key": "s", "after_seq": True}):
            self.assertEqual(handle_resume(journal, bad)[0]["error_code"], "invalid_resume")

    def test_negotiation_is_opt_in_and_legacy_ack_is_unchanged(self) -> None:
        legacy = ["text", "buttons", "typing", "preview", "terminal"]  # Flutter 0.1.206
        self.assertEqual(negotiate(legacy), ())
        self.assertEqual(register_ack(legacy, epoch="e"), {"type": "register_ack", "ok": True, "error": ""})
        self.assertEqual(register_ack(None, epoch="e"), {"type": "register_ack", "ok": True, "error": ""})
        v2 = register_ack([*legacy, "seq", "resume", "session_status", "future_thing"], epoch="e")
        self.assertEqual(negotiate(["plan_cards", "usage", "seq"]), ("seq", "plan_cards", "usage"))
        self.assertEqual(v2["protocol"], 2)
        self.assertEqual(v2["capabilities"], ["seq", "resume", "session_status"])
        self.assertEqual(v2["epoch"], "e")


if __name__ == "__main__":
    unittest.main()
