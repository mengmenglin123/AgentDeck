package com.huanmeng.huanhermes.ui.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.huanmeng.huanhermes.core.mgmt.ProjectInfo
import com.huanmeng.huanhermes.core.net.HostError
import com.huanmeng.huanhermes.core.terminal.TerminalSession
import com.huanmeng.huanhermes.core.workspace.FileDiff
import com.huanmeng.huanhermes.core.workspace.GitStatus
import com.huanmeng.huanhermes.core.workspace.Workspace
import com.huanmeng.huanhermes.core.workspace.WsNode
import com.huanmeng.huanhermes.data.AppGraph
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class WorkspaceUi(
    val loading: Boolean = true,
    val node: WsNode? = null,
    val error: String? = null,
    val unsupported: Boolean = false,
    val projects: List<ProjectInfo> = emptyList(),
    val project: String? = null,
    val hostName: String = "",
)

private fun friendlyError(e: Throwable): Pair<Boolean, String> = when (e) {
    is HostError.Http -> (e.status == 404) to (e.message ?: "HTTP ${e.status}")
    else -> false to (e.message ?: e.javaClass.simpleName)
}

/** Shared project picker for Workspace / Git / Terminal. */
abstract class ProjectScopedViewModel(protected val graph: AppGraph) : ViewModel() {
    protected suspend fun runtime() = run {
        if (!graph.profiles.state.value.loaded) graph.profiles.load()
        graph.runtimeFor(graph.profiles.state.value.active)
    }
    protected val hostName get() = graph.profiles.state.value.active?.name.orEmpty()
}

class WorkspaceViewModel(graph: AppGraph) : ProjectScopedViewModel(graph) {
    private val _ui = MutableStateFlow(WorkspaceUi())
    val ui: StateFlow<WorkspaceUi> = _ui.asStateFlow()

    init { open("") }

    fun selectProject(name: String?) { _ui.update { it.copy(project = name) }; open("") }

    fun open(path: String) = viewModelScope.launch {
        val rt = runtime() ?: run { _ui.update { it.copy(loading = false, error = "还没有连接 Host") }; return@launch }
        _ui.update { it.copy(loading = true, error = null, hostName = hostName) }
        if (_ui.value.projects.isEmpty()) _ui.update { it.copy(projects = runCatching { rt.mgmt.projects() }.getOrDefault(emptyList())) }
        try {
            val node = Workspace.parseNode(rt.mgmt.get(Workspace.url("/workspace", _ui.value.project, path)))
            _ui.update { it.copy(loading = false, node = node, unsupported = false) }
        } catch (e: Exception) {
            val (unsupported, msg) = friendlyError(e)
            _ui.update { it.copy(loading = false, error = msg, unsupported = unsupported && path.isEmpty()) }
        }
    }

    /** Back inside the tree; false when already at the root. */
    fun up(): Boolean {
        val node = _ui.value.node ?: return false
        if (node.path.isEmpty()) return false
        open(node.path.substringBeforeLast('/', ""))
        return true
    }
}

data class GitUi(
    val loading: Boolean = true,
    val status: GitStatus? = null,
    val error: String? = null,
    val unsupported: Boolean = false,
    val projects: List<ProjectInfo> = emptyList(),
    val project: String? = null,
    val hostName: String = "",
    val diff: FileDiff? = null,
    val diffLoading: Boolean = false,
    /** Review comments on diff lines, sent back to a session as one message. */
    val comments: List<com.huanmeng.huanhermes.core.chat.ReviewComments.Comment> = emptyList(),
    /** Host has `git_write` (opt-in in its config). */
    val canWrite: Boolean = false,
    val writing: Boolean = false,
    val writeResult: String? = null,
)

class GitViewModel(graph: AppGraph, project: String? = null, openPath: String? = null) : ProjectScopedViewModel(graph) {
    private val _ui = MutableStateFlow(GitUi(project = project))
    val ui: StateFlow<GitUi> = _ui.asStateFlow()

    init { refresh(); openPath?.let { openDiff(it) } }

    fun addComment(path: String, line: Int?, code: String, note: String) {
        if (note.isBlank()) return
        _ui.update { it.copy(comments = it.comments + com.huanmeng.huanhermes.core.chat.ReviewComments.Comment(path, line, code, note)) }
    }
    fun removeComment(index: Int) = _ui.update { it.copy(comments = it.comments.filterIndexed { i, _ -> i != index }) }
    fun clearComments() = _ui.update { it.copy(comments = emptyList()) }
    fun reviewMessage(): String = com.huanmeng.huanhermes.core.chat.ReviewComments.message(_ui.value.comments)

    fun selectProject(name: String?) { _ui.update { it.copy(project = name, diff = null) }; refresh() }

    fun refresh() = viewModelScope.launch {
        val rt = runtime() ?: run { _ui.update { it.copy(loading = false, error = "还没有连接 Host") }; return@launch }
        _ui.update { it.copy(loading = true, error = null, hostName = hostName) }
        if (_ui.value.projects.isEmpty()) _ui.update { it.copy(projects = runCatching { rt.mgmt.projects() }.getOrDefault(emptyList())) }
        if (!_ui.value.canWrite) {
            val caps = runCatching { rt.mgmt.status()["capabilities"] }.getOrNull()
            _ui.update { it.copy(canWrite = caps.toString().contains("\"git_write\"")) }
        }
        try {
            val st = Workspace.parseGit(rt.mgmt.get(Workspace.url("/workspace/git", _ui.value.project)))
            _ui.update { it.copy(loading = false, status = st, unsupported = false) }
        } catch (e: Exception) {
            val (unsupported, msg) = friendlyError(e)
            _ui.update { it.copy(loading = false, error = msg, unsupported = unsupported) }
        }
    }

    fun openDiff(path: String) = viewModelScope.launch {
        val rt = runtime() ?: return@launch
        _ui.update { it.copy(diffLoading = true, diff = com.huanmeng.huanhermes.core.workspace.FileDiff(path, emptyList(), false)) }
        val diff = runCatching { Workspace.parseDiffData(rt.mgmt.get(Workspace.url("/workspace/diff", _ui.value.project, path)), path) }
            .getOrElse { e -> _ui.update { it.copy(error = e.message) }; null }
        _ui.update { it.copy(diffLoading = false, diff = diff) }
    }

    fun closeDiff() = _ui.update { it.copy(diff = null) }

    /** stage / unstage / commit / push (Hosts with `git_write`). */
    fun gitWrite(action: String, paths: List<String> = emptyList(), message: String? = null) = viewModelScope.launch {
        val rt = runtime() ?: return@launch
        _ui.update { it.copy(writing = true, writeResult = null) }
        val body = kotlinx.serialization.json.buildJsonObject {
            if (paths.isNotEmpty()) put("paths", kotlinx.serialization.json.JsonArray(paths.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            if (message != null) put("message", kotlinx.serialization.json.JsonPrimitive(message))
        }
        val result = runCatching { rt.mgmt.post(Workspace.url("/workspace/git/$action", _ui.value.project), body) }
        val label = when (action) { "stage" -> "已暂存"; "unstage" -> "已取消暂存"; "commit" -> "已提交"; "push" -> "已推送"; else -> action }
        _ui.update {
            it.copy(writing = false, writeResult = result.fold(
                onSuccess = { d -> label + ((d["commit"] as? kotlinx.serialization.json.JsonPrimitive)?.content?.let { c -> " $c" } ?: "") },
                onFailure = { e -> "失败：" + (e.message ?: e.javaClass.simpleName) },
            ))
        }
        refresh()
    }
    fun clearWriteResult() = _ui.update { it.copy(writeResult = null) }
}

class TerminalViewModel(graph: AppGraph) : ProjectScopedViewModel(graph) {
    private val _session = MutableStateFlow<TerminalSession?>(null)
    val session: StateFlow<TerminalSession?> = _session.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    val projects = MutableStateFlow<List<ProjectInfo>>(emptyList())
    val project = MutableStateFlow<String?>(null)
    /** Sticky Ctrl from the key bar: the next typed key becomes a control char. */
    val ctrl = MutableStateFlow(false)
    private var pendingSize: Pair<Int, Int>? = null

    init { open() }

    fun selectProject(name: String?) {
        if (name == project.value) return
        project.value = name
        _session.value?.close()
        _session.value = null
        open()
    }

    private fun open() = viewModelScope.launch {
        val rt = runtime() ?: run { _error.value = "还没有连接 Host"; return@launch }
        if (projects.value.isEmpty()) projects.value = runCatching { rt.mgmt.projects() }.getOrDefault(emptyList())
        val p = project.value ?: projects.value.firstOrNull()?.name
        // One terminal per device+project, so a reconnect lands on the same PTY.
        val key = "terminal:" + (p ?: "default") + ":" + rt.profile.config.deviceId.take(12)
        val (c, r) = pendingSize ?: (80 to 24)
        val s = TerminalSession(rt.bridge, viewModelScope, key, p, c, r)
        _session.value = s
        s.start()
    }

    fun resize(cols: Int, rows: Int) {
        pendingSize = cols to rows
        _session.value?.resize(cols, rows)
    }

    fun type(text: String) {
        val s = _session.value ?: return
        if (ctrl.value && text.isNotEmpty()) {
            ctrl.value = false
            val ch = text[0].uppercaseChar()
            val code = when (ch) { in '@'..'_' -> ch.code - 64; '?' -> 127; ' ' -> 0; else -> null }
            if (code != null) { s.input(code.toChar().toString() + text.drop(1)); return }
        }
        s.input(text)
    }

    fun key(seq: String) { _session.value?.input(seq) }

    override fun onCleared() {
        _session.value?.close()
    }
}

data class ExternalUi(
    val loading: Boolean = true,
    val sessions: List<com.huanmeng.huanhermes.core.workspace.ExternalSession> = emptyList(),
    val error: String? = null,
    val unsupported: Boolean = false,
    val projects: List<ProjectInfo> = emptyList(),
    val project: String? = null,
    val open: com.huanmeng.huanhermes.core.workspace.ExternalSession? = null,
    val rows: List<com.huanmeng.huanhermes.core.workspace.ExternalRow> = emptyList(),
)

/** Claude Code sessions started in a terminal on the Host (read-only, D3). */
class ExternalSessionsViewModel(graph: AppGraph) : ProjectScopedViewModel(graph) {
    private val _ui = MutableStateFlow(ExternalUi())
    val ui: StateFlow<ExternalUi> = _ui.asStateFlow()

    init { refresh() }

    fun selectProject(name: String?) { _ui.update { it.copy(project = name, open = null) }; refresh() }

    fun refresh() = viewModelScope.launch {
        val rt = runtime() ?: run { _ui.update { it.copy(loading = false, error = "还没有连接 Host") }; return@launch }
        _ui.update { it.copy(loading = true, error = null) }
        if (_ui.value.projects.isEmpty()) _ui.update { it.copy(projects = runCatching { rt.mgmt.projects() }.getOrDefault(emptyList())) }
        try {
            val list = com.huanmeng.huanhermes.core.workspace.ExternalSessions.parseList(rt.mgmt.get(com.huanmeng.huanhermes.core.workspace.ExternalSessions.url(_ui.value.project)))
            _ui.update { it.copy(loading = false, sessions = list, unsupported = false) }
        } catch (e: Exception) {
            val (unsupported, msg) = friendlyError(e)
            _ui.update { it.copy(loading = false, error = msg, unsupported = unsupported) }
        }
    }

    fun open(s: com.huanmeng.huanhermes.core.workspace.ExternalSession) = viewModelScope.launch {
        val rt = runtime() ?: return@launch
        _ui.update { it.copy(open = s, rows = emptyList(), loading = true) }
        val rows = runCatching {
            com.huanmeng.huanhermes.core.workspace.ExternalSessions.parseTranscript(rt.mgmt.get(com.huanmeng.huanhermes.core.workspace.ExternalSessions.url(_ui.value.project, s.id)))
        }.getOrElse { e -> _ui.update { it.copy(error = e.message) }; emptyList() }
        _ui.update { it.copy(rows = rows, loading = false) }
    }

    fun close() = _ui.update { it.copy(open = null, rows = emptyList()) }
}
