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

    init {
        viewModelScope.launch {
            if (!graph.profiles.state.value.loaded) graph.profiles.load()
            graph.profiles.state.map { it.active }.distinctUntilChanged().collect { profile ->
                _active.value = profile
                _projects.value = emptyList()
                val rt = graph.runtimeFor(profile)
                model.bind(profile?.id, rt?.mgmt, secrets = profile?.config?.secrets.orEmpty())
                if (rt != null) {
                    rt.bridge.start()
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

    fun create(project: String, title: String?, onCreated: (SessionInfo) -> Unit) = viewModelScope.launch {
        model.create(project, title)?.let(onCreated)
    }

    fun rename(s: SessionInfo, title: String) = viewModelScope.launch { model.rename(s, title) }
    fun delete(s: SessionInfo) = viewModelScope.launch { model.delete(s) }

    fun remember(s: SessionInfo): String {
        graph.sessionRefs[s.id] = SessionRef(s.id, s.sessionKey, s.project.ifBlank { null }, s.displayTitle)
        return s.id
    }

    override fun onCleared() {
        model.close()
    }
}

class ChatViewModel(private val graph: AppGraph, sessionId: String) : ViewModel() {
    private val ref: SessionRef? = graph.sessionRefs[sessionId]
    private val chat: ChatSession? = run {
        val profile = graph.profiles.state.value.active ?: return@run null
        val rt = graph.runtimeFor(profile) ?: return@run null
        val r = ref ?: return@run null
        ChatSession(profile.id, r, rt.bridge, rt.mgmt, graph.offlineQueue, viewModelScope, secrets = profile.config.secrets)
    }
    val title: String = ref?.title ?: "会话"
    val state: StateFlow<ChatState> = chat?.state ?: MutableStateFlow(ChatState(error = "会话不可用：请回到会话列表重新打开"))

    init { chat?.start() }

    fun send(text: String) = viewModelScope.launch { chat?.send(text) }
    fun cancel() { chat?.cancelRun() }
    fun reload() = viewModelScope.launch { chat?.reloadTranscript() }
    fun respond(item: ChatItem.Permission, decision: String) { chat?.respondPermission(item, decision) }
    fun reconnect() {
        val profile = graph.profiles.state.value.active ?: return
        graph.runtimeFor(profile)?.bridge?.reconnectNow()
    }

    fun safeError(text: String?): String? = text?.let { Redactor.redact(it, graph.profiles.state.value.active?.config?.secrets.orEmpty()) }

    override fun onCleared() {
        chat?.close() // no state updates after the screen is gone
    }
}
