import json
import unittest

from agent_drivers import (
    ClaudeStreamAgentDriver,
    CodexAgentDriver,
    HermesTextAgentDriver,
    build_agent_driver,
)


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

    def test_codex_maps_reasoning_tools_and_failed_turn(self) -> None:
        driver = CodexAgentDriver("s1", reply_ctx="r1")
        rows = [
            {"type": "item.started", "item": {"type": "reasoning", "text": "plan"}},
            {"type": "item.started", "item": {"type": "command_execution", "command": "pwd"}},
            {"type": "item.completed", "item": {"type": "command_execution", "aggregated_output": "/tmp", "status": "completed"}},
            {"type": "item.started", "item": {"type": "mcp_tool_call", "server": "tools"}},
            {"type": "item.completed", "item": {"type": "mcp_tool_call", "server": "tools"}},
            {"type": "turn.failed", "error": {"message": "rate limited"}},
        ]
        data = b"".join(json.dumps(row).encode() + b"\n" for row in rows)
        events = driver.feed(data)
        self.assertEqual([event["type"] for event in events], ["thinking", "tool_call", "tool_result", "tool_call", "tool_result", "reply"])
        self.assertEqual(events[1]["input"], "pwd")
        self.assertEqual(events[2]["output"], "/tmp")
        self.assertEqual(events[-1]["content"], "rate limited")
        self.assertEqual(events[-1]["status"], "failed")

    def test_claude_maps_text_thinking_tool_result_and_result(self) -> None:
        driver = ClaudeStreamAgentDriver("s1")
        rows = [
            {"type": "system", "subtype": "init"},
            {"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": "plan"}]}},
            {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "bash", "input": {"cmd": "pwd"}}]}},
            {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "tool-1", "content": "/tmp"}]}},
            {"type": "assistant", "message": {"content": [{"type": "text", "text": "done"}]}},
            {"type": "result", "subtype": "success"},
        ]
        events = driver.feed(b"".join(json.dumps(row).encode() + b"\n" for row in rows))
        self.assertEqual([event["type"] for event in events], ["agent_meta", "thinking", "tool_call", "tool_result", "reply_stream", "run_done"])
        self.assertEqual(events[1]["content"], "plan")
        self.assertEqual(events[2]["name"], "bash")
        self.assertEqual(events[3]["output"], "/tmp")
        self.assertEqual(events[4]["delta"], "done")

    def test_hermes_maps_plain_text_lines_without_json_assumption(self) -> None:
        driver = HermesTextAgentDriver("s1")
        events = driver.feed("hello\nworld\n".encode())
        self.assertEqual([event["delta"] for event in events], ["hello", "world"])
        self.assertTrue(all(event["type"] == "reply_stream" for event in events))

    def test_unknown_driver_fails_closed(self) -> None:
        with self.assertRaises(ValueError):
            build_agent_driver("not-a-driver", "s1", None)
