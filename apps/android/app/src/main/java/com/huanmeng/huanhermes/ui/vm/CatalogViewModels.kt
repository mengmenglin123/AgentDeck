package com.huanmeng.huanhermes.ui.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.huanmeng.huanhermes.core.catalog.CatalogEntry
import com.huanmeng.huanhermes.core.catalog.CatalogKind
import com.huanmeng.huanhermes.core.catalog.HostCatalogs
import com.huanmeng.huanhermes.core.mgmt.ProjectInfo
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.core.net.HostError
import com.huanmeng.huanhermes.data.AppGraph
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class CatalogUiState(
    val loading: Boolean = true,
    val entries: List<CatalogEntry> = emptyList(),
    val error: String? = null,
    /** The Host has no such endpoint (404 / capability not advertised). */
    val unsupported: Boolean = false,
    val hostName: String = "",
    val projects: List<ProjectInfo> = emptyList(),
    val project: String? = null,
)

class CatalogViewModel(private val graph: AppGraph, val kind: CatalogKind) : ViewModel() {
    private val _state = MutableStateFlow(CatalogUiState())
    val state: StateFlow<CatalogUiState> = _state.asStateFlow()
    val query = MutableStateFlow("")
    /** Logs only: "" = all levels. */
    val level = MutableStateFlow("")

    val visible: StateFlow<List<CatalogEntry>> = combine(_state, query, level) { st, q, lv ->
        val byLevel = if (lv.isEmpty()) st.entries else st.entries.filter { it.level == lv }
        HostCatalogs.filter(byLevel, q)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    init { refresh() }

    fun selectProject(name: String?) {
        _state.update { it.copy(project = name) }
        refresh()
    }

    fun refresh() = viewModelScope.launch {
        if (!graph.profiles.state.value.loaded) graph.profiles.load()
        val profile = graph.profiles.state.value.active
        val rt = graph.runtimeFor(profile)
        if (rt == null) {
            _state.update { it.copy(loading = false, error = "还没有连接 Host", entries = emptyList()) }
            return@launch
        }
        _state.update { it.copy(loading = true, error = null, hostName = profile?.name.orEmpty()) }
        if (kind.projectScoped && _state.value.projects.isEmpty()) {
            val projects = runCatching { rt.mgmt.projects() }.getOrDefault(emptyList())
            _state.update { it.copy(projects = projects) }
        }
        try {
            val data = rt.mgmt.get(kind.url(_state.value.project))
            _state.update { it.copy(loading = false, entries = HostCatalogs.parse(kind, data), unsupported = false) }
        } catch (e: HostError.Http) {
            if (e.status == 404) _state.update { it.copy(loading = false, unsupported = true, entries = emptyList()) }
            else _state.update { it.copy(loading = false, error = e.message) }
        } catch (e: Exception) {
            _state.update { it.copy(loading = false, error = e.message ?: e.javaClass.simpleName) }
        }
    }
}

data class DashboardUiState(
    val loading: Boolean = true,
    val error: String? = null,
    val hostName: String = "",
    val statusRows: List<Pair<String, String>> = emptyList(),
    val capabilities: List<String> = emptyList(),
    val sessions: List<SessionInfo> = emptyList(),
    val projects: List<ProjectInfo> = emptyList(),
    val pendingAllHosts: Int = 0,
    val hostCount: Int = 0,
) {
    val running get() = sessions.count { it.running || it.status == "running" }
    val needsMe get() = sessions.count { it.pendingPermissions.isNotEmpty() || it.status == "needs_you" }
    val byProject: List<Pair<String, Int>> get() = sessions.groupingBy { it.project.ifBlank { "默认" } }.eachCount().toList().sortedByDescending { it.second }
}

/** Status + Dashboard share one load: `/status`, `/projects`, `/sessions` of the active Host. */
class DashboardViewModel(private val graph: AppGraph) : ViewModel() {
    private val _state = MutableStateFlow(DashboardUiState())
    val state: StateFlow<DashboardUiState> = _state.asStateFlow()

    init { refresh() }

    fun refresh() = viewModelScope.launch {
        if (!graph.profiles.state.value.loaded) graph.profiles.load()
        val snap = graph.profiles.state.value
        val rt = graph.runtimeFor(snap.active)
        _state.update { it.copy(loading = true, error = null, hostName = snap.active?.name.orEmpty(), hostCount = snap.profiles.size) }
        if (rt == null) {
            _state.update { it.copy(loading = false, error = "还没有连接 Host") }
            return@launch
        }
        try {
            val status = rt.mgmt.status()
            val projects = runCatching { rt.mgmt.projects() }.getOrDefault(emptyList())
            val sessions = runCatching { rt.mgmt.sessions() }.getOrDefault(emptyList())
            runCatching { graph.inbox.refresh(snap.profiles) }
            _state.update {
                it.copy(
                    loading = false,
                    statusRows = HostCatalogs.statusRows(status),
                    capabilities = HostCatalogs.capabilities(status),
                    projects = projects, sessions = sessions,
                    pendingAllHosts = graph.inbox.state.value.visible.size,
                )
            }
        } catch (e: Exception) {
            _state.update { it.copy(loading = false, error = e.message ?: e.javaClass.simpleName) }
        }
    }
}
