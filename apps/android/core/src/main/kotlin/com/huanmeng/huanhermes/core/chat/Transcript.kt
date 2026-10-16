package com.huanmeng.huanhermes.core.chat

import com.huanmeng.huanhermes.core.mgmt.TranscriptRow
import com.huanmeng.huanhermes.core.protocol.BridgeFrame
import com.huanmeng.huanhermes.core.protocol.FrameButton

/** One row in the chat list. [id] is stable for list keys and diffing. */
sealed class ChatItem {
    abstract val id: Long

    data class User(override val id: Long, val text: String, val msgId: String? = null, val queued: Boolean = false) : ChatItem()
    data class Assistant(override val id: Long, val text: String, val streaming: Boolean, val replyCtx: String?, val format: String?) : ChatItem()
    data class Thinking(override val id: Long, val text: String) : ChatItem()

    /** A tool call and (once it arrives) its result; collapsed by default in the UI. */
    data class Tool(
        override val id: Long,
        val name: String,
        val input: String,
        val output: String? = null,
        val callId: String? = null,
        val status: String? = null,
        val isError: Boolean = false,
    ) : ChatItem() {
        val finished: Boolean get() = output != null
    }

    data class Permission(
        override val id: Long,
        val text: String,
        val buttons: List<FrameButton>,
        val replyCtx: String?,
        val permissionId: String?,
        /** `allow` / `allow_all` / `deny` once answered from this device. */
        val decision: String? = null,
    ) : ChatItem()

    data class Notice(override val id: Long, val text: String) : ChatItem()
    data class Failure(override val id: Long, val text: String, val code: String? = null) : ChatItem()
    data class RunEnded(override val id: Long, val status: String, val exitCode: Long? = null) : ChatItem()

    /** Forward compatibility: an event type this version does not know. */
    data class Unsupported(override val id: Long, val type: String) : ChatItem()
}

/**
 * Pure reducer from Bridge frames to [ChatItem]s. Immutable: each call returns
 * a new [Transcript]. Session filtering happens before frames reach it.
 */
data class Transcript(
    val items: List<ChatItem> = emptyList(),
    private val streamingId: Long? = null,
    private val nextId: Long = 1,
) {
    val streaming: Boolean get() = streamingId != null

    fun addUser(text: String, msgId: String?, queued: Boolean): Transcript =
        copy(items = items + ChatItem.User(nextId, text, msgId, queued), streamingId = null, nextId = nextId + 1)

    fun markSent(msgId: String): Transcript = copy(items = items.map {
        if (it is ChatItem.User && it.msgId == msgId) it.copy(queued = false) else it
    })

    fun markDecision(itemId: Long, decision: String): Transcript = copy(items = items.map {
        if (it is ChatItem.Permission && it.id == itemId) it.copy(decision = decision) else it
    })

    fun apply(frame: BridgeFrame): Transcript = when (frame) {
        is BridgeFrame.ReplyStream -> stream(frame.delta, frame.fullText, frame.done, frame.replyCtx)
        is BridgeFrame.UpdateMessage -> stream("", frame.content, done = false, replyCtx = frame.replyCtx)
        is BridgeFrame.Reply -> if (frame.isError) {
            finishStreaming().append { ChatItem.Failure(it, frame.content.ifBlank { "Host 返回错误" }, frame.errorCode) }
        } else final(frame.content, frame.replyCtx, frame.format)
        is BridgeFrame.Thinking -> {
            val last = items.lastOrNull()
            if (last is ChatItem.Thinking) replaceLast(last.copy(text = last.text + frame.content))
            else append { ChatItem.Thinking(it, frame.content) }
        }
        is BridgeFrame.ToolCall -> finishStreaming().append {
            ChatItem.Tool(it, frame.name, frame.input, callId = frame.callId, status = frame.status ?: "running")
        }
        is BridgeFrame.ToolResult -> toolResult(frame)
        is BridgeFrame.Card -> if (frame.buttons.isEmpty()) {
            append { ChatItem.Notice(it, frame.content) }
        } else finishStreaming().append {
            ChatItem.Permission(it, frame.content, frame.buttons, frame.replyCtx, frame.permissionId)
        }
        is BridgeFrame.RunDone -> finishStreaming().append { ChatItem.RunEnded(it, frame.status, frame.exitCode) }
        is BridgeFrame.Error -> append { ChatItem.Failure(it, frame.message, frame.code) }
        is BridgeFrame.Unknown -> append { ChatItem.Unsupported(it, frame.type.ifEmpty { "?" }) }
        // Connection-level, typing, preview and terminal frames never become chat rows.
        is BridgeFrame.RegisterAck, is BridgeFrame.Pong, is BridgeFrame.Typing, is BridgeFrame.PreviewStart,
        is BridgeFrame.ResumeAck, is BridgeFrame.ResyncRequired, is BridgeFrame.SessionStatus,
        is BridgeFrame.Terminal -> this
    }

    private fun stream(delta: String, fullText: String?, done: Boolean, replyCtx: String?): Transcript {
        val sid = streamingId
        if (sid == null) {
            val text = fullText ?: delta
            if (text.isEmpty() && done) return this
            val id = nextId
            return copy(
                items = items + ChatItem.Assistant(id, text, streaming = !done, replyCtx = replyCtx, format = null),
                streamingId = if (done) null else id,
                nextId = nextId + 1,
            )
        }
        return copy(
            items = items.map {
                if (it is ChatItem.Assistant && it.id == sid) it.copy(text = fullText ?: (it.text + delta), streaming = !done) else it
            },
            streamingId = if (done) null else sid,
        )
    }

    private fun final(content: String, replyCtx: String?, format: String?): Transcript {
        val sid = streamingId
        if (sid != null) {
            return copy(
                items = items.map {
                    if (it is ChatItem.Assistant && it.id == sid) it.copy(text = content.ifEmpty { it.text }, streaming = false, format = format) else it
                },
                streamingId = null,
            )
        }
        val last = items.lastOrNull()
        // Hosts often send the final `reply` after a `reply_stream(done=true)` with the same text.
        if (last is ChatItem.Assistant && !last.streaming && last.text == content) return this
        if (content.isEmpty()) return this
        return append { ChatItem.Assistant(it, content, streaming = false, replyCtx = replyCtx, format = format) }
    }

    private fun toolResult(frame: BridgeFrame.ToolResult): Transcript {
        val index = items.indexOfLast {
            it is ChatItem.Tool && !it.finished && (
                (frame.callId != null && it.callId == frame.callId) ||
                    (frame.callId == null && it.name == frame.name)
                )
        }
        if (index < 0) {
            return append { ChatItem.Tool(it, frame.name, "", frame.output, frame.callId, frame.status ?: "done", frame.isError) }
        }
        val tool = items[index] as ChatItem.Tool
        val updated = tool.copy(output = frame.output, status = frame.status ?: if (frame.isError) "error" else "done", isError = frame.isError)
        return copy(items = items.toMutableList().also { it[index] = updated })
    }

    private fun finishStreaming(): Transcript {
        val sid = streamingId ?: return this
        return copy(
            items = items.map { if (it is ChatItem.Assistant && it.id == sid) it.copy(streaming = false) else it },
            streamingId = null,
        )
    }

    private inline fun append(make: (Long) -> ChatItem) = copy(items = items + make(nextId), nextId = nextId + 1)

    private fun replaceLast(item: ChatItem) = copy(items = items.dropLast(1) + item)

    companion object {
        /** Rebuild from Management `transcript` rows (after a resync or on open). */
        fun hydrate(rows: List<TranscriptRow>, keepQueued: List<ChatItem.User> = emptyList()): Transcript {
            var t = Transcript()
            for (row in rows) {
                t = when (row.role) {
                    "user" -> t.addUser(row.content, null, queued = false)
                    "assistant" -> t.append { ChatItem.Assistant(it, row.content, false, null, null) }
                    "tool" -> t.append { ChatItem.Tool(it, "tool", "", row.content, status = "done") }
                    else -> t.append { ChatItem.Notice(it, row.content) }
                }
            }
            for (q in keepQueued) t = t.addUser(q.text, q.msgId, queued = true)
            return t
        }
    }
}
