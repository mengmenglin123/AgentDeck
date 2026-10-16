package com.huanmeng.huanhermes.core.overview

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

interface PrefsStorage {
    suspend fun read(): String?
    suspend fun write(text: String)
}

class MemoryPrefsStorage(var text: String? = null) : PrefsStorage {
    override suspend fun read() = text
    override suspend fun write(text: String) { this.text = text }
}

class FilePrefsStorage(private val file: File) : PrefsStorage {
    override suspend fun read(): String? = withContext(Dispatchers.IO) { if (file.exists()) file.readText() else null }
    override suspend fun write(text: String) = withContext(Dispatchers.IO) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
        Unit
    }
}

/**
 * Device-local session state: pinned, archived (archive is not delete), last
 * opened time (for unread), per-session drafts and input history. Keys are
 * `hostId|sessionId` so two Hosts never share state. Corrupt data resets.
 */
class LocalSessionPrefs(private val storage: PrefsStorage, private val clock: () -> Double = { System.currentTimeMillis() / 1000.0 }) {
    @Serializable
    data class Data(
        val pinned: Set<String> = emptySet(),
        val archived: Set<String> = emptySet(),
        val lastSeen: Map<String, Double> = emptyMap(),
        val drafts: Map<String, String> = emptyMap(),
        val history: List<String> = emptyList(),
    )

    /** View for one Host, keys stripped of the Host prefix. */
    data class Snapshot(
        val pinned: Set<String> = emptySet(),
        val archived: Set<String> = emptySet(),
        val lastSeen: Map<String, Double> = emptyMap(),
        val drafts: Map<String, String> = emptyMap(),
    )

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }
    private val _data = MutableStateFlow(Data())
    val data: StateFlow<Data> = _data.asStateFlow()
    private val mutex = Mutex()
    @Volatile var loaded = false
        private set

    suspend fun load() = mutex.withLock {
        if (loaded) return@withLock
        _data.value = runCatching { storage.read()?.let { json.decodeFromString(Data.serializer(), it) } }.getOrNull() ?: Data()
        loaded = true
    }

    fun snapshot(hostId: String?, d: Data = _data.value): Snapshot {
        if (hostId == null) return Snapshot()
        val p = "$hostId|"
        fun Set<String>.strip() = filter { it.startsWith(p) }.map { it.removePrefix(p) }.toSet()
        fun <V> Map<String, V>.strip() = filterKeys { it.startsWith(p) }.mapKeys { it.key.removePrefix(p) }
        return Snapshot(d.pinned.strip(), d.archived.strip(), d.lastSeen.strip(), d.drafts.strip())
    }

    suspend fun setPinned(hostId: String, sessionId: String, pinned: Boolean) =
        edit { it.copy(pinned = it.pinned.toggle(key(hostId, sessionId), pinned)) }

    suspend fun setArchived(hostId: String, sessionId: String, archived: Boolean) = edit {
        val k = key(hostId, sessionId)
        it.copy(archived = it.archived.toggle(k, archived), pinned = if (archived) it.pinned - k else it.pinned)
    }

    suspend fun markSeen(hostId: String, sessionId: String, at: Double = clock()) =
        edit { it.copy(lastSeen = it.lastSeen + (key(hostId, sessionId) to at)) }

    fun draft(hostId: String, sessionId: String): String = _data.value.drafts[key(hostId, sessionId)].orEmpty()

    suspend fun setDraft(hostId: String, sessionId: String, text: String) = edit {
        val k = key(hostId, sessionId)
        val trimmed = text.take(MAX_DRAFT)
        if (it.drafts[k] == trimmed || (trimmed.isBlank() && k !in it.drafts)) return@edit it
        it.copy(drafts = if (trimmed.isBlank()) it.drafts - k else it.drafts + (k to trimmed))
    }

    /** Newest first, de-duplicated, capped. Slash commands are kept too (they are the most re-used). */
    suspend fun addHistory(text: String) = edit {
        val t = text.trim()
        if (t.isEmpty() || t.length > MAX_HISTORY_ITEM) return@edit it
        it.copy(history = (listOf(t) + it.history.filterNot { h -> h == t }).take(MAX_HISTORY))
    }

    suspend fun forget(hostId: String, sessionId: String) = edit {
        val k = key(hostId, sessionId)
        it.copy(pinned = it.pinned - k, archived = it.archived - k, lastSeen = it.lastSeen - k, drafts = it.drafts - k)
    }

    private suspend fun edit(change: (Data) -> Data) = mutex.withLock {
        val before = _data.value
        val after = change(before)
        if (after == before) return@withLock
        _data.value = after
        runCatching { storage.write(json.encodeToString(Data.serializer(), after)) }
    }

    private fun Set<String>.toggle(k: String, on: Boolean) = if (on) this + k else this - k

    companion object {
        const val MAX_HISTORY = 50
        const val MAX_HISTORY_ITEM = 4000
        const val MAX_DRAFT = 20_000
        fun key(hostId: String, sessionId: String) = "$hostId|$sessionId"
    }
}
