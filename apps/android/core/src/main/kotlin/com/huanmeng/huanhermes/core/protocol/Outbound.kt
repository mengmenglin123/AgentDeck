package com.huanmeng.huanhermes.core.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

object Capabilities {
    /** What Flutter 0.1.206 declares; the v1 baseline every Host understands. */
    val LEGACY = listOf("text", "buttons", "typing", "preview", "terminal")
    const val SEQ = "seq"
    const val RESUME = "resume"
    const val SESSION_STATUS = "session_status"
    val V2 = listOf(SEQ, RESUME, SESSION_STATUS)
    val NATIVE = LEGACY + V2
}

/** App -> Host frame builders (shapes match docs/protocol/schema). */
object Outbound {
    fun shortId(prefix: String) = "$prefix-" + UUID.randomUUID().toString().replace("-", "").take(12)

    fun register(platform: String, deviceId: String, version: String, capabilities: List<String> = Capabilities.NATIVE) =
        buildJsonObject {
            put("type", "register")
            put("platform", platform)
            put("capabilities", JsonArray(capabilities.map(::JsonPrimitive)))
            put("metadata", buildJsonObject {
                put("version", version)
                put("device_id", deviceId)
                put("protocol", 2)
            })
        }

    fun message(
        sessionKey: String,
        content: String,
        project: String?,
        msgId: String = shortId("msg"),
        replyCtx: String = shortId("ctx"),
        userId: String = "user",
        userName: String = "User",
    ) = buildJsonObject {
        put("type", "message")
        put("msg_id", msgId)
        put("session_key", sessionKey)
        if (!project.isNullOrBlank()) put("project", project)
        put("user_id", userId)
        put("user_name", userName)
        put("content", content)
        put("reply_ctx", replyCtx)
        put("images", buildJsonArray { })
        put("files", buildJsonArray { })
        put("audio", JsonNull)
    }

    fun cancel(sessionKey: String, replyCtx: String?, project: String?) = buildJsonObject {
        put("type", "cancel")
        put("session_key", sessionKey)
        put("reply_ctx", replyCtx.orEmpty())
        if (!project.isNullOrBlank()) put("project", project)
    }

    fun cardAction(sessionKey: String, action: String, replyCtx: String?, project: String?) = buildJsonObject {
        put("type", "card_action")
        put("session_key", sessionKey)
        put("action", action)
        put("reply_ctx", replyCtx.orEmpty())
        if (!project.isNullOrBlank()) put("project", project)
    }

    fun ping(ts: Long) = buildJsonObject { put("type", "ping"); put("ts", ts) }

    fun previewAck(refId: String, handle: String) = buildJsonObject {
        put("type", "preview_ack"); put("ref_id", refId); put("preview_handle", handle)
    }

    fun resume(sessionKey: String, afterSeq: Long, epoch: String?) = buildJsonObject {
        put("type", "resume")
        put("session_key", sessionKey)
        put("after_seq", afterSeq)
        if (epoch != null) put("epoch", epoch)
    }

    fun sessionStatus(sessionKey: String) = buildJsonObject {
        put("type", "session_status"); put("session_key", sessionKey)
    }

    /**
     * Maps a short decision (`allow`/`deny`/`allow_all`) onto the card's exact
     * button data (`perm:<id>:<decision>`), which is all the Host accepts.
     */
    fun resolvePermissionAction(decision: String, buttons: List<FrameButton>): String {
        val d = decision.trim()
        if (d.contains(':')) return d
        return buttons.firstOrNull { it.data == d || it.data.endsWith(":$d") }?.data ?: d
    }
}

fun JsonObject.encode(): String = toString()
