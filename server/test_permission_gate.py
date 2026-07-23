from __future__ import annotations

import unittest

from permission_gate import PermissionAuditRecord, PermissionGate, PermissionGateError


class TestPermissionGate(unittest.TestCase):
    def setUp(self) -> None:
        self.now = 100.0
        self.ids = iter(("p1", "p2", "p3", "p4"))
        self.audit: list[PermissionAuditRecord] = []
        self.gate = PermissionGate(
            ttl_seconds=10,
            clock=lambda: self.now,
            id_factory=lambda: next(self.ids),
            audit_sink=self.audit.append,
        )

    def test_issue_redacts_prompt_and_creates_stable_buttons(self) -> None:
        card = self.gate.issue(
            session_key="s1",
            reply_ctx="r1",
            scope="shell",
            prompt="Run with Bearer secret token=abc api_key=xyz",
        )
        self.assertEqual(card["permission_id"], "p1")
        self.assertNotIn("secret", card["content"])
        self.assertNotIn("abc", card["content"])
        self.assertEqual(card["buttons"][0][0]["data"], "perm:p1:allow")
        self.assertEqual(self.gate.pending_ids, ("p1",))
        self.assertEqual(self.audit[0].action, "permission.requested")

    def test_decision_is_bound_to_session_reply_and_one_shot(self) -> None:
        self.gate.issue(session_key="s1", reply_ctx="r1", scope="shell", prompt="run")
        with self.assertRaises(PermissionGateError):
            self.gate.decide(session_key="other", reply_ctx="r1", action="perm:p1:allow")
        with self.assertRaises(PermissionGateError):
            self.gate.decide(session_key="s1", reply_ctx="wrong", action="perm:p1:allow")
        result = self.gate.decide(session_key="s1", reply_ctx="r1", action="perm:p1:allow")
        self.assertEqual(result.decision, "allow")
        self.assertEqual(self.gate.pending_ids, ())
        with self.assertRaises(PermissionGateError):
            self.gate.decide(session_key="s1", reply_ctx="r1", action="perm:p1:allow")

    def test_expiry_rejects_old_decision_and_audits(self) -> None:
        self.gate.issue(session_key="s1", reply_ctx="r1", scope="shell", prompt="run")
        self.now = 111.0
        with self.assertRaises(PermissionGateError):
            self.gate.decide(session_key="s1", reply_ctx="r1", action="perm:p1:allow")
        self.assertEqual(self.gate.pending_ids, ())
        self.assertEqual(self.audit[-1].action, "permission.expired")

    def test_allow_all_auto_approves_same_scope_only_until_expiry(self) -> None:
        self.gate.issue(session_key="s1", reply_ctx="r1", scope="shell", prompt="run")
        result = self.gate.decide(session_key="s1", reply_ctx="r1", action="perm:p1:allow_all")
        self.assertEqual(result.decision, "allow_all")
        auto = self.gate.issue(session_key="s1", reply_ctx="r2", scope="shell", prompt="secret")
        self.assertEqual(auto.decision, "allow")
        other_scope = self.gate.issue(session_key="s1", reply_ctx="r3", scope="write", prompt="write")
        self.assertEqual(other_scope["type"], "card")
        self.now = 111.0
        expired_scope = self.gate.issue(session_key="s1", reply_ctx="r4", scope="shell", prompt="again")
        self.assertEqual(expired_scope["type"], "card")

    def test_rejects_invalid_actions_and_ids(self) -> None:
        with self.assertRaises(PermissionGateError):
            self.gate.decide(session_key="s1", reply_ctx=None, action="perm:p1:allow")
        bad_gate = PermissionGate(id_factory=lambda: "bad:id")
        with self.assertRaises(PermissionGateError):
            bad_gate.issue(session_key="s1", reply_ctx=None, scope="shell", prompt="run")

    def test_audit_failure_does_not_change_pending_state(self) -> None:
        def fail(_record: PermissionAuditRecord) -> None:
            raise OSError("disk full")

        gate = PermissionGate(audit_sink=fail)
        with self.assertRaises(OSError):
            gate.issue(session_key="s1", reply_ctx=None, scope="shell", prompt="run")
        self.assertEqual(gate.pending_ids, ())

    def test_decision_is_not_consumed_when_audit_fails(self) -> None:
        calls = 0

        def fail_once(_record: PermissionAuditRecord) -> None:
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("disk full")

        gate = PermissionGate(id_factory=lambda: "p1", audit_sink=fail_once)
        gate.issue(session_key="s1", reply_ctx=None, scope="shell", prompt="run")
        with self.assertRaises(OSError):
            gate.decide(session_key="s1", reply_ctx=None, action="perm:p1:allow")
        self.assertEqual(gate.pending_ids, ("p1",))


if __name__ == "__main__":
    unittest.main()
