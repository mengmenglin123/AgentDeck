package com.huanmeng.huanhermes.core.chat

import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/** A text message typed while offline; it belongs to exactly one Host + session. */
@Serializable
data class QueuedMessage(
    val hostId: String,
    val sessionKey: String,
    val project: String? = null,
    val content: String,
    val msgId: String,
    val queuedAt: Long,
)

interface QueueStorage {
    fun read(): List<QueuedMessage>
    fun write(items: List<QueuedMessage>)
}

/** Atomic JSON file storage; a corrupt file reads as empty instead of crashing. */
class FileQueueStorage(private val file: File) : QueueStorage {
    private val serializer = ListSerializer(QueuedMessage.serializer())

    override fun read(): List<QueuedMessage> = runCatching {
        if (!file.exists()) emptyList() else ProtocolJson.decodeFromString(serializer, file.readText(Charsets.UTF_8))
    }.getOrDefault(emptyList())

    override fun write(items: List<QueuedMessage>) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, ".${file.name}.tmp")
        tmp.writeText(ProtocolJson.encodeToString(serializer, items), Charsets.UTF_8)
        if (!tmp.renameTo(file)) {
            file.delete()
            tmp.renameTo(file)
        }
    }
}

/**
 * Offline queue keyed by Host + session_key: a message only ever goes back to
 * the session it was typed in. Loading from disk merges with what is already
 * in memory (nothing typed before the load finishes is lost). Text only:
 * attachments are never queued.
 */
class OfflineQueue(private val storage: QueueStorage, val maxSize: Int = 50) {
    private val mutex = Mutex()
    private val _items = MutableStateFlow<List<QueuedMessage>>(emptyList())
    val items: StateFlow<List<QueuedMessage>> = _items.asStateFlow()
    @Volatile private var loaded = false

    suspend fun load() = mutex.withLock { loadLocked() }

    /** Every mutation merges the stored queue first, so a write never drops entries on disk. */
    private fun loadLocked() {
        if (loaded) return
        val merged = (storage.read() + _items.value).distinctBy { it.msgId }.sortedBy { it.queuedAt }
        _items.value = merged
        loaded = true
    }

    /** Returns false when the queue is full. */
    suspend fun enqueue(message: QueuedMessage): Boolean = mutex.withLock {
        if (message.content.isBlank()) return@withLock false
        loadLocked()
        if (_items.value.any { it.msgId == message.msgId }) return@withLock true
        if (_items.value.size >= maxSize) return@withLock false
        _items.value = _items.value + message
        storage.write(_items.value)
        true
    }

    fun pending(hostId: String, sessionKey: String): List<QueuedMessage> =
        _items.value.filter { it.hostId == hostId && it.sessionKey == sessionKey }

    suspend fun remove(msgId: String) = mutex.withLock {
        loadLocked()
        val next = _items.value.filterNot { it.msgId == msgId }
        if (next.size != _items.value.size) {
            _items.value = next
            storage.write(next)
        }
    }

    /**
     * Sends this session's queued messages in order through [send]; stops at
     * the first failure so ordering is kept. Returns the ids that went out.
     */
    suspend fun flush(hostId: String, sessionKey: String, send: suspend (QueuedMessage) -> Boolean): List<String> {
        val sent = mutableListOf<String>()
        for (message in pending(hostId, sessionKey)) {
            if (!send(message)) break
            remove(message.msgId)
            sent += message.msgId
        }
        return sent
    }

    suspend fun clearHost(hostId: String) = mutex.withLock {
        loadLocked()
        _items.value = _items.value.filterNot { it.hostId == hostId }
        storage.write(_items.value)
    }
}
