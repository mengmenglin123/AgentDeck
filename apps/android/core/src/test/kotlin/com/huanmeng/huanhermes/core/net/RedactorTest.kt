package com.huanmeng.huanhermes.core.net

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class RedactorTest {
    @Test fun queryTokensBearerAndSecretsAreMasked() {
        val secret = "s3cr3t value&x"
        val text = "Failed ws://h:9810/bridge/ws?token=${HostConfig.encode(secret)} and ?a=1&mgmt_token=zz " +
            "Authorization: Bearer abc.def-123 raw=$secret plus=${java.net.URLEncoder.encode(secret, "UTF-8")}"
        val out = Redactor.redact(text, listOf(secret))
        for (leak in listOf("s3cr3t", "zz ", "abc.def-123")) assertFalse(out, out.contains(leak))
        assertEquals("x ws://h/bridge/ws?token=***", Redactor.redact("x ws://h/bridge/ws?token=abc"))
    }

    @Test fun exceptionsAreRedacted() {
        val e = java.io.IOException("Failed to connect to /10.0.0.2:9810 (ws://10.0.0.2:9810/bridge/ws?token=tok123)")
        assertFalse(Redactor.redact(e, listOf("tok123")).contains("tok123"))
        assertEquals("IllegalStateException", Redactor.redact(IllegalStateException()))
    }

    @Test fun shortSecretsAreNotUsedForBlindReplacement() {
        assertEquals("abc", Redactor.redact("abc", listOf("a")))
    }
}
