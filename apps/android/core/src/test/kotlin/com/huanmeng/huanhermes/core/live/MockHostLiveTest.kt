package com.huanmeng.huanhermes.core.live

import com.huanmeng.huanhermes.core.bridge.BridgeClient
import com.huanmeng.huanhermes.core.bridge.BridgeState
import com.huanmeng.huanhermes.core.bridge.OkHttpWsTransport
import com.huanmeng.huanhermes.core.bridge.ReconnectPolicy
import com.huanmeng.huanhermes.core.chat.ChatItem
import com.huanmeng.huanhermes.core.chat.ChatSession
import com.huanmeng.huanhermes.core.chat.MemoryQueueStorage
import com.huanmeng.huanhermes.core.chat.OfflineQueue
import com.huanmeng.huanhermes.core.chat.SessionRef
import com.huanmeng.huanhermes.core.hosts.MemoryProfileStorage
import com.huanmeng.huanhermes.core.hosts.ProfileManager
import com.huanmeng.huanhermes.core.mgmt.MgmtClient
import com.huanmeng.huanhermes.core.net.HostConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File
import java.net.ServerSocket
import java.net.Socket

/** End to end against server/mock-host/mock_host.py over real sockets (skipped without python3). */
class MockHostLiveTest {
    companion object {
        private var proc: Process? = null
        private var bridgePort = 0
        private var mgmtPort = 0

        private fun freePort() = ServerSocket(0).use { it.localPort }

        @BeforeClass @JvmStatic fun startMock() {
            val serverDir = File(System.getProperty("huanhermes.serverDir") ?: return)
            val script = File(serverDir, "mock-host/mock_host.py")
            if (!script.exists()) return
            bridgePort = freePort(); mgmtPort = freePort()
            proc = runCatching {
                ProcessBuilder("python3", script.absolutePath).apply {
                    environment().putAll(mapOf(
                        "HUAN_BRIDGE_HOST" to "127.0.0.1",
                        "HUAN_BRIDGE_PORT" to "$bridgePort", "HUAN_MGMT_PORT" to "$mgmtPort",
                        "HUAN_BRIDGE_TOKEN" to "live-bridge-token", "HUAN_MGMT_TOKEN" to "live-mgmt-token",
                    ))
                    redirectErrorStream(true)
                    redirectOutput(ProcessBuilder.Redirect.DISCARD)
                }.start()
            }.getOrNull()
            val deadline = System.currentTimeMillis() + 10_000
            while (proc != null && System.currentTimeMillis() < deadline) {
                if (runCatching { Socket("127.0.0.1", bridgePort).close(); Socket("127.0.0.1", mgmtPort).close() }.isSuccess) return
                Thread.sleep(100)
            }
            proc?.destroy(); proc = null
        }

        @AfterClass @JvmStatic fun stopMock() { proc?.destroy() }
    }

    private val config get() = HostConfig(
        host = "127.0.0.1", bridgePort = bridgePort, mgmtPort = mgmtPort,
        bridgeToken = "live-bridge-token", mgmtToken = "live-mgmt-token", deviceId = "livetest",
    )

    @Test fun profileProbeSessionsAndStreamingChatRoundTrip() = runBlocking {
        assumeTrue("mock host not available", proc != null)
        val pm = ProfileManager(MemoryProfileStorage(), { MgmtClient(it) })
        pm.load()
        assertTrue(pm.state.value.lastError ?: "", pm.testAndSave(null, "mock", config))
        val mgmt = MgmtClient(config)
        assertTrue(mgmt.projects().isNotEmpty())
        val project = mgmt.projects().first().name
        val created = mgmt.createSession(project, "原生测试")
        assertTrue(mgmt.sessions(project).any { it.id == created.id })

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val bridge = BridgeClient(config, OkHttpWsTransport(), scope, policy = ReconnectPolicy(200, 2_000))
            val chat = ChatSession("live", SessionRef(created.id, config.sessionKeyFor("live-1"), project, "t"), bridge,
                mgmt, OfflineQueue(MemoryQueueStorage()), scope)
            chat.start()
            withTimeout(10_000) { bridge.state.first { it is BridgeState.Connected } }
            assertEquals(2, (bridge.state.value as BridgeState.Connected).protocol)
            assertTrue(chat.send("hello"))
            val done = withTimeout(20_000) { chat.state.first { s -> s.items.any { it is ChatItem.RunEnded } } }
            assertTrue(done.items.any { it is ChatItem.Assistant && it.text.isNotBlank() })
            assertTrue(bridge.lastSeq(config.sessionKeyFor("live-1")) > 0)
            chat.close()
            bridge.stop()
        } finally {
            scope.cancel()
        }
    }

    @Test fun wrongBridgeTokenStopsWithAuthErrorAndNoTokenInMessage() = runBlocking {
        assumeTrue("mock host not available", proc != null)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val bad = config.copy(bridgeToken = "wrong-token-value")
            val bridge = BridgeClient(bad, OkHttpWsTransport(), scope, policy = ReconnectPolicy(200, 1_000))
            bridge.start()
            val stopped = withTimeout(10_000) { bridge.state.first { it is BridgeState.Stopped } } as BridgeState.Stopped
            assertTrue(stopped.authFailed)
            assertTrue(!stopped.reason.contains("wrong-token-value"))
        } finally {
            scope.cancel()
        }
    }

    @Test fun terminalOpenEchoResizeAndCatalogs() = runBlocking {
        assumeTrue("mock host not available", proc != null)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val bridge = BridgeClient(config, OkHttpWsTransport(), scope)
        try {
            val term = com.huanmeng.huanhermes.core.terminal.TerminalSession(bridge, scope, "live-term", "codex", cols = 60, rows = 12)
            term.start()
            withTimeout(10_000) { term.ui.first { it.status == com.huanmeng.huanhermes.core.terminal.TerminalSession.Status.Open } }
            term.input("echo hello-term\n")
            // Mock output uses bare LF: the output line must still start at column 0.
            withTimeout(10_000) { term.ui.first { term.read { e -> e.screenText() }.lines().any { it.startsWith("hello-term") } } }
            term.resize(40, 10)
            term.input("stty size\n")
            withTimeout(10_000) { term.ui.first { term.read { e -> e.screenText() }.contains("columns") } }
            term.close()
            // M3 catalogs parse against the real mock payloads.
            val mgmt = MgmtClient(config)
            com.huanmeng.huanhermes.core.catalog.CatalogKind.entries.forEach { kind ->
                val rows = com.huanmeng.huanhermes.core.catalog.HostCatalogs.parse(kind, mgmt.get(kind.url(null)))
                if (kind != com.huanmeng.huanhermes.core.catalog.CatalogKind.AUDIT) assertTrue("$kind empty", rows.isNotEmpty())
            }
        } finally {
            bridge.stop(); scope.cancel()
        }
    }
}
