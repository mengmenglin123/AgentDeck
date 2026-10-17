package com.huanmeng.huanhermes.notify

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.huanmeng.huanhermes.MainActivity
import com.huanmeng.huanhermes.R
import com.huanmeng.huanhermes.core.overview.InboxItem

/**
 * "需要我" notifications with 允许 / 拒绝 actions. Every call is guarded: a
 * notification failure must never take the app down (the 0.1.204 lesson).
 */
object ApprovalNotifications {
    const val CHANNEL = "approvals"
    const val EXTRA_OPEN_TAB = "open_tab"
    private const val GROUP = "huanhermes.approvals"
    private const val SUMMARY_ID = 1

    fun id(item: InboxItem): Int = item.key.hashCode().let { if (it == SUMMARY_ID) it + 1 else it }

    fun canPost(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            NotificationManagerCompat.from(context).areNotificationsEnabled()

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "待批准操作", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Agent 需要你允许或拒绝的操作"
            },
        )
    }

    fun post(context: Context, item: InboxItem) = runCatching {
        if (!canPost(context)) return@runCatching
        ensureChannel(context)
        val nid = id(item)
        val open = PendingIntent.getActivity(
            context, nid,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_OPEN_TAB, "inbox"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle("${item.session.displayTitle} 需要你批准")
            .setContentText(item.permission.prompt.ifBlank { "Agent 请求权限" })
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.permission.prompt.ifBlank { "Agent 请求权限" }))
            .setSubText(item.hostName)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setGroup(GROUP)
            .setContentIntent(open)
        val data = item.permission.buttons.map { it.data }
        fun has(suffix: String) = data.any { it.endsWith(":$suffix") || it == suffix } || data.isEmpty() && suffix != "allow_all"
        if (has("allow")) builder.addAction(0, "允许本次", ApprovalReceiver.intent(context, item, "allow", nid))
        if (has("deny")) builder.addAction(0, "拒绝", ApprovalReceiver.intent(context, item, "deny", nid))
        NotificationManagerCompat.from(context).notify(nid, builder.build())
    }

    fun cancel(context: Context, key: String) = runCatching {
        NotificationManagerCompat.from(context).cancel(key.hashCode().let { if (it == SUMMARY_ID) it + 1 else it })
    }

    /** Replaces the action buttons with a short result line. */
    fun showResult(context: Context, nid: Int, title: String, text: String) = runCatching {
        if (!canPost(context)) return@runCatching
        ensureChannel(context)
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setTimeoutAfter(8_000)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(nid, n)
    }
}
