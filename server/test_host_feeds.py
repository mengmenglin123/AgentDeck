from __future__ import annotations

import json
import logging
import os
import tempfile
import unittest

import host_feeds


class TestHostFeeds(unittest.TestCase):
    def test_activity_feed_summarises_journal_events(self) -> None:
        feed = host_feeds.ActivityFeed(clock=lambda: 5.0)
        feed.observe({"type": "reply_stream", "session_key": "s", "delta": "x"})
        feed.observe({"type": "buttons", "session_key": "s", "content": "Run rm token=abc"})
        feed.observe({"type": "run_done", "session_key": "s", "status": "completed"})
        events = feed.list()
        self.assertEqual([e["kind"] for e in events], ["run.completed", "permission.requested"])
        self.assertNotIn("abc", events[1]["summary"])

    def test_combined_observer_isolates_failures(self) -> None:
        seen = []
        def boom(_e):
            raise RuntimeError
        host_feeds.combine_observers(boom, seen.append)({"type": "x"})
        self.assertEqual(seen, [{"type": "x"}])

    def test_ring_log_handler_redacts_and_filters(self) -> None:
        ring = host_feeds.RingLogHandler(capacity=3)
        log = logging.getLogger("hh.test.ring")
        log.addHandler(ring)
        log.setLevel(logging.INFO)
        log.propagate = False
        try:
            log.info("hello")
            log.warning("auth Bearer sekret")
            items = ring.list()
            self.assertEqual(items[0]["level"], "warn")
            self.assertNotIn("sekret", items[0]["message"])
            self.assertEqual([i["message"] for i in ring.list(level="info")], ["hello"])
        finally:
            log.removeHandler(ring)

    def test_audit_tail_newest_first_and_tolerant(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "a.jsonl")
            with open(path, "w") as f:
                for i in range(5):
                    f.write(json.dumps({"action": "decided", "request_id": f"r{i}", "decision": "allow", "ts": i}) + "\n")
                f.write("not json\n")
            recs = host_feeds.read_audit_tail(path, limit=2)
            self.assertEqual([r["request_id"] for r in recs], ["r4", "r3"])
            self.assertEqual(host_feeds.read_audit_tail(os.path.join(d, "missing")), [])
            self.assertEqual(host_feeds.read_audit_tail(None), [])


if __name__ == "__main__":
    unittest.main()
