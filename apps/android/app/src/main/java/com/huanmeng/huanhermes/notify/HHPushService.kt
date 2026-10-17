package com.huanmeng.huanhermes.notify

import com.huanmeng.huanhermes.HuanHermesApp
import kotlinx.coroutines.launch
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.PushService
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage

/**
 * UnifiedPush (ntfy, NextPush, …) wake-ups. A message carries only a
 * reference; the details are fetched over the authenticated Management API.
 */
class HHPushService : PushService() {
    private val app get() = application as HuanHermesApp

    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) {
        app.graph.scope.launch {
            app.settings.update { it.copy(pushEndpoint = endpoint.url) }
            app.graph.syncPush(endpoint.url)
        }
    }

    override fun onMessage(message: PushMessage, instance: String) {
        app.graph.scope.launch { runCatching { app.graph.checkInboxAndNotify() } }
    }

    override fun onRegistrationFailed(reason: FailedReason, instance: String) {
        app.graph.scope.launch { app.settings.update { it.copy(pushEndpoint = null) } }
    }

    override fun onUnregistered(instance: String) {
        app.graph.scope.launch {
            app.settings.update { it.copy(pushEndpoint = null) }
            app.graph.syncPush(null)
        }
    }
}
