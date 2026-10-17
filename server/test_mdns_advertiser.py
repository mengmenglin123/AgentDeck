from __future__ import annotations

import struct
import unittest

from mdns_advertiser import SERVICE, MdnsAdvertiser, _name, parse_questions, read_name


def query(name: str, qtype: int = 12, qu: bool = False) -> bytes:
    return struct.pack("!HHHHHH", 0, 0, 1, 0, 0, 0) + _name(name) + struct.pack("!HH", qtype, 0x8001 if qu else 1)


class TestMdns(unittest.TestCase):
    def test_parse_query_and_match(self) -> None:
        adv = MdnsAdvertiser(instance="dev box", address="192.168.1.20", bridge_port=9810, mgmt_port=9820)
        qs = parse_questions(query(SERVICE))
        self.assertEqual(qs, [(SERVICE, 12, False)])
        self.assertTrue(adv.wants(qs))
        self.assertFalse(adv.wants(parse_questions(query("_other._tcp.local"))))
        self.assertTrue(parse_questions(query(SERVICE, qu=True))[0][2])

    def test_response_contains_srv_txt_a_and_no_secrets(self) -> None:
        adv = MdnsAdvertiser(instance="dev box", address="192.168.1.20", bridge_port=9810, mgmt_port=9820, version="0.2.7")
        packet = adv.records()
        flags, _, ancount = struct.unpack("!HHH", packet[2:8])
        self.assertTrue(flags & 0x8000)
        self.assertEqual(ancount, 4)
        name, _ = read_name(packet, 12)
        self.assertEqual(name, SERVICE)
        self.assertIn(b"mgmt=9820", packet)
        self.assertIn(bytes([192, 168, 1, 20]), packet)
        self.assertNotIn(b"token", packet)
        # Responses are ignored as queries.
        self.assertEqual(parse_questions(packet), [])

    def test_compression_pointer_and_garbage(self) -> None:
        base = struct.pack("!HHHHHH", 0, 0, 2, 0, 0, 0) + _name(SERVICE) + struct.pack("!HH", 12, 1)
        pointer = b"\xc0\x0c" + struct.pack("!HH", 255, 1)
        self.assertEqual([q[0] for q in parse_questions(base + pointer)], [SERVICE, SERVICE])
        with self.assertRaises(ValueError):
            parse_questions(struct.pack("!HHHHHH", 0, 0, 1, 0, 0, 0) + b"\xc0\x0c")


if __name__ == "__main__":
    unittest.main()
