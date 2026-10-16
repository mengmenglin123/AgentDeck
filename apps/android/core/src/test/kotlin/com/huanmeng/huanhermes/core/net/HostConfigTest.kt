package com.huanmeng.huanhermes.core.net

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HostConfigTest {
    private val base = HostConfig(host = "10.0.0.2", bridgeToken = "tok", mgmtToken = "mtok", deviceId = "d")

    @Test fun tokenIsQueryEncoded() {
        val c = base.copy(bridgeToken = "a&b=c d/é+%")
        assertEquals("ws://10.0.0.2:9810/bridge/ws?token=a%26b%3Dc%20d%2F%C3%A9%2B%25", c.bridgeWsUrl)
        assertEquals("ws://10.0.0.2:9810/bridge/ws?token=***", c.bridgeWsUrlRedacted)
    }

    @Test fun ipv6HostsAreBracketed() {
        val c = base.copy(host = "fe80::1", useTls = true)
        assertEquals("wss://[fe80::1]:9810/bridge/ws?token=tok", c.bridgeWsUrl)
        assertEquals("https://[fe80::1]:9820/api/v1", c.mgmtBaseUrl)
        assertEquals("http://[::1]:9820/api/v1", base.copy(host = "[::1]").mgmtBaseUrl)
        assertEquals("http://host.lan:9820/api/v1", base.copy(host = " host.lan ").mgmtBaseUrl)
    }

    @Test fun validationCoversPortsHostAndTokens() {
        assertTrue(base.validate().isEmpty())
        assertTrue(base.copy(bridgePort = 0).validate().any { "Bridge" in it })
        assertTrue(base.copy(mgmtPort = 65536).validate().any { "Management" in it })
        assertTrue(base.copy(host = "").validate().isNotEmpty())
        assertTrue(base.copy(host = "a b").validate().isNotEmpty())
        assertTrue(base.copy(mgmtToken = "").validate().isNotEmpty())
    }

    @Test fun pairingUriRoundTripsAndRejectsBadPorts() {
        val parsed = HostConfig.parsePairingUri(base.copy(host = "fe80::1").toPairingUri(includeTokens = true))!!
        assertEquals("fe80::1", parsed.host)
        assertEquals("tok", parsed.bridgeToken)
        assertEquals(9810, parsed.bridgePort)
        for (bad in listOf("0", "65536", "-1", "abc", "99999999999")) {
            assertNull(bad, HostConfig.parsePairingUri("huanhermes://connect?host=h&bridge=$bad&mgmt=9820"))
            assertNull(bad, HostConfig.parsePairingUri("huanhermes://connect?host=h&bridge=9810&mgmt=$bad"))
        }
        assertEquals(1, HostConfig.parsePairingUri("huanhermes://connect?host=h&bridge=1&mgmt=65535")!!.bridgePort)
        assertEquals(9810, HostConfig.parsePairingUri("huanhermes://connect?host=h&mgmt=9820")!!.bridgePort)
        assertNull(HostConfig.parsePairingUri("huanhermes://connect?bridge=1"))
        assertNull(HostConfig.parsePairingUri("https://example.com"))
        assertTrue(HostConfig.parsePairingUri("huanhermes://connect?host=h&bridge=1&tls=1")!!.useTls)
        assertEquals("a b", HostConfig.parsePairingUri("huanhermes://connect?host=h&bridge_token=a%20b")!!.bridgeToken)
    }

    @Test fun toStringAndPublicUriNeverIncludeTokens() {
        assertFalse(base.toString().contains("tok"))
        assertFalse(base.toPairingUri().contains("tok"))
    }
}
