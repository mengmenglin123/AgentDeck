package com.huanmeng.huanhermes.core.overview

import com.huanmeng.huanhermes.core.hosts.HostProfile
import com.huanmeng.huanhermes.core.mgmt.PendingPermission
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.core.net.Redactor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withTimeoutOrNull

/** One thing waiting on the user, on any Host. */
data class InboxItem(
    val hostId: String,
    val hostName: String,
    val session: SessionInfo,
    val permission: PendingPermission,
) {
    val key: String get() = "$hostId|${session.id}|${permission.id}"
}

data class HostInboxStatus(val hostId: String, val hostName: String, val error: String? = null, val supported: Boolean = true)

data class InboxState(
    val items: List<InboxItem> = emptyList(),
    val hosts: List<HostInboxStatus> = emptyList(),
    val loading: Boolean = false,
    /** Items answered from this device, hidden until the next refresh confirms them gone. */
    val answered: Set<String> = emptySet(),
) {
    val visible: List<InboxItem> get() = items.filterNot { it.key in answered }
    val unsupportedHosts: List<HostInboxStatus> get() = hosts.filter { !it.supported && it.error == null }
}

/**
 * Cross-Host "需要我" list built from each Host's `/sessions` overview
 * (`pending_permissions`). Hosts without the overview are reported as
 * unsupported rather than as empty. Each Host is fetched in parallel with a
 * timeout so one offline Host never blocks the rest.
 */
class InboxModel(
    private val fetch: suspend (HostProfile) -> Pair<List<SessionInfo>, Boolean>,
    private val timeoutMs: Long = 8_000,
) {
    private val _state = MutableStateFlow(InboxState())
    val state: StateFlow<InboxState> = _state.asStateFlow()

    suspend fun refresh(profiles: List<HostProfile>) {
        _state.update { it.copy(loading = true) }
        val results = coroutineScope {
            profiles.map { p ->
                async {
                    try {
                        val r = withTimeoutOrNull(timeoutMs) { fetch(p) }
                        if (r == null) p to Result.failure<Pair<List<SessionInfo>, Boolean>>(IllegalStateException("连接超时"))
                        else p to Result.success(r)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        p to Result.failure(e)
                    }
                }
            }.awaitAll()
        }
        val items = mutableListOf<InboxItem>()
        val hosts = mutableListOf<HostInboxStatus>()
        for ((p, r) in results) {
            r.fold(
                onSuccess = { (sessions, supported) ->
                    hosts += HostInboxStatus(p.id, p.name, supported = supported)
                    sessions.forEach { s -> s.pendingPermissions.forEach { items += InboxItem(p.id, p.name, s, it) } }
                },
                onFailure = { e -> hosts += HostInboxStatus(p.id, p.name, error = Redactor.redact(e, p.config.secrets)) },
            )
        }
        val keys = items.map { it.key }.toSet()
        _state.update { st -> InboxState(items, hosts, loading = false, answered = st.answered intersect keys) }
    }

    fun markAnswered(item: InboxItem) = markAnswered(item.key)

    fun markAnswered(key: String) = _state.update { it.copy(answered = it.answered + key) }

    fun unmark(item: InboxItem) = _state.update { it.copy(answered = it.answered - item.key) }
}
