package com.huanmeng.huanhermes.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.huanmeng.huanhermes.core.agent.ConversationRepository
import com.huanmeng.huanhermes.core.agent.ConversationStorage
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
data class LocalAgentSettings(
    /** Active model, derived from [providers] + selection (kept for 0.6/0.7 data). */
    val llm: LlmSettings = LlmSettings(),
    val policy: ApprovalPolicy = ApprovalPolicy.SAFE_AUTO,
    val providers: List<com.huanmeng.huanhermes.core.agent.ProviderConfig> = emptyList(),
    val selectedProvider: String? = null,
    val selectedModel: String? = null,
    /** Phone-side tools offered to the model. */
    val webTools: Boolean = true,
    val jsTool: Boolean = true,
    /** Built-in skill pack id (SkillPacks), or null for the plain agent. */
    val skillId: String? = null,
) {
    val choice get() = com.huanmeng.huanhermes.core.agent.resolveModel(providers, selectedProvider, selectedModel)

    /** Recomputes [llm] from the provider list. */
    fun normalized(): LocalAgentSettings {
        val c = choice ?: return copy(llm = LlmSettings())
        return copy(llm = c.provider.settings(c.model), selectedProvider = c.provider.id, selectedModel = c.model)
    }

    /** 0.6/0.7 stored a single model: turn it into the first provider. */
    fun migrated(): LocalAgentSettings {
        if (providers.isNotEmpty() || !llm.configured) return this
        val name = runCatching { java.net.URI(llm.effectiveBaseUrl).host }.getOrNull()?.removePrefix("api.") ?: llm.provider.name
        val p = com.huanmeng.huanhermes.core.agent.ProviderConfig(name = name, type = llm.provider, baseUrl = llm.baseUrl, apiKey = llm.apiKey, models = listOf(llm.effectiveModel))
        return copy(providers = listOf(p), selectedProvider = p.id, selectedModel = llm.effectiveModel).normalized()
    }
}

/**
 * Phone-side agent: saved SSH servers (passwords/keys encrypted), model
 * settings (API key encrypted), and the running conversation. The run lives on
 * the app scope so leaving the screen does not stop it.
 */
class LocalAgentController(context: Context, private val scope: CoroutineScope) {
    private val secure = SecurePrefs(context, "huanhermes_local_agent")
    private val legacyHistory = File(context.filesDir, "local_agent_chat_v1.json")
    private val dir = File(context.filesDir, "local_agent").apply { mkdirs() }

    private fun atomicWrite(f: File, raw: String) { val tmp = File(f.path + ".tmp"); tmp.writeText(raw); tmp.renameTo(f) }
    private fun safe(id: String) = id.filter { it.isLetterOrDigit() || it == '-' }.take(64)

    val conversations = ConversationRepository(object : ConversationStorage {
        override suspend fun readIndex(): String? = withContext(Dispatchers.IO) { runCatching { File(dir, "index.json").readText() }.getOrNull() }
        override suspend fun writeIndex(raw: String) = withContext(Dispatchers.IO) { runCatching { atomicWrite(File(dir, "index.json"), raw) }; Unit }
        override suspend fun read(id: String): String? = withContext(Dispatchers.IO) { runCatching { File(dir, safe(id) + ".json").readText() }.getOrNull() }
        override suspend fun write(id: String, raw: String) = withContext(Dispatchers.IO) { runCatching { atomicWrite(File(dir, safe(id) + ".json"), raw) }; Unit }
        override suspend fun delete(id: String) = withContext(Dispatchers.IO) { File(dir, safe(id) + ".json").delete(); Unit }
    })

    val servers = SshServerRepository(object : SshServerStorage {
        override suspend fun load() = secure.read("servers_v1")
        override suspend fun save(raw: String) = secure.write("servers_v1", raw)
    })

    private val _settings = MutableStateFlow(LocalAgentSettings())
    val settings: StateFlow<LocalAgentSettings> = _settings

    private val http = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(180, TimeUnit.SECONDS).build()
    private val webHttp = http.newBuilder().readTimeout(30, TimeUnit.SECONDS).followRedirects(true).build()

    val agent = LocalAgent(servers, conversations = conversations, phoneTools = {
        val s = _settings.value
        com.huanmeng.huanhermes.core.agent.PhoneTools.defaults(webHttp, web = s.webTools, js = s.jsTool)
    })

    /** Reads picked files into attachments (documents → text, pictures → downscaled JPEG). */
    val attachments = AttachmentReader(context.applicationContext)
    private var job: Job? = null
    private var loaded: Job? = null

    fun ensureLoaded() {
        if (loaded != null) return
        loaded = scope.launch {
            servers.load()
            secure.read("settings_v1")?.let { raw -> runCatching { ProtocolJson.decodeFromString(LocalAgentSettings.serializer(), raw) }.getOrNull() }?.let { _settings.value = it.migrated() }
            migrateLegacy()
            agent.restore()
        }
    }

    fun saveSettings(raw: LocalAgentSettings) {
        val s = raw.normalized()
        _settings.value = s
        scope.launch { secure.write("settings_v1", ProtocolJson.encodeToString(LocalAgentSettings.serializer(), s)) }
    }

    fun selectModel(providerId: String, model: String) = saveSettings(_settings.value.copy(selectedProvider = providerId, selectedModel = model))

    fun upsertProvider(p: com.huanmeng.huanhermes.core.agent.ProviderConfig) {
        val cur = _settings.value
        val list = if (cur.providers.any { it.id == p.id }) cur.providers.map { if (it.id == p.id) p else it } else cur.providers + p
        saveSettings(cur.copy(providers = list))
    }

    fun removeProvider(id: String) { val cur = _settings.value; saveSettings(cur.copy(providers = cur.providers.filterNot { it.id == id })) }

    suspend fun fetchModels(p: com.huanmeng.huanhermes.core.agent.ProviderConfig): List<String> = com.huanmeng.huanhermes.core.agent.fetchModels(p, http)

    fun send(text: String, files: List<com.huanmeng.huanhermes.core.agent.AgentAttachment> = emptyList()) {
        if (job?.isActive == true) return
        val s = _settings.value
        agent.skill = com.huanmeng.huanhermes.core.agent.SkillPacks.find(s.skillId)
        job = scope.launch { loaded?.join(); agent.send(text, llmClientFor(s.llm, http), s.policy, files) }
    }

    fun selectSkill(id: String?) = saveSettings(_settings.value.copy(skillId = id))

    fun stop() { job?.cancel() }

    fun newConversation() { if (job?.isActive != true) agent.newConversation() }

    fun open(id: String) { if (job?.isActive != true) scope.launch { agent.open(id) } }

    fun delete(id: String) { scope.launch { agent.deleteConversation(id) } }

    fun rename(id: String, title: String) { scope.launch { conversations.rename(id, title) } }

    /** 0.6.0 kept one chat in a single file: import it as the first conversation. */
    private suspend fun migrateLegacy() {
        val raw = withContext(Dispatchers.IO) { runCatching { legacyHistory.readText() }.getOrNull() } ?: return
        runCatching {
            val msgs = ProtocolJson.decodeFromString(kotlinx.serialization.builtins.ListSerializer(com.huanmeng.huanhermes.core.agent.AgentMessage.serializer()), raw)
            if (msgs.isNotEmpty()) conversations.save(conversations.newId(), msgs)
        }
        withContext(Dispatchers.IO) { legacyHistory.delete() }
    }
}
