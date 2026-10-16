package com.huanmeng.huanhermes.core.bridge

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

interface WsListener {
    fun onOpen()
    fun onMessage(text: String)
    fun onClosed(code: Int, reason: String)
    /** [httpStatus] is set when the upgrade itself was refused (401/403/404…). */
    fun onFailure(error: Throwable, httpStatus: Int?)
}

interface WsSocket {
    fun send(text: String): Boolean
    fun close(code: Int = 1000, reason: String = "")
    fun cancel()
}

fun interface WsTransport {
    fun open(url: String, headers: Map<String, String>, listener: WsListener): WsSocket
}

class OkHttpWsTransport(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build(),
) : WsTransport {
    override fun open(url: String, headers: Map<String, String>, listener: WsListener): WsSocket {
        val request = Request.Builder().url(url).apply { headers.forEach { (k, v) -> header(k, v) } }.build()
        val ws = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) = listener.onOpen()
            override fun onMessage(webSocket: WebSocket, text: String) = listener.onMessage(text)
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, null)
                listener.onClosed(code, reason)
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = listener.onClosed(code, reason)
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val status = response?.code?.takeIf { it != 101 }
                response?.close()
                listener.onFailure(t, status)
            }
        })
        return object : WsSocket {
            override fun send(text: String) = ws.send(text)
            override fun close(code: Int, reason: String) { ws.close(code, reason.ifEmpty { null }) }
            override fun cancel() = ws.cancel()
        }
    }
}
