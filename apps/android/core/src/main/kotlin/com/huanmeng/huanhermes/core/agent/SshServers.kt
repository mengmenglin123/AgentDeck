package com.huanmeng.huanhermes.core.agent

import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import com.huanmeng.huanhermes.core.ssh.SshException
import com.huanmeng.huanhermes.core.ssh.SshRunner
import com.huanmeng.huanhermes.core.ssh.SshTarget
import com.huanmeng.huanhermes.core.ssh.TrileadSshRunner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.util.UUID

/**
 * An SSH server the user saved on this phone. Secrets live only in the app's
 * encrypted storage; [hostKey] is the `SHA256:` fingerprint confirmed by the
 * user on the first "test connection" (trust on first use).
 */
@Serializable
data class SshServer(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val host: String,
    val port: Int = 22,
    val username: String,
    val password: String = "",
    val privateKey: String = "",
    val passphrase: String = "",
    val hostKey: String = "",
    val note: String = "",
) {
    val usesKey: Boolean get() = privateKey.isNotBlank()
    fun target() = SshTarget(host.trim(), port, username.trim(), password.ifEmpty { null }, privateKey.ifBlank { null }, passphrase.ifEmpty { null })
    fun label() = "$username@$host" + if (port != 22) ":$port" else ""

    companion object {
        private val nameRe = Regex("^[\\p{L}\\p{N}_.\\- ]{1,40}$")
        fun validate(s: SshServer): String? = when {
            !nameRe.matches(s.name.trim()) -> "名称需为 1–40 个字符（字母、数字、空格、- _ .）"
            s.host.isBlank() || s.host.any { it.isWhitespace() } -> "请输入有效的主机地址"
            s.port !in 1..65535 -> "端口需在 1–65535"
            s.username.isBlank() -> "请输入用户名"
            s.password.isEmpty() && s.privateKey.isBlank() -> "请输入密码或私钥"
            else -> null
        }
    }
}

interface SshServerStorage {
    suspend fun load(): String?
    suspend fun save(raw: String)
}

/** Saved SSH servers, observable; names are unique (case-insensitive) so the agent can address them. */
class SshServerRepository(private val storage: SshServerStorage) {
    private val _servers = MutableStateFlow<List<SshServer>>(emptyList())
    val servers: StateFlow<List<SshServer>> = _servers
    private val lock = Mutex()
    @Volatile private var loaded = false

    private val ser = ListSerializer(SshServer.serializer())

    suspend fun load(): List<SshServer> = lock.withLock {
        if (!loaded) {
            _servers.value = storage.load()?.let { runCatching { ProtocolJson.decodeFromString(ser, it) }.getOrNull() } ?: emptyList()
            loaded = true
        }
        _servers.value
    }

    /** Insert or replace by id. Returns an error message, or null on success. */
    suspend fun upsert(server: SshServer): String? {
        load()
        val s = server.copy(name = server.name.trim(), host = server.host.trim(), username = server.username.trim())
        SshServer.validate(s)?.let { return it }
        return lock.withLock {
            val list = _servers.value
            if (list.any { it.id != s.id && it.name.equals(s.name, ignoreCase = true) }) return@withLock "已有同名服务器"
            val old = list.firstOrNull { it.id == s.id }
            // A changed address means the stored fingerprint no longer applies.
            val keep = if (old != null && (old.host != s.host || old.port != s.port) && s.hostKey == old.hostKey) s.copy(hostKey = "") else s
            val next = if (old == null) list + keep else list.map { if (it.id == s.id) keep else it }
            storage.save(ProtocolJson.encodeToString(ser, next)); _servers.value = next
            null
        }
    }

    suspend fun remove(id: String) {
        load()
        lock.withLock {
            val next = _servers.value.filterNot { it.id == id }
            storage.save(ProtocolJson.encodeToString(ser, next)); _servers.value = next
        }
    }

    fun find(nameOrId: String): SshServer? = _servers.value.let { list ->
        list.firstOrNull { it.id == nameOrId } ?: list.firstOrNull { it.name.equals(nameOrId.trim(), ignoreCase = true) }
    }
}

/** Opens SSH sessions for the agent; refuses servers whose host key was never confirmed. */
fun interface SshConnector {
    fun open(server: SshServer): SshRunner

    companion object {
        val Trilead = SshConnector { s ->
            if (s.hostKey.isBlank()) throw SshException("服务器「${s.name}」还没确认主机指纹，请先在服务器列表里点「测试连接」")
            TrileadSshRunner(s.target(), { _, fp -> fp == s.hostKey })
        }
    }
}
