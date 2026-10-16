package com.huanmeng.huanhermes.core.bridge

import com.huanmeng.huanhermes.core.net.HostConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BridgeClientTest {
    private val config = HostConfig(host = "10.0.0.2", bridgeToken = "secret-bridge-tok", mgmtToken = "secret-mgmt-tok", deviceId = "dev1")

    private fun TestScope.client(fake: FakeTransport, heartbeatMs: Long = 15_000) = BridgeClient(
        config, fake, backgroundScope, policy = ReconnectPolicy(baseMs = 1_000, maxMs = 60_000, jitter = 0.0),
        heartbeatMs = heartbeatMs, registerTimeoutMs = 5_000, now = { testScheduler.currentTime },
    )

    private fun TestScope.collect(c: BridgeClient): MutableList<BridgeEvent> {
        val out = mutableListOf<BridgeEvent>()
        backgroundScope.launch { c.events.collect { out += it } }
        return out
    }

    private fun TestScope.connect(fake: FakeTransport, v2: Boolean = true) {
        runCurrent()
        fake.last.open()
        runCurrent()
        if (v2) fake.last.ackV2() else fake.last.ack()
        runCurrent()
    }

    @Test fun registersWithV2CapabilitiesAndBecomesConnected() = runTest {
        val fake = FakeTransport()
        val c = client(fake)
        c.start()
        connect(fake)
        val register = fake.last.sent.first()
        assertEquals("register", register["type"]!!.jsonPrimitive.content)
        assertTrue(register.toString().contains("\"resume\""))
        assertTrue(c.isConnected)
        assertEquals(BridgeState.Connected(2, setOf("seq", "resume", "session_status"), "e1"), c.state.value)
        assertEquals("Bearer secret-bridge-tok", fake.last.headers["Authorization"])
    }

    @Test fun handshakeFailuresKeepRetryingWithUncappedAttemptsAndCappedDelay() = runTest {
        val fake = FakeTransport()
        fake.onOpen = { s -> s.fail(java.io.IOException("Failed to connect to ws://10.0.0.2:9810/bridge/ws?token=secret-bridge-tok")) }
        val c = client(fake)
        c.start()
        runCurrent()
        val delays = mutableListOf<Long>()
        repeat(15) {
            val st = c.state.value as BridgeState.Reconnecting
            delays += st.delayMs
            assertFalse("token must be redacted: ${st.reason}", st.reason.contains("secret-bridge-tok"))
            advanceTimeBy(st.delayMs + 1)
            runCurrent()
        }
        assertEquals(listOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 32_000L, 60_000L), delays.take(7))
        assertTrue(delays.drop(6).all { it == 60_000L })
        assertTrue("attempts are not capped", fake.sockets.size >= 16)
    }

    @Test fun authRejectionStopsReconnecting() = runTest {
        val fake = FakeTransport()
        fake.onOpen = { s -> s.fail(java.net.ProtocolException("Expected HTTP 101 response but was '401 Unauthorized'"), 401) }
        val c = client(fake)
        c.start()
        runCurrent()
        val st = c.state.value as BridgeState.Stopped
        assertTrue(st.authFailed)
        advanceTimeBy(600_000)
        assertEquals(1, fake.sockets.size)
        c.reconnectNow() // explicit user action restarts
        runCurrent()
        assertEquals(2, fake.sockets.size)
    }

    @Test fun registerAckDeniedForTokenStops() = runTest {
        val fake = FakeTransport()
        val c = client(fake)
        c.start(); runCurrent(); fake.last.open(); runCurrent()
        fake.last.text("""{"type":"register_ack","ok":false,"error":"invalid token"}""")
        runCurrent()
        assertTrue((c.state.value as BridgeState.Stopped).authFailed)
    }

    @Test fun registerTimeoutRetries() = runTest {
        val fake = FakeTransport()
        val c = client(fake)
        c.start(); runCurrent(); fake.last.open()
        advanceTimeBy(5_001); runCurrent()
        assertTrue(c.state.value is BridgeState.Reconnecting)
        assertTrue(fake.sockets[0].closed)
    }

    @Test fun serverCloseFlipsIsConnectedImmediately() = runTest {
        val fake = FakeTransport()
        val c = client(fake)
        c.start(); connect(fake)
        assertTrue(c.isConnected)
        fake.last.serverClose()
        runCurrent()
        assertFalse(c.isConnected)
        assertTrue(c.state.value is BridgeState.Reconnecting)
        assertFalse(c.send(kotlinx.serialization.json.buildJsonObject { }))
        advanceTimeBy(1_001); runCurrent()
        assertEquals(2, fake.sockets.size)
    }

    @Test fun heartbeatDeclaresDeadLinkAfterTwoSilentPeriods() = runTest {
        val fake = FakeTransport()
        val c = client(fake, heartbeatMs = 10_000)
        c.start(); connect(fake)
        advanceTimeBy(10_001); runCurrent()
        assertTrue(c.isConnected) // one silent period: still up, a ping went out
        assertTrue("ping" in fake.last.sentTypes())
        advanceTimeBy(10_000); runCurrent()
        assertFalse(c.isConnected)
        assertTrue((c.state.value as BridgeState.Reconnecting).reason.contains("心跳"))
    }

    @Test fun pongKeepsTheLinkAlive() = runTest {
        val fake = FakeTransport()
        val c = client(fake, heartbeatMs = 10_000)
        c.start(); connect(fake)
        repeat(6) {
            advanceTimeBy(10_000); runCurrent()
            fake.last.text("""{"type":"pong"}""")
            runCurrent()
        }
        assertTrue(c.isConnected)
        assertEquals(1, fake.sockets.size)
    }

    @Test fun duplicateSeqIsDroppedAndResumeAfterReconnectUsesLastSeq() = runTest {
        val fake = FakeTransport()
        val c = client(fake)
        val events = collect(c)
        c.watch("s1")
        c.start(); connect(fake)
        fake.last.text("""{"type":"reply_stream","session_key":"s1","delta":"a","seq":1}""")
        fake.last.text("""{"type":"reply_stream","session_key":"s1","delta":"b","seq":2}""")
        fake.last.text("""{"type":"reply_stream","session_key":"s1","delta":"b","seq":2}""")
        runCurrent()
        assertEquals(2, events.filterIsInstance<BridgeEvent.Frame>().size)
        fake.last.serverClose(); runCurrent()
        advanceTimeBy(1_001); connect(fake)
        val resume = fake.last.sent.first { it["type"]!!.jsonPrimitive.content == "resume" }
        assertEquals(2L, resume["after_seq"]!!.jsonPrimitive.long)
        assertEquals("e1", resume["epoch"]!!.jsonPrimitive.content)
        assertTrue(events.contains(BridgeEvent.Reconnected))
        // Replay overlapping what we already have: only seq 3 is new.
        fake.last.text("""{"type":"reply_stream","session_key":"s1","delta":"b","seq":2,"replayed":true}""")
        fake.last.text("""{"type":"reply_stream","session_key":"s1","delta":"c","seq":3,"replayed":true}""")
        runCurrent()
        assertEquals(3, events.filterIsInstance<BridgeEvent.Frame>().size)
        assertEquals(3L, c.lastSeq("s1"))
    }

    @Test fun resyncRequiredAndV1HostAndHostRestartAskForResync() = runTest {
        val fake = FakeTransport()
        val c = client(fake)
        val events = collect(c)
        c.watch("s1")
        c.start(); connect(fake)
        fake.last.text("""{"type":"resync_required","session_key":"s1","last_seq":40}""")
        runCurrent()
        assertEquals(BridgeEvent.ResyncNeeded("s1", "resync_required"), events.last())
        assertEquals(40L, c.lastSeq("s1"))
        // Host restarted (new epoch): resume would be meaningless.
        fake.last.serverClose(); runCurrent(); advanceTimeBy(1_001); runCurrent()
        fake.last.open(); runCurrent(); fake.last.ackV2(epoch = "e2"); runCurrent()
        assertEquals(BridgeEvent.ResyncNeeded("s1", "host_restarted"), events.last())
        assertFalse("resume" in fake.last.sentTypes())
        assertEquals(0L, c.lastSeq("s1"))
        // v1 Host (Flutter-era) has no resume at all.
        fake.last.serverClose(); runCurrent(); advanceTimeBy(1_001)
        connect(fake, v2 = false)
        assertEquals(BridgeEvent.ResyncNeeded("s1", "no_resume"), events.last())
    }

    @Test fun framesForUnwatchedSessionsStillFlowForTheInbox() = runTest {
        val fake = FakeTransport()
        val c = client(fake)
        val events = collect(c)
        c.start(); connect(fake)
        fake.last.text("""{"type":"buttons","session_key":"other","buttons":[{"text":"Allow","data":"perm:p:allow"}]}""")
        fake.last.text("""not json""")
        fake.last.text("""{"type":"pong"}""")
        runCurrent()
        assertEquals(1, events.size)
    }

    @Test fun tokenIsEncodedInUrl() = runTest {
        val fake = FakeTransport()
        val c = BridgeClient(config.copy(bridgeToken = "a&b=c d"), fake, backgroundScope)
        c.start(); runCurrent()
        assertTrue(fake.urls.single().endsWith("?token=a%26b%3Dc%20d"))
        c.stop()
    }

    @Test fun stopEndsTheLoop() = runTest {
        val fake = FakeTransport()
        val c = client(fake)
        c.start(); connect(fake)
        c.stop()
        runCurrent()
        assertEquals(BridgeState.Idle, c.state.value)
        advanceTimeBy(120_000)
        assertEquals(1, fake.sockets.size)
    }
}
