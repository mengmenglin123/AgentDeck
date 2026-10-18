package com.huanmeng.huanhermes.core.overview

import com.huanmeng.huanhermes.core.hosts.HostProfile
import com.huanmeng.huanhermes.core.mgmt.MgmtClient
import com.huanmeng.huanhermes.core.mgmt.PendingPermission
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.protocol.FrameButton
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneOffset

class OverviewTest {
    private fun s(id: String, project: String = "codex", updated: Double? = 100.0, running: Boolean = false, preview: String? = null,
                  pending: List<PendingPermission> = emptyList(), title: String? = id) =
        SessionInfo(id, "sk-$id", project, title, null, updated, running, null, null, preview = preview, pendingPermissions = pending)

    private val perm = PendingPermission("p1", "rm -rf build", "ctx", listOf(FrameButton("Allow", "perm:p1:allow")))

    @Test fun statusPriority() {
        assertEquals(SessionStatus.NeedsYou, SessionOverview.statusOf(s("a", pending = listOf(perm)), null, hostOnline = false))
        assertEquals(SessionStatus.Offline, SessionOverview.statusOf(s("a", running = true), null, hostOnline = false))
        assertEquals(SessionStatus.Running, SessionOverview.statusOf(s("a", running = true), null, true))
        assertEquals(SessionStatus.Unread, SessionOverview.statusOf(s("a", updated = 200.0), 100.0, true))
        assertEquals(SessionStatus.Idle, SessionOverview.statusOf(s("a", updated = 100.5), 100.0, true))
        // Never opened here: only a Host preview makes it unread.
        assertEquals(SessionStatus.Idle, SessionOverview.statusOf(s("a"), null, true))
        assertEquals(SessionStatus.Unread, SessionOverview.statusOf(s("a", preview = "done"), null, true))
    }

    @Test fun relativeTimeInChinese() {
        val z = ZoneOffset.UTC
        val now = LocalDateTime.of(2026, 10, 17, 12, 0).toEpochSecond(z).toDouble()
        assertEquals("刚刚", SessionOverview.relativeTime(now - 10, now, z))
        assertEquals("5 分钟前", SessionOverview.relativeTime(now - 300, now, z))
        assertEquals("3 小时前", SessionOverview.relativeTime(now - 3 * 3600, now, z))
        assertEquals("昨天", SessionOverview.relativeTime(now - 20 * 3600, now, z))
        assertEquals("3 天前", SessionOverview.relativeTime(now - 3 * 86400, now, z))
        assertEquals("9月1日", SessionOverview.relativeTime(LocalDateTime.of(2026, 9, 1, 8, 0).toEpochSecond(z).toDouble(), now, z))
        assertEquals("2025年9月1日", SessionOverview.relativeTime(LocalDateTime.of(2025, 9, 1, 8, 0).toEpochSecond(z).toDouble(), now, z))
        assertEquals("", SessionOverview.relativeTime(null, now, z))
    }

    @Test fun previewPrefersDraftThenPendingThenHostPreview() {
        assertEquals("草稿：hi there", SessionOverview.previewOf(s("a", preview = "x"), "hi\n there"))
        assertEquals("等待批准：rm -rf build", SessionOverview.previewOf(s("a", preview = "x", pending = listOf(perm)), null))
        assertEquals("x", SessionOverview.previewOf(s("a", preview = "x"), ""))
    }

    @Test fun groupingPinsArchivesAndSearches() {
        val list = listOf(s("a", "codex", 10.0), s("b", "claude", 30.0), s("c", "codex", 20.0, title = "修复登录"), s("d", "codex", 5.0))
        val prefs = LocalSessionPrefs.Snapshot(pinned = setOf("d"), archived = setOf("b"))
        val groups = SessionGrouping.group(list, prefs, hostOnline = true)
        assertEquals(listOf("置顶", "codex"), groups.map { it.title })
        assertEquals(listOf("d"), groups[0].rows.map { it.session.id })
        assertEquals(listOf("c", "a"), groups[1].rows.map { it.session.id })
        assertEquals(listOf("b"), SessionGrouping.group(list, prefs, true, showArchived = true).flatMap { it.rows }.map { it.session.id })
        assertEquals(listOf("c"), SessionGrouping.group(list, prefs, true, query = "登录").flatMap { it.rows }.map { it.session.id })
        assertEquals(1, SessionGrouping.archivedCount(list, prefs))
    }

    @Test fun needsYouSortsFirstInGroup() {
        val list = listOf(s("a", updated = 50.0), s("b", updated = 1.0, pending = listOf(perm)))
        val rows = SessionGrouping.group(list, LocalSessionPrefs.Snapshot(), true).single().rows
        assertEquals(listOf("b", "a"), rows.map { it.session.id })
    }

    @Test fun localPrefsPersistPerHostAndSurviveCorruption() = runTest {
        val storage = MemoryPrefsStorage()
        val prefs = LocalSessionPrefs(storage, clock = { 42.0 })
        prefs.load()
        prefs.setPinned("h1", "a", true)
        prefs.setArchived("h1", "b", true)
        prefs.markSeen("h1", "a")
        prefs.setDraft("h1", "a", "draft text")
        prefs.addHistory("one"); prefs.addHistory("two"); prefs.addHistory("one")
        assertEquals(setOf("a"), prefs.snapshot("h1").pinned)
        assertTrue(prefs.snapshot("h2").pinned.isEmpty())
        val again = LocalSessionPrefs(storage).apply { load() }
        assertEquals(42.0, again.snapshot("h1").lastSeen["a"]!!, 0.0)
        assertEquals("draft text", again.draft("h1", "a"))
        assertEquals(listOf("one", "two"), again.data.value.history)
        again.setArchived("h1", "a", true)
        assertFalse("archiving unpins", "a" in again.snapshot("h1").pinned)
        again.setDraft("h1", "a", "  ")
        assertEquals("", again.draft("h1", "a"))
        val broken = LocalSessionPrefs(MemoryPrefsStorage("{not json")).apply { load() }
        assertTrue(broken.data.value.pinned.isEmpty())
    }

    @Test fun inboxCollectsAcrossHostsAndReportsFailures() = runTest {
        val h1 = HostProfile("h1", "家里", HostConfig(host = "10.0.0.1", bridgeToken = "secret-bridge", mgmtToken = "secret-mgmt"))
        val h2 = HostProfile("h2", "公司", HostConfig(host = "10.0.0.2"))
        val h3 = HostProfile("h3", "旧版", HostConfig(host = "10.0.0.3"))
        val h4 = HostProfile("h4", "慢", HostConfig(host = "10.0.0.4"))
        val model = InboxModel({ p ->
            when (p.id) {
                "h1" -> listOf(s("a", pending = listOf(perm)), s("b")) to true
                "h2" -> throw IllegalStateException("refused token=secret-mgmt")
                "h3" -> listOf(s("c")) to false
                else -> { delay(60_000); emptyList<SessionInfo>() to true }
            }
        }, timeoutMs = 1_000)
        model.refresh(listOf(h1, h2, h3, h4))
        val st = model.state.value
        assertEquals(listOf("h1|a|p1"), st.visible.map { it.key })
        assertEquals(listOf("旧版"), st.unsupportedHosts.map { it.hostName })
        assertEquals(setOf("h2", "h4"), st.hosts.filter { it.error != null }.map { it.hostId }.toSet())
        model.markAnswered(st.items.single())
        assertTrue(model.state.value.visible.isEmpty())
    }

    @Test fun parsesOptionalOverviewFields() {
        val o = com.huanmeng.huanhermes.core.protocol.ProtocolJson.parseToJsonElement(
            """{"session_key":"k","status":"needs_you","last_message_preview":"hi","updated_at":12.5,
               "pending_permissions":[{"id":"p9","prompt":"ls","reply_ctx":"r","buttons":[[{"text":"Allow","data":"perm:p9:allow"},{"text":"Deny","data":"perm:p9:deny"}]]}]}""",
        ) as kotlinx.serialization.json.JsonObject
        val info = MgmtClient.session(o, "codex")
        assertEquals("needs_you", info.status)
        assertEquals("hi", info.preview)
        assertEquals(listOf("perm:p9:allow", "perm:p9:deny"), info.pendingPermissions.single().buttons.map { it.data })
        val old = MgmtClient.session(com.huanmeng.huanhermes.core.protocol.ProtocolJson.parseToJsonElement("""{"session_key":"k"}""") as kotlinx.serialization.json.JsonObject, "p")
        assertTrue(old.pendingPermissions.isEmpty())
        assertEquals(null, old.status)
    }

    @Test fun titleSortKeepsNeedsYouFirst() {
        fun s(id: String, title: String, t: Double, perm: Boolean = false) = com.huanmeng.huanhermes.core.mgmt.SessionInfo(
            id = id, sessionKey = id, project = "p", title = title, lastUser = null, updatedAt = t, running = false, mode = null, model = null,
            pendingPermissions = if (perm) listOf(com.huanmeng.huanhermes.core.mgmt.PendingPermission("x", "c", null, emptyList())) else emptyList(),
        )
        val list = listOf(s("1", "beta", 3.0), s("2", "Alpha", 1.0), s("3", "zeta", 2.0, perm = true))
        val rows = SessionGrouping.group(list, LocalSessionPrefs.Snapshot(), true, sort = SessionSort.Title).single().rows
        assertEquals(listOf("zeta", "Alpha", "beta"), rows.map { it.session.displayTitle })
        val recent = SessionGrouping.group(list, LocalSessionPrefs.Snapshot(), true).single().rows
        assertEquals(listOf("zeta", "beta", "Alpha"), recent.map { it.session.displayTitle })
    }
}
