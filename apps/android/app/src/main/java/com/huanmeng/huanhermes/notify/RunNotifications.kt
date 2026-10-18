package com.huanmeng.huanhermes.notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.huanmeng.huanhermes.MainActivity
import com.huanmeng.huanhermes.R

/**
 * Long-run progress ("Agent 正在运行", promoted to a Live Update on Android 16+),
 * the finished note, and the "messages not sent" watchdog. All calls are guarded.
 */
object RunNotifications {
    private const val RUNS = "runs"
    const val RUNS_CHANNEL = RUNS
    private const val UNSENT = "unsent"
    const val UNSENT_ID = 42_001
    /** Android 16 `Notification.EXTRA_REQUEST_PROMOTED_ONGOING`. */
    private const val EXTRA_PROMOTED = "android.requestPromotedOngoing"

    fun runId(sessionId: String) = ("run:$sessionId").hashCode()

    fun ensure(context: Context) = channels(context)

    private fun channels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(RUNS) == null) nm.createNotificationChannel(
            NotificationChannel(RUNS, "运行中的任务", NotificationManager.IMPORTANCE_LOW).apply { description = "离开 App 时仍在运行的 Agent 任务" },
        )
        if (nm.getNotificationChannel(UNSENT) == null) nm.createNotificationChannel(
            NotificationChannel(UNSENT, "未发送的消息", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "离线排队、迟迟没有发出的消息" },
        )
    }

    private fun open(context: Context, req: Int, tab: String? = null) = PendingIntent.getActivity(
        context, req,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .apply { if (tab != null) putExtra(ApprovalNotifications.EXTRA_OPEN_TAB, tab) },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun ongoing(context: Context, sessionId: String, title: String, detail: String) = runCatching {
        if (!ApprovalNotifications.canPost(context)) return@runCatching
        channels(context)
        val id = runId(sessionId)
        val n = NotificationCompat.Builder(context, RUNS)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle("$title · 运行中")
            .setContentText(detail)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(open(context, id))
            .addExtras(android.os.Bundle().apply { putBoolean(EXTRA_PROMOTED, true) })
            .build()
        NotificationManagerCompat.from(context).notify(id, n)
    }

    fun finished(context: Context, sessionId: String, title: String, status: String) = runCatching {
        val id = runId(sessionId)
        NotificationManagerCompat.from(context).cancel(id)
        if (!ApprovalNotifications.canPost(context)) return@runCatching
        channels(context)
        val label = when (status) { "completed" -> "已完成"; "cancelled" -> "已取消"; "failed", "error" -> "失败"; else -> status }
        val n = NotificationCompat.Builder(context, RUNS)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle("$title · $label")
            .setContentText("点按查看结果")
            .setAutoCancel(true)
            .setContentIntent(open(context, id))
            .build()
        NotificationManagerCompat.from(context).notify(id, n)
    }

    fun cancelRun(context: Context, sessionId: String) = runCatching { NotificationManagerCompat.from(context).cancel(runId(sessionId)) }

    fun unsent(context: Context, count: Int) = runCatching {
        if (count <= 0 || !ApprovalNotifications.canPost(context)) return@runCatching
        channels(context)
        val n = NotificationCompat.Builder(context, UNSENT)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle("$count 条消息还没发出")
            .setContentText("Host 连不上，回到 App 会自动重试")
            .setAutoCancel(true)
            .setContentIntent(open(context, UNSENT_ID))
            .build()
        NotificationManagerCompat.from(context).notify(UNSENT_ID, n)
    }

    fun cancelUnsent(context: Context) = runCatching { NotificationManagerCompat.from(context).cancel(UNSENT_ID) }
}
