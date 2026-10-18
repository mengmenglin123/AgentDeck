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
    /** Plan approval and AskUserQuestion cards (`card.kind`). */
    const val PLAN_CARDS = "plan_cards"
    /** Token / context usage on `run_done`. */
    const val USAGE = "usage"
    val V2 = listOf(SEQ, RESUME, SESSION_STATUS, PLAN_CARDS, USAGE)
    val NATIVE = LEGACY + V2
}

/** A small attachment (`images[]` / `files[]` element). */
data class Attachment(val name: String, val mime: String, val bytes: ByteArray) {
    val isImage: Boolean get() = mime.startsWith("image/")
    val sizeBytes: Int get() = bytes.size
    override fun equals(other: Any?) = other is Attachment && other.name == name && other.mime == mime && other.bytes.contentEquals(bytes)
    override fun hashCode() = name.hashCode() * 31 + bytes.contentHashCode()

    companion object {
        const val MAX_ITEMS = 4
        const val MAX_ITEM_BYTES = 5 * 1024 * 1024
        const val MAX_TOTAL_BYTES = 10 * 1024 * 1024

        /** Why [list] cannot be sent (protocol limits), or null when it can. */
        fun problem(list: List<Attachment>): String? = when {
            list.size > MAX_ITEMS -> "最多 $MAX_ITEMS 个附件"
            list.any { it.sizeBytes > MAX_ITEM_BYTES } -> "单个附件不能超过 5 MB"
            list.sumOf { it.sizeBytes } > MAX_TOTAL_BYTES -> "附件总计不能超过 10 MB"
            else -> null
        }
    }
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
        attachments: List<Attachment> = emptyList(),
    ) = buildJsonObject {
        put("type", "message")
        put("msg_id", msgId)
        put("session_key", sessionKey)
        if (!project.isNullOrBlank()) put("project", project)
        put("user_id", userId)
        put("user_name", userName)
        put("content", content)
        put("reply_ctx", replyCtx)
        fun encode(a: Attachment) = buildJsonObject {
            put("name", a.name); put("mime", a.mime); put("size_bytes", a.sizeBytes)
            put("data_base64", java.util.Base64.getEncoder().encodeToString(a.bytes))
        }
        put("images", JsonArray(attachments.filter { it.isImage }.map(::encode)))
        put("files", JsonArray(attachments.filterNot { it.isImage }.map(::encode)))
        put("audio", JsonNull)
    }

    fun cancel(sessionKey: String, replyCtx: String?, project: String?) = buildJsonObject {
        put("type", "cancel")
        put("session_key", sessionKey)
        put("reply_ctx", replyCtx.orEmpty())
        if (!project.isNullOrBlank()) put("project", project)
    }

    fun cardAction(
        sessionKey: String,
        action: String,
        replyCtx: String?,
        project: String?,
        text: String? = null,
        answers: Map<String, List<String>>? = null,
    ) = buildJsonObject {
        put("type", "card_action")
        put("session_key", sessionKey)
        put("action", action)
        put("reply_ctx", replyCtx.orEmpty())
        if (!project.isNullOrBlank()) put("project", project)
        if (!text.isNullOrBlank()) put("text", text)
        if (!answers.isNullOrEmpty()) put("answers", buildJsonObject {
            answers.forEach { (k, v) -> put(k, JsonArray(v.map(::JsonPrimitive))) }
        })
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
