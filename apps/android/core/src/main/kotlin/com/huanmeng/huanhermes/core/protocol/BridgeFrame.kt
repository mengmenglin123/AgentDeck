package com.huanmeng.huanhermes.core.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

/** A permission/action button: `data` is what goes back in `card_action.action`. */
data class FrameButton(val text: String, val data: String)

/**
 * Typed view of a Host -> App Bridge frame (see docs/protocol/schema).
 * Every frame keeps its raw JSON; unknown types become [Unknown] instead of failing.
 */
sealed class BridgeFrame {
    abstract val raw: JsonObject
    val type: String get() = raw.str("type").orEmpty()
    val sessionKey: String? get() = raw.text("session_key")
    val replyCtx: String? get() = raw.text("reply_ctx")
    /** Protocol v2 sequence, only present when negotiated. */
    val seq: Long? get() = raw.long("seq")
    val replayed: Boolean get() = raw.bool("replayed")

    data class RegisterAck(
        override val raw: JsonObject,
        val ok: Boolean,
        val error: String?,
        val protocol: Int,
        val capabilities: Set<String>,
        val epoch: String?,
    ) : BridgeFrame()

    data class Pong(override val raw: JsonObject) : BridgeFrame()
    data class ReplyStream(override val raw: JsonObject, val delta: String, val fullText: String?, val done: Boolean) : BridgeFrame()
    data class Reply(override val raw: JsonObject, val content: String, val format: String?, val isError: Boolean, val errorCode: String?) : BridgeFrame()
    data class Thinking(override val raw: JsonObject, val content: String) : BridgeFrame()
    data class ToolCall(override val raw: JsonObject, val name: String, val input: String, val callId: String?, val status: String?) : BridgeFrame()
    data class ToolResult(override val raw: JsonObject, val name: String, val output: String, val callId: String?, val status: String?, val isError: Boolean) : BridgeFrame()

    /** `buttons` and `card` frames: a permission request when it has buttons. */
    data class Card(override val raw: JsonObject, val content: String, val buttons: List<FrameButton>, val permissionId: String?) : BridgeFrame()
    data class RunDone(override val raw: JsonObject, val status: String, val exitCode: Long?, val summary: String?) : BridgeFrame()
    data class Typing(override val raw: JsonObject, val active: Boolean) : BridgeFrame()
    data class PreviewStart(override val raw: JsonObject, val refId: String) : BridgeFrame()
    data class UpdateMessage(override val raw: JsonObject, val content: String) : BridgeFrame()
    data class Error(override val raw: JsonObject, val message: String, val code: String?) : BridgeFrame()
    data class ResumeAck(override val raw: JsonObject, val lastSeq: Long, val replayedCount: Long) : BridgeFrame()
    data class ResyncRequired(override val raw: JsonObject, val lastSeq: Long) : BridgeFrame()
    data class SessionStatus(override val raw: JsonObject, val alive: Boolean, val running: Boolean, val lastSeq: Long) : BridgeFrame()

    /** Any `terminal_*` frame; the terminal screen (M4) interprets them. */
    data class Terminal(override val raw: JsonObject) : BridgeFrame() {
        val streamId: String? get() = raw.text("stream_id")
    }

    /** Forward compatibility: rendered as a placeholder, never a crash. */
    data class Unknown(override val raw: JsonObject) : BridgeFrame()

    companion object {
        fun parse(text: String): BridgeFrame? {
            val element = runCatching { ProtocolJson.parseToJsonElement(text) }.getOrNull() ?: return null
            val obj = element as? JsonObject ?: return null
            return from(obj)
        }

        fun from(o: JsonObject): BridgeFrame = when (o.str("type")) {
            "register_ack" -> RegisterAck(
                o, ok = o.bool("ok"), error = o.text("error"),
                protocol = o.long("protocol")?.toInt() ?: 1,
                capabilities = (o["capabilities"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }?.toSet().orEmpty(),
                epoch = o.text("epoch"),
            )
            "pong" -> Pong(o)
            "reply_stream" -> ReplyStream(o, o.str("delta").orEmpty(), o.str("full_text"), o.bool("done"))
            "reply" -> Reply(o, o.str("content").orEmpty(), o.text("format"), isErrorFlag(o["error"]), o.text("error_code"))
            "thinking" -> Thinking(o, (o.str("content") ?: o.str("text")).orEmpty())
            "tool_call" -> ToolCall(o, o.text("name") ?: "tool", o["input"].display(), o.text("call_id"), o.text("status"))
            "tool_result" -> ToolResult(
                o, o.text("name") ?: "tool", (o["output"] ?: o["content"]).display(), o.text("call_id"), o.text("status"),
                o.bool("is_error") || o.text("status") == "error",
            )
            "buttons", "card" -> Card(
                o, (o.text("content") ?: o.text("text") ?: o.text("title") ?: if (o.str("type") == "buttons") "需要权限" else "card"),
                flattenButtons(o["buttons"]), o.text("permission_id"),
            )
            "run_done" -> RunDone(o, o.text("status") ?: "completed", o.long("exit_code"), o.text("summary"))
            "typing_start" -> Typing(o, true)
            "typing_stop" -> Typing(o, false)
            "preview_start" -> PreviewStart(o, o.str("ref_id").orEmpty())
            "update_message" -> UpdateMessage(o, o.str("content").orEmpty())
            "error" -> Error(o, (o.text("error") ?: o.text("message") ?: "未知错误"), o.text("error_code"))
            "resume_ack" -> ResumeAck(o, o.long("last_seq") ?: 0, o.long("replayed") ?: 0)
            "resync_required" -> ResyncRequired(o, o.long("last_seq") ?: 0)
            "session_status" -> SessionStatus(o, o.bool("alive"), o.bool("running"), o.long("last_seq") ?: 0)
            else -> if (o.str("type")?.startsWith("terminal_") == true) Terminal(o) else Unknown(o)
        }

        /** Buttons arrive flat (`[{text,data}]`) or as rows (`[[…]]`). */
        fun flattenButtons(raw: JsonElement?): List<FrameButton> {
            val out = mutableListOf<FrameButton>()
            fun add(e: JsonElement) {
                val b = e as? JsonObject ?: return
                val data = b.str("data") ?: return
                out += FrameButton(b.str("text") ?: data.substringAfterLast(':'), data)
            }
            (raw as? JsonArray)?.forEach { row -> if (row is JsonArray) row.forEach(::add) else add(row) }
            return out
        }

        private fun isErrorFlag(e: JsonElement?): Boolean = when (e) {
            null -> false
            is JsonPrimitive -> if (e.isString) e.content.isNotBlank() else e.content == "true"
            else -> true
        }
    }
}

/** True for frames that report a failure (acks with `"error": ""` are not). */
fun BridgeFrame.isFailure(): Boolean = when (this) {
    is BridgeFrame.Error -> true
    is BridgeFrame.Reply -> isError
    is BridgeFrame.RegisterAck -> !ok
    else -> false
}

internal fun JsonElement.asObject(): JsonObject = jsonObject
