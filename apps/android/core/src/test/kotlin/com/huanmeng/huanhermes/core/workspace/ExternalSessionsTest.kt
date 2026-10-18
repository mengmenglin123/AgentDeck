package com.huanmeng.huanhermes.core.workspace

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Test

class ExternalSessionsTest {
    @Test fun parsesListAndTranscript() {
        val list = ExternalSessions.parseList(Json.parseToJsonElement(
            """{"sessions":[{"id":"abc","title":"修复","cwd":".","messages":3,"updated_at":1.5,"resume_command":"claude --resume abc"},{"title":"no id"}]}""",
        ).jsonObject)
        assertEquals(listOf("abc"), list.map { it.id })
        assertEquals("claude --resume abc", list[0].resumeCommand)
        val rows = ExternalSessions.parseTranscript(Json.parseToJsonElement(
            """{"transcript":[{"role":"user","content":"hi"},{"role":"tool","content":"Edit"},{"role":"x"}]}""",
        ).jsonObject)
        assertEquals(listOf("user", "tool"), rows.map { it.role })
        assertEquals("/external-sessions/a%20b?project=p", ExternalSessions.url("p", "a b"))
    }
}
