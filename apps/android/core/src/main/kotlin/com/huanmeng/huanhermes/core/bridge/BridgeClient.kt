package com.huanmeng.huanhermes.core.bridge

import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.net.Redactor
import com.huanmeng.huanhermes.core.protocol.BridgeFrame
import com.huanmeng.huanhermes.core.protocol.Capabilities
import com.huanmeng.huanhermes.core.protocol.Outbound
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.onTimeout
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

sealed interface BridgeState {
    data object Idle : BridgeState
    data class Connecting(val attempt: Int) : BridgeState
    data class Connected(val protocol: Int, val hostCapabilities: Set<String>, val epoch: String?) : BridgeState
    data class Reconnecting(val attempt: Int, val delayMs: Long, val reason: String) : BridgeState
    /** Terminal: only an explicit [BridgeClient.start] / [BridgeClient.reconnectNow] leaves it. */
    data class Stopped(val reason: String, val authFailed: Boolean) : BridgeState
}

sealed interface BridgeEvent {
    data class Frame(val frame: BridgeFrame) : BridgeEvent
    /** Connected again after a drop (first connect is not a reconnect). */
    data object Reconnected : BridgeEvent
    /** Live replay is impossible: reload this session's transcript over Management. */
    data class ResyncNeeded(val sessionKey: String, val reason: String) : BridgeEvent
}

/**
 * One Bridge WebSocket per Host with protocol v2 negotiation.
 *
 * - Never gives up on transient failures (handshake errors included); only an
 *   authentication rejection or [stop] ends the loop.
 * - `isConnected` turns false as soon as the socket closes or fails.
 * - Heartbeat: a ping every [heartbeatMs]; two whole periods without any
 *   inbound frame means the link is dead and it reconnects.
 * - Per-session `seq` is tracked for watched sessions; after a reconnect it
 *   sends `resume` (v2 Host) or asks callers to resync (v1 Host).
 * - Every error string is redacted (no tokens from the `?token=` URL).
 */
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class BridgeClient(
    private val config: HostConfig,
    private val transport: WsTransport,
    private val scope: CoroutineScope,
    private val appVersion: String = "0.2.1",
    private val policy: ReconnectPolicy = ReconnectPolicy(),
    private val heartbeatMs: Long = 15_000,
    private val registerTimeoutMs: Long = 12_000,
    private val capabilities: List<String> = Capabilities.NATIVE,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val _state = MutableStateFlow<BridgeState>(BridgeState.Idle)
    val state: StateFlow<BridgeState> = _state.asStateFlow()
    val isConnected: Boolean get() = _state.value is BridgeState.Connected

    private val _events = MutableSharedFlow<BridgeEvent>(extraBufferCapacity = 1024)
    val events: SharedFlow<BridgeEvent> = _events.asSharedFlow()

    private val lastSeq = ConcurrentHashMap<String, Long>()
    private val watched = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var socket: WsSocket? = null
    @Volatile private var epoch: String? = null
    private var loop: Job? = null
    private val wake = Channel<Unit>(Channel.CONFLATED)
    @Volatile private var stopRequested = false

    fun start() {
        if (loop?.isActive == true) return
        stopRequested = false
        loop = scope.launch { run() }
    }

    /** Skip the current backoff wait, or restart after [BridgeState.Stopped]. */
    fun reconnectNow() {
        if (loop?.isActive == true) wake.trySend(Unit) else start()
    }

    fun stop() {
        stopRequested = true
        socket?.close(1000, "bye")
        socket = null
        loop?.cancel()
        loop = null
        _state.value = BridgeState.Idle
    }

    /** Track [sessionKey] so its frames are de-duplicated and resumed after drops. */
    fun watch(sessionKey: String, afterSeq: Long? = null) {
        watched += sessionKey
        if (afterSeq != null) lastSeq[sessionKey] = afterSeq
    }

    fun unwatch(sessionKey: String) {
        watched -= sessionKey
    }

    fun lastSeq(sessionKey: String): Long = lastSeq[sessionKey] ?: 0

    /** After a transcript reload the transcript already contains everything up to [seq]. */
    fun markSynced(sessionKey: String, seq: Long) {
        lastSeq[sessionKey] = seq
    }

    /** Sends one frame; false when not connected (callers queue or report). */
    fun send(frame: JsonObject): Boolean {
        if (!isConnected) return false
        return socket?.send(frame.toString()) == true
    }

    // ---------------------------------------------------------------------

    private sealed interface Signal {
        data object Open : Signal
        data class Text(val text: String) : Signal
        data class Closed(val reason: String) : Signal
        data class Failed(val reason: String, val auth: Boolean) : Signal
    }

    private sealed interface Outcome {
        data class Dropped(val reason: String, val wasConnected: Boolean) : Outcome
        data class AuthRejected(val reason: String) : Outcome
    }

    private suspend fun run() {
        var attempt = 0
        var everConnected = false
        while (scope.isActive && !stopRequested) {
            _state.value = BridgeState.Connecting(attempt + 1)
            when (val outcome = connectOnce(reconnect = everConnected)) {
                is Outcome.AuthRejected -> {
                    _state.value = BridgeState.Stopped(outcome.reason, authFailed = true)
                    return
                }
                is Outcome.Dropped -> {
                    if (stopRequested) return
                    if (outcome.wasConnected) {
                        everConnected = true
                        attempt = 0
                    }
                    attempt += 1
                    val wait = policy.delayFor(attempt)
                    _state.value = BridgeState.Reconnecting(attempt, wait, outcome.reason)
                    select<Unit> {
                        wake.onReceive { }
                        onTimeout(wait) { }
                    }
                }
            }
        }
    }

    private suspend fun connectOnce(reconnect: Boolean): Outcome {
        val inbox = Channel<Signal>(Channel.UNLIMITED)
        val secrets = config.secrets
        val ws = try {
            transport.open(
                config.bridgeWsUrl,
                mapOf("Authorization" to "Bearer ${config.bridgeToken}"),
                object : WsListener {
                    override fun onOpen() { inbox.trySend(Signal.Open) }
                    override fun onMessage(text: String) { inbox.trySend(Signal.Text(text)) }
                    override fun onClosed(code: Int, reason: String) {
                        inbox.trySend(Signal.Closed(Redactor.redact("连接已关闭 ($code${if (reason.isBlank()) "" else " $reason"})", secrets)))
                    }
                    override fun onFailure(error: Throwable, httpStatus: Int?) {
                        val auth = httpStatus == 401 || httpStatus == 403
                        val reason = when {
                            auth -> "Bridge 握手被拒绝 (HTTP $httpStatus)：请检查 Bridge 令牌"
                            httpStatus != null -> "Bridge 握手失败 (HTTP $httpStatus)"
                            else -> Redactor.redact(error, secrets)
                        }
                        inbox.trySend(Signal.Failed(reason, auth))
                    }
                },
            )
        } catch (e: Exception) {
            return Outcome.Dropped(Redactor.redact(e, secrets), wasConnected = false)
        }
        socket = ws
        try {
            // --- handshake + register -------------------------------------
            val ack: Any? = withTimeoutOrNull(registerTimeoutMs) {
                var registerSent = false
                while (true) {
                    when (val signal = inbox.receive()) {
                        Signal.Open -> if (!registerSent) {
                            registerSent = true
                            ws.send(Outbound.register(config.platformName, config.deviceId, appVersion, capabilities).toString())
                        }
                        is Signal.Text -> {
                            val frame = BridgeFrame.parse(signal.text)
                            if (frame is BridgeFrame.RegisterAck) return@withTimeoutOrNull frame
                        }
                        is Signal.Closed -> return@withTimeoutOrNull signal
                        is Signal.Failed -> return@withTimeoutOrNull signal
                    }
                }
                @Suppress("UNREACHABLE_CODE")
                null
            }
            when (ack) {
                null -> return Outcome.Dropped("register_ack 超时", wasConnected = false)
                is Signal.Failed -> return if (ack.auth) Outcome.AuthRejected(ack.reason) else Outcome.Dropped(ack.reason, false)
                is Signal.Closed -> return Outcome.Dropped(ack.reason, false)
                is BridgeFrame.RegisterAck -> if (!ack.ok) {
                    val reason = Redactor.redact(ack.error ?: "register denied", secrets)
                    return if (looksLikeAuth(reason)) Outcome.AuthRejected(reason) else Outcome.Dropped(reason, false)
                }
                else -> return Outcome.Dropped("unexpected handshake state", false)
            }
            ack as BridgeFrame.RegisterAck

            // --- connected --------------------------------------------------
            val previousEpoch = epoch
            epoch = ack.epoch
            _state.value = BridgeState.Connected(ack.protocol, ack.capabilities, ack.epoch)
            if (reconnect) {
                _events.emit(BridgeEvent.Reconnected)
                val canResume = Capabilities.RESUME in ack.capabilities
                val hostRestarted = previousEpoch != null && ack.epoch != null && previousEpoch != ack.epoch
                for (key in watched) {
                    when {
                        canResume && !hostRestarted ->
                            ws.send(Outbound.resume(key, lastSeq[key] ?: 0, ack.epoch).toString())
                        else -> {
                            if (hostRestarted) lastSeq.remove(key)
                            _events.emit(BridgeEvent.ResyncNeeded(key, if (hostRestarted) "host_restarted" else "no_resume"))
                        }
                    }
                }
            }

            val framesThisPeriod = AtomicInteger(0)
            val heartbeat = scope.launch {
                var silentPeriods = 0
                while (isActive) {
                    delay(heartbeatMs)
                    if (framesThisPeriod.getAndSet(0) == 0) silentPeriods += 1 else silentPeriods = 0
                    if (silentPeriods >= 2) {
                        inbox.trySend(Signal.Failed("心跳超时：${heartbeatMs * 2 / 1000} 秒内未收到任何数据", auth = false))
                        return@launch
                    }
                    ws.send(Outbound.ping(now()).toString())
                }
            }
            try {
                while (true) {
                    when (val signal = inbox.receive()) {
                        Signal.Open -> Unit
                        is Signal.Text -> {
                            framesThisPeriod.incrementAndGet()
                            val frame = BridgeFrame.parse(signal.text) ?: continue
                            handleFrame(frame)
                        }
                        is Signal.Closed -> return Outcome.Dropped(signal.reason, wasConnected = true)
                        is Signal.Failed -> return if (signal.auth) Outcome.AuthRejected(signal.reason)
                            else Outcome.Dropped(signal.reason, wasConnected = true)
                    }
                }
            } finally {
                heartbeat.cancel()
            }
        } finally {
            if (socket === ws) socket = null
            ws.cancel()
            if (_state.value is BridgeState.Connected) {
                _state.value = BridgeState.Reconnecting(0, 0, "连接已断开")
            }
        }
    }

    private suspend fun handleFrame(frame: BridgeFrame) {
        val key = frame.sessionKey
        when (frame) {
            is BridgeFrame.Pong, is BridgeFrame.RegisterAck -> return
            is BridgeFrame.ResyncRequired -> {
                if (key != null) {
                    lastSeq[key] = frame.lastSeq
                    _events.emit(BridgeEvent.ResyncNeeded(key, "resync_required"))
                }
                return
            }
            else -> Unit
        }
        val seq = frame.seq
        if (key != null && seq != null) {
            val last = lastSeq[key] ?: 0
            if (seq <= last) return // duplicate (replay overlap): already applied
            lastSeq[key] = seq
        }
        _events.emit(BridgeEvent.Frame(frame))
    }

    private fun looksLikeAuth(reason: String): Boolean {
        val r = reason.lowercase()
        return "auth" in r || "token" in r || "unauthor" in r || "forbidden" in r || "denied" in r
    }
}
