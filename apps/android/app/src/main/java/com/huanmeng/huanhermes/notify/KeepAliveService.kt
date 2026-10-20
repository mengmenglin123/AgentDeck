package com.huanmeng.huanhermes.notify

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.huanmeng.huanhermes.HuanHermesApp
import com.huanmeng.huanhermes.MainActivity
import com.huanmeng.huanhermes.R
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Optional "保持连接": a foreground service that checks every Host for
 * approvals every 30 s while the app is closed. For phones without a push
 * distributor; costs battery, so it is off by default.
 */
class KeepAliveService : Service() {
    private var loop: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            val app = application as HuanHermesApp
            app.graph.scope.launch { app.settings.update { it.copy(keepAlive = false) } }
            stopSelf()
            return START_NOT_STICKY
        }
        val ok = runCatching {
            ServiceCompat.startForeground(
                this, NOTIFICATION_ID, notification(),
                if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING else 0,
            )
        }.isSuccess
        if (!ok) { stopSelf(); return START_NOT_STICKY }
        if (loop == null) {
            val graph = (application as HuanHermesApp).graph
            loop = graph.scope.launch {
                while (isActive) {
                    if (!graph.inForeground) runCatching { graph.checkInboxAndNotify() }
                    delay(30_000)
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        loop?.cancel()
        loop = null
        super.onDestroy()
    }

    private fun notification(): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java)?.let { nm ->
                if (nm.getNotificationChannel(CHANNEL) == null) {
                    nm.createNotificationChannel(NotificationChannel(CHANNEL, "保持连接", NotificationManager.IMPORTANCE_MIN).apply {
                        description = "后台检查待批准操作时显示"
                        setShowBadge(false)
                    })
                }
            }
        }
        val open = PendingIntent.getActivity(this, 2, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 3, Intent(this, KeepAliveService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle("AgentDeck 保持连接中")
            .setContentText("有需要你批准的操作会立即通知")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(open)
            .addAction(0, "停止", stop)
            .build()
    }

    companion object {
        private const val CHANNEL = "keepalive"
        private const val NOTIFICATION_ID = 7
        private const val ACTION_STOP = "com.huanmeng.huanhermes.KEEPALIVE_STOP"

        fun set(context: Context, on: Boolean) = runCatching {
            val i = Intent(context, KeepAliveService::class.java)
            if (on) ContextCompat.startForegroundService(context, i) else context.stopService(i)
        }
    }
}
