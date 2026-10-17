package com.huanmeng.huanhermes.core.net

import com.huanmeng.huanhermes.core.mgmt.MgmtClient
import com.huanmeng.huanhermes.core.mgmt.OkHttpEngine
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class PairingTest {
    @Test fun parsesCodeNameAndPin() {
        val link = PairingLink.parse("huanhermes://connect?host=10.0.0.5&bridge=9810&mgmt=9820&tls=1&code=ABCD2345&name=dev%20box&pin=sha256/AAA%3D")!!
        assertEquals("ABCD2345", link.code)
        assertEquals("dev box", link.name)
        assertEquals("AAA=", link.config.certPin)
        assertTrue(link.needsClaim)
        assertTrue(link.config.toPairingUri().contains("pin=AAA%3D"))
        assertNull(PairingLink.parse("https://example.com"))
        val plain = PairingLink.parse("huanhermes://connect?host=h&bridge_token=a&mgmt_token=b")!!
        assertEquals(false, plain.needsClaim)
    }

    @Test fun claimTradesCodeForTokens() = runBlocking {
        val server = MockWebServer().apply { start() }
        try {
            server.enqueue(MockResponse().setBody("""{"ok":true,"data":{"bridge_token":"bt","mgmt_token":"mt","bridge_port":9811,"mgmt_port":${server.port}}}"""))
            server.enqueue(MockResponse().setResponseCode(403).setBody("""{"ok":false,"error":"invalid"}"""))
            val link = PairingLink.parse("huanhermes://connect?host=${server.hostName}&mgmt=${server.port}&code=ABCD2345")!!
            val cfg = Pairing.claim(link, OkHttpEngine(), "Pixel 9")
            assertEquals("bt", cfg.bridgeToken); assertEquals("mt", cfg.mgmtToken); assertEquals(9811, cfg.bridgePort)
            val req = server.takeRequest()
            assertEquals("/api/v1/pairing/claim", req.path)
            assertNull(req.getHeader("Authorization"))
            val body = req.body.readUtf8()
            assertTrue(body.contains("ABCD2345")); assertTrue(body.contains(link.config.deviceId))
            try { Pairing.claim(link, OkHttpEngine(), "x"); fail() } catch (e: HostError.Auth) { assertTrue(e.message!!.contains("过期")) }
        } finally { server.shutdown() }
    }

    @Test fun pinnedSelfSignedTlsAcceptsMatchingPinOnly() = runBlocking {
        val held = HeldCertificate.Builder().commonName("not-the-hostname").addSubjectAlternativeName("example.invalid").build()
        val serverCerts = HandshakeCertificates.Builder().heldCertificate(held).build()
        val server = MockWebServer().apply { useHttps(serverCerts.sslSocketFactory(), false); start() }
        try {
            val pin = Pinning.spkiSha256(held.certificate)
            val base = OkHttpClient()
            val good = HostConfig(host = server.hostName, mgmtPort = server.port, useTls = true, mgmtToken = "t", bridgeToken = "b", certPin = pin)
            server.enqueue(MockResponse().setBody("""{"ok":true,"data":{"version":"x"}}"""))
            MgmtClient(good, OkHttpEngine(Pinning.clientFor(base, good))).status()
            val bad = good.copy(certPin = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
            server.enqueue(MockResponse().setBody("{}"))
            try { MgmtClient(bad, OkHttpEngine(Pinning.clientFor(base, bad))).status(); fail("wrong pin accepted") } catch (e: Exception) { }
            // Unpinned TLS keeps normal trust: a self-signed cert is rejected.
            val unpinned = good.copy(certPin = "")
            try { MgmtClient(unpinned, OkHttpEngine(Pinning.clientFor(base, unpinned))).status(); fail("self-signed accepted without pin") } catch (e: Exception) { }
        } finally { server.shutdown() }
    }
}
