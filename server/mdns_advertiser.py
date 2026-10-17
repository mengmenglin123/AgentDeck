"""Minimal mDNS/DNS-SD responder: advertises ``_huanhermes._tcp.local`` (M5).

Lets the App find Hosts on the LAN (Android NsdManager) without typing an IP.
Only public facts are advertised (ports, TLS flag, version, host name) — never
tokens. Pure standard library; failures (no multicast, port busy) are logged
and ignored so they can never stop the Host.
"""
from __future__ import annotations

import logging
import socket
import struct
import threading
from typing import Iterable

SERVICE = "_huanhermes._tcp.local"
GROUP = "224.0.0.251"
PORT = 5353
TTL = 120
log = logging.getLogger("huanhermes.mdns")


def _name(labels: str) -> bytes:
    out = b""
    for part in labels.rstrip(".").split("."):
        raw = part.encode("utf-8")[:63]
        out += bytes([len(raw)]) + raw
    return out + b"\0"


def _rr(name: str, rtype: int, data: bytes, ttl: int = TTL, cache_flush: bool = True) -> bytes:
    cls = 0x8001 if cache_flush else 0x0001
    return _name(name) + struct.pack("!HHIH", rtype, cls, ttl, len(data)) + data


def _txt(items: dict[str, str]) -> bytes:
    out = b""
    for k, v in items.items():
        raw = f"{k}={v}".encode("utf-8")[:255]
        out += bytes([len(raw)]) + raw
    return out or b"\0"


def read_name(packet: bytes, offset: int) -> tuple[str, int]:
    labels: list[str] = []
    jumped = False
    end = offset
    for _ in range(64):
        if offset >= len(packet):
            raise ValueError("truncated name")
        length = packet[offset]
        if length == 0:
            offset += 1
            break
        if length & 0xC0 == 0xC0:
            if offset + 1 >= len(packet):
                raise ValueError("truncated pointer")
            pointer = ((length & 0x3F) << 8) | packet[offset + 1]
            if not jumped:
                end = offset + 2
            jumped = True
            offset = pointer
            continue
        labels.append(packet[offset + 1: offset + 1 + length].decode("utf-8", "replace"))
        offset += 1 + length
    else:
        raise ValueError("name loop")
    return ".".join(labels), (end if jumped else offset)


def parse_questions(packet: bytes) -> list[tuple[str, int, bool]]:
    if len(packet) < 12:
        return []
    flags, qd = struct.unpack("!HH", packet[2:6])
    if flags & 0x8000:  # a response, not a query
        return []
    out = []
    offset = 12
    for _ in range(min(qd, 32)):
        name, offset = read_name(packet, offset)
        if offset + 4 > len(packet):
            break
        qtype, qclass = struct.unpack("!HH", packet[offset: offset + 4])
        offset += 4
        out.append((name.lower(), qtype, bool(qclass & 0x8000)))
    return out


class MdnsAdvertiser:
    def __init__(self, *, instance: str, address: str, bridge_port: int, mgmt_port: int, tls: bool = False, version: str = "") -> None:
        safe = "".join(ch for ch in instance if ch.isalnum() or ch in "-_ ")[:40] or "HuanHermes"
        self.instance = f"{safe}.{SERVICE}"
        self.hostname = "".join(ch for ch in safe.lower().replace(" ", "-") if ch.isalnum() or ch == "-") + "-hh.local"
        self.address = address
        self.bridge_port = bridge_port
        self.txt = {"bridge": str(bridge_port), "mgmt": str(mgmt_port), "tls": "1" if tls else "0", "v": "1"}
        if version:
            self.txt["ver"] = version[:32]
        self._sock: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    def records(self) -> bytes:
        try:
            a = socket.inet_aton(self.address)
        except OSError:
            a = b""
        srv = struct.pack("!HHH", 0, 0, self.bridge_port) + _name(self.hostname)
        answers = [
            _rr(SERVICE, 12, _name(self.instance), cache_flush=False),
            _rr(self.instance, 33, srv),
            _rr(self.instance, 16, _txt(self.txt)),
        ]
        if a:
            answers.append(_rr(self.hostname, 1, a))
        return struct.pack("!HHHHHH", 0, 0x8400, 0, len(answers), 0, 0) + b"".join(answers)

    def wants(self, questions: Iterable[tuple[str, int, bool]]) -> bool:
        names = {SERVICE.lower(), self.instance.lower(), self.hostname.lower(), "_services._dns-sd._udp.local"}
        return any(name in names and qtype in {1, 12, 16, 33, 255} for name, qtype, _ in questions)

    def start(self) -> bool:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if hasattr(socket, "SO_REUSEPORT"):
                try:
                    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
                except OSError:
                    pass
            sock.bind(("", PORT))
            mreq = socket.inet_aton(GROUP) + socket.inet_aton(self.address if self.address != "127.0.0.1" else "0.0.0.0")
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
            sock.settimeout(1.0)
        except OSError as exc:
            log.warning("mDNS advertising disabled: %s", exc)
            return False
        self._sock = sock
        self._thread = threading.Thread(target=self._run, name="mdns", daemon=True)
        self._thread.start()
        return True

    def _run(self) -> None:
        sock = self._sock
        assert sock is not None
        for _ in range(2):  # announce
            try:
                sock.sendto(self.records(), (GROUP, PORT))
            except OSError:
                pass
        while not self._stop.is_set():
            try:
                packet, peer = sock.recvfrom(9000)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                questions = parse_questions(packet)
            except ValueError:
                continue
            if not self.wants(questions):
                continue
            try:
                unicast = peer[1] != PORT or any(qu for _, _, qu in questions)
                sock.sendto(self.records(), peer if unicast else (GROUP, PORT))
            except OSError:
                pass

    def close(self) -> None:
        self._stop.set()
        if self._sock is not None:
            try:
                goodbye = self.records()  # TTL 0 would be ideal; peers expire us after TTL anyway
                del goodbye
                self._sock.close()
            except OSError:
                pass
        if self._thread is not None:
            self._thread.join(timeout=2)
