from __future__ import annotations

import base64
import hashlib
import json
import socket
import sys
import threading
import time
import unittest

from agent_session_runtime import AgentSessionRuntime
from bridge_agent_loop import AgentBridgeLoop
from bridge_websocket import BridgeWebSocketServer, BridgeWebSocketTransport, WebSocketConfig
from permission_gate import PermissionGate
from production_adapter import AgentSpec, ProductionAgentAdapter
from project_router import ProjectAgentRouter
from pty_terminal_adapter import PtySpec, PtyTerminalAdapter
from terminal_bridge_loop import TerminalBridgeLoop


def client_frame(opcode: int, payload: bytes, mask: bytes = b"abcd") -> bytes:
    length = len(payload)
    header = bytearray([0x80 | opcode])
    if length < 126:
        header.append(0x80 | length)
    elif length < 1 << 16:
        header.append(0x80 | 126)
        header.extend(length.to_bytes(2, "big"))
    else:
        header.append(0x80 | 127)
        header.extend(length.to_bytes(8, "big"))
    header.extend(mask)
    header.extend(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    return bytes(header)


def read_server_frame(connection: socket.socket) -> tuple[int, bytes]:
    first, second = connection.recv(2)
    opcode = first & 0x0F
    length = second & 0x7F
    if length == 126:
        length = int.from_bytes(connection.recv(2), "big")
    elif length == 127:
        length = int.from_bytes(connection.recv(8), "big")
    payload = b""
    while len(payload) < length:
        payload += connection.recv(length - len(payload))
    return opcode, payload


class TestBridgeWebSocketTransport(unittest.TestCase):
    def setUp(self) -> None:
        self.adapters: list[ProductionAgentAdapter] = []
        self.threads: list[threading.Thread] = []

    def tearDown(self) -> None:
        for thread in self.threads:
            thread.join(timeout=2)
        for adapter in self.adapters:
            adapter.close_all()

    def transport_for(
        self,
        script: str,
        token: str = "secret",
        *,
        permission_gate: PermissionGate | None = None,
    ) -> BridgeWebSocketTransport:
        adapter = ProductionAgentAdapter(
            AgentSpec(agent_type="ws-fixture", command=(sys.executable, "-u", "-c", script))
        )
        self.adapters.append(adapter)
        runtime = AgentSessionRuntime(adapter, permission_gate=permission_gate)
        loop = AgentBridgeLoop(runtime, workdir_resolver=lambda message: "/tmp")
        return BridgeWebSocketTransport(loop, WebSocketConfig(token=token, poll_interval=0.01))

    def transport_with_terminal(
        self,
        script: str,
        *,
        permission_gate: PermissionGate | None = None,
        require_open_permission: bool = False,
    ) -> BridgeWebSocketTransport:
        transport = self.transport_for("pass")
        terminal = TerminalBridgeLoop(
            PtyTerminalAdapter(PtySpec(command=(sys.executable, "-u", "-c", script))),
            workdir_resolver=lambda message: "/tmp",
            permission_gate=permission_gate,
            require_open_permission=require_open_permission,
        )
        transport.terminal_loop = terminal
        return transport

    def run_server(self, transport: BridgeWebSocketTransport) -> socket.socket:
        server, client = socket.socketpair()
        thread = threading.Thread(target=transport.serve_connection, args=(server,), daemon=True)
        thread.start()
        self.threads.append(thread)
        client.settimeout(2)
        return client

    @staticmethod
    def handshake(client: socket.socket, *, token: str | None = "secret", header: str = "") -> bytes:
        key = base64.b64encode(b"0123456789abcdef").decode()
        target = "/bridge/ws"
        if token is not None:
            target += "?token=" + token
        request = (
            f"GET {target} HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            f"{header}"
            "\r\n"
        ).encode()
        client.sendall(request)
        response = b""
        while b"\r\n\r\n" not in response:
            response += client.recv(4096)
        return response

    def test_threaded_server_listens_and_shuts_down(self) -> None:
        transport = self.transport_for("pass")
        server = BridgeWebSocketServer(transport, host="127.0.0.1", port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.assertTrue(server.wait_until_ready())
        self.assertIsNotNone(server.address)
        host, port = server.address or ("127.0.0.1", 0)
        client = socket.create_connection((host, port), timeout=2)
        client.settimeout(2)
        self.assertIn(b"101 Switching Protocols", self.handshake(client))
        client.sendall(client_frame(0x1, b'{"type":"register"}'))
        self.assertTrue(json.loads(read_server_frame(client)[1])["ok"])
        server.shutdown()
        thread.join(timeout=2)
        self.assertFalse(thread.is_alive())
        client.close()

    def test_terminal_frames_use_real_pty_and_stream_identity(self) -> None:
        transport = self.transport_with_terminal(
            "import sys; print('ready', flush=True); line=sys.stdin.readline(); print('got:'+line.strip(), flush=True)"
        )
        client = self.run_server(transport)
        self.assertIn(b"101 Switching Protocols", self.handshake(client))
        client.sendall(client_frame(0x1, b'{"type":"register"}'))
        self.assertTrue(json.loads(read_server_frame(client)[1])["ok"])
        client.sendall(client_frame(0x1, json.dumps({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1", "cols": 80, "rows": 24,
        }).encode()))
        ack = json.loads(read_server_frame(client)[1])
        self.assertEqual((ack["type"], ack["stream_id"], ack["ok"]), ("terminal_open_ack", "t1", True))
        received: list[dict] = []
        deadline = time.monotonic() + 2
        while not any("ready" in event.get("data", "") for event in received) and time.monotonic() < deadline:
            received.append(json.loads(read_server_frame(client)[1]))
        client.sendall(client_frame(0x1, json.dumps({
            "type": "terminal_input", "session_key": "s1", "stream_id": "t1", "data": "hello\n",
        }).encode()))
        deadline = time.monotonic() + 2
        while not any(event.get("type") == "terminal_exit" for event in received) and time.monotonic() < deadline:
            received.append(json.loads(read_server_frame(client)[1]))
        self.assertTrue(any("got:hello" in event.get("data", "") for event in received))
        terminal_events = [event for event in received if event.get("type", "").startswith("terminal_")]
        self.assertEqual({event.get("stream_id") for event in terminal_events}, {"t1"})
        client.close()

    def test_terminal_permission_is_resolved_before_pty_open(self) -> None:
        transport = self.transport_with_terminal(
            "import time; time.sleep(60)",
            permission_gate=PermissionGate(id_factory=lambda: "perm-terminal"),
            require_open_permission=True,
        )
        client = self.run_server(transport)
        self.assertIn(b"101 Switching Protocols", self.handshake(client))
        client.sendall(client_frame(0x1, b'{"type":"register"}'))
        self.assertTrue(json.loads(read_server_frame(client)[1])["ok"])
        client.sendall(client_frame(0x1, json.dumps({
            "type": "terminal_open", "session_key": "s1", "stream_id": "t1",
        }).encode()))
        challenge = json.loads(read_server_frame(client)[1])
        self.assertEqual(challenge["type"], "terminal_permission")
        client.sendall(client_frame(0x1, json.dumps({
            "type": "terminal_permission_action",
            "session_key": "s1",
            "stream_id": "t1",
            "action": challenge["buttons"][0][0]["data"],
        }).encode()))
        opened = json.loads(read_server_frame(client)[1])
        self.assertEqual((opened["type"], opened["ok"]), ("terminal_open_ack", True))
        client.close()

    def test_second_connection_cannot_input_resize_or_close_terminal(self) -> None:
        transport = self.transport_with_terminal("import time; time.sleep(60)")
        client_one = self.run_server(transport)
        client_two = self.run_server(transport)
        for client in (client_one, client_two):
            self.assertIn(b"101 Switching Protocols", self.handshake(client))
            client.sendall(client_frame(0x1, b'{"type":"register"}'))
            self.assertTrue(json.loads(read_server_frame(client)[1])["ok"])
        client_one.sendall(client_frame(0x1, json.dumps({
            "type": "terminal_open", "session_key": "term-owned", "stream_id": "stream-owned",
        }).encode()))
        self.assertTrue(json.loads(read_server_frame(client_one)[1])["ok"])
        for message_type in ("terminal_input", "terminal_resize", "terminal_close"):
            message = {
                "type": message_type,
                "session_key": "term-owned",
                "stream_id": "stream-owned",
            }
            if message_type == "terminal_input":
                message["data"] = "whoami\n"
            if message_type == "terminal_resize":
                message.update({"cols": 100, "rows": 40})
            client_two.sendall(client_frame(0x1, json.dumps(message).encode()))
            rejected = json.loads(read_server_frame(client_two)[1])
            self.assertEqual(rejected["error"], "terminal_stream_in_use")
        client_one.close()
        client_two.close()

    def test_authenticated_register_ping_and_agent_events(self) -> None:
        script = (
            "import json, sys; "
            "line=sys.stdin.readline().rstrip(); "
            "print(json.dumps({'type':'text_delta','text':line}), flush=True); "
            "print(json.dumps({'type':'done'}), flush=True)"
        )
        client = self.run_server(self.transport_for(script))
        response = self.handshake(client)
        self.assertIn(b"101 Switching Protocols", response)

        client.sendall(client_frame(0x1, b'{"type":"register","platform":"test"}'))
        opcode, payload = read_server_frame(client)
        self.assertEqual(opcode, 1)
        self.assertEqual(json.loads(payload)["type"], "register_ack")

        client.sendall(client_frame(0x9, b"ping"))
        opcode, payload = read_server_frame(client)
        self.assertEqual((opcode, payload), (0xA, b"ping"))

        client.sendall(client_frame(0x1, json.dumps({
            "type": "message", "session_key": "s1", "reply_ctx": "r1", "content": "hello",
        }).encode()))
        received: list[dict] = []
        deadline = time.monotonic() + 2
        while not any(event.get("type") == "run_done" for event in received) and time.monotonic() < deadline:
            opcode, payload = read_server_frame(client)
            if opcode == 1:
                received.append(json.loads(payload))
        self.assertTrue(any(event.get("delta") == "hello" for event in received))
        self.assertEqual([event["type"] for event in received].count("run_done"), 1)
        self.assertEqual(received[0]["reply_ctx"], "r1")
        client.close()

    def test_project_router_selects_the_requested_agent_runtime(self) -> None:
        loops = {}
        for project in ("claude-code", "codex"):
            script = (
                "import json, sys; "
                "line=sys.stdin.readline().strip(); "
                f"print(json.dumps({{'type':'text_delta','text':'{project}:'+line}}), flush=True); "
                "print(json.dumps({'type':'done'}), flush=True)"
            )
            adapter = ProductionAgentAdapter(
                AgentSpec(agent_type=project, command=(sys.executable, "-u", "-c", script))
            )
            self.adapters.append(adapter)
            loops[project] = AgentBridgeLoop(
                AgentSessionRuntime(adapter),
                workdir_resolver=lambda message: "/tmp",
            )
        transport = BridgeWebSocketTransport(
            ProjectAgentRouter(loops),
            WebSocketConfig(token="secret", poll_interval=0.01),
        )
        client = self.run_server(transport)
        self.assertIn(b"101 Switching Protocols", self.handshake(client))
        client.sendall(client_frame(0x1, b'{"type":"register"}'))
        self.assertTrue(json.loads(read_server_frame(client)[1])["ok"])
        client.sendall(client_frame(0x1, json.dumps({
            "type": "message",
            "session_key": "s-project",
            "project": "codex",
            "content": "hello",
        }).encode()))
        events = []
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            event = json.loads(read_server_frame(client)[1])
            events.append(event)
            if event.get("type") == "run_done":
                break
        self.assertTrue(any(event.get("delta") == "codex:hello" for event in events))
        client.close()

    def test_rejects_wrong_token_before_upgrade(self) -> None:
        client = self.run_server(self.transport_for("pass"))
        response = self.handshake(client, token="wrong")
        self.assertIn(b"401 Unauthorized", response)
        client.close()

    def test_bearer_header_authenticates_without_query_token(self) -> None:
        client = self.run_server(self.transport_for("pass"))
        response = self.handshake(client, token=None, header="Authorization: Bearer secret\r\n")
        self.assertIn(b"101 Switching Protocols", response)
        client.close()

    def test_events_are_not_broadcast_between_connections(self) -> None:
        script = (
            "import json, sys, time; "
            "line=sys.stdin.readline().rstrip(); time.sleep(0.1); "
            "print(json.dumps({'type':'text_delta','text':line}), flush=True); "
            "print(json.dumps({'type':'done'}), flush=True)"
        )
        transport = self.transport_for(script)
        client_one = self.run_server(transport)
        client_two = self.run_server(transport)
        for client in (client_one, client_two):
            self.assertIn(b"101 Switching Protocols", self.handshake(client))
            client.sendall(client_frame(0x1, b'{"type":"register"}'))
            self.assertTrue(json.loads(read_server_frame(client)[1])["ok"])
        client_one.sendall(client_frame(0x1, json.dumps({
            "type": "message", "session_key": "one", "content": "private-one",
        }).encode()))
        first_opcode, first_payload = read_server_frame(client_one)
        self.assertEqual(first_opcode, 1)
        self.assertEqual(json.loads(first_payload).get("delta"), "private-one")
        client_two.settimeout(0.3)
        with self.assertRaises(socket.timeout):
            read_server_frame(client_two)
        client_one.close()
        client_two.close()

    def test_second_connection_cannot_take_over_agent_or_terminal_session(self) -> None:
        transport = self.transport_for("import time; time.sleep(60)")
        client_one = self.run_server(transport)
        client_two = self.run_server(transport)
        for client in (client_one, client_two):
            self.assertIn(b"101 Switching Protocols", self.handshake(client))
            client.sendall(client_frame(0x1, b'{"type":"register"}'))
            self.assertTrue(json.loads(read_server_frame(client)[1])["ok"])
        client_one.sendall(client_frame(0x1, json.dumps({
            "type": "message", "session_key": "s1", "content": "run",
        }).encode()))
        time.sleep(0.05)
        client_two.sendall(client_frame(0x1, json.dumps({
            "type": "message", "session_key": "s1", "content": "takeover",
        }).encode()))
        event = json.loads(read_server_frame(client_two)[1])
        self.assertEqual(event["error_code"], "session_in_use")
        client_one.close()
        client_two.close()

    def test_second_connection_cannot_submit_agent_card_action(self) -> None:
        script = (
            "import json, sys; "
            "print(json.dumps({'type':'permission','scope':'shell','content':'run'}), flush=True); "
            "import time; time.sleep(60)"
        )
        transport = self.transport_for(script, permission_gate=PermissionGate())
        client_one = self.run_server(transport)
        client_two = self.run_server(transport)
        for client in (client_one, client_two):
            self.assertIn(b"101 Switching Protocols", self.handshake(client))
            client.sendall(client_frame(0x1, b'{"type":"register"}'))
            self.assertTrue(json.loads(read_server_frame(client)[1])["ok"])
        client_one.sendall(client_frame(0x1, json.dumps({
            "type": "message", "session_key": "s1", "reply_ctx": "r1", "content": "run",
        }).encode()))
        card = json.loads(read_server_frame(client_one)[1])
        self.assertEqual(card["type"], "card")
        action = card["buttons"][0][0]["data"]
        client_two.sendall(client_frame(0x1, json.dumps({
            "type": "card_action", "session_key": "s1", "reply_ctx": "r1", "action": action,
        }).encode()))
        event = json.loads(read_server_frame(client_two)[1])
        self.assertEqual(event["error_code"], "session_in_use")
        client_one.close()
        client_two.close()

    def test_disconnect_only_closes_sessions_owned_by_that_connection(self) -> None:
        transport = self.transport_for("import time; time.sleep(60)")
        client_one = self.run_server(transport)
        client_two = self.run_server(transport)
        self.assertIn(b"101 Switching Protocols", self.handshake(client_one))
        self.assertIn(b"101 Switching Protocols", self.handshake(client_two))
        for client in (client_one, client_two):
            client.sendall(client_frame(0x1, b'{"type":"register"}'))
            self.assertEqual(json.loads(read_server_frame(client)[1])["ok"], True)
        for client, session_key in ((client_one, "one"), (client_two, "two")):
            client.sendall(client_frame(0x1, json.dumps({
                "type": "message", "session_key": session_key, "content": "run",
            }).encode()))
        deadline = time.monotonic() + 2
        while set(("one", "two")) - set(self.adapters[0].active_sessions) and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertEqual(set(self.adapters[0].active_sessions), {"one", "two"})
        client_one.close()
        deadline = time.monotonic() + 2
        while "one" in self.adapters[0].active_sessions and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertNotIn("one", self.adapters[0].active_sessions)
        self.assertIn("two", self.adapters[0].active_sessions)
        client_two.close()

    def test_requires_register_before_routing_message(self) -> None:
        client = self.run_server(self.transport_for("pass"))
        self.assertIn(b"101 Switching Protocols", self.handshake(client))
        client.sendall(client_frame(0x1, b'{"type":"message","session_key":"s","content":"x"}'))
        opcode, payload = read_server_frame(client)
        self.assertEqual(opcode, 1)
        self.assertEqual(json.loads(payload)["ok"], False)
        client.close()


if __name__ == "__main__":
    unittest.main()
