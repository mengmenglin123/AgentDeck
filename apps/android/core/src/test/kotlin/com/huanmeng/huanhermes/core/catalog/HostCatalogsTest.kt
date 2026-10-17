package com.huanmeng.huanhermes.core.catalog

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HostCatalogsTest {
    private fun j(s: String): JsonObject = Json.parseToJsonElement(s).jsonObject

    @Test fun agentsAndPlatforms() {
        val e = HostCatalogs.parse(CatalogKind.AGENTS, j("""{"agents":[{"id":"cc","name":"Claude Code","type":"claude-code","model":"sonnet","status":"ok","capabilities":["stream"]}],"platforms":[{"type":"bridge","connected":true}]}"""))
        assertEquals(listOf("Claude Code", "bridge"), e.map { it.title })
        assertEquals("claude-code · sonnet", e[0].subtitle)
        assertEquals("ok", e[0].level)
        assertTrue("stream" in e[0].chips)
    }

    @Test fun mcpToolsAcceptStringsAndObjects() {
        val data = j("""{"servers":[{"name":"fs","kind":"stdio","enabled":false,"tools":["read",{"name":"write"}]}]}""")
        val mcp = HostCatalogs.parse(CatalogKind.MCP, data).single()
        assertEquals("off", mcp.level)
        assertTrue("2 个工具" in mcp.chips)
        assertEquals(listOf("read", "write"), HostCatalogs.parse(CatalogKind.TOOLS, data).map { it.title })
    }

    @Test fun auditLogsAndFilter() {
        val audit = HostCatalogs.parse(CatalogKind.AUDIT, j("""{"records":[{"action":"decided","request_id":"r1","decision":"deny","scope":"shell","session_key":"s","ts":3}]}"""))
        assertEquals("拒绝 · shell", audit.single().title)
        assertEquals("error", audit.single().level)
        val logs = HostCatalogs.parse(CatalogKind.LOGS, j("""{"logs":[{"ts":1,"level":"info","message":"hello","source":"host"},{"ts":2,"level":"warn","message":"disk","source":"fs"}]}"""))
        assertEquals(listOf("disk"), HostCatalogs.filter(logs, "WARN").map { it.title })
        assertEquals(2, HostCatalogs.filter(logs, " ").size)
    }

    @Test fun missingFieldsNeverThrow() {
        CatalogKind.entries.forEach { assertEquals(emptyList<CatalogEntry>(), HostCatalogs.parse(it, j("{}"))) }
        val mem = HostCatalogs.parse(CatalogKind.MEMORY, j("""{"memories":[{"id":"m1","content":null,"updated_at":"x"}]}""")).single()
        assertEquals("m1", mem.title)
        assertEquals(null, mem.ts)
    }

    @Test fun urlsAndStatus() {
        assertEquals("/skills?project=a%20b", CatalogKind.SKILLS.url("a b"))
        assertEquals("/logs?limit=200&level=warn", CatalogKind.LOGS.url("p", mapOf("level" to "warn")))
        assertEquals("/cron", CatalogKind.CRON.url("p"))
        val rows = HostCatalogs.statusRows(j("""{"version":"1.0","uptime_seconds":3700,"active_sessions":2}"""))
        assertEquals(listOf("版本" to "1.0", "运行时间" to "1 小时 1 分", "运行中" to "2"), rows)
    }
}
