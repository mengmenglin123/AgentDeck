package com.huanmeng.huanhermes.core.bridge

import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Scriptable WebSocket transport for deterministic (virtual-time) tests. */
class FakeTransport : WsTransport {
    val sockets = mutableListOf<FakeSocket>()
    val urls = mutableListOf<String>()
    var onOpen: (FakeSocket) -> Unit = {}
    val last: FakeSocket get() = sockets.last()

    override fun open(url: String, headers: Map<String, String>, listener: WsListener): WsSocket {
        urls += url
        val s = FakeSocket(listener, headers)
        sockets += s
        onOpen(s)
        return s
    }

    class FakeSocket(private val listener: WsListener, val headers: Map<String, String>) : WsSocket {
        val sent = mutableListOf<JsonObject>()
        var closed = false
        fun sentTypes() = sent.map { it["type"]!!.jsonPrimitive.content }
        fun open() = listener.onOpen()
        fun text(json: String) = listener.onMessage(json)
        fun ack(extra: String = "") = text("""{"type":"register_ack","ok":true,"error":""$extra}""")
        fun ackV2(epoch: String = "e1") =
            ack(""","protocol":2,"capabilities":["seq","resume","session_status"],"epoch":"$epoch"""")
        fun serverClose(code: Int = 1001, reason: String = "going away") = listener.onClosed(code, reason)
        fun fail(error: Throwable = java.io.IOException("boom"), status: Int? = null) = listener.onFailure(error, status)

        override fun send(text: String): Boolean {
            if (closed) return false
            sent += ProtocolJson.parseToJsonElement(text).jsonObject
            return true
        }
        override fun close(code: Int, reason: String) { closed = true }
        override fun cancel() { closed = true }
    }
}
