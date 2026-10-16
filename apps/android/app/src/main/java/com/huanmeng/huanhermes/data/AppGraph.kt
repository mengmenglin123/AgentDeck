package com.huanmeng.huanhermes.data

import android.content.Context
import com.huanmeng.huanhermes.BuildConfig
import com.huanmeng.huanhermes.core.bridge.BridgeClient
import com.huanmeng.huanhermes.core.bridge.OkHttpWsTransport
import com.huanmeng.huanhermes.core.chat.FileQueueStorage
import com.huanmeng.huanhermes.core.chat.OfflineQueue
import com.huanmeng.huanhermes.core.chat.SessionRef
import com.huanmeng.huanhermes.core.hosts.HostProfile
import com.huanmeng.huanhermes.core.hosts.ProfileManager
import com.huanmeng.huanhermes.core.mgmt.MgmtClient
import com.huanmeng.huanhermes.core.mgmt.OkHttpEngine
import com.huanmeng.huanhermes.core.overview.FilePrefsStorage
import com.huanmeng.huanhermes.core.overview.InboxModel
import com.huanmeng.huanhermes.core.overview.LocalSessionPrefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/** One live connection to the active Host profile. */
class HostRuntime(val profile: HostProfile, val bridge: BridgeClient, val mgmt: MgmtClient)

/**
 * App-wide singletons, created lazily (nothing here runs before the first frame).
 * Exactly one [HostRuntime] exists at a time: switching profile tears down the
 * old Bridge socket before the new one starts.
 */
class AppGraph(private val context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val http: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .build()
    }
    private val wsHttp: OkHttpClient by lazy { http.newBuilder().readTimeout(0, TimeUnit.MILLISECONDS).build() }
    private val engine by lazy { OkHttpEngine(http) }

    val profiles: ProfileManager by lazy {
        ProfileManager(SecureProfileStorage(context), { cfg -> MgmtClient(cfg, engine) })
    }

    val offlineQueue: OfflineQueue by lazy {
        OfflineQueue(FileQueueStorage(File(context.filesDir, "offline_queue_v2.json")))
    }

    /** Pinned / archived / last seen / drafts / input history, local to this device. */
    val localPrefs: LocalSessionPrefs by lazy {
        LocalSessionPrefs(FilePrefsStorage(File(context.filesDir, "session_prefs_v1.json")))
    }

    /** Cross-Host "需要我" list, read from each Host's Management `/sessions` overview. */
    val inbox: InboxModel by lazy {
        InboxModel({ profile ->
            val rt = runtime
            val client = if (rt != null && rt.profile == profile) rt.mgmt else MgmtClient(profile.config, engine)
            val caps = runCatching {
                (client.status()["capabilities"] as? kotlinx.serialization.json.JsonArray).orEmpty()
                    .mapNotNull { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
            }.getOrDefault(emptyList())
            client.sessions() to ("session_overview" in caps)
        })
    }

    /** First message typed in the session list's quick-start bar, sent once the chat opens. */
    val pendingFirstMessage = ConcurrentHashMap<String, String>()

    /** Sessions the list showed, so a chat route only needs the id. */
    val sessionRefs = ConcurrentHashMap<String, SessionRef>()

    @Volatile private var runtime: HostRuntime? = null

    /** The live runtime, if any (diagnostics, inbox approvals). */
    val currentRuntime: HostRuntime? get() = runtime

    /** App came to the foreground: don't sit out a long backoff wait. */
    fun onForeground() {
        val rt = runtime ?: return
        if (!rt.bridge.isConnected) rt.bridge.reconnectNow()
    }

    @Synchronized
    fun runtimeFor(profile: HostProfile?): HostRuntime? {
        val current = runtime
        if (profile == null) {
            current?.bridge?.stop()
            runtime = null
            return null
        }
        if (current != null && current.profile == profile) return current
        current?.bridge?.stop()
        val bridge = BridgeClient(
            profile.config,
            OkHttpWsTransport(wsHttp),
            scope,
            appVersion = BuildConfig.VERSION_NAME,
        )
        return HostRuntime(profile, bridge, MgmtClient(profile.config, engine)).also { runtime = it }
    }
}
