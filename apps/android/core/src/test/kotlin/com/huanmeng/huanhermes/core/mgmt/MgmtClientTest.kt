package com.huanmeng.huanhermes.core.mgmt

import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.net.HostError
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class MgmtClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: MgmtClient

    @Before fun setUp() {
        server = MockWebServer().apply { start() }
        client = MgmtClient(HostConfig(host = server.hostName, mgmtPort = server.port, bridgeToken = "b-secret", mgmtToken = "m-secret-123"))
    }

    @After fun tearDown() = server.shutdown()

    private fun json(body: String, code: Int = 200, contentType: String = "application/json") =
        MockResponse().setResponseCode(code).setHeader("Content-Type", contentType).setBody(Buffer().write(body.toByteArray(Charsets.UTF_8)))

    @Test fun decodesUtf8BytesWithoutCharsetAndDespiteWrongCharset() = runBlocking {
        server.enqueue(json("""{"ok":true,"data":{"version":"中文版本 🚀"}}""", contentType = "application/json"))
        assertEquals("中文版本 🚀", client.status()["version"]!!.jsonPrimitive.content)
        server.enqueue(json("""{"ok":true,"data":{"version":"会话"}}""", contentType = "text/plain; charset=ISO-8859-1"))
        assertEquals("会话", client.status()["version"]!!.jsonPrimitive.content)
        val req = server.takeRequest()
        assertEquals("Bearer m-secret-123", req.getHeader("Authorization"))
        assertEquals("/api/v1/status", req.path)
    }

    @Test fun proxyHtmlErrorIsShortAndReadable() = runBlocking {
        val html = "<html><head><title>502 Bad Gateway</title><style>body{}</style></head><body><center><h1>502 Bad Gateway</h1></center>" +
            "<hr><center>nginx</center>" + "x".repeat(5000) + "</body></html>"
        server.enqueue(MockResponse().setResponseCode(502).setHeader("Content-Type", "text/html").setBody(html))
        try {
            client.status(); fail()
        } catch (e: HostError.Http) {
            assertEquals(502, e.status)
            val m = e.message!!
            assertTrue(m, m.startsWith("HTTP 502: 502 Bad Gateway"))
            assertFalse(m.contains("<"))
            assertTrue(m.length <= "HTTP 502: ".length + MgmtClient.ERROR_BODY_LIMIT + 1)
        }
    }

    @Test fun nonJsonSuccessBodyIsAProtocolError() = runBlocking {
        server.enqueue(MockResponse().setBody("<html>captive portal</html>"))
        try { client.status(); fail() } catch (e: HostError.Protocol) { assertTrue(e.message!!.contains("captive portal")) }
    }

    @Test fun unauthorizedIsAuthAndErrorsNeverEchoTokens() = runBlocking {
        server.enqueue(json("""{"ok":false,"error":"bad token m-secret-123"}""", code = 401))
        try { client.status(); fail() } catch (e: HostError.Auth) { assertFalse(e.message!!.contains("m-secret-123")) }
        server.enqueue(json("""{"ok":false,"error":"nope"}""", code = 200))
        try { client.status(); fail() } catch (e: HostError.Protocol) { assertEquals("nope", e.message) }
    }

    @Test fun connectionFailureIsRedactedDisconnected() = runBlocking {
        val dead = MgmtClient(HostConfig(host = "127.0.0.1", mgmtPort = 1, mgmtToken = "m-secret-123", bridgeToken = "b"))
        try { dead.status(); fail() } catch (e: HostError.Disconnected) { assertFalse(e.message!!.contains("m-secret-123")) }
    }

    @Test fun detectsFlatDialectAfterProject404AndEncodesPaths() = runBlocking {
        server.enqueue(json("""{"ok":false,"error":"not found"}""", code = 404))
        server.enqueue(json("""{"ok":true,"data":{"sessions":[{"id":"1","session_key":"huan:d:1","title":"会话一","running":true}]}}"""))
        val list = client.sessions("my proj")
        assertEquals("flat", client.dialect)
        assertEquals("会话一", list.single().displayTitle)
        assertEquals("my proj", list.single().project)
        assertTrue(list.single().running)
        assertEquals("/api/v1/projects/my%20proj/sessions", server.takeRequest().path)
        assertEquals("/api/v1/sessions?project=my%20proj", server.takeRequest().path)
    }

    @Test fun projectDialectAndSessionDetail() = runBlocking {
        server.enqueue(json("""{"ok":true,"data":{"sessions":[]}}"""))
        client.sessions("codex")
        assertEquals("project", client.dialect)
        server.enqueue(json("""{"ok":true,"data":{"transcript":[{"role":"user","content":"hi"},{"role":"assistant","content":"yo"}],"mode":"plan","running":false,"last_seq":7}}"""))
        val d = client.sessionDetail("a/b", "codex")
        assertEquals(listOf("user", "assistant"), d.transcript.map { it.role })
        assertEquals(7L, d.lastSeq)
        server.takeRequest()
        assertEquals("/api/v1/projects/codex/sessions/a%2Fb", server.takeRequest().path)
    }

    @Test fun searchFilesDropsUnsafePaths() = runBlocking {
        server.enqueue(json("""{"ok":true,"data":{"files":[{"path":"src/Main.kt"},{"path":"../etc/passwd"},{"path":"/abs"},"docs/a b.md"]}}"""))
        assertEquals(listOf("src/Main.kt", "docs/a b.md"), client.searchFiles("codex", "ma in", 20))
        val req = server.takeRequest()
        assertEquals("/api/v1/files/search?q=ma%20in&limit=20&project=codex", req.path)
    }

    @Test fun pushRegistrationBodies() = runBlocking {
        server.enqueue(json("""{"ok":true,"data":{"registered":true}}"""))
        server.enqueue(json("""{"ok":true,"data":{"removed":true}}"""))
        client.registerPush("dev1", "https://ntfy.sh/upX")
        client.unregisterPush("dev1")
        val reg = server.takeRequest()
        assertEquals("POST", reg.method); assertEquals("/api/v1/push/register", reg.path)
        assertTrue(reg.body.readUtf8().contains("\"endpoint\":\"https://ntfy.sh/upX\""))
        val del = server.takeRequest()
        assertEquals("DELETE", del.method)
        assertTrue(del.body.readUtf8().contains("dev1"))
    }
}
