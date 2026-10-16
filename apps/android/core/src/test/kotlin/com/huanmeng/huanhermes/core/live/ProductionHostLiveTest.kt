package com.huanmeng.huanhermes.core.live

import com.huanmeng.huanhermes.core.bridge.BridgeClient
import com.huanmeng.huanhermes.core.bridge.BridgeState
import com.huanmeng.huanhermes.core.bridge.OkHttpWsTransport
import com.huanmeng.huanhermes.core.bridge.ReconnectPolicy
import com.huanmeng.huanhermes.core.chat.ChatItem
import com.huanmeng.huanhermes.core.chat.ChatSession
import com.huanmeng.huanhermes.core.chat.ChatState
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
import java.nio.file.Files
import java.util.Collections
import kotlin.concurrent.thread

/**
 * End to end against the real production Host (server/production_host.py) with a
 * JSONL fixture agent, through a TCP proxy that can sever live connections, so the
 * reconnect + resume path runs over real sockets.
 */
class ProductionHostLiveTest {
    /** Forwards one port to another; [dropAll] kills every live connection. */
    class DropProxy(private val target: Int) : AutoCloseable {
        private val server = ServerSocket(0)
        val port = server.localPort
        private val live = Collections.synchronizedList(mutableListOf<Socket>())

        init {
            thread(isDaemon = true) {
                while (!server.isClosed) {
                    val client = runCatching { server.accept() }.getOrNull() ?: break
                    val upstream = runCatching { Socket("127.0.0.1", target) }.getOrNull() ?: run { client.close(); null } ?: continue
                    live += client; live += upstream
                    pipe(client, upstream); pipe(upstream, client)
                }
            }
        }

        private fun pipe(from: Socket, to: Socket) = thread(isDaemon = true) {
            runCatching { from.getInputStream().copyTo(to.getOutputStream()) }
            runCatching { from.close() }; runCatching { to.close() }
        }

        fun dropAll() = synchronized(live) { live.forEach { runCatching { it.close() } }; live.clear() }
        override fun close() { server.close(); dropAll() }
    }

    companion object {
        private var proc: Process? = null
        private var bridgePort = 0
        private var mgmtPort = 0
        private lateinit var proxy: DropProxy
        private fun freePort() = ServerSocket(0).use { it.localPort }

        @BeforeClass @JvmStatic fun start() {
            val serverDir = File(System.getProperty("huanhermes.serverDir") ?: return)
            val host = File(serverDir, "production_host.py")
            val agent = File(ProductionHostLiveTest::class.java.getResource("/fake_agent.py")?.toURI() ?: return)
            if (!host.exists()) return
            val root = Files.createTempDirectory("hh-prod").toFile()
            bridgePort = freePort(); mgmtPort = freePort()
            val toml = File(root, "host.toml")
            toml.writeText(
                """
                [server]
                bridge_host = "127.0.0.1"
                bridge_port = $bridgePort
                mgmt_host = "127.0.0.1"
                mgmt_port = $mgmtPort
                default_project = "codex"

                [auth]
                bridge_token = "prod-bridge-token"
                mgmt_token = "prod-mgmt-token"

                [workspace]
                roots = ["${root.absolutePath}"]

                [management]
                session_store_path = "${File(root, "sessions.json").absolutePath}"

                [audit]
                permission_log_path = "${File(root, "audit.jsonl").absolutePath}"
                permission_log_fsync = false

                [projects.codex]
                agent_type = "codex"
                command = ["python3", "-u", "${agent.absolutePath}"]
                workdir = "${root.absolutePath}"
                """.trimIndent(),
            )
            toml.setReadable(false, false); toml.setReadable(true, true)
            proc = runCatching {
                ProcessBuilder("python3", host.absolutePath, "--config", toml.absolutePath)
                    .directory(serverDir).redirectErrorStream(true)
                    .redirectOutput(File(root, "host.log")).start()
            }.getOrNull()
            val deadline = System.currentTimeMillis() + 10_000
            while (proc != null && System.currentTimeMillis() < deadline) {
                if (runCatching { Socket("127.0.0.1", bridgePort).close(); Socket("127.0.0.1", mgmtPort).close() }.isSuccess) {
                    proxy = DropProxy(bridgePort)
                    return
                }
                Thread.sleep(100)
            }
            println(File(root, "host.log").takeIf { it.exists() }?.readText())
            proc?.destroy(); proc = null
        }

        @AfterClass @JvmStatic fun stop() {
            if (proc != null) proxy.close()
            proc?.destroy()
        }
    }

    private val config get() = HostConfig(
        host = "127.0.0.1", bridgePort = proxy.port, mgmtPort = mgmtPort,
        bridgeToken = "prod-bridge-token", mgmtToken = "prod-mgmt-token", deviceId = "prodlive",
    )

    private suspend fun ChatSession.awaitState(ms: Long = 15_000, p: (ChatState) -> Boolean) =
        withTimeout(ms) { state.first(p) }

    private fun runChat(block: suspend (CoroutineScope, BridgeClient, ChatSession) -> Unit) = runBlocking {
        assumeTrue("production host not available", proc != null)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val mgmt = MgmtClient(config)
            val created = mgmt.createSession("codex", "native e2e")
            val bridge = BridgeClient(config, OkHttpWsTransport(), scope, policy = ReconnectPolicy(200, 1_000), heartbeatMs = 5_000)
            val chat = ChatSession("prod", SessionRef(created.id, created.sessionKey, "codex", "t"), bridge, mgmt,
                OfflineQueue(MemoryQueueStorage()), scope)
            chat.start()
            withTimeout(10_000) { bridge.state.first { it is BridgeState.Connected } }
            block(scope, bridge, chat)
            chat.close(); bridge.stop()
        } finally {
            scope.cancel()
        }
    }

    @Test fun probeProjectsAndSessionCrud() = runBlocking {
        assumeTrue("production host not available", proc != null)
        val pm = ProfileManager(MemoryProfileStorage(), { MgmtClient(it) })
        pm.load()
        assertTrue(pm.state.value.lastError ?: "", pm.testAndSave(null, "prod", config))
        val mgmt = MgmtClient(config)
        assertEquals(listOf("codex"), mgmt.projects().map { it.name })
        val s = mgmt.createSession("codex", "原生")
        assertTrue(mgmt.sessions("codex").any { it.id == s.id })
        val renamed = mgmt.renameSession(s.id, "改名后", "codex")
        assertEquals("改名后", renamed.title ?: mgmt.sessions("codex").first { it.id == s.id }.title)
        mgmt.sessionDetail(s.id, "codex")
        mgmt.deleteSession(s.id, "codex")
        assertTrue(mgmt.sessions("codex").none { it.id == s.id })
    }

    @Test fun streamingThinkingToolsAndRunDone() = runChat { _, bridge, chat ->
        assertEquals(2, (bridge.state.value as BridgeState.Connected).protocol)
        assertTrue(chat.send("世界"))
        val s = chat.awaitState { st -> st.items.any { it is ChatItem.RunEnded } }
        val assistant = s.items.filterIsInstance<ChatItem.Assistant>().single()
        assertEquals("你好，世界", assistant.text)
        assertTrue(!assistant.streaming)
        val tool = s.items.filterIsInstance<ChatItem.Tool>().single()
        assertEquals("README.md", tool.output)
        assertTrue(s.items.any { it is ChatItem.Thinking })
        assertTrue(!s.runActive)
    }

    @Test fun permissionDenyReachesTheAgent() = runChat { _, _, chat ->
        chat.send("perm")
        val card = chat.awaitState { st -> st.items.any { it is ChatItem.Permission } }
            .items.filterIsInstance<ChatItem.Permission>().single()
        assertTrue(card.buttons.any { it.data.endsWith(":deny") })
        assertTrue(chat.respondPermission(card, "deny"))
        val s = chat.awaitState { st -> st.items.any { it is ChatItem.RunEnded } }
        assertTrue(s.items.filterIsInstance<ChatItem.Assistant>().any { it.text == "decision=deny" })
    }

    @Test fun droppedConnectionResumesWithoutLosingOrDuplicating() = runChat { _, bridge, chat ->
        chat.send("slow")
        chat.awaitState { st -> st.items.any { it is ChatItem.Assistant && it.text.startsWith("first") } }
        proxy.dropAll() // network blip mid-run: "second" + run_done happen while we're away
        withTimeout(5_000) { bridge.state.first { it !is BridgeState.Connected } }
        val s = chat.awaitState { st -> st.items.any { it is ChatItem.RunEnded } }
        val assistants = s.items.filterIsInstance<ChatItem.Assistant>()
        assertEquals(listOf("first second"), assistants.map { it.text })
        assertEquals(1, s.items.count { it is ChatItem.RunEnded })
        assertTrue(bridge.isConnected)
        // Same session keeps working after the resume.
        chat.send("again")
        chat.awaitState { st -> st.items.count { it is ChatItem.RunEnded } == 2 }
    }
}
