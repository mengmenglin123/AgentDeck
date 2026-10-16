"""Adapters for the stable machine-oriented output of supported CLIs."""

from __future__ import annotations

from typing import Any

from jsonl_agent_driver import JsonlAgentDriver


class CodexAgentDriver(JsonlAgentDriver):
    """Map `codex exec --json` thread events to Bridge events."""

    def _map_event(self, value: dict[str, Any], line_number: int) -> dict[str, Any]:
        event_type = value.get("type")
        if event_type in {"thread.started", "turn.started"}:
            return {"type": "agent_meta", "session_key": self.session_key}
        if event_type == "error":
            return self._error_event(str(value.get("message") or "Codex error"))
        if event_type == "turn.failed":
            error = value.get("error")
            return self._error_event(
                str(error.get("message") if isinstance(error, dict) else error or "Codex turn failed"),
                done=True,
                status="failed",
            )
        if event_type == "turn.completed":
            return self._run_done("completed")
        item = value.get("item")
        if not isinstance(item, dict):
            return self._error("missing_item", line_number)
        item_type = item.get("type")
        phase = "completed" if event_type == "item.completed" else "started"
        if item_type == "agent_message":
            return self._base_text(str(item.get("text") or ""))
        if item_type == "reasoning":
            event = self._base("thinking")
            event["content"] = str(item.get("text") or "")
            return event
        if item_type == "command_execution":
            if phase == "completed":
                event = self._base("tool_result")
                event["name"] = "command"
                event["output"] = item.get("aggregated_output", "")
                event["status"] = item.get("status", "completed")
                return event
            event = self._base("tool_call")
            event["name"] = "command"
            event["input"] = item.get("command", "")
            return event
        if item_type in {"file_change", "mcp_tool_call", "web_search", "collab_tool_call"}:
            if phase == "completed":
                event = self._base("tool_result")
                event["name"] = str(item_type)
                event["output"] = item
                return event
            event = self._base("tool_call")
            event["name"] = str(item_type)
            event["input"] = item
            return event
        if item_type == "error":
            return self._error_event(str(item.get("message") or "Codex item failed"))
        return self._error("unsupported_item", line_number, str(item_type))

    def _base_text(self, text: str) -> dict[str, Any]:
        event = self._base("reply_stream")
        event["delta"] = text
        return event

    def _error_event(
        self,
        content: str,
        *,
        done: bool = False,
        status: str = "failed",
    ) -> dict[str, Any]:
        event = self._base("reply")
        event.update({"content": content, "error": True})
        if done:
            event["status"] = status
        return event

    def _run_done(self, status: str) -> dict[str, Any]:
        event = self._base("run_done")
        event["status"] = status
        return event


class ClaudeStreamAgentDriver(JsonlAgentDriver):
    """Map Claude Code `--output-format stream-json` events to Bridge events."""

    def _map_event(self, value: dict[str, Any], line_number: int) -> dict[str, Any]:
        event_type = value.get("type")
        if event_type == "system":
            return {"type": "agent_meta", "session_key": self.session_key}
        if event_type == "assistant":
            message = value.get("message")
            blocks = message.get("content") if isinstance(message, dict) else None
            if not isinstance(blocks, list) or not blocks:
                return {"type": "agent_meta", "session_key": self.session_key}
            return self._map_content_block(blocks[0])
        if event_type == "user":
            message = value.get("message")
            blocks = message.get("content") if isinstance(message, dict) else None
            if isinstance(blocks, list):
                for block in blocks:
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        event = self._base("tool_result")
                        event["name"] = str(block.get("tool_use_id") or "tool")
                        if block.get("tool_use_id"):
                            event["call_id"] = str(block.get("tool_use_id"))
                        if block.get("is_error"):
                            event["is_error"] = True
                        event["output"] = block.get("content", "")
                        return event
            return {"type": "agent_meta", "session_key": self.session_key}
        if event_type == "result":
            subtype = str(value.get("subtype") or "success")
            if subtype != "success":
                event = self._base("reply")
                event.update({"content": str(value.get("result") or subtype), "error": True})
                return event
            return self._run_done("completed")
        return self._error("unsupported_event", line_number, str(event_type))

    def _map_content_block(self, block: Any) -> dict[str, Any]:
        if not isinstance(block, dict):
            return {"type": "agent_meta", "session_key": self.session_key}
        block_type = block.get("type")
        if block_type == "text":
            event = self._base("reply_stream")
            event["delta"] = str(block.get("text") or "")
            return event
        if block_type == "thinking":
            event = self._base("thinking")
            event["content"] = str(block.get("thinking") or block.get("text") or "")
            return event
        if block_type == "tool_use":
            event = self._base("tool_call")
            event["name"] = str(block.get("name") or "tool")
            if block.get("id"):
                # Lets clients pair the result (which only carries tool_use_id) with this call.
                event["call_id"] = str(block.get("id"))
            event["input"] = block.get("input", {})
            return event
        return {"type": "agent_meta", "session_key": self.session_key}

    def _run_done(self, status: str) -> dict[str, Any]:
        event = self._base("run_done")
        event["status"] = status
        return event


class HermesTextAgentDriver(JsonlAgentDriver):
    """Map Hermes `chat -q` line output; no private JSON dialect is assumed."""

    def _decode_line(self, line: bytes, line_number: int) -> dict[str, Any]:
        event = self._base("reply_stream")
        event["delta"] = line.decode("utf-8", errors="replace")
        return event


def build_agent_driver(
    driver: str,
    session_key: str,
    reply_ctx: str | None,
) -> JsonlAgentDriver:
    normalized = driver.strip().lower()
    if normalized in {"fixture_jsonl", "jsonl"}:
        return JsonlAgentDriver(session_key, reply_ctx=reply_ctx)
    if normalized == "codex_exec_json":
        return CodexAgentDriver(session_key, reply_ctx=reply_ctx)
    if normalized == "claude_stream_json":
        return ClaudeStreamAgentDriver(session_key, reply_ctx=reply_ctx)
    if normalized in {"hermes_text", "hermes_oneshot_text"}:
        return HermesTextAgentDriver(session_key, reply_ctx=reply_ctx)
    raise ValueError(f"unsupported agent driver: {driver}")
