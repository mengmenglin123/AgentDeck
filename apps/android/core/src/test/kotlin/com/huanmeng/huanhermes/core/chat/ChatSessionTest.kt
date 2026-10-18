package com.huanmeng.huanhermes.core.chat

import com.huanmeng.huanhermes.core.bridge.BridgeClient
import com.huanmeng.huanhermes.core.bridge.FakeTransport
import com.huanmeng.huanhermes.core.bridge.ReconnectPolicy
import com.huanmeng.huanhermes.core.mgmt.MgmtApi
import com.huanmeng.huanhermes.core.mgmt.ProjectInfo
import com.huanmeng.huanhermes.core.mgmt.SessionDetail
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.core.mgmt.TranscriptRow
import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.net.HostError
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FakeMgmt : MgmtApi {
    var transcript = listOf<TranscriptRow>()
    var detailCalls = 0
    var failDetail = false
    override suspend fun status() = JsonObject(emptyMap())
    override suspend fun projects() = emptyList<ProjectInfo>()
    override suspend fun sessions(project: String?) = emptyList<SessionInfo>()
    override suspend fun createSession(project: String, title: String?) = throw UnsupportedOperationException()
    override suspend fun renameSession(id: String, title: String, project: String?) = throw UnsupportedOperationException()
    override suspend fun deleteSession(id: String, project: String?) = Unit
    override suspend fun sessionDetail(id: String, project: String?): SessionDetail {
        detailCalls += 1
        if (failDetail) throw HostError.Http(404, "not found")
        return SessionDetail(transcript, "default", "m", "/w", emptyList(), false, null)
    }
}

class MemoryQueueStorage : QueueStorage {
    var stored = listOf<QueuedMessage>()
    override fun read() = stored
    override fun write(items: List<QueuedMessage>) { stored = items }
}

@OptIn(ExperimentalCoroutinesApi::class)
class ChatSessionTest {
    private val config = HostConfig(host = "h", bridgeToken = "btok-123", mgmtToken = "mtok-123", deviceId = "d")
    private val sk = "huan:d:c1"

    private class Rig(val fake: FakeTransport, val bridge: BridgeClient, val mgmt: FakeMgmt, val queue: OfflineQueue, val storage: MemoryQueueStorage, val chat: ChatSession)

    private fun TestScope.rig(storage: MemoryQueueStorage = MemoryQueueStorage()): Rig {
        val fake = FakeTransport()
        val bridge = BridgeClient(config, fake, backgroundScope, policy = ReconnectPolicy(1_000, 60_000, 0.0), now = { testScheduler.currentTime })
        val mgmt = FakeMgmt()
        val queue = OfflineQueue(storage, io = kotlinx.coroutines.test.StandardTestDispatcher(testScheduler))
        val chat = ChatSession("host-A", SessionRef("c1", sk, "codex", "t"), bridge, mgmt, queue, backgroundScope, clock = { testScheduler.currentTime })
        return Rig(fake, bridge, mgmt, queue, storage, chat)
    }

    private fun TestScope.connect(r: Rig, v2: Boolean = true) {
        runCurrent(); r.fake.last.open(); runCurrent()
        if (v2) r.fake.last.ackV2() else r.fake.last.ack()
        runCurrent()
    }

    private fun Rig.sentMessages() = fake.sockets.flatMap { s -> s.sent.filter { it["type"]!!.jsonPrimitive.content == "message" } }

    @Test fun framesForOtherSessionsAreIgnoredIncludingTyping() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        r.fake.last.text("""{"type":"typing_start","session_key":"huan:d:OTHER"}""")
        r.fake.last.text("""{"type":"reply_stream","session_key":"huan:d:OTHER","delta":"leak","reply_ctx":"other-ctx"}""")
        r.fake.last.text("""{"type":"reply","content":"no session key at all"}""")
        runCurrent()
        assertFalse(r.chat.state.value.typing)
        assertTrue(r.chat.state.value.items.isEmpty())
        r.fake.last.text("""{"type":"typing_start","session_key":"$sk"}""")
        r.fake.last.text("""{"type":"reply_stream","session_key":"$sk","delta":"mine"}""")
        runCurrent()
        assertTrue(r.chat.state.value.typing)
        assertEquals("mine", (r.chat.state.value.items.single() as ChatItem.Assistant).text)
        // cancel must use this session's reply_ctx, never the other session's
        r.chat.cancelRun()
        val cancel = r.fake.last.sent.last()
        assertEquals("cancel", cancel["type"]!!.jsonPrimitive.content)
        assertFalse(cancel.toString().contains("other-ctx"))
    }

    @Test fun offlineTextIsQueuedAndFlushedBackToItsOwnSessionOnly() = runTest {
        val storage = MemoryQueueStorage().apply {
            stored = listOf(
                QueuedMessage("host-A", "huan:d:OTHER", null, "not mine", "m-other", 1),
                QueuedMessage("host-B", sk, null, "other host", "m-hostb", 2),
            )
        }
        val r = rig(storage); r.chat.start(); runCurrent()
        assertTrue(r.chat.send("hello offline"))
        val user = r.chat.state.value.items.filterIsInstance<ChatItem.User>().single()
        assertTrue(user.queued)
        connect(r)
        val sent = r.sentMessages()
        assertEquals(listOf("hello offline"), sent.map { it["content"]!!.jsonPrimitive.content })
        assertEquals(sk, sent.single()["session_key"]!!.jsonPrimitive.content)
        assertEquals(user.msgId, sent.single()["msg_id"]!!.jsonPrimitive.content)
        assertFalse(r.chat.state.value.items.filterIsInstance<ChatItem.User>().single().queued)
        assertEquals(setOf("m-other", "m-hostb"), storage.stored.map { it.msgId }.toSet())
    }

    @Test fun sendWhileConnectedGoesOutImmediately() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        assertTrue(r.chat.send("  hi  "))
        assertEquals("hi", r.sentMessages().single()["content"]!!.jsonPrimitive.content)
        assertTrue(r.chat.state.value.runActive)
        assertFalse(r.chat.send("   "))
    }

    @Test fun reconnectClearsErrorBannerAndResyncsOnV1Host() = runTest {
        val r = rig(); r.chat.start(); connect(r, v2 = false)
        val callsAfterOpen = r.mgmt.detailCalls
        r.fake.last.serverClose(); runCurrent()
        assertTrue(r.chat.state.value.banner is ConnectionBanner.Reconnecting)
        assertFalse(r.chat.state.value.connected)
        r.chat.cancelRun() // fails while offline -> error
        assertEquals("未连接，无法取消", r.chat.state.value.error)
        advanceTimeBy(1_001); connect(r, v2 = false)
        assertEquals(ConnectionBanner.None, r.chat.state.value.banner)
        assertNull(r.chat.state.value.error)
        assertTrue("transcript reloaded after reconnect", r.mgmt.detailCalls > callsAfterOpen)
    }

    @Test fun resyncRequiredReloadsTranscript() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        r.mgmt.transcript = listOf(TranscriptRow("user", "q"), TranscriptRow("assistant", "a"))
        r.fake.last.text("""{"type":"resync_required","session_key":"$sk","last_seq":5}""")
        runCurrent()
        assertEquals(2, r.chat.state.value.items.size)
        assertEquals(5L, r.bridge.lastSeq(sk))
    }

    @Test fun sessionStatusOnFirstConnectPreventsReplayingHydratedHistory() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        assertTrue(r.fake.last.sent.any { it["type"]!!.jsonPrimitive.content == "session_status" })
        r.fake.last.text("""{"type":"session_status","session_key":"$sk","alive":true,"running":true,"last_seq":12}""")
        runCurrent()
        assertEquals(12L, r.bridge.lastSeq(sk))
        assertTrue(r.chat.state.value.runActive)
    }

    @Test fun permissionUsesCardReplyCtxAndExactButtonData() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        r.fake.last.text("""{"type":"buttons","session_key":"$sk","reply_ctx":"card-ctx","content":"ok?","buttons":[[{"text":"Allow","data":"perm:p7:allow"},{"text":"Deny","data":"perm:p7:deny"}]]}""")
        r.fake.last.text("""{"type":"reply_stream","session_key":"$sk","reply_ctx":"later-ctx","delta":"x"}""")
        runCurrent()
        val card = r.chat.state.value.items.filterIsInstance<ChatItem.Permission>().single()
        assertTrue(r.chat.respondPermission(card, "deny"))
        val action = r.fake.last.sent.last()
        assertEquals("perm:p7:deny", action["action"]!!.jsonPrimitive.content)
        assertEquals("card-ctx", action["reply_ctx"]!!.jsonPrimitive.content)
        assertEquals("deny", r.chat.state.value.items.filterIsInstance<ChatItem.Permission>().single().decision)
    }

    @Test fun planAndQuestionCardsCarryFeedbackAndAnswers() = runTest {
        val r = rig(); r.chat.start()
        runCurrent(); r.fake.last.open(); runCurrent()
        r.fake.last.ack(""","protocol":2,"capabilities":["seq","resume","session_status","plan_cards","usage"],"epoch":"e1"""")
        runCurrent()
        r.fake.last.text("""{"type":"card","session_key":"$sk","reply_ctx":"c1","kind":"plan","content":"## Plan","buttons":[[{"text":"Accept","data":"perm:p1:accept"},{"text":"Keep","data":"perm:p1:keep"}]]}""")
        r.fake.last.text("""{"type":"card","session_key":"$sk","reply_ctx":"c2","kind":"question","content":"Q","questions":[{"id":"0","question":"DB?","options":[{"label":"SQLite"},{"label":"PG","description":"prod"}]}],"buttons":[[{"text":"Submit","data":"perm:p2:submit"}]]}""")
        r.fake.last.text("""{"type":"run_done","session_key":"$sk","status":"completed","usage":{"context_tokens":50000,"context_window":200000}}""")
        runCurrent()
        val (plan, question) = r.chat.state.value.items.filterIsInstance<ChatItem.Permission>()
        assertEquals("plan", plan.kind)
        assertEquals("PG", question.questions.single().options[1].label)
        assertEquals(25, r.chat.state.value.usage?.contextPercent)
        assertTrue(r.chat.respondPermission(plan, "keep", text = "先别动数据库"))
        val a1 = r.fake.last.sent.last()
        assertEquals("perm:p1:keep", a1["action"]!!.jsonPrimitive.content)
        assertEquals("先别动数据库", a1["text"]!!.jsonPrimitive.content)
        assertTrue(r.chat.respondPermission(question, "submit", answers = mapOf("0" to listOf("PG"))))
        val a2 = r.fake.last.sent.last()
        assertEquals("perm:p2:submit", a2["action"]!!.jsonPrimitive.content)
        assertTrue(a2["answers"].toString().contains("PG"))
        assertEquals(listOf("keep", "submit"), r.chat.state.value.items.filterIsInstance<ChatItem.Permission>().map { it.decision })
    }

    @Test fun oldHostGetsPlanFeedbackAsMessage() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        r.fake.last.text("""{"type":"card","session_key":"$sk","reply_ctx":"c1","kind":"plan","content":"## Plan","buttons":[[{"text":"Keep","data":"perm:p1:keep"}]]}""")
        runCurrent()
        val plan = r.chat.state.value.items.filterIsInstance<ChatItem.Permission>().single()
        assertTrue(r.chat.respondPermission(plan, "keep", text = "再想想"))
        assertTrue(r.fake.last.sent.none { it["type"]!!.jsonPrimitive.content == "card_action" && it.containsKey("text") })
        assertEquals("再想想", r.sentMessages().last()["content"]!!.jsonPrimitive.content)
    }

    @Test fun stallHintAfterFiveSilentMinutes() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        advanceTimeBy(1_000)
        r.fake.last.text("""{"type":"reply_stream","session_key":"$sk","delta":"x"}""")
        runCurrent()
        val st = r.chat.state.value
        assertTrue(st.runActive)
        assertEquals(false, st.stalled(st.lastActivityAt + 60_000))
        assertTrue(st.stalled(st.lastActivityAt + ChatState.STALL_MS))
    }

    @Test fun noStateUpdatesAfterClose() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        val before = r.chat.state.value
        r.chat.close()
        r.fake.last.text("""{"type":"reply_stream","session_key":"$sk","delta":"late"}""")
        r.fake.last.serverClose()
        runCurrent()
        assertEquals(before, r.chat.state.value)
    }

    @Test fun emptyHostHistoryDoesNotWipeTheScreenOnResync() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        r.fake.last.text("""{"type":"reply","session_key":"$sk","content":"kept"}""")
        runCurrent()
        r.fake.last.text("""{"type":"resync_required","session_key":"$sk","last_seq":3}""")
        runCurrent()
        assertEquals("kept", (r.chat.state.value.items.single() as ChatItem.Assistant).text)
    }

    @Test fun missingHistoryIsNotAnError() = runTest {
        val r = rig(); r.mgmt.failDetail = true
        r.chat.start(); connect(r)
        assertNull(r.chat.state.value.error)
        assertFalse(r.chat.state.value.reloading)
    }

    @Test fun messagesTypedDuringARunWaitForRunDone() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        assertTrue(r.chat.send("first"))
        assertTrue(r.chat.send("second"))
        assertTrue(r.chat.send("/status"))
        // v2 Host (session_status): queued behind the run; slash commands go straight out.
        assertEquals(listOf("first", "/status"), r.sentMessages().map { it["content"]!!.jsonPrimitive.content })
        assertEquals(listOf("second"), r.chat.state.value.runQueue.map { it.text })
        r.fake.last.text("""{"type":"run_done","session_key":"$sk","status":"completed"}""")
        runCurrent()
        assertEquals(listOf("first", "/status", "second"), r.sentMessages().map { it["content"]!!.jsonPrimitive.content })
        assertTrue(r.chat.state.value.runQueue.isEmpty())
    }

    @Test fun queuedEntriesCanBeEditedOrSentNow() = runTest {
        val r = rig(); r.chat.start(); connect(r)
        r.chat.send("first"); r.chat.send("a"); r.chat.send("b")
        val (a, b) = r.chat.state.value.runQueue
        assertEquals("a", r.chat.takeQueued(a.msgId))
        assertTrue(r.chat.sendQueuedNow(b.msgId))
        assertEquals(listOf("first", "b"), r.sentMessages().map { it["content"]!!.jsonPrimitive.content })
        assertTrue(r.chat.state.value.runQueue.isEmpty())
    }

    @Test fun v1HostWithoutRunEndsNeverQueues() = runTest {
        val r = rig(); r.chat.start(); connect(r, v2 = false)
        r.chat.send("first"); r.chat.send("second")
        assertEquals(listOf("first", "second"), r.sentMessages().map { it["content"]!!.jsonPrimitive.content })
    }
}
