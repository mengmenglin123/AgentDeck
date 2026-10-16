package com.huanmeng.huanhermes.core.chat

import com.huanmeng.huanhermes.core.bridge.BridgeClient
import com.huanmeng.huanhermes.core.bridge.BridgeEvent
import com.huanmeng.huanhermes.core.bridge.BridgeState
import com.huanmeng.huanhermes.core.mgmt.MgmtApi
import com.huanmeng.huanhermes.core.net.HostError
import com.huanmeng.huanhermes.core.net.Redactor
import com.huanmeng.huanhermes.core.protocol.BridgeFrame
import com.huanmeng.huanhermes.core.protocol.Capabilities
import com.huanmeng.huanhermes.core.protocol.Outbound
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class SessionRef(val id: String, val sessionKey: String, val project: String?, val title: String)

sealed interface ConnectionBanner {
    data object None : ConnectionBanner
    data object Connecting : ConnectionBanner
    data class Reconnecting(val attempt: Int, val delayMs: Long, val reason: String) : ConnectionBanner
    data class Stopped(val reason: String, val authFailed: Boolean) : ConnectionBanner
}

data class ChatState(
    val transcript: Transcript = Transcript(),
    val banner: ConnectionBanner = ConnectionBanner.Connecting,
    val connected: Boolean = false,
    val typing: Boolean = false,
    val runActive: Boolean = false,
    val reloading: Boolean = false,
    /** Last action error (send/cancel/permission); cleared on a successful reconnect. */
    val error: String? = null,
    val mode: String? = null,
    val model: String? = null,
    val capabilities: List<String> = emptyList(),
    /** Messages typed while a run was active; sent one by one after each `run_done`. */
    val runQueue: List<QueuedSend> = emptyList(),
    /** Host capabilities from the Bridge handshake (empty until connected). */
    val hostCapabilities: Set<String> = emptySet(),
) {
    val items get() = transcript.items
}

/**
 * Chat logic for one session on one Host (the Android ViewModel only wraps it).
 *
 * Every Bridge frame is filtered by `session_key` before anything else looks
 * at it — typing, reply_ctx and all. Offline text goes to the queue keyed by
 * Host + session and is flushed back to this session only. After [close] no
 * state is updated.
 */
class ChatSession(
    private val hostId: String,
    val session: SessionRef,
    private val bridge: BridgeClient,
    private val mgmt: MgmtApi,
    private val queue: OfflineQueue,
    private val scope: CoroutineScope,
    private val clock: () -> Long = System::currentTimeMillis,
    private val secrets: List<String> = emptyList(),
) {
    private val _state = MutableStateFlow(ChatState())
    val state: StateFlow<ChatState> = _state.asStateFlow()
    @Volatile private var closed = false
    private val jobs = mutableListOf<Job>()
    private var lastReplyCtx: String? = null
    private val flushLock = Mutex()
    private var wasDisconnected = false
    /** The run queue is only safe once this Host has shown it reports run ends. */
    @Volatile private var runEndsKnown = false

    fun start() {
        bridge.watch(session.sessionKey)
        jobs += scope.launch { bridge.events.collect { onEvent(it) } }
        jobs += scope.launch { bridge.state.collect { onBridgeState(it) } }
        jobs += scope.launch {
            queue.load()
            reloadTranscript()
            flushQueue()
        }
        bridge.start()
    }

    fun close() {
        closed = true
        jobs.forEach { it.cancel() }
        jobs.clear()
        bridge.unwatch(session.sessionKey)
    }

    private inline fun mutate(block: (ChatState) -> ChatState) {
        if (closed) return
        _state.update(block)
    }

    // --- inbound ---------------------------------------------------------

    private suspend fun onEvent(event: BridgeEvent) {
        if (closed) return
        when (event) {
            is BridgeEvent.Frame -> onFrame(event.frame)
            is BridgeEvent.ResyncNeeded -> if (event.sessionKey == session.sessionKey) reloadTranscript()
            BridgeEvent.Reconnected -> Unit
        }
    }

    internal fun onFrame(frame: BridgeFrame) {
        // Rule 1: anything for another session (or no session at all) is not ours.
        if (frame.sessionKey != session.sessionKey) return
        frame.replyCtx?.let { lastReplyCtx = it }
        when (frame) {
            is BridgeFrame.Typing -> mutate { it.copy(typing = frame.active, runActive = it.runActive || frame.active) }
            is BridgeFrame.PreviewStart -> {
                bridge.send(Outbound.previewAck(frame.refId, "app-${clock()}"))
                mutate { it.copy(transcript = it.transcript.apply(frame)) }
            }
            is BridgeFrame.RunDone -> {
                runEndsKnown = true
                mutate { it.copy(transcript = it.transcript.apply(frame), runActive = false, typing = false) }
                scope.launch { sendNextQueued() }
            }
            is BridgeFrame.ResumeAck -> Unit
            is BridgeFrame.SessionStatus -> {
                // First contact: the transcript we hydrated already covers the journal up to here,
                // so a later resume must not replay it again.
                if (bridge.lastSeq(session.sessionKey) == 0L) bridge.markSynced(session.sessionKey, frame.lastSeq)
                mutate { it.copy(runActive = frame.running) }
            }
            else -> mutate {
                val running = when (frame) {
                    is BridgeFrame.ReplyStream, is BridgeFrame.Thinking, is BridgeFrame.ToolCall,
                    is BridgeFrame.ToolResult, is BridgeFrame.Card -> true
                    else -> it.runActive
                }
                it.copy(transcript = it.transcript.apply(frame), runActive = running)
            }
        }
    }

    private suspend fun onBridgeState(s: BridgeState) {
        when (s) {
            is BridgeState.Connected -> {
                val recovered = wasDisconnected
                wasDisconnected = false
                // Rule: a successful (re)connect clears the stale error banner.
                mutate { it.copy(banner = ConnectionBanner.None, connected = true, error = if (recovered) null else it.error) }
                if (Capabilities.SESSION_STATUS in s.hostCapabilities) {
                    runEndsKnown = true
                    bridge.send(Outbound.sessionStatus(session.sessionKey))
                }
                mutate { it.copy(hostCapabilities = s.hostCapabilities) }
                flushQueue()
            }
            is BridgeState.Connecting -> mutate {
                it.copy(connected = false, banner = if (it.banner is ConnectionBanner.Reconnecting) it.banner else ConnectionBanner.Connecting)
            }
            is BridgeState.Reconnecting -> {
                wasDisconnected = true
                mutate {
                    it.copy(
                        connected = false, typing = false,
                        banner = ConnectionBanner.Reconnecting(s.attempt, s.delayMs, s.reason),
                    )
                }
            }
            is BridgeState.Stopped -> {
                wasDisconnected = true
                mutate { it.copy(connected = false, typing = false, banner = ConnectionBanner.Stopped(s.reason, s.authFailed)) }
            }
            BridgeState.Idle -> mutate { it.copy(connected = false) }
        }
    }

    // --- outbound --------------------------------------------------------

    /** True when [send] would hold the text in the run queue instead of sending it now. */
    val queuesWhileRunning: Boolean get() = runEndsKnown && _state.value.runActive && bridge.isConnected

    /**
     * Sends text now, queues it behind the active run (Hosts known to report
     * run ends), or keeps it in the offline queue when disconnected.
     */
    suspend fun send(text: String): Boolean {
        val content = text.trim()
        if (content.isEmpty() || closed) return false
        if (queuesWhileRunning && !content.startsWith("/")) {
            mutate { it.copy(runQueue = it.runQueue + QueuedSend(Outbound.shortId("q"), content), error = null) }
            return true
        }
        return sendNow(content)
    }

    /** Sends immediately even while a run is active (steer / slash commands). */
    suspend fun sendNow(text: String): Boolean {
        val content = text.trim()
        if (content.isEmpty() || closed) return false
        val msgId = Outbound.shortId("msg")
        val replyCtx = Outbound.shortId("ctx")
        val sent = bridge.isConnected && bridge.send(Outbound.message(session.sessionKey, content, session.project, msgId, replyCtx))
        if (sent) {
            lastReplyCtx = replyCtx
            mutate { it.copy(transcript = it.transcript.addUser(content, msgId, queued = false), runActive = true, error = null) }
            return true
        }
        val queued = queue.enqueue(QueuedMessage(hostId, session.sessionKey, session.project, content, msgId, clock()))
        mutate {
            if (queued) it.copy(transcript = it.transcript.addUser(content, msgId, queued = true), error = null)
            else it.copy(error = "离线队列已满，消息未保存")
        }
        return queued
    }

    /** Removes a run-queue entry and returns its text (to edit it in the composer). */
    fun takeQueued(id: String): String? {
        var taken: String? = null
        mutate { st ->
            taken = st.runQueue.firstOrNull { it.msgId == id }?.text
            st.copy(runQueue = st.runQueue.filterNot { it.msgId == id })
        }
        return taken
    }

    /** Sends one queued entry right away instead of waiting for the run to end. */
    suspend fun sendQueuedNow(id: String): Boolean {
        val text = takeQueued(id) ?: return false
        return sendNow(text)
    }

    private suspend fun sendNextQueued() {
        if (closed) return
        val next = _state.value.runQueue.firstOrNull() ?: return
        if (_state.value.runActive || !bridge.isConnected) return
        takeQueued(next.msgId)
        sendNow(next.text)
    }

    private suspend fun flushQueue() = flushLock.withLock {
        if (closed || !bridge.isConnected) return@withLock
        val sent = queue.flush(hostId, session.sessionKey) { m ->
            bridge.send(Outbound.message(m.sessionKey, m.content, m.project, m.msgId))
        }
        if (sent.isEmpty()) return@withLock
        mutate { st ->
            var t = st.transcript
            for (id in sent) {
                t = if (t.items.any { it is ChatItem.User && it.msgId == id }) t.markSent(id)
                else t.addUser(queue.items.value.firstOrNull { it.msgId == id }?.content ?: "", id, queued = false)
            }
            st.copy(transcript = t, runActive = true)
        }
    }

    fun cancelRun(): Boolean {
        val ok = bridge.send(Outbound.cancel(session.sessionKey, lastReplyCtx, session.project))
        if (!ok) mutate { it.copy(error = "未连接，无法取消") }
        return ok
    }

    /** Answers a permission card with its own `reply_ctx` and exact button data. */
    fun respondPermission(item: ChatItem.Permission, decision: String): Boolean {
        val action = Outbound.resolvePermissionAction(decision, item.buttons)
        val ok = bridge.send(Outbound.cardAction(session.sessionKey, action, item.replyCtx ?: lastReplyCtx, session.project))
        val label = when {
            action.endsWith("allow_all") -> "allow_all"
            action.endsWith("deny") -> "deny"
            else -> "allow"
        }
        mutate {
            if (ok) it.copy(transcript = it.transcript.markDecision(item.id, label))
            else it.copy(error = "未连接，权限回复未发送")
        }
        return ok
    }

    suspend fun reloadTranscript() {
        if (closed) return
        mutate { it.copy(reloading = true) }
        try {
            val detail = mgmt.sessionDetail(session.id, session.project)
            mutate { st ->
                val queued = st.items.filterIsInstance<ChatItem.User>().filter { it.queued }
                // Hosts without stored history (the production Host returns []) must not wipe
                // what is on screen when a resync falls back to Management.
                val transcript = if (detail.transcript.isEmpty() && st.items.isNotEmpty()) st.transcript
                    else Transcript.hydrate(detail.transcript, queued)
                st.copy(
                    transcript = transcript,
                    mode = detail.mode ?: st.mode,
                    model = detail.model ?: st.model,
                    capabilities = detail.capabilities.ifEmpty { st.capabilities },
                    runActive = detail.running || st.runActive,
                    reloading = false,
                )
            }
            detail.lastSeq?.let { bridge.markSynced(session.sessionKey, it) }
        } catch (e: HostError) {
            // No history yet is normal for a fresh session; keep what we have.
            mutate { it.copy(reloading = false) }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            mutate { it.copy(reloading = false, error = Redactor.redact(e, secrets)) }
        }
    }
}
