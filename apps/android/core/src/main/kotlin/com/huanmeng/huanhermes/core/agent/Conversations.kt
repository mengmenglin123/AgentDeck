package com.huanmeng.huanhermes.core.agent

import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.util.UUID

@Serializable
data class ConversationMeta(val id: String, val title: String, val updatedAt: Long, val messages: Int = 0)

/** Raw storage: one blob per conversation plus a small index. */
interface ConversationStorage {
    suspend fun readIndex(): String?
    suspend fun writeIndex(raw: String)
    suspend fun read(id: String): String?
    suspend fun write(id: String, raw: String)
    suspend fun delete(id: String)
}

/** Local agent conversations, newest first. */
class ConversationRepository(private val storage: ConversationStorage, private val now: () -> Long = System::currentTimeMillis) {
    private val _list = MutableStateFlow<List<ConversationMeta>>(emptyList())
    val list: StateFlow<List<ConversationMeta>> = _list
    private val lock = Mutex()
    @Volatile private var loaded = false
    private val idx = ListSerializer(ConversationMeta.serializer())
    private val msgs = ListSerializer(AgentMessage.serializer())

    suspend fun load(): List<ConversationMeta> = lock.withLock {
        if (!loaded) {
            _list.value = storage.readIndex()?.let { runCatching { ProtocolJson.decodeFromString(idx, it) }.getOrNull() }.orEmpty().sortedByDescending { it.updatedAt }
            loaded = true
        }
        _list.value
    }

    fun newId(): String = UUID.randomUUID().toString()

    suspend fun messages(id: String): List<AgentMessage> =
        storage.read(id)?.let { runCatching { ProtocolJson.decodeFromString(msgs, it) }.getOrNull() }.orEmpty()

    suspend fun save(id: String, messages: List<AgentMessage>) {
        load()
        if (messages.isEmpty()) return
        storage.write(id, ProtocolJson.encodeToString(msgs, messages))
        lock.withLock {
            val old = _list.value.firstOrNull { it.id == id }
            val title = old?.title?.takeIf { it.isNotBlank() } ?: titleFor(messages)
            val meta = ConversationMeta(id, title, now(), messages.size)
            _list.value = (listOf(meta) + _list.value.filterNot { it.id == id }).sortedByDescending { it.updatedAt }
            storage.writeIndex(ProtocolJson.encodeToString(idx, _list.value))
        }
    }

    suspend fun rename(id: String, title: String) {
        load()
        lock.withLock {
            _list.value = _list.value.map { if (it.id == id) it.copy(title = title.trim().take(60).ifEmpty { it.title }) else it }
            storage.writeIndex(ProtocolJson.encodeToString(idx, _list.value))
        }
    }

    suspend fun delete(id: String) {
        load()
        storage.delete(id)
        lock.withLock {
            _list.value = _list.value.filterNot { it.id == id }
            storage.writeIndex(ProtocolJson.encodeToString(idx, _list.value))
        }
    }

    companion object {
        fun titleFor(messages: List<AgentMessage>): String =
            messages.filterIsInstance<AgentMessage.User>().firstOrNull()?.text?.lineSequence()?.firstOrNull()?.trim()?.take(30)?.ifEmpty { null } ?: "新对话"
    }
}
