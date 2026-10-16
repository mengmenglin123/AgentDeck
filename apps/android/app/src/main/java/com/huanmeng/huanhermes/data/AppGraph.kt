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

    /** Sessions the list showed, so a chat route only needs the id. */
    val sessionRefs = ConcurrentHashMap<String, SessionRef>()

    @Volatile private var runtime: HostRuntime? = null

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
