package com.huanmeng.huanhermes.core.extensions

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExtensionsTest {
    @Test fun parsesServersSkillsAndTools() {
        val data = Json.parseToJsonElement("""{"servers":[{"name":"gh","kind":"http","target":"https://x/mcp","scope":"project","editable":true,"tools":["a","b"],"secret_keys":["Authorization"]},{"name":"old","enabled":false}]}""") as JsonObject
        val s = Extensions.parseServers(data)
        assertEquals(listOf("gh", "old"), s.map { it.name })
        assertTrue(s[0].editable); assertEquals(2, s[0].tools.size); assertEquals(false, s[1].enabled)
        val skills = Extensions.parseSkills(Json.parseToJsonElement("""{"skills":[{"name":"pdf","description":"d","scope":"user"}]}""") as JsonObject)
        assertEquals("user", skills[0].scope)
        assertEquals("echo", Extensions.parseTools(Json.parseToJsonElement("""{"tools":[{"name":"echo"}]}""") as JsonObject)[0].name)
    }

    @Test fun specsAndConnectors() {
        assertEquals("npx" to listOf("-y", "pkg", "a b"), Extensions.splitCommand("npx -y pkg \"a b\""))
        assertEquals(mapOf("A" to "1", "B" to "x=y"), Extensions.parsePairs("A=1\n bad\nB=x=y\n"))
        assertEquals("请填写启动命令", McpSpec("x").problem())
        assertNull(McpSpec("x", command = "npx").problem())
        val gh = Extensions.connector("github")!!.build(mapOf("token" to "T"))
        assertEquals("Bearer T", gh.headers["Authorization"])
        assertTrue(gh.toJson().toString().contains("api.githubcopilot.com"))
        val fs = Extensions.connector("filesystem")!!.build(mapOf("dir" to "/data"))
        assertEquals(listOf("-y", "@modelcontextprotocol/server-filesystem", "/data"), fs.args)
        assertTrue(Extensions.connectors.map { it.id }.toSet().size == Extensions.connectors.size)
        assertNull(Extensions.skillNameProblem("deploy-check"))
    }
}
