package com.huanmeng.huanhermes.core.chat

import com.huanmeng.huanhermes.core.mgmt.TranscriptRow
import com.huanmeng.huanhermes.core.protocol.BridgeFrame
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptTest {
    private fun f(json: String) = BridgeFrame.parse(json)!!
    private fun Transcript.feed(vararg frames: String) = frames.fold(this) { t, j -> t.apply(f(j)) }

    @Test fun streamingDeltasThenFinalReplyMakeOneMessage() {
        val t = Transcript().feed(
            """{"type":"reply_stream","session_key":"s","delta":"Hel"}""",
            """{"type":"reply_stream","session_key":"s","delta":"lo"}""",
        )
        val a = t.items.single() as ChatItem.Assistant
        assertEquals("Hello", a.text)
        assertTrue(a.streaming)
        val done = t.feed("""{"type":"reply_stream","session_key":"s","delta":"!","full_text":"Hello!","done":true}""",
            """{"type":"reply","session_key":"s","content":"Hello!"}""")
        assertEquals(1, done.items.size)
        assertFalse((done.items.single() as ChatItem.Assistant).streaming)
    }

    @Test fun toolResultsAttachToTheirCall() {
        val t = Transcript().feed(
            """{"type":"tool_call","session_key":"s","name":"bash","input":"ls","call_id":"c1"}""",
            """{"type":"tool_call","session_key":"s","name":"bash","input":"pwd","call_id":"c2"}""",
            """{"type":"tool_result","session_key":"s","name":"bash","output":"/tmp","call_id":"c2"}""",
            """{"type":"tool_result","session_key":"s","name":"bash","output":"a b","call_id":"c1"}""",
        )
        val tools = t.items.filterIsInstance<ChatItem.Tool>()
        assertEquals(2, tools.size)
        assertEquals("a b", tools[0].output)
        assertEquals("/tmp", tools[1].output)
    }

    @Test fun permissionUnknownErrorAndRunDone() {
        val t = Transcript().feed(
            """{"type":"reply_stream","session_key":"s","delta":"x"}""",
            """{"type":"buttons","session_key":"s","reply_ctx":"r9","content":"rm?","buttons":[[{"text":"Allow","data":"perm:p:allow"},{"text":"Deny","data":"perm:p:deny"}]]}""",
            """{"type":"brand_new_event","session_key":"s"}""",
            """{"type":"reply","session_key":"s","content":"rejected","error":true,"error_code":"permission_action_rejected"}""",
            """{"type":"run_done","session_key":"s","status":"failed","exit_code":2}""",
            """{"type":"typing_start","session_key":"s"}""",
            """{"type":"terminal_out","session_key":"s","stream_id":"t","data":"x"}""",
        )
        assertFalse((t.items[0] as ChatItem.Assistant).streaming)
        val p = t.items[1] as ChatItem.Permission
        assertEquals("r9", p.replyCtx)
        assertEquals(2, p.buttons.size)
        assertEquals("brand_new_event", (t.items[2] as ChatItem.Unsupported).type)
        assertEquals("permission_action_rejected", (t.items[3] as ChatItem.Failure).code)
        assertEquals(ChatItem.RunEnded(t.items[4].id, "failed", 2), t.items[4])
        assertEquals(5, t.items.size)
        assertEquals("allow", t.markDecision(p.id, "allow").items.filterIsInstance<ChatItem.Permission>().single().decision)
        assertEquals(t.items.map { it.id }.distinct().size, t.items.size)
    }

    @Test fun hydrateKeepsQueuedMessages() {
        val queued = ChatItem.User(99, "later", "m1", queued = true)
        val t = Transcript.hydrate(listOf(TranscriptRow("user", "hi"), TranscriptRow("assistant", "yo")), listOf(queued))
        assertEquals(listOf("hi", "yo", "later"), t.items.map {
            when (it) { is ChatItem.User -> it.text; is ChatItem.Assistant -> it.text; else -> "" }
        })
        assertTrue((t.items.last() as ChatItem.User).queued)
        assertFalse((t.markSent("m1").items.last() as ChatItem.User).queued)
    }
}
