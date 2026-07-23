import json
import unittest

from agent_drivers import ClaudeStreamAgentDriver, CodexAgentDriver


class TestAgentDrivers(unittest.TestCase):
    def test_codex_message_and_done(self) -> None:
        driver = CodexAgentDriver("s1", reply_ctx="r1")
        rows = [
            {"type": "item.completed", "item": {"type": "agent_message", "text": "hello"}},
            {"type": "turn.completed", "usage": {}},
        ]
        data = b"".join(json.dumps(row).encode() + b"\n" for row in rows)
        events = driver.feed(data)
        self.assertEqual([event["type"] for event in events], ["reply_stream", "run_done"])
