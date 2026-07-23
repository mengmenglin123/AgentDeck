from __future__ import annotations

import json
import unittest

from jsonl_agent_driver import DriverConfig, JsonlAgentDriver


class TestJsonlAgentDriver(unittest.TestCase):
    def test_buffers_partial_lines_and_injects_host_context(self) -> None:
        driver = JsonlAgentDriver("host-session", reply_ctx="host-reply")
        prefix = '{"type":"text_delta","text":"你'.encode()
        self.assertEqual(driver.feed(prefix), [])
        events = driver.feed('好"}\n'.encode())
        self.assertEqual(
            events,
            [{
                "type": "reply_stream",
                "session_key": "host-session",
                "reply_ctx": "host-reply",
                "delta": "你好",
                "done": False,
            }],
        )

    def test_agent_cannot_override_identity(self) -> None:
        driver = JsonlAgentDriver("trusted", reply_ctx="trusted-reply")
        event = driver.feed(
            b'{"type":"done","session_key":"evil","reply_ctx":"evil","status":"ok"}\n'
        )[0]
        self.assertEqual(event["session_key"], "trusted")
        self.assertEqual(event["reply_ctx"], "trusted-reply")
        self.assertEqual(event["type"], "run_done")

    def test_maps_supported_events(self) -> None:
        driver = JsonlAgentDriver("s")
        payloads = [
            {"type": "thinking", "text": "plan"},
            {"type": "tool_call", "name": "shell", "input": "pwd"},
            {"type": "tool_result", "name": "shell", "output": "/tmp"},
            {"type": "permission", "prompt": "allow?", "buttons": [[{"text": "allow"}]]},
            {"type": "error", "message": "failed"},
        ]
        events = driver.feed(b"".join(json.dumps(item).encode() + b"\n" for item in payloads))
        self.assertEqual([event["type"] for event in events], [
            "thinking", "tool_call", "tool_result", "buttons", "reply",
        ])
        self.assertTrue(events[-1]["error"])
        self.assertEqual(events[3]["buttons"][0][0]["text"], "allow")

    def test_malformed_and_unsupported_lines_are_structured(self) -> None:
        driver = JsonlAgentDriver("s")
        events = driver.feed(b"not-json\n{}\n{\"type\":\"nope\"}\n[]\n")
        self.assertEqual([event["error_code"] for event in events], [
            "malformed_json", "missing_type", "unsupported_event", "event_not_object",
        ])
        self.assertEqual(events[0]["line"], 1)
        self.assertEqual(events[0]["session_key"], "s")

    def test_limits_line_and_unterminated_buffer(self) -> None:
        driver = JsonlAgentDriver("s", config=DriverConfig(max_line_bytes=16, max_buffer_bytes=32))
        self.assertEqual(driver.feed(b"x" * 17 + b"\n")[0]["error_code"], "line_too_large")
        self.assertEqual(driver.feed(b"x" * 33)[0]["error_code"], "buffer_too_large")
        self.assertEqual(driver.finish(), [])

    def test_finish_flushes_unterminated_json_line(self) -> None:
        driver = JsonlAgentDriver("s")
        self.assertEqual(driver.feed(b'{"type":"done"}'), [])
        self.assertEqual(driver.finish()[0]["type"], "run_done")
        self.assertEqual(driver.finish(), [])

    def test_rejects_invalid_config_and_closed_feed(self) -> None:
        with self.assertRaises(ValueError):
            DriverConfig(max_line_bytes=10, max_buffer_bytes=9)
        driver = JsonlAgentDriver("s")
        driver.finish()
        with self.assertRaises(RuntimeError):
            driver.feed(b"{}")


if __name__ == "__main__":
    unittest.main()
