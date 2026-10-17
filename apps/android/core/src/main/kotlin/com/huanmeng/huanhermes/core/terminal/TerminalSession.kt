package com.huanmeng.huanhermes.core.terminal

import com.huanmeng.huanhermes.core.bridge.BridgeClient
import com.huanmeng.huanhermes.core.bridge.BridgeEvent
import com.huanmeng.huanhermes.core.bridge.BridgeState
import com.huanmeng.huanhermes.core.protocol.BridgeFrame
import com.huanmeng.huanhermes.core.protocol.Outbound
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put

/** A Host PTY over the Bridge `terminal_*` channel, rendered by [TerminalEmulator]. */
class TerminalSession(
    private val bridge: BridgeClient,
    private val scope: CoroutineScope,
    val sessionKey: String,
    val project: String?,
    cols: Int = 80,
    rows: Int = 24,
    val streamId: String = Outbound.shortId("term"),
) {
    sealed interface Status {
        data object Opening : Status
        data object Open : Status
        data class Exited(val code: Int?) : Status
        data class Failed(val message: String) : Status
    }

    data class Permission(val id: String?, val content: String, val actions: List<Pair<String, String>>)

    data class Ui(
        val status: Status = Status.Opening,
        val version: Long = 0,
        val permission: Permission? = null,
        val busy: Boolean = false,
        val title: String = "",
    )

    val emulator = TerminalEmulator(cols, rows)
    private val lock = Any()
    private val _ui = MutableStateFlow(Ui())
    val ui: StateFlow<Ui> = _ui.asStateFlow()
    private var job: Job? = null

    init {
        emulator.onResponse = { reply -> send(frame("terminal_input") { put("data", reply) }) }
    }

    fun <T> read(block: (TerminalEmulator) -> T): T = synchronized(lock) { block(emulator) }

    fun start() {
        if (job != null) return
        job = scope.launch {
            launch {
                bridge.events.collect { e ->
                    when (e) {
                        is BridgeEvent.Frame -> (e.frame as? BridgeFrame.Terminal)?.let { onFrame(it.raw) }
                        BridgeEvent.Reconnected -> if (_ui.value.status !is Status.Exited) open()
                        else -> {}
                    }
                }
            }
            bridge.start()
            bridge.state.first { it is BridgeState.Connected }
            open()
        }
    }

    private fun open() {
        val (c, r) = read { it.cols to it.rows }
        _ui.update { it.copy(status = Status.Opening) }
        send(frame("terminal_open") { put("cols", c); put("rows", r) })
    }

    fun input(text: String) {
        if (text.isEmpty()) return
        if (send(frame("terminal_input") { put("data", text) })) _ui.update { it.copy(busy = true) }
    }

    fun resize(cols: Int, rows: Int) {
        val changed = read { e -> val before = e.cols to e.rows; e.resize(cols, rows); before != (e.cols to e.rows) }
        if (!changed) return
        bump()
        if (_ui.value.status == Status.Open) {
            val (c, r) = read { it.cols to it.rows }
            send(frame("terminal_resize") { put("cols", c); put("rows", r) })
        }
    }

    fun answerPermission(action: String) {
        val p = _ui.value.permission ?: return
        _ui.update { it.copy(permission = null) }
        send(frame("terminal_permission_action") { put("action", action); p.id?.let { put("permission_id", it) } })
    }

    fun restart() {
        read { it.reset() }
        bump()
        open()
    }

    fun close() {
        send(frame("terminal_close") {})
        job?.cancel()
        job = null
    }

    /** Arrow keys honour DECCKM (vim/less ask for application cursor keys). */
    fun arrow(dir: Char): String = if (read { it.appCursorKeys }) "\u001bO$dir" else "\u001b[$dir"

    internal fun onFrame(raw: JsonObject) {
        if (raw.str("session_key")?.let { it != sessionKey } == true) return
        val sid = raw.str("stream_id")
        if (sid != null && sid != streamId) return
        when (raw.str("type")) {
            "terminal_open_ack" -> if (raw.bool("ok") == false) {
                val err = raw.str("error") ?: "terminal_open_failed"
                _ui.update { it.copy(status = Status.Failed(friendly(err))) }
            } else {
                _ui.update { it.copy(status = Status.Open) }
                // Host may have clamped the geometry.
                val c = raw.int("cols"); val r = raw.int("rows")
                if (c != null && r != null) { read { it.resize(c, r) }; bump() }
            }
            "terminal_out" -> {
                val data = raw.str("data").orEmpty()
                read { it.feed(translateNewlines(data)) }
                _ui.update { it.copy(busy = false, status = if (it.status is Status.Opening) Status.Open else it.status) }
                bump()
            }
            "terminal_clear" -> { read { it.clear() }; bump() }
            "terminal_exit" -> { _ui.update { it.copy(status = Status.Exited(raw.int("exit_code")), busy = false) } }
            "terminal_permission" -> {
                val actions = (raw["buttons"] as? JsonArray).orEmpty().flatMap { row -> (row as? JsonArray).orEmpty() }
                    .mapNotNull { b -> (b as? JsonObject)?.let { o -> val d = o.str("data") ?: return@let null; (o.str("text") ?: d) to d } }
                _ui.update { it.copy(permission = Permission(raw.str("permission_id"), raw.str("content") ?: "允许打开终端？", actions)) }
            }
            "terminal_ack" -> if (raw.bool("ok") == false) {
                val err = raw.str("error").orEmpty()
                if (err == "stale_terminal_stream") open()
                else _ui.update { it.copy(busy = false, status = Status.Failed(friendly(err))) }
            }
        }
    }

    /**
     * A real PTY (onlcr) always sends CRLF; the line-mode mock and some
     * hosts send bare LF. Until a CRLF is seen, a bare LF also returns the carriage.
     */
    private var sawCrLf = false
    internal fun translateNewlines(data: String): String {
        if (sawCrLf) return data
        if (data.contains("\r\n")) { sawCrLf = true; return data }
        return data.replace("\n", "\r\n")
    }

    private fun bump() = _ui.update { it.copy(version = it.version + 1, title = read { e -> e.title }) }

    private fun send(f: JsonObject): Boolean = bridge.send(f)

    private fun frame(type: String, extra: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit) = buildJsonObject {
        put("type", type)
        put("session_key", sessionKey)
        project?.let { put("project", it) }
        put("stream_id", streamId)
        extra()
    }

    companion object {
        fun friendly(code: String): String = when (code) {
            "terminal_stream_in_use" -> "这个终端正被另一台设备使用"
            "terminal_open_failed", "" -> "终端打开失败"
            "permission_denied", "terminal_permission_denied" -> "终端权限被拒绝"
            "terminal_disabled", "terminal_unsupported" -> "这个 Host 没有开启终端"
            else -> code
        }

        private fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull
        private fun JsonObject.bool(k: String) = (this[k] as? JsonPrimitive)?.booleanOrNull
        private fun JsonObject.int(k: String) = (this[k] as? JsonPrimitive)?.intOrNull
    }
}
