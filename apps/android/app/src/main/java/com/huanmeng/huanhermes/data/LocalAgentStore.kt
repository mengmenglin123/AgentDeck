package com.huanmeng.huanhermes.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.huanmeng.huanhermes.core.agent.AgentHistoryStorage
import com.huanmeng.huanhermes.core.agent.ApprovalPolicy
import com.huanmeng.huanhermes.core.agent.LlmSettings
import com.huanmeng.huanhermes.core.agent.LocalAgent
import com.huanmeng.huanhermes.core.agent.SshServerRepository
import com.huanmeng.huanhermes.core.agent.SshServerStorage
import com.huanmeng.huanhermes.core.agent.llmClientFor
import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit

/** Encrypted prefs that wipe themselves if the Keystore key is gone (same rule as Host profiles). */
internal class SecurePrefs(private val context: Context, private val file: String) {
    @Volatile private var prefs: SharedPreferences? = null

    fun get(): SharedPreferences {
        prefs?.let { return it }
        val app = context.applicationContext
        val created = try { create(app) } catch (e: Exception) {
            app.deleteSharedPreferences(file)
            runCatching { create(app) }.getOrElse { app.getSharedPreferences("$file-volatile", Context.MODE_PRIVATE).also { p -> p.edit().clear().apply() } }
        }
        prefs = created
        return created
    }

    private fun create(app: Context): SharedPreferences {
        val key = MasterKey.Builder(app).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        return EncryptedSharedPreferences.create(app, file, key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
    }

    suspend fun read(key: String): String? = withContext(Dispatchers.IO) { runCatching { get().getString(key, null) }.getOrNull() }
    suspend fun write(key: String, value: String) = withContext(Dispatchers.IO) { runCatching { get().edit().putString(key, value).commit() }; Unit }
}

@Serializable
data class LocalAgentSettings(val llm: LlmSettings = LlmSettings(), val policy: ApprovalPolicy = ApprovalPolicy.SAFE_AUTO)

/**
 * Phone-side agent: saved SSH servers (passwords/keys encrypted), model
 * settings (API key encrypted), and the running conversation. The run lives on
 * the app scope so leaving the screen does not stop it.
 */
class LocalAgentController(context: Context, private val scope: CoroutineScope) {
    private val secure = SecurePrefs(context, "huanhermes_local_agent")
    private val historyFile = File(context.filesDir, "local_agent_chat_v1.json")

    val servers = SshServerRepository(object : SshServerStorage {
        override suspend fun load() = secure.read("servers_v1")
        override suspend fun save(raw: String) = secure.write("servers_v1", raw)
    })

    val agent = LocalAgent(servers, history = object : AgentHistoryStorage {
        override suspend fun load(): String? = withContext(Dispatchers.IO) { runCatching { historyFile.readText() }.getOrNull() }
        override suspend fun save(raw: String) = withContext(Dispatchers.IO) {
            runCatching { val tmp = File(historyFile.path + ".tmp"); tmp.writeText(raw); tmp.renameTo(historyFile) }; Unit
        }
    })

    private val _settings = MutableStateFlow(LocalAgentSettings())
    val settings: StateFlow<LocalAgentSettings> = _settings

    private val http = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(180, TimeUnit.SECONDS).build()
    private var job: Job? = null
    private var loaded: Job? = null

    fun ensureLoaded() {
        if (loaded != null) return
        loaded = scope.launch {
            servers.load()
            secure.read("settings_v1")?.let { raw -> runCatching { ProtocolJson.decodeFromString(LocalAgentSettings.serializer(), raw) }.getOrNull() }?.let { _settings.value = it }
            agent.restore()
        }
    }

    fun saveSettings(s: LocalAgentSettings) {
        _settings.value = s
        scope.launch { secure.write("settings_v1", ProtocolJson.encodeToString(LocalAgentSettings.serializer(), s)) }
    }

    fun send(text: String) {
        if (job?.isActive == true) return
        val s = _settings.value
        job = scope.launch { loaded?.join(); agent.send(text, llmClientFor(s.llm, http), s.policy) }
    }

    fun stop() { job?.cancel() }

    fun clear() { stop(); scope.launch { agent.clear() } }
}
