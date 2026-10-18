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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import com.huanmeng.huanhermes.core.bridge.BridgeState
import com.huanmeng.huanhermes.core.protocol.Outbound
import com.huanmeng.huanhermes.notify.ApprovalNotifications
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

    /** Per-Host HTTP: pinned TLS when the profile carries a certificate pin. */
    fun engineFor(cfg: com.huanmeng.huanhermes.core.net.HostConfig): com.huanmeng.huanhermes.core.mgmt.HttpEngine =
        if (cfg.useTls && cfg.certPin.isNotBlank()) OkHttpEngine(com.huanmeng.huanhermes.core.net.Pinning.clientFor(http, cfg)) else engine

    private fun wsFor(cfg: com.huanmeng.huanhermes.core.net.HostConfig): OkHttpClient =
        com.huanmeng.huanhermes.core.net.Pinning.clientFor(wsHttp, cfg)

    /** A link scanned from a QR code, waiting for the Hosts screen to pair it. */
    val pendingPairing = MutableStateFlow<String?>(null)

    val profiles: ProfileManager by lazy {
        ProfileManager(SecureProfileStorage(context), { cfg -> MgmtClient(cfg, engineFor(cfg)) })
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
            val client = if (rt != null && rt.profile == profile) rt.mgmt else MgmtClient(profile.config, engineFor(profile.config))
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
    /** Text handed to a chat before it opens (diff review, system share); consumed once by its composer. */
    val pendingDrafts = ConcurrentHashMap<String, String>()

    @Volatile private var runtime: HostRuntime? = null

    /** The live runtime, if any (diagnostics, inbox approvals). */
    val currentRuntime: HostRuntime? get() = runtime

    // --- foreground / notifications -------------------------------------

    @Volatile var inForeground = false
        private set
    /** Same as [inForeground], observable (run notifications, app lock). */
    val foreground = MutableStateFlow(false)
    /** When the app last went to the background (app lock grace period). */
    @Volatile var backgroundAt: Long = 0L
        private set
    /** App lock: unlocked for this foreground stretch. */
    val unlocked = MutableStateFlow(false)
    val appContext: Context get() = context
    @Volatile private var unsentWatch: Job? = null
    @Volatile private var notificationsEnabled = true
    private val notified: MutableSet<String> = ConcurrentHashMap.newKeySet()
    @Volatile private var backgroundPoll: Job? = null
    @Volatile private var notifierStarted = false

    /** A tab the UI should switch to (set by a notification tap). */
    val openTabRequests = MutableStateFlow<String?>(null)

    /** App came to the foreground: don't sit out a long backoff wait. */
    fun onForeground() {
        inForeground = true
        foreground.value = true
        if (backgroundAt > 0 && System.currentTimeMillis() - backgroundAt > LOCK_GRACE_MS) unlocked.value = false
        unsentWatch?.cancel()
        com.huanmeng.huanhermes.notify.RunNotifications.cancelUnsent(context)
        backgroundPoll?.cancel()
        val rt = runtime ?: return
        if (!rt.bridge.isConnected) rt.bridge.reconnectNow()
    }

    /** For a few minutes after leaving the app, check for approvals often; WorkManager covers the rest. */
    fun onBackground() {
        inForeground = false
        foreground.value = false
        backgroundAt = System.currentTimeMillis()
        // Watchdog: messages still queued 30 s after leaving the app get a notification.
        unsentWatch?.cancel()
        unsentWatch = scope.launch {
            delay(30_000)
            val n = offlineQueue.items.value.size
            if (!inForeground && n > 0) com.huanmeng.huanhermes.notify.RunNotifications.unsent(context, n)
        }
        backgroundPoll?.cancel()
        backgroundPoll = scope.launch {
            repeat(12) {
                delay(45_000)
                runCatching { checkInboxAndNotify() }
            }
        }
    }

    /** Called once after the first frame (never at process start). */
    fun startNotifier(enabled: kotlinx.coroutines.flow.Flow<Boolean>) {
        if (notifierStarted) return
        notifierStarted = true
        scope.launch { enabled.collect { notificationsEnabled = it } }
        scope.launch { inbox.state.collect { reconcile(it) } }
    }

    /** Tell every Host (with `push`) where to wake this device; null unregisters. */
    suspend fun syncPush(endpoint: String?) {
        if (!profiles.state.value.loaded) profiles.load()
        for (p in profiles.state.value.profiles) {
            runCatching {
                val mgmt = MgmtClient(p.config, engineFor(p.config))
                if (endpoint != null) mgmt.registerPush(p.config.deviceId, endpoint) else mgmt.unregisterPush(p.config.deviceId)
            }
        }
    }

    suspend fun checkInboxAndNotify() {
        if (!profiles.state.value.loaded) profiles.load()
        val list = profiles.state.value.profiles
        if (list.isEmpty()) return
        inbox.refresh(list)
        reconcile(inbox.state.value)
    }

    private fun reconcile(st: com.huanmeng.huanhermes.core.overview.InboxState) {
        if (st.loading) return
        val live = st.visible.associateBy { it.key }
        for (key in notified.toList()) if (key !in live) {
            notified.remove(key)
            ApprovalNotifications.cancel(context, key)
        }
        for ((key, item) in live) {
            if (!notified.add(key)) continue
            // In the app the badge is enough; only new items while away become notifications.
            if (!inForeground && notificationsEnabled) ApprovalNotifications.post(context, item)
        }
    }

    /**
     * Sends a permission decision to the Host that asked. The active Host uses
     * its live Bridge; any other Host gets a short-lived connection (its
     * detached session is claimable), so approving never switches Host.
     */
    suspend fun sendDecision(hostId: String, sessionKey: String, project: String?, replyCtx: String?, action: String): Boolean {
        if (!profiles.state.value.loaded) profiles.load()
        val profile = profiles.state.value.profiles.firstOrNull { it.id == hostId } ?: return false
        val frame = Outbound.cardAction(sessionKey, action, replyCtx, project)
        val rt = runtime
        if (rt != null && rt.profile.id == hostId) {
            rt.bridge.start()
            val up = withTimeoutOrNull(12_000) { rt.bridge.state.first { it is BridgeState.Connected } } != null
            return up && rt.bridge.send(frame)
        }
        val temp = BridgeClient(profile.config, OkHttpWsTransport(wsFor(profile.config)), scope, appVersion = BuildConfig.VERSION_NAME)
        return try {
            temp.start()
            val up = withTimeoutOrNull(12_000) { temp.state.first { it is BridgeState.Connected } } != null
            val sent = up && temp.send(frame)
            if (sent) delay(1_500) // let the frame flush before closing
            sent
        } finally {
            temp.stop()
        }
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
            OkHttpWsTransport(wsFor(profile.config)),
            scope,
            appVersion = BuildConfig.VERSION_NAME,
        )
        return HostRuntime(profile, bridge, MgmtClient(profile.config, engineFor(profile.config))).also { runtime = it }
    }

    companion object {
        /** App lock re-arms after this long in the background. */
        const val LOCK_GRACE_MS = 60_000L
    }
}
