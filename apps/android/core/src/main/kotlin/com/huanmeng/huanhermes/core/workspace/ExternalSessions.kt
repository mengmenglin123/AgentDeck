package com.huanmeng.huanhermes.core.workspace

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/** Claude Code CLI sessions found on the Host (capability `external_sessions`), read-only. */
data class ExternalSession(
    val id: String,
    val title: String,
    val cwd: String,
    val messages: Long,
    val updatedAt: Double?,
    val resumeCommand: String,
)

data class ExternalRow(val role: String, val content: String)

object ExternalSessions {
    fun url(project: String?, id: String? = null): String =
        Workspace.url(if (id == null) "/external-sessions" else "/external-sessions/" + com.huanmeng.huanhermes.core.net.HostConfig.encode(id), project)

    fun parseList(data: JsonObject): List<ExternalSession> =
        (data["sessions"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::parseOne) }

    fun parseOne(o: JsonObject): ExternalSession? {
        val id = o.s("id") ?: return null
        return ExternalSession(
            id, o.s("title") ?: id.take(8), o.s("cwd") ?: ".", (o["messages"] as? JsonPrimitive)?.longOrNull ?: 0,
            (o["updated_at"] as? JsonPrimitive)?.doubleOrNull, o.s("resume_command") ?: "claude --resume $id",
        )
    }

    fun parseTranscript(data: JsonObject): List<ExternalRow> =
        (data["transcript"] as? JsonArray).orEmpty().mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            val content = o.s("content") ?: return@mapNotNull null
            ExternalRow(o.s("role") ?: "assistant", content)
        }

    private fun JsonObject.s(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull
}
