package com.huanmeng.huanhermes.core.hosts

import com.huanmeng.huanhermes.core.mgmt.MgmtApi
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.net.HostError
import com.huanmeng.huanhermes.core.net.Redactor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class HostProfile(val id: String = UUID.randomUUID().toString(), val name: String, val config: HostConfig)

@Serializable
data class ProfilesSnapshot(val profiles: List<HostProfile> = emptyList(), val activeId: String? = null)

/** Tokens live in encrypted storage on Android; tests use memory. */
interface ProfileStorage {
    suspend fun load(): ProfilesSnapshot
    suspend fun save(snapshot: ProfilesSnapshot)
}

class MemoryProfileStorage(var snapshot: ProfilesSnapshot = ProfilesSnapshot()) : ProfileStorage {
    override suspend fun load() = snapshot
    override suspend fun save(snapshot: ProfilesSnapshot) { this.snapshot = snapshot }
}

data class ProfilesState(
    val loaded: Boolean = false,
    val profiles: List<HostProfile> = emptyList(),
    val activeId: String? = null,
    /** Bumped on every switch: results started under an older generation are dropped. */
    val generation: Long = 0,
    val testing: Boolean = false,
    val ready: Boolean = false,
    val lastError: String? = null,
    val latencyMs: Long? = null,
) {
    val active: HostProfile? get() = profiles.firstOrNull { it.id == activeId }
}

/**
 * Host profiles and the "test & connect" flow. A test that is still running
 * when the user switches profile must not write its config into the new one:
 * every async result is checked against the generation it started in.
 */
class ProfileManager(
    private val storage: ProfileStorage,
    private val mgmtFor: (HostConfig) -> MgmtApi,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val _state = MutableStateFlow(ProfilesState())
    val state: StateFlow<ProfilesState> = _state.asStateFlow()
    private val mutex = Mutex()

    suspend fun load() {
        val snap = runCatching { storage.load() }.getOrDefault(ProfilesSnapshot())
        _state.update { it.copy(loaded = true, profiles = snap.profiles, activeId = snap.activeId ?: snap.profiles.firstOrNull()?.id) }
    }

    /** Switch the active profile. Drops readiness: the user re-tests (no silent connect). */
    suspend fun select(id: String?) = mutex.withLock {
        _state.update { it.copy(activeId = id, generation = it.generation + 1, ready = false, testing = false, lastError = null, latencyMs = null) }
        persist()
    }

    /**
     * Probe `/status` with [draft]; on success save it as profile [profileId]
     * (null = new profile) and make it active. Returns false when the probe
     * failed or the user switched profiles meanwhile.
     */
    suspend fun testAndSave(profileId: String?, name: String, draft: HostConfig): Boolean {
        val problems = draft.validate()
        val startGen: Long
        mutex.withLock {
            startGen = _state.value.generation
            if (problems.isNotEmpty()) {
                _state.update { it.copy(testing = false, ready = false, lastError = problems.first()) }
                return false
            }
            _state.update { it.copy(testing = true, lastError = null) }
        }
        val started = clock()
        val outcome = try {
            mgmtFor(draft).status()
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: HostError.Auth) {
            "令牌被拒绝：${e.message}"
        } catch (e: HostError) {
            "无法连接 Host：${e.message}"
        } catch (e: Exception) {
            Redactor.redact(e, draft.secrets)
        }
        return mutex.withLock {
            val now = _state.value
            if (now.generation != startGen || (profileId != null && now.activeId != profileId)) {
                return@withLock false // switched while testing: discard, write nothing
            }
            if (outcome != null) {
                _state.update { it.copy(testing = false, ready = false, lastError = outcome) }
                return@withLock false
            }
            val id = profileId ?: UUID.randomUUID().toString()
            val profile = HostProfile(id, name.trim().ifEmpty { draft.host }, draft)
            val list = now.profiles.filterNot { it.id == id } + profile
            _state.update {
                it.copy(profiles = list, activeId = id, testing = false, ready = true, lastError = null, latencyMs = clock() - started)
            }
            persist()
            true
        }
    }

    suspend fun delete(id: String) = mutex.withLock {
        _state.update {
            val list = it.profiles.filterNot { p -> p.id == id }
            val active = if (it.activeId == id) list.firstOrNull()?.id else it.activeId
            it.copy(profiles = list, activeId = active, generation = it.generation + 1, ready = if (it.activeId == id) false else it.ready)
        }
        persist()
    }

    /** Mark the active profile usable without probing (e.g. restored on app start). */
    fun markReady(ready: Boolean) = _state.update { it.copy(ready = ready) }

    private suspend fun persist() {
        val s = _state.value
        runCatching { storage.save(ProfilesSnapshot(s.profiles, s.activeId)) }
    }
}

data class SessionsState(
    val hostId: String? = null,
    val sessions: List<SessionInfo> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
)

/** Session list for the active Host; switching Host clears it and ignores stale responses. */
class SessionsModel {
    private val _state = MutableStateFlow(SessionsState())
    val state: StateFlow<SessionsState> = _state.asStateFlow()
    @Volatile private var generation = 0L
    @Volatile private var mgmt: MgmtApi? = null
    @Volatile private var project: String? = null
    @Volatile private var closed = false
    private var secrets: List<String> = emptyList()

    fun bind(hostId: String?, api: MgmtApi?, project: String? = null, secrets: List<String> = emptyList()) {
        generation += 1
        mgmt = api
        this.project = project
        this.secrets = secrets
        if (!closed) _state.value = SessionsState(hostId = hostId)
    }

    fun close() {
        closed = true
        generation += 1
    }

    suspend fun refresh() = guarded { api ->
        val list = api.sessions(project);
        { st: SessionsState -> st.copy(sessions = list, error = null) }
    }

    suspend fun create(project: String, title: String?): SessionInfo? {
        var created: SessionInfo? = null
        guarded { api ->
            val s = api.createSession(project, title)
            created = s;
            { st: SessionsState -> st.copy(sessions = listOf(s) + st.sessions.filterNot { x -> x.id == s.id }) }
        }
        return created
    }

    suspend fun rename(session: SessionInfo, title: String) = guarded { api ->
        val updated = api.renameSession(session.id, title, session.project);
        { st: SessionsState ->
            st.copy(sessions = st.sessions.map { if (it.id == session.id) updated.copy(title = updated.title ?: title) else it })
        }
    }

    suspend fun delete(session: SessionInfo) = guarded { api ->
        api.deleteSession(session.id, session.project);
        { st: SessionsState -> st.copy(sessions = st.sessions.filterNot { it.id == session.id }) }
    }

    /**
     * Runs [call] and applies the state change it returns only if the Host
     * binding is still the one the call started with (and the model is open).
     */
    private suspend fun guarded(call: suspend (MgmtApi) -> (SessionsState) -> SessionsState): Boolean {
        val api = mgmt ?: return false
        val gen = generation
        if (closed) return false
        _state.update { it.copy(loading = true) }
        return try {
            val change = call(api)
            if (gen != generation || closed) return false
            _state.update { change(it).copy(loading = false) }
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (gen == generation && !closed) _state.update { it.copy(loading = false, error = Redactor.redact(e, secrets)) }
            false
        }
    }
}
