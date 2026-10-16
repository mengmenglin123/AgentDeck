package com.huanmeng.huanhermes.ui.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.huanmeng.huanhermes.core.chat.ChatItem
import com.huanmeng.huanhermes.core.chat.ChatSession
import com.huanmeng.huanhermes.core.chat.ChatState
import com.huanmeng.huanhermes.core.chat.SessionRef
import com.huanmeng.huanhermes.core.hosts.HostProfile
import com.huanmeng.huanhermes.core.hosts.SessionsModel
import com.huanmeng.huanhermes.core.hosts.SessionsState
import com.huanmeng.huanhermes.core.mgmt.ProjectInfo
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.net.Redactor
import com.huanmeng.huanhermes.data.AppGraph
import com.huanmeng.huanhermes.core.bridge.BridgeState
import com.huanmeng.huanhermes.core.net.Diagnostics
import com.huanmeng.huanhermes.core.overview.InboxItem
import com.huanmeng.huanhermes.core.overview.InboxState
import com.huanmeng.huanhermes.core.overview.LocalSessionPrefs
import com.huanmeng.huanhermes.core.overview.SessionGroup
import com.huanmeng.huanhermes.core.overview.SessionGrouping
import com.huanmeng.huanhermes.core.protocol.Outbound
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class HostsViewModel(private val graph: AppGraph) : ViewModel() {
    val state = graph.profiles.state

    init {
        viewModelScope.launch { if (!graph.profiles.state.value.loaded) graph.profiles.load() }
    }

    fun select(id: String) = viewModelScope.launch { graph.profiles.select(id) }
    fun delete(id: String) = viewModelScope.launch { graph.profiles.delete(id) }

    fun testAndSave(profileId: String?, name: String, draft: HostConfig, onDone: (Boolean) -> Unit = {}) =
        viewModelScope.launch { onDone(graph.profiles.testAndSave(profileId, name, draft)) }
}

class SessionsViewModel(private val graph: AppGraph) : ViewModel() {
    private val model = SessionsModel()
    val sessions: StateFlow<SessionsState> = model.state
    private val _projects = MutableStateFlow<List<ProjectInfo>>(emptyList())
    val projects: StateFlow<List<ProjectInfo>> = _projects.asStateFlow()
    private val _active = MutableStateFlow<HostProfile?>(null)
    val active: StateFlow<HostProfile?> = _active.asStateFlow()
    val profiles = graph.profiles.state
    val query = MutableStateFlow("")
    val showArchived = MutableStateFlow(false)
    private val _online = MutableStateFlow(true)
    private var bridgeWatch: Job? = null

    val prefs: StateFlow<LocalSessionPrefs.Snapshot> = combine(graph.localPrefs.data, _active) { d, a -> graph.localPrefs.snapshot(a?.id, d) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, LocalSessionPrefs.Snapshot())

    val groups: StateFlow<List<SessionGroup>> = combine(model.state, prefs, query, showArchived, _online) { st, p, q, arch, online ->
        SessionGrouping.group(st.sessions, p, online, q, arch)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    val archivedCount: StateFlow<Int> = combine(model.state, prefs) { st, p -> SessionGrouping.archivedCount(st.sessions, p) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, 0)

    init {
        viewModelScope.launch {
            graph.localPrefs.load()
            if (!graph.profiles.state.value.loaded) graph.profiles.load()
            graph.profiles.state.map { it.active }.distinctUntilChanged().collect { profile ->
                _active.value = profile
                _projects.value = emptyList()
                val rt = graph.runtimeFor(profile)
                model.bind(profile?.id, rt?.mgmt, secrets = profile?.config?.secrets.orEmpty())
                bridgeWatch?.cancel()
                if (rt != null) {
                    rt.bridge.start()
                    bridgeWatch = launch {
                        rt.bridge.state.collect { s ->
                            _online.value = s is BridgeState.Connected || s is BridgeState.Connecting || s is BridgeState.Idle
                        }
                    }
                    refresh()
                }
            }
        }
    }

    fun refresh() = viewModelScope.launch {
        val rt = graph.runtimeFor(_active.value) ?: return@launch
        val forHost = _active.value?.id
        val projects = runCatching { rt.mgmt.projects() }.getOrDefault(emptyList())
        if (_active.value?.id == forHost) _projects.value = projects
        model.refresh()
    }

    fun switchHost(id: String) = viewModelScope.launch { graph.profiles.select(id) }

    fun create(project: String, title: String?, onCreated: (SessionInfo) -> Unit) = viewModelScope.launch {
        model.create(project, title)?.let(onCreated)
    }

    /** Quick start: the first message becomes the title and is sent once the chat opens. */
    fun quickStart(project: String, text: String, onCreated: (SessionInfo) -> Unit) = viewModelScope.launch {
        val first = text.trim()
        if (first.isEmpty()) return@launch
        val title = first.lineSequence().first().take(30)
        model.create(project, title)?.let {
            graph.pendingFirstMessage[it.id] = first
            onCreated(it)
        }
    }

    fun rename(s: SessionInfo, title: String) = viewModelScope.launch { model.rename(s, title) }
    fun delete(s: SessionInfo) = viewModelScope.launch {
        model.delete(s)
        _active.value?.id?.let { graph.localPrefs.forget(it, s.id) }
    }
    fun setPinned(s: SessionInfo, pinned: Boolean) = viewModelScope.launch { _active.value?.id?.let { graph.localPrefs.setPinned(it, s.id, pinned) } }
    fun setArchived(s: SessionInfo, archived: Boolean) = viewModelScope.launch { _active.value?.id?.let { graph.localPrefs.setArchived(it, s.id, archived) } }

    fun remember(s: SessionInfo): SessionRef {
        _active.value?.id?.let { host -> viewModelScope.launch { graph.localPrefs.markSeen(host, s.id) } }
        return SessionRef(s.id, s.sessionKey, s.project.ifBlank { null }, s.displayTitle).also { graph.sessionRefs[s.id] = it }
    }

    override fun onCleared() {
        model.close()
    }
}

class InboxViewModel(private val graph: AppGraph) : ViewModel() {
    val state: StateFlow<InboxState> = graph.inbox.state
    private val _busy = MutableStateFlow<String?>(null)
    /** Key of the item whose decision is being sent. */
    val busy: StateFlow<String?> = _busy.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        viewModelScope.launch {
            if (!graph.profiles.state.value.loaded) graph.profiles.load()
            graph.profiles.state.map { it.profiles }.distinctUntilChanged().collect { refresh() }
        }
    }

    fun refresh() = viewModelScope.launch { graph.inbox.refresh(graph.profiles.state.value.profiles) }

    /**
     * Sends the decision over the Bridge of the item's Host. Only one Bridge is
     * live at a time, so an item on another Host switches the active Host first.
     */
    fun decide(item: InboxItem, decision: String) = viewModelScope.launch {
        _busy.value = item.key
        _error.value = null
        try {
            val profile = graph.profiles.state.value.profiles.firstOrNull { it.id == item.hostId }
                ?: run { _error.value = "Host 已删除"; return@launch }
            if (graph.profiles.state.value.activeId != profile.id) graph.profiles.select(profile.id)
            val rt = graph.runtimeFor(profile) ?: run { _error.value = "无法连接 ${profile.name}"; return@launch }
            rt.bridge.start()
            val connected = withTimeoutOrNull(12_000) { rt.bridge.state.first { it is BridgeState.Connected } } != null
            if (!connected) { _error.value = "连不上 ${profile.name} 的 Bridge，稍后再试"; return@launch }
            val action = Outbound.resolvePermissionAction(decision, item.permission.buttons)
            val ok = rt.bridge.send(Outbound.cardAction(item.session.sessionKey, action, item.permission.replyCtx, item.session.project.ifBlank { null }))
            if (!ok) { _error.value = "发送失败，请重试"; return@launch }
            graph.inbox.markAnswered(item)
            delay(800)
            graph.inbox.refresh(graph.profiles.state.value.profiles)
        } finally {
            _busy.value = null
        }
    }

    /** Opening the session from the inbox makes its Host active first. */
    fun open(item: InboxItem, onReady: (SessionRef) -> Unit) = viewModelScope.launch {
        if (graph.profiles.state.value.activeId != item.hostId) graph.profiles.select(item.hostId)
        val s = item.session
        graph.localPrefs.markSeen(item.hostId, s.id)
        onReady(SessionRef(s.id, s.sessionKey, s.project.ifBlank { null }, s.displayTitle).also { graph.sessionRefs[s.id] = it })
    }
}

/** [fallback] comes from the nav route, so the chat survives process death (no in-memory map then). */
class ChatViewModel(private val graph: AppGraph, private val sessionId: String, fallback: SessionRef?) : ViewModel() {
    private val ref: SessionRef? = graph.sessionRefs[sessionId] ?: fallback
    private val hostId: String? = run {
        // After process death the profile store may not be loaded yet.
        if (!graph.profiles.state.value.loaded) kotlinx.coroutines.runBlocking { graph.profiles.load() }
        if (!graph.localPrefs.loaded) kotlinx.coroutines.runBlocking { graph.localPrefs.load() }
        graph.profiles.state.value.active?.id
    }
    private val chat: ChatSession? = run {
        val profile = graph.profiles.state.value.active ?: return@run null
        val rt = graph.runtimeFor(profile) ?: return@run null
        val r = ref ?: return@run null
        ChatSession(profile.id, r, rt.bridge, rt.mgmt, graph.offlineQueue, viewModelScope, secrets = profile.config.secrets)
    }
    val title: String = ref?.title ?: "会话"
    val state: StateFlow<ChatState> = chat?.state ?: MutableStateFlow(ChatState(error = "会话不可用：请回到会话列表重新打开"))
    val initialDraft: String = hostId?.let { graph.localPrefs.draft(it, sessionId) }.orEmpty()
    val history: StateFlow<List<String>> = graph.localPrefs.data.map { it.history }
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())
    private val _models = MutableStateFlow<List<String>>(emptyList())
    val models: StateFlow<List<String>> = _models.asStateFlow()
    private var draftJob: Job? = null

    init {
        chat?.start()
        hostId?.let { h -> viewModelScope.launch { graph.localPrefs.markSeen(h, sessionId) } }
        graph.pendingFirstMessage.remove(sessionId)?.let { first -> send(first) }
        viewModelScope.launch {
            val project = ref?.project ?: return@launch
            val rt = graph.currentRuntime ?: return@launch
            _models.value = runCatching { rt.mgmt.projects() }.getOrDefault(emptyList()).firstOrNull { it.name == project }?.models.orEmpty()
        }
    }

    fun send(text: String) = viewModelScope.launch {
        if (text.isBlank()) return@launch
        graph.localPrefs.addHistory(text)
        saveDraftNow("")
        chat?.send(text)
    }

    /** Slash commands and steer messages skip the run queue. */
    fun sendNow(text: String) = viewModelScope.launch {
        if (text.isBlank()) return@launch
        graph.localPrefs.addHistory(text)
        chat?.sendNow(text)
    }

    fun queuesWhileRunning(): Boolean = chat?.queuesWhileRunning == true
    fun takeQueued(id: String): String? = chat?.takeQueued(id)
    fun sendQueuedNow(id: String) = viewModelScope.launch { chat?.sendQueuedNow(id) }

    fun saveDraft(text: String) {
        draftJob?.cancel()
        draftJob = viewModelScope.launch { delay(400); saveDraftNow(text) }
    }

    private suspend fun saveDraftNow(text: String) {
        val h = hostId ?: return
        graph.localPrefs.setDraft(h, sessionId, text)
    }

    fun cancel() { chat?.cancelRun() }
    fun reload() = viewModelScope.launch { chat?.reloadTranscript() }
    fun respond(item: ChatItem.Permission, decision: String) {
        if (chat?.respondPermission(item, decision) == true) {
            hostId?.let { h -> viewModelScope.launch { delay(600); graph.inbox.refresh(graph.profiles.state.value.profiles) } }
        }
    }
    fun reconnect() {
        val profile = graph.profiles.state.value.active ?: return
        graph.runtimeFor(profile)?.bridge?.reconnectNow()
    }

    fun diagnostics(): String {
        val profile = graph.profiles.state.value.active
        val rt = graph.currentRuntime
        val st = state.value
        return Diagnostics.report(
            appVersion = com.huanmeng.huanhermes.BuildConfig.VERSION_NAME,
            androidSdk = android.os.Build.VERSION.SDK_INT,
            config = profile?.config,
            bridgeState = rt?.bridge?.state?.value?.toString() ?: "无",
            hostCapabilities = st.hostCapabilities,
            lastError = safeError(st.error),
        )
    }

    fun safeError(text: String?): String? = text?.let { Redactor.redact(it, graph.profiles.state.value.active?.config?.secrets.orEmpty()) }

    override fun onCleared() {
        hostId?.let { h -> graph.scope.launch { graph.localPrefs.markSeen(h, sessionId) } }
        chat?.close() // no state updates after the screen is gone
    }
}
